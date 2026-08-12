# Chase scene framework

Specification for how chase scenes work in TRAWF. Chase scenes are a distinct scene type within the broader scene spec framework (see `trawf-scene-spec-framework/SKILL.md`). They share the structure but have specific mechanical requirements that make them behave differently from tactical encounters, puzzle set pieces, or dialogue scenes.

This doc specifies the chase scene pattern generally, then documents the existing lockout chase as the reference instance, then lists anticipated future chase scenes and their categorization.

## What defines a chase scene

A chase scene is distinct from other encounter types along several axes:

**Forced movement.** The party cannot stop and tactically reposition without serious consequence. Unlike tactical encounters where pause-and-plan is the primary mode, chase scenes compress the pause-and-plan architecture to almost nothing. Pausing is still mechanically available but gives limited advantage because the pursuing threat does not pause with the player.

**Directional pressure.** The party moves toward a specific destination. There is no exploration, no optionality about route (though there may be micro-route choices within a scripted corridor). The chase has a defined start point and end point.

**Pursuer class.** A specific threat is behind the party. The pursuer is a dramatic presence rather than a tactical encounter: the player does not fight the pursuer during the chase. The pursuer's role is to create pressure, and the scene's design controls whether they catch up.

**Environmental slowdowns.** The pursuer has narrative-consistent reasons to slow down at specific points. These can be protocol-hesitations, physical obstacles, chemical gradients, or scripted terrain features. The slowdowns are how the scene keeps the party barely ahead.

**Authored outcome (deprecated):** Earlier draft of this framework claimed chase scenes have fixed outcomes and the party always survives. This is not correct for TRAWF. Chase scenes can genuinely fail: if the pursuer catches the party, the reset system fires (see `trawf_timing_and_pacing_spec.md` section 4 for reset behavior). The chase has real stakes because the reset has real cost. What distinguishes chase scenes from tactical encounters is not authored-outcome but the compression of normal play modes into a time-pressured environmental-management puzzle, described below.

**Minimal dialogue.** Short reactive lines only. Physical sounds (breath, stamina, footfalls) carry most of the audio. Extended dialogue is incompatible with the chase's pace.

**Character role shifts.** Chase scenes produce relational pivots under pressure. Characters have to ask each other for help they would not normally ask for in calmer moments. The chase's time pressure *produces* the character moment; the character moment is the chase's narrative payoff.

**Compressed emotional arc.** Chase scenes land a sustained emotional arc (often built up across multiple preceding scenes) into a real-time compression where the player cannot intellectualize or optimize their way through it. The chase delivers as visceral experience what has been established as intellectual premise.

## The chase scene shape

Every chase follows this rough structure:

1. **Trigger moment.** The scene shifts from its preceding mode into chase mode. Could be a tag rejection, a Naturalizer detection, a swarm event, a perception failure, a narrative beat. The trigger makes the chase necessary and, ideally, the player understands the trigger as it happens.

2. **Initial distance.** The pursuer is established at a specific distance behind the party. The player sees/hears the pursuer and understands what is coming.

3. **Chase corridor(s).** The party moves through scripted or partially-scripted space, using their normal abilities (movement, overlays, character switching, flora planting, terminal hacking) in compressed form. The player deploys environmental levers to slow the pursuer. Decisions about routing, pacing, lever deployment, and stamina management happen in real time (with pause-planning as the reflective mode between decisions).

4. **Pursuer closes (once or multiple times).** The pursuer's speed means they close on the party when levers are not being deployed effectively. Close-approaches are not scripted guarantees; they happen when the player has not slowed the pursuer enough. Repeated close-approaches escalate: first close produces a warning beat, second close produces damage, third close catches the party.

5. **Optional: phase shift.** Some chases have multiple phases with different mechanical focus. The lockout chase has a pre-Tyreg phase (pure environmental management) and a post-Tyreg phase (environmental management plus ammo-delivery puzzle). Phase shifts are marked by a trigger event (an NPC arriving, a corridor feature changing, a pursuer behavior shift) and usually introduce new mechanical elements (a new character, a new puzzle layer, a new type of lever).

6. **Boundary or destination reached.** The party arrives at a state where the chase ends: a boundary the pursuer cannot cross, a shelter the pursuer does not enter, a destination the pursuer is not designed to follow to, or a timeout condition (the pursuer gives up after a distance).

7. **Chase-end beat.** A brief pause-frame where the party has survived. Often this is where the chase's emotional payoff lands — characters sitting, breathing, absorbing what just happened.

8. **Aftermath.** A separate scene that absorbs the chase's consequences. The aftermath is often the scene's actual emotional centerpiece; the chase itself is the mechanism that gets the characters to the aftermath's emotional state.

**Alternative: failure branch.** If the pursuer catches the party, the chase ends with the reset system firing. No chase-end beat, no aftermath in the success-register. The party respawns at the zone's last major checkpoint (default reset) or at the chase's start (consumable reset if used). Failure is a real branch, not an authored impossibility.

## Mechanical requirements for chase scenes

**Pause availability:** Pause remains available and is essential to chase design. The player is expected to pause frequently during chase scenes — reading the corridor for environmental levers, planning lever deployment, identifying portal destinations, timing character switches. Pause is not a concession to difficulty; it is the intended planning mode within the chase's real-time execution.

**Speed-up available:** Speed-up is always available during chase scenes and during any dialogue beats within them. This is a blanket game-wide commitment: speedrunners never have the speed-up button forcibly released from their hands. A single "never disengage speed-up for more than 5 seconds" achievement exists that rewards players who play the entire game at continuous 3x speed. This achievement is compatible with chase scenes because chase scenes do not force 1x anywhere.

Speed-up does not make chases easier. Pursuer speed scales with time-speed, so a 3x chase has the same speed-ratio between party and pursuer as a 1x chase. What changes at higher speed is the player's decision-window: at 3x, the player has one-third the real-time to read levers and deploy them. This rewards players who are fluent in the mechanics and creates a distinct challenge for speedrun play.

**Character switching remains available:** Essential. Chase scenes often require coordinated actions by multiple party members (one character at a terminal, another navigating, a third suppressing). Switching is the primary coordination tool.

**Ability use remains available:** Abilities are not disabled. Peris can plant flora mid-chase (if she can afford the seconds it costs). Myke can Inflame. The player's full toolkit remains. Some abilities will be more time-efficient levers than others, and identifying which ones to deploy where is part of the chase's puzzle.

**Environmental levers are the core mechanic:** The chase corridor contains a finite set of environmental tools the player can use to slow the pursuer. Levers include:
- Chelator clusters (pursuer class has protocol-hesitation around iron-feeding fauna)
- Sealable doors or barriers the party can reach first
- Flora that masks iron signatures or disrupts pursuer scanning
- Scarpet patches that affect friction and signal
- Alcoves, side corridors, or architectural features that break line of sight
- Portal terminals (Aster) that let the party skip corridor sections or access ammo caches
- Specific flora species with specific effects (Hushbloom for stun windows, Flure for decoy redirection)

Each lever has a deployment cost in time. Using a lever correctly costs the player seconds during which the pursuer closes, but produces a larger slowdown. The scene is a time-budget puzzle: which levers are available, which ones give the most slowdown for their cost, in what order to deploy them.

**Stamina matters:** Sprint is the expected travel mode. Stamina drain is primary resource pressure. Running out of stamina mid-chase means the character walks (half speed) and falls behind. This creates real tactical decisions about when to sprint and when to walk-recover.

**HP damage is possible:** Chase scenes can include HP damage from pursuer close-approaches, environmental hazards the party must route through, or pursuer abilities. Damage is real and contributes to the standard game-wide health and knockout mechanics.

**Downing mid-chase has consequences:** A character downed mid-chase triggers the standard knockout behavior. A conscious ally can drag them (half-speed), which almost guarantees the pursuer catches up; or the party can attempt to stabilize and run. If the entire party is downed, the reset fires. Mass-party-down during a chase is a real failure mode.

**Puzzle and flora state do not change during chase itself:** The chase is temporally bracketed. Flora tended before the chase is still there after. Puzzle state does not reset unless the chase fails and the catastrophic reset fires.

**Reset availability:** If the Naturalizers (or whichever pursuer) catch the party, the reset system fires. Default reset rolls back zone progress, kills zone flora, restores party. Consumable reset preserves progress if the player has an extraction item. See `trawf_timing_and_pacing_spec.md` section 4 for full reset behavior.

## Chase scene content spec

Using the scene spec framework, here is what a chase scene's spec should contain:

**Identity:** Name, location, when in game, scene type (chase scene, possibly hybrid with dialogue-frame or environmental set piece).

**Intent:**
- *Thematic intent.* What the chase is thematically about. The lockout chase is about Aster's frame breaking and Peris's competence surfacing. A Peris-sundowning chase would be about the horror of chasing someone who is walking away.
- *Mechanical intent.* What the chase teaches or tests. First chase is a tutorial for two-character control under time pressure.
- *Emotional intent.* The specific emotional register the chase should produce.

**Preconditions:**
- Party composition requirements
- Narrative prerequisites (what must have happened first)
- World state prerequisites (has the party been tagged, has the patrol been triggered, is it nighttime)

**Player verbs:**
- *Primary verbs.* Sprint, direction change, character switch, pause, limited ability use
- *Forbidden verbs.* Speed-up. Extended ability use that costs significant time. Exploration of side routes.

**Entities:**
- *Pursuer.* Specific enemy class, count, behavior pattern, speed relative to party sprint.
- *Environmental obstacles.* What slows the pursuer at specific points. Chelator clusters, iron-feeding fauna the pursuer has protocol issues with, doors that seal, terrain features.
- *Waypoints.* Specific points along the chase corridor where scripted moments fire (pursuer closes, environment reacts, character beat triggers).

**Spatial and temporal structure:**
- *Corridor layout.* Linear or branching? If branching, which branches lead to slowdowns versus dead ends?
- *Distances.* Chase corridor length. Where the pursuer starts. Where they close. Where the boundary is.
- *Timing.* How fast the pursuer is relative to the party. How long the chase takes at 1x in real time. Scripted moments and their trigger points.
- *Stamina budget.* At what sprint intensity can the party complete the chase without stamina collapse? Is the design tight (player must manage stamina carefully) or generous (even a stamina-mismanaging player can barely make it)?

**Dialogue:**
- Short reactive lines only. Usually limited to a few beats: trigger recognition, navigation under pressure, close-call reaction, boundary crossing.
- Character role shifts (who asks whom for help).
- Minimal; physical sounds carry most of the audio.

**Success and failure:**
- *Success condition.* Reaching the chase endpoint with all party members conscious.
- *Near-miss conditions.* Stamina exhausted mid-chase; a character taking a close hit; pursuer's closest approach; a lever misdeployed and pursuer gaining ground.
- *Failure modes.* Character falls behind and is caught (party must decide: drag back and risk more catches, or accept the loss and continue). Multiple characters caught (reset fires). Entire party caught (reset fires).
- *Failure consequence.* When the pursuer catches the party, the reset system fires. Default reset rolls back zone progress, kills zone flora, restores party. Consumable reset preserves progress if the player has an extraction item.
- *No authored guarantee.* Chase scenes can genuinely fail. The designer's job is to provide enough environmental levers that a player who reads the corridor competently has a path through, but the game does not force success. Players who do not deploy levers effectively get caught.

**Variants:**
- Different party compositions change the chase's character dynamics (Peris-leads vs Tyreg-leads vs Myke-leads). Design should note these variants.
- Optional route choices during the chase (does the player take the longer safer route or the shorter riskier route?).

**Connections:**
- What narrative beats set up the chase
- What the chase pays off
- What aftermath scene follows

**Open questions:**
- Per-chase design decisions not yet resolved.

## Reference instance: the lockout chase

See `lockout_chase_aftermath.md` for the scene draft (to be updated to reflect the phase and branch structure below). Key spec elements:

- **Trigger:** Tag rejection at the simulation-boundary checkpoint
- **Pursuer:** Multiple Naturalizers (institutional enforcement), faster than party sprint
- **Chase corridor:** From the checkpoint back through the Act 1 late corridors toward Endo's boundary at the edge of Zone 2
- **Phase 1 (pre-Tyreg): pure environmental management.** Aster and Peris flee the Naturalizers using the corridor's environmental levers (Chelator clusters, doors, flora, terrain). Their skill from preceding zones is being tested.
- **Phase shift: Tyreg arrives.** Tyreg catches up to the party from a side corridor. She has been Suppressing a second wave of enforcers closing in from another route; the player did not see this happening but learns of it now. Her ammo is low because she has been doing work offscreen to protect the party's escape path.

**Player choice at Tyreg's arrival:**

*Accept: Tyreg joins as temporary party member.*
- Tyreg joins the party as a controllable character for the remainder of the chase
- The player learns her kit during the chase: Suppress (freezes enemies in place), enforcement-class tag (does not trigger scanners, can walk past scan points), precise articulation and professional register
- Phase 2 becomes a three-character coordination puzzle: Aster hacks terminals for portal access to ammo caches, Peris runs ammo, Tyreg Suppresses when ammo is delivered, the chase continues
- The chase's difficulty is calibrated for a three-character party with Tyreg's kit available
- Tyreg departs at the boundary with Endo's maintained section. Her parting line is brief and character-forward. She will see the party again in Archive Depths.
- The Archive Depths recruitment then becomes the second meeting: she and the party have a minor shared history, the formal joining is about why she commits to this specific party rather than about teaching her kit

*Decline: Tyreg departs.*
- Tyreg leaves when the player declines her help. Her Archive Depths recruitment becomes the first meeting with the party.
- The side route Tyreg was clearing is no longer cleared. A second wave of enforcers closes in from a side corridor.
- The chase has more pursuers from more directions. Difficulty scales significantly.
- Escape is possible only through a specific expert solution, described below. First-play players who decline will typically fail the chase and trigger the reset. Expert or replay players can attempt the solution.
- The decline-path is gated by specific mechanical knowledge the first-play player does not have. The game does not telegraph the solution; players discover it through experience across the game or through community knowledge.

**The decline-path expert solution:**

The solution exploits a late-game mechanic (portal stunning via Hushbloom or equivalent stun plant) applied to a specific corridor configuration. It requires:

1. **Prior knowledge that portals can be stunned.** Players first encounter this mechanic in Act 2 or early Act 3, where a pursuer emerges from a portal and the player must stun it to survive. The game does not teach this mechanic in Act 1; a decline-path player must have prior playthrough knowledge or community knowledge.

2. **Identifying the specific offshoot portal.** One portal in the lockout corridor leads to a small offshoot chamber with hide spots. The player must know which portal and know it exists before attempting the solution.

3. **Engineering a gap window.** Aster and Peris need enough distance from the Naturalizers to execute the hack and the stun-throws without being interrupted. This gap is opened through prior environmental lever deployment — sealing a door behind them, routing through Chelator clusters, flora-mask corridor. The decline-path player must know where the gap window opens.

4. **Double portal stun (one on each side).** Peris carries at least one stun plant. Aster hacks the portal open. Both characters enter the offshoot. Inside, they stun the offshoot's exit portal (the one leading back to the main corridor). They then exit back through the entrance portal briefly and stun that portal from the main-corridor side before re-entering. This seals both portals temporarily, making the offshoot a locked pocket Naturalizers cannot enter.

5. **Using the tight-hide spots in the offshoot.** Two tight-hide spots exist inside the offshoot, one per character. Aster and Peris each take one, breaking line of sight. Naturalizers patrol past the main corridor, lose aggro over the search cycle, and eventually move on. When the stuns expire and the portals come back online, the Naturalizers have already given up and the party can exit.

**Why this solution works as expert-only:**

No piece of this solution is discoverable by accident. Portal stunning is a late-game mechanic. The offshoot portal's existence is not flagged as mechanically important. The gap window must be engineered through environmental levers, not just encountered. The two-portal stun pattern is something a player who knows the mechanic has to reason about — most early portal-stun uses involve one portal, not two. The hide spots are the game's standard tight-hide mechanic but applied in an unusual context.

A player who figures this out on first play is either executing prior knowledge from a community or replay run, or has assembled the pieces through unusual depth of attention. Either way, the solution rewards total system mastery rather than accident.

**Why this solution fits the characters:**

The solution is specifically Peris's register rendered tactically. Her perception reads corridors for the exits that are not marked. Her social-worker register reads situations for absences that can hide you. The expert path is not outrun, not outfight; it is *step out of the pursuit's line of sight entirely*. The Naturalizers walk through the corridor the party was just fleeing, and the party is not there anymore.

It is also genuinely two-character. Aster's hack opens the portal; Peris carries the stun plants and selects the hide spots; both characters execute stun-throws; both find hides. Neither character can solve this alone. The Aster-Peris-solvability commitment is honored not as "a solution exists" but as "the solution requires both their specific kits."

**Implications for game-wide design:**

- The portal-stun introduction scene (Act 2 or early Act 3) needs to be recognizable enough that a player who learns the mechanic will retroactively wonder if it could have solved the lockout chase. The retroactive recognition is part of the hidden-solution payoff.
- The offshoot chamber needs to exist in the lockout corridor as real geometry, accessible during the chase, not flagged as specifically useful by the game's UI.
- The tight-hide spots inside the offshoot follow standard tight-hide mechanics (capacity-limited, search-cycle behavior, listening-through-cover) but in an unusual location.
- The specific placement of the offshoot portal, the gap window, and the hide spots is corridor-level spec that needs to be nailed down during implementation. This is left as an open design task.

**Why the accept/decline structure matters:**

The accept-path is the first-play expected route. Most players will accept. They get a tutorial for Tyreg's kit in the context of a tense chase, then see her again in Archive Depths with recognition.

The decline-path is the expert-knowledge route. It provides a hidden challenge for players who know the game well, consistent with the game-wide Aster-Peris-solvability commitment (every puzzle has a hidden two-character solution, usually requiring late-game knowledge).

The decline-path's existence also means players have real agency over how they engage with Tyreg's character. A player who distrusts enforcement-class can reject her help. The game honors the refusal but makes the player pay for it, which is the honest design: the Naturalizers are dangerous, enforcement-class help is genuinely useful, refusing that help for principled reasons has consequences. The game does not let the player decline and then softly guide them through anyway.

- **Boundary:** Endo's maintained wall. Naturalizers cannot cross into unmaintained territory.
- **Chase-end beat:** Party breathing at boundary. Naturalizers standing still on the other side. Endo visible working at a distance. In accept-path, Tyreg is there with the party at the boundary; she says her parting line and departs. In decline-path, Tyreg is gone; the party survived (if they did) without her.
- **Aftermath:** Aster and Peris alone at the boundary. Sitting-on-floor scene with the fugacity exchange and "focus on what matters, right?" The aftermath is just them regardless of accept/decline path.
- **Character role shifts:** Aster asks Peris for navigation for the first time. Peris uses sensory register tactically for the first time. In accept-path, Tyreg as enforcement-class intervenes procedurally. Three character pivots in one sequence.

**Tyreg as pre-recruitment temporary party member:**

This is the game's first instance of a party member being temporarily controllable before their formal recruitment. The pattern expands the character-introduction structure the game has been using:

- **Glimpse** (Marco in Residential Rings, Myke in Stacks NPC appearance): character appears as NPC, characterized but not played
- **Temporary control** (Tyreg in lockout chase, accept-path only): character briefly joins as controllable, teaches their kit
- **Formal join** (Tyreg in Archive Depths, Myke in Supply Lines, etc.): character commits to the party for the long arc

Not every character needs all three stages. Marco is glimpse-only (he never joins). Myke is glimpse plus formal join (no temporary control phase because his Stacks decision affects whether the Mother Flure chamber run has him). Tyreg gets all three (glimpse during lockout if accept, temporary control during lockout if accept, formal join in Archive Depths). The specific arc reflects the character's narrative weight and the player's existing relationship with them.

**Why Tyreg has temporary-control rather than glimpse-only:**

The lockout chase is the game's first real test of the player's environmental-lever skill under time pressure. Adding Tyreg as a controllable character gives the player an additional kit to learn in the chase's context, not as a tutorial interruption but as a capability that arrives when the player needs it. The player meets Suppress and its utility in a moment of actual utility. Archive Depths then uses the learned kit, not introduces it.

The decline-path also matters: the player who refuses temporary control is refusing *help they would find useful*, which means their principled refusal has real cost. This is a choice the game asks to be earned with knowledge or with acceptance of catastrophic failure.

## Anticipated future chase scenes

These are not yet fully designed but are likely to exist in the game. Spec each one using the framework above when they come up for drafting.

**Patrol-failure chases (zone-specific, recurring):**
The party is caught outside of the usual stealth-avoidance pattern in a Checkpoint Plaza or Archive Depths corridor. They flee a specific patrol until the patrol resets or they cross into unpatrolled territory. Shorter than the lockout chase. Less narratively weighty. Emergent rather than scripted. Expected: 2-4 of these across Act 2.

**Swarm-overwhelm flights (zone-specific, scripted):**
The party is in a corridor when a specific swarm event triggers (cytokine storm, sudden Neutrophil infiltration at night, Meeb patrol that has aggroed on them specifically). They retreat to shelter while the swarm pursues. Can trigger emergent in any corridor but also has scripted instances tied to specific zones (a cytokine storm is a Zone 3 event; Neutrophil infiltration is night-specific in Zone 2 mid-late).

**Peris-sundowning chases (late game, scripted):**
Peris's sundowning has her wandering off, and the party has to reach her before she reaches danger (a breach, an iron-dense zone, an open night corridor). The pursuer is time, not an entity. The party is pursuing, not fleeing. This inverts the usual chase polarity but follows the same structure. Expected: 1-2 of these in late Act 2 or Act 3. Deeply tied to the game's emotional thesis and should land with scripted-dramatic weight.

**Endgame crisis chases (scripted, climactic):**
The civilization's final collapse produces environmental-collapse chases during the cure assembly. A corridor is actively collapsing; the party must traverse before the collapse reaches them. Different from pursuer chases because the threat is structural rather than intentional. Structure mostly the same.

**NK infiltration (night-specific, partially emergent):**
Neutrophils squeeze through the failing BBB at night and chase characters outside of shelter. Unlike other pursuer classes, they are lethal on contact (40 HP/sec). This is closer to horror-survival than scripted chase; the party must reach shelter before contact. Zone-specific and difficulty-scaled.

## Common design decisions across all chases

**Pursuer speed tuning.** Pursuers are faster than party sprint speed. The chase is survivable only through environmental lever deployment. A 10-15% speed advantage for the pursuer at base sprint is a starting value to playtest; tuning depends on how many levers the corridor offers.

**Lever density.** The chase corridor should provide enough environmental levers that a competent player who reads the corridor has a path through. The exact count depends on corridor length and pursuer aggression. A minimum of 3-5 levers for a medium-length chase; more for longer ones. Levers should be recognizable on first inspection — the player should understand what the Chelator cluster or the sealable door offers without tutorial text.

**Chelator-mediated slowdowns as signature move.** The Chelator protocol-hesitation beat is one of the game's most elegant mechanics and recurs in chase scenes where it fits. Not every chase; just the ones where the pursuer class has a protocol hesitation around iron-feeding fauna. Naturalizers have this hesitation. Other pursuers may not.

**Stamina tuning.** Chase stamina budgets should assume a competent player manages stamina reasonably. A player who sprints the entire chase should run out before the end and have to walk-recover briefly. A player who manages stamina (sprints and walks alternately, uses levers efficiently) should arrive with stamina to spare. This creates real tactical decisions without requiring perfect play.

**Audio mix.** Chase audio is specific: compressed, directional (pursuer audio behind), breath-forward for the party, environmental cues (water sounds for navigation, patrol banter for horror). The soundtrack during chase scenes follows the "no genre shifts during combat" rule from the TRAWF soundtrack prompts — tension layers on top of the zone's register, not replacement music.

**Dialogue density.** Chase dialogue is always sparse. If a scene needs more than 3-5 lines of dialogue during active chase, the chase is probably too long or the dialogue should be moved to the aftermath. Dialogue during chases can be speed-fast-forwardable like any other dialogue.

**Pause and speed-up both essential.** Pause is the planning mode; speed-up is the execution mode for players who want compressed runs. Both should be available throughout. Design accommodates players using either or both to their preference.

**Levers re-deploy.** Levers consumed in a chase do not re-regenerate during the chase. A sealed door stays sealed (which helps the party who sealed it but also blocks retreat if they need to go back). A Chelator cluster that has engulfed a Naturalizer is now a cluster with one more Chelator and one less Naturalizer — potentially stronger or weaker depending on the state. This produces persistent-consequence play within the chase itself.

## Lock status for chase scenes

The structural pattern (trigger → initial distance → corridor → lever deployment → optional phase shift → boundary → chase-end beat → aftermath, with failure branch via reset) is LOCKED for all chase scenes. Individual chase scenes vary in content, specific pursuer, specific levers, phase structure, and aftermath, but the shape is consistent.

Mechanical requirements (pause available, speed-up available, character switching available, stamina primary resource, environmental levers as core mechanic, real failure states via reset, dialogue fast-forwardable) are LOCKED. Tuning values (pursuer speed advantage, lever density, stamina budgets, chase corridor length, phase-shift triggers) are FLEX.

The speedrun-compatibility commitment is LOCKED across the game, not just for chase scenes: speed-up is never forcibly disabled, and the "5-second rule" speedrun achievement is valid throughout every scene in the game including dialogue.

## Related docs

- `trawf-scene-spec-framework/SKILL.md` — the general scene spec framework chase scenes fit within
- `lockout_chase_aftermath.md` — the reference chase scene (Act 1 lockout)
- `survival_gameplay_feel.md` — encounter feel doc; chase scenes are a distinct case from tactical encounters but share some sensory vocabulary
- `trawf_timing_and_pacing_spec.md` — timing values chase scenes tune against
- `enemy_ecosystem.md` — pursuer classes and their behaviors (Naturalizers, Flares, Redactors, etc.)
- `to_rust_gdd_v01__7_.md` — GDD sections 3.3 (health/knockout/rest), 4.3 (day/night), 6 (entity behavior)

## Open questions

**Resolved by this revision:**
- Whether chase scenes have authored or real failure states: **real failure, reset system fires**
- Whether speed-up is available during chase scenes: **yes, always, including during dialogue**
- Whether dialogue can be fast-forwarded: **yes, no forced 1x anywhere in the game**
- Whether Tyreg appears before Archive Depths recruitment: **yes, during the lockout chase phase 2**
- Whether Tyreg is temporary-controllable or NPC-only during the chase: **temporary-controllable on accept path, absent on decline path**
- What the decline-path expert solution is: **portal-stun double-seal of an offshoot with tight-hide spots**

**Still open:**

*Lockout chase specifics:*
- How Tyreg communicates her side-route clearing work when she arrives. Does she mention it explicitly ("I thinned the other patrol; this is what is left of my ammo") or leave it inferrable from her state and a look back down the corridor she came from? Default leans toward brief mention plus visual cue.
- What the parting line is when Tyreg exits at the boundary. Procedural-register ("I need to submit a report; the documentation will not match") versus pointed ("Who tagged you? Never mind. I'll figure it out") versus practical ("You have somewhere to be. So do I"). Default leans practical.
- Specific corridor geometry: where the offshoot portal is, where the gap window opens up, where the tight-hides are inside the offshoot. Implementation-level spec needed when the scene moves to Godot.
- Whether there is a subtle environmental hint for the expert solution (a dead Hushbloom near the offshoot portal suggesting someone tried this before) or whether the solution is entirely knowledge-gated without environmental hint. Default: no environmental hint; total knowledge gate.

*Portal-stun introduction scene:*
- Where exactly in Act 2 or early Act 3 the portal-stun mechanic is introduced. Candidates: Archive Depths (Tyreg's recruitment beat), Filtration Membranes (barrier-crossing set piece), Maintenance Warrens (Oli's recruitment). Needs design decision for where the tutorial lands.
- Whether the portal-stun tutorial is scripted (a specific moment in a specific scene) or emergent (a situation the player encounters in gameplay where stunning a portal is the obvious survival move). Scripted is easier to guarantee; emergent is richer.

*Chase framework generally:*
- Whether other chase scenes have expert-only alternative solutions or whether the lockout is the only chase with this structure. Peris-sundowning chases, swarm-overwhelm flights, endgame crisis chases, NK infiltration — do any of these have hidden two-character solutions gated by late-game knowledge? Default: the lockout is the canonical expert-solution chase; others may or may not have analogs depending on their specific design needs.
- Whether Peris-sundowning chases use the same environmental-lever mechanic or a different one (since there is no intentional pursuer to slow down, and the party is pursuing rather than fleeing).
- Whether the endgame crisis chases have levers that act on environmental collapse rather than on intentional pursuers. The mechanic would be "find a way to stabilize the corridor faster than it collapses" rather than "slow the pursuer."
- How chase scenes interact with the overlay-fidelity sleep-deprivation debuff. A tired character in a chase has unreliable overlays; this might be too punishing, or exactly the right horror. Playtest question.
- Whether chase scenes can trigger from emergent world state (Naturalizer catches the party during normal traversal) or only from scripted narrative triggers. Emergent chases probably work the same way mechanically but are shorter and have simpler phase structure.
- How character voice shifts during chases. Tyreg's precise articulation may crack under chase pressure in ways the dialogue can reflect.
