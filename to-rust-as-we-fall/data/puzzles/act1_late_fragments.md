# Act 1 Late Fragments

These fragments cover the back half of Act 1, where the game stops teaching raw movement rules and starts teaching interpretation under degradation and pressure.

## `rings_client_bloom_read`

- `campaign_job`: teach
- `kind`: hybrid
- `party_spotlight`: Peris
- `primary_insight`: Peris's flora layer can still open a local read even after the signal has begun to decay.
- `main_target`: recognition
- `working_memory_budget`: 1 unstable fact
- `pressure_sources`: none; the room is quiet enough to let the player notice the overlay grammar
- `durable_outcome`: the player learns that the Rings are readable through local flora traces before the full network has propagated
- `failure_pedagogy`: the representative failure is the read never opening, which would collapse the player's trust in the overlay
- `headless_hooks`: `prepare_rings_fragment("client")`, `headless_set_overlay_state("peris", true)`

Why this works:
It introduces the late-stage flora read in a small radius. The player gets a clean "stand here, the network wakes" moment before we ask them to interpret weaker propagation.

## `rings_flora_propagation`

- `campaign_job`: reinforce
- `kind`: hybrid
- `party_spotlight`: Peris
- `primary_insight`: Encountered flora nodes can rejoin a later read, so the network behaves like memory propagation rather than simple proximity highlighting.
- `main_target`: prospective_memory
- `secondary_target`: map_layer_arbitration
- `working_memory_budget`: 2 unstable facts
- `pressure_sources`: delay and information decay, not combat
- `durable_outcome`: the player understands that prior contact changes what the flora layer can surface
- `failure_pedagogy`: the representative failure is treating each plant as a standalone ping instead of part of a remembered network
- `headless_hooks`: `prepare_rings_fragment("client")`, `headless_set_overlay_state("peris", true)`

Why this works:
This fragment turns the flora layer from a novelty into a system. The payoff is not just "a clue appears," but "a clue appears because I already touched the network somewhere else."

## `rings_forget_me_not_flicker`

- `campaign_job`: combine
- `kind`: hybrid
- `party_spotlight`: Peris
- `primary_insight`: Relational memory in the Rings has not vanished yet, but it is already failing.
- `main_target`: recall
- `secondary_target`: pressure_management
- `working_memory_budget`: 1 recalled association
- `pressure_sources`: emotional uncertainty rather than tactical stress
- `durable_outcome`: the player gets a readable preview of relational memory collapse before the later failures become harsher
- `failure_pedagogy`: the representative failure is the scent disappearing too early, which would flatten the staged degradation arc
- `headless_hooks`: `prepare_rings_fragment("client")`, `headless_set_overlay_state("peris", true)`

Why this works:
The fragment makes the degradation legible without resolving it. "Flicker" is the right amount of signal for this point in the campaign.

## `lockout_boundary_escape`

- `campaign_job`: gate
- `kind`: survival
- `party_spotlight`: Aster
- `primary_insight`: The chase resolves only when Aster crosses back into unserviced space; the boundary itself is the exit condition.
- `main_target`: route_planning
- `secondary_target`: pressure_management
- `working_memory_budget`: 1 active objective
- `pressure_sources`: direct pursuit and spatial commitment
- `durable_outcome`: the player understands that "back into the broken infrastructure" is the safe route, even though it reads like retreat
- `failure_pedagogy`: the representative failure is hesitating near the bright boundary instead of committing to the ugly escape line
- `headless_hooks`: `prepare_lockout_fragment("chase")`

Why this works:
The fragment converts a narrative reversal into a mechanical one. Safety is not where the lighting and access panel say it should be.

## Sequence Use

1. `rings_client_bloom_read` teaches the degraded local flora read.
2. `rings_flora_propagation` shows that prior contact changes what the network can recover.
3. `rings_forget_me_not_flicker` turns the same system toward relational memory.
4. `lockout_boundary_escape` cashes out the lesson in a high-pressure routing beat.
