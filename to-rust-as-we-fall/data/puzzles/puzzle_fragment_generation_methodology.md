# Puzzle Fragment Generation Methodology

This document defines how we generate reusable puzzle fragments for *To Rust as We Fall*.

It complements:

- [Puzzle Fragment Workflow](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/puzzles/README.md)
- [Hide Encounter Analysis Methodology](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/hide_encounter_analysis_methodology.md)

The goal is not just to make fragments that are solvable. The goal is to make fragments that:

- express the game's themes
- feel like a DnD campaign filtered through this world's systems
- teach through consequences instead of UI text
- compose cleanly into larger levels
- can be tested headlessly before we ever launch the game

## Design Note

We are using ideas from cognitive psychology and systems neuroscience as design lenses, not as a claim that the game literally simulates the brain.

The useful questions are:

- What must the player hold in working memory?
- What can the world externalize for them?
- When do we ask for recognition, and when do we ask for recall?
- What kind of stress sharpens the task, and what kind only creates noise?
- How do conflicting perception layers create productive ambiguity instead of confusion?

If a "scientific" framing does not improve player learning, tension, or legibility, we should drop it.

## Campaign Feel

Levels should feel less like abstract puzzle boxes and more like a good tabletop adventure.

That does not mean fantasy tropes pasted onto the world. It means the player should feel like they are guiding a vulnerable, specialized party through a dangerous expedition with:

- a clear objective
- distinct encounters with different textures
- role spotlights for different party members
- resource attrition across an "adventuring day"
- moments of rest, regrouping, and re-planning
- optional risks that offer loot, lore, or future convenience
- a memorable set-piece or finale that resolves the level's question

The closest translation is:

- shelter = long rest / camp
- fragment = encounter or room-sized problem
- survival corridor = wilderness travel / attrition layer
- durable shortcut = campaign progress that permanently changes future sessions
- map-layer conflict = party argument about what the world is actually like
- party ability asymmetry = class identity

We should ask of every level:

- Why is this expedition being undertaken now?
- Which character gets to be the expert in this zone?
- What is the "rumor" or promise pulling the party deeper?
- Where is the regroup point?
- What future route, relationship, or possibility changes because this level was completed?

## What A Puzzle Fragment Is

A puzzle fragment is the smallest durable puzzle beat that:

- teaches or tests one primary insight
- uses the same live systems as the shipped level
- has at least one success case and one representative failure case
- leaves the world changed, or meaningfully changes how later traversal is understood

In the GDD's terms, fragments belong to `work`, not just `labor`. Survival pressure may frame them, but the fragment should create durable understanding or durable world change.

## Core Design Guardrails

### 1. One Primary Insight

Every fragment should be reducible to one sentence:

- "Lure the pack, then hide until the release window."
- "Trade a longer safe route for a shorter harmful route before dusk."
- "Use one character's perception to disambiguate another character's bad map."

Secondary texture is fine. The player should still be able to say what the fragment was *about* after a single attempt.

### 2. Teach Through Consequence

Prefer visible cause and effect over explanation.

- The player activates the lure and sees the ecology redirect.
- The player takes the direct route and watches stamina disappear.
- The player trusts the wrong perception layer and gets punished by the real world.

If the player can only learn the fragment by reading a tooltip, the fragment is not carrying enough of its own teaching burden.

### 3. Survival Pressure Should Shape The Puzzle, Not Replace It

Time, ATP, shelter distance, enemy pressure, and perception degradation are framing pressures. They should make the player's decision sharper. They should not obscure the underlying insight.

A good early fragment says:

- "I understand what happened, and I can do better."

A bad early fragment says:

- "I died, but I am not sure what I was supposed to notice."

### 4. Perception Is Puzzle Material

In this game, partial information is not decoration. It is one of the main systems.

Fragments should intentionally choose which of these are in play:

- direct perception
- degraded memory
- schematic abstraction
- survival intel
- threat route intel
- contradictory map layers

The player should sometimes solve a fragment by moving matter in the world, and sometimes by deciding which perception layer deserves trust.

### 5. Failures Should Instruct

Each representative failure should teach one of:

- you moved too early
- you moved too late
- you trusted the wrong signal
- you spent the wrong resource
- you failed to prepare the recovery state

Failure is best when the player can point to the exact sentence that explains it.

### 6. Durable Change Matters

Whenever possible, fragments should create lasting consequences:

- a corridor becomes safer
- a hazard gets rerouted
- a shelter becomes reachable
- an information conflict becomes resolved
- a shortcut or ratchet gets established

This keeps puzzle solving aligned with the GDD's "survive, solve, connect" rhythm instead of collapsing everything into attrition.

### 7. Party Spotlight Matters

A level should not just test systems. It should make the party feel like a party.

Across a full level, try to include:

- one encounter where Endo's survival reading matters
- one encounter where Aster's abstraction or terminal logic matters
- one encounter where Peris's sensory trust matters
- later, one encounter where another recruitable party member becomes the deciding perspective

The player should leave the level able to say not just "we solved it," but also "that was Endo's zone" or "Aster was the only reason we understood that room."

### 8. Telegraph, Then Let The Party Commit

A good GM telegraphs danger before asking the table to commit. Our levels should do the same.

Telegraph with:

- visible hazard geometry
- enemy movement that can be observed before engagement
- survival intel from Endo
- contradictory but interpretable map layers
- architecture that suggests what kind of room this is before the player is trapped in it

Then let the player make a plan under uncertainty. Hidden information is fine. Unsignaled information is usually not.

### 9. Optional Risk Should Feel Like A Side Room, Not Busywork

DnD campaigns feel rich because not every door is mandatory.

Optional routes in a level should ideally offer one of:

- ATP, food, or water buffer
- a shortcut for the return route
- lore or relationship payoff
- a safety valve that makes a later encounter more forgiving
- a dangerous but efficient route for expert players

Optional content is strongest when the player understands the tradeoff, not when they are punished for not being clairvoyant.

## Cognitive Foundations

## Working Memory Load

Players can only actively track a small number of unstable facts at once. Fragments should be designed around a memory budget.

Typical unstable facts:

- current lure state
- enemy location
- remaining ATP or stamina
- shelter distance
- which perception layer is currently trustworthy
- whether a previously safe route is still valid

Design rules:

- Early fragments: 1 to 2 unstable facts, 1 active pressure source
- Mid-game fragments: 2 to 4 unstable facts, 1 to 2 pressure sources
- Late fragments: 3 to 5 unstable facts, often supported by externalized cues

If a fragment needs more than that, the state should be externalized into the scene, the UI, or the scheduler trace.

## Chunking And Reusable Motifs

Players learn faster when multiple fragments reuse the same pattern with different stakes.

Examples of chunkable motifs:

- bait -> wait -> pass
- route -> observe -> reroute
- spend resource now -> buy safety later
- compare two map layers -> choose one -> verify in direct sight

Once a motif is chunked, later fragments can recombine two known motifs instead of introducing a new mechanic from scratch.

At the level scale, this lets a sequence feel like a campaign session:

- opening reconnaissance
- a first encounter that teaches the room's logic
- a harder recombination encounter
- a side-room temptation
- a finale that pays off the level's promise

## Recognition Before Recall

Early fragments should bias toward recognition:

- the hide spot is visible
- the danger cue is obvious
- the correct lure target is already in frame

Later fragments can ask for recall:

- remember a shelter location from earlier
- remember which layer lied in a similar corridor
- remember that a safe detour will fail once sundowning closes in

Recognition teaches the rule. Recall tests whether the rule has become internalized.

## Desirable Difficulty

We want difficulty that produces better understanding, not difficulty that merely produces noise.

Good difficulty:

- asks the player to commit before perfect certainty
- punishes sloppy timing by a readable amount
- rewards planning and observation
- can be recovered from when the fragment is still in the teaching phase

Bad difficulty:

- combines too many novel ideas at once
- hides the critical state transition
- punishes an invisible mistake with a distant reset

The fragment should stay slightly ahead of the player's certainty, not miles ahead of it.

## Attention And Task Switching

Real puzzle pressure often comes from attention, not from raw complexity.

Useful attentional demands:

- watch the enemy while preserving a future escape route
- monitor ATP while deciding whether to stay hidden
- switch from route planning to timing execution at a clear boundary

Guideline: one dominant attentional switch per fragment is usually enough. If the player must monitor several urgent channels at once, make sure at least one of them is stable and externally visible.

## Prospective Memory

Many fragments in this game are really about remembering to do something later:

- hide now so you can move later
- preserve ATP now so you can afford the exit window later
- establish a ratchet now so a future return trip is safe

Prospective-memory fragments need visible futures. The player should be able to imagine the later payoff while acting in the present.

## Spatial Cognition

Players generally learn spaces in two passes:

- route knowledge first: "turn here, hide there, run to that shelter"
- survey knowledge later: "this corridor loops behind the iron bloom"

Early fragments should mostly operate on route knowledge. Later fragments can leverage survey knowledge, shortcut logic, and contradictions between remembered and actual layouts.

## Stress, Interoception, And Performance

ATP, stamina drain, dusk pressure, enemy pursuit, and shelter scarcity act like interoceptive stressors. They change how much cognition the player has available.

Use stress to:

- force prioritization
- make tradeoffs meaningful
- turn a known mechanic into a tense one

Do not use stress to bury a first-time lesson. If the player is still learning the core rule, reduce stress until the rule is legible.

## Multisource Integration

The game's party structure naturally supports partial, conflicting information.

Fragments can ask the player to integrate:

- Peris warmth and shape
- Aster abstraction and system state
- Endo survival readability
- Tyreg patrol timing
- Myke route infrastructure
- Oli power connectivity

This is one of the game's strongest design advantages. Use it deliberately. The integration task should still resolve to a readable decision.

## Difficulty Budget

Score each fragment across the following axes before implementation:

- `info_load`: how many unstable facts must be tracked?
- `time_pressure`: how quickly does the window close?
- `execution_precision`: how exact is movement or timing?
- `ambiguity`: how much conflicting or degraded information is present?
- `reset_cost`: how painful is failure?
- `durability`: how large is the lasting payoff?

Suggested ranges:

- Early game teaching fragment: keep the first five axes low, but still give at least moderate `durability`
- Mid-game recombination fragment: raise `info_load` or `ambiguity`, not every axis at once
- Late-game mastery fragment: high `ambiguity` and `time_pressure` are fair if the player is operating on known motifs

If a fragment scores high on both `ambiguity` and `reset_cost`, it probably needs stronger external cues or a closer recovery point.

## Fragment Generation Pipeline

## Level Generation Pipeline

Fragments are the atomic unit. Levels are the session structure that gives those fragments emotional and strategic context.

### 1. Choose The Level Promise

Write one sentence that would make the player want to go.

Examples:

- "Recover the sealant canister before Endo's junction fails tonight."
- "Reach the deep archive and learn why the maintenance map keeps lying."
- "Climb the ferric shaft to reroute the siderophore pack away from the shelter chain."

This is the level's quest hook.

### 2. Choose The Party Spotlight

Decide whose level this is.

That does not mean only one character matters. It means one character's knowledge is the emotional and mechanical spine of the expedition.

### 3. Define The Adventuring Day

Map the level into a resource arc:

- entry state
- first pressure spike
- mid-level regroup point
- optional side risk
- finale
- return or escape state

Shelter, ATP, and recoverable mistakes should be placed intentionally, not evenly.

### 4. Build A Sequence Of Encounter Types

A strong level usually mixes several room functions:

- orientation room
- teaching encounter
- traversal under pressure
- optional reward room
- gating puzzle
- finale or set-piece
- shortcut unlock or safe return

Do not make every room a full puzzle. Variation is what makes a level feel like an expedition instead of a worksheet.

### 5. Assign Each Encounter A Role Spotlight

Ask who is "speaking" in each room:

- Endo speaks through survival knowledge
- Aster through systems and data
- Peris through trust, warmth, and sensory contradiction
- Tyreg through timing and patrol rhythms
- Myke through route memory and infrastructure intuition
- Oli through connectivity and power logic

This gives the level a party-campaign feel instead of a purely mechanical one.

### 6. Place A Regroup Beat

At least one beat in a full level should let the player exhale, reframe the objective, and feel the party dynamic.

That beat can be:

- a shelter
- a half-safe overlook
- a small cache room
- a temporary ecology lull created by the player's own actions

Without regroup beats, the level can become emotionally flat even if the mechanics are good.

### 7. Make The Finale Resolve The Level's Question

The final encounter should not just be harder. It should answer the level's promise.

If the promise is "can we hold the corridor long enough to save the junction," the finale should resolve that.

If the promise is "which map layer deserves trust here," the finale should force the player to commit to one and live with it.

### 8. Define Persistent Consequences

Good campaign-feeling levels change the future:

- a safe loop opens
- a shelter chain expands
- an ecology route changes
- a party relationship shifts
- a later zone becomes more approachable

If the level leaves no trace, it risks feeling like filler even if the room-to-room play was decent.

### 1. Choose The Fragment's Campaign Job

Pick one:

- teach a new motif
- reinforce a known motif
- combine two known motifs
- gate progress
- create a durable shortcut
- create a high-pressure mastery check

If the fragment has no job in the campaign learning arc, it is probably set dressing, not a puzzle fragment.

### 2. Write The Primary Insight

Use one sentence only.

Good:

- "Use the first lure to peel the pack off the hallway, then hide until the exit window opens."

Bad:

- "The player should feel tense and maybe use the lure and also manage stamina and maybe discover hiding."

### 3. Pick The Cognitive Target

Choose the main mental demand:

- recognition
- recall
- timing
- prospective memory
- map-layer arbitration
- route planning
- pressure management
- recovery planning

This helps keep the fragment honest. If the implemented fragment tests something else, the design drifted.

### 4. Pick The World Systems And Verbs

List the systems that carry the fragment:

- lure
- hide
- shelter
- ATP or stamina
- patrol
- hazard routing
- transport
- flora growth
- terminal activation

Then list the verbs the player actually performs:

- observe
- lure
- wait
- reroute
- sprint
- consume
- drag
- activate
- insulate

Fragments are easier to test when the verbs are explicit.

### 5. Build A Small State Diagram

Define the states and transitions before layout polish.

For example:

- `safe`
- `baited`
- `hidden`
- `release_window`
- `escaped`
- `detected`

If the state graph is muddy, the player experience will be muddy too.

### 6. Choose The Pressure Envelope

Pick only the pressures that serve the insight:

- timer
- ATP drain
- enemy pursuit
- perception degradation
- route uncertainty
- scarce shelter

Ask:

- What is the minimum pressure needed to make the choice meaningful?
- What pressure is too much for the current learning phase?

### 7. Decide The Durable Outcome

Name the lasting consequence:

- corridor cleared
- ecology rerouted
- safe shelter chain established
- shortcut opened
- information contradiction resolved
- future traversal simplified

If there is no durable outcome, confirm that the fragment is intentionally a survival beat instead of a puzzle beat.

### 8. Design Representative Failures

Write at least one failure for each relevant mistake class:

- naive failure: what a first-time player is likely to do
- greedy failure: what happens if they push too early or spend too much
- trust failure: what happens if they choose the wrong signal
- recovery failure: what happens if they arrive with the wrong resource state

Each failure should be local, readable, and ideally attributable to one bad assumption.

### 9. Expose Headless Probes

Before tuning layout, define what the scene must expose:

- stable anchors for setup
- state paths for assertions
- helper methods for scripted triggers
- deterministic scheduler stepping

Minimum scene contract:

- `headless_get_anchor_positions()`
- `headless_get_state()`
- `headless_advance()`

Optional probe examples:

- current phase
- current target or aggro state
- active lure id
- ATP or stamina values
- last outcome
- event counters

### 10. Author Deterministic Scenario Tests

Every fragment should start with a small deterministic suite:

- `golden_path`: intended success
- `naive_failure`: obvious incorrect play
- `recovery_case`: barely succeeds after a delay or small cost
- `sequence_guard`: prevents a trivial exploit or out-of-order skip

Not every fragment needs all four on day one, but `golden_path` plus one representative failure is the minimum.

### 11. Identify Free Parameters

List the knobs we may tune later:

- lane distance
- lure duration
- enemy speed
- ATP drain
- regen values
- hold duration
- hide duration
- safe-route cost
- detection threshold

Separate:

- structural parameters: layout, doors, shelter spacing
- behavioral parameters: speeds, timers, drains
- information parameters: cue duration, cue visibility, map reliability

### 12. Sweep The Envelope

Once the fragment is deterministic, test the solvability envelope.

Useful sweep questions:

- What is the first ATP or stamina value where success becomes viable?
- Which free variables widen the success window without trivializing the task?
- Which failure modes cluster near the boundary?

For fragments with continuous resources and discrete events, use the same hybrid analysis style as the hide encounter:

- closed-form approximation where possible
- phase-plane traces for resource vs remaining distance
- bifurcation sweeps over a primary threshold variable
- Monte Carlo perturbations for hesitation, mis-timing, or model uncertainty

### 13. Compose The Fragment Into A Sequence

Before calling a fragment done, answer:

- What did the player learn immediately before this?
- What future fragment will reuse this motif?
- Does the durable outcome create a later route, shelter chain, or narrative beat?
- If this fragment were removed, what understanding would the level lose?

Fragments matter more when they hand something forward.

### 14. Check The Campaign Session Feel

Before implementation, ask:

- Does this level have a hook, an expedition shape, and a payoff?
- Does the party feel specialized and interdependent?
- Is there at least one optional temptation?
- Is there at least one regroup beat?
- Does the finale resolve the promise instead of merely being the toughest room?
- Will the player remember this as "the level with the ferric spiral" or "Endo's broken wall run," not just as a list of mechanics?

## Validation Stack

Use four validation layers:

### Layer 1. Contract Tests

Headless scenario scripts assert that the fragment still behaves correctly after content edits.

### Layer 2. Parameter Envelope

Sweeps identify thresholds, margins, and brittle variables.

### Layer 3. Monte Carlo Robustness

Perturb timing, movement delay, or model assumptions to find false positives that deterministic scripts miss.

### Layer 4. Sequence Integration

Run the fragment as part of a longer level chain to verify:

- correct narrative order
- expected resource carryover
- no broken handoff between fragments
- no sequence breaks introduced by durable world changes
- optional routes pay off correctly
- the promised party spotlight is actually required somewhere

Manual play should happen after these four layers, not instead of them.

## A Good Fragment Brief

Before implementation, a fragment brief should be able to answer these questions in plain language:

- What is the player meant to notice?
- What are they meant to decide?
- What are they risking?
- What permanent thing changes if they succeed?
- What exact mistake does the representative failure teach?
- How will we prove all of that headlessly?

If any answer is vague, the fragment is still too blurry to build.

## Example: Hide Lane

`hide_lane` is a strong example because it already fits the methodology.

- Campaign job: teach and then reinforce bait -> hide -> exit timing
- Primary insight: the lure creates a future movement window, but only if the player spends that time hiding instead of advancing
- Cognitive target: prospective memory under stress
- Pressure envelope: enemy movement, timing window, ATP or stamina state
- Durable outcome: safe passage to the shelter or next lane
- Representative failure: move while exposed and get detected
- Headless probes: `hide_phase`, `hide_last_outcome`, stable anchors, lure trigger helper
- Analysis path: deterministic scenarios first, then parameter sweeps and Monte Carlo

That same pattern can be generalized to other fragment families:

- route-and-rest fragments
- hazard-crossing fragments
- multi-layer information conflicts
- escort or drag-to-shelter fragments
- terminal-plus-physical-routing fragments

## Practical Rule Of Thumb

When in doubt, shrink the fragment until it cleanly teaches one thing, then recover complexity by chaining fragments together.

Small, composable, headlessly verified fragments are more valuable than large "cool" puzzle rooms that no one can reliably reason about.
