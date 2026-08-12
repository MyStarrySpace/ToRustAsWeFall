# Design Archetypes for TRAWF: Implementation Reference

## Purpose

This document is the working reference for the archetype-based design system used in TRAWF (To Rust As We Fall). Content (puzzles, encounters, danger zones, narrative beats) is composed by nesting and chaining archetypes. Each archetype is a procedural template with internal steps and variant trees.

Use this document when generating new content. For each piece of content:

1. Identify the macro-archetype that fits the content type
2. Choose variants
3. Identify nested archetypes for individual steps
4. Identify chained archetypes for setup or payoff
5. Ensure shadow-solution feasibility (Aster + Peris alone can complete the content)
6. Connect to canonical worldbuilding in `to_rust_gdd_v02.md`

The system has four scales: puzzle archetypes (1-8), meta-archetypes (9-11), enemy archetypes, and construction patterns (nesting and chaining).

Variant code notation: "Archetype 3-A-i" means Archetype 3 (Carry the heavy thing) with variant A-i (by what is carried: cure component or fragment).

## Puzzle archetypes

### Archetype 1: Redirected enemy aggression

Lure an enemy toward a target, dodge at the right moment, and the enemy charges into a structure the party needs to break, damage, or destroy.

Steps:
1. Identify the structure that needs to be broken, damaged, or activated by enemy impact.
2. Position the bait character within the enemy's aggro range, with the target structure on the line between the bait and the enemy's charge path.
3. Trigger the enemy's charge or attack (movement, line-of-sight, sound, depending on enemy type).
4. Dodge at the moment the enemy commits to its strike.
5. Enemy collides with the target, producing the desired state change.
6. Use the resulting state.

Variants:
- A. Destroy a structural barrier (opens traversal).
- B. Kill the enemy (combat resolution via self-collision).
- C. Destroy a cage or blockade revealing: i. a plant, ii. a terminal, iii. a passage, iv. a character.
- D. Activate a mechanism through impact.

### Archetype 2: Plant as tool

Use a planted flora to manipulate the environment or enemies. Variants by species reflect the flora taxonomy in GDD section 8.

Steps:
1. Acquire the plant or seed (harvest, gift, environmental source, or Peris's inventory).
2. Identify the target location for the plant's effect.
3. Plant the seed (typically Peris's class-gated ability for some species).
4. Wait for growth or trigger the plant's effect. Some plants activate on proximity (Hushbloom); some require time to mature (Climbvine); some attract enemies immediately on planting (Flure); some require multi-step tending (Resolution Roots).
5. Use the plant's effect.

Variants:
- A. Flure (iron decoy): i. pull enemies from carrier, ii. pull from terminal-access window, iii. cluster into kill zone.
- B. Hushbloom (proximity stun): i. trap on patrol path, ii. last-resort defense, iii. combat window opener.
- C. Climbvine (traversal): i. bridge gap, ii. reach height, iii. camouflage slope.
- D. Resolution Roots (puzzle-only flora): i. stabilize structure, ii. break structure.

### Archetype 3: Carry the heavy thing

A character carries something the puzzle requires. The carrier walks slowly, cannot fight, and is vulnerable; the party covers them.

Steps:
1. Pick up the carry-target. The carrier accepts the carry-state's limitations: reduced speed, no combat, possible perception layer loss.
2. Other party members provide cover, distraction, or path-clearing.
3. Carrier navigates the route.
4. Manage hazards during transit. This step often nests another archetype.
5. Deliver or place the carry-target.

Variants:
- A. By what is carried: i. cure component or fragment, ii. puzzle piece (mosaic, document, schematic), iii. injured party member, iv. critical resource, v. information artifact.
- B. By what the carrier loses: i. combat only, ii. movement only, iii. perception layer only, iv. all of the above (the Flow Aligner mosaic case).

### Archetype 4: Distract the patrol

One character draws attention; another character accomplishes the objective in the patrol's blind spot.

Steps:
1. Identify patrol pattern and the objective in its blind spot.
2. Choose distracting character based on the distraction method (loud, scent, iron signal, electrical).
3. Position distractor at the trigger point.
4. Acting character positions at the objective.
5. Distractor triggers the distraction.
6. Patrol responds.
7. Acting character completes objective during the patrol gap.
8. Distractor disengages and the party regroups.

Variants:
- A. By distraction method: i. loud action (Myke combustion, Tyreg shot), ii. false scent (Marco chemistry), iii. iron signal (Peris flora), iv. electrical signature (Aster EMP).
- B. By acting character's task: i. Aster terminal, ii. Peris plant-tending, iii. Endo aquatic route, iv. Oli insulation.

### Archetype 5: Two-character split

The party divides into sides; each side accomplishes something the other depends on.

Steps:
1. Encounter the separation.
2. Party divides.
3. Each side scouts or explores.
4. Each side completes their dependent task.
5. Sides communicate or coordinate timing if needed.
6. The separation resolves and the sides reunite.

Variants:
- A. By separation cause: i. physical wall, ii. class-restricted access, iii. hazard one can traverse.
- B. By interdependence type: i. sequential, ii. simultaneous, iii. sustained, iv. recovery.

### Archetype 6: Pattern reconstruction

Fragments scattered through an area; assembly reveals information.

Steps:
1. Discover that fragments exist.
2. Locate each fragment.
3. Retrieve each fragment. Each retrieval often nests another archetype.
4. Assemble the fragments.
5. Read or use the reconstructed whole.

Variants:
- A. By what is reconstructed: i. area map, ii. flow diagram (Flow Aligner mosaic), iii. document or text, iv. image or symbol.
- B. By retrieval constraint: i. combat pressure, ii. memory pressure (Peris forgets), iii. carry vulnerability, iv. hidden fragments requiring Aster's overlay.

### Archetype 7: Stealth-and-time

Avoid a patrol; complete the objective in the patrol gap.

Steps:
1. Observe the patrol pattern.
2. Identify the patrol gap.
3. Position during the pre-gap window.
4. Execute the objective during the gap.
5. Disengage and find cover.

Variants:
- A. By patrol type: i. NK patrol, ii. Naturalizer patrol, iii. Chelator presence.
- B. By objective: i. pass through, ii. terminal access, iii. plant something, iv. extract something.

### Archetype 8: Class-gated interaction

Some interactions require specific institutional authority.

Steps:
1. Encounter the gated interaction.
2. Identify which class is required.
3. Position the class-bearing character.
4. Initiate the interaction.
5. Resolve the interaction.

Variants:
- A. By class: i. AST (data terminal), ii. PCT (client interaction), iii. ENT (barrier infrastructure), iv. TMC or T-reg (enforcement override).
- B. By gated thing: i. door, ii. information access, iii. resource access, iv. NPC cooperation.

## Meta-archetypes (9-11)

### Archetype 9: Expectation subversion

Recurring strategic move of designing for surprise. The game uses player expectations against them. Genre conventions, level-design grammar, and narrative tropes are deployed as setup. Specific instances within this archetype are one-offs (each subversion needs rarity to land).

Structure (meta-pattern, not procedural):
1. Establish the convention via earlier game design or imported genre familiarity.
2. Set up the moment that appears to invoke the convention.
3. Break the convention at the moment of player commitment.
4. Deliver the consequence (mechanical, narrative, tonal).

Variants:
- A. By what is subverted: i. death/sacrifice convention (Marco's diminuendo death), ii. interact-with-highlighted-thing convention (Psyknapse trap), iii. others to be added sparingly.
- B. By tone: i. tragic, ii. weaponized.
- C. By stakes: i. mechanical consequence, ii. narrative consequence.

### Archetype 10: Danger zone

Persistent area containing a cure component, with environmental hazards, enemy compositions, and multiple solution paths. The DZ is a level-design container for sub-puzzles.

Structure (a DZ holds a composition of archetypes 1-8):
1. Entry transition (often a narrative beat per Archetype 11).
2. Sub-puzzle composition using archetypes 1-8.
3. Retrieval of the cure component.
4. Exit transition (often another narrative beat).

Variants:
- A. By cure component (per GDD section 10): i. Iron Redistribution Chaperone (Supply Lines), ii. Inflammashunt (Basal Galleries), iii. Pattern Wrap (Maintenance Warrens), iv. Flow Aligner (Zone 2), v. Acid Core (Zone 2 or 3), vi. Outflow Expander (Zone 2 or 3), vii. Resonator (deepest Zone 3), viii. Membrane Sealant (endgame Zone 3), ix. Rest Cycle Module (hidden shelter).
- B. By hazard composition: i. iron-based, ii. Naturalizer-patrol-based, iii. atmospheric, iv. mixed.
- C. By solution path: i. single-route with shadow alternative, ii. multi-route converging, iii. sequence-locked.

### Archetype 11: Narrative beat

Scene-level structural pattern where character dialogue, interaction, or interior experience produces a state transition. Distinguished from environmental storytelling by the transition criterion: environmental storytelling is static evidence of past state; a narrative beat involves transition during the encounter.

Structure (varies by variant in A):
1. Pre-transition state.
2. Transition mechanism.
3. Post-transition state.

Variants:
- A. By structure: i. setup-pivot-payoff (Ouroboros beat), ii. recognition (Endo at the wall), iii. realization (Peris realizing she did not see her patients), iv. confession (Aster's trickle-clown-effect revelation), v. memory (Peris's mural-scene memory), vi. silence (Marco's mundane death).
- B. By participants: i. two-character, ii. party-wide, iii. character-alone, iv. with NPC.
- C. By register: i. heavy, ii. light, iii. pivoting.
- D. By transition axes (a single beat can carry multiple): i. character or relationship state, ii. location or zone transition, iii. camera mode transition, iv. thematic priming.

Multi-axis beats (those carrying multiple transitions simultaneously) are particularly efficient at structural boundaries (act transitions, boss encounters, zone changes). The Ouroboros beat is canonical multi-axis: secret-sharing (D-i), into-the-Paranucleus (D-ii), camera shift (D-iii), thematic priming (D-iv) all simultaneously.

## Construction patterns

### Nesting

One archetype's step is itself another archetype. The outer archetype's step becomes a slot where the inner archetype's procedure executes.

Nesting can go multiple levels deep. Archetype 6 with Step 3 (retrieve each fragment) might nest Archetype 3 (carry), whose Step 4 (manage hazards) nests Archetype 4 (distract patrol).

Common nest points: Step 4 of Archetype 3 (manage hazards during transit) accepts almost any archetype that handles a specific hazard; Step 3 of Archetype 6 (retrieve each fragment) accepts any archetype that can produce a contained item; Step 5 of Archetype 4 (distractor triggers) often nests Archetype 2 (plant as distraction mechanism).

### Chaining

One archetype's output becomes the next archetype's setup. Chains can extend across multiple archetypes if each link produces what the next needs.

Common chains:
- Archetype 1-C-i (redirect enemy to break cage, revealing a plant) → Archetype 2 (harvest and plant the revealed flora).
- Archetype 8-A-i (Aster clears class-gate at terminal) → Archetype 6-A-iii (assemble institutional logs).
- Archetype 4 (distract patrol) → Archetype 7 (stealth-and-time through the distracted patrol's blind spot).
- Archetype 2-A-i (plant Flures) → Archetype 3-A-i (carry the gear through the cleared path).

### Shadow solutions as alternate compositions

Every major puzzle has a shadow solution (per GDD section 2.6) executable by Aster and Peris alone. The shadow solution typically uses different archetype variants in the same composition pattern, or substitutes one archetype for another that the two-character constraint allows. The chain pattern is preserved; the variants change to fit the constraint. Shadow solutions are alternate compositions of the same archetype skeleton.

### Worked decompositions

**Mother Flure chamber** (GDD section 12.2): Archetype 2-A-i chained into Archetype 3-A-i.
- Steps 1-5 of Archetype 2 (acquire Flures, identify planting locations, plant, wait for siderophores to be drawn, effect active).
- Steps 1-5 of Archetype 3 (Endo picks up gear, party clears, navigate, hazards managed by Flures' effect, gear delivered).
- Shadow solution: Archetype 2-A-ii chained into Archetype 3-A-iii. Same chain, different variants. Scarpet masks Aster's iron-signal; Peris drags Aster.

**Flow Aligner ruin**: Archetype 6 with Archetype 3 nested in Step 3.
- Steps 1-2 of Archetype 6 (discover mosaic exists, locate fragments).
- Step 3 (retrieve each fragment) executes Archetype 3 once per fragment.
- Step 4 of Archetype 6 (assemble at plinth).
- Step 5 of Archetype 6 (read reconstructed pattern, unlock next gate).

**Psyknapse trap** (GDD section 0.4): Pure Archetype 9 without standard composition. Presents appearance of Archetype 8-A-i (class-gated terminal) to lure player, then subverts via Archetype 9 mechanic.

## Enemy archetypes

### Framework

Each enemy type in TRAWF is an archetype with three components:

1. **Universal behavior steps**: how the enemy operates regardless of deployment context.
2. **Sub-archetypes by deployment context**: each is a specific area + specific hiding spots + specific cover + specific environmental affordances.
3. **Ways to deal with them**: composition with puzzle archetypes 1-8 (and sometimes 9-11).

Enemy archetypes compose with puzzle archetypes. The level designer picks: which enemy archetype, which sub-archetype (deployment context), and which puzzle archetypes to handle them.

Enemy roster (per GDD section 7.1): Sapscraps, Ferrules, Hidras, Crusts, Candids, Meebs, Naturalizers, Gnawers, Flares, Spikers, Tanglers, Toxos, Redactors. Four of these (Sapscraps, Ferrules, Hidras, Crusts) are siderophore species that compete for iron (GDD section 7.2).

### Worked example: Sapscraps (basic siderophores)

Universal behavior steps:
1. Detect iron signal within detection radius.
2. Path toward strongest available iron signal.
3. Engage on contact: drain iron from infrastructure or organism.
4. Cluster with other Sapscraps when iron source is rich enough.
5. Disperse when iron source is depleted or destroyed.
6. Compete with other siderophore species; avoid Crust-dense surfaces, Hidra-occupied conduits, Ferrule-concentrated breach areas.

Sub-archetype A: Channels deployment (Perivascular Channels)
- Hiding spots: pipe junctions, between water-flow controls, in dark pipe recesses.
- Cover: support columns, pipe segments, water-channel walls.
- Environmental affordances: water-flow controls; pipe-opening valves; plantable spots for Peris's Flures.
- Ways to deal with: open water-flow control to wash into sealed section; Flure-plant in adjacent pipe (Archetype 2-A-i); Aster's iron-signal masking via Scarpet; Archetype 1 to bait into iron-rich junction.

Sub-archetype B: Iron Marshes deployment (Act 3, Zone 3)
- Hiding spots: rust pools, behind crumbling iron towers, iron-rich substrate.
- Cover: iron tower remains, rust formations, dead structural columns.
- Environmental affordances: iron-pool drainage; iron-tower collapse triggers; ambient iron-storm cycles that cluster siderophores.
- Ways to deal with: drain iron pool to displace cluster; collapse tower onto cluster for mass kill; time movement to non-storm cycles for reduced detection; Archetype 7 using storm cycle as patrol gap.

Sub-archetype C: Basal Galleries deployment (Act 1 transition)
- Hiding spots: foundation alcoves, between support beams, deep galleries.
- Cover: foundation beams, ancient infrastructure, dim lighting.
- Environmental affordances: dim lighting reduces detection radius slightly; old iron storage tanks as decoys; collapsing floor sections.
- Ways to deal with: open storage tank to flood area with decoy signal; lure over weak floor section; Aster's overlay to pre-detect positioning.

### Other enemies (roster, sub-archetype design pending)

Each enemy below needs full enemy-archetype treatment (universal behavior steps, sub-archetypes by deployment, ways to deal with them). The biological role is from GDD section 7.1 to anchor the design.

| Enemy | Biology | Role |
|---|---|---|
| Ferrules | Fluorescent siderophores | Fluorescent specialists at breaches |
| Hidras | Hydroxamate siderophores, segmented wire | Infrastructure mimics |
| Crusts | Mycobactin-type, membrane-embedded | Surface biofilm, wall-paranoia |
| Candids | Candida biofilms | Slow biofilm colonizers, environment changers |
| Meebs | Free-living amoebae | Indiscriminate engulfers |
| Naturalizers | NK cells | Institutional enforcement patrols |
| Gnawers | Gingipains (P. gingivalis) | Metabolic-signature hunters |
| Flares | Neutrophils | AoE bursters, neutral-until-triggered |
| Spikers | Hyperexcitable neurons | Line-of-sight lock-on snipers |
| Tanglers | Tau propagation | Stealth-grapple hunters with seeding |
| Toxos | Toxoplasma gondii | Set piece or player-facing |
| Redactors | Membrane-cloaked pathological T-cells | Late-game invisible enforcers |

For each, the design pass should produce:
- Universal behavior steps (3-6 steps describing how the enemy operates)
- 2-4 sub-archetypes by deployment context (each with hiding spots, cover types, environmental affordances)
- 4-8 ways to deal with them per sub-archetype, with explicit puzzle-archetype references

## How to use this system to generate content

### Generating a new puzzle

1. Identify the puzzle's goal (cure component retrieval, area access, character beat).
2. Select macro-archetype that fits (typically Archetype 3, 5, 6, or 7 for major puzzles).
3. List the macro-archetype's steps.
4. For each step, decide whether to execute simply or nest another archetype.
5. For the macro-archetype's output, decide whether to chain into a second archetype.
6. Choose variants (A/B/C levels) to fit the area's flora and enemy populations.
7. Check shadow-solution feasibility: can Aster + Peris alone execute the composition? If not, what variant substitutions enable it?
8. Connect to canon: which cure component (if any), which characters (party composition at this point in the game), which area, which environmental storytelling layer.

### Generating a new enemy encounter

1. Pick enemy archetype (which enemy from the roster).
2. Pick sub-archetype (which deployment context).
3. Identify available environmental affordances at that sub-archetype.
4. Pick the puzzle archetype that handles the encounter (typically Archetype 1, 2, 4, or 7).
5. Compose the encounter using the archetype's steps.
6. Check shadow-solution feasibility.

### Generating a new danger zone (Archetype 10)

1. Pick the cure component to be retrieved.
2. Pick the area where the DZ is located.
3. Identify the enemy archetypes and sub-archetypes that populate the area.
4. Design the sub-puzzle composition: which archetypes 1-8 nest and chain inside the DZ.
5. Design entry and exit narrative beats (Archetype 11).
6. Ensure the composition has a shadow-solution path.

### Generating a new narrative beat (Archetype 11)

1. Identify what state needs to transition (character, relationship, world register).
2. Pick the structure variant (setup-pivot-payoff, recognition, realization, confession, memory, silence).
3. Pick participants (two-character, party-wide, alone, with NPC).
4. Pick the transition mechanism (joke, environmental cue, recognition trigger, etc.).
5. Identify which transition axes the beat carries (D dimension: character, location, camera, thematic).
6. Write the beat's dialogue and stage directions.

### Connecting to canonical worldbuilding

The GDD (`to_rust_gdd_v02.md`) is the canonical reference for:
- Character interiority and arcs (sections 3.1-3.7)
- Worldbuilding (section 4)
- Institutional vocabulary and class codes (section 5)
- Aesthetic register (section 6)
- Enemy ecosystem (section 7)
- Flora system (section 8)
- Cure components (section 10)
- Bosses (section 11)
- Major set pieces (section 12)
- Endings (section 13)
- Thematic spine (section 1.1)

The thematic spine in section 1.1 is the load-bearing argument: responsibility creates conditions for trust, trust enables secret-sharing, shared secrets resist institutional capture, the relational practices accumulated through this chain become the externalized cure. Enemies are failure modes of responsibility; cure components are externalized relational practices.

Every piece of content should support this spine in at least one way: through the relational work the party does to compose the solution, through the environmental storytelling around enemy failure modes, through the dialogue beats that articulate responsibility / trust / secret-sharing, or through the connection between the cure component retrieved and the relational practice it externalizes.
