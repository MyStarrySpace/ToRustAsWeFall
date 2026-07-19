# Node Authoring Audit

This ledger separates authored structure from runtime composition. The rule is:

- stable hierarchy, layout, copy, anchors, theme defaults, lights, cameras, and editor controls belong in `.tscn` files;
- variable membership still comes from data, but each repeated item is instantiated from a `PackedScene` template;
- topology, meshes, path ribbons, perception buffers, streamed chunks, and state-dependent effects stay runtime-driven when their shape or lifetime is the mechanic.

This keeps the scene tree inspectable without turning deterministic gameplay state into hidden editor state.

## Migrated In This Pass

The constructor counts are the pre-migration audit counts for stable UI nodes.

| Area | Before | Authored scene result |
| --- | ---: | --- |
| Fragment preview shell, inventory, overlay drawer, fragment menu, seed lab, branch modal | 51 | `fragment_preview_ui.tscn` plus fragment/branch/hint/toggle button templates |
| Game HUD | 33 | `game_hud.tscn` plus portrait, stat, pip, hand, ability, and control templates |
| Level editor HUD | 27 | `editor_hud.tscn`, instanced by `level_editor.tscn` |
| Engram journal | 22 | `engram_overlay.tscn` |
| Pause and settings | 22 | complete `pause_menu.tscn`, including fixed ability-binding slots |
| Level builder presentation | 10 | camera, light, environment, grid host, brush palette, actions, status, and help authored in `level_builder.tscn` |
| Act 1 and elevator perception controls | 15 | shared `perception_overlay.tscn` |
| Developer console | 5 | `dev_console.tscn` and `dev_console_touch_toggle.tscn` |
| Shared selection feedback | 4 | `selection_marquee_layer.tscn` and `rally_hold_layer.tscn` |
| Shared screen effects and sequence animation host | 4 | `screen_effect.tscn` and `sequence_animation_player.tscn` |
| Elevator bridge lighting | 3 | `elevator_bridge_lighting.tscn`, streamed as one authored lighting group |
| Elevator lower-route lighting | 5 | `elevator_lower_route_lighting.tscn`, replacing four weak generated lamps with route-wide authored pools |
| Elevator route guides | shared | Peris's safe edge reuses `PathRenderer` rather than generating a parallel solid-box path system |
| Elevator EMP feedback | 10 | `elevator_emp_effect.tscn` and reusable `elevator_emp_faceplate.tscn`; runtime only binds scene-owned nodes to the sequence animation |
| Showcase and Tag Day readouts | 4 | `showcase_info_overlay.tscn` and `tag_day_data_overlay.tscn` |
| Touch mode cluster | 4 | `touch_mode_controller.tscn` |
| Cursor verb and game-over presentation | 4 | `cursor_verb.tscn` and `game_over_overlay.tscn` |

Already authored immediately before this audit: main menu, dialogue box, tutorial prompt, and input glyph.

Production scripts now contain no direct construction of built-in UI node types. The syntax suite enforces that boundary so new UI structure must be added as a scene or reusable scene template.

## High-Generation World Scripts

These files were also audited because raw constructor counts are high. They should not receive a blind `.new()`-to-`PackedScene` rewrite: their remaining work falls into the categories below.

| Area | Node constructors | Classification | Next authoring boundary |
| --- | ---: | --- | --- |
| `act1_sequence.gd` | 112 | mixed fixed graybox and runtime interaction composition | move fixed room/scenery groups into child scenes; keep stateful interactable registration in script |
| `elevator_sequence.gd` | 90 | streamed bridge/elevator assembly and stateful encounter visuals | keep streamed bridge batches; move fixed elevator-car dressing and static collision anchors into authored chunk scenes |
| `leaving_facility_sequence.gd` | 35 | mostly fixed scenery | convert the environment and fixed set dressing into a child scene |
| `aster_sim_sequence.gd` | 32 | imported-room binding plus graybox fallback and stateful protocol props | keep fallback/runtime protocol visualization; author stable props against existing markers |
| `peris_sim_sequence.gd` | 31 | imported-room binding, portal viewport, and stateful care props | keep viewport/state effects; author stable room props against existing markers |
| `showcase_room.gd` | 29 | data-driven station construction | create one authored scene per station, with script responsible only for station data and wiring |
| `tag_day_sequence.gd` | 28 | mostly fixed checkpoint scenery | convert fixed checkpoint geometry and collision into a child scene |
| fragment chunk scripts | 5–27 each | loader/kit composition whose count and topology vary by fragment data | keep composition in scripts; promote repeated kit visuals to their owning object scenes rather than whole-chunk static nodes |

The elevator bridge, generated stretches, builder-painted meshes, path drawing, perception/outline render targets, procedural grid renderers, and enemy/state-machine instances remain runtime systems. Their node count, topology, visibility, or lifetime depends on current data or state, so moving them wholesale into a scene would make the editor representation misleading.

## Authoring Rules Going Forward

1. Do not call `BuiltInControlType.new()` in production scripts. Add a `.tscn` scene or item template.
2. A dynamic list may choose how many entries exist, but each entry must be a `PackedScene` instance.
3. Put default text, sizing, anchors, focus behavior, and base theme resources in the scene.
4. Scripts bind signals, populate data, and drive state; they do not recreate the stable hierarchy.
5. For world content, author stable geometry and collision first. Keep only topology-dependent or state-dependent construction in code.
6. Preserve causal feedback: path, hazard, damage, and overlay visuals must continue to reflect the live deterministic state rather than an editor-only duplicate.
