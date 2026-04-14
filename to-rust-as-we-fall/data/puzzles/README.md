# Puzzle Fragment Workflow

Puzzle fragments are small, reusable level beats that can be tested on their own before they get combined into a larger scene or survival route. The current fragment catalog lives in [showcase_fragments.json](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/showcase_fragments.json).

## Headless Commands

Run the whole fragment suite:

```powershell
& ..\godot.bat --headless --path . -- --test-puzzle-fragments
```

Run one fragment by id:

```powershell
& ..\godot.bat --headless --path . -- --test-puzzle-fragment hide_lane
```

Fragments also run inside:

```powershell
& ..\godot.bat --headless --path . -- --test-all
```

## Catalog Shape

Each catalog points at a scene plus a list of named fragments:

```json
{
	"scene": "res://scenes/showcase/showcase.tscn",
	"fragments": [
		{
			"id": "hide_lane",
			"kind": "puzzle",
			"scenarios": [
				{
					"id": "hidden_success",
					"script": [
						{"type": "select_character", "char_id": "endo"},
						{"type": "teleport", "char_id": "endo", "anchor": "hide_spot"},
						{"type": "call", "method": "activate_hide_lure"},
						{"type": "advance", "seconds": 6.2},
						{"type": "assert_path", "path": "hide_phase", "op": "==", "value": "run"}
					]
				}
			]
		}
	]
}
```

## Supported Script Actions

- `select_character`: switches active control. Requires `char_id`.
- `teleport`: moves a character instantly for headless setup. Requires `char_id` and either `anchor` or `position`.
- `advance`: steps the scheduler deterministically. Uses `seconds` and optional `step`.
- `call`: invokes a public scene helper method such as `activate_hide_lure`.
- `snapshot_state`: stores the current `headless_get_state()` dictionary under `key`.
- `assert_path`: compares a value in `headless_get_state()` against either a literal `value` or a prior snapshot.
- `refresh_anchors`: re-reads `headless_get_anchor_positions()` if a scene changes where probes should be.

## Scene Contract

Scenes that want to participate should expose these headless helpers:

- `headless_get_anchor_positions() -> Dictionary`
- `headless_get_state() -> Dictionary`
- `headless_advance(duration, step := 0.05) -> void`

Optional helpers make scripts easier to write:

- `headless_select_character(char_id)`
- `headless_set_character_position(char_id, pos)`
- scenario-specific methods such as `activate_showcase_ferrolure()`

## Authoring Pattern

1. Build the lane in a real scene using the same live systems the shipped level will use.
2. Add a few stable probe anchors for setup and verification.
3. Expose just enough state for assertions through `headless_get_state()`.
4. Write at least one success scenario and one representative failure scenario.
5. Keep fragments small. A full level can chain several fragment ids plus travel/shelter sections.
