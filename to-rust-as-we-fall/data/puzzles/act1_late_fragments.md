# Act 1 Late Fragments

These fragments cover the back half of Act 1. In the Rings, story progression belongs to Marco naming the reassignment pattern and Endo leaving. Peris's three flora/memory reads are optional ambient worldbuilding: they work in any order and cannot gate, reorder, or complete the route.

## `rings_reassignment_beat`

- `campaign_job`: story gate
- `kind`: conversation
- `party_spotlight`: Peris, with Aster and Endo present
- `primary_insight`: residents scatter because a Separations/Transport analyst and a therapist arriving together are the known shape that precedes reassignment
- `causal_model`: the response is institutional pattern recognition, not fear of rank or visiting executives
- `durable_outcome`: Marco names the pattern; Peris registers the shift without completing her later Psyknapse recognition; Endo then leaves at the junction
- `failure_pedagogy`: tests reject the retired c-suite explanation and any dependency on optional flora reads
- `headless_hooks`: `prepare_rings_fragment("client")`, gather conscious Peris and Endo beside
  `ClientNPC`, then trigger Marco's real one-shot as Peris

## `rings_client_bloom_read`

- `campaign_job`: optional worldbuilding
- `kind`: ambient read
- `party_spotlight`: Peris
- `primary_insight`: a former client's bloom retains an emotional outline after the resident stops answering
- `main_target`: recognition
- `pressure_sources`: none
- `durable_outcome`: local relationship context, with no progression mutation
- `failure_pedagogy`: the read may fail to surface, but skipping it can never block Marco or Endo
- `headless_hooks`: `prepare_rings_fragment("client")`, move Peris to
  `RingsTrace_client_bloom`, then trigger that real one-shot

## `rings_flora_propagation`

- `campaign_job`: optional worldbuilding
- `kind`: ambient read
- `party_spotlight`: Peris
- `primary_insight`: flora follows the routes, warmth, and repeated contact of a tended commuter district
- `main_target`: environmental interpretation
- `pressure_sources`: none
- `durable_outcome`: context for how residents used the Rings, with no route effect
- `failure_pedagogy`: the read cannot become a prerequisite or imply that the district is abandoned
- `headless_hooks`: `prepare_rings_fragment("client")`, `trigger_rings_trace("doorvine")`

## `rings_forget_me_not_flicker`

- `campaign_job`: optional worldbuilding
- `kind`: ambient read
- `party_spotlight`: Peris
- `primary_insight`: a deliberately tended domestic species briefly surfaces relational memory
- `main_target`: recognition
- `pressure_sources`: emotional uncertainty, not tactical stress
- `durable_outcome`: a hidden reference to later memory content, without resolving Peris's recognition here
- `failure_pedagogy`: the read cannot gate, reorder, or complete Rings progression
- `headless_hooks`: `prepare_rings_fragment("client")`, `trigger_rings_trace("forget_me_not")`

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

## Sequence Use

1. Any or all three ambient Rings reads may be found, skipped, or revisited in any order.
2. Marco names the analyst-plus-therapist reassignment pattern; this is the required Rings beat.
3. Endo departs at the junction.
4. Rings exploration hands off to `lockout_boundary_escape`.
