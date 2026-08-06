# Project Agent Guidance (Router)

The playable Godot project is in `to-rust-as-we-fall/`. This file routes work
to the canonical project references; read only the rows that match the task
before changing files.

| If the task involves... | Read and apply... |
| --- | --- |
| A puzzle, level, encounter, tutorial, or mechanic composition | `to-rust-as-we-fall/docs/SYSTEMS_THINKING_PUZZLE_STANDARD.md`, `to-rust-as-we-fall/docs/DESIGN_PRINCIPLES.md`, and `to-rust-as-we-fall/data/puzzles/level_design_review_rubric.md` |
| Anything involving enemies or fauna: designing, implementing, naming, tuning, spawning them in authored levels or procedural generation, composing encounters, or defining flora/ecology interactions | `to-rust-as-we-fall/docs/ENEMY_GAMEPLAY_ROSTER_AUDIT.md`; sections 2.7 and 7 of `reference-docs/to_rust_gdd_v02.md`; `reference-docs/fauna_roster.md`; `to-rust-as-we-fall/data/enemy_ecosystem.md`; `to-rust-as-we-fall/docs/ECOLOGY_COMBOS.md`; and `to-rust-as-we-fall/data/generation/content_palette.json`. For a visual, also read `reference-docs/fauna_image_prompts.md` and the asset-authoring row below. |
| A human or browser playtest, an automated persona/probe, AI-agent player decisions, or playthrough recording, scripting, or analysis | The three puzzle/design references above, plus `to-rust-as-we-fall/docs/PLAYTEST_PERSONAS.md`, `to-rust-as-we-fall/data/PLAYTHROUGH_WORKFLOW.md`, and `to-rust-as-we-fall/docs/TESTING.md` |
| Tests, CI, Web validation, or a release gate | `to-rust-as-we-fall/docs/TESTING.md` |
| A new unique 3D visual asset | `to-rust-as-we-fall/docs/ASSET_AUTHORING_STANDARD.md` |
| Adding or naming mechanics, characters, flora, fauna, items, regions, abilities, or other world content | The relevant canonical source under `reference-docs/`, especially `to_rust_gdd_v02.md`, `flora_taxonomy.md`, `to_rust_as_we_fall_series_bible.docx`, and `to_rust_prototype.jsx` |

Treat systems thinking as a required design lens. Define the causal model the
player is meant to build, make action-to-consequence feedback legible, and
separate reasoning difficulty from control, camera, memory, visibility, and
repetitive-execution costs. A failure should falsify an understandable player
prediction. Once the model is solved, do not add repetition that produces no
new decision or information.

`reference-docs/` is a gitignored local mirror. If a required canonical source
is absent or stale, restore it from the project originals or ask for it; never
invent replacement canon.

For enemy work, preserve the distinction between designed, placeholder, partial,
environmental, and implemented roles recorded in the enemy gameplay roster audit.
Do not represent a palette entry, visual, prose specification, or generic `Enemy`
instance as an implemented species-specific behavior. Explicit director rulings in
the audit supersede stale names or mechanics in the local reference mirror.

The worktree is often shared with concurrent agents. Preserve unrelated edits
and inspect current file state before modifying an existing file.

For required test or release validation, use the tracked root launcher
`scripts/test-gate.ps1`; do not rely on the ignored workstation-only
`godot.bat`.

For unique 3D assets, ship UV-mapped portable model sources and external
textures. Keep Godot scenes as gameplay/collision wrappers rather than the
only home of visible geometry.
