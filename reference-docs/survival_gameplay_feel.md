# Survival gameplay feel — design problem and direction

Working document for a dedicated design session. The survival loop is currently specified at a systems/colony-sim altitude (AI state machines, sensing radii, population dynamics). It needs to be redesigned at an experiential altitude (what the player sees, hears, and does with their hands second to second).

## The problem

The current GDD describes siderophore encounters through AI behavioral state machines, iron-sensing radii, scent decay curves, and population dynamics. These read like Rimworld combat specs — useful for implementation but silent on what the encounter feels like to play. A third-person 3D adventure game needs moment-to-moment tension, not spreadsheet optimization.

The question that needs answering: **What is the player doing with their hands in the three seconds before, during, and after a siderophore encounter?**

## Reference triangle

Three references for the survival feel. Each contributes a specific quality the game needs. None of them is "what the game is" — they're vectors pointing at what the game should feel like.

**Horror gameplay loop without the horror.** (Alien Isolation, Amnesia, Outlast.) The mechanical vocabulary: hiding from things that are searching for you, listening to environmental cues, managing limited resources under pressure, planning routes that minimize exposure, the tension between needing to move forward and the safety of where you are. Strip the horror affect (dread, grotesque death, violation) and keep the mechanical feel (tense presence, environmental reading, immediate physical decisions).

**Zelda-style improvisational toolkit.** (Breath of the Wild, Tears of the Kingdom.) The world is a system you can interact with in unscripted ways. Environmental tools combine to produce emergent solutions. A single problem usually has multiple valid approaches. The player who treats the world as a manipulable system is rewarded for creativity and lateral thinking.

**It Takes Two-style simultaneous multi-character engagement.** (It Takes Two, Brothers: A Tale of Two Sons.) Each character has distinct capabilities. Most problems require combining them. Both characters are always doing something — there's very little standing around waiting. The coordination is active, not passive.

These three references map to three scales of the same question: How do you survive minute-to-minute in a hostile environment (horror)? How do you change the environment over time so it's less hostile (Zelda)? How do you coordinate with other people to do work that no individual could do (It Takes Two)?

## The encounter decision tree

When the player sees a siderophore (or hears the clicking approaching), the decision tree is:

1. Can another character lure it away? (positional / loosest)
2. Can I reach a safe zone before it reaches me? (environmental / medium)
3. If it's already chasing me, can I break the pursuit? (pursuit-break / tight)
4. If none of the above, how do I minimize damage taken?

Each branch has a different feel, a different cost, and rewards different kinds of preparation.

## The hiding hierarchy

Three levels, ordered from cheapest to costliest. The hierarchy rewards preparation: a player who has invested in the world has access to cheaper options more often.

### Loosest: positional (get out of the way)

The player isn't hiding. They're just not being the most interesting iron source in the room. Another character has a stronger signal, or the player has dropped something more attractive than they are. The siderophore passes because something else is pulling harder.

**Feel:** Traffic management. Reading the iron-gradient landscape and positioning yourself in the low-signal zone. The skill is spatial awareness and party positioning.

**Mechanic:** Switch to another character, walk them into a position where their iron footprint draws the cluster. Or drop lysate as a decoy. Or simply stand still while a higher-iron party member (Oli, Myke) is closer to the siderophore's current path.

**Cost:** Nothing. No resources spent, no time lost, no infrastructure needed. Just awareness.

**Coordination:** This is where the It Takes Two reference lives. The player is thinking about all three characters' positions simultaneously, even though they're only controlling one. The switch itself is the action.

### Medium: environmental safe zones (flora patches, portals)

The player moves into an area that Peris has tended, or steps through a portal. The siderophore loses detection ability in this zone — the flora interferes with the iron gradient, masking the party's scent.

**Feel:** Zelda toolkit payoff. The player is using infrastructure they built over time. The flora network isn't atmosphere; it's a tactical resource that changes how encounters work.

**Mechanic:** Flora patches (Rustmoss, or a dedicated scent-masking species) cover sections of corridor floor or junction space. When a party member is inside the patch's area, their iron scent is masked. Siderophores in Idle or Foraging state won't enter the zone — the flora confuses their sensing. But siderophores already in Pursue state (locked on and chasing) will follow the party into the zone. Inside the zone, the pursuit degrades over time — the siderophore gradually loses the signal and transitions out of Pursue. How quickly pursuit breaks depends on the flora's health (well-tended = faster break, neglected = slower).

**The "won't enter unless already chasing" rule:** A siderophore wandering near a tended flora patch reads the zone as empty/confusing and routes around it. A siderophore actively chasing a character follows them in but loses the thread over time. This means flora zones are preemptive safe corridors (the reward for tending) but not instant pursuit-breaks (the player still needs to survive the seconds inside the zone while pursuit degrades).

**Portals:** Stepping through a portal puts the player somewhere the siderophore can't follow (no portal access). Similar to flora zones but binary — the siderophore can't enter at all. The cost is that portals are fixed infrastructure, not something the player builds.

**Cost:** Peris's tending investment over time. The player who has been doing Peris's care work has medium-hide options everywhere they've tended. The player who hasn't is limited to whatever wild flora exists.

**Flora as area/terrain:** Flora patches function as terrain zones with properties. A Rustmoss patch covers a section of corridor and masks iron scent within its area. A Lumivine cluster fills a junction with biological noise that dampens siderophore detection. Peris builds zones through tending, not just individual plants.

### Tight: pursuit-break (doors, alcoves, maintenance closets)

The player is being actively chased. No other character is pulling the cluster away. No flora zone is close enough. The player needs to mechanically break the pursuit.

**Feel:** The horror moment. Get inside, slam the door, hear the clicking on the other side, wait. The tension is in the waiting and in the uncertainty about when it's safe to open the door.

**Mechanic:** The player reaches a tight hide spot (maintenance alcove, small room, closet) and enters. The door closes. Siderophores cannot pass through a closed door. They transition from Pursue to Investigate (move to last known position), then Search (circle the area), then Scatter (drift away). The player waits inside until the search cycle ends.

**Cost:** Time and position. The player is locked in a small space for the duration of the search cycle (several seconds to maybe 15-20 seconds depending on cluster size and agitation). They've stopped progressing. They may have left other party members exposed outside.

**Limited capacity:** Tight hide spots have a character limit. A maintenance alcove might fit one character. A small room might fit two. A three-person spot is rare. If the player has a three-person party and the tight spot fits two, someone stays outside. The player chooses who gets saved.

This is a survival decision that is also a character decision. Hide Peris because she carries a cure component and is fragile? Hide Endo because he's carrying starch the party needs? Hide whoever you're currently controlling because panic? The capacity limit forces the choice.

**The game doesn't tell you "all clear."** The player has to open the door and check whether the siderophores have left. The clicking (or its absence) is the only cue. Listening through the door is the skill.

### Branch 4: damage mitigation (when hiding fails)

The siderophore is on you. It's latched and draining. Options:

- **Dodge roll** to shake off latched siderophores (costs stamina)
- **Sprint away** to break sensing range (costs stamina, generates scent if carrying lysate)
- **Switch characters** to pull the cluster's attention with a higher iron signal elsewhere
- **Use a consumable** (fire-fruit thrown to create a thermal zone they avoid, flure seed dropped to create a competing lure)
- **Myke's fire** (effective but loud, may attract other entities, has area consequences)

This branch should feel frantic but recoverable. Not a death spiral. The player made a positioning mistake, they're paying for it in HP and resources, but they have options. Every option costs something.

## Flora patch design questions (for this session or the next)

### What does a flora patch mask?

Options:
- **Lysate scent only.** The carried-food signal is masked, but body iron (Oli, Myke) still broadcasts. Flora zones are safe for low-iron characters but not for high-iron ones.
- **All iron signal.** Body iron and carried lysate are both masked. Flora zones are true safe zones for anyone inside.
- **Partial masking.** Flora reduces the iron signal strength within the zone. Low-iron characters become undetectable; high-iron characters become harder to detect but not invisible. Cluster size and proximity determine whether the masking is sufficient.

The third option is probably richest. It means party composition matters even inside a safe zone. Sending Peris alone through a tended corridor is safe. Sending Peris and Oli together through the same corridor is risky because Oli's signal leaks through the masking.

### How do patches grow?

Options:
- Peris plants a seed that grows into a small patch over time (hours of in-game time)
- Peris tends an existing wild patch to expand it
- Both (plant new, tend to expand, expansion takes time)

Patches should be persistent and grow slowly. The player's flora network is a long-term investment that pays off over many shelter cycles. Rushed tending doesn't produce instant results.

### Can patches be destroyed?

Yes. By:
- Myke's fire (instant, accidental or deliberate)
- Candid colonization (the Candid's growth competes with and overtakes Peris's flora)
- Siderophore activity (heavy siderophore traffic through a patch degrades it over time)
- Neglect (untended patches slowly shrink back to wild state)

Destruction of a flora patch is a real loss. The player who accidentally burns a Rustmoss zone with Myke's fire has lost a safe corridor that took real investment to build. The game's "Peris's work matters" thesis includes "Peris's work can be undone."

### What determines patch size?

Tending time and species. Each flora species has a maximum patch radius. Well-tended patches grow toward that maximum. Neglected patches shrink. Different species cover different areas: Rustmoss might cover a corridor section (long, narrow), Lumivine might cover a junction (roughly circular). The shape matches the species' biology.

### Can the player see the patch boundary?

Yes. The flora is visible. Rustmoss is a visible patch of growth on the corridor floor. Lumivine glows. The player can see where the safe zone starts and ends. The boundary should be legible at a glance during movement, not something the player has to stop and check.

Peris's overlay shows patch boundaries more precisely (exact radius, health state, signal-masking strength). Aster's overlay might show the iron gradient and where it drops off within the patch. Both overlays give more information than the raw visual, but the raw visual is sufficient for tactical decisions.

## Tight hide capacity design questions

### How often do tight spots appear?

This is a map density question. If every corridor has a maintenance alcove every 30 meters, tight hiding is always available and the capacity limit is the main constraint. If tight spots are rare (one per corridor section, maybe 100 meters apart), reaching one in time is a challenge and the player has to memorize their locations.

The right density is probably: common enough that the player usually has one within sprinting distance, rare enough that they can't rely on it as the default strategy. Tight hiding should be the emergency option, not the routine.

### Standard capacity distribution

- **One-person alcoves:** Most common. The player hides one character, the others are exposed.
- **Two-person rooms:** Less common. Found at corridor junctions or in areas with more built infrastructure.
- **Three-person rooms (full party):** Rare. Probably at or near shelter locations. Finding one mid-corridor is a relief.

The distribution means: in most encounters, if the player resorts to tight hiding, someone is staying outside. The "who stays out" decision is a regular occurrence, not an edge case.

### What happens to characters left outside?

If the player hides one character and the other two are outside, the outside characters are subject to whatever threats are in the corridor. If they're in a low-signal position (loosest hide), they might be fine. If they're in an exposed position with siderophores bearing down, they're taking damage.

The player can switch to an outside character and try to manage their situation while the hidden character waits. This is active multi-character management during a crisis — exactly the It Takes Two reference.

If an outside character goes down while the hidden character is waiting, the hidden character hears it (muffled sound through the door). They have to decide: stay safe, or open the door to help? Opening the door re-exposes them to whatever is in the corridor. Staying means the downed character is on their own until the threats pass.

## Character switching design questions

### How fast is the switch?

Single button press. Immediate camera snap to the new character's position. No menu, no confirmation. The player should be able to think "Endo, go left" and execute it in under a second.

The speed of switching IS the gameplay for the loosest hide level. If switching is slow, the player can't use positional management in real-time encounters.

### What do non-controlled characters do?

When the player is controlling one character, the other two need autonomous behavior. Options:

- **Hold position.** They stay where they were when the player switched away. Simple, predictable, but means the player has to manually position everyone.
- **Follow at distance.** They trail the controlled character, staying a set distance behind. Convenient for traversal but means the party is always grouped, which limits positional play.
- **Context-sensitive.** They follow during traversal but hold position during encounters (when threats are detected nearby). The switch from follow to hold is automatic based on threat proximity.

The third option is probably richest. During calm traversal, the party moves as a group. When siderophores are detected, the non-controlled characters freeze in place, and the player manages from there. This gives the player a starting position for each character that they can then adjust by switching.

### Can non-controlled characters take damage?

Yes. A non-controlled character in the path of a siderophore cluster takes damage. The player sees the damage indicator (health bar ticking down, audio cue). This creates urgency to switch and deal with the situation.

A non-controlled character who reaches zero HP goes down. They're unconscious. They need to be dragged to shelter or revived. If they're carrying a cure component, the component is inside their unconscious body in a hostile corridor.

## Camera design questions

### Distance and angle during encounters

Close enough to read the immediate environment for hiding spots. Far enough to see approaching threats. Probably a close third-person camera (slightly further than Resident Evil 4 remake, closer than God of War) that can pull back slightly when the player is scanning for cover.

The camera should convey embodiment. The player is a person in a corridor, not a general commanding units. The tension comes from not being able to see everything at once.

### Camera during character switch

Snap to the new character's position and orientation. Brief transition (0.2-0.3 seconds) so the player orients to the new viewpoint. The snap should feel responsive, not cinematic — this is a tactical tool, not a cutscene.

### Camera during tight hide

Inside the alcove or room, the camera is close and constrained. The player can look at the door. They can hear what's outside. The camera doesn't show them what's on the other side of the door — they have to listen, then open it and look.

## Sound design load

Sound carries a huge part of the survival feel. Specifically:

- **Sapscrap clicking** tells the player where threats are and how many
- **Clicking cadence change** signals state transition (Idle → Pursue sounds different from Idle → Foraging)
- **Silence** after hiding signals Search state ending
- **Distant clicking resumption** signals return to Idle (safe to emerge)
- **Muffled clicking through doors** during tight hide (the horror moment)
- **Character damage audio** for non-controlled characters taking hits elsewhere

The player who learns to read audio can navigate encounters by ear. This is the horror reference's specific contribution — in Alien Isolation, listening is the primary survival skill.

## Connection to the game's thesis

The hiding hierarchy mechanically expresses the game's core argument: **the world is safer when you've cared for it.**

- The player who has invested in Peris's flora network has medium-hide options everywhere they've tended. Their survival is easier because they did care work.
- The player who hasn't invested relies on spatial awareness (loosest) or emergency brakes (tight). Their survival is harder and more moment-to-moment.
- The flora network is persistent infrastructure that rewards long-term thinking. Rushing through the game without tending means every encounter is an emergency. Taking time to tend means encounters have built-in escape routes.

This is the thesis expressed through encounter design: care work has mechanical value. Peris's tending isn't a side activity; it's the thing that makes the world survivable.

## Open questions for the dedicated session

- Exact flora species that provides scent masking (existing species like Rustmoss, or a new species?)
- Masking strength model (binary, partial, or signal-reduction?)
- Tight hide search-cycle duration (how long do siderophores investigate before leaving?)
- Character switching autonomous behavior model (hold, follow, or context-sensitive?)
- Map density rule for tight hides (spacing, capacity distribution)
- Whether the player can create new tight-hide infrastructure (blocking corridors, growing flora across doorways)
- Damage model for non-controlled characters (same as controlled, or reduced?)
- Camera distance and behavior spec
- How the encounter feel differs between early game (mostly Sapscraps, simple encounters) and late game (mixed species, complex encounters)
- Whether any of this changes in the Inflammashunt DZ or other puzzle-specific contexts
- Controller mapping for character switch (which button, any modifiers?)

## Additional encounter information sources

### Lookout (another character watching)

Listening through a door isn't the only way to know when it's safe. If the player has positioned another character with line of sight to the corridor outside the tight hide, that character can serve as a lookout. The player switches to the lookout, checks the corridor visually, switches back.

This turns the tight-hide moment from a solo horror beat into a coordination beat. One character hides, another watches. The lookout doesn't have to be safe themselves — they might be in a loose-hide position behind an outcrop, watching the siderophore cluster drift away while Peris is behind a door.

The lookout option also means the player has a reason to position characters before an encounter escalates to tight-hide. If you know a corridor has siderophore traffic, you might pre-position Aster at a vantage point before sending Peris through. When things go wrong and Peris hides, Aster is already in position to report.

This adds a planning layer to the encounter flow. The player who thinks ahead has more information during the crisis than the player who reacts.

### Four-hand carry (two-character vulnerability)

Some items require four hands — two characters carrying together. The Mother Flure gear is one example (currently specified as two-hand carry for Endo alone, but larger items elsewhere in the game could require paired carry). When two characters are carrying a four-hand item, they're locked together, moving at reduced speed, and neither can use abilities.

This creates a specific encounter texture: two characters are vulnerable and committed, the third character is the only one free to manage threats. The free character becomes the scout, the decoy, the lookout, and the door-opener all at once. Every encounter during a four-hand carry is a crisis for the solo free character.

Four-hand carries through siderophore-dense corridors are set pieces. The player knows they have to cross a section with two characters locked and one character doing everything. The planning that goes into which character stays free, what route to take, which flora patches are available, and where the tight-hide spots are (that fit one person, since the two carriers can't separate) is the encounter design at its most demanding.

The four-hand carry is also where the It Takes Two reference is strongest. Two characters doing something together that neither could do alone, while a third provides support. The coordination is physical and spatial and immediate.

## Related documents

- `techos_species_doc.md` — AI behavioral specification (the systems layer this doc complements)
- `mother_flure_spec.md` — first puzzle where multi-character coordination is fully specified
- `mother_flure_dialogue.md` — scene-level dialogue for the chamber
- `inventory_and_endocytosis.md` — the two-hand carrying and consumption system
- `to_rust_gdd_v01__7_.md` (project file) — sections 3.2 (food/scent), 6.1-6.2 (entity behavior)
