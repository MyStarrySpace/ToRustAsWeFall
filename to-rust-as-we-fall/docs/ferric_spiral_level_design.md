# Ferric Spiral Level Design

This is a level concept built directly from the puzzle fragment methodology.

It is designed to:

- feel like a DnD campaign session
- use systems we already have or have already prototyped
- decompose cleanly into headless-testable fragments
- fit the game's vertical spiral exploration structure

## Level Pitch

**Name:** Ferric Spiral

**Level promise:** Climb a rusted maintenance spiral above Endo's junction, recover a sealant canister from an abandoned cache, and permanently reroute the siderophore pack before nightfall.

**Party spotlight:** Endo is the guide and emotional spine of the level, while Aster handles route interpretation and Peris is the tie-breaker when the map feels wrong.

**DnD translation:**

- quest giver: Endo
- dungeon: the spiral maintenance shaft
- camp: the central shelter core
- wandering danger: siderophore pack and corridor enemies
- side room temptation: salvage cache and ATP relief route
- short rest: overlook nook halfway up the spiral
- boss-equivalent finale: the dual-flure reroute and escape window
- treasure: sealant canister, optional salvage, and a permanent safe shortcut back to the junction

## Why This Feels Like A Campaign

The player is not just "solving rooms." They are taking a party on an expedition with a clear ask and a clear cost if they fail.

- Endo knows his section is failing and asks the party to retrieve sealant before the next rest cycle.
- The spiral structure lets the player see future and past routes, which creates the feeling of a dungeon with layered loops.
- Each major encounter spotlights a different type of expertise.
- The midpoint overlook gives a regroup beat where the player can re-plan and feel the party's vulnerability.
- The final flure sequence is a set-piece that resolves the level's central question: can the party turn a deadly route into a durable survival corridor?

## Assumed Roster And Current System Scope

Primary assumption for first implementation:

- Aster
- Peris
- Endo

Systems assumed available because we already use or prototype them:

- direct versus safe traversal around hazards
- ATP or stamina pressure
- iron bloom hazard
- flure signal redirection
- hide encounter timing
- pendulum traversal hazard
- basic enemy aggro lane
- deterministic headless scheduler and fragment runner

Optional future layer if Tyreg or Oli are implemented by the time we build it:

- Tyreg adds patrol-route timing to the upper spiral
- Oli adds a powered shortcut unlock in the cache chamber

## Macro Structure

The level is a vertical spiral wrapped around a central shelter core. The player repeatedly sees:

- the junction below where Endo's wall is failing
- the shelter core at the center of the spiral
- the cache chamber above as a visible promise
- siderophore movement through open grates in the middle distance
- one or two future shortcuts they cannot use yet

The route structure is:

1. Shelter briefing and departure
2. Lower spiral survival node
3. First siderophore puzzle node
4. Midpoint regroup and optional side node
5. Upper spiral mixed-pressure node
6. Cache chamber retrieval node
7. Dual-flure finale
8. Shortcut unlock back to the shelter core
9. Eat, recuperate, and return to the junction

## Node Mix

This level should explicitly mix:

- survival nodes that tax ATP, timing, and route judgment
- puzzle nodes that create durable changes
- shortcut nodes that reconnect the outer spiral to the shelter core
- a finale node that resolves the level promise

That is the same grammar established in [spiral_level_framework.md](/C:/Users/quest/Programming/Games/ToRustAsWeFall/to-rust-as-we-fall/data/levels/spiral_level_framework.md).

## Resource Arc

Entry state:

- moderate ATP
- low narrative uncertainty
- obvious local goal

First pressure spike:

- iron bloom plus enemy lane creates the first real route choice

Midpoint regroup:

- overlook nook with a partial shelter feel but not a full rest
- enough safety to pause, inspect the route, and absorb what changed

Late pressure spike:

- hide-lane style execution under tighter margins
- final return path asks the player to cash in what they learned

End state:

- the junction is sealable
- a durable shortcut back to the shelter core now exists
- the player understands the siderophore bait -> hide -> pass motif as a reusable campaign tool

## Encounter Sequence

## Encounter 1: Endo's Briefing Alcove

**Role in level:** orientation room and quest hook

**Primary insight:** Endo's survival knowledge is what makes this expedition possible.

**Player experience:**

- Endo marks the first hide spot and shelter line
- Aster can see the spiral's geometry but not whether it is livable
- Peris gets warmth and unease from the shaft but not a reliable route

**Dnd feel:** the guide explains the mission, the party sees the dungeon mouth, and the table gets its first rumor about what lies above.

**Headless need:** mostly narrative sequencing and anchor setup, not a puzzle fragment by itself

## Encounter 2: Rusted Split

**Role in level:** early teaching encounter

**Primary insight:** safe routing and direct routing trade time for ATP

**Systems:**

- iron bloom lane
- visible detour
- visible direct line

**Spotlight:** Endo warns about survival cost; Aster makes the route readable

**Representative failures:**

- player takes the direct route too casually and enters the next room under-resourced
- player takes the long route too slowly and arrives as the siderophore window is narrowing

**Durable payoff:** teaches the resource logic that the rest of the level depends on

**Candidate fragment ids:**

- `spiral_split_safe_route`
- `spiral_split_direct_route`

## Encounter 3: Grate Gallery

**Role in level:** first real puzzle encounter

**Primary insight:** a flure is not an escape button; it is a way to create a later movement window

**Systems:**

- flure signal lane
- visible siderophore pack through grates
- obvious but unsafe advance path
- nearby hide space

**Spotlight:** Endo identifies the hide space, Aster confirms the pack shifted, Peris verifies the corridor feels empty enough to trust

**Representative failures:**

- activate lure and run immediately
- hide too far from the lane and lose the window

**Durable payoff:** opens the lower loop so the return trip later is legible

**Candidate fragment ids:**

- `spiral_first_lure_hidden_success`
- `spiral_first_lure_exposed_failure`

## Encounter 4: Midway Overlook

**Role in level:** regroup beat

**Primary insight:** the player now understands the spiral as a whole and can choose risk appetite

**Player experience:**

- the player sees the cache chamber above
- the player sees an optional side room below the next switchback
- Endo comments on whether the party looks fit enough to risk it

**Dnd feel:** this is the short-rest balcony where the party looks at the dungeon map and debates whether to go off the main path for supplies

**Headless need:** sequence integration test should confirm the route branches and rejoins cleanly

## Encounter 5: Side Cache Of Old Rations

**Role in level:** optional side room temptation

**Primary insight:** optional risk can buy future forgiveness

**Systems:**

- pendulum hazard or thrown-object lane
- optional ATP refill or salvage bundle

**Spotlight:** Peris's sensory trust matters because the room looks safer on Aster's schematic than it feels in direct presence

**Representative failures:**

- player greedily enters without observing the timing pattern
- player ignores the room and must play the finale on a tighter ATP budget

**Durable payoff:**

- extra ATP buffer for the finale
- optional salvage lore
- possibly a one-way drop that creates a micro-shortcut on the descent

**Candidate fragment ids:**

- `spiral_side_cache_pendulum`
- `spiral_side_cache_throw_lane`

## Encounter 6: Upper Spiral Pursuit Lane

**Role in level:** pressure recombination

**Primary insight:** route planning must now happen while accounting for a live hostile lane

**Systems:**

- standard enemy or chain enemy
- iron bloom interference
- short hide opportunity

**Spotlight:** Aster reads approach vectors, Endo marks the only survivable retreat pocket

**Representative failures:**

- commit to a dead-end pocket
- enter the lane while under-resourced from the first split

**Durable payoff:** proves the player can apply the earlier motifs under pressure

**Candidate fragment ids:**

- `spiral_upper_pursuit_escape`
- `spiral_upper_pursuit_failure`

## Encounter 7: Sealant Cache Chamber

**Role in level:** reward room with tactical sting

**Primary insight:** the objective is easy to take but hard to leave with

**Systems:**

- obvious goal object
- ecology re-converges after interaction
- return route only becomes safe if the player prepares the chamber correctly

**Spotlight:** Aster interacts with the cache mechanism; Peris senses that the room is not truly safe just because the item is visible

**Dnd feel:** this is the room where the relic is on the pedestal and everyone at the table knows the hard part starts when somebody touches it

**Durable payoff:** sealant canister secured

**Headless needs:**

- verify the objective can be acquired
- verify acquiring it changes the return state
- verify a naive grab triggers an unsafe exit condition

## Encounter 8: Dual-Flure Finale

**Role in level:** set-piece finale and campaign promise resolution

**Primary insight:** chain two lure windows and one hide window to permanently reroute the siderophore pack away from Endo's junction

**Systems:**

- hide-lane style first lure
- second lure at a higher anchor
- sprint to shortcut crank or gate
- return to junction shelter

**Spotlight:** Endo's hide knowledge makes the sequence possible, Aster times the shifts, Peris is the final trust check when the visual information is incomplete

**Representative failures:**

- spend the first window greedily and never reach the second lure
- activate the second lure too late and get trapped between streams
- survive but fail to flip the ratchet, forcing a future repeat

**Durable payoff:**

- siderophore route permanently shifts away from the junction lane
- a safe return shortcut opens
- Endo's junction can now be sealed

**Candidate fragment ids:**

- `spiral_dual_lure_success`
- `spiral_dual_lure_first_window_failure`
- `spiral_dual_lure_second_window_failure`

## Encounter 9: Junction Return

**Role in level:** denouement and payoff

**Primary insight:** what was dangerous on the way up is now legible and partly domesticated

**Player experience:**

- the player returns via the shortcut
- Endo uses the sealant
- the level ends at shelter, reinforcing the "expedition session" rhythm

**Dnd feel:** the party gets back to camp changed, with a new route unlocked and a story to tell

## Fragment Decomposition

If we build this level from current methodology, the first fragment batch should be:

1. `spiral_split`
2. `spiral_first_lure`
3. `spiral_side_cache`
4. `spiral_upper_pursuit`
5. `spiral_cache_grab`
6. `spiral_dual_lure`

Each should have:

- one golden path
- one representative failure
- stable anchors
- explicit `headless_get_state()` probes

The regroup beats and narrative handoffs should be tested at sequence level rather than fragment level.

## Cognitive And Difficulty Arc

Early part of level:

- recognition-heavy
- one pressure source at a time
- Endo externalizes the survival logic

Middle part of level:

- player must remember the lure motif and route budget
- optional side room introduces greed tradeoff

Late part of level:

- prospective memory and timing combine
- player must track a small future plan instead of reacting room by room

Difficulty target:

- early-mid game
- tense but fair
- recoverable if the player skips the side room and plays cleanly
- more forgiving if they win the optional ATP cache

## Headless Test Plan

### Fragment Tests

- `spiral_split`: safe route succeeds with higher remaining ATP than direct route damage profile, while direct route is faster
- `spiral_first_lure`: exposed failure fails and hidden success succeeds
- `spiral_side_cache`: observed timing succeeds, greedy crossing fails
- `spiral_upper_pursuit`: correct retreat pocket survives, dead-end retreat fails
- `spiral_cache_grab`: objective can be collected, naive grab creates unsafe return
- `spiral_dual_lure`: only the intended sequence flips the ratchet

### Sequence Tests

- `level_golden_path`: main path without side room succeeds from intended starting ATP
- `level_low_margin_path`: main path barely succeeds when the player chooses the direct route once
- `level_side_room_buffer`: side room path succeeds with larger final margin
- `level_skip_guard`: cache cannot be reached by bypassing the first lure sequence
- `level_ratchet_persistence`: after finale success, return shortcut state remains open

### Sweep Questions

- what starting ATP values allow the main path without optional side room?
- how much lure duration margin is actually needed in the dual-lure finale?
- does the side room meaningfully widen the success envelope without becoming mandatory?
- do safe/direct route choices in the first split change the finale in a legible way?

## Narrative Texture

Because this is meant to feel like a campaign session, the level should include small moments of party identity:

- Endo quietly noticing which hide pockets are still intact
- Aster over-trusting the schematic early, then deferring more later
- Peris being the one who says the cache room feels wrong before the trap state flips

These do not need long cutscenes. Short pre-barks, arrival lines, and shelter payoff are enough.

## Why This Level Is A Good First Build

It is a good candidate for implementation because:

- the core geometry can be simple and modular
- the vertical spiral naturally supports DnD-style encounter sequencing
- the main systems are already in prototype or showcase form
- the level promise is clear
- the durable payoff is concrete
- it decomposes into headless fragments cleanly

If we decide to build it, the next practical step is to convert the six core encounter beats into fragment briefs and then into a new catalog plus sequence-level integration tests.
