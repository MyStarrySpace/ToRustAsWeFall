# Project Agent Guidance

The playable Godot project is in `to-rust-as-we-fall/`.

For any puzzle, level, encounter, tutorial, mechanic-composition, or playtest work, read and apply:

1. `to-rust-as-we-fall/docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md`
2. `to-rust-as-we-fall/docs/DESIGN_PRINCIPLES.md`
3. `to-rust-as-we-fall/data/puzzles/level_design_review_rubric.md`

Treat systems thinking as a required design lens. Define the causal model the player is meant to build, make action-to-consequence feedback legible, and distinguish reasoning difficulty from control, camera, memory, visibility, and repetitive-execution costs. A failure should falsify an understandable player prediction. Once the model is solved, do not pad the encounter with repeated execution that produces no new decision or information.

The worktree is often shared with concurrent agents. Preserve unrelated edits and inspect current file state before modifying an existing file.
