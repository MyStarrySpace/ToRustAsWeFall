# Stacks Fragment Briefs

These Processing Stacks fragments keep the Stacks scene atomic: one insight at a time, recognition before recall, and just enough pressure to make the fiction stick without turning the room into a combat puzzle.

## `stacks_support_log_intro`

- `campaign_job`: teach
- `kind`: hybrid
- `party_spotlight`: Aster
- `primary_insight`: The Engram is a pause-layer Aster can use to externalize crucial context, not just a lore dump.
- `main_target`: recognition
- `working_memory_budget`: 1 unstable fact
- `pressure_sources`: none in the moment; the pressure is narrative framing
- `durable_outcome`: the player learns that hidden infrastructure memory can be surfaced and revisited through the Engram
- `failure_pedagogy`: the only failure worth testing is sequence breakage: the log does not surface, does not pause, or does not hand control back to the Stacks route
- `headless_hooks`: `prepare_stacks_fragment("engram")`, `trigger_stacks_support_log()`, `close_stacks_engram_overlay()`

Why this works:
The scene externalizes a future memory tool before asking the player to rely on it under pressure. That keeps the introduction in recognition-space, which is exactly where a new motif should start.

## `stacks_terminal_signal`

- `campaign_job`: reinforce
- `kind`: hybrid
- `party_spotlight`: Aster
- `primary_insight`: The official terminal is coherent but incomplete, and that mismatch should push the player toward the unofficial signal lane.
- `main_target`: recognition
- `working_memory_budget`: 1 unstable fact
- `pressure_sources`: expectation dissonance, not execution pressure
- `durable_outcome`: the player stops treating the cleaned terminal output as the whole truth
- `failure_pedagogy`: the representative failure is accepting the normalized feed as complete instead of suspiciously too neat
- `headless_hooks`: `prepare_stacks_fragment("terminal")`, `trigger_stacks_terminal()`

Why this works:
This fragment does not ask the player to solve the room yet. It teaches the suspicion that makes the next fragment legible.

## `stacks_signal_wall`

- `campaign_job`: reinforce
- `kind`: hybrid
- `party_spotlight`: Aster with Peris as the plain-language check
- `primary_insight`: The room becomes legible only when Aster trusts the unofficial sensor wall over the sanctioned interface.
- `main_target`: map_layer_arbitration
- `working_memory_budget`: 2 unstable facts
- `pressure_sources`: route commitment plus information ambiguity
- `durable_outcome`: the player learns that infrastructure truth can sit in unofficial tooling instead of the sanctioned interface
- `failure_pedagogy`: the representative failure is reading each metric as isolated noise instead of a coordinated failure pattern
- `headless_hooks`: `prepare_stacks_fragment("signal")`, `trigger_stacks_signal()`

Why this works:
This is the Stacks version of "trust the better layer, not the official layer." It carries a later campaign tactic in a low-threat space where the player can notice the pattern without combat noise.

## `stacks_archive_audit`

- `campaign_job`: combine
- `kind`: hybrid
- `party_spotlight`: Aster with Peris as the plain-language check
- `primary_insight`: Correlating a physical workspace with archive records reveals intent, not just malfunction.
- `main_target`: prospective_memory
- `secondary_target`: recall
- `working_memory_budget`: 3 unstable facts
- `pressure_sources`: narrative tension and information integration, not execution precision
- `durable_outcome`: the player leaves the room knowing someone actively protected the sensor stream from normalization
- `failure_pedagogy`: the representative failure is stopping at "clever maintenance" instead of pushing one layer deeper into authorship and motive
- `headless_hooks`: `prepare_stacks_fragment("archive")`, `trigger_stacks_archive()`

Why this works:
The room turns a set of clues into a readable inference. The notebook, warm workspace, and ghost worker IDs all point in the same direction, so the player gets authorship rather than trivia scatter.

## `stacks_support_log_revisit`

- `campaign_job`: reinforce
- `kind`: hybrid
- `party_spotlight`: Aster
- `primary_insight`: The Engram should stay useful after its introduction; it is a persistent notebook, not a one-off cutscene wrapper.
- `main_target`: recall
- `working_memory_budget`: 1 recalled fact
- `pressure_sources`: none; this is a quiet reinforcement beat
- `durable_outcome`: the player understands that resurfacing prior context is an allowed verb during exploration
- `failure_pedagogy`: the representative failure is regressions where reopening the log advances the scene or fails to restore control
- `headless_hooks`: `prepare_stacks_fragment("explore")`, `trigger_stacks_support_log()`, `close_stacks_engram_overlay()`

Why this works:
Revisit fragments keep tutorial affordances from feeling scripted and disposable. The player gets to practice "I can check my memory layer again" without any additional fiction burden.

## Sequence Use

Primary Stacks chain:

1. `stacks_support_log_intro` teaches the external memory tool.
2. `stacks_terminal_signal` establishes that the sanctioned layer is incomplete.
3. `stacks_signal_wall` turns anomaly into a readable infrastructure diagnosis.
4. `stacks_archive_audit` resolves the room's question by turning diagnosis into authorship.

Optional reinforcement:

1. `stacks_support_log_revisit` can be dropped into free exploration to remind the player that the Engram is a persistent tool.

That gives the Stacks a distinct expedition shape without forcing a combat puzzle into a scene whose real job is disillusionment and inference.
