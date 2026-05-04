# Survival Fragment Briefs

These showcase survival fragments teach the expedition layer in small, testable chunks: aggro commitment, attrition recovery, and "wait now, move later" under pressure.

Some of the newer fragments intentionally begin from primed encounter states instead of fresh scene boot. That lets us test the middle of a survival beat, not just its cold open.

## `standard_enemy_commitment`

- `campaign_job`: reinforce
- `kind`: survival
- `party_spotlight`: Aster
- `primary_insight`: Drawing aggro is only half the lesson; if you linger in the lane after the patrol commits, the enemy closes space immediately.
- `main_target`: pressure_management
- `secondary_target`: route_planning
- `working_memory_budget`: 1 active threat
- `pressure_sources`: direct pursuit and short-range commitment
- `durable_outcome`: the player learns that line-of-sight scouting must immediately become movement discipline
- `failure_pedagogy`: the representative failure is treating detection as information only instead of a commitment state
- `headless_hooks`: `enemy_probe`, `enemy.standard.distance_to_target`, `enemy.standard.target`

Why this works:
The fragment converts a readable patrol into a real survival commitment. "The enemy saw me" becomes "I needed a next move already."

## `chain_enemy_commitment`

- `campaign_job`: reinforce
- `kind`: survival
- `party_spotlight`: Peris
- `primary_insight`: The chain enemy closes space differently from a normal patrol, so hesitation in its lane is punished harder and earlier.
- `main_target`: recognition
- `secondary_target`: pressure_management
- `working_memory_budget`: 1 active threat and 1 spatial warning
- `pressure_sources`: pursuit plus constrained lane geometry
- `durable_outcome`: the player learns that not all hostile lanes can be read with the same retreat rhythm
- `failure_pedagogy`: the representative failure is assuming the chain lane grants the same hesitation window as the standard enemy lane
- `headless_hooks`: `chain_probe`, `enemy.chain.distance_to_target`, `enemy.chain.target`

Why this works:
It teaches enemy-family differentiation without a wall of explanation. The player feels the chain enemy's reach before we ask them to route around it in a real level.

## `iron_bloom_step_out`

- `campaign_job`: teach
- `kind`: survival
- `party_spotlight`: Endo
- `primary_insight`: Iron bloom damage is continuous area attrition, so survival depends on stepping out cleanly, not tanking through it.
- `main_target`: recognition
- `secondary_target`: recovery_planning
- `working_memory_budget`: 1 resource trend
- `pressure_sources`: HP attrition only
- `durable_outcome`: the player understands that exiting the patch immediately stabilizes the situation
- `failure_pedagogy`: the representative failure is reading the floor as a one-time hit instead of a sustained drain
- `headless_hooks`: `iron_patch`, `iron_safe`, `character_hp.endo`

Why this works:
This fragment teaches a useful survival grammar early: some hazards are about leaving, not enduring.

## `iron_bloom_last_gasp`

- `campaign_job`: reinforce
- `kind`: survival
- `party_spotlight`: Endo
- `primary_insight`: Attrition hazards become a different problem when the party enters them already compromised.
- `main_target`: pressure_management
- `secondary_target`: recovery_planning
- `working_memory_budget`: 1 active survival margin
- `pressure_sources`: low HP plus continuous floor damage
- `durable_outcome`: the player learns that "I can probably eat one more tick" is not a safe assumption when a run starts damaged
- `failure_pedagogy`: the representative failure is entering the iron lane as if full-health timing still applies
- `headless_hooks`: `headless_set_character_hp()`, `iron_patch`, `character_hp.endo`

Why this works:
It gives the iron bloom family a second texture. The lane is no longer just "notice the floor hurts," but "notice that expedition state changes what counts as survivable."

## `hide_timeout_exposure`

- `campaign_job`: combine
- `kind`: survival
- `party_spotlight`: Endo
- `primary_insight`: The lure window only converts into a sprint if Endo is already hidden when it burns out; waiting exposed wastes the whole setup.
- `main_target`: prospective_memory
- `secondary_target`: timing
- `working_memory_budget`: 2 unstable facts
- `pressure_sources`: countdown pressure and swarm detection
- `durable_outcome`: the player learns that setup beats can fail from passivity, not just reckless movement
- `failure_pedagogy`: the representative failure is "I waited, so I was safe" instead of "I waited in the wrong state"
- `headless_hooks`: `hide_exposed_wait`, `activate_hide_lure()`, `hide_phase`, `hide_last_outcome`

Why this works:
It sharpens the hide/run motif. The player already knows that moving exposed is bad; this fragment teaches that exposed waiting is also a decision.

## `hide_release_window`

- `campaign_job`: reinforce
- `kind`: survival
- `party_spotlight`: Endo
- `primary_insight`: Once the hide phase has paid out, the new question is execution under release pressure, not whether the lure worked.
- `main_target`: timing
- `secondary_target`: pressure_management
- `working_memory_budget`: 1 active objective
- `pressure_sources`: a shrinking release window plus panic routing
- `durable_outcome`: the player learns to read the post-hide state as its own encounter phase
- `failure_pedagogy`: the representative failure is breaking back toward the swarm after earning the run instead of committing to shelter
- `headless_hooks`: `prime_hide_run_window()`, `hide_run_exposed`, `shelter`, `hide_phase`, `hide_last_outcome`

Why this works:
It gives the hide lane a second half. The player is no longer being tested on whether they hid correctly, but on whether they can cash out the release window without panicking.

## `shelter_to_shelter_range`

- `campaign_job`: combine
- `kind`: survival
- `party_spotlight`: full party, with Endo owning the final cash-out
- `primary_insight`: a real shelter-chain stretch is not one trick repeated, but a disciplined handoff from scouting, to route opening, to attrition management, to the final shelter sprint
- `main_target`: route_planning
- `secondary_target`: prospective_memory
- `working_memory_budget`: 3 linked steps and 1 active margin
- `pressure_sources`: lure timing, shortcut temptation, hide commitment, and shelter-distance judgment
- `durable_outcome`: the player learns what "one shelter to the next" actually feels like as a survival promise rather than as a list of isolated mechanics
- `failure_pedagogy`: the representative failure is taking the shorter bloom line without the scouting and lure setup, then discovering that the slit no longer converts into a real release window
- `headless_hooks`: `headless_set_selected_characters()`, `headless_set_routing_mode()`, `headless_call_chunk()`, `chunk.route_phase`, `chunk.mid_seam_damage`, `chunk.hide_phase`, `chunk.shelter_reached`

Why this works:
This is the first full survival range, not just a lane. It makes the shelter chain legible as a sequence of party responsibilities, so later spiral levels can borrow the same grammar at a larger scale.

## Sequence Use

1. `standard_enemy_lane` introduces aggro recognition.
2. `standard_enemy_commitment` teaches that recognition must turn into immediate repositioning.
3. `chain_enemy_lane` introduces a different hostile silhouette.
4. `chain_enemy_commitment` proves that the chain lane punishes hesitation on a tighter clock.
5. `iron_bloom_lane` teaches that the floor hurts.
6. `iron_bloom_step_out` teaches how to recover from that attrition cleanly.
7. `iron_bloom_last_gasp` shows that damaged entry changes the margin entirely.
8. `hide_lane` teaches bait -> hide -> run.
9. `hide_timeout_exposure` closes the loophole where passive waiting masquerades as correct play.
10. `hide_release_window` teaches that the release phase is its own commitment test.
11. `shelter_to_shelter_range` recombines the full survival grammar into one shelter-chain stretch.
