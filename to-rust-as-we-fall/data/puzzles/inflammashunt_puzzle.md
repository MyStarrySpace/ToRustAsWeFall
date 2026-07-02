# Inflammashunt Puzzle - Full Spec

The Inflammashunt is the Resolution Catalyst retrieval: a piece of salvageable working tech in Myke's old maintenance corridors. It is the most mechanically complex Act 1 danger-zone puzzle, built around three-route information gathering, contradictory character reports, environmental state changes, route-info-as-efficiency, recoverable wrong approaches, and a hostile-root recovery sub-puzzle.

This is the canonical full puzzle spec. The shadow solution is documented separately in [Inflammashunt Shadow Solution](./inflammashunt_shadow_solution.md).

## Design Job

- `component`: Resolution Catalyst
- `in_game_name`: Inflammashunt
- `real_basis`: specialized pro-resolving mediators, including resolvins, lipoxins, maresins, and protectins
- `gameplay_role`: Act 1 danger-zone retrieval and Manage Conflict puzzle
- `primary_cognitive_test`: synthesize conflicting information across character-specific routes
- `primary_emotional_test`: resist the aggressive instinct when every confident first answer points toward escalation
- `location`: danger zone branching off the Ancourage near the end of Act 1, after shelter 10
- `party_spotlight`: Myke, with Aster and Peris as equal information anchors
- `survival_clock`: off inside the puzzle area; danger is local state, not day/night attrition

Designer-only framing: this is the Manage Conflict component. Do not mention the therapy architecture in player-facing text. Nobody knows a cure exists at this point in the story. The party retrieves the device because it is useful salvage, not because they recognize it as a cure component.

## Component Identity

The Resolution Catalyst represents the biological resolution phase of inflammation. Chronic neuroinflammation in AD is not simply "too much inflammation"; it is inflammation that does not receive the signal to stop, clean up, and repair. The problem is not fire. The problem is fire that never goes out.

The Inflammashunt redirects the local inflammatory loop into a resolution cycle:

1. fluid dampens burn residue
2. char is removed without reignition
3. roots regrow into the corridor
4. dormant Chelators are incorporated into a buffer
5. the healing zone reaches the device housing

The device does not suppress Myke's fire. It completes what fire starts.

## Narrative Premise

Myke knows the branch corridor because it leads into the maintenance routes where he used to work before being pushed farther out to the The Hypelines. He does not enter heroically. He knows there may be salvageable working tech in the old corridors, and working tech can be traded, repurposed, or used to improve the party's survival situation.

The player's motivation is the established danger-zone grammar:

- harder side path
- visible environmental danger
- a party member with local knowledge
- likely stronger reward

The Inflammashunt is found as salvage. Its cure role is revealed later, after Aster cross-references it against schematics from later zones.

## Approach Corridor

The approach should feel immediately different from the surrounding Basal Gallery infrastructure.

### Visual Read

- walls blackened and scorched
- surfaces fused by old heat damage
- conduit routing still elegant beneath the burn marks
- acrid air and ash residue
- Crust organisms growing from accumulated char
- old Chelator damage visible beneath later burn residue

The key read is not "Myke was careless." The key read is "Myke's fire worked, but nobody managed the aftermath."

The fire zones he creates in normal gameplay burn out after a few seconds because the current party and local systems can manage them. In these abandoned corridors, he burned Chelators out over and over with no cleanup phase. The residue accumulated until the unresolved response became worse than the original infestation.

### Entry Dialogue

```text
Myke: "...I cleared this section. Twice, maybe. The crawlers kept coming back."

Aster: "The fire worked. The crawlers are gone."

Myke: "Yeah."
```

After this, Myke should be quiet for a while. Let the corridor do the talking.

## Macro Layout

The puzzle has four spatial layers:

1. Approach corridor: emotional setup and burn-damage read.
2. Three-route hub: Aster, Peris, and Myke split into character-coded information routes.
3. Junction room: the shared eight-interactable puzzle space.
4. Device housing: prize reveal and after-retrieval scene.

Suggested rough world layout:

```text
                        [Aster Route]
                             |
[Approach] ---- [Route Hub] -+---- [Junction Room] ---- [Device Housing]
                             |
                        [Peris Route]
                             |
                        [Myke Crawl]
```

The three routes should not be long combat dungeons. They are information routes with local affordance checks. Each has two interactables. The point is interpretation, not traversal attrition.

## Core State Model

Use explicit puzzle state rather than implied scene state.

```gdscript
var route_info := {
	"aster_log": false,
	"aster_pipe_diagram": false,
	"peris_dead_roots": false,
	"peris_living_junction": false,
	"myke_char_feed": false,
	"myke_buffer_ring": false,
}

var puzzle_state := {
	"valve_open": false,
	"char_a_state": "dry",      # dry, damp, cleared, burned
	"char_b_state": "dry",      # dry, damp, cleared, burned
	"root_state": "suppressed", # suppressed, tame, hostile, recovering, connected
	"buffer_state": "stable",   # stable, shattered, reforming
	"gas_sac_state": "idle",    # idle, tended, carried, expired, ignited
	"healing_zone": 0.0,        # 0.0 to 1.0
	"housing_unlocked": false,
	"device_retrieved": false,
	"wrong_events": [],
	"long_hold_count": 0,
}
```

These exact field names are not mandatory, but the implementation should expose equivalent state through `headless_get_state()` for tests.

## Route Information As Efficiency

The routes are not mandatory. They make the correct actions faster and safer.

| Action | Info flag | Hold with info | Hold without info | Why |
| --- | --- | ---: | ---: | --- |
| Open drainage valve | `aster_pipe_diagram` | 2.5s | 14.0s | Aster knows the flow routing and pressure order. |
| Scrape char A | `myke_char_feed` | 2.0s | 10.0s | Myke knows the char is fuel and where to scrape. |
| Scrape char B | `myke_char_feed` | 2.5s | 11.0s | More careful due to root proximity. |
| Tend root tendril | `peris_living_junction` | 2.5s | 12.0s | Peris recognizes the root-Chelator symbiosis. |
| Tend gas sac | none required | 2.0s | 2.0s | Recovery tool; should remain available even after mistakes. |
| Open housing after unlock | `healing_zone >= 1.0` | 1.2s | 1.2s | The lock condition is spatial/biological, not knowledge-gated. |

Suggested tuning target:

- clean informed solve: 7-9 minutes first play
- clean repeat solve: 3-5 minutes
- brute-force/no-route solve: 16-22 minutes, with higher local hazard exposure

## The Three Information Routes

Each route has two interactables:

- one red herring
- one true specific
- one internal contradiction

Each character reports a confident wrong answer after returning. Every report is honest. The character is right about what they saw and wrong about what to do.

### Aster Route - Terminal And Pipe Diagram

Character read: engineering infrastructure, logs, decommission language.

#### A1: Engineering Log Terminal

Player-facing text:

```text
FINAL ENTRY
Resolution capacity exceeded.
Recommend thermal reset.

Filed: same day as section removal from registry.
```

Red herring:

- "thermal reset" appears to mean apply heat.
- It is actually a decommission order, not repair guidance.

State:

- sets `route_info.aster_log = true`

Feedback:

- Aster highlights "thermal reset" with confidence.
- The filing date should be visible and weirdly final.

#### A2: Pipe Junction Diagram

Aster scans a wall diagram opposite the terminal.

True specific:

- drainage valve connects to Plumbing Power Project
- flow direction and pressure ratings are readable
- the infrastructure is for water/fluid movement, not heat

State:

- sets `route_info.aster_pipe_diagram = true`

Internal contradiction:

- the log says thermal reset
- the only live infrastructure shown is a drainage/flushing system

Aster report:

```text
Aster: "The engineers left instructions. The device needs a thermal reset."
```

Design note: Aster should sound convincing. The contradiction is for the player to catch.

### Peris Route - Dead Roots And Living Junction

Character read: flora, growth, damage pattern, relationship.

#### P1: Dead Root Network

The route enters a lower passage. Peris finds a dead root network: hollow, porous, tunneled through by Chelator feeding, with char deposited on top.

Red herring:

- the char is visible
- Peris initially reads it as fire killing the roots

The careful read:

- the structure is hollowed from inside
- material was removed before the char layer settled
- the roots died of consumption first, then got coated by burn residue

State:

- sets `route_info.peris_dead_roots = true`

#### P2: Living Root-Chelator Junction

Deeper underground, living root filaments connect to dormant Chelator husks. The filaments pulse faintly.

True specific:

- dormant Chelators are not simply dead enemies
- the roots feed the device
- the device pacifies Chelators
- processed iron cycles back into the roots

State:

- sets `route_info.peris_living_junction = true`

Internal contradiction:

- the old roots look eaten by Chelators
- the living roots are growing toward Chelators and connecting to them

Peris report:

```text
Peris: "The old roots were burned. Fire killed the previous resolution system. We can't use fire near the device."
```

Design note: Peris is partly wrong in a protective direction. She is correctly wary of fire near living roots, but she misreads the historical sequence.

### Myke Route - Crawlspace Observation

Character read: enemy behavior, fuel source, field experience.

This route is physically character-coded. Myke is the only one who fits through the crawlspace in the presented solution. See the shadow solution for how Aster and Peris can reconstruct this route's information without entering it.

#### M1: Grate Observation - Active Chelators Feeding

Myke sees active Chelators clustered around char deposits on the corridor floor.

True specific:

- char is the fuel source
- active Chelators are not randomly roaming
- remove char, remove the local attraction source

State:

- sets `route_info.myke_char_feed = true`

#### M2: Device Gap - Dormant Buffer Ring

Myke sees the Inflammashunt through a gap. Dormant Chelators surround it in a ring. Active Chelators press inward from outside the ring.

Red herring:

- it looks like too many crawlers near the device
- Myke reads it as "clear them all out"

Careful read:

- the dormant ones are calm
- they form a perimeter
- the active ones are outside the ring
- the ring is a buffer, not a siege

State:

- sets `route_info.myke_buffer_ring = true`

Internal contradiction:

- active Chelators feed on char
- dormant Chelators near the device do not feed and behave differently

Myke report:

```text
Myke: "Too many crawlers. We burn the corridor clean, give the thing room to breathe."
```

## Reunion Beat

After route completion, the party returns to the hub. If all three route reports are available, play the contradiction triangle.

```text
Aster: "The engineers left instructions. The device needs a thermal reset."

Peris: "The old roots were burned. Fire killed the previous resolution system. We can't use fire near the device."

Myke: "Too many crawlers. We burn the corridor clean, give the thing room to breathe."
```

The triangle:

- Aster says apply heat, but Peris says heat killed the old system.
- Peris says no fire anywhere, but Myke knows char residue is the current fuel source.
- Myke says burn them out, but Aster's pipe data shows a water-based system.

If Myke is absent or Route C is skipped, use the two-report variant and preserve the missing-route inference for the shadow path. Do not force Myke's report if the player did not earn it.

## Junction Room

The junction room has eight interactables in one shared space. The healing zone is visible through a grated floor section at the far end. The device housing is embedded in the floor near the grate.

The room must visually support the full solution without text:

- drainage valve on wall
- char deposits on the floor
- root tendril in floor crack near char B
- dormant Chelator ring near the housing
- gas sac flora in damp corner
- terminal near valve
- sealed housing near healing-zone edge

### Spatial Layout

Recommended placement:

```text
          [Aster Route Return]
                    |
 Entrance ---- Char A ---- Valve / Terminal
                    |
             Dormant Chelator Ring
                    |
 Gas Sacs ---- Char B + Root Tendril ---- Device Housing / Grate
                    |
          [Peris Route Return]
```

Design priorities:

- valve and terminal should be near each other but visually distinct
- gas sacs should be visible before they ignite, but not read as required in clean solve
- char B must clearly be near the root so the dry-fire mistake feels fair
- dormant Chelators must look like enemies at first glance and like a geometric buffer on closer read

## Eight Interactables

### 1. Drainage Valve

Actor: Aster preferred, other characters can examine.

Function:

- opens fluid flow from the Plumbing Power Project
- changes `char_a_state` and `char_b_state` from `dry` to `damp`
- douses gas sac fire if popcorn event is active

Hold:

- 2.5s with `aster_pipe_diagram`
- 14.0s without it

Feedback:

- valve wheel turns
- pipe rumble travels through wall
- floor channels fill
- char deposits darken and steam
- active Chelators recoil but do not despawn yet

Failure:

- no hard failure
- long hold under fire or enemy pressure is dangerous

### 2. Char Deposit A

Actor: Myke preferred in presented solution. Aster or Peris may scrape in shadow/brute-force solve.

Location:

- near entrance
- active Chelators cluster around it

If dry:

- Myke's available action reads as Inflame
- applying fire clears the char but wakes nearby dormant Chelators
- triggers combat encounter
- sets `char_a_state = burned`
- appends `wrong_events += ["burned_char_a"]`

If damp:

- scrape clean
- sets `char_a_state = cleared`
- active Chelator cluster loses a food source and thins out

Hold:

- 2.0s with `myke_char_feed`
- 10.0s without it

Rule taught by wrong approach:

- fire works, but it wakes what the puzzle needs to keep dormant

### 3. Char Deposit B

Actor: Myke preferred in presented solution. Aster or Peris may scrape in shadow/brute-force solve.

Location:

- near device housing and root tendril

If dry:

- Inflame clears char
- root tendril goes hostile
- starts hostile-root recovery sub-puzzle
- sets `char_b_state = burned`
- sets `root_state = hostile`
- appends `wrong_events += ["burned_char_b"]`

If damp:

- scrape clean without disturbing root
- sets `char_b_state = cleared`

Hold:

- 2.5s with `myke_char_feed`
- 11.0s without it

Rule taught by wrong approach:

- fire near living resolution tissue is not neutral; dampening first matters

### 4. Root Tendril

Actor: Peris.

Initial state:

- suppressed by char residue

Prerequisite:

- `char_a_state == cleared`
- `char_b_state == cleared`
- `root_state != hostile`

If used early:

- nothing happens
- root pulse flickers and dies down
- Peris line indicates suppression

If used after both char deposits are cleared:

- Peris tends root
- root brightens
- filaments extend toward dormant Chelator cluster
- healing zone expands toward housing
- sets `root_state = connected`
- sets `healing_zone = 1.0`
- sets `housing_unlocked = true`

Hold:

- 2.5s with `peris_living_junction`
- 12.0s without it

Rule taught by early attempt:

- care cannot land while the suppressing residue remains

### 5. Dormant Chelator Cluster

Actor: any character can examine; attacking is the mistake.

Examination result:

- warm
- connected by thin root filaments
- not feeding
- not aggressive

If attacked:

- buffer shatters
- active Chelators flood in
- root tendril retracts
- starts combat encounter
- sets `buffer_state = shattered`
- sets `root_state = suppressed` or `recovering`
- appends `wrong_events += ["attacked_buffer"]`

Recovery:

- after combat ends and player stops attacking, cluster reforms over time
- root returns once cluster stabilizes

Rule taught:

- the enemy-looking cluster is part of the resolution system

### 6. Gas Sac Flora

Actor: Peris.

Clean-solve role:

- optional; may never be used

Wrong-approach/recovery role:

- produces repellent sac for hostile-root recovery
- becomes popcorn fuel during thermal reset trap

Interaction:

- Peris tends flora for 2.0s
- flora swells
- produces carryable gas sac
- sac duration: 20-25s recommended
- duration can be tuned per difficulty

If terminal thermal reset triggers:

- flora ignites
- sacs launch as flaming projectiles
- sets `gas_sac_state = ignited`
- starts popcorn hazard until valve douses room

Rule taught:

- gas sacs exist and are reactive; water is a meaningful countermeasure

### 7. Terminal

Actor: Aster.

Function:

- shows route data on larger screen
- can trigger wrong thermal-reset command

Hack:

- normal hack opens read-only diagnostic view
- initiating `thermal reset` is the mistake

If thermal reset command is initiated:

- gas sac flora ignites
- flaming sacs launch in random arcs, bounce off walls, damage characters
- party must reach drainage valve to flood room
- appends `wrong_events += ["thermal_reset"]`

Rule taught:

- "thermal reset" was a catastrophic misread
- the valve produces water
- gas sacs can become hazards

### 8. Device Housing

Actor: any character; Aster likely opens in clean solve.

Initial state:

- sealed biological lock
- no backlash for trying early

If tried before unlock:

```text
It does not budge. The lock is warm, but the warmth is coming from below, not from the panel.
```

If `housing_unlocked == true`:

- opens
- device can be collected
- sets `device_retrieved = true`
- starts after-retrieval scene

Rule taught by early attempt:

- the healing zone must reach the housing

## Correct Solution

The clean solution is five steps:

1. Aster opens the drainage valve.
2. Scrape damp char deposit A.
3. Scrape damp char deposit B.
4. Peris tends the root tendril.
5. Open the device housing.

Presented party distribution:

- Aster opens the valve and housing.
- Myke scrapes both char deposits.
- Peris tends the root.

Shadow party distribution:

- Aster opens the valve and housing.
- Aster or Peris scrape both char deposits.
- Peris tends the root.

Important: scraping is a general physical action. Myke is not required as actuator labor. Myke's unique value is information.

## Wrong Approach Pedagogy

Every wrong approach teaches exactly one rule. No wrong approach permanently destroys the puzzle.

| Wrong approach | Immediate consequence | Rule taught | Recovery |
| --- | --- | --- | --- |
| Thermal reset via terminal | gas sac popcorn fire | thermal reset is wrong; valve douses fire | open valve under pressure |
| Burn dry char A | combat from woken Chelators | fire works but wakes dormant systems | finish combat, then dampen/scrape remaining char |
| Burn dry char B | hostile root | fire near roots escalates | gas sac herding sub-puzzle |
| Attack dormant Chelators | buffer shatters, combat | buffer is not an enemy | stop attacking; cluster reforms |
| Tend root before char cleared | root does not grow | residue suppresses resolution | clear char first |
| Open housing too early | no opening | healing zone is lock condition | expand healing zone |

## Hostile Root Recovery Sub-Puzzle

This is the largest recovery path and should feel like a complete mini-encounter, not a punishment screen.

Trigger:

- player burns dry char B near the root

State changes:

- root becomes hostile
- root whips nearby characters
- root camouflages against wall conduits
- root uses Chain AI movement to thread through infrastructure
- root base remains in the original floor crack

Recovery objective:

- force the hostile root back to its base point so it retracts
- wait a few seconds for a new tame tendril to emerge
- clear char properly before tending it

Tools:

- Peris tends gas sac flora
- a gas sac item appears
- a character carries the sac
- root recoils from the sac aura

Recommended values:

- gas sac duration: 22s
- repellent aura radius: 3.0 world units
- root flee preference: move away from carrier while avoiding direct path to base unless boxed in
- base capture radius: 1.5 world units
- root retract delay after entering base: 1.0s
- tame regrowth delay: 4.0s

Herding behavior:

- root tries to flank around the carrier
- root can double back through wall conduits
- root should not teleport
- player should be able to cut off escape routes by positioning the carrier and other party members
- if the sac expires, root becomes aggressive again but stays in current location
- Peris can tend another sac

Completion:

- root reaches origin
- retracts fully
- new smaller tame tendril emerges
- puzzle returns to recoverable state with char B needing proper cleanup if not already cleared

Design note:

The mistake forces the correct lesson. The player must eventually dampen, scrape, and tend in order.

## Hint Escalation

Hints should push reconnaissance, not solution text. The characters do not know the answer either.

Track long holds caused by missing route info or failed prerequisites.

### First Long Hold

Use active-character frustration only.

Examples:

```text
Aster: "This interface is fighting me."
Peris: "It is not answering yet."
Myke: "I don't like guessing at crawler sign."
```

### Second Long Hold

Another character comments.

```text
Myke: "You look like you're guessing."

Peris: "Maybe we should look around first."

Aster: "There might be information here we're not seeing."
```

### Third Long Hold Or First Wrong Consequence

Characters volunteer routes.

```text
Myke: "There's a crawlspace back there I could fit through. Might see something useful."

Peris: "I noticed a growth at that junction. I could follow it underground."

Aster: "That terminal at the junction had a hack lock. I should take a look."
```

### After A Wrong Consequence With Missing Route Info

Be explicit about missing reconnaissance, but not the solution.

```text
Aster: "We're missing something. Let me check that terminal back at the junction."

Myke: "We're doing this blind. Let me crawl in and see what we're actually dealing with."

Peris: "There's something growing underground near the junction. I think I need to see it before we try anything else."
```

## After Retrieval

When the device housing opens, the healing zone should visibly expand around it. The corridor is still burned, but no longer only damaged. It is scar tissue becoming functional infrastructure.

Myke sees the difference.

```text
Myke: "...Huh. So that's what it looks like when somebody finishes the job."
```

He is not talking only about the device. He is talking about what his work could have been if the system had supported resolution instead of leaving him alone to fight and move on.

This beat recontextualizes Inflame:

- fire was not the problem
- the immune response was not the disease
- unresolved fire was the damage
- Myke did the part he was given
- the system failed to complete the cycle

If Myke is not present due to a shadow route, skip this specific line. Do not play it through another character.

## Later Collection Beat - Tyreg Naming War

When Tyreg later joins and examines the collection, she misreads the label.

```text
Tyreg: "Inflammation't."

Myke: "What?"

Tyreg: "The label. It's called the inflammation't. Like... inflammation, but with a contraction. Inflammation is not. Inflammation't."

Aster: "It says 'inflammashunt.' It's a shunt. For inflammatory--"

Tyreg: "A shunt."

Aster: "A shunt redirects flow from one pathway to--"

Tyreg: "I know what a shunt is. The label is small."
```

She did not know what a shunt was. The party calls it both names for the rest of the game. Myke says Inflammashunt. Tyreg says Inflammation't. Neither concedes.

## Shadow Solution Compatibility

The puzzle must support Aster and Peris solving without Myke.

Required design facts:

- scraping char is not Myke-locked
- Route C information can be reconstructed from Aster route, Peris route, and junction-room observation
- dormant Chelator ring must be visible and examinable from central room
- active Chelators clustering near char must be visible enough to infer the char-fuel relationship
- the five-step solution remains unchanged

See [Inflammashunt Shadow Solution](./inflammashunt_shadow_solution.md) for the full reconstruction logic.

## Implementation Anchors

Suggested anchors for headless tests:

```text
route_hub
aster_route_log
aster_route_pipe_diagram
peris_route_dead_roots
peris_route_living_junction
myke_route_char_grate
myke_route_device_gap
junction_valve
junction_char_a
junction_char_b
junction_root
junction_buffer_cluster
junction_gas_sacs
junction_terminal
junction_housing
root_base
hostile_root_lane_north
hostile_root_lane_south
```

Suggested `headless_get_state()` fields:

```text
current_step
route_info
valve_open
char_a_state
char_b_state
root_state
buffer_state
gas_sac_state
healing_zone
housing_unlocked
device_retrieved
wrong_events
active_hazards
long_hold_count
```

## Required Tests

Minimum deterministic test coverage:

1. `clean_full_info_solution`: all six route interactables read; five-step solve completes; no wrong events.
2. `long_hold_no_info_solution`: route info skipped; correct five steps still solve with longer timers.
3. `thermal_reset_recovery`: terminal mistake starts popcorn fire; valve douses; puzzle remains solvable.
4. `dry_char_a_recovery`: burning char A starts combat; after combat, puzzle remains solvable.
5. `dry_char_b_hostile_root_recovery`: burning char B starts hostile root; gas sac herding resets root; puzzle remains solvable.
6. `attack_buffer_recovery`: attacking dormant cluster starts combat and reforms buffer; puzzle remains solvable.
7. `early_root_attempt`: tending before char clears fails without state destruction.
8. `early_housing_attempt`: opening housing early fails without state destruction.
9. `shadow_solution`: Myke route skipped; Aster/Peris route info plus central observations allow clean five-step solve.
10. `route_info_timers`: hold durations are shorter when relevant info flags are set.

## Tuning And Readability Gates

Hard gates before implementation is considered shippable:

- A first-time player can identify all eight interactables within the room.
- The valve's water effect visibly changes both char deposits.
- Char A and char B are visually distinct enough that char B's root proximity is obvious.
- Dormant Chelators initially look threatening but become legible as a buffer on examination.
- Every wrong approach produces an immediately visible lesson.
- Every wrong approach is recoverable without reloading.
- The clean solution can be explained as "water, clean, clean, tend, open."
- The puzzle's violence alternatives are tempting but not optimal.

## Open Questions

- Should the dormant Chelator cluster be attackable through normal combat input, or only through an explicit interact/attack prompt?
- Does the hostile-root recovery sub-puzzle need a dedicated camera framing pass to keep Chain AI movement readable?
- Should Aster's pipe diagram give a small UI memory card, or should the player remember it entirely diegetically?
- How long can the no-info valve hold be under popcorn fire before it becomes funny-frustrating instead of tense?
- Should Myke's after-retrieval line be replayable as a shelter reflection if he was absent during a shadow solve?

## Cross-References

- [Inflammashunt Shadow Solution](./inflammashunt_shadow_solution.md)
- [Teaching Beats Catalogue](./teaching_beats_catalogue.md)
- `flora_taxonomy.md`: gas sac flora and resolution roots
- `survival_gameplay_feel.md`: danger zone safety principle
- `mother_flure_spec.md`: contrast puzzle for Act 1 major retrieval design
- `chase_scene_framework.md`: related environmental lever scene framework
