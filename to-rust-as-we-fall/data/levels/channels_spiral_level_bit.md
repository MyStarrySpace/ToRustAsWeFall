# Channels Spiral Level Bit

This document reframes the current Channels sequence as a proper shelter-centered spiral level bit.

It is built from:

- the current `act1_sequence.gd` implementation
- the dialogue revision notes in `channels_edits.md`
- the ferrolure and hide-run design already prototyped in the tutorial flow

The aim is to make the first `channels` section feel like a real expedition slice instead of a straight tutorial corridor.

## Level Promise

Get the party through the channels, learn how ferrolures and hiding turn the ecology, and reach the shelter at the center before the route closes on you.

This is a small level bit, not a whole standalone region. It is the first example of the spiral grammar the game will reuse later.

## What This Bit Needs To Teach

This bit should establish:

- Peris's memory can lead the party before anyone comments on it
- the world outside the portal is materially harsher than Peris was allowed to feel
- ferrolures are not just interactables, they are ecological levers
- the player can survive by reading rhythm and setting up the space
- Endo's shelter and hide knowledge is a real party role
- shelter is the center of the loop, not just the end of a hallway
- shortcuts back to shelter are earned from the far side

## Relationship To Current Act 1 Sequence

The current runtime sequence already contains almost all of the needed pieces:

- `channels_enter`
- `channels_memory`
- `channels_corpse`
- `channels_ferrolure`
- `channels_encounter_activate`
- `channels_encounter_hide`
- `channels_encounter_run`
- `channels_shelter`

What changes here is not the emotional content. It is the spatial and structural framing.

## Revised Spatial Model

The Channels should be treated as a **partial spiral wrapped around a central shelter core**.

The player begins on the outer arm of the spiral, moves through a sequence of nodes, and reaches the central shelter from the far side. Once inside, they unlock a shortcut back toward the route they used to arrive.

That means the player should feel:

- the shelter exists before they reach it
- the shelter is spatially central
- the route to it is obstructed by ecology and survival logic
- reaching it transforms the space from hostile route into usable loop

## Topology

### Center

- shelter core
- eating and recuperation
- checkpoint and regroup beat
- inner shortcut door that opens from the shelter side

### Outer Path

- entry lane
- memory/body lane
- first ferrolure rhythm lane
- second ferrolure coda
- hide-and-run lane

### Shortcut Logic

At least one route back to the shelter should be visible but locked earlier in the bit.

The default implementation should be:

- the player sees a shelter-adjacent gate or membrane wall earlier
- they cannot open it from the approach side
- after reaching the shelter, Endo opens or gestures through the inner side
- future retries or returns become much shorter

That is the first "Elden Ring shortcut" lesson.

## Node Breakdown

## Node 1: Channel Mouth

**Type:** survival-narrative node

**Current sequence:** `channels_enter`

**Purpose:**

- establish the channels as a place with readable rhythm
- let Aster give a narrow systems observation
- let Peris answer in character rather than in tutorial language

**Dialogue spine from notes:**

- narration: flowing water reads cleaner where it moves
- Aster: "Flow rate correlates with atmospheric quality. Don't quote me on the mechanism."
- Peris: "So, just go with the flow?"

**What the player learns:**

- flow matters
- the zone has a rhythm
- the tone is not purely tactical yet

## Node 2: Memory Body Lane

**Type:** narrative-perception node

**Current sequence:** `channels_memory`

**Purpose:**

- introduce Peris's memory-leading ability without over-explaining it
- establish a baseline for later memory decline

**Dialogue spine from notes:**

- Peris: "I know this place."
- Aster: "We haven't been down here."
- Peris: "No. But I saw it."

**Important rule:**

Peris leads. Aster and Endo do not underline what the player should already be noticing.

## Node 3: Corpse Harvest Lane

**Type:** survival-narrative node

**Current sequence:** `channels_corpse`

**Purpose:**

- make the cost of survival concrete
- let Peris discover what mediation hid from her
- let Aster and Endo reveal class and coping differences through action and vocabulary

**Dialogue spine from notes and current sequence:**

- Endo eats
- Aster recommits to filing the report
- Peris reacts to the smell
- Peris realizes this is what her clients were eating
- Aster deflects with `lysate` language
- Peris insists: "These were people."
- Aster answers: "They were. And we're hungry."

**What the player learns:**

- survival here is ugly and practical
- language reflects class position
- the shelter they are moving toward is not abstract comfort, it is needed

## Node 4: Ferrolure Rhythm Lane

**Type:** puzzle-teaching node

**Current sequence:** `channels_ferrolure`

**Purpose:**

- show the player that ferrolures can alter ecological flow
- make the player read environment rhythm rather than react in panic
- transition from corpse-horror back into tactical attention

**Beat shape from notes:**

- Peris notices the dormant or partial ferrolure
- Aster warns: "That's a lure."
- Peris answers: "Nothing's around to receive its signals."
- pause
- Peris touches it
- it responds to her

**Mechanic shape we should preserve:**

- the channel powers on or surges in a readable cadence
- siderophores are drawn into the flushed lane
- the player sees lure -> attract -> washout as a legible sequence

**Structural lesson:**

The space can be prepared. Ecology is a system, not just an enemy.

## Node 5: Shortcut Sightline

**Type:** shortcut node

**Current implementation status:** implied, not yet formalized

**Purpose:**

- let the player see the shelter-adjacent shortcut before it is usable
- spatially tie the outer path to the shelter center
- make the eventual unlock feel earned

**Suggested presentation:**

- a barred membrane gate
- a locked maintenance hatch
- a shelter light glimpsed through a grate

The player should understand:

- "That goes to safety."
- "We are not allowed in from this side yet."

## Node 6: Hide-And-Run Lane

**Type:** mixed survival-puzzle node

**Current sequence:** `channels_encounter_activate` -> `channels_encounter_hide` -> `channels_encounter_run`

**Purpose:**

- teach hiding
- teach that ferrolures create later movement windows, not immediate escape
- give Endo a strong survival-guide spotlight

**Current implementation surface already contains:**

- lure marker
- hide marker
- shelter marker
- hide alcove
- swarm cluster
- lure dwell activation
- failure reset

**Desired framing in the level bit:**

- the hide-and-run node is the last outer-arm obstacle between the party and the shelter core
- the player now understands enough to plan, wait, and commit
- failure should not feel like total loss because the shelter shortcut is what they are about to earn

## Node 7: Shelter Core

**Type:** shelter node

**Current sequence:** `channels_shelter`

**Purpose:**

- complete the first spiral loop
- let the party eat and recuperate
- establish shelter as the center of future spiral logic

**What must happen here:**

- the shelter reads differently from the rest of the channels
- the party pauses
- eating and recuperation are part of the fiction, not just menu bookkeeping
- a shortcut back outward is unlocked from the shelter side

**Shortcut payoff:**

Once inside, Endo opens the inner gate. From that point on, the route from shelter back to the earlier channels arm is short and legible.

That teaches the player the deeper rule:

- solving the level makes future survival easier

## Exact Structural Arc

The Channels bit should now read like this:

1. enter the outer arm of the channels
2. learn its rhythm
3. see Peris lead through memory
4. confront corpse-harvest survival reality
5. learn the first ferrolure rhythm safely
6. glimpse the central shelter but remain locked out
7. use hide-and-run to penetrate the inner route
8. reach shelter
9. eat and recuperate
10. unlock the shortcut from the inside

That is a complete mini-expedition.

## Why This Works As The First Spiral

It is still teachable because:

- each node introduces one major idea
- Endo externalizes survival knowledge
- the first ferrolure beat is safe and legible
- the hide-and-run is forgiving compared to later versions
- the central shelter gives a strong emotional payoff

It still feels like a real level because:

- the player pushes toward a known safe center
- the route contains both survival and puzzle logic
- a shortcut is earned from the far side
- the space is changed by traversal

## Survival Nodes Versus Puzzle Nodes In This Bit

The Channels bit should explicitly contain both:

### Survival-heavy nodes

- channel mouth
- corpse harvest lane
- hide-and-run lane
- shelter core

### Puzzle-heavy nodes

- ferrolure rhythm lane
- shortcut unlock

### Narrative-perception node

- memory body lane

This is the first example of the later rule:

- some nodes are survival
- some nodes are puzzle
- some are mixed
- all still belong to one expedition loop

## Future Spiral Rule

Later spiral levels should reuse the same grammar with more complexity:

- more optional side nodes
- more than one shortcut back to shelter
- distinct branches with different node types
- party-specific spotlights by branch
- shelter-to-shelter progression where each new shelter becomes the next spiral's center

The Channels bit is the smallest version of that structure.

## Implementation Notes

### What Already Exists

- the dialogue skeleton for the channels beats
- the current ferrolure coda beat
- the hide-run encounter logic
- the shelter destination

### What Needs Stronger Formalization

- visually reading the shelter as central before the player reaches it
- a locked-beforehand shortcut that opens from the shelter side
- shelter actions reading as eat / recuperate / regroup
- node framing so the bit feels like a loop around a center instead of a straight corridor

## Headless Testing Plan

For this bit, we should eventually test at two levels:

### Node tests

- ferrolure flush succeeds and clears the lane when timed correctly
- hide-and-run succeeds when hidden before lure expiry
- hide-and-run fails when exposed
- shelter node is reached only after successful encounter completion

### Sequence tests

- channels golden path reaches shelter in the expected order
- shortcut begins locked
- shortcut becomes unlocked once shelter is reached
- the unlocked route back toward the outer arm is shorter than the original approach

## What To Build Next

If we turn this from spec into content work, the next practical steps are:

1. make the shelter-centered shortcut explicit in the channels geometry and sequence
2. expose the shortcut state in headless scene state
3. split the current channels run into named nodes in the level spec
4. add sequence tests for "reach shelter, unlock shortcut, shorten retry path"

That gets us from "good tutorial corridor" to "first real spiral level bit."
