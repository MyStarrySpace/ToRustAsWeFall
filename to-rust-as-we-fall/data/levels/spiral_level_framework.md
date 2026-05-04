# Spiral Level Framework

This document defines the default structure for a full spiral level.

It exists to answer three related goals:

- make levels feel like expeditions with a camp at the center
- let us mix survival beats and puzzle beats without losing coherence
- make the level shape easy to reason about and test headlessly

## Core Shape

A spiral level is built around a **central shelter hub**.

The party does not simply move linearly from left to right. They spiral around or away from the shelter, opening shortcuts back toward it over time.

The player experience should feel close to:

- Elden Ring or Dark Souls shortcut logic
- a DnD dungeon with a camp or safe room
- Rain World style resource pressure between safe rests

The shelter is not just a save point. It is the emotional and structural center of the level.

At shelters we:

- eat
- recuperate
- stabilize ATP and the party state
- checkpoint progress
- reframe the next objective
- feel the party as a party instead of as a bundle of mechanics

## Why The Shelter Is In The Center

Putting the shelter in the center does several jobs at once:

- it gives the level a navigational anchor
- it makes shortcuts meaningful because they bend back toward safety
- it makes repeated passes through the level feel cumulative rather than repetitive
- it supports the DnD-campaign feeling of pushing outward from camp and returning changed
- it keeps survival and puzzle content in the same structural rhythm
- it lets us refresh hub-space with state changes so the center stays alive instead of turning dull

The player should repeatedly gain the feeling:

- "We're pushing farther from camp."
- "If we can just unlock that door, the next attempt will be shorter."
- "We made the space safer than it was before."

## Level Promise And Spatial Thesis

Every spiral should be writable as three statements before room drafting begins:

- **level promise:** what the player thinks they are trying to accomplish
- **spatial thesis:** what the layout is teaching them to feel, notice, or master
- **durable change:** what becomes permanently safer, shorter, or more knowable after success

Examples:

- "Climb away from camp while always seeing the return path below."
- "Cross exposed hazard lanes by reading refuge pockets and timing the ecology."
- "Turn a deadly branch into a dependable supply route."

If a node does not support one of those three statements, it is probably filler.

## Node Types

A spiral is made out of nodes, not just corridors.

Later levels should deliberately mix different node types instead of making every stop a puzzle room.

### 1. Shelter Node

The safe center.

Typical functions:

- rest
- eat
- recover
- save
- dialogue regroup beat
- loadout and route planning

### 2. Survival Node

A room or lane where the main question is endurance, resource tradeoff, or safe passage.

Typical functions:

- ATP or stamina pressure
- food or water acquisition
- hazard routing
- hiding
- shelter-distance judgment
- short-term survival decision making

Typical result:

- keeps the expedition alive
- widens or narrows the margin for later puzzle nodes

### 3. Puzzle Node

A room or lane where the main question is durable change or a specific insight.

Typical functions:

- reroute ecology
- open a gate
- establish a ratchet
- decode contradictory map layers
- activate a device in the correct sequence

Typical result:

- changes the future state of the level
- unlocks a route
- resolves a structural obstacle

### 4. Mixed Node

A room where survival pressure and puzzle logic are both active, but one is still primary.

Use this when:

- the player must solve while under pressure
- a known motif is being recombined with attrition
- the level is moving toward a set-piece

### 5. Shortcut Node

A door, ladder, gate, flora bridge, crank, or terminal-controlled route that reconnects an outer loop to the shelter or a prior branch.

At first, shortcuts should usually be:

- seen before they are used
- locked before they are unlocked
- legible as future relief

The player should think:

- "If we survive long enough to open that, the whole level changes."

### 6. Set-Piece Node

The finale or signature encounter for the level.

Typical functions:

- resolve the level promise
- combine previously taught motifs
- open the most meaningful shortcut
- produce a memorable story beat

## Wayfinding And Mental Maps

Players need to be able to build a mental map of the spiral quickly.

Each full spiral should intentionally define:

- **paths:** the main expedition spine and fallback routes
- **edges:** the boundaries that separate safe from unsafe or known from unknown
- **districts:** branches or floors with distinct visual and systemic identity
- **nodes:** clear re-orientation points where the player chooses or reassesses
- **landmarks:** the shelter plus one or two outer promises visible, audible, or otherwise referenceable from multiple places

At each meaningful choice point, use at least one strong cue and one supporting cue.

Strong cues:

- framed sightline or silhouette
- lighting or color contrast
- sound or motion
- party bark or diegetic signage

Supporting cues:

- floor wear, rails, pipes, or cable direction
- enemy or ecology movement
- repeated landmark alignment

Rules of thumb:

- the shelter should be referenceable from multiple nodes, even if only by light, sound, or shaft glimpses
- shortcuts should be previewed before use whenever possible
- optional routes should read as tempting, not mistaken for dead progress
- each junction should communicate one dominant directional message, not three competing ones
- if the player cannot tell where the next refuge pocket is, the area is under-authored

## Layout As Teacher

A spiral should teach like a natural tutorial without feeling like a tutorial.

Default teaching ladder:

1. introduce a rule or motif in isolation
2. preview the later payoff or inaccessible route
3. recombine the same idea under pressure

During introduction:

- remove unrelated distractions
- remove extra threats
- make success require the actual intended technique

During recombination:

- add only one new stressor at a time
- prefer physical circumstance before timer pressure
- use time pressure sparingly
- make the finale spend earlier lessons instead of introducing a completely new rule

This is how the level earns a sense of fairness.

## Recommended Spiral Rhythm

A good default spiral level uses this rhythm:

1. Shelter briefing or departure
2. Early survival node
3. Early puzzle node
4. Shortcut sightline without access
5. Midpoint regroup or overlook
6. Optional side node
7. Harder mixed node
8. Finale set-piece
9. Shortcut unlock
10. Return to shelter

Not every level needs every step. This is the baseline cadence.

## Prospect, Refuge, And Beat Contrast

Spirals work best when exposed spaces and safe pockets are intentionally contrasted.

- **refuge spaces** let the player observe, regroup, and plan
- **prospect spaces** expose the player and demand commitment

In our structure:

- the shelter is maximum refuge
- a hide nook or overlook is partial refuge
- a catwalk, chase lane, or open hazard band is prospect

Default cadence rule:

- after a major prospect beat, give the player at least a partial refuge beat before the next major commitment, unless the level is intentionally entering climax compression

This keeps tension legible instead of flattening the whole level into one undifferentiated stress state.

## Locked Shortcut Rule

Shortcuts should feel like Elden Ring shortcuts, not arbitrary keycards.

That means:

- the player usually sees the shortcut before they can use it
- its relationship to the shelter is spatially legible
- unlocking it feels like earned mastery over the space
- it reduces retry friction and future traversal cost

Good shortcut examples:

- crank-operated gate back to the shelter spine
- collapsed membrane wall repaired from the far side
- flora bridge grown only after Peris tends a node deeper in the level
- powered lift activated from an outer maintenance station

Bad shortcut examples:

- a door that only exists as a menu flag
- a route that teleports the player with no spatial understanding
- a "shortcut" that barely saves time and changes nothing emotionally

## Loop Value Rule

Loops are useful because they make authored progression feel less blatantly linear while still guiding the player back toward meaningful goals.

A good spiral loop should do at least one of these:

- shorten retry distance
- reveal a new perspective on a known space
- convert a former danger route into a safer return
- let the player re-evaluate an earlier objective with better knowledge

Avoid loops that:

- exist only to pad travel time
- return the player with no new understanding
- undermine a level whose emotional point is one-way departure rather than return

## Survival Versus Puzzle Distribution

Later spirals should contain both survival nodes and puzzle nodes.

They should not be evenly alternating by formula. They should be distributed according to the level's promise and emotional arc.

Useful distributions:

- Early level: more survival nodes, fewer puzzle nodes, high guidance
- Mid level: balanced survival and puzzle nodes, more optional routes
- Late level: fewer but harder survival nodes, more mixed and set-piece puzzle nodes

Rule of thumb:

- survival nodes tax the expedition
- puzzle nodes justify the expedition

Without survival nodes, the level loses weight.
Without puzzle nodes, the level loses memory.

## Optional Route Rule

Optional branches should buy something meaningful.

Good optional payoffs:

- resource forgiveness
- information that changes later confidence
- a safer or faster return route
- party spotlight or world texture that strengthens the campaign feeling

If an optional branch adds risk but does not widen any future margin, reduce future friction, or deepen the level's identity, cut it or merge it into the critical path.

## Readability Budget

When the player enters a node, they should be able to answer most of these within a few seconds:

- where is the next refuge?
- what is the immediate danger?
- what durable opportunity exists here?
- what changed since the last pass, if this is a revisit?

If a room is trying to introduce a mechanic, branch the route, threaten the player, and hide the next landmark all at once, it is likely doing too much.

## Party Spotlight Across Nodes

A spiral level should use node distribution to make the party feel specialized.

Examples:

- Endo shines in shelter, hide, food, water, and route-survival nodes
- Aster shines in terminal, systems, and abstraction-heavy puzzle nodes
- Peris shines in memory, sensory trust, flora, and contradiction nodes
- Tyreg shines in patrol-timing nodes
- Myke shines in route-memory and infrastructure nodes
- Oli shines in connectivity, power, and controlled-shortcut nodes

The player should remember a spiral partly by who owned which room.

## Headless Testing Implications

A spiral level should be testable at two scales:

### Node Scale

Each survival or puzzle node should have its own fragment-style tests:

- success path
- representative failure
- key state probes
- critical unlock assertions

### Sequence Scale

The full spiral should also have sequence tests:

- expected order of nodes
- correct resource carryover into key encounters
- locked shortcuts start locked
- shortcut unlocks persist once opened
- return-to-shelter route is actually shorter after unlock
- shelter state is reached after intended success path

### Playtest Scale

Headless tests prove logic. Playtests prove readability, pacing, and emotional cadence.

Each spiral should also be checked in rough form for questions like:

- can players sketch the shelter, key shortcut, and outer goal after one run?
- do players understand why a shortcut matters before they unlock it?
- where do they hesitate or spin the camera at junctions?
- which nodes do they describe as safe, unsafe, optional, or confusing?
- does the midpoint relief actually feel like relief?

## What To Remember While Building

The player is not just clearing content.

They are:

- leaving camp
- taking a risk
- learning the ecology of the space
- opening a way home
- returning to shelter with something changed

That is the emotional grammar of the spiral.

## Research References

- [Joel Burgess, Matt Scott, and Lee Perry, "Level Design Workshop: Layout Fundamentals"](https://media.gdcvault.com/gdcchina14/presentations/833762_JoelBurgess_MattScott_LeePerry_2_Layout_EN.pdf)
- [Valve, "Loops (level design)"](https://developer.valvesoftware.com/wiki/Loops_%28level_design%29)
- [Valve, "Valve's Design Process for Creating Half-Life 2"](https://cdn.steamstatic.com/apps/valve/2006/GDC2006_HL2DesignProcess.pdf)
- [Justin Reeve, "Prospect and Refuge"](https://www.gamedeveloper.com/design/prospect-and-refuge)
- [HOK, "Wayfinding Primer"](https://www.hok.com/ideas/publications/hok-experience-design-wayfinding-primer/)
- [The Level Design Book, "Wayfinding"](https://book.leveldesignbook.com/process/blockout/wayfinding)
- [Cornell Game Design Initiative, "Level Design" lecture notes](https://www.cs.cornell.edu/courses/cs3152/2020sp/lectures/24-LevelDesign.pdf)
