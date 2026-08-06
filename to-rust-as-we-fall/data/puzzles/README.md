# Puzzle Fragment Workflow

Puzzle fragments are small, reusable level beats that can be tested on their own before they get combined into a larger scene or survival route. The current fragment catalog lives in [showcase_fragments.json](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/showcase_fragments.json).

## Design Docs

- [Puzzle Fragment Generation Methodology](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/puzzle_fragment_generation_methodology.md): how to generate fragments from campaign role, cognitive target, pressure profile, and headless validation requirements
- [Puzzle Fragment Design Template](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/puzzle_fragment_design_template.md): copyable brief for new fragment authoring
- [Level Design Review Rubric](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/level_design_review_rubric.md): compact scoring rubric for reviewing fragments, scene chunks, and level slices
- [Survival Fragment Briefs](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/survival_fragments.md): showcase combat, attrition, and hide/run fragment briefs for the survival layer
- [Stacks Fragment Briefs](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/stacks_fragments.md): narrative-information fragment briefs for the The Open Files Initiative sequence
- [Act 1 Late Fragments](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/act1_late_fragments.md): Rings flora-memory and Lockout chase fragment briefs for the second half of Act 1
- [Mother Flure 6x6 Board Draft](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/mother_flure_board_layout.md): implementation-facing board layout, root list, and first-pass solve chain for the enlarged Mother chamber
- [Inflammashunt Puzzle Full Spec](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/inflammashunt_puzzle.md): canonical Resolution Catalyst danger-zone puzzle spec — IMPLEMENTED as `--preview=inflammashunt` (scripts/fragments/chunks/inflammashunt_chunk.gd; `--test-inflammashunt` runs the spec's ten required scenarios)
- [Inflammashunt Shadow Solution](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/inflammashunt_shadow_solution.md): Aster-Peris reconstruction path for the Inflammashunt
- [Teaching Beats Catalogue](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/teaching_beats_catalogue.md): shadow-solution techniques and their diegetic teaching beats

## Headless Commands

Set `GODOT_BIN` to the Godot 4.7 console executable for focused commands.
Required suite/release validation uses the tracked launcher documented in
[`docs/TESTING.md`](../../docs/TESTING.md), not the ignored workstation-only
`godot.bat`.

Run the whole fragment suite:

```powershell
& $env:GODOT_BIN --headless --path . -- --test-puzzle-fragments
```

Run one fragment by id:

```powershell
& $env:GODOT_BIN --headless --path . -- --test-puzzle-fragment hide_lane
```

Fragments also run inside:

```powershell
Push-Location ..
& .\scripts\test-gate.ps1 -Tier Headless
Pop-Location
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

Fragments can declare shared `setup` steps, and individual scenarios can add their own `setup` before the scenario `script` runs. That makes it easier to test "already damaged," "post-lure," or other mid-encounter starts without duplicating the whole bootstrap in every script.

Chunk-backed preview scenes can also expose a relay helper like `headless_call_chunk(method_name, args := [])` so fragment scripts can drive the active scene chunk without needing a one-off root method for every new fragment.

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
- scenario-specific methods such as `activate_showcase_flure()`

## Authoring Pattern

1. Build the lane in a real scene using the same live systems the shipped level will use.
2. Add a few stable probe anchors for setup and verification.
3. Expose just enough state for assertions through `headless_get_state()`.
4. Write at least one success scenario and one representative failure scenario.
5. Keep fragments small. A full level can chain several fragment ids plus travel/shelter sections.
