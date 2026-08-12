# TO RUST AS WE FALL — Canonical GDD (v02 rebuild)

This is the canonical Game Design Document, rebuilt from the mini GDD as the spine. Each section absorbs from canonical project docs (rosters, scene specs, worldbuilding files) rather than carrying forward the drift of the previous bloated GDD. Sections still pending fill-in are marked with their canonical source.

Status: in-progress rebuild. Sections 1, 2.1, 2.4, 2.5 (day/night) are drafted; everything else is stubbed against the agreed TOC and pulls from the docs noted in the brackets.

## Contents

- **1. Pitch and overview**
    - 1.1 Thematic spine
- **2. Core mechanics**
    - 2.1 Control model
    - 2.2 Asymmetric perception
    - 2.3 Forgetting system
    - 2.4 Resource systems
    - 2.5 Day/night cycle and shelters
    - 2.6 Indirect-solution puzzles
    - 2.7 Ecological threats (overview)
    - 2.8 Diegetic tutorial philosophy
- **3. The cast**
    - 3.1 Aster
    - 3.2 Peris
    - 3.3 Endo
    - 3.4 Myke
    - 3.5 Oli
    - 3.6 Tyreg
    - 3.7 Marco (recurring NPC)
    - 3.8 Plexa (substrate, never on-screen as party)
- **4. World structure**
    - 4.1 Three zones, concentric
    - 4.2 Acts, shelters, and boss landmarks
    - 4.3 The map at zoomed-out scale
    - 4.4 Named regions
    - 4.5 Mega-landmarks
    - 4.6 Path geometry and shelter nodes
    - 4.7 The center and the singletons
    - 4.8 Central facility political economy and the failed re-entry
    - 4.9 The preservation architecture is invisible to the player and renders as institutional infrastructure
    - 4.10 The outer regions depopulated before the enemies arrived
    - 4.11 The same underlying failure manifests differently across the capitalist and socialist districts
    - 4.12 The growth-versus-stability fault line produced two factions, and anamnesis is the answer to both
- **5. Institutional vocabulary and worker codes**
    - 5.1 The encoding scheme
    - 5.2 Why this format works thematically
    - 5.3 What the encoding implies about the institution's database
    - 5.4 How the codes function in practice
    - 5.5 Class codes catalog (current state)
    - 5.6 Simulo-care and the Psyknapse gate
    - 5.7 The cross-class propaganda system suppresses envy through opposite-direction propaganda
    - 5.8 Credits as formal currency with informal worker economies in parallel
    - 5.9 The caste is emergent and beloved because specialization delivers real identity-goods
    - 5.10 A reassignment reads from below as a Separations and Transport analyst arriving with a therapist
- **6. Aesthetic**
    - 6.1 In-game visual register
    - 6.2 Cultural-architectural register: post-solarpunk in decline
    - 6.3 Restricted palette
    - 6.4 The map view
    - 6.5 Sky
    - 6.6 Ground
    - 6.7 Color register by zone
    - 6.8 The pink-red saturation rule
    - 6.9 Bibliography for the look
    - 6.10 Production tooling
- **7. Enemy ecosystem**
    - 7.1 Roster
    - 7.2 Siderophores compete with siderophores
    - 7.3 Candids poison the environment for everyone else
    - 7.4 Meebs eat what they can engulf
    - 7.5 Naturalizers have complicated immune politics
    - 7.6 Gnawers hunt metabolic signatures, any metabolic signatures
    - 7.7 Flares are ecosystem detonations
    - 7.8 Spikers connect to anything that moves
    - 7.9 Tanglers hunt neural activity
    - 7.10 Toxos are everyone's target
    - 7.11 Redactors are invisible to normal perception
    - 7.12 The inter-enemy matrix
    - 7.13 What the ecosystem changes for gameplay
    - 7.14 The political ecology
    - 7.15 Visual specifications (image generation prompts)
- **8. Flora system**
    - 8.1 The roster
    - 8.2 The network property (applies to all tended flora)
    - 8.3 Hiding-tier mapping
    - 8.4 Peris's worker vocabulary
    - 8.5 Ambient flora
    - 8.6 Sensory signatures
    - 8.7 Flora states (healthy / dormant / stressed / dying / dead)
    - 8.8 Flure (dedicated entry)
    - 8.9 Capbage (dedicated entry)
    - 8.10 Gasafoetida (dedicated entry)
    - 8.11 Resolution Roots (puzzle-only flora)
    - 8.12 Visual specifications (image generation prompts)
    - 8.13 Implementation notes
- **9. Tutorial sequences**
    - 9.1 Aster's workspace tutorial
    - 9.2 Peris's workspace tutorial
    - 9.3 What the tutorial pair establishes
    - 9.4 The tutorial-seed reward pattern
- **10. The cure**
    - 10.1 Discovery principle
    - 10.2 Danger zone safety from external survival mechanics
    - 10.3 The components (roster)
    - 10.4 Per-component specs
    - 10.5 The rogue tenth component
    - 10.6 The cure as encoded relationship
- **11. Bosses**
    - 11.1 Loca (Act 1 boss)
    - 11.2 The Paranucleus (Act 2 boss)
    - 11.3 Final encounter
- **12. Major set pieces**
    - 12.1 The lockout chase (Act 1)
    - 12.2 Mother Flure encounter (Act 1)
    - 12.3 Endo at the wall (Act 1)
    - 12.4 Processing Station Sequence (Act 1, end)
    - 12.5 Stacks anxiety (Act 1)
    - 12.6 Nustle / Nusselt scene (Act 2)
    - 12.7 Marco set pieces
    - 12.8 Endo and Aster barrier scenes (Act 1)
    - 12.9 The Psyknapse foil (Act 1 to Act 2)
    - 12.10 Love is dimensionless (Act 2 to Act 3)
    - 12.11 The settlement that won its war and lost to the land (Act 3)
- **13. Endings**
    - 13.1 Design philosophy
    - 13.2 The endgame return sequence
    - 13.3 The four endings
    - 13.4 Two-character completability
    - 13.5 The decline-vs-compensation curve
- **14. Achievements**
    - 14.1 Design principles
    - 14.2 Locked achievements
    - 14.3 Candidate additions
    - 14.4 Innovations
- **15. DLC: Roguelike mode**
    - 15.1 Core concept
    - 15.2 Narrative framing: timeline ambiguity
    - 15.3 Playable characters
    - 15.4 DLC-exclusive cast
    - 15.5 Systems inherited and modified
- **16. Stretch framework**
    - 16.1 Four design principles
    - 16.2 World degradation as the unifying mechanism
    - 16.3 The three artifact types
    - 16.4 Per-stretch variables
    - 16.5 How the framework is used
    - 16.6 What the framework commits the design to
- **17. Open design questions**
    - 17.1 Cross-cutting
    - 17.2 Control model and UI
    - 17.3 Forgetting system and asymmetric perception
    - 17.4 Cure components, per puzzle
    - 17.5 Bosses
    - 17.6 Shadow-solution layer (section 2.6)
    - 17.7 Tutorials (section 9)
    - 17.8 Enemy ecosystem (section 7)
    - 17.9 DLC roguelike mode (section 15)
    - 17.10 Stretch framework (section 16)
    - 17.11 Source-doc gaps
    - 17.12 Pending scenes, assignments, and mappings
- **18. Bibliography and research grounding**
    - 18.1 Philosophical and political theory
    - 18.2 Literary and cultural references
    - 18.3 Game design influences and method
    - 18.4 Real-world institutional and historical patterns
    - 18.5 Neuroscience and pathology
    - 18.6 Botany
    - 18.7 Chemical engineering
    - 18.8 Visual, aesthetic, and production references
    - 18.9 Personal and methodological grounding
- **19. Scope and current status**
    - 19.1 Scope
    - 19.2 Current state
    - 19.3 Open priorities

## 1. Pitch and overview

> There is a discipline adapted to the schools, and which it is profitable to have studied, but which has no direct bearing upon action.
>
> Francis Edgeworth (1889), on Walras's *Éléments d'économie politique pure*

Candidate epigraph. The simulation is exactly that discipline, a model internally consistent and worth studying that has lost contact with the living body it runs on, and anamnesis is the return to action the model forgot. The line comes from Georg Blind's *The Entrepreneur in Rule-Based Economics* (section 18.1), whose rule-based framework grounds the growth-versus-stability spine in sections 4.12 and 1.1.

Two characters navigate a decaying civilization from inside a dying brain. One forgets. The other only sees data, not texture. Together they compensate. Apart, they fail. Difficulty rises because the characters degrade, not because the levels get harder.

The world is a neurovascular unit. Every character is a cell type. Every threat, every district, every piece of infrastructure maps onto brain biology. The civilization built a simulation to suppress envy and curate perception, and the cure worked: nobody is unhappy with what they have. The cure is also killing everyone, because envy was the regulatory signal that let the body notice when something was wrong. Stripped of comparison, the population cannot see the barrier is failing. Stripped of aspiration, nobody is motivated to fix it. The brain forgets itself.

It is a 3D adventure-puzzle with survival, indirect-control, and ecological threats. References include Rain World, Dark Souls, Pathologic 2, Eastward, Subnautica, Rimworld, and Duskers.

Tagline: "What's it like to remember in a world everyone forgets?"

Alternate elevator pitch, in the contemporary cultural register: this is a game about fighting brainrot. The literal sense (the civilization is a brain, its degeneration is medically accurate Alzheimer's progression) and the cultural sense (Documentation Load Reduction destroying originals for AI summaries, Portcut replacing reading, the wellness feed displacing care, simulo-care's metrics gate as epistemic-luxury access control, the institution's surface frames obscuring structural realities) reinforce each other. The design's mechanical thesis is the same in both registers: pay attention or the world degrades faster. Asymmetric perception, shadow solutions, the optional richness layer, and the four-ending differentiation all reward focused engagement; doom-scrolling past content makes the world degrade. The hook is brainrot-economy compressed into a tweet ("fight brainrot in a brain civilization") and the body of the work hides a literary thesis. Disco Elysium architecture: casual hook, depth on inspection.

It is the genre fiction adaptation of a real intellectual project. The frame is post-structural and critical-theory work on institutional knowledge production, surveillance, the manufacturing of compliance through curated information environments, and the political economy of the labor that keeps systems running. The world is overdetermined enough to admit multiple critical lenses, and the design treats them as compatible rather than competing: the player who reads the world through any of them finds the design responding.

Arendt and Foucault are the most foundational presences. The banality of evil renders through institutional cells doing their jobs to death, with the Pattern Wrap puzzle's Timeline 4 enforcer (filing the closure order, cataloguing the equipment, neutral-faced) as the canonical moment. Foucauldian disciplinary power renders through scan-grid checkpoints, tag-protocols, the institutional scan that decides who counts and who does not. The lockout chase is the moment the apparatus turns its scrutiny on the player.

The labor analysis is canonical to the rogue component's history (section 10.5): the cure repurposed for productivity, workers becoming hyper-effective until they made themselves obsolete, the third party that valued metric performance over medical efficacy, the deployment that "worked" by the productivity metric and catastrophically failed by the medical one. The civilization's death is also a labor history.

Derrida's hauntology runs through the design as a whole. The institution is being run by ghosts: dead researchers whose archives still process as live signals, suppressed cure work that persists in fragmentary form, construction-era workers whose tags still register in systems even after their bodies are sealed in the chamber. Hauntology is also Peris's condition: she is being erased while still alive, and the people who knew her are losing access to her even as she stands in front of them. The Flow Aligner ruin makes this explicit, with the synthesis beat ("Specters, of Marks") jointly produced by Aster's analytical register and Peris's relational register; what the institution cannot hear in either register alone is what the line names.

Kant on judgment as acting without rules surfaces in the missing-chapter writing in Ending 4, where what fills Arendt's blank is not the application of theory but the capacity to act without certainty (Aster does not know he is paraphrasing Kant). Augustine's "love is the weight of the soul" surfaces in the shelter scenes as the quietest theoretical commitment the game makes.

Six damaged book fragments scattered across the late game form a philosophical progression, each tied to a character and a question. R. Douglas Fields's *The Other Brain* (the surviving title fragment reads "...ther Brain") is Aster's, asking whether truth-tellers are rewarded; the answer the civilization gave is that they are destroyed. Joel Mokyr's *A Culture of Growth* (reading "Culture... Grow") is the civilization's own fragment, asking whether the cultural conditions for open inquiry can be lost entirely. Hannah Arendt's *The Life of the Mind* (reading "the Mind") is Aster and Peris's shared fragment, the missing-third-volume hinge that the best ending fills. Amartya Sen's *Development as Freedom* (reading "Freedom") is Oli's, asking whether the suffering that required triage could have been structurally prevented. James Baldwin's *The Fire Next Time* (reading "Fire") is Myke's, asking what happens when the system's innocence is the crime. Michel Foucault's *Discipline and Punish* (reading "Discipline") is Tyreg's, asking whether the system produces the categories it then punishes. Each fragment moves one step further back in the causal chain, from consequences to causes to the conditions that produce causes to the mechanisms that manufacture the categories themselves.

Fragments are mechanically rewarding as well as thematically. Recovering and reading a fragment grants its owner-character an ability upgrade in the direction the book asks them to grow. Specific upgrade designs per character are tracked in the (currently undrafted) `book_fragments_spec.md` and flagged in section 17.11 as a consolidation gap.

The neuroscience is a substrate, not an allegory. The locus coeruleus does degenerate first in Alzheimer's; tau tangles do propagate prion-like; iron dysregulation is a known pathology. The biological specifics are accurate enough that a neuroscientist can read the world as a working model of neurodegeneration.

The thesis is never stated in-game. The player discovers it by asking why anything is the way it is and following the answer down.

It works mechanically because the central pair has asymmetric perception and you cannot play either of them in isolation for very long. Peris sees, smells, intuits, and forgets. Aster reads data overlays, abstracts patterns, and cannot feel. The puzzles, the navigation, the combat, and the resource economy all require both registers. The relationship is the gameplay.

It works narratively because the world is dying on a timer the player can feel. Not a doom counter, but a creeping degradation: shelters that were safe become hostile, infrastructure that worked stops working, characters who were lucid become confused. The four endings (worst, partial, bittersweet, best) express how much of the cure the player assembled. The worst ending is the default if you only do the main path. The best requires every component, every shelter explored, every ally recruited. Effort is rewarded with the people you love still being themselves.

### 1.1 Thematic spine

The game's core argument is a chain: responsibility creates the conditions for trust, trust enables the sharing of secrets, shared secrets resist institutional capture, and the relational practices accumulated through this chain become the externalized cure. The chain is what the game is about beneath the cure-retrieval plot. The cure components are not the solution to the civilization's collapse; they are the externalized form of the relational work the party has been doing all along. The civilization died of a failure of responsibility; the cure is responsibility made retrievable.

The philosophical scaffolding is Derrida. *Foi et savoir* (1996) supplies the faith-precedes-knowledge structure: every act of speaking presupposes faith in the addressee, so faith comes before knowledge rather than following from it. The Ouroboros secret-sharing scene (section 11.2) is structured by this. Peris's "we are not doomed" is faith, not knowledge, and the trickle-clown-effect insight Aster speaks afterward is knowledge that the faith made speakable. The order matters across the game's revelations: characters extend trust before they have evidence it will be honored, and the evidence arrives because the trust was extended.

*Donner la mort* (1992) supplies the responsibility-as-irreducibly-singular structure: responsibility is the specific response of a specific person to the specific call of a specific other, and it cannot be generalized into institutional function. Each party member's responsibility is non-substitutable. Peris's specific clients, Aster's specific predictions ignored, Endo's specific wall, Myke's specific community, Oli's specific triage decisions, Tyreg's specific protocol-adherence. The institution wants these responsibilities to be generalizable functions (interchangeable workers performing interchangeable roles); the party's growth is into being irreducibly specific responders. The civilization's collapse is, at the deepest level, the consequence of having generalized away the specificity that responsibility requires.

Trust as the bridge between responsibility and shared secrets is the chain's middle term. Trust accumulates through demonstrated responsibility: party members extend it because the other has shown care in the way only that other can show. The shared secrets that follow are not strategic information; they are commitments that can only exist between people who have done the responsibility-and-trust work. The Ouroboros secret is shared because Peris and Aster have built the responsibility-trust foundation through every prior scene. The institution cannot capture the secret because the institution is the failure of responsibility that made the secret necessary.

Donner la mort runs this the other way as well: the secret is not only what responsibility produces but a condition of it. Derrida reads this through Abraham, who keeps silent about what he has been commanded and tells no one, because to speak it, to give an account of it in the general terms anyone could check, would dissolve the singular relation into ethics-in-general and betray it. The secret is what holds the relation singular, and singular responsibility is what the secret makes possible, so the two depend on each other and neither is simply first. The trust between them is faith extended ahead of its grounds in the sense of Foi et savoir, the leap the game gives Peris when she says they are not doomed. None of this needs a figure laid over it; the dependence is the content. What the dependence makes legible is the cost of the institution: the demand that everything be sayable and accountable in general terms is the demand that there be no secret, and Derrida's point is that this is the same as the demand that there be no singular responsibility, only substitutable function. A world in which nothing can be kept has nothing left but compliance, which is not response.

The disease is a different shape, or rather it is the one place a closed figure belongs. The simulation holds the civilization at the end of its own history, a history treated as complete, so that nothing new arrives and the system only incorporates and reshuffles what was there from the start. This is what the Ouroboros scene is named for (section 11.2): the snake feeding on its own already-given material, the dissatisfaction signal suppressed, the steady state that has lost the capacity to correct itself. What such a closed system cannot produce from inside its own accounting is the new, the equilibrium-disturbing variation Schumpeter names and the alertness that works it back into coordination that Kirzner names, together Blind's variation-selection-retention (section 4.12 and section 18.1). The new has to enter from outside the system's own derivations, which is why the positive program set out below is about restoring the signal and reopening the history rather than perfecting the loop.

Enemies are failure modes of responsibility. Each enemy type embodies a specific kind of responsibility-failure that the civilization stopped maintaining. Working assignments for the failure-mode mappings: siderophores as the failure of resource stewardship, Naturalizers as the failure of just enforcement, Redactors as the failure of transparency in enforcement, Spikers as the failure of regulatory self-control, Tanglers as the failure of cleanup, Gnawers as the failure of containment, Chelators as the failure of distribution, Crust as the failure of maintenance, Hidra as the failure of authentic signal, Toxos as the failure of self-determination, Candid as the failure of mutual respect, Locusts as the failure of containment of consequences. The party's work against the enemies is not combat but maintenance, upholding the responsibility the enemy represents the failure of. This grounds the existing mechanic that the party rarely defeats enemies through conventional combat: they manage ecology, use environmental affordances, plant flora. The mechanic is responsibility-keeping rather than violence.

Cure components are externalized relational practices. The invisible architecture (the Gottman mapping, present in the canon but not named in-game per the no-naming principle) gives each component its relational-practice register. The Iron Redistribution Chaperone is the practice of building love maps (knowing each other in detail). The Inflammashunt is the practice of managing conflict (resolution rather than escalation). The Pattern Wrap is turning toward (responsive attention to bids for connection). Each component is a kind of relational work that, sustained, would have prevented the disease. The cure works because the party has been doing the practices the components externalize; the cure is what those practices crystallize into. The retrieval mechanics for each component should embody the practice they externalize, so the player who retrieves the component has performed (mechanically) the relational work it represents.

The word "love" has been displaced from the civilization's vocabulary. People say "lust," "hospitality," and "bonding"; "love" itself has been commercialized to mean "doing acts for people that they like." The Tag Day enforcer banter is the institutional displacement (NK-01 and NK-02 talk about courtship, approach, dates, ghosting). The Nusselt scene is the worker-vocabulary displacement (Peris describes what dogs did as "universal hospitality," and the oldest word she knows for the closeness she values is "nustle," not love). The Augustine passage in the shelter scene carries the weight it does because Peris and Aster, in private, are preserving the word as it was meant.

Two prior-era simulo product lines, named in the love-is-dimensionless origination scene, illustrate the commercialization concretely. Simulo-skins ran the jingle "Simulo-skins, love at first site... love when you turn on the light... as easy as just 1-2-3... turn it on for you and me," with the tagline "love at a good price, that's nice." The Love Linguistics course trained workers to "speak the love languages." Both products belong to the era before the game's timeline; Peris and Aster recall them as nostalgia, not as current institutional offerings. They are the cultural mechanism by which "love" became "doing acts for people that they like."

The transmission dimension closes the chain. Responsibility, trust, and secrets are not held only by the party; they are passed forward. The best ending's Aster-writes-the-missing-Arendt-chapter beat is the transmission externalized: the secret becomes book becomes future readers. But the transmission also happens within the game's body. The recurring NPCs (Marco, Peris's former clients) and the book fragments are evidence that secrets get passed on across generations. Marco's improvised survival is teaching the party knowledge that came to him from his own teachers. The book fragments are the externalized form of past secret-keepers' transmissions to future readers. The Peris-tends-forget-me-nots-at-every-shelter pattern is in-game transmission: each shelter she tends accumulates into a record of care that other characters and the player can read. The endings differentiate by how much transmission has happened: the worst ending has the chain broken (no secrets passed, no cure assembled), the best ending has the chain complete (the missing chapter filled, the cure built, the people the player loves still themselves).

What the spine asks of the player is not to be told but to discover. The thesis is never stated in-game (per the existing principle in this section). The player discovers the chain by playing through it: extending trust to party members before they prove worthy, doing the relational work that the puzzles require, finding the cure components through the practices they externalize, encountering the enemies as failure modes that the responsibility-work could prevent, and reaching endings whose differences encode how much transmission has happened. The spine works because every mechanic is also an instance of the chain. The player who pays attention finds it; the player who does not still plays the game.

The defeatism risk (the player coming away with "society is broken, cure the disease, longevity fixes things") is addressed by the chain's structure. The cure is not the substitute for social change; the cure is what social change crystallizes into when sustained. The longevity the cure produces is not the end-goal; it is the consequence of having maintained the relational practices that prevent collapse. The endings make this differentiation legible: the worst ending has longevity-without-relational-work (and is therefore not a real cure, just survival without meaning), the best ending has the relational work complete (and the longevity is its byproduct, recognizable as such because the people who survive are still themselves). A player who reads the game as "cure the disease and society is fine" has missed the chain; the chain is what the design is for.

The deeper answer to the same risk is that the game carries a positive political program, not only a critique. The spine is the deconstruction of growth-versus-stability (section 4.12), and its resolution is anamnesis read as the restoration of error-correction, the feedback a living system needs in order to sense when to hold and when to risk. That is a constructive lever rather than the familiar closing gesture toward mutual aid and indigenous knowledge, and it is grounded in Georg Blind's rule-based economics (section 18.1), where the cure corresponds to slow, durable second-order rule change rather than instant, hollow operational fixes. The actionable claim is that a society dies by losing the capacity to feel its own condition and heals by getting it back.

## 2. Core mechanics

### 2.1 Control model

The control model is indirect with pause-and-direct architecture. The player does not inhabit any character's body; they direct the party from a slightly elevated perspective. Movement, interaction, and ability use are issued as commands; the characters execute. The player can pause at any time to plan, queue actions, reassess. Specific bindings are still being finalized; canonical source is `controls_reference.md`.

#### 2.1.1 Movement

Click on a map tile to move the active character there. The pathfinder is optimistic: it treats unexplored tiles as passable and recalculates as vision reveals reality. The party's perception layers (Peris's warm view, Aster's data overlay, the others' specialized layers) progressively reveal hazards that the pathfinder then routes around.

Movement has two orthogonal toggles. The walk/run toggle switches the active character between walking (free, slower) and running (costs stamina, faster). Stamina depletes while running. The pathing mode toggle switches between safe mode (heavy cost penalty on known hazard tiles, routes around hazards when reasonable) and direct mode (shortest path regardless of hazards). The two toggles are linked by default: walking pairs with safe routing, running pairs with direct routing. The link can be broken for edge cases (a player running through a known-safe corridor or walking carefully through a hazard-dense area).

#### 2.1.2 Camera

The camera follows the active character by default. A pan binding appears at the screen edge when relevant (off-screen events worth following, story moments the camera can witness). The binding is tutorialized in Aster's workspace scene during the Tag Day reveal: when a citizen is escorted to the Wellness Wing, the pan binding surfaces at the screen edge near them. The player who pans witnesses the moment; the player who does not, does not. This is a specific instance of the diegetic-bindings tutorial philosophy described in section 2.8.

#### 2.1.3 Time

Hold-X accelerates time during travel, waiting, and downtime. The thematic register of the binding: it is offered everywhere, including moments where holding it means skipping witnessing. The game gives the player permission to skip; the player chooses whether to. The binding is tutorialized in Aster's workspace during the citizen's poem at Tag Day, where holding X skips a moment the script would otherwise hold the player in.

The pause binding pauses the game entirely. Paused time does not advance the in-game clock. The player can issue new commands, reassess, plan, queue actions.

#### 2.1.4 Character switching

During the pause state, the player can cycle the active focus between party members. Switching is available after the two protagonists meet in early-to-mid Act 1; before that point, the game alternates control at narrative intervals (the tutorial-pair structure described in section 9). After the meeting, the player has full control of who is active when. Each party member retains their own perception layer, ability set, and item inventory; switching characters reveals what they can see and do that the previous character could not.

#### 2.1.5 Interaction (channel-on-arrival)

Click on an interactable object. The active character walks to the object using the click-to-move pathfinder. When the character arrives within range, channeling starts: a channel bar fills automatically over the channel duration. The interaction completes when the channel fills.

There is no separate "interact" button. The click on the interactable both initiates the path and (implicitly) the channel-on-arrival. If the character is already within range when the click occurs, channeling starts immediately. If the character moves away before the channel completes (the player issues a new command, or pursuit forces relocation), the channel cancels.

Channel duration is the work being done, not the player's input cost. Plant tending takes 4-9 seconds depending on species. Terminal interaction varies by terminal complexity. Switch toggles are near-instant once in range. The same model applies across switch toggles, terminal interactions, plant tending, character handoffs, and any other contact-based interaction. Tutorialized at Aster's drink machine.

**Interactability surface.** Hovering over an interactable shows a white outline. Once an action on it has been queued by a character (via shift+click or direct command), the outline shifts to that character's color and emits matching particles. The particle and color cue tells the player which character is committed to which interaction at a glance, including across queued multi-step plans where several characters have actions pending. The cue persists until the action completes or is cancelled.

#### 2.1.6 Abilities

Select an ability (per-character bindings, likely 1-4 keys), then click a target. Activating an ability pays its stamina cost and triggers its cooldown. The first ability the player uses in the game is Peris's Wrap (the protect/shield ability cast through her feed portal during the Monos session in her tutorial). Per-ability detail is in section 3 (per-character) and the dedicated character worldbuilding docs.

**The dodge package (auto-evade toggle).** The exception to the cast-and-target pattern: a standing per-character toggle, acquired diegetically in the Gnawer-courtship tutorial scene on the walk back from the Mother Flure chamber (scene sheet: gnawer-dodge). While enabled, the character's device watches for the telegraphed wind-up of any attack pattern the overlay has scanned, fires a pulse that throws the body clear of the predicted impact point, then catches the throw into a roll. The player times nothing; the verb stays inside the game's policy grammar of reads, positioning, and commitments rather than reflexes. Each dodge drains stamina (section 2.4.1). A dodge attempted without enough stamina still fires the throw but the catch fails: the character goes slack, falls, and must recover from the ground. Coverage is scan-gated: the device only evades species the overlay has filed, and filing a new species requires scanning it while it attacks something else, so every unscanned species gets at least one free attack; this rewards observing new creatures from cover before engaging. A dodged charge carries the attacker onward into whatever stood behind the dodger, so the toggle doubles as a baiting tool against environmental hazards; that use is never tutorialized in dialogue and is left to level design. In fiction the package is Aster's barrier-fault forecasting pointed at bodies, the first forecast of his career that acts on its own prediction; the characters experience the stamina cost only as fatigue and never name a meter.

#### 2.1.7 Item handling: the four input verbs

The hand-slot UI element on each character supports four inputs. Items occupy hand slots; a character has two hand slots (left and right).

- **Single-click on hand slot.** Selects the item, displays its details.
- **Click on hand slot, then click on a map space.** Throws the item in a parabolic arc to the target location. Range is approximately 6-8 tiles depending on item mass.
- **Double-click on hand slot.** Endocytoses the item (internal absorption), freeing the hand and committing the item to its internal-effect properties. The canonical example is endocytosing lysate to restore ATP at a shelter.
- **Shift+click on hand slot, then shift+click on a map space (or on additional hand slots, switches, interactables).** Queues the action rather than executing immediately. Multiple shift+clicks build a multi-step plan.

The four verbs are the entire item-handling vocabulary. There are no separate "use," "drop," "give," or "discard" verbs; throwing covers placement (throw to an empty tile to drop), exchanges (throw to another character's hand slot), and combat use (throw at an enemy). Endocytosis covers consumption. Selection covers inspection.

#### 2.1.8 Action queueing

Shift+click on any actionable target (map tile, hand slot, switch, terminal, plant, character) queues the action rather than executing it. Multi-step plans build by chaining shift+clicks. Each character has their own queue; queues run in parallel during execution. The current queue is visible while shift is held. The player can cancel by releasing shift without committing, or revise by canceling specific steps and re-queueing.

The same input mechanic supports two play registers. Casual queueing chains 2-3 actions for routine traversal, reducing clicks during normal play. Heavy queueing builds extended multi-character plans for complex puzzles. The Membrane Sealant puzzle (section 10.4.8) and the Loca watchtower (section 11.1) are the canonical heavy-queueing contexts; both depend on the player committing to a multi-step plan and watching it execute.

#### 2.1.9 Open bindings

Specific key and button assignments are TBD as of this writing. Bindings will be assigned during implementation. The mechanics above are stable; only the surface mappings remain open. Open bindings: pause key, walk/run toggle, pathing mode toggle, camera pan, character switch, ability selection (likely 1-4 per character). Confirmed: hold-X for time acceleration, shift for queueing.

[NOTE: `item_handling_spec.md`, referenced by `controls_reference.md` as the canonical source for the four input verbs and the action-queueing mechanic, is not in the current project file set. The verb structure absorbed above is from `controls_reference.md` directly; the dedicated spec should be surfaced or re-authored as part of the source-doc gaps tracked in section 17.11.]

### 2.2 Asymmetric perception

Each party member contributes a perception layer to the player's view of the world. The layers are not equivalent versions of the same information; they are different cognitive registers, each surfacing what its character can see and the others cannot. The player's effective view is the composite, assembled from whichever layers are toggled on at any moment.

#### 2.2.1 The six layers

Each character contributes a distinct overlay with distinct visual conventions so layers do not interfere when stacked.

- **Aster's data overlay.** Cyan geometry and data. Surfaces map structure, terminal locations, hackable systems, environmental readings, infrastructural data flows. Aster's device also logs all dialogue as it appears in the world; the player can review the running transcript at any time, which encourages exploration of optional scenes and missable beats. The log is diegetic (it is Aster's device doing what a data-class device does) and player-facing (it is where the player goes to find a line they missed or to revisit a scene).
- **Peris's flora and memory overlay.** Warm amber tones for flora and relational memory. Surfaces the flora network (the distributed sensor system Peris has tended), people (who they are, what they need), places (what happened here, emotional charge), and the felt substrate of relationships. Peris reads the world as who-and-why.
- **Endo's survival overlay.** Survival markers for safe routes, hazard tiles, water sources, hide spots. Endo reads the world as a corridor he has been maintaining for years; his overlay marks the affordances of long-term inhabitation.
- **Myke's road overlay.** Structural lines for maintenance routes. Surfaces the infrastructure paths the maintenance class uses, including routes the institutional layer does not document. Myke reads the world as a working layout known by feet, not by maps.
- **Oli's electrical flow overlay.** Electrical glow showing powered conduits, sealed sections behind power, signal pathways, points of insulation failure. Oli reads the world as the live grid keeping the body running.
- **Tyreg's patrol overlay.** Movement arrows and patrol zones. Surfaces enforcement routes, scan-grid timing, NK patterns, the institution's surveillance topology. Tyreg reads the world as a system of observation.

Aster reads the world as geometry-and-data. Peris reads it as relation-and-meaning. Aster tells the player what is there; Peris tells the player what it matters to. The other four characters add registers neither pair member produces.

#### 2.2.2 Overlay toggles decoupled from character selection

Character selection (who receives commands) is separate from overlay visibility (what information layers are shown). The two are independent UI systems. The player commands Aster while seeing Peris's flora network. Commands Myke while seeing Tyreg's patrol data. The information view is composed by the player from available layers regardless of who is acting.

**Why decoupled.** The party's collective perception exceeds any individual's, and decoupling lets the player experience this directly. Practically, decoupling solves several problems: Peris does not have to be in active selection for her flora reading to be useful (her overlay is visible whenever toggled on; the player can send her to smell flora, see the network refresh, command other characters while her reading stays fresh); cognitive load is player-controlled (overwhelmed by layered information? Turn overlays off; want comprehensive planning? Turn them all on); the UI maps to information needs ("I want to see threats" becomes "toggle Tyreg patrols and Peris flora network").

**Availability rules.** An overlay is available while the character contributing it is in the party. A character who is out of play but still conscious, for instance after a wash-down in a flush, still contributes their overlay; a knocked-out character at zero HP is unconscious and stops contributing it (the HP rules are in section 2.4.3). The dividing line is consciousness, not whether the character is currently in play. Characters who have not yet been recruited or have left the party do not contribute overlays. Exception: Endo's survival overlay persists in his home territory (the Plumbing and adjacent zones) even after he leaves the party, because his knowledge of those specific corridors was built over years and is tied to the place. In unfamiliar zones where he never lived, his overlay goes blank once he is gone.

**Default state.** Peris's and Aster's overlays default to on (the two permanent characters). Other overlays default to off and the player toggles them on as characters join. Players can override defaults through settings.

### 2.3 Forgetting system

Peris's memory degradation is the game's central mechanic; everything else is architecture around it. Her overlay is the relationship-and-meaning layer (per section 2.2), and the forgetting system is the degradation of that overlay across the run, tied to milestones rather than wall-clock time. Canonical source: `forgetting_system__1_.md`.

Losing Peris's overlay means losing access to the social and meaning fabric of the game, not losing the map. Navigation comes from other characters' overlays. Peris's overlay provides the layer of experience that makes the world feel inhabited rather than geometric.

#### 2.3.1 The flora system as operational core

Peris's flora capability is the operational core of her overlay. Plants are where her relational perception is most developed, because plants are where her capacity for wanting-with survived the simulation's atomization of desire.

**The backstory.** Peris saw plants through her client portals. The simulation rendered them as visual content, curated, mediated. She could not actually experience them. But she loved them. She built a private scent catalog. One time she smelled a flower she had only seen, and the flower reacted to her. That moment is the origin of her flora capability. Not as learned botanical skill but as recognition. She routed her relational capacity around the simulation's constraints by loving plants through portal images. Her flora-reading is what that routed capacity produced.

**Why this matters for the mechanic.** Her flora sense is grounded in personal history, not innate biology. What she is losing to her disease is a life's worth of relational acts with specific species, not generic plant knowledge. The archive of her flora relationships is what the disease is eating.

**Objective vs relational components.** Flora-reading is a compound of two layers. The objective layer is real chemical and biological signals (a flora near iron has different chemistry than one far from iron; a stressed plant has different biochemistry than a healthy one). The relational layer is Peris's personal history with the species (emotional associations, past encounters, scent-catalog entries). Late game, the objective layer persists relatively longer (biology keeps working). The relational layer degrades with memory. The reading becomes raw signal she can no longer interpret.

#### 2.3.2 Forget-me-nots, the pure-relational case

Forget-me-nots are scentless. This is verifiable terminal data. Peris perceives them as smelling like "the rust going away." Her scent-generating apparatus is producing this perception out of nothing, because the species is important to her even though it has no chemistry to index.

The source of the perception is ambiguous. The Chaperone Lattice's iron chelation actually neutralizes iron (rust), and Peris is perceiving a real chemical process through synaesthetic mapping. Or the scent is Peris's association with Aster's care, projected onto the flowers he gave her. Or it is a Peris-specific perceptual quirk, her system generating experience where no signal exists. The game does not resolve which. All three can be simultaneously true.

**Aster finds out.** Aster at a terminal pulls flora data and sees "Myosotis sylvatica, scentless." The information lands against his accumulated experience of Peris describing the scent. His response, to Peris when she next mentions it: "I don't think so." The line is ambiguous. Disbelief of the data because he has been watching her smell them. Disbelief of Peris because the terminal has corrected his model. The player reads it however they read it. Aster himself might not know which he means. He does not log it. Logging it would be making it data. The thing he is learning is that not everything should be data.

**The late-game collapse.** Because forget-me-nots are pure relational perception with zero objective component, they are exactly what goes first as Peris's memory degrades. The species that emotionally feels most secure to her is mechanically the most vulnerable. Late game, she holds forget-me-nots and smells nothing. The data was right. The data won. Her perception has been corrected by her disease into matching the terminal readout. This plays differently per ending: best preserves the scent (the cure restores the relational layer), bittersweet flickers, partial loses it mid-to-late game, worst loses it early.

#### 2.3.3 What degrades

Mechanically, the thing that degrades is the read-window duration: how long Peris's flora-network sense activates per smell. Early game it is long; late game it is short (rough reference points are in 2.3.5). One number going down across milestones.

Narratively, what degrades is Peris herself. Her recognition of species, her sense of what plants are responding to, her memory of plants she has tended for years, her ability to tell where stressors are by smell. These are not separate mechanical systems running in parallel; they are how Peris and the player communicate the single mechanical fact of the read-window getting shorter. Plants she once knew at a glance she now hesitates over. Stressors she once located by direction she now feels as ambient unease. Tended plants she has known for years she now walks past without recognizing. The mechanic is one number; the narrative is the entire texture of how the world is becoming less legible to her.

**Relationship-based decay.** Within the network, decay hits Peris's weakest relationships first. Plants she has deep history with stay legible to her late game; plants she met briefly fade fast. Early-game flora tending is strategic investment in late-game sensor durability: players who tended flora in Act 1 still get useful reads in Act 3, players who did not are navigating blind alongside Peris.

#### 2.3.4 Bidirectional reactivity

Flora in the game actually respond to Peris's presence, visibly and measurably, in ways other characters cannot replicate. The flora know who Peris is. The relationship is mutual, not just her perceiving them. Flora bloom more readily near her, release scents to her that they do not release for others, enter states that reveal information only to her.

As she degrades, the flora's response also degrades. Not because the flora are failing, but because Peris's biochemical signature is changing with her illness. The flora react to who she is, and who she is is changing. Late game, flora may not recognize her anymore. She approaches a plant she grew and it does not bloom like it used to. The relationship is dying from both sides.

#### 2.3.5 The flora network as gameplay loop

The flora Peris has tended form a distributed sensor network. When she approaches a flora node and smells it, her flora sense activates for a limited duration, during which she can read the network: resources, enemies, and environmental state visible through any tended flora in the zone, not just the one she is near. The activation is proximity-triggered, light-touch. Peris walks close to a flora node, a brief interaction plays (leaning in, touching a leaf, breathing near the plant), and the read-window opens.

The read is both defensive (enemies visible in or near the network, threat positions, environmental hazards) and offensive (resource locations, harvest-ready flora, unused caches, flora tending opportunities, tactical advantages revealed by environmental state).

**Read-window duration by degradation state.** Early game: roughly 60 seconds of full-fidelity network access per flora smell, comfortable planning cycle. Mid game: roughly 30 seconds, still usable but execution faster. Late game: roughly 10 seconds, only coarse information visible (something in this area, direction unclear, magnitude unclear). Endgame uncured: 2-3 seconds of anything, sometimes nothing. (Rates are design reference points, not commitments. Tuning to feel.)

**Read propagation in layers.** Immediate: full-fidelity information about the flora she is touching and the immediate vicinity, always available. Fast-propagating: close nodes (adjacent corridors, same sub-zone), reaches her within the first few seconds. Slow-propagating: distant nodes (far corners of the zone, other sub-zones connected through the network), reaches her later in the read-window if it holds long enough. As her read-window shrinks, the slow-propagating distant information stops arriving. Late game, she smells flora and sees only what is right around her.

**Spatial implications.** Flora density in a zone determines how well-mapped that zone is. Zones with dense Peris-tended flora (the Plumbing with her careful tending, Greenfields Collective with her client locations) are well-mapped even late game because she can refresh often. Zones with sparse flora (Dead Zones, unexplored territory) are poorly-mapped regardless of her state. Flora tending is spatial investment.

#### 2.3.6 Encounter randomness as epistemic uncertainty

The flora network combined with enemy behaviors produces a Duskers-style design mode: the player acts under uncertainty, and the uncertainty is the gameplay. Enemies in the world have legible behaviors (siderophores move toward iron, fixate on flures, respond to flow cycles; candids colonize at rule-based rates; Naturalizers follow patrol routes). The player can learn these behaviors over the game. The uncertainty is not what enemies do but where they are right now.

Peris's network gives partial spatial information with time-limited freshness. The player reads the network, plans based on what it shows, commits to actions. In the real-time interval between reading and executing, enemies move. Sometimes the read holds. Sometimes it doesn't.

The variance is not random. It is the interaction between the player's information delay and the enemies' ongoing movement against deterministic behavior rules. The world is emergent-deterministic. Peris's degradation is what makes it feel random. Early game this produces tactical planning. Late game this produces crisis response: the player reads quickly, commits under severe uncertainty, adapts to surprises in real-time. Player skill shifts across the game's arc from "precise plan" to "read partial information fast, commit, react."

#### 2.3.7 Telegraphing degradation to the player

The player needs to understand that the sensor is becoming unreliable. Four channels, in progression:

- **Dialogue.** Peris says so. "I cannot tell if it is iron or infection." "The scents are muddled today." "I think this is a Seefern? I am not sure."
- **Overlay self-representation.** The overlay shows uncertainty. Instead of a clear directional indicator, a fuzzy cone. Flickering readings. Conflicting values.
- **Observable wrongness.** Peris flags a corridor safe, party enters, siderophores are there. Trust erodes through experience.
- **Party observation.** Aster's data contradicts Peris's reading. Myke notices her hesitation before flora she used to identify instantly. The party's concern about her is itself the tell.

Progression: early degradation uses dialogue and overlay representation. Mid degradation adds party observation. Late degradation includes outright observable wrongness. The player's trust in the sensor degrades alongside the sensor itself.

#### 2.3.8 Two flora roles (sensor vs relationship)

Two systems share the same visual and mechanical layer but do different work.

**Flora-as-sensor** gives the player information about the environment. Degrades with Peris's memory but the underlying chemistry persists, so some information remains even late game. Compensated by redundancy from multiple tended flora and by cure components. Most flora in the game serve this function.

**Flora-as-relationship** carries meaning between characters. Forget-me-nots primarily, possibly a small number of other significant species. Does not provide environmental information. Degrades with Peris's capacity for relationship, which is the disease itself. Compensated only by the cure.

The distinction is not visible in the visual layer. Both look like flora. The player figures out which is which through behavior (forget-me-nots do not respond to environmental state; they just are).

#### 2.3.9 Cure mechanism and player responsibility

**The cure works by reinforcing the flora-relationship substrate** until it can regenerate human-relationship capacity. Peris is curable specifically because plants love her and the disease has not yet erased that fact. The cure is built from the one domain where relationship survived the system's suppression. She remembers the plants, and through the plants, eventually remembers people again. The cure components being made of flora and biological substrate is thesis-congruent: the cure-creator figured out that flora were the surviving relational substrate and built medicine out of that.

**Not asking the player to take notes.** The degradation is explicitly not designed to require player note-taking. Critical path progression does not depend on Peris's memory of specific details. The main story routes through information that is either stable (Aster's data, environmental state, character perception overlays that do not degrade) or recoverable (can be re-encountered, re-learned). Peris's memory is optional richness. The player who engages with it gets deeper experience and access to optional content. The player who does not still progresses but experiences the world as emptier. The player is not asked to remember things. The player is asked to feel it when Peris loses access to things she cared about. The compensation is not cognitive (the player's memory) but mechanical (flora tending, cure components, party bonds).

Open implementation questions are tracked in `forgetting_system__1_.md` and section 17.

### 2.4 Resource systems

The game uses three resource bars per character (stamina, ATP, HP) plus a per-character sleep-deprivation tracker. They operate at different time horizons (moment, day, encounter, multi-day) and pressure each other in cascade rather than stack.

#### 2.4.1 Stamina

Stamina is the moment-to-moment action budget. It depletes from running, dodge rolls, and ability use. It regenerates passively while the character walks. Walking is the default movement, slow but free; running is fast but costs stamina. Stamina does not shrink as the game progresses. The world degrades around the player at every other layer; stamina is deliberately the one bar that stays consistent.

#### 2.4.2 ATP (Action-Taking Power)

ATP is the rest budget. The bar uses discrete increments (e.g., a character at 4 of 9 units, not 4.3 of 9), so the player thinks of their reserve as countable rather than continuous. ATP only drains during rest at a shelter; it does not deplete during exploration, combat, or ability use. ATP refills when characters endocytose lysate, the in-world term for digestible biological material absorbed from organic remains. The daily loop is forage during the day, spend at the shelter to afford the night. A character arriving at shelter with insufficient ATP rests poorly or cannot rest at all; the consequence appears as sleep deprivation debuffs in the next day.

#### 2.4.3 HP

HP is the damage threshold, per character. It depletes from attacks, hazards, and friendly fire (Myke's flames and Tyreg's crossfire are the canonical sources, documented in the cast and combat sections). HP at zero means knockout, not death, and a downing comes in two states. A knocked-out character at zero HP is unconscious and dead weight: they cannot move, use abilities, or contribute their perception layer, and a conscious party member can drag them, moving more slowly and burning stamina faster while dragging. A character who is out of play but still conscious, such as one swept off by a flush before their HP reaches zero, keeps their perception layer and loses only their actions, the lose-the-hands-keep-the-eyes rule set out in the beginning-puzzle spec and consistent with the overlay availability rule above. The overlay goes dark only on unconsciousness, not on every removal from play. Revival happens at a shelter, with Oli's late-game Restore as the field exception.

#### 2.4.4 Sleep deprivation

Sleep deprivation is the cumulative cost of skipped or partial rest. The system replaces an earlier idea where prolonged low ATP would drain HP directly; that pattern is no longer canonical. Sleep deprivation accumulates with each missed or shortened rest and clears with a full restful night. The specific debuffs it imposes (which bars shrink, by how much, at which thresholds) are open design values pending playtest.

#### 2.4.5 The four in cascade

The bars cascade rather than stack. Stamina is the action budget for the moment. ATP gates the night's recovery. HP is the cost of failure to manage stamina well in encounters. Sleep deprivation is the cumulative cost of failing to manage ATP across multiple days. Well-managed days produce strong mornings; mismanaged days produce mornings worse than the previous one. The ratchet is one-directional except for the resets that good rest provides.

### 2.5 Day/night cycle and shelters

The world runs on a day/night cycle paced for sustained exploration rather than tight survival pressure. Subnautica is the named pacing reference (one of the explicit inspirations in the mini GDD); Rain World's faster, punishing cycle is not the model.

The cycle's session time and game time are decoupled by the pause-and-direct control architecture. The player can pause to plan and to issue commands; paused time does not advance the in-game clock. A speed-up button is available for compressing routine traversal and deliberate waits. A player who pauses heavily experiences a longer real-time session than a player who pauses sparingly while both see the same in-game day.

The starting target for an in-game day is 12 unpaused minutes. At a typical 25-40% pause rate this corresponds to roughly 14-20 real-time minutes per day, with a 30-shelter main path accordingly running roughly 7-10 hours of day-cycle gameplay before side content. The value is a starting target for playtest, not a final commitment. The day-to-night ratio and the shelter rest duration are open playtest values pending tuning against the 12-minute spine.

Shelters are where the cycle resets. At a shelter, characters can heal HP, restore stamina, and spend ATP to afford the night's rest. The shelter is the normal mechanism for advancing past night; the player skips the night by getting all conscious party members to a shelter and committing to rest. Rest that is skipped, partial, or interrupted produces sleep deprivation that carries into the next day.

Peris's progressive perception decline is the long arc that shapes how the cycle feels over the course of the game. Early on, the daily transition is atmospheric. Late in the game, her vision baseline at the end is less than her morning baseline at the beginning, and the cycle becomes a real navigation crisis. This is the source of the game's difficulty curve: the characters degrade, not the levels.

Specific nighttime threats remain an open design question. Earlier iterations specified a nocturnal predator class spawning at nightfall (the framing went through several biological identities), but the current canonical state is unresolved. The night is hostile in some form; the specific mechanism is to be determined.

### 2.6 Indirect-solution puzzles

Every major puzzle in the game has a hidden solution path that can be executed by Aster and Peris alone, even when the presented solution involves other party members. Canonical source: `design_principles_shadow_solutions.md`.

The hidden solution is not presented to the first-play player, is not required for standard progression, and is not surfaced through tutorial or UI. It exists as a structural option for players who have learned enough of the game's mechanical vocabulary to recognize it. The presented solutions use other party members (Endo carrying, Myke burning, Oli shielding, Tyreg shooting); the hidden solutions substitute Aster and Peris's combined toolkit (overlay-reading, terminal hacking, flora planting, sensory perception).

#### 2.6.1 Why the design commits to this

Aster and Peris are the base pair. The game opens with them, the endings land on them, every other party member is someone who joined *them*. Making them the puzzle-completion minimum is the mechanical version of that fact. It also rewards mastery (the player who learns the game's mechanical vocabulary deeply finds the game is more open than it appeared) and gives replays real variance.

#### 2.6.2 Commitments this imposes

**Every major puzzle must have a designed Aster-Peris solution.** This is not optional. If a puzzle cannot be solved by Aster and Peris alone, the puzzle must be redesigned until it can. The design-time cost is significant but absorbed by the fact that Aster and Peris are always in the party, so the coordinate mechanical affordances (Peris's flora kit, Aster's overlay and hacking) are always available.

**The hidden solution must not be surfaced as a first-play option.** The presented solution uses the additional party member whose contribution the puzzle is built around. The hidden solution exists but is not advertised. Environmental design, UI prompts, and dialogue all assume the presented solution. A player who sees the hidden solution on first play has earned it through observation.

**The hidden solution must be achievable with mechanics the game teaches.** It cannot rely on undocumented edge cases or exploits. The teaching happens organically via NPC demonstrations (Marco), terminal logs, environmental storytelling, shelter conversations, without being framed as tutorial. The player encounters the information and has to connect it to the puzzles where it applies.

**The hidden solution is typically harder than the presented solution.** It takes more moves, more setup, more resources, or more tactical care. The reward for finding it is not efficiency; it is agency. The player who knows the hidden solution can complete the puzzle without the ally whose contribution was presented as required.

#### 2.6.3 The three solution layers

**Layer 1: Presented solution.** What the first-play player does. Involves the party member whose contribution is the puzzle's hook. Mother Flure uses Endo carrying the gear. The Honeycomb Cooperative puzzles will use Oli's insulation reading. Beacon Hill puzzles will use Tyreg's enforcement-class authority. The Loca watchtower's presented solution uses the full party (including Myke) to leverage the tower's environmental affordances against the swarm. These are the canonical solutions the game teaches through level design and character moments.

**Layer 2: Optimized presented solution.** Players who have internalized the mechanics can execute the presented solution more efficiently: fewer moves, less combat, faster completion. This is standard mastery and requires no special knowledge beyond what the game teaches.

**Layer 3: Shadow solution.** Aster and Peris alone. Requires game-wide mechanical knowledge. Usually harder than Layer 1 but possible. Sequence-break-adjacent. Not a speedrun category per se; a mastery expression.

#### 2.6.4 Examples and current commitments

**Mother Flure chamber (Act 1 end, section 12.2).** Presented solution: Endo carries the gear; siderophores controlled by party combat tools. Shadow solution: Aster and Peris drag the gear over a pre-planted Scarpet bed. Scarpet reduces friction (enabling the drag) and masks iron signal (preventing siderophore swarm). Requires rapid-germination technique learned from Marco's drag demonstration.

**Inflammashunt DZ (Act 1 transition / Act 2 early, section 10.4.2).** Presented solution: three-route information gathering uses Myke's crawlspace access, Peris's underground flora route, and Aster's terminal route. Each party member contributes a route's information. Shadow solution: Aster can technically access all three routes alone via overlay-scanning with specific environmental conditions; Peris can read the flora without needing Myke's physical access if the flora are mature enough. The shadow solution requires multiple visits and patient information-gathering. (Status: needs design pass to confirm Aster-Peris feasibility.)

**Loca watchtower (Act 1 boss, section 11.1).** Presented solution: full party including Myke, leveraging the tower's affordances against the swarm. Shadow solution: Aster and Peris alone, exploiting the locusts' baseline ecology (when isolated and at rest, the locusts cannibalize each other). Aster strategically hacks doors to trap groups, the trapped locusts feed on each other, Peris handles survivors with flora. The shadow solution does not require fire and uses the locusts' own behavioral patterns against them. The thematic resonance is dense: the shadow solution lets the rogue component's victims consume each other while the party waits, which is an uncomfortable but accurate description of what trapping a contagious population does. The player is not killing them; they are letting the locusts finish what Loca's containment started.

**The Honeycomb Cooperative puzzles (Act 2 early).** Presented solution: Oli's insulation-reading layer identifies safe vs hostile conduits; his Barrier provides cover in tight corridors. Shadow solution: Aster's overlay can read the conduits through signal-analysis (slower, imperfect, requires active scanning). Peris's Capbage can provide pursuit-break cover where Oli's Barrier would. The shadow path is slower and requires more resource management. (Status: needs design pass to confirm.)

**Beacon Hill (Act 2 mid).** Presented solution: Tyreg's institutional-enforcement authority allows bypassing certain checkpoint-protocol interactions. She is Act 2's new face and her recruitment happens here. Shadow solution: Aster's device can emulate enforcement-class credentials via a hack learned at a specific earlier terminal. This is fragile and requires specific conditions. Without Tyreg, the puzzle becomes a stealth-and-timing problem rather than an authority-override problem. (Status: needs design pass to confirm.)

**Bulwark Wharf (Act 2 late).** Presented solution: barrier-crossing mechanics use the full party's tools in combination. Shadow solution: needs design pass.

**Welcombe Springs, Harmonia, Sunset Acres, Root Archive (Act 3).** Presented solutions: Act 3 uses the full party with escalating coordination demands. Shadow solutions: need design pass across all four sub-areas. Act 3 is the hardest place to maintain this principle because the late-game puzzles are designed to stress full-party coordination. The shadow solutions in Act 3 will be the hardest to design and will require the most player mastery to execute.

Note that the cure components retrieval puzzles (section 10) follow the same three-layer structure, with the Membrane Sealant explicitly testing Aster-Peris-only capability through its no-perception-overlays constraint and Section 3's longest dark route. The endgame Psy-Knapse defense section is designed to be solvable from two characters to six, with the experience scaling rather than the puzzle (section 13.4).

#### 2.6.5 How players learn the shadow solutions

**NPC demonstrations.** Marco is the game's primary shadow-solution teacher (section 12.7). He demonstrates mechanics (Scarpet-drag, rapid germination, applied chemistry) that the player then applies in unexpected places. Marco is positioned across the game specifically to surface mechanics the official party members would not.

**Terminal logs and environmental storytelling.** Construction-era logs reference techniques the workers used that the official party does not. A terminal log describing how construction crews moved heavy materials over Scarpet beds, discovered late-game after the chamber is done, retroactively teaches the Mother Flure shadow solution.

**Shelter conversations.** Late-game shelter conversations where party members mention offhand observations that connect to earlier puzzles. Oli's "Scarpet is what you use to move heavy things" line during a Honeycomb shelter rest plants the Mother Flure shadow solution alongside its more direct Honeycomb application.

**Peris's own discovery.** As Peris's relationship with flora deepens, her own practice surfaces capabilities the first-play player did not expect. Rapid germination. Network communication between tended flora. Long-range sensing. These are mechanical surfacing of narrative character growth.

#### 2.6.6 What the shadow-solution layer is not

**This is not a speedrun system.** Shadow solutions are not about minimizing time. They are about minimizing party-member dependencies. A shadow solution can be slower than the presented solution.

**This is not a difficulty toggle.** The shadow solutions are harder; they are not the "hard mode" of the presented solutions. The shadow layer exists alongside the presented layer; players choose which to use based on knowledge and intent.

**This is not punishment for missing party members.** The game does not force shadow solutions in any situation. If a party member is available, their contribution is always welcome. The shadow solutions matter for expert players and replay players, not for the first-play player who should never realize they are missing anything.

**This is not a secret ending path.** Shadow solutions do not lock or unlock endings. The endings depend on cure-component collection (section 13), not on how puzzles were solved. Shadow solutions are mastery expression, not narrative variance. The "It Takes Two" achievement (section 14.2) is the single mastery-and-completion marker tied to the shadow path; achievement-only, not narrative.

Open design questions are tracked in section 17 and in `design_principles_shadow_solutions.md`.

### 2.7 Ecological threats (overview)

The world is hostile in two registers: enemies (autonomous units with behaviors) and environmental hazards (iron blooms, hostile fluid, broken barrier sections, rising water). Both are governed by deterministic rules; the player learns the rules and acts under partial information about the current state of the world.

Enemies do not exist as isolated encounters. They form an ecosystem of thirteen species (the roster is in section 7.1) that interact with each other on top of interacting with the party. Siderophores compete with each other for iron. Candids poison territory other species depend on. Naturalizers attack Flares. Gnawers hunt anything with a metabolic signature. The behaviors are real biology made hostile: cells and molecules whose function in a healthy nervous system is regulation, when the regulatory signals fail, become the things eating the body alive.

Two implications follow for play. Combat is one valid response but rarely the most efficient. Reading the inter-enemy matrix and routing through it (letting a Naturalizer patrol clear a Flare, waiting for a Candid colony to displace the Toxo cysts that would otherwise have to be fought) is often the better move. Second, late-game ecology shifts. Enemies the party fought in Act 1 are pushed out of their niches by other enemies the party did not encounter early. The world the player traverses in Act 3 is not the same world they traversed in Act 1; the regulatory failure has propagated.

Per-species detail, the inter-enemy matrix, the political ecology, and visual specifications are in section 7.

### 2.8 Diegetic tutorial philosophy

The game never displays explanatory text like "Press E to interact" or "Drag to pan camera." The only tutorial indicator is the binding icon itself, which appears when the action becomes available and disappears when it is no longer relevant. The scene provides the reason; the binding provides the means. If the player misses a prompt, the game does not repeat it or pause; the mechanic remains available, the player discovers it when they are ready. This philosophy persists throughout the entire game.

**Tutorial as scene, not as segment.** The opening sequences (section 9) are simultaneously character-establishment and mechanic-teaching. The drink machine teaches ATP through Aster's actual workday, not through a labeled tutorial. The pan binding surfaces during Tag Day because there is something off-screen worth witnessing. Hold-X is offered during the citizen's poem because the player might want to skip it (and the game wants the player to notice that wanting). Peris's session waits while she walks around her workspace because that is what Peris does. There is no zone called "tutorial"; there are scenes that happen to be the player's first encounter with a mechanic.

**Continue labels.** Exploration scenes use a consistent "Continue" label to mark the interactable that advances the story, distinct from ambient or optional interactables. The hallway exit in Aster's workspace carries it. The logbook in Peris's workspace carries it. Endo's dormant plant carries it. The label is functional UI rather than diegetic (the characters do not see it); the player learns the vocabulary in the tutorial beats and carries it forward.

**No tutorial pop-ups in the rest of the game.** New mechanics introduced after the opening sequences (Climbvine planting, flora tending, the four-verb item handling, action queueing) are introduced through the same architecture: a scene where the mechanic is the natural thing to do, with the binding icon as the only UI tutor. The player who misses the surfacing the first time will find the mechanic still available the next time it is relevant.

## 3. The cast

| Character | Cell type | Role | Joins |
|-----------|-----------|------|-------|
| Aster | Astrocyte | Tank/Scout, data analyst | Tutorial |
| Peris | Pericyte | Support, social worker | Tutorial |
| Endo | Endothelial | Rogue/Scout, barrier maintainer | Shelter 1 (departs at 6-7) |
| Myke | Microglia | Burst DPS, maintenance worker | Shelter 9 |
| Oli | Oligodendrocyte | Defensive support, insulation worker | Shelter 11-12 |
| Tyreg | T-regulatory | ADC, enforcement class | Shelter 15-16 |

Each ally arrives with their own grief and leaves residue in the systems even after they're gone.

Marco is a recurring NPC who is not a party member; he appears at specific narrative moments to resolve problems and leave. Section 3.7 covers his design.

**Color identity.** Aster and Peris are colored after the forget-me-not: Aster is forget-me-not blue, Peris is forget-me-not gold. The supporting cast (Endo, Myke, Oli, Tyreg) are cool colors, each distinct from the others. Specific values are an art-direction call. The character's identity color is what the interactability surface uses for queued-action outlines and particles (section 2.1.5).

### 3.1 Aster

Aster is an astrocyte. His biological role is metabolic support, information routing, and the maintenance of homeostatic conditions that keep neurons functional. In game terms he is the Tank/Scout and the party's data analyst: the pattern-matcher whose overlay surfaces signals nobody else can see. His institutional role is data work for the simulation, the job he was given because his cognitive style made him useful to the system and the system had no other slot for him. He is autistic, which in-universe is not a named condition but a lived experience that shapes every scene he is in. His detachment has two roots: a learned psychological response to childhood friendships that kept ending badly, and a neurological baseline of sensory and social overstimulation that made full engagement with the world exhausting in a way the people around him could not see. The simulation was appealing because it reduced both kinds of load at once. The arc is about a pattern-matcher learning that love is commitment across unpredictability, not successful prediction, and that some relationships are worth the sensory cost of being fully present.

His institutional title is Deputy Analyst, Separations and Transport. The title names the choroid plexus's biological function (regulation of the blood-CSF barrier, controlling passage of substances from blood into cerebrospinal fluid, transport of CSF through the ventricular system) rendered as bureaucratic terminology. Aster is the institutional administrator of the barrier-and-transport function that Plexa biologically performs at the cellular level, which positions him structurally as the regulator who has been correctly predicting the failures the institution then files and ignores (the CSB analog established in the simulation tutorial expansions, section 9.1). The same title cuts the other way when read from below: to residents, Separations and Transport is the function that decides who is filtered out and where they are moved, so the tag Aster still carries marks him as an agent of a power he does not in fact hold (the residents' reading, and its use in the Residential Rings, are in section 5.10).

His EMP and his ability to hack come from the same illicit place, and together they justify the toolkit he uses in the elevator scene. Aster wears the standard device his class is issued, the one Ron reads his name and metrics off in the simulation tutorial (section 9.1), a credential and data-work tool rather than a maintenance kit. His role gives him no real operational power: Separations and Transport analysis has been hollowed into pure theory and publication, prediction with no authority to act, so the hands-on tools an actual engineer would carry are precisely what he does not have. What he has instead is a device he has quietly modified. He learned the technique from the digital-art crowd he already runs with, the Die-agrams collectors of section 9.1, who used a location-spoof to slip their tracking and goof off during work hours. Aster repurposed the same trick toward the opposite end, spoofing his location to get into parts of the facility his role does not permit, gathering observations and data nobody else can reach, so that he can out-publish everyone. It is fieldwork in the sense a sociologist means it, going out to where the data is, and it leaves him worldlier than coworkers who never leave the simulation, which quietly feeds the pattern he keeps documenting and the institution keeps ignoring. He goes out into the facility, but he stays inside it; venturing past its edge is a boundary the journey eventually forces him across. The EMP is one of the settings he added to the modified device, an emergency cut-off for the times a reading turns dangerous while he is somewhere he should not be. The elevator is the first time he uses it; he starts to explain what it is and where it came from, then cuts himself off and simply triggers it, finishing the account once they are clear (the explanation lands in the post-elevator stretch). The irony runs two ways: a tool built by slackers to do less becomes, in his hands, a tool for doing more than anyone, and dodging your location tracking is also dodging the productivity surveillance the whole institution runs on. The biological substrate still fits cleanly: astrocytes regulate the local neural electrical environment, take up neurotransmitters, and modulate synaptic activity, so an astrocyte that can disable electrical signals and probe data flows is doing biologically what astrocytes biologically do.

Aster keeps a photo album in his logs interface. The earliest entries were drafts of institutional complaints he meant to file, grievances about systems he could see were failing; he never filed them because he could see, too, that filing produced no response. The middle entries shifted to wellness-feed posts in The Board's register (section 5.6), the institutionally-acceptable performance of seeing things that mattered, his posts competent and flat. The current entries are personal: things he wants to capture because they are happening, with no audience and no institutional purpose. The arc from complaint to feed post to personal capture mirrors his larger arc from institutional capture to personal authenticity. The album is also the in-world UI through which the player views accumulated innovations during a playthrough (section 14.4); each innovation enters the album as an auto-captured screenshot from Aster's diegetic camera (one more capability on the device he modified, alongside the EMP and the location-spoof) at the moment of the triggering action. The pre-game album content establishes the arc; the in-game additions extend it with screenshots from the player's specific playthrough.

The Die-agrams collection gives the hollowed role its artifact. The two pieces he spotlights in his otherwise dark sim, Macabre Teal and Hunter and Ash, are generations-corrupted renderings of the McCabe-Thiele and Hunter-Nash diagrams, the staged-separations design methods of his own field. He owns the design tools of the engineering his analyst role amputated, carries every foundational skill they ask for, and experiences them only as art that evokes a loss he cannot name. The names themselves carry the forgetting: proper nouns drifted through generations of transmission without understanding, their surface readings (macabre, ash) suiting dead blueprints, so non-engineering players read elegy while engineering-literate players decode the originals on sight, in the same buried-reference register as the Glass Bead Game and the line of light. The collection's name resolves the same way: Die-agrams are diagrams that died into assets. In the chamber-exit reflection (mother-flure sheet, exit block) the collection meets something real, his market vocabulary for worth fails him in real time, and the question he is left holding, how something can have value without having value, is the act's aesthetics-and-awe meditation in his own grammar.

The drink machine in Aster's workspace recurs across the game as his institutional-reward motif. Ron introduces it in the simulation tutorial as the perk for top performers ("Unlimited, as always, for top performers like you"). At the Open Files, Aster recognizes its meaning ("the system that gave me the drink machine is the same one that cleaned my reports") and registers its loss ("damn, I was gonna use their drink machine"). In the Greenfields Collective he identifies one on sight, the recognition tinged by the prior realization. In the late Act 2 / early Act 3 "love is dimensionless" scene, Peris invokes it back to him as part of their shared memory: the institutional perk now a small affectionate reference in their private vocabulary.

Full character interiority is in `aster_worldbuilding.md`.

### 3.2 Peris

Peris is a pericyte. Her biological role is maintaining the barrier between blood and brain, regulating flow, clearing waste, and mediating communication between the vascular and neural compartments. In game terms she is the Support class, the party's social worker: the one who reads people through behavior, carries weight others file away, and holds specific particular details rather than reducing people to patterns. In the civilization's framework, she is one of the workers who tends to the people nobody else wants to think about: civilians whose cognitive decline has reached the point where they can no longer be productive, and who have been quietly routed into the facility where Peris works. She has the same condition her clients have, at an earlier stage. She has known this for a long time and hidden it, because she has been telling herself her suffering does not count when her clients have had so much worse. The game begins with her still employed, still doing the work, still hiding her own decline behind her clients' worse conditions. The rupture happens in-game: at some point after the party has been flagged as anomalies, they try to return to their normal lives, and immunity (the civilization's enforcement class) chases them away. Peris cannot go back to the facility. She cannot see her clients again. Sitting with this in the days after, she realizes something she could not have realized from inside the work: that she never had the opportunity to actually see her patients, because the framework of being their caseworker was a wall she did not notice until she was barred from the role. The arc from that realization forward is about a person whose identity was built on caring for others learning what is left of her when she is no longer in the caregiver position, while her own condition continues to progress.

Full character interiority is in `peris_worldbuilding.md`.

### 3.3 Endo

Endo is an endothelial cell. His biological role is forming the wall of the blood vessel itself: the barrier that holds, the surface across which the body's regulated traffic happens. In game terms he is the Rogue/Scout, the party's survival guide through the early game. He communicates through action rather than speech. He joins at Shelter 1, the junction he maintains, and departs at Shelter 6-7 to return to that junction; his wall is a place he has, and the player's choice of whether to ask him to leave it is one of the game's first weight-bearing decisions.

The junction itself is a maintenance post (the institutional checkpoint structure of section 4.7), not Endo's domestic residence. It is the workspace where ENT-class workers staff extended shifts, with a cot, a workbench, basic supplies, and the dormant plant Endo keeps as his personal touch at the station. Endo spends most of his time at the post because the work requires it, sleeps there when he needs to, and has shaped the institutional space through long maintenance, but the post is professional infrastructure, not a home. When the party arrives at Shelter 1, they are arriving at the post as displaced transient occupants, not breaking into Endo's residence. The post has shelter capacity for transient need per institutional norms; Endo's role at the post includes processing such occupants. Peris's tending of the dormant plant is recognition rather than payment for entry: Endo notices that the visitor cares for the plant without being asked or watched, which registers to him as something about who she is, not as something she has done for him. The professional acceptance of the party as transient occupants and the recognition that softens the encounter into companionship are two different beats operating on two different layers; conflating them produces the transactional read the design is trying to avoid.

His silence is canonical to his cell type and his profession rather than to his personal trait. ENT class work is interior-of-vessel maintenance, which is underwater work in the fluid the vessels carry. ENTs develop fully realized gestural professional vocabularies because their environment requires them; the silence isn't a compensatory behavior, it's the working language of the trade. Endothelial biology backs this up: real endothelial cells signal through contact channels (tight junctions, gap junctions, secreted molecules), not vocally.

Mechanically this gives Endo a kit affordance. He can navigate flooded passages, partly-submerged infrastructure, and fluid corridors that other party members cannot. His edge-concentrated junction-glow reads particularly clearly underwater, where the cool wavelength disperses through the fluid.

The party reads him fluently regardless: Aster through the data overlay (barrier integrity readings), Peris through somatic registration. Diegetic delivery to the player is via a stretch-dialogue moment that combines the swimming-grounded silence with the institution's class-shaped access pattern (per section 5.6: simulo-care is metrics-gated, working-class workers like ENTs can't reach it). The canonical workshopped version of the exchange:

> Peris: "Endo doesn't talk much, does he."
> Aster: "ENTs, right? I only ever heard about them when something was delayed. Higher-ups would joke about it — 'oh, ENTs are scuba diving again.'"
> Peris: "Well, they're always too tough to be my clients, apparently. Never had these types as clients. I wonder if they know these sessions are private, and their peers won't roast them for needing some help..."
> Aster: "The ENTs really need to check off the Simulo-care add-on in their benefits package more often, then!"

The exchange is a duet of misreading. Peris offers the helping-professional frame (tough culture, stigma about reaching out for help) which is genuinely concerned but structurally blind; Aster jumps in with the institutional surface gripe ("they should just check the box") that frames absence-of-access as user-error. They co-construct the wrong frame in real time and agree with each other. Neither names the actual barrier (simulo-care's metrics gate). The player sees what the characters don't.

A dedicated worldbuilding doc for Endo's full interiority does not yet exist; what is canonical is the mini GDD entry, his role in `endo_wall_scene.md` (the silent barrier-maintenance beat that anchors his arc), and `chase_scene_framework.md` (his junction as the lockout-chase boundary). [TODO: an `endo_worldbuilding.md` parallel to the other character files should be drafted; the silence canon, the swimming canon, the class-access fact, the appearance design from this session, and the workshopped dialogue should all be incorporated.]

### 3.4 Myke

Myke is a microglia. His biological role is surveillance, debris clearance, and inflammation mediation: the cleanup crew that walks the corridors looking for things to fix, heal, or burn. In game terms he is the Burst DPS maintenance worker with a fire ability. His institutional role is bottom-tier maintenance, a classification the system assigned him when his visible trajectory stopped somewhere it did not expect. The arc is about what happened to the trajectory, why he stopped producing outputs for the people who identified him as exceptional, and how his withdrawal from their game is a specific rational response rather than a collapse.

Myke started as MOC (Maintenance and Operations Cadet, the junior monocyte classification, per section 5.5) before being elevated into his current maintenance class. The elevation was the institutional success story (talent recognized, reassigned out of the cadet stagnation path) even though the specific role he ended up in is bottom-tier maintenance. Marco shares the MOC origin (per section 3.7) as the parallel non-elevation path; the two characters are the same starting point with two divergent survival strategies.

Canon line for Myke, placement committed: "Publish or perish, huh? Why not be me and get a two for one deal?" Delivered in the failed-bonding scene at shelter 9 immediately after Myke joins the party (see `myke_joining_scene.md`). Aster tries to introduce his role and his research, reaching for some commonality with Myke and inadvertently using the institutional-class cadence (publication metrics, "publish or perish"). Myke catches the phrase and gives it back as recognition of his own already-perished position. The "two for one deal" framing is the Hypelines marketing register applied to himself. Callback to Martín-Baró's "publish AND perish" formulation (section 18.1 bibliography). The scene establishes the cross-class assumption pattern that Aster will later have broken (in the Psyknapse-trap survival scene, section 12.9) when Peris receives his theory as serious theory.

Full character interiority is in `myke_worldbuilding.md`.

### 3.5 Oli

Oli is an oligodendrocyte. His role is to insulate and support the signal lines of the civilization: the electrical and metabolic infrastructure that carries communication between parts. In game terms he is the Defensive Support who thinks in networks and metabolism. He joined the maintenance class early, was given the tools to maintain what others built, and eventually made triage decisions during infrastructure failures that cut connections he knew mattered. He carries guilt for those choices. The arc is learning that the triage was the symptom of a system that defunded prevention, not a personal moral failure.

Full character interiority is in `oli_worldbuilding.md`.

### 3.6 Tyreg

Tyreg is a T-regulatory cell. Her role is to prevent the immune system from attacking the body it is supposed to protect. In game terms she is the Enforcer who believes in enforcement done right. She went through the academy as a TMC (Threat Monitoring Cadet, the junior thymocyte classification, per section 5.5), graduated into her current T-regulatory enforcement class, served, and initially appears in Act 1 as an enforcement officer the party briefly encounters during the sequence where they are chased away from their former lives. She does not join at that point. She rejoins at Shelter 15-16 in Act 2, after the craftsmen's evidence cracks her protocol-adherence.

Full character interiority is in `tyreg_worldbuilding.md`.

### 3.7 Marco (recurring NPC)

Marco is an eccentric. The institution tagged him as Monos and sent him through a standard monocyte caseload, which for his class tends toward early death or slow institutional stagnation. He has refused that ending. The refusal does not look like heroism; it looks like a person cycling through self-descriptions, vocabularies, and nicknames, building a survivable life out of whatever material is at hand. By the time the party encounters him after the Greenfields, he may be going by Marco, by Makrov Mage, or by several names in rotation.

Marco's institutional class is MOC (Maintenance and Operations Cadet), the junior monocyte classification given to younger members of the society (per section 5.5). MOCs branch into specialized adult classes for those who get elevated (Myke's microglial maintenance class is one such branch). Marco is the cadet who never got elevated; the "early death or slow institutional stagnation" path the canonical doc describes is the MOC stagnation track. "Monos" is the institutional shorthand for monocyte cadets, used in casual reference and in caseload entries.

Marco shares an origin with Myke: both were classified as monocytes (MOC). Myke got out institutionally (talent recognized, reassigned to maintenance, given a different working life). Marco did not. His survival has been improvised, lateral, outside institutional reclassification. Same origin, two survival strategies: the sanctioned path and the eccentric improvised path. Both produce people who eventually leave the corridors the institution drew for them. The game does not valorize one over the other.

Marco does not join the party. His structural role is non-joining deus-ex-machina: he appears in moments where the party's problems exceed their own capabilities, resolves the problem, and leaves. No explanation, no demand for reciprocity. His "magic" vocabulary is surviving practical technique that the institution no longer officially recognizes; his "spells" are real applied chemistry and botany rendered in fantasy-game language.

His first appearance in the game (Peris's tutorial session, per section 9.2) involves Marco having spoofed someone else's Psyknapse to access simulo-care, since workers like him normally cannot reach it (per section 5.6). The attack on the session is the institutional system's response to a worker-class break into a system calibrated for the qualifying-worker population it expects. Marco's later session-dialogue could reflect a worker's perspective on having entered a system normally inaccessible to his class, but specific dialogue is not yet committed.

Marco's death is a diminuendo death, structured as a series of fake-out heroic-sacrifice setups followed by a mundane real death the player did not read as a death scene. Marco gets multiple high-stakes scenes coded for heroic sacrifice. Each is set up so the player braces for his death. Each resolves with him surviving. Three fake-out setups feels about right, with the third being the most highly coded as the moment, the one Marco survives most decisively. By the time the real death comes, the player has been trained to read his survival as the default outcome. The real death is then mundane, abrupt, in a scene the player did not read as a death scene. This is in keeping with how monocyte-class characters actually die from systemic precarity, rather than from narratively meaningful confrontations. The literary tradition is Tolstoy's *Death of Ivan Ilyich* (1886), Chekhov's late stories, Carver, Beckett, the Sopranos cut-to-black, Breaking Bad's refusal to make Walt's death triumphant. The design preserves the Myke-Marco symmetry: Marco does not die because his survival strategy was wrong; he survived every moment the narrative tried to kill him in. He dies because everyone dies eventually, and the institution does not grant heroic deaths to its disposable class. Specific placements of the three fake-out scenes and the real-death scene are pending.

Marco's four-elements poem is canon and is recited in a quieter scene than the working-mid-job demos, possibly after a near-miss. The text:

> Perhaps we are earth, the ground for seeds to grow.
> Perhaps we are water, for we change and we flow.
> Perhaps we are fire, whose sparks cook, create and consume,
> Perhaps we are air, that leaves our lungs in our tomb.

The verse is the four classical elements rendered as a "perhaps we are" meditation. What it actually describes is cellular biology: earth as substrate for cells to grow (extracellular matrix), water as fluid dynamics (CSF, the resource that ran out), fire as combustion (mitochondrial respiration), air as cellular respiration ending at tissue death. For a civilization made of cells in a brain that is degenerating, the last line lands twice: as Marco's mystical reach and as the literal physiology. The "Perhaps we are" framing is character-coded; Marco does not assert, he tries on, the same way he cycles names and identities. The poem also functions at the meta-level as Plexa's question inside her own preserved brain about what kind of substance she has become.

Full design notes are in `marco_concept.md`. His DLC roguelike-mode role is in `dlc_roguelike_mode.md`.

### 3.8 Plexa (substrate, never on-screen as party)

Plexa is the cure creator and the cellular instantiation of the brain whose civilization the player explores. As a cell, she is CHR-1a (Choroid Researcher #1, founder), at the Root Archive in the late game (see sections 11.1, 12.2). As the human being whose preserved brain is the cell civilization's substrate, she has a biography that the game never states but that the player can piece together from artifacts at the Root Archive and from the structure of the cure project itself.

Plexa came from a family of APOE4 carriers and watched relatives die of Alzheimer's across generations. Her interest in Alzheimer's research was personal before it was institutional. The politics of academia kept her out of the credentialed research track. She could not afford further education and ended up working as a lab tech on other people's projects, watching ideas she could have led be assigned to credentialed researchers with less personal stake. After losing the lab tech position she fell into the service industry. When she began to detect signs of her own deterioration, she reasoned that her brain would be more scientifically valuable in mid-progression than in late stage, and that her life had higher worth as a research subject than as another precarious worker the system would no longer recognize. She wanted the cure she designed to be both biological (addressing the disease) and systematic (showing how society could be rebuilt and how people could bond with each other through the work). She arranged for voluntary euthanasia followed by immediate brain donation to preservation.

The receiving institution's relationship to her consent is left somewhat open in canon. Historical precedent supports a hybrid framing in which she consents to donation but the institution exceeds the consent she gave: Einstein's brain taken by Thomas Harvey without family permission in 1955; Ishi's brain removed and sent to the Smithsonian in 1916 against his explicitly stated wishes; Henrietta Lacks's cells used for decades without her or her family's consent. The alternate-universe setting also gives latitude. In the hybrid version, the cell civilization the player explores is partly Plexa's brain processing the betrayal of her terms, working out the cure from inside an institutional arrangement she would have rejected if she had known. Her wish that her brain become the substrate of cure research is what the cell-level Plexa (CHR-1a) is performing, and the betrayal gives the project the additional motive of outlasting and outwitting the institution that took her remains beyond what she allowed.

The Plexa-as-substrate framing is structurally load-bearing for the metafictional layer. The player is inside a brain that has been preserved and is being studied. The cell civilization is doing the cure work from inside that preservation. The recursion (Plexa designed the cure project to do for her preserved brain what the player is doing for her preserved brain) is the structural point the game embodies without ever stating. The receiving-institution's-overreach piece adds another layer: the cure is also the brain's preserved cells working to outlast an institutional capture that the human Plexa would have refused to consent to.

### 3.9 The simulation's architect (origin of the disease, never on-screen as party)

He is the figure on the far side of the central conflict from Plexa. She is the architect of the cure; he is the architect of the disease. A neuron, never named, he built one of the two neuron preservation facilities whose rivalry became the CSF wars (the neuron faction war), and he is the one who built the simulation. Like Plexa, he never appears as a party member and is never narrated directly. The player assembles him from logs, the way Plexa's biography is pieced together from artifacts at the Root Archive. Keeping him distinct from Plexa matters: they are the two poles the cure-versus-disease axis runs between, and the game should never let them blur into one origin.

His logs run roughly as follows. The early entries are about difficulty forming habits and getting out of bed, and feeling tired all the time. Everyone else is a cog in a smoothly functioning machine, running on clocks that work, and he is the only one who feels the gears grind. What grinds is that the things automatic for everyone else are things he has to consider consciously, and the friction of doing that, over and over, is what tires him out. Then comes the entry where he learns that if he really cared he would not forget, and he forgets anyway, so he thinks he just does not care about anything, and he identifies as a broken person. Then he sees he has hurt someone by forgetting their preferences, and he feels the pain too, so much it is almost unbearable. He feels like a cornered animal and wants to escape, his mind going into fight or flight, the world feeling like it is conspiring against him because he is broken, and he is trapped. Another entry is about people calling him evil and telling others to avoid him because he cannot feel empathy, which is not true, since he feels sadness when others do and pain when others do. So he decides to focus his life on making a world where everyone who wants to do right can do it without feeling broken, which is the simulation, and then finds people criticizing him for destroying human connection. Wanting to escape, he builds the preservation system, sheds his body, and goes into the simulation, where neurons finally appreciate him.

The model underneath him is intact empathic resonance with a broken learning loop. The pain is felt at full volume; what fails is the conversion of that pain into the shame that would teach restraint. His distress is self-focused rather than other-oriented, closer to what the literature calls personal distress than to empathic concern, so the shortest route to making it stop is to remove the source, which reads from outside as reactive aggression rather than the cold, instrumental cruelty the words narcissism and sociopathy usually point at. He is mislabeled as feeling nothing when the truth is that he feels too much and cannot learn from it. He is also the negative image of the game's central equation: he accepts the sentence that forgetting proves you do not care and breaks under it, where Aster's and Peris's arcs exist to refute it, the love that is commitment across what you cannot hold rather than a working memory. The logs carry all of this through concrete particulars, the tired mornings and the cornered-animal entry and the people steering others away from him, and never name a condition. Following the David Simon rule the game uses elsewhere (section 18.3, and compare the scrapped didactic academy in the Tyreg material), the entries show the shape and let the player supply the word.

The catalyst under all of it is overstimulation, which is also what makes him the right author for this particular disease. Overstimulation is a known way to dysregulate a reward system. Simmel's blasé attitude (section 18.1) is the nervous system going dull under too much input until it can no longer react to the differences between things, and the same thing in dopamine terms is tolerance, the threshold climbing until the ordinary stops registering. His simulation is a supernormal-stimulus machine in Tinbergen's sense (section 18.5), the exaggerated artificial cue an organism prefers to the real one. This is the mechanism beneath what the world already does. Blunt the reward system and wanting goes flat, which is the atomization of desire the canon already names (section 2.3.1); and the blasé state is precisely the inability to register the gap between how things are and how they could be, which is what envy is, the signal that lets a system feel its own lack and that the simulation suppresses (section 5.7). So the population is not censored into contentment, it is overstimulated into it, Huxley rather than Orwell, which makes the phrase the cure that became the disease (section 4.1) literal rather than poetic. It is addiction at the scale of a civilization, the thing built to make everyone feel good being the same thing that wears out their capacity to feel anything, the remedy and the poison one substance. And because dopamine is the learning signal, the prediction error that tells a brain what to do more of, rather than the pleasure chemical (section 18.5), overstimulation degrades the very channel that would have turned his empathic pain into learning. He feels everything and learns nothing because the channel that does the learning is the one that burned out. The same shortfall is what grinds his gears in the early logs: dopamine is also what consolidates a repeated action into automatic habit, so when the signal runs low the routines others perform without thinking stay effortful and consciously managed for him. The cruelty completes itself here: the overstimulation that ground him down is the engine of the world he builds to spare everyone the grinding. He medicates the world with the poison that broke him and calls it mercy.

His exit is the second preservation system in the game, and it is not the one that made the world. The outside institution preserved Plexa's brain to study it, cold and extractive, and that preservation is the invisible frame the cells never see (section 4.9). His system is a cell-level one, one of the warring neuron preservation facilities, sold to neurons as a way never to die, modeled on the real commercial brain-preservation ventures that pitch the same thing (section 18.4): pay now, wake later, death reframed as a subscription. He sheds his cellular body and uploads himself into the simulation, the one place where neurons finally welcome him. This adds a turn to the recursion the game already runs on. The cells living inside a preserved brain have built their own preservation racket and sell it as a product, doing to themselves, one level down, the thing that was done to the brain they inhabit; the architect who uploads himself is buying his own small version of what happened to Plexa. Keeping his system at the cell level, separate from the human-level preservation, is what keeps the metafiction's levels clean.

Several things about him are deliberately unresolved. Whether he authored the central simulation, which would make him the origin of the apparatus the whole game exists to undo and a great deal of weight to carry, or whether he is one local architect among several, is open. Whether he is a logs-only figure or someone the party can reach inside the simulation, since he is in there, an actual confrontation with the author of the condition rather than only his diary, is open. And he needs to be squared against the Paranucleus (section 11.2) so the two are not the same origin or quietly competing for it. These belong with the boss and scope questions in section 17.5 when they are taken up.

## 4. World structure

### 4.1 Three zones, concentric

The world is a giant ring around a central simulation.

**Zone 1 (the simulation).** The curated perception bubble at the center, where most citizens live. Clean, mediated, internally consistent. The cure that became the disease. Its origin, the architect who built it and the overstimulation mechanism by which it dulled the population into contentment, is given in section 3.9.

**Zone 2 (the inner ring).** The institutional infrastructure that runs the body, where Aster and Peris work. Solarpunk-Wall-E aesthetic; aging architecture, biomimetic facades, integrated greenery rusting. This is most of Acts 1 and 2.

**Zone 3 (the outer ring).** Beyond the Bulwark Wharf breach. Histological substrate exposed, raw tissue visible, organic conduits read as vasculature and nerve fascicles. Cold, biological, increasingly hostile. Acts 2 (later) and 3.

### 4.2 Acts, shelters, and boss landmarks

Three acts, thirty-plus shelters, two mega-landmark boss encounters: Loca's watchtower at the Act 1/2 boundary, the Paranucleus at the Act 2/3 boundary.

### 4.3 The map at zoomed-out scale

A bird's-eye three-quarter view of the entire NVU as a continuous landscape. The world reads as mostly open at this scale: what reads as enclosed corridor at human scale resolves at zoomed-out scale as roads, vessel-channels, and trenches running between districts. Buildings rise from the open landscape. The named regions read as architectural districts rather than as nested rooms.

The concentric ring geometry of the SVG renders at the diorama level as actual nested architecture. The vessel wall is a continuous structural barrier visible from above, the central simulation enclosed within it. Zone 2 is a band of solarpunk-Wall-E architecture: curving balconies, biomimetic facades, integrated green spaces gone to rust, fractal branching infrastructure aging at different rates. Zone 3 is a wider, more irregular band: histological substrate with scattered architectural islands, raw tissue visible between built sections, organic conduit bundles, no consistent street grid.

### 4.4 Named regions

Each ring is segmented into named districts that the player traverses. Each district has its own dominant architectural form (specified in `world_aesthetic_reference.md`). At zoomed-out scale, each reads as a distinct silhouette.

Districts are named in a mixed register: institutional-project naming (Plumbing Power Project, The Open Files Initiative, The Hypelines, The Cleanstreets Initiative) and picturesque-community naming (Greenfields Collective, Ancourage, The Honeycomb Cooperative, Beacon Hill, Bulwark Wharf, Welcombe Springs, Harmonia, Sunset Acres). The institutional names span sub-registers from utility-grandiose (Plumbing Power Project) through government-aspirational (The Open Files Initiative, The Cleanstreets Initiative) to corporate-marketing rebrand (The Hypelines). The mix reflects real geographic-area naming, where utility and government projects coexist with planned communities and aspirational developments. Each name carries a project category (succeeded but captured, failed, or planned but never built). The formal name is canonical; residents use vernacular shortenings in dialogue. Class-coded register applies: institutional speakers use formal names, maintenance speakers use vernacular.

The named regions, in approximate traversal order with shelter ranges and vernacular nicknames in parentheses:

- **Section 3B** (shelters 1-2; institutional designator, no vernacular): tutorial corridor, elevator, iron bridge, meet Endo, first night
- **Plumbing Power Project** (shelters 2-3; "the Plumbing," "the Power"): water infrastructure
- **Greenfields Collective** (shelters 4-5; "the Greenfields," "the Collective," "Builder's"): residential, planned cooperative community
- **The Open Files Initiative** (shelters 6-7; "the Open Files," "Open"): data terminals
- **The Hypelines** (shelters 8-9; "the Lines," "the Hype," "Iron Heart"): resource distribution; corporate-rebrand of what was once coordinated cooperative planning infrastructure; "Iron Heart" persists as resident-memory of the pre-rebrand name
- **Ancourage** (shelter 10; "the Anchor," "Bedrock"): foundation layer, Inflammashunt DZ junction, Act 1/2 transition; corporate-cheerful planned-community name (anchor + encourage) covering for the foundation that did not hold
- **The Honeycomb Cooperative** (shelters 11-12; "Honeycomb," "the Comb"): worker housing, worker-cooperative federation
- **The Cleanstreets Initiative** (shelters 13-14; "Cleanstreets," "the Streets"): transit corridors and plazas
- **Beacon Hill** (shelters 15-16; "Beacon," "the Hill," "the Stand"): archive preservation; historic-preservation neighborhood register, preservation as institutional capture
- **Bulwark Wharf** (shelters 17-18; "the Wharf," "Bulwark"): the Zone 2/3 boundary, barrier maintenance, Act 2/3 transition; fortified crossing-point district where the vascular system meets brain tissue
- **Welcombe Springs** (shelters 19-20; "Picturesque," "the Picture," "the Springs"): failed wellness-restoration; abandoned spa community
- **Harmonia** (shelters 21-22; "Harmony"): gamma entrainment infrastructure; planned wellness community
- **Sunset Acres** (shelters 23-24; "the Acres," "Sunset"): areas the civilization gave up on, named in cemetery-real-estate register
- **Root Archive** (shelters 25-30+; "the Root"): foundational archive, Plexa's archive, endgame

The naming convention is documented in `area_renaming_proposals.md`. Project categories are reflected in each area's environmental storytelling: failed projects have ruins of attempts and ironic signage where the project's aspirational name still reads; planned-but-never-built projects have empty foundations and planning documents; succeeded-but-captured projects have working infrastructure with abandoned practice.

[TODO: Welcombe Springs (formerly Iron Marshes) shifted from iron-bloom hazard to tourism-gentrification ruin per section 4.10 and the rename. The area's mechanical identity needs design pass: the "low wet terrain with stagnant pools" base description from `world_map_prompt.md` can be reframed as the spring-water remnants of the failed wellness-restoration project (mineral pools, abandoned bath houses, broken view-platforms). The cure-component-echo-and-environmental-storytelling design pass for each area (per the open-items in `area_renaming_proposals.md`) is the broader pending work.]

### 4.5 Mega-landmarks

Two singular silhouettes dominate the map. Both read at any zoom level.

**Loca's watchtower (Act 1 boss, west of the map between Ancourage and the Filtration crossing).** A mountain rises from the open landscape, exposed switchback trail visible up its face. At the summit, an institutional watchtower facility, clean-lined and reinforced, glowing cool blue from interior lighting. The watchtower silhouette is small relative to the mountain that supports it; the mountain is the landmark, the tower is the punctuation.

**The Paranucleus (Act 2 boss, southeast of the map between shelters 18 and 19).** Bone-white and pale-lavender stacked rings rising vertically out of the landscape, monumental in scale, dwarfing every other structure on the map. Raised tooth patterns along the inner edges of each ring (amyloid plaque's protein-subunit register made architectural). Deep purple shadows in the recesses between rings. A faint pink-red core glows from the deepest ring center. At the structure's base, NUTECH industrial fragments are preserved: grey institutional buildings with NUTECH signage and platforms, partly engulfed by the amyloid growth, partly still legible as a working facility. The hazy gray/purple sky overhead distinguishes this region from the red-sky majority of the map.

### 4.6 Path geometry and shelter nodes

The path geometry (Arm A, Arm B, the spiraling Zone 3 arc) renders at the diorama level as roads or vascular channels traced through the tissue substrate. The exact visual treatment per region (paved roads, raised walkways, vessel-channels with running fluid, simple worn paths through the substrate) is open. The player visibly moves between regions across the surface, not through hidden tunnels.

Shelter nodes read at the diorama level as small structures along these routes: rest stops, way-stations, modest buildings the party shelters in. They are settlement-scale punctuation along the paths, not landmarks at the mega-scale.

### 4.7 The center and the singletons

**The simulation dome.** The central vessel renders as a domed structure capping the central vessel. The simulation residents live inside, visible from outside only as glow and warm light leaking from the dome's surface. The dome sits within the vessel wall (which acts as the structural envelope around the simulation). Its clean, mediated, simulation-bright glow contrasts with everything around it. From outside, it looks unreal, the way a movie set looks unreal next to the actual world.

**Endo's junction (top of the vessel wall, 12 o'clock).** Reads as an institutional checkpoint structure on the dome's outer surface, where Zone 2's path arcs meet the vessel wall.

**Lockout checkpoint (6 o'clock of the vessel wall).** A similar institutional structure to Endo's junction, with tag-reader infrastructure and processing equipment. Where the Act 1 chase climaxes.

**The Filtration crossing (9 o'clock).** A permeable wall section with visible pore structures, the membrane partly breached. The hazy gray/purple sky covers this region. The path's first crossing into Zone 3 at the start of Act 2.

**The Hidden shelter (above the Root Archive).** The location of the Rest Cycle Module. A small structure tucked into terrain, not visible from most angles, the way a shrine in real terrain might be obscured until the viewer is close enough.

**The Paranucleus crossing (between shelters 18 and 19).** Where Act 2 ends and Act 3 begins, adjacent to the Paranucleus mega-landmark.

### 4.8 Central facility political economy and the failed re-entry

The central facility (the simulation dome and its surrounding administrative structures at the central vessel) is the visible administrative center of the civilization. It houses a majority of the current simulation devices and many of the governmental functions. The supply chain for inelastic goods is concentrated near it, which means that proximity to the central facility tracks with access to institutional resources. Other centers of power exist throughout the world but are not readily known to the player; the sites of the CSF wars between the two neuron preservation facilities are among these distributed power centers, and others exist. The class stratification has a geographic dimension. Outer regions house worker residences, businesses, and the ecology that has overrun many of them, and worker precarity is most concentrated there.

Aster and Peris attempt to re-enter the central facility early in the game and fail. This is when the lockout becomes mechanically real for the player and the characters. Before this point they are operating on the assumption that the lockout is an administrative error and they will be allowed back in once the wellness check resolves. The failure of re-entry is the moment that assumption breaks. The lockout chase (section 12.1) is the elaboration of this failure into kinesthetic terms; the failed re-entry is the antecedent that establishes the chase as the only available response.

### 4.9 The preservation architecture is invisible to the player and renders as institutional infrastructure

The fact that the player is inside Plexa's preserved brain in a research facility is never visible to the player as preservation. The player never sees the glass of the tank, never sees the external lab, never sees evidence of being preserved as preservation. The world is bounded by its own architecture. The architecture itself reflects the preservation infrastructure: pipes carrying fluid, barriers maintaining separation, filters regulating passage. These read as ordinary institutional features of the civilization (the kind of decay-and-maintenance infrastructure any aging institution would have) and as the apparatus of preservation rendered into the cell-civilization's built environment. The world's edges are the tank's walls, but the player encounters them as the world's edges.

This invisibility is load-bearing for the metafictional structure. If the player saw the preservation explicitly, the cell civilization would be framed as someone else's drama. By keeping it invisible, the cell civilization is the civilization. The meta-frame is something the player can construct from accumulated evidence (the Plexa biographical artifacts at the Root Archive, the recursive structure of the cure project doing for her brain what the brain is doing for her brain) but the game does not stop to explain.

### 4.10 The outer regions depopulated before the enemies arrived

The outer regions of the civilization were already depopulating before the enemy ecology moved in. The current state, with outer regions overrun by siderophores, naturalizers, and other enemies while the central facility concentrates the surviving population (section 4.8), is the late stage of a depopulation process that began earlier, for reasons that predate the ecological collapse.

Multiple factors drove the depopulation. Economies of scale that work in the central facility fail in the outer regions: distribution networks for inelastic goods require minimum population thresholds to be economical, and below those thresholds per-unit costs rise unsustainably, which further drives emigration. Network effects compound the collapse, since services need customer bases, social life needs critical mass, and professional opportunities need density. Below threshold, services close, social networks thin, opportunities disappear, and the remaining population experiences both higher costs and lower amenities. Loneliness becomes structural; cells in sparse outer populations cannot maintain the contact density their biology requires for normal function. The young leave for opportunity, the older population that remains experiences worsening conditions just as those who could maintain them depart, and the depopulation cascades.

The pattern maps onto contemporary rural depopulation in the real world. The mechanization of agriculture in the 20th century reduced the number of farmworkers needed, rural towns lost their customer base, services collapsed, the young left for urban centers, and the older population aged out without replacement. The literature on this is substantial: Patrick Carr and Maria Kefalas's *Hollowing Out the Middle* (2009) on rural Midwest depopulation, and Robert Wuthnow's *The Left Behind* (2018) on rural America generally. The "rural doom loop" or "depopulation cascade" names the dynamic.

For the cellular civilization, the analog is direct. The End of History prehistory (section 6.2) automated much of the work that supported the outer regions. The cellular populations that maintained outer infrastructure lost their function, the maintenance economy became uneconomical, and the supporting cells left for the central facility where the simulation infrastructure and the credit economy concentrated. The outer regions became hollow before the enemies arrived. When the enemy ecology moved in (siderophores responding to iron in the dying infrastructure, naturalizers responding to the absence of human-coded order, gnawers responding to the slow metabolic decay), the regions were already thinly populated; the ecology consumed what was left rather than displacing a living population.

A second mechanism compounded the slow depopulation: tourism gentrification. The phenomenon was named by Kevin Fox Gotham in his 2005 paper on the French Quarter in New Orleans and has since become one of the major drivers of rural and small-city displacement globally, with Venice as the canonical case (resident population dropped from over 175,000 in the 1950s to roughly 50,000 today, driven primarily by conversion of housing to short-term tourist rentals). The mechanism: speculative second-home purchases price out locals, short-term-rental conversion removes long-term housing stock, businesses pivot from serving residents to serving tourists, wages stay low while costs rise, the locals leave, the tourists experience an "authentic" place that has been emptied of the people who made it authentic, then the tourists leave when the hype shifts to the next location. The cellular civilization runs this pattern with the central-facility class as the tourists and the remaining outer-region workers as the displaced. The central-facility cells come to the outer regions to see what the simulation does not show them, take their selfies in front of architectural features the workers had been maintaining, occupy properties speculatively, and leave when the next location surfaces in the wellness feed. The outer regions lose their last residents to the very class that was supposed to value them. The connection to the cross-class envy mechanism (section 5.7) is direct: the management class is told the maintenance-class life is authentic and embodied, and their tourism is what they do with that valuation. The propaganda told them to value the working-class register, and their valuation takes the form of speculative consumption that destroys what they were taught to value.

The structural consequence is that the outer regions feel quiet not because the enemies are merely sparse but because the absence is multilayered. The cells that should be there are not, and they were not even before the present collapse. The ruins are not the ecological displacement of a population; they are the ecological occupation of a vacancy that the civilization's own economic dynamics had already produced, then deepened through the tourism wave, before the enemy ecology arrived. The party traversing the outer regions is moving through layered emptinesses, with the enemies as the most recent occupants of a space that had been emptying for a long time and that the central facility's own population had finished hollowing out before withdrawing back to the center.

The pattern has institutional precedents for what would address it. Coordinated regional planning, used in market economies under names like regional development authority, industrial policy, and active labor market policy, has multiple working historical examples. The Tennessee Valley Authority (1933 to present) bought land in a depopulating and economically devastated region across seven states, built coordinated infrastructure (dams, electrification, navigation), targeted economic development, and used the federal-corporate structure to coordinate across local jurisdictions that would have blocked piecemeal action. The TVA's outcome is mixed but real: the region went from one of the poorest in the country to a stable manufacturing economy, and the federal investment paid back many times over (with displacement of populations off land that became reservoirs as a real cost). Mondragon (Basque Spain, 1956 to present) addressed a depopulating region punished by the Franco regime with a federation of worker-owned cooperatives that pooled capital, planned production across firms, and coordinated training; the federation structure provides the planning function that individual cooperatives could not have done alone. Singapore's HDB (Housing and Development Board) built and now manages around 80% of Singapore's housing through coordinated planning that integrates transit, employment centers, and ecological constraints. The structural elements common to working examples are state acquisition of distressed property to solve consolidation problems that piecemeal market activity cannot, skill-targeted incentives that address the chicken-and-egg coordination problem in depopulating regions, infrastructure built according to sustainable resource flow rather than recreated metropolitan density, and job-creation backstops for residual unemployment that voluntary migration alone cannot absorb. The framework cuts against the institutional logic of leaving things where they have collapsed; the same logic that produced the cellular civilization's depopulation cascade is what these historical examples successfully resisted.

What the framework would need to operationalize, per the historical record: a clear mechanism for sustainable resource flow assessment (water, energy, ecological carrying capacity), a jurisdictional theory for who actually does the buying and coordinating (US federalism makes a federal land bank politically expensive, state-level land banks have done some of this work with mixed results), an incentive structure for existing residents to avoid the resentment that breaks bring-in-outsiders programs, and a theory of what the place produces that markets actually want, to avoid the make-work failure mode. The thematic spine in section 1.1 positions these institutional precedents as candidate real-world mappings for specific cure components; the Iron Redistribution Chaperone's mapping is committed in section 10.4.1 as (TVA + Mondragon).

### 4.11 The same underlying failure manifests differently across the capitalist and socialist districts

The districts can be read off their surfaces, Souls-style and without exposition, through a set of environmental-storytelling motifs that show the civilization's failure at human scale. The organizing principle is the one the rest of the design keeps arriving at: the underlying failure is structural and shared, the loss of error-correction and the capture of the natural and the free, but it manifests in different idioms depending on the system a district ran on. The world is diverse in its governance, and the section 4.4 names already encode the split. The corporate-rebrand districts (The Hypelines, The Cleanstreets Initiative) wear the capitalist idiom; the collectivist-named districts (Greenfields Collective, the Honeycomb Cooperative) wear the socialist one. Specific motif-to-district placements are pending; what follows is the catalog.

The capitalist idiom is the friction of money and the enclosure of the commons, usually a cheerful corporate name over a grim function. Roads wind around the holdouts who refused to move, the high-modernist grid bent by private refusal into a legibility scar, and the leftover wedges the detours create host the informal worker economy from section 5.8: refusal makes dead space, survival moves in. Herd Space charges for booth reservations to socialize, belonging turned into a product and class-gated by the credit economy (section 5.8), the Board spectacle from section 5.6 pushed down to the level of friendship. Rest is commodified into paid recharge-pods priced out of reach for the maintenance class, monetizing the glymphatic clearance the Rest Cycle Module is meant to restore. A metered chokepoint narrows a channel to single file at a "Flow Optimization" toll, a vascular constriction rendered in built form, with worn unofficial paths beaten around it where people dodge the fee. And a cheerful plaza or memorial sits on a cleared site, a bright community name and a nice plaque over ground that was "consolidated," dressing the section 4.10 depopulation in a civic bow. And the opening hours run backward: the convenience outlets are signed always open while the museums and libraries can only advertise their openings as rare events to be hyped, the institutions that hold the civilization's memory caught in a cycle they cannot win, unable to staff the convenient hours that would earn the revenue that would pay the staff, thinning into a few promoted windows a month. The everyday engine of forgetting turns out to be an opening-hours sign, the place you go to remember almost never open and the place you go to consume never closed.

The socialist idiom runs in two registers, because the planning logic fails both by succeeding too smoothly and by rotting where no one will work. The first register is the predictive optimizer, sleek rather than decayed, the simulation's own family, where the horror is the smoothness. Housing is identical not from poverty but from optimization, pleasant statistically-perfect dwellings the system assigned for fairness and efficiency that the resident did not choose and cannot change. There is no ration queue because there is no queue at all, the optimizer anticipating and meeting needs before they are voiced, which reads as utopia until you notice the act of asking is gone and there is no one to petition. There is no denunciation box, only joyful total sensing, the helpful system that knows everything because it was gladly told, the Board scaled up to the whole. And a district optimized perfectly for harmony on every available metric stands uncannily hollow in person, the proxy maxed and the thing itself gone.

The second register is the demoralized collapse, and it follows from a coverage gap in human motivation rather than from inefficiency. Autonomy, mastery, and esteem carry the interesting work and abandon the grim work, so a system that levels the extrinsic reward strands the essential degrading jobs, which then offer neither pride nor premium. The signage works hard to convince these workers of their dignity while the workers know they are looked down on and mistreated, and the demoralized response is shirking and escapism through substances, which ties to the liberation-psychology thread, the sedation the Board offers approached from the other end. A second response is to game rather than shirk, tuning shoddy craftsmanship exactly to the metric so the facade passes every inspection while the function rots behind the panel, which is Goodhart made into masonry and the same move the central cure makes when it clears the surface marker and leaves the disease untouched (section 10.5). The work no one will do is then coerced or automated, and the automation degrades: this is the same End-of-History automation that hollowed the outer regions in section 4.10, seen from the decay side rather than the depopulation side, and it surfaces as the backed-up pipes and overflowing tanks already canonized at the Acid Core facility (section 10.4.6). When competence collapses, legitimacy follows. PLA-8o is a pharmacy where demoralized or automated work began killing people and a crowd raised signs to shut it down; other government halls were stormed once the population decided the state was incompetent. Because the Collective provides everything, the failure of its services is not one bad firm but the whole system indicted at once, which is what turns decay into storming.

One reconciliation is pending and should not be written as canon yet. The instinct to make the barrier breach originate in this clearance collapse is strong and biologically apt, since blood-brain-barrier breakdown and glymphatic clearance failure co-occur in the real disease. But the Bulwark Wharf crossing is already canonized as an intact structural gate the party disrupts with the Lavender Lake spray retrieved at the Paranucleus (section 11.2), not as a pre-existing failure, so the clearance breach cannot be sited there without contradiction. The compatible homes are the Filtration crossing, which section 4.7 already describes as a partly-breached membrane, or the Acid Core facility itself; tying the social origin, the contempt for the grim-work class whose maintenance was holding the wall, to one of those is the question to resolve later.

### 4.12 The growth-versus-stability fault line produced two factions, and anamnesis is the answer to both

The deconstructive spine of the game is the old quarrel between growth and innovation on one side and stability and consistency on the other, and its argument is that neither pure position survives contact with a body that people depend on. Pick stability and the system ossifies into a local optimum it can no longer climb out of; pick growth and it externalizes the wreckage of its gambles onto everyone downstream. The point the game lands on is not a third political position but anamnesis: the failure underneath both is the loss of the feedback that would let a living system sense when to hold and when to risk, and the cure restores that sensing rather than choosing a side. The two factions below are foils for this, each one the result of trying to answer the fault line with a program instead of with a restored capacity to feel and re-choose.

The first faction forms on the growth side, out of a blocked innovation. Someone proposes an idea that looks as though it would benefit everyone but is risky, resource-hungry, and disruptive to the planned distribution; the collective votes for consistency, because ex-ante nobody can tell the transformative idea from the catastrophic one and the distribution it protects is real food on real tables; and the would-be builders begin stealing resources to pursue the idea regardless. Nobody in this is clean. The collective's caution is responsible rather than cowardly; the rebels are dangerous because they impose the risk on everyone without consent; and the rebels are also self-deceiving, because the yearning gave them purpose and they are half rebellious for the aesthetic, which means their meaning is now invested in the idea being right and they can no longer judge it. Their live register is the disruptor-founder, ask forgiveness not permission, the masses voted wrong and will thank us later, and the sharp irony is that the planned system breeds this capitalist archetype directly: it abolished the legitimate channel for the high-variance bet, the market with its venture capital and its freedom to fail, so the risk-taking impulse has nowhere lawful to go and comes out as theft. They are entrepreneurs without a market, which is what becomes of an entrepreneur when the only way to run the experiment is to steal the lab. The deepest layer is that they are the dark twin of the protagonists, who are also pursuing a blocked, risky, distribution-disrupting ideal against the system's preference for consistency, and the game is stronger if it does not pretend the line between the cure-quest and the resource-theft is obvious. Biologically they read as cells hoarding iron and glucose against the regulated distribution to fund an unsanctioned project, ambiguous between a desperate repair and a cancerous defection.

This faction has a name and a shape: the Aghora. It has no founder and no organization; like the caste in section 5.9 it is emergent, a precipitate of the contentment the simulation manufactured, condensing the way Slaanesh condenses out of a civilization that refines sensation until its own excess destroys it. Its members are the people of the cooperative districts in whom the suppressed signal leaked back as boredom. The simulation took envy, so nobody is unhappy with what they have, but contentment without aspiration is flatness, and the most restless cells felt that flatness as a void they could not name, because the civilization had already displaced love into doing acts people like and priced aspiration out of the language. So they knew they wanted more and reached for the only more still available to them, not connection or meaning, those words were gone, but sensation, novelty, risk, the feeling of being awake. What they built, in the cracks and on the stolen resources described above, is a counterfeit agora: a real market where the collective only allocates, a real assembly where comparison and wanting are finally permitted, a place of transgression and the new. It is the disruptive thing the collective refused, an overdose it could not distinguish from a renewal, built underground anyway.

The Aghora runs the addiction curve as a cosmology. Sensation dulls, the dose climbs, and the chase escalates toward the point where ecstasy and agony are the same signal and the self comes apart into pure sensation, the Hellraiser logic in which the box opened in search of transcendence is a door into one's own consumption. It renders through the biology rather than through gore or sex: the intensity is excitotoxic, cells firing past what they can survive, synchronized excitation that burns the participants out, manufactured aliveness exciting the body to death; the escalation is tolerance at the receptor level; the dissolution is a self pulled apart into a string of present moments with nothing to hold it together. The Aghora kills its members from the opposite direction as the simulation.

It is the third shadow of the cure: the neuron faction war is the shadow of the cure's method and the rogue tenth component (section 10.5) the shadow of its purpose, and the Aghora is the shadow of its substance. Where the cure recovers something true that was lost, the Aghora fabricates an intensity that was never there, which is why the two are easy to confuse and why the line drawn above between the cure-quest and the resource-theft stays deliberately faint: both begin from the same correct reading, that the contentment is empty. The name carries the inversion. Heard as the Spanish ahora it is now, the cult of the present tense, sensation with no past and no future, the exact opposite of anamnesis, which is literally un-forgetting; the disease forgets through contentment and the Aghora forgets through a now so loud it erases the continuity that memory is, so the figure is the now that forgets set against the remembering that heals. Beneath the pun sit the agora, the counterfeit public square; the agorist counter-economy operating outside the collective's allocation; and the Aghori, the ascetics who chased the sacred by breaking every taboo. And the faction keeps the section honest in both directions, because the collective was right to fear the thing, it really was an overdose that consumed the body, and the collective was also its cause, since the flatness is what drove people to reach for the rush and the legitimate hunger underneath, for novelty and voice and the feeling of being awake, had no other outlet. In the Polanyian frame the Aghora is the growth-side form of the protective countermovement gone wrong, the Dionysian answer to the disembedding and the mirror of the purity faction's reactionary one, and anamnesis is the re-embedding that is neither.

The second faction forms on the stability side, out of resentment of the metric-gamers in section 4.11. The hard workers' fury at the people gaming the metric is legitimate, and a leveled-reward system cannot discipline free-riding with wages, so the resentment curdles into a movement that wants purity. The exact point where it turns, the point that makes this a critique rather than a cartoon, is that the faction cannot tell the won't from the can't: the lazy and the disabled both fail the metric, so hatred of the shirker spills automatically onto the person who simply cannot, and once you are hating people for incapacity you are doing ableism. From there the slide is short and incremental, from "you won't contribute" to "you can't" to "you are constitutionally lesser" to "the worthy should concentrate their line," which is the Arendtian point that nobody set out to build eugenics, it precipitated out of justified anger one defensible-seeming inch at a time. The faction that loathed the metric becomes a worse metric, swapping the productivity number for the right blood, and it is the terminal form of the caste in section 5.9, the cutie-mark hardened into a bloodline. Its live register is not jackboots but the sleek high-performance in-group, the private breeding circles of self-styled contributors the present already grows in its pronatalist corners; dress it in excellence and wellness rather than a rally. In the NVU the breeding translates to factions hoarding the proliferation and lineage-commitment capacity, deciding which progenitors are permitted to divide, and the whole thing is the immune logic turned inward, a movement sorting the body's own cells into worthy and disposable, which is autoimmunity becoming an ideology and connects directly to the enforcement classes, Tyreg and the Naturalizers and the NK patrols. The program is not new: Plato's Republic set it down twenty-four centuries ago, the guardian class paired best with best under rigged marriage lotteries and the rest quietly disposed of (section 18.1).

The two factions are mirror errors. One purges the unworthy to protect the stable order; the other steals from the stable order to build the unbuilt future. Both are what happens when a society loses the capacity to feel its own condition and tries to resolve the growth-versus-stability tension with an ideology, and both are answered not by being defeated but by the thing the whole game is about, the restored signal that lets the body hold and risk in proportion again.

This is also where the game's politics turns actionable rather than merely diagnostic. The deconstruction shows both pure positions failing, but anamnesis is a constructive claim and not a shrug: the cure is the restoration of error-correction, the feedback a living system needs to sense when to hold and when to risk, which is a real lever rather than the familiar closing gesture toward mutual aid and indigenous knowledge. Those keep their place as instances of restored local feedback, mutual aid being local error-correction and indigenous knowledge being the local knowledge the global optimizer destroyed, but the program underneath them is the rule-based one, and the design should foreground it.

Georg Blind's rule-based economics (section 18.1) supplies the formal version. An economy is a population of rules evolving by variation, selection, and retention; the entrepreneur is the variation source; and policy sorts into operational, first-order, and second-order depths with a hard tradeoff between immediacy and self-sustainability. The sim and the symptom-suppression are operational policy, instant and never self-sustaining, while the cure is second-order policy, the slowest and most durable intervention there is, which is why it has to be assembled piece by piece rather than switched on. Blind's Japan case also lets section 5.9 be stated as fact rather than intuition: the empirical suppressors of the founder force there are traditional class order, fear of failure, and the cultural worship of craft and mastery, which is the cutie-mark measured, the honored fixed specialty shown to crush the very changing subsystem it claims to perfect.

Specific district placements, signage, symbols, and whether either faction becomes a playable or quest-bearing presence are pending design.

## 5. Institutional vocabulary and worker codes

The institution addresses workers procedurally. Every worker has a code on their tag, in their wellness feed, in their performance reviews, and on every form that processes them through the day. The code is the operational identity. The worker's name lives in a database row but is not used unless someone close to them uses it.

### 5.1 The encoding scheme

Worker codes have three parts: `PROF-NNNX`, where PROF is a 3-letter profession code (the institutional class), NNN is a sequential ID number within that profession (which worker number this is), and X is the last letter of the worker's actual name. The name-ending letter is the institution's small concession to individuality, just enough to suggest the worker has a name without ever giving the institution a reason to use it.

Sequential numbers reflect order of registration within a class. Founder cells, those who were among the earliest registered in their profession, hold the lowest numbers. The cure creator (Plexa) is CHR-1a. Her mentor on the cure project (Loca) is LCR-1a. Both are #1 in their classes because both registered before the institution had grown to need higher numbers. By contrast, Aster (AST-13r) and Peris (PCT-57s) are mid-registration cells, born into a population that had already been counted.

Examples currently in canon:

- **AST-13r**: Aster, Analyst #13 whose name ends in "r"
- **PCT-57s**: Peris, Personal Care Therapist #57 whose name ends in "s"
- **LCR-1a**: Loca, Locus Coeruleus Researcher #1 (founder) whose name ends in "a"
- **CHR-1a**: Plexa, Choroid Researcher #1 (founder) whose name ends in "a"
- **RDG-##X**: Resident Developmental Guide (radial-glia teaching class), specific instances pending

### 5.2 Why this format works thematically

The encoding scheme echoes the format of human gene names (TREM2, APOE3, APOE4, BDNF, GFAP). Real genes are typically named with a 3-to-5-letter abbreviation plus a number. Several of these are major neurodegeneration risk factors: APOE4 is the single largest genetic risk factor for late-onset Alzheimer's; TREM2 loss-of-function variants dramatically elevate AD risk by impairing microglial cleanup. Carriers of certain four-letters-and-a-number combinations really do have their fate decided by them, biologically.

The institution did not invent procedural categorization. It literalized what genetics was already doing. AST-13r echoes APOE4 in form because the institution's procedural categorization is the same operation, at a different scale, as the genetic categorization that determines whether a cell's microglial cleanup works properly. A character delivering a line like "imagine your fate being decided by four letters and a number" is naming the institutional fact; a player who recognizes the gene-name format hears the biological fact too. The character does not know the second register, but the line carries both.

### 5.3 What the encoding implies about the institution's database

The institution maintains a worker registry where every worker has a row. The sequential number is unique within profession. The name-ending letter is the worker's name's last character. The worker's actual name is somewhere in the row but is not operationally referenced. Aster's name is listed in his row as "Aster," but the operational vocabulary uses AST-13r everywhere except in personal communication, in shelter conversation, in the small spaces where the institution does not reach.

This produces a specific narrative possibility. A player who finds a database entry, a worker registry, or a personnel record can find a worker's full name even when the institutional vocabulary has been using the code throughout. The full name is buried but discoverable. The institution kept the name in the record because it had to (somewhere); the institution does not surface the name because it does not need to. The player who reads carefully can find names the institution refuses to use.

### 5.4 How the codes function in practice

In dialogue, the institutional vocabulary uses the codes. Wellness feed notifications, performance reviews, scanner readouts, sanctioned-list announcements all use codes. Personal conversations between workers (especially at shelters, off the clock) use names. The shift between code and name is a register shift: institutional context vs personal context.

At Tag Day, the scanner reads the worker's tag and confirms the code matches the registry. A failed read is a failed code: the worker's tag is not registering as a valid combination of profession + sequential + name-ending. The Naturalizers are summoned for "wellness referral" because a worker without a valid code has no operational identity in the system.

In sanctions, the code is what gets revoked. The sanctioned worker's code is marked invalid in the registry. The worker is now system-invisible: no profession, no sequential ID, no recognized name-ending. They become uncategorizable. In this civilization, uncategorizable is deletable.

The DLC roguelike's tag-swap framing leverages the code system directly (cross-reference: section 15.2). A living worker swaps their tag onto a dead worker's corpse before the bodies are logged and sealed. The system reads the code on the corpse and registers the corpse as the code's owner (alive, present, accounted for). The living worker now has no valid code. The institution registers them as the dead one (gone, no tag to find). The same procedural categorization that kills people, the system never looking closely enough to see them as people, is what lets some of them escape.

The codes also gate which institutional services workers access. The wellness feed, the simulo-care therapy track, sanction-routing details, performance review escalation paths, are not uniformly distributed across the worker population. Different services are gated by different metrics and credentials, and the populations that qualify for each are systematically class-shaped. Section 5.6 documents the simulo-care gate specifically (the surface frame of opt-in benefits, the metrics-gated reality underneath, the Psyknapse credential, and Marco's spoofing).

### 5.5 Class codes catalog (current state)

Confirmed in canon:

- **AST**: Analyst (astrocytes). Aster's class.
- **PCT**: Personal Care Therapist (pericytes). Peris's class.
- **RDG**: Resident Developmental Guide (radial glia). The teaching class.
- **ENT**: External Network Technician (endothelial cells). Endo's class. The institution's barrier-maintenance workers.
- **LCR**: Locus Coeruleus Researcher (locus coeruleus neurons). Loca's class.
- **CHR**: Choroid Researcher (choroid plexus cells). Plexa's class.
- **MOC**: Maintenance and Operations Cadet (monocytes). The junior classification given to younger members of the society. Branches into specialized adult classes (Myke's microglial maintenance class, the soldier-equivalent class) for cadets who get elevated, or stagnates as MOC for cadets who don't. Marco's class (the stagnation path).
- **TMC**: Threat Monitoring Cadet (thymocytes). The junior T-cell classification, parallel to MOC but for the T-cell lineage. Branches into Tyreg's T-regulatory enforcement class and other specialized adult T-cell classes.
- **MLR**: Moderation Lifecycle Reviewer (Müller glia). Mule's class. The content-moderator analog cell class: exposed to the system's worst processed content, support and cleanup for the meaning-makers, structurally prevented from healing because the institution has captured the natural regenerative capacity. Recurring presence in base game through terminal logs distributed across The Open Files Initiative, Beacon Hill, and Root Archive. Playable in DLC roguelike mode (section 15.4.8).

To be assigned as needed: microglial maintenance class (Myke), oligodendrocyte insulation class (Oli), T-regulatory enforcement class (Tyreg), construction class (Brobla, Vasca, Senchy), the various enforcement subclasses (Naturalizers, NK, others), and client classes (Peris's caseload, including any specific clients introduced by name).

The convention is that each class code should be 3 letters that echo the cell type (AST = Astrocyte, PCT echoes Pericyte, RDG echoes Radial Glia), and should resolve to an institutional job title that fits the class's actual function. New characters whose institutional position matters should be assigned a code in their worldbuilding doc when written.

### 5.6 Simulo-care and the Psyknapse gate

Simulo-care is the institutional term for simulation-based therapy, the service Peris provides. Sessions take place in a curated virtual space designed to support client processing; the simulation environment is the institution's premier mental-health offering.

The institution presents simulo-care as an opt-in benefit: workers "check off" the Simulo-care add-on in their benefits package to access it. The surface frame is voluntary participation, and casual workplace conversation reflects this frame ("the ENTs really need to check off the Simulo-care add-on more often"). The reality underneath is metrics-gated. Workers whose institutional output is measured by metrics that qualify (Aster ground his analyst-class metrics hard to reach simulo-care) can access; workers whose work is not measured by qualifying metrics (infrastructure maintenance, manual labor, the working classes generally) cannot, regardless of whether they "check off" anything. The gate is not officially economic, but it is structurally exclusionary. The institution maintains the gap between the surface frame and the underlying reality as part of how it operates: blame for non-access lives with the worker who failed to opt in, not with the system that gated the option.

The Psyknapse is the access credential that authenticates a worker into a simulo-care session. Each qualifying worker has their own. Marco, the recurring NPC who first appears in Peris's tutorial session, is a worker-class character who spoofed someone else's Psyknapse to access simulo-care. He wanted to see what it was like, since workers normally can't reach it. The attack on Marco's session (per section 9.2) is not a standard event in simulo-care; sessions normally proceed without external incident, because the system is calibrated for the qualifying-worker population it expects. Marco's worker-class break into a system not designed for worker-class users is what triggered the exception. His character (eccentric, brilliant, scrappy oddball with many names, per section 3.7) is consistent with a person who would hack into spaces he is not supposed to occupy, both to see and to survive.

The Psyknapse technology has a botanical ancestor, recorded in the flora roster's cultivar section. Its signaling mechanism, and the portal network's alongside it, both descend from Seefern, the communication cultivar whose bioluminescent signaling was the engineered predecessor of both. The world's two connection technologies grew out of a plant, a thread to carry as quiet worldbuilding rather than exposition.

Peris's wellness feed, the satisfying content stream that replaces her caseload when the system sanctions her, is called The Board. The name is a phonetic pun on Debord (drop the "De" and you have Board) and a theoretical reference to Guy Debord's *The Society of the Spectacle* (1967), which argued that contemporary capitalism produces a social relation mediated by representations. The wellness feed is one of the purest current expressions: relationship to one's own well-being mediated through metrics, dashboards, and notifications, with the representation substituting for the thing. The pun pairs Peris and Aster structurally. Aster works the dashboard, Peris has The Board. Both characters are operating through mediated representations of the world that have stopped being just-tools-for-knowing and started being the thing they were supposed to represent. The capture-pattern operates on both ends of the same loop: he is captured by the metric production side, she is captured by the wellness consumption side. The joke embeds the critique in the artifact; only players reading the spectacle critically will catch the reference, which is itself the structural condition Debord described.

### 5.7 The cross-class propaganda system suppresses envy through opposite-direction propaganda

The simulation's envy suppression is not only about hiding what others have. It also pre-loads the cross-class comparison so each class is convinced the other class has the worse life. The mechanism operates in opposite directions.

The management class (Aster, Peris, Tyreg) is told they are succeeding at the only legible metric, that they are smart and accomplished for understanding numbers, systems, and structures, and that they have escaped the back-breaking labor of the maintenance classes. The maintenance class (Myke, Marco, the working population generally) is told that management life is boring and ridiculous, filled with crazy rituals and bureaucratic rules. They are also told they are free to actually enjoy life and embrace it with all their senses, street-smart for having simple lives, with common sense and a community of people. Each class is convinced its own life is the better one. Cross-class envy collapses because the comparative valuation in each direction has been pre-loaded. The simulation does not just hide what others have; it hides what is desirable about what others have by reframing the desirable features as flaws.

The community enforces the propaganda internally by policing anyone who talks about anything boring like the management class as "being a buzzkill." This is the piece that closes the cross-class coalition. The management class can be told whatever; what locks in the working class is the community's own policing of internal deviation. The character who starts asking systemic questions is talked out of it by their friends. The character who notices the wellness referral gets told "don't worry about it." The simulation does not need to enforce this. The community does it for free, because the community has internalized the propaganda as the texture of belonging.

This is not specifically a late-capitalism failure mode but a general failure mode of any stratified society without a robust cross-perspective epistemology. Caste systems, feudal hierarchies, religious orders, mandarin bureaucracies, soviet-era nomenklatura, and modern technocratic states have all generated versions of the same opposite-direction propaganda. Hindu varna assigned each caste its own dharma not to be envied across. Medieval peasants were told nobles bore burdens while nobles were told peasants were free in their simple closeness to nature. Imperial China's literati were told commoners lived without bureaucratic burden, while commoners were told the literati were trapped in study and politics. The mechanism does not require capitalism; it requires stratification plus the absence of a holistic worldview that spans across positions. Stratified societies that maintain robust cross-perspective institutions (forced cross-class contact rituals, mentorship traditions that cross positions, mobility channels, dialogic forums that include all classes) can preserve the cross-perspective epistemology the mechanism requires to be absent. The failure mode appears when stratification and the loss of cross-perspective integration coincide.

The character relationships clarify in this light. Aster and Peris embody the two captures of this mechanism. Aster has been told he is smart and accomplished for working with systems. Peris has been told her embodied sensory care work is the better register. Their relationship crosses the divide structurally. When Peris asks "is he okay?" she is doing the thing the management-class propaganda has trained Aster not to do. When Aster reads the data she cannot access, he is doing the thing the working-class propaganda has trained Peris not to value. Each gives the other access to the side the simulation took. Marco fits the maintenance-class capture: the "Makrov Mage" affect, the cycling identities, the four-elements poem, the embodied register all sit in the value space the maintenance-class propaganda assigns. The propaganda has taught him that the work he does is authentic and the work others do is ridiculous.

The four endings can reflect how much the player has broken through the cross-class enforcement in both directions, with the deeper endings requiring scenes in which the player feels and resists the social pressure to dismiss the systemic question (in maintenance space) or the working-class concern (in management space). The hope generalizes to any society in which two captured perspectives can find each other and rebuild the missing cross-position vision. Specific scene placements for the buzzkill enforcement and the management-side respectful dismissal are pending design.

The Cassandra-lock is the corollary at civilizational scale. The maintenance class fights among themselves when deterioration starts, because they cannot grasp the role of the management class and so blame each other for the conditions they all experience. Proximity makes blame easier; workers can see their neighbors doing differently than expected but cannot see the structural force shaping all of them. The standard divide-and-conquer dynamic operates without requiring active divider intent. The management class refuses to recognize the worker conflict because the social norm against acknowledging class difference reads any such acknowledgment as prejudice. The norm originally protected against older paternalistic and prejudiced discourse, but the "respectful" denial is now more disabling than the older paternalism: the paternalism at least saw the workers as a category needing attention; respect-driven denial sees nothing at all. Bonilla-Silva's *Racism without Racists* (2003) is the closest theoretical analysis of how color-blind frameworks can produce more entrenched inequality than the overt racism they replace; the same logic applies to class-blind frameworks in this civilization. The lock is Foucauldian. Polite silence is productive of non-action. Workers cannot articulate what they see because their framework gives them only their neighbors to blame; management cannot perceive the worker fighting because the framework that should let them see has been recoded as the very thing it should detect.

For the game, this opens specific scene possibilities. Working-class shelters where workers blame each other while management refuses to see. The "respectful" dismissal of working-class concerns by management characters. Marco's position gains texture from having been in the worker fights, seen workers blame each other, and possibly bearing the marks. The moment when Aster has to actually see the working-class struggle becomes the breaking of the taboo, framed as transgressive rather than merely informational. The moment when Peris articulates what is happening can be dismissed by management characters as classist before being heard. The cross-perspective synthesis becomes specifically the capacity to violate the polite-silence norm in both directions.

### 5.8 Credits as formal currency with informal worker economies in parallel

The formal currency of the civilization is credits. Workers struggle to earn enough credits to meet basic needs because their class limits the credit-earning work available to them. An informal worker economy circulates in parallel, structurally because the credit system limits access for the lower classes. The informal economy is what enables maintenance-class survival on inadequate formal credit allocations; the specific mechanisms (barter, mutual obligation, gray-market exchange of services and goods, time-banking variants) are not yet specified.

### 5.9 The caste is emergent and beloved because specialization delivers real identity-goods

The caste system was not imposed from above. It emerged, as the precipitate of three ordinary things: cells having different skills, cells being selective about who they work with, and cells wanting a defined talent of their own. The institution did not need to assign castes any more than it needed to invent procedural categorization (section 5.2); it literalized a sorting the population was already performing on itself. The anti-division-of-labor ideal, in which no one holds a fixed role, breaks first on the high-skill, high-responsibility classes: you want your surgeon to have specialized rather than dabbled, and the cells know it. Specialization in this world is not merely tolerated, it is wanted. A defined craft confers identity, agency, and the dignity of mastery, and cells reach for it the way they reach for a name.

This is why the population believes the caste is good, and says so in its own voice: it brings out your talents, it is what you are built for. The belief is not simple false consciousness, which is exactly what makes it load-bearing. The goods are real. Mastery does confer identity; a defined role does answer the question of who you are and what you are for; the pride in a unique skill is real pride. The caste is the captured-contentment engine, the same engine as the simulation's envy suppression, operating at the level of work and identity. The simulation suppresses the question by hiding what others have; the caste suppresses the question by answering it too well. Both leave the cell content, and the contentment is the capture.

The critique therefore cannot run against specialization itself, because the opposite of a fixed caste is not freedom but enforced sameness, which is its own dystopia. The two failure modes are legible in My Little Pony's cutie-mark system, where an individual special talent is treated as identity and as freedom, set against that show's equal-sign village, where every mark is erased into mandatory equality and the erasure is the nightmare. The game threads between them. The villain is never the mark and never equality; the villain is the mark being permanent, inherited, and unleaveable. The slide the caste runs on is the quiet equation of "I love my craft" with "I accept my fixed station," using the first claim, which is true and good, to launder the second, which is the cage.

This arrangement has its charter in Plato. The Republic builds the just city out of three classes sorted by the ruling part of each soul, the appetitive producers, the spirited auxiliaries, and the rational guardian-rulers, and naturalizes the sort with the myth of the metals, a noble lie told so that every citizen believes their station is the metal innate to them. The game's caste is the same three-class sort reached from below rather than imposed from above, made literal in a body, and its quarrel is with Plato's verdict rather than his structure: the claim that a permanent, inherited, unleaveable sort is justice. What it keeps from Plato is that specialization is wanted and real; what it rejects is the lie that makes the mark uneditable (section 18.1).

The justification has a seam, and Marco sits on it. "It brings out what you are built for" is the winners' sentence. It is true if you were built for surgery and a death sentence with a bow on it if you were built, as Marco was, for a monocyte's caseload that trends toward an early grave (his class is the MOC stagnation path, section 5.5). The same proud line lands as self-actualization on the elevated classes and as a leash on the disposable ones, told to the cells the system spends so that they will be content being spent. The asymmetry is the sharpest tool available against the ideology, because it does not argue against pride in craft; it shows pride in craft being aimed downward as a weapon. A scene that puts the talent-and-purpose speech in front of Marco punctures the whole ideology without a word spoken against it.

The emergence is what makes the caste land morally, because it removes the architect. The system precipitated out of a great many reasonable and even beautiful individual desires, chief among them the wish for an identity, which means there is no villain to indict, only the aggregate of cells wanting a place. This is the game's Arendtian register again: the monstrous structure with no monster behind it, the invisible hand reaching for the throat, except the hand is made of the wish to be someone. It is also why the caste cannot be cured by abolishing the wish. The cure is the same lever the rest of the design keeps arriving at: keep the exit open. A cell may keep the talent, the pride, the mastery, and the identity, all of it, on the single condition that the mark can be chosen again. The good was never the specialty. The good was the choosing. A caste is only a specialty that has forgotten it was once a choice, which makes the caste one more form of the forgetting the whole game is about, and makes mobility, the right to re-choose, the social-scale version of the anamnesis the cure restores.

### 5.10 A reassignment reads from below as a Separations and Transport analyst arriving with a therapist

The institution's removals travel under the word "reassignment," and from below the residents have learned the shape one takes. It arrives as an analyst from Separations and Transport, the department that at institutional scale administers who passes and who is moved, walking in beside a therapist. The analyst reads the infrastructure and never the faces; the therapist reads the people. The pairing of those two roles is the configuration that precedes a reassignment, so residents scatter to avoid being near it while it is choosing.

The dread is the two roles together, not rank. This supersedes an earlier reading in which residents fled the party as senior leadership on a walk-through (a c-suite tour that meant restructuring). The pairing is the more specific trigger because it uses what the characters are rather than a generic rank signal: Aster reading barriers is his literal job (section 3), Peris reading people is hers, and the cruelty is that this harmless pairing is exactly the death-shape, while Aster, the department's ignored Cassandra, holds none of the removal power his tag implies.

The beat is planted in the Residential Rings, where Marco, a former client of Peris's, names the pattern and Peris registers only that something has shifted without yet understanding why. It is paid off in the Psyknapse survival scene (section 12.9), where she realizes that the clients of hers who were quietly reassigned, the ones who looked less well off and lived further out, were removals she signed the paperwork for and never once questioned. The Residential Rings scene holds the seed and not the recognition; the recognition belongs to the later scene.

### 5.11 The Rings are commuter housing now, and the emptiness is a schedule, not a failure

The Residential Rings no longer house Peris's client base. Her clients mostly moved inward to the Facility while she was in the simulation, and the poorer ones had already been reassigned. What remains is working-class housing for people who work in the Facility but cannot live there, plus the in-between and the illegible living in the seams: lapsed statuses, mid-transition classifications, and class-spoofers like Marco, whose device reads facility-class among people who are the real thing one rung down. The corridors breathe with the Facility's shift cycle, and the party crosses mid-shift, so the Rings read sparse but tended. Nothing here is failing, which is the point. This splits the section 5.10 scatter in two: workers protect classifications, and the seam-dwellers avoid being looked at at all. The scent gradient is class infrastructure: the full Nutech regime is a Facility amenity, the Rings smell of it secondhand on returning workers' clothes, and the decommissioned margins not at all.

## 6. Aesthetic

The fuller aesthetic canon (architectural grammar, the fever-dream-with-biological-referent principle, what is settled vs unsettled at world scale) is in `world_aesthetic_reference.md`, which is referenced by `world_map_prompt.md` but not present in the current project doc set. [TODO: surface or re-incorporate that doc when available.] What follows here absorbs the mini GDD §6 and the visual-register content from `world_map_prompt.md`.

### 6.1 In-game visual register

3D low-poly geometry in the PlayStation 2 era register: faceted forms, simplified silhouettes, modest polygon counts, slightly curved surfaces rather than voxel-blocky cubes. Pixel-art textures applied to those surfaces: grid-aligned, limited palette, sharp pixel edges visible on close inspection. Realistic lighting layered over the whole: proper shadow casting, ambient occlusion, direct light from in-world sources (lamps, scanners, fires), atmospheric haze. The combination is the look: low-poly form, retro-pixel surface, modern lighting.

For individual rooms, the framing is diorama-on-dark: discrete spatial volumes lit against near-black backgrounds, with the room cut as a small theatrical stage rather than embedded in a continuous environment.

(Note: this updates the earlier canonical phrasing in the mini GDD and `world_map_prompt.md`, which describe the look as "voxel and low-poly base geometry with painterly atmospheric textures." The PS2-style geometry plus pixel-art textures plus realistic lighting is the current canonical framing.)

### 6.2 Cultural-architectural register: post-solarpunk in decline

The world's broader aesthetic register is a post-solarpunk apocalypse. Solarpunk visual language (sweeping curves, integrated-with-nature design, renewable energy infrastructure) is present but in decline. The plants are still green, engineered to stay that way regardless of care or abandonment, so the visual register of life persists in places nothing else does. The renewable infrastructure has become decorative. The aesthetic of sustainability survives as branding while the substance has died.

The decline is visible in specific juxtapositions:

- **Sweeping curves and dead plants.** Architecture that gestures toward integrated-with-nature design, but the nature has stopped happening. The forms are still there; the life isn't.
- **Renewable energy infrastructure.** Solar arrays, wind systems, biological energy networks. Still present, still pictured in institutional propaganda, but neglected and often non-functional.
- **Anti-homeless architecture.** Hostile design features (spikes, slanted ledges, awkward partitions) that prevent stagnation-path workers and other discarded populations from occupying public space. The institution's silent answer to the people it has discarded but hasn't formally erased.
- **Walkable spaces replaced by roads and buildings.** Pedestrian infrastructure eroded; class-shaped urban design (cars for those who qualify, walking for those who don't, but with progressively less space to do it).
- **Performative gardens.** Gardens that look green from a distance but are dead, ornamental, or just for show. Gardening as status-display rather than care.
- **Abstract art detached from common meaning.** Paintings and sculptures that read as autonomous abstract art but whose original referents have been lost (per section 9.1's *Macabre Teal* and *Hunter and Ash* collections, which are McCabe-Thiele and Hunter-Nash engineering diagrams sold as art after the Documentation Load Reduction era destroyed the originals).

This aesthetic connects to other institutional patterns documented elsewhere in the GDD: epistemic-luxury access (performative gardens, art-as-status-good), class-shaped urban design (anti-homeless architecture, walkability erosion), Documentation Load Reduction (art detached from referent).

The post-solarpunk decline is the architectural residue of a specific civilizational phase. At one point in the civilization's history, everything appeared to work. The infrastructure looked green and sustainable. Nothing seemed left to fix or build. Everyone seemed happy. Work had been automated to the degree that the working class chose to stop working, and their skills and work ethic deteriorated from disuse. The upper class believed they could not come up with any more grand innovations and that history was basically complete. Lifespans shortened, because there was no reason to do anything; people let themselves rot away in their excess without realizing they had been blinded to actual conditions. The workers who saw the decay happening were detached, coping, justifying the changes, and structurally unable to acquire what they would have needed to make fixes anyway. The post-historical pattern matches Fukuyama's "The End of History?" (1989) and *The End of History and the Last Man* (1992), Galbraith's earlier *The Affluent Society* (1958) on postwar American complacency that eroded public goods, and the post-scarcity dystopia of *WALL-E*'s Axiom, *Brave New World*'s soma, and Wells's Eloi in *The Time Machine*. Use-it-or-lose-it operates at civilizational scale, and the Zone 2 solarpunk-Wall-E ruin is the architectural residue of this period.

The brain-biology version of the pattern is what makes it the right substrate for the game. Cognitive reserve theory (Stern 2002, building on Katzman) holds that the brain maintains function through redundant pathways built up by challenge and novelty. Without demand, the redundancy atrophies and the underlying decline becomes uncompensated. The civilization is doing brain-tissue-level atrophy at civilizational scale. The redundancy that maintained function under stress was never rebuilt during the abundance period, so when stress arrived (iron handling failed, the barrier began breaking, the preservation class created CSF demand the choroid plexus could not scale to meet), the system had no capacity to respond. The bifurcated decline is non-symmetrical: the upper class's complacency was self-congratulation ("we did it"); the working class's detachment was justified surrender ("there is no point, and we could not get the resources to fix it even if we tried"). The lifespan deterioration is grounded in real research: purpose in life is one of the most robust predictors of mortality in longitudinal studies (Hill and Turiano 2014). Stripping a population of reasons to do anything correlates with biological aging acceleration, not just metaphorical decline. The civilization is empirically aging itself to death by removing purpose from its inhabitants, which is what the simulation does on the wellness side and the automation does on the productive side. The integration with the rest of the GDD's canon is clean. The Wellness apparatus and Tag Day are the late-stage forms of End of History administration, what the institution does when it has stopped innovating and is just managing decay through curated perception. The information quarantine is the institutional refusal to acknowledge that the End of History was wrong. The CSF crisis is the structural failure of the abundance-period assumption that current production would always be sufficient. The neuron faction war is the abundance period's terminal contradiction surfacing: when supply could not be scaled, two factions chose extraction over cooperation because cooperation was outside the framework. Plexa's individual biography (researcher locked out, watching her family die, choosing to become the research subject because the institution would not let her be the researcher) is the same pattern enacted at the personal level: she lived through the End of History and was its victim before the civilization began its collective collapse.

### 6.3 Restricted palette

Muted cool teals and greens dominate, with warm cream highlights on natural materials. Near-black backgrounds. Two saturated lighting anchors carry the rest of the color work:

- Warm orange firelight (where Myke or other fire-deployable presences burn, where natural fires are lit, the simulation dome's interior warmth)
- Cold cyan-white scanner light (institutional checkpoint glow, terminal indicators, the Watchtower's cool blue institutional lighting visible from a long way off)

Everything else sits in the muted base palette.

### 6.4 The map view

Bird's-eye three-quarter of the entire NVU as a continuous landscape, rendered in the same visual language as the in-game environments. The viewer hovers above the diorama at a high angle; the world tilts slightly toward the viewer. Vertical landmarks (the Paranucleus, the Watchtower, the central simulation dome) read as silhouettes catching the sky. Horizontal infrastructure (rings, roads, district envelopes) reads laid out below.

Lighting is ambient and diffuse. Most of the world is in the ambient red of the sky. Where artificial lighting punches through (the simulation dome at center, institutional checkpoints, the cool blue glow of the Watchtower interior), the contrast against the ambient red is part of the visual texture. The world is not lit by a single sun-direction; it is bathed in atmosphere.

### 6.5 Sky

Ferric red over most of the map, the color of Western Australia's Pilbara region: oxidized iron in the atmospheric haze, the sun a diffuse orange disc visible through the dust, sparse thin cloud cover or none. The sky's color is biologically grounded; the NVU's iron handling is broken, the atmosphere has accumulated iron oxide, the sky reads red because the body is rusting from the inside. Without the biological framing, this just looks like a desert sky. With the framing, it is pathology rendered as weather.

Two regions sit under hazy gray/purple sky instead of red: the area around the Paranucleus and the Filtration approach. The Paranucleus's gray/purple is the amyloid plaque's atmospheric signature; the pathology there is protein aggregation rather than iron. The Filtration approach's gray/purple is the membrane breach's atmospheric mixing; what bleeds across the boundary produces a different haze. The boundaries between red sky and gray/purple sky are diffuse, not hard transitions.

### 6.6 Ground

The substrate of the entire diorama is biological tissue. Pinkish-pale floor running between districts, vessel-like grooves traced through it (some are the path geometry; others are ambient veining of the substrate), fine particulate dust catching the red light. The architecture sits on this tissue.

In Zone 2, the tissue is mostly covered by architectural flooring, with tissue visible only at the edges and in cracks. In Zone 3, the tissue is more exposed; the architectural layer is patchy, eroded, with tissue showing through across larger areas. The transition from Zone 2 to Zone 3 is the visible erosion of the architectural surface to reveal the body underneath.

### 6.7 Color register by zone

**Zone 1 (the simulation, the central vessel).** Clean, warm, mediated. Soft pastels and ambient glow leak from the dome at the center. The simulation reads as the only "wrong" color in the world: a small bubble of properly-illuminated, simulation-clean atmosphere in the middle of a landscape under iron-red skies. From outside, the dome glows.

**Zone 2 (the inner ring, corridor infrastructure, Wall-E Earth).** Muted teals and greens dominant on the architecture, warm cream and brown on natural materials. Ferric-red bleeds streak down metal where it has oxidized. The whole zone is bathed in red ambient light from the sky, so the cool architectural palette interacts with warm atmospheric light, producing complex muted tones across surfaces.

**Zone 3 (the outer ring, beyond the breach).** Colder than Zone 2. The architectural palette gives way to tissue palette: pinkish-pale substrate, basement-membrane translucency, conduit bundles reading as nerve fascicles, cilia-like projections on atmospheric channels. The red sky still bathes most of Zone 3 (except over the Paranucleus and the Filtration approach), but the surfaces beneath it are colder and more biological.

### 6.8 The pink-red saturation rule

Pink-red is reserved for major boss landmarks at the map level. The Paranucleus has a faint pink-red core at its deepest ring (visible from above as a small saturated point at the structure's heart). No other map element gets pink-red saturation.

The room-scale Infiltrator pathology (the saturated pink-red organic growth referenced in the room mood-study) shows pink-red in close-up environments but is too small to register on the map view and does not show on the zoomed-out diorama. Boss landmarks are the only saturated pink-red things on the map.

### 6.9 Bibliography for the look

- Western Australia / Pilbara region atmospheric color reference (iron oxide dust producing characteristic ferric-red skies)
- Wall-E (2008, Pixar). Aesthetic reference for solarpunk-decay register at world scale
- The Paranucleus reference concept art and the in-game room reference (3D PS2-style geometry with pixel-art textures and realistic lighting)

### 6.10 Production tooling

The visual register is built in two specific tools that match the aesthetic. Models and characters are made in Blockbench, which produces the pixel-textured low-poly forms the design commits to. Levels and rooms are made in Crocotile 3D, the tile-based level editor associated with the PS1/PS2-era indie scene. Both are hand-driven workflows: rooms are tiled by hand, textures are painted by hand.

AI use in the production pipeline is bounded. Code generation (typical AI-assisted development; outputs are functionally verifiable) and 3D model bases that are then iterated on manually, painted, and finished in Blockbench. AI is not used as a deliverable for art or design; the iteration and finishing are human-driven.

## 7. Enemy ecosystem

The NVU is not a zoo of discrete threats the party walks through. It is a dysfunctional ecosystem where every inhabitant is stressed by every other inhabitant. Enemies fight each other, avoid each other, eat each other, disrupt each other. The party is one more agent in a multi-sided mess, and sometimes the smartest play is letting two enemies handle each other while you slip through.

The reason all these enemies are hostile to each other is the same reason the civilization is dying: the regulatory systems that kept their relationships functional have stopped working. Every enemy in the NVU is trying to do its old job in a context where its old job no longer makes sense.

The full per-species spec for the four siderophore species lives in `techos_species_doc.md`. The remaining material here is consolidated from `enemy_ecosystem.md`.

### 7.1 Roster

The thirteen enemy types, with one-line role summaries.

| Name | Role | Biology |
|---|---|---|
| Sapscraps | Basic swarm drainers, workhorse | Catecholate siderophores |
| Ferrules | Fluorescent specialists at breaches | Mixed-type fluorescent siderophores |
| Hidras | Infrastructure mimics | Hydroxamate siderophores, segmented wire bodies |
| Crusts | Surface biofilm, wall-paranoia | Mycobactin-type, membrane-embedded |
| Candids | Slow biofilm colonizers, environment changers | Candida biofilms |
| Meebs | Indiscriminate engulfers | Free-living amoebae (Naegleria, Acanthamoeba) |
| Naturalizers | Institutional enforcement patrols | NK cells |
| Gnawers | Metabolic-signature hunters | Gingipains (Porphyromonas gingivalis) |
| Flares | AoE bursters, neutral-until-triggered | Neutrophils |
| Spikers | Delayed line-of-sight connection turrets | Pathological hyperexcitable neurons |
| Tanglers | Stealth-grapple hunters with seeding status | Tau propagation |
| Toxos | Set piece (NK Slop) or player-facing threat | Toxoplasma gondii |
| Redactors | Late-game invisible enforcers, deepest institutional class | Membrane-cloaked pathological T-cells |

### 7.2 Siderophores compete with siderophores

The four siderophore species (Sapscraps, Ferrules, Hidras, Crusts) all share a class but they do not cooperate. They compete for iron, and because different species prefer different iron sources, they settle into territorial divisions when iron is abundant. Where iron is scarce they displace each other. A Crust patch on a pipe is denying that pipe's surface iron to every Sapscrap nearby. A Hidra burrowed into a conduit makes that conduit's iron unavailable to Ferrules. A Ferrule cluster near a breach is concentrating the local iron economy in a way that starves the smaller siderophores in adjacent corridors.

The competition is visible to the player as distribution patterns. Heavy Crust coverage on a stretch of wall correlates with reduced Sapscrap population in that stretch. Hidra-dominated conduit sections are quiet of other siderophores. The player who learns to read these patterns can infer which species will be present where before seeing them.

None of the siderophore species attack each other directly. Their competition is metabolic, not combative. But a Sapscrap displaced by Crust dominance is a Sapscrap looking for iron elsewhere, which may mean a Sapscrap that shows up in a corridor that was quiet yesterday. Shifts in one siderophore species' territory push other species into new areas.

### 7.3 Candids poison the environment for everyone else

Candids change the chemistry of corridors they colonize. The local atmosphere shifts toward conditions that favor Candid biology: low oxygen, altered pH, biofilm matrix blanketing surfaces, reduced airflow. These conditions are hostile to almost every other enemy type, not because Candids attack them but because the environment itself becomes uninhabitable.

Tanglers avoid Candid zones because the biofilm chemistry disrupts their protein filament integrity. Their bodies would unweave if they stayed too long. They route around colonized areas.

Naturalizers' tag-scanning becomes noisy and unreliable in Candid air. The sensors are calibrated for healthy tissue chemistry, and the biofilm interferes. Naturalizer patrols skip colonized corridors because their equipment stops working there.

Siderophores have trouble navigating the altered iron gradients inside a colonized zone. The biofilm absorbs and locks iron in its matrix, denying it to the siderophore sensing systems. A heavily colonized corridor is a corridor that reads as iron-dead to a Sapscrap, which is a reason the Sapscrap doesn't go there.

The player can use this. Moving through a Candid colony is slow and consumable-reducing because the corridor is degraded, but it is also Naturalizer-free and Tangler-free and low on siderophores. A party member with a compromised tag who needs to move through Naturalizer territory can route through a Candid zone instead, trading the tag-scan risk for the biofilm-exposure risk.

Candids themselves do not attack. They just make the area uninhabitable for everything else.

### 7.4 Meebs eat what they can engulf

Meebs are indiscriminate predators. Anything within their detection range that is small enough to engulf gets engulfed. Siderophores are the primary food source. A Meeb rolling through a corridor clears out Sapscraps in its path, freezes while digesting, and continues drifting.

They cannot eat Candid colonies because the colony is too large and too embedded in the infrastructure. They ignore Tanglers because the filament structure is tougher than the siderophore bodies Meebs are built to digest; an attempted engulfment would fail. They do not engage Naturalizers, who are immune enforcement with defensive responses that would damage the Meeb. They cannot catch Gnawers, who are faster.

So Meebs are a natural siderophore predator and an obstacle to everything party-sized or smaller. A corridor that Meebs are patrolling is a corridor with low siderophore density. The player can route through Meeb corridors for relative safety from siderophores, accepting that the Meebs themselves are a threat.

A Meeb currently engulfing a siderophore is frozen and temporarily safe to pass. This is the player's window to move past a Meeb that would otherwise be dangerous. The engulfment takes several seconds. The Meeb is locked in place. The player who has observed this pattern can turn a Meeb encounter into a Meeb-assisted transit.

### 7.5 Naturalizers have complicated immune politics

Naturalizers have a specific enforcement mandate: scan tags, remove incoherent presences. They ignore most pathogen-class enemies because siderophores, Candids, and Meebs do not carry tags at all. They are pathogens, not tagged entities. Naturalizers were built to enforce the body's internal coherence, not to fight external invaders.

The exceptions are biologically specific.

Naturalizers engage Toxos. Natural Killer cells are literally the immune response real biology evolved to kill Toxoplasma. In the NVU, this is preserved: Naturalizers on patrol will actively hunt Toxos if they detect them. Toxos in Naturalizer territory lose fast.

Naturalizers engage Tanglers if the tangles are disrupting tagged tissue. Tau pathology in a region the Naturalizers recognize as part of the body triggers their enforcement response. This is inconsistent because tau is technically a self-protein, so tag coherence is ambiguous; sometimes Naturalizers engage, sometimes they ignore.

Naturalizers and Flares have a failing alliance. In a healthy NVU they would be on the same side, both institutional immune response. In the dysfunctional NVU, Naturalizers have started scanning Flares as threats because Flare degranulation produces cellular debris that trips the tag-incoherence detector. They shoot each other sometimes. A Flare degranulation event in a Naturalizer patrol zone may produce a Naturalizer response against the surviving Flares. The immune system is turning on itself because the signaling that used to distinguish friend from debris has degraded.

The player can observe this. A corridor with Flare corpses and active Naturalizer patrols is a corridor where the system ate its own response team. This is one of the NVU's saddest environmental storytelling beats. The institutional enforcement is not evil; it is malfunctioning. The Flares were doing their jobs; the Naturalizers were doing theirs. The signals between them collapsed and now they kill each other.

### 7.6 Gnawers hunt metabolic signatures, any metabolic signatures

Gnawers detect metabolic activity and converge on the strongest signal in range. They do not distinguish between party members, siderophores, Flares mid-degranulation, or Spikers completing a connection. They want the metabolic spike.

A siderophore feeding on iron produces a strong metabolic signal. Gnawers in range will latch onto feeding siderophores, ignoring the party entirely. A living siderophore ecosystem is cover because the ecosystem generates louder signals than the party does.

Flares degranulating are a massive metabolic signal. Gnawers converge on a Flare burst site. The Flares are already dead or dying from the burst; the Gnawers arrive to scavenge. A Flare event in Gnawer territory produces a Gnawer pileup that takes both species offline for several seconds.

Spikers completing a damaging connection produce a brief metabolic spike at the discharge moment. Gnawers may converge on a Spiker that has just completed a connection before it can recover. A Spiker in Gnawer territory cannot complete connections often without being latched onto during the recovery window.

The ecological consequence is that Gnawers thin the populations of whatever is metabolically loud around them. Corridors with heavy Gnawer presence have quieter ecosystems because the loud species get eaten and the quiet species survive. The player who wants a quiet corridor should go where Gnawers have been for a while.

### 7.7 Flares are ecosystem detonations

A Flare event is catastrophic for the local ecology. Flares converge on damage sites, arrive in packs, and degranulate in radial bursts that damage everything in radius. This includes other Flares that arrived in the same convergence, which means Flare packs kill themselves as part of their firing pattern. The enzyme burst also damages siderophores in range, Tanglers in range (the inflammatory environment degrades protein aggregates), Candid colony edges, and any other biological entity the burst touches.

Every Flare event reshuffles the local ecology. A corridor that had a Flare burst five minutes ago has reduced or eliminated siderophore population in the burst radius, damaged Tangler filaments if any were nearby, cellular debris that will attract Gnawers within minutes, possible Naturalizer response if the debris trips the tag-incoherence detector, and chemical signaling that may flush Cytokine Storm systems.

The player can weaponize this. Triggering Flare convergence in an area the party does not want to stay in creates a temporary ecological void. The burst clears the immediate threats, and by the time other enemies drift back in, the party has moved on. Myke's Inflame explicitly generates damage signals that attract Flares; in a crowded corridor the player can use Myke as a Flare magnet deliberately, drawing the Flares to the damage site while the rest of the party slips around it.

The cost is that the Flare event is real, and getting caught in it is devastating. The player who miscalculates the timing takes the burst.

### 7.8 Spikers connect to anything that moves

Spikers do not distinguish targets. When anything moving enters a Spiker's receptive field with a clear line of sight, the Spiker locks on and establishes a visible connection to it. The connection must remain unbroken for an authored delay before it discharges and deals damage. Breaking line of sight at any point immediately severs the connection, cancels the pending damage, and forces the Spiker to reacquire. Siderophores, Naturalizer patrols, Gnawers, Tanglers, and party members all follow the same rule.

The ecological consequence is that Spiker corridors tend to be depopulated of enemies that cannot reach cover before a connection matures. Siderophores learn to route around; those that do not get killed. Tanglers who hunt neural activity are drawn toward Spikers as a food source, but they must cross its connection field and repeatedly break line of sight or reach it before the delay expires. Many Tanglers die in exposed Spiker corridors before reaching the Spiker that drew them.

A Spiker that has been completing connections regularly for a long time has a corridor around it that is unusually quiet of other enemies. The player may find a Spiker's territory easier to traverse than a siderophore-swarmed one if they can route between sightline breaks. The corridor is clean because the Spiker cleaned it.

### 7.9 Tanglers hunt neural activity

Tanglers feed on neural activity. They propagate by contact with cells that contain tau-compatible machinery, which means neural tissue. They are drawn to areas where neurons still fire, which in the dying NVU is a short list.

Spikers are a Tangler food source. Tanglers actively hunt Spikers because hyperexcitable neurons are the strongest neural activity signal in the NVU, and because tau pathology in real biology is known to target hyperexcitable neurons. A Tangler approaching a Spiker has to navigate the Spiker's connection field, and many die when they fail to break line of sight before the delay expires. The ones that succeed grapple the Spiker and propagate their tau into the Spiker's cellular machinery. A Spiker that has been tau-seeded eventually collapses. The player may find dead Spikers in corridors where Tangler populations have worked through the local Spiker population.

Tanglers avoid Candid colonies because the biofilm chemistry disrupts their filament integrity. Candid zones are Tangler-free.

Tanglers are damaged by Flare degranulation because the inflammatory environment degrades protein aggregates. A Flare event in Tangler territory thins the Tangler population temporarily.

Tanglers are indifferent to siderophores because siderophores contain no neural tissue to convert. The two species pass each other without engaging. A corridor with both Tanglers and siderophores is a corridor where the two threats are operating in parallel without interference.

Tanglers are drawn to areas with existing tau pathology, which means the NVU's old cognitive-function zones (The Open Files Initiative, signal conduit networks, anywhere neurons were dense in the living architecture). The player can read corridor history by Tangler density: heavy Tangler presence means this was an area where thinking happened once.

### 7.10 Toxos are everyone's target

If Toxos become a player-facing enemy beyond the NK Slop set piece, they occupy a specific ecological position: almost everything hunts them.

Naturalizers are built to kill Toxos. Real NK cells evolved specifically to handle Toxoplasma. In the NVU, Naturalizers in Toxo range engage immediately and do not route around them.

Gnawers are drawn to Toxo metabolism. Toxos in a Gnawer corridor get latched onto quickly.

Meebs can engulf Toxos because Toxo cell size is within Meeb digestion range. Meebs near Toxos eat them.

Flares do not specifically target Toxos, but a Flare burst near Toxos damages them.

Toxos survive best in corridors where the immune system has failed. Candid zones where Naturalizer scanning is disrupted. Areas where Naturalizer patrols have been killed by Flare friendly fire. Dead Zones where no immune response is functional anymore. Toxo distribution is a map of where the NVU's immune system has lost ground.

### 7.11 Redactors are invisible to normal perception

Late-game enforcement class. Membrane-cloaked pathological T-cells that have adopted antigenic-mimicry biology from Candid horizontal gene transfer; the enforcement apparatus has learned to be undetectable. Name is institutional Latin (no- + soma, no-body) echoing Trypanosoma, the real parasitic genus famous for membrane cloaking. Workers adopted the institutional name rather than inventing their own because Redactors are relatively recent and workers who encountered them rarely survived to coin slang.

Redactors are invisible to all standard sensing: character sight, Aster's data overlay, Peris's warm perception. They don't trigger the ambient sound design other enemies produce. The corridor looks and feels empty when Redactors are patrolling it.

How the player can see them. Tyreg's patrol-route map layer reveals Redactor routes regardless of visibility. She's the same biological class (regulatory T-cell); her enforcement credentials recognize what they are under the cloak. This is the same mechanism by which Naturalizers ignore her. Seefern light reveals their physical body as a pale outline within the activated glow radius. Direct contact (too late) is the third detection method: when a Redactor engages, the player learns it was there.

Engagement: silent wrap-grapple, similar to Tangler mechanics but without the proximity warning. A character grappled by an unseen Redactor is being attacked by something the player cannot address until they bring Seefern light into the area or have Tyreg confirm presence. The attack is not instantly lethal; it is a sustained contact that drains the character until they are down. Other party members can free the grappled character if they can see the Redactor (Seefern coverage, Tyreg present) or if they attack the grapple position blind (possible but wasteful of resources).

Distribution: rare in late Zone 2 (Beacon Hill onward), more common in Zone 3, densest near institutional infrastructure. Thematic: the more institutional a zone is, the more Redactors. Where the institution is strongest, its most evolved enforcement class operates.

Ecosystem interactions: Redactors occupy a specific niche, the institution's answer to ecological problems the civilization's standard enforcement (Naturalizers) can't handle. They hunt what Naturalizers can't see: Candid scouts, Toxo infiltrators, anyone with a tag failure that slipped past standard scanning. They are enforcement targeting the things the institution officially denies exist. They don't interact with other enemies the way most species do; they move through the ecology invisibly, picking off targets, and the ecology doesn't register their presence until biomass disappears.

The one exception: Seefern reveals them. A tended Seefern network in a Redactor-patrolled corridor produces something new. Other enemies in that corridor can also see the Redactors, and a Flare burst or a Candid's environmental toxicity affects them normally once visible. Seefern light ecologically exposes them to the rest of the ecosystem, with interesting late-game consequences in Zone 3 where Seefern-lit corridors become sites of chaotic multi-enemy engagement that Redactors triggered.

Compositional run implications: the Aster/Peris-only run is specifically harder in late-game Zone 2 and Zone 3 because neither character has Tyreg's patrol-route map layer. The player must compensate with aggressive Seefern cultivation in all institutional-heavy corridors. The player without Tyreg who has also neglected Peris's Seefern network walks through late-game Zone 2 being ambushed by enforcement they cannot see. This is intentional. Flora infrastructure as survival: the player who tended the network has a way to survive; the player who didn't has a problem.

Counter (once visible): Tyreg's gun works. Myke's fire works (and is unusually satisfying here, the institution's invisible elite burning). Oli's barrier can block Redactor pursuit. Peris's wrap can protect a grappled character while someone else addresses the Redactor. The Redactor's strength is the invisibility, not its combat capability. Once visible, it fights like a somewhat-weaker Naturalizer.

### 7.12 The inter-enemy matrix

The short version of who does what to whom. Rows affect columns. Entries describe the effect on the column's species.

| → | Sapscraps/siderophores | Candids | Meebs | Naturalizers | Gnawers | Flares | Spikers | Tanglers | Toxos |
|---|---|---|---|---|---|---|---|---|---|
| Siderophores | Compete for iron territory | Indifferent | Food source (engulfed) | Ignored (untagged) | Metabolically loud, attract | Damaged by degranulation | Hit if in receptive field | Indifferent | Indifferent |
| Candids | Displace from colonized zones | Grow where conditions allow | No effect | Disrupt tag-scanning | No effect | No effect | No effect | Zone-deny | No effect |
| Meebs | Engulf on contact | Cannot engulf | Territorial | No engagement | Too fast to catch | Degranulation kills Meebs | Hit if in receptive field | Cannot engulf (filaments) | Can engulf |
| Naturalizers | Ignore (untagged) | Cannot scan (interference) | No engagement | Factional tension | No engagement | Friendly-fire scans | No engagement | Engage if in tagged tissue | Engage aggressively |
| Gnawers | Converge on feeding signals | No signal to converge on | No engagement | Ignore (signal is low) | Territorial | Converge on burst signal | Converge on completed-connection spike | No engagement | Converge on metabolism |
| Flares | AoE damage | Damage colony edge | Not targeted, but caught in radius | Tag-incoherence response | Attract Gnawers via debris | AoE includes other Flares | Damage if in radius | Damage aggregates | Damage if in radius |
| Spikers | Connect; damage only if LOS persists | No effect on colony | Connect; damage only if LOS persists | Connect; damage only if LOS persists | Connect; damage only if LOS persists | Connect; damage only if LOS persists | N/A | Connect; damage only if LOS persists | Connect; damage only if LOS persists |
| Tanglers | Indifferent | Avoid zones | Cannot grapple | Engaged only if tag-disrupting | No engagement | Damaged by inflammation | Hunt (food source) | Propagate among each other | Indifferent |
| Toxos | Indifferent | Thrive in zones | Eaten | Killed aggressively | Eaten | Damaged by bursts | Hit if in receptive field | Indifferent | Coexist |

The matrix is not symmetrical. A Flare event damages Naturalizers (through cellular debris triggering tag-incoherence scans), but Naturalizers do not damage Flares except in that specific friendly-fire pattern. Meebs eat siderophores, but siderophores do not affect Meebs.

Redactors are not in the matrix because their cloaking makes them ecologically silent. Other enemies do not register their presence and do not interact with them under normal conditions. The exception is Seefern light: once a Redactor is revealed by Seefern glow, other enemies in the revealed area can perceive it and engage normally. A Flare burst in a Seefern-lit corridor damages visible Redactors. Candid toxicity affects revealed Redactors. Gnawers can lock onto revealed Redactor metabolism. This produces a late-game tactical pattern: the player who lights up a Redactor-patrolled corridor with Seeferns can make the corridor's own ecosystem turn against the Redactors, rather than confronting them directly. The enforcement becomes a target the moment it becomes visible.

### 7.13 What the ecosystem changes for gameplay

The enemy ecosystem has emergent behavior. The player does not just navigate enemies; they navigate enemy relationships. A corridor that looks empty might have had a Flare event that killed everything. A Tangler swarm concentrating in an area suggests Spikers nearby that the Tanglers are hunting. A suspiciously quiet Naturalizer patrol zone might be a Candid colony deadening their scans. A pile of dead Spikers indicates recent Tangler activity. A stretch of wall with Crust coverage has fewer Sapscraps for reasons the player can work out.

The player can weaponize these relationships. Leading a Tangler into a Candid zone degrades it. Drawing a Spiker connection onto a Tangler patrol can clear the patrol if the target remains exposed for the full delay. Triggering Flare convergence in a Gnawer-heavy area creates a Gnawer pileup that takes both species offline. Myke's fire triggers Flare convergence intentionally when the party needs a distraction. A party member who has been marked by a Naturalizer can wait in a Candid zone for the scan to lose its lock.

Enemy distribution tells corridor history. A corridor with heavy Candid colonization and no other threats had enemies once but the Candids drove them all out. A corridor with Spikers and no siderophores means the Spikers cleared the siderophores over time. A corridor with Tanglers and dead Spiker remains means the Tanglers fed here recently. A corridor with Flare corpses and active Naturalizer patrols is a corridor where the system ate its own response team.

The party is not the apex threat. In most combat games the player is the strongest thing in the room. In TRAWF, every encounter is multilateral. The enemies would be fighting each other even if the party was not there. The party walking through a corridor is a perturbation in an already-running system, not a force imposed on passive hazards.

### 7.14 The political ecology

All these enemies were, at one point, part of a functioning system. Flares were immune responders doing their jobs. Naturalizers enforced tag coherence to preserve the body's integrity. Siderophores were part of normal iron economy. Candids lived in small colonies that the immune system managed. Spikers were normal neurons firing normal action potentials. Tanglers were not a thing at all until tau pathology emerged.

The reason they are all hostile to each other now is that the system regulating their relationships has collapsed. In a healthy NVU, Naturalizers do not scan Flares because tag coherence is stable. Flares do not fire AoE at nothing because damage signals are meaningful. Siderophores are fed by regulated iron distribution. The dysregulation that made the NVU dying made the enemies fight each other. They are all trying to do their old jobs in a context where their old jobs do not make sense anymore.

That is a real thing about neurodegeneration: the cells and molecules that maintain the brain start attacking the brain when regulation fails. The enemies hating each other is not a fantasy element; it is what neurodegeneration is. Cells losing the signals that told them when to stop.

This is also the thematic bridge to the game's politics. The NVU's institutional framework (funding decisions, resource allocation, regulatory oversight) failed in specific ways that produced the cellular dysfunction the party is now navigating. Naturalizers attacking Flares is the cellular-scale version of institutional departments turning on each other when the regulation between them stops working. The Candid colonies making Naturalizers unable to function is the cellular-scale version of an unmonitored population growing in a niche the enforcement class can no longer reach. Every inter-enemy relationship in the matrix has a real-world political analog.

The player does not need to see this connection to enjoy the gameplay. The player who does see it finds a second layer that rewards attention.

(Open design questions for this system, balance/scripting/visibility/late-game-rebalancing/cure-component-interactions, are collected in section 17.)

### 7.15 Visual specifications (image generation prompts)

The following visual specs are absorbed from `fauna_image_prompts__3_.md`. Each entry describes the silhouette, form, locomotion, attack telegraph, hurt/death state, and biological inspiration to guide concept art and image generation.

**Style preamble (common to all species)**

PS2-era 3D low-poly geometry with pixel art textures and realistic dark/dramatic lighting. Restricted palette: muted teals and greens with rust-red and warm cream highlights, near-black background. Diorama-on-dark composition. Soft lighting from one direction, diffuse fill. Single specimen at frame center, isolated against the void. Subject reads as biological organism, not as machine.

[NOTE: `fauna_image_prompts__3_.md` currently carries the older voxel + painterly preamble. That doc should be updated to match the PS2-era 3D + pixel art register established in section 6.1.]

**Entry template.** Each species entry follows the same structure: tier (encounter frequency and detail budget), silhouette priority (the feature that must read at any distance), form (visual description), locomotion, attack telegraph (the wind-up signal), hurt/death (damage state and corpse), biological inspiration (real-world organism or chemistry).

#### Siderophore class

##### Sapscraps

**Tier:** Common. Workhorse swarm enemy, encountered constantly. Silhouette must read clearly at small scale and from across a corridor.

**Silhouette priority:** Three radial palps in C3 symmetry around a central recessed mouth. From above, the organism is a triangular three-pointed shape; from the side, it is a low disc with three forward-projecting hooks. The three-fold radial body plan is the read.

**Form:** Disc-like body sitting low to the ground, roughly chest-high to a small dog. Three forward-projecting hooked palps emerge in C3 symmetry from around a recessed central mouth-pit. Surface is a deep red-violet plated chitin (the iron-enterobactin complex color), simple and matte rather than detailed. The chelating clamps at the palp tips are the only sharply-rendered feature on the body; everything else stays simplified for visual economy.

**Locomotion:** Glides on three short stub-legs hidden beneath the disc body, one per palp segment. Movement is smooth and low to the ground, not insect-scuttling. The body rotates around its center as it changes direction (radial symmetry means there is no front; whichever palp is engaging is the front).

**Attack telegraph:** A single palp brightens with iron concentration (deep red-violet shifting toward magenta) and extends slightly outward as the chelating clamp opens. Brief wind-up, perhaps half a second. The lit palp is the attack direction.

**Hurt / death:** When hit, the body flattens slightly and one palp may snap off if the damage was direct. On death, the disc collapses inward toward its center and the palps splay outward in a triradiate flat shape — the corpse reads as a small dark three-pointed star on the floor. Other Sapscraps route around dead Sapscraps rather than feeding on them (siderophore class doesn't cannibalize).

*Biological inspiration:* Catecholate-class siderophores, particularly enterobactin from *E. coli*, which is a triscatecholate molecule with C3 symmetry that wraps around iron through six oxygen atoms in octahedral coordination. The species' three-fold radial body plan IS the molecular geometry. The deep red-violet color is the actual color of the iron-enterobactin complex.

##### Ferrules

**Tier:** Mid. Less common than Sapscraps but still encountered in groups at vessel-breach sites. Detail level moderate.

**Silhouette priority:** Translucent body with a single bright internal core. From any angle, the read is "soft glowing organism with a chartreuse-yellow heart visible through its skin."

**Form:** Soft amphipod-like body, gelatinous and slightly elongated, roughly the size of a small backpack. Outer surface pale green-yellow translucency, flexible rather than chitinous. Inside the body, a single visible cyclic structure (the chromophore) glows chartreuse-yellow, the surrounding gel diffusing the glow outward into a halo. The chromophore pulses slowly with the protein's folding cycle, a steady rhythm that distinguishes the organism from background lighting.

**Locomotion:** Low gliding motion on multiple short flexible feeding tendrils underneath, the way a sea slug glides on its foot. The body undulates slightly as it moves. Slower than Sapscraps.

**Attack telegraph:** The chromophore intensifies and concentrates toward the front of the body (the direction of attack) as a feeding tendril extends. The pulse rhythm accelerates from slow to rapid as the attack winds up. Bright telegraph; the player can read the direction from the chromophore's shift.

**Hurt / death:** When hit, the gel body deforms visibly and the chromophore flickers. On death, the gel deflates and the chromophore dims to a faint residual ember before going out entirely. The corpse is a flat translucent puddle with a small dark spot at the center where the chromophore was, leaking a faint glow at the puddle's edges for a few seconds before fading.

*Biological inspiration:* Pyoverdines from *Pseudomonas aeruginosa*, whose chromophore is a folded dihydroxyquinoline ring system fused around a planar fluorescent core. Pyoverdines fluoresce yellow-green under UV because the chromophore traps electron states in the ring. The species' translucent body housing a single visible chromophore IS the molecular structure made organism. *P. aeruginosa* in real infections is associated with vascular damage sites (wounds, burns, catheters), which the breach-clustering behavior reflects.

##### Hidras

**Tier:** Mid. Stationary or slow-moving, common in conduit corridors. Player encounters them as ambient infrastructure-mimic threats.

**Silhouette priority:** Three-fold blade segments along a coiled body. When motionless against cabling, the silhouette flattens; when alerted, the blades rotate slightly and the helix uncoils, breaking the disguise.

**Form:** Long multi-segmented body, roughly arm-thick. Each segment carries three radial blade-fins in C3 symmetry. The body coils in a propeller-twist along its length, segments rotating gradually relative to each other. Blade fins are flat and broad, mottled grey-bronze with metallic sheen at the edges. Recesses between segments are darker, almost black. Eyes are small dark pinholes distributed along the body, one or two per segment.

**Locomotion:** Snake-like undulation, but the propeller-twist gives the movement a screwing motion as the body advances. When camouflaged, motionless against infrastructure. When pursuing, the body unspools from its disguise position and slithers along the substrate, blades flicking outward at each segment.

**Attack telegraph:** The body coils tighter and the blades along the front segments rotate to fully extended position, catching light. Brief still-pose before strike. The strike itself is a fast lunge with the head segment leading, the front blades cutting forward.

**Hurt / death:** When hit, individual blade-fins can be sheared off — the body remains alive but loses C3 symmetry at the damaged segment, the asymmetry visibly affecting locomotion. Severed segments separate from the body but continue twitching for a few seconds. On full death, the body uncoils flat against the substrate, blades drooping outward; the corpse reads as a long ribbed strip with the propeller-twist relaxed.

*Biological inspiration:* Hydroxamate-class siderophores (desferrioxamine from *Streptomyces*, ferrichrome from *Aspergillus*), which form octahedral iron-coordination cages where three bidentate hydroxamate groups wrap around an iron atom in a propeller geometry: three blades meeting at a center, three-fold helical symmetry. The species' three-fold blade-segment body plan IS this molecular geometry. The chain-of-octahedra body extends the molecule into a multi-segmented organism. Earlier in the project the species was called Chains; the rename to Hidras committed to the segmented-helical morphology.

##### Crusts

**Tier:** Environmental landmark, not mobile. Treated as terrain rather than as an enemy that approaches the player. Detail level allowed to be high since the player can study it at close range.

**Silhouette priority:** Hexagonal pore-array waxy mat fused into a wall section. The hexagonal close-packing is the read.

**Form:** A thick layered wax-mat colony covering a wall section, the surface architecture an intricate hexagonal close-packed pore array. Matte cream-pale between the pores, each pore a deep dark recess set in the hexagonal grid. Cross-section visible at the colony's edge: three or four layers of pore-arrays stacked vertically, the entire structure built into and partially fusing with the wall it grew on. Color shifts subtly across the colony from pale cream at the older center to faint rust-tint at the actively-growing edge. The boundary between Crust and substrate is effectively gone at the center.

**Locomotion:** None. The colony does not move. The "expansion" the player observes is the slow growth of the colony's outer edge over time — visible across multiple visits to the same area, but never within a single combat encounter.

**Attack telegraph:** When something approaches, pores in the near vicinity dilate visibly and emit a faint puff of acidic vapor — a hazard zone forms in front of the active pores for a few seconds before damaging contact. The dilating pores are the telegraph; the player can step around the affected area.

**Hurt / death:** When attacked, the colony loses sections rather than dying. Damaged areas of the mat crack and flake away, exposing the bare wall beneath. The colony cannot be fully killed in normal play; sustained burning (Myke's flame, environmental fires) clears the colony from a region for the rest of the encounter. The colony will grow back if the player returns much later.

*Biological inspiration:* Mycobactin-class siderophores produced by *Mycobacterium tuberculosis*, which are membrane-embedded rather than secreted: the molecule sits IN the lipid bilayer of the bacterium's outer surface. Real mycobacterial colonies under electron microscopy show a cratered wax-mat structure with the lipid membrane pocked by transmembrane pores arranged in hexagonal close-packing. The species' visual register is this colony architecture made readable at human scale: the hexagonal pore-array IS the mycolic acid arrangement on a real *Mycobacterium* surface. The wall-paranoia behavior reflects mycobacterial intracellular pathogen biology, where the bacterium hides in host membrane infrastructure.

#### Colonizer / environment-changer

##### Candids

**Tier:** Environmental landmark, not mobile. Like Crusts, the colony is terrain that the player navigates around rather than an enemy that approaches. High detail allowed at close range.

**Silhouette priority:** Three-strata layered fungal architecture. The basal carpet, the chained mid-layer, and the upper canopy must read as three distinct horizontal bands.

**Form:** A fungal biofilm colony with three architectural strata visible in cross-section. Bottom: dense pebbled carpet of small round yeast-cells. Middle: forest of vertical chained pseudohyphal cells stretching upward in connected segments. Top: horizontal canopy of branched true-hyphae forming a filament cap. Pale yellow-cream throughout, with the basal layer slightly darker (older yeast) and the canopy slightly translucent (newer hyphae). Around the colony, a bleached pH-shifted zone where the institutional flooring is visibly compromised.

**Locomotion:** None. Colony grows over the course of the game, expanding its territory by hours of in-world time, never by a single encounter.

**Attack telegraph:** Passive area denial. The bleached pH-shifted zone visibly extends from the colony's edge a meter or so, and characters who stand in this zone take continuous damage. The visible discoloration IS the telegraph; standing on bleached substrate is the warning.

**Hurt / death:** Like Crusts, Candids cannot be killed outright. Burning damages the canopy layer, exposing the chained mid-layer beneath, which is more vulnerable. Sustained burning collapses the colony down through its strata until only the basal yeast layer remains — at which point the colony is dormant for the rest of the encounter. The hurt-state visually shows charred patches in the canopy and the layered structure exposed where the canopy has burned away. Scarpet outcompetes Candids at the colony edge through sustained tending; in regions where Peris has Scarpet established, Candid colonies retreat over time.

*Biological inspiration:* *Candida albicans* biofilms in real immunocompromised infections, which form the canonical three-layer structure: basal yeast layer at the substrate, middle pseudohyphal layer of elongated chained cells, upper true-hyphal layer of branched filaments. The species' three-strata architecture IS the *Candida* biofilm morphology. The pH-shifting and environment-hostile behavior models real Candida biofilm chemistry: secreted aspartyl proteases, biofilm-mediated drug resistance, and the suppression of competing microbiota. The fungal-vs-bacterial distinction is part of the project's design rule that player flora are plants and enemy colonizers are fungal or bacterial.

#### Scavenger / engulfer

##### Meebs

**Tier:** Common in some zones, rare in others. Detail level moderate. Silhouette must be readable from above and at distance.

**Silhouette priority:** Translucent blob with multiple food cups (mouth-pits) distributed across the body surface, oriented in all directions. The "many mouths" reading is the species ID.

**Form:** A translucent amoeboid organism roughly the size of a small dog, gelatinous and roughly spherical at rest, deforming continuously as it moves. Multiple food cups (deep concave invaginations of the membrane) scattered across the body surface, each puckering outward like a mouth-pit. The body is translucent enough to show internal organization: a centrally-positioned nucleus, contractile vacuoles pulsing slightly, food vacuoles full of partially-digested material visible as darker irregular shapes. Color is pale green-grey, almost transparent at the edges.

**Locomotion:** Pseudopod extension and retraction. The organism flows toward its target rather than walking — pseudopods extend in the direction of movement, then the rest of the body flows after them. No clear front or back; orientation is wherever the largest pseudopod is currently extending. Slow, inexorable rather than fast.

**Attack telegraph:** When close to a target, one of the food cups orients toward the target and dilates wider, the membrane around it puckering outward. The cup brightens as digestive enzymes concentrate. Brief delay before the cup snaps forward to suction onto the target. The dilating, brightening cup is the telegraph; the player can move out of its line of approach.

**Hurt / death:** When hit, the gel body deforms and pseudopods retract briefly. Sustained damage causes the body to lose cohesion: it visibly thins at the edges, the internal organelles exposed through increasingly transparent membrane. On death, the gel collapses into a flat puddle, the nucleus and vacuoles settling at the bottom. The puddle remains briefly visible before being absorbed back into the substrate.

*Biological inspiration:* Free-living pathogenic amoebae, particularly *Naegleria fowleri* (the brain-eating amoeba) whose defining morphological feature is the amoebostome or food cup: a deep invagination of the cell membrane that suctions onto target cells and pulls pieces off. *Naegleria* in real cases of primary amoebic meningoencephalitis uses these food cups to consume host tissue. The species' multiple-food-cup body plan IS this feeding apparatus distributed across the surface. The visible internal chaos (nucleus, vacuoles, partial-digestion contents) is biologically accurate to the *Naegleria* trophozoite stage.

#### Enforcement class

##### Naturalizers

**Tier:** Rare/Elite. Encountered in patrols of two or three. Player encounters them infrequently but at close range, with full boss-tier detail at the model level. Mid encounter frequency in institutional zones.

**Silhouette priority:** Low quadrupedal-or-hexapodal beetle-like body with a translucent dorsal carapace, glowing internal granule clusters visible through the carapace as warm orange-yellow dots packed together like pomegranate seeds. The "internal lights through translucent shell" is the read at any distance.

**Form:** A polished beetle-like organism walking on six short stubby limbs, body close to the ground, deceptively soft posture. Dorsal carapace is grey-blue with translucent patches across the back revealing dense granule clusters inside, glinting warm orange-yellow. The granules are packed tightly inside the carapace, visible as a stippled luminous interior. A single sharper pale yellow band across the head where sensory receptors cluster. The silhouette is decidedly NOT humanoid: low, focused, polished.

**Locomotion:** Walks on six legs, three per side, in a smooth coordinated gait. Movement is steady and purposeful rather than fast — they patrol rather than chase, but commit when they engage. They can pivot in place by using their legs alternately.

**Attack telegraph:** When engaging a target, the granule clusters concentrate visibly toward a single point on the body — the contact synapse — usually the front of the head or one of the forelegs. That point begins to glow more intensely as granules pack into it, and a brief stillness precedes the strike. The bright concentration point is the attack telegraph and the visual marker for where the deployment will land.

**Hurt / death:** When hit, the dorsal carapace can crack, exposing more of the internal granule field. Heavy damage causes granules to leak out as small glowing droplets that fall to the substrate. On death, the legs collapse and the body settles flat, the carapace cracking fully and the granule field dimming over a few seconds before going dark. The corpse leaves a faint warm afterglow on the floor briefly before fading.

*Biological inspiration:* Natural killer (NK) cells, the innate-immunity lymphocyte class whose killing apparatus is stored INSIDE the cell as cytotoxic granules pre-loaded with perforin (which forms membrane pores in target cells) and granzymes (proteases that trigger apoptosis). Real NK cells deploy this payload through a focused contact synapse called the immunological synapse: the granules concentrate at the contact point and release their contents into the target cell. The species' translucent carapace revealing internal granule clusters IS this biology made visible. The contact-synapse glow models the real synaptic deployment. The bipedal-power-armor humanoid silhouette of earlier design passes was wrong; real NK cells are amorphous lymphocytes with internal payloads, and the species' visual register reflects that.

##### Redactors

**Tier:** Rare/Elite. Late-game encounter, low frequency. Full boss-tier detail at close range. Two compositions, one for each state.

**Silhouette priority:**
- *Cloaked:* a section of background that has peeled forward into space, locally perfect mimicry but the form is detectable as a vertical plane of surface-detail standing where no surface should be.
- *Revealed:* an elongated, malformed Naturalizer-derived body, longer-than-tall with irregular granule clusters and too many limbs.

**Cloaked-state form:** A corridor or institutional space in which one section of the wallpaper, floor tile, framed poster, or architectural detail in the background appears to have peeled forward into the space — a vertically-oriented plane of surface-detail standing in three-dimensional space. The cloaking is locally perfect: the Redactor's surface is exactly what is behind it, copied with high fidelity, but the surface tension between what the cloak displays and what is actually behind betrays the form. The viewer notices the discrepancy as a wrongness: a doorway slightly displaced, a fern frond hovering an inch ahead of where its plant pot is, a tile pattern continuing where it shouldn't. The body underneath is invisible.

**Revealed-state form:** A body that reads as Naturalizer-derived but stretched and malformed. Longer than tall, with the polished-beetle silhouette of the Naturalizer elongated into something that walks more uprightly. Translucent carapace patches still show internal granule clusters but the granules are malformed, smaller, and unevenly distributed; the elegant pomegranate-seed packing of the Naturalizer is here irregular, with empty patches and overdense clusters. The carapace surface itself has a faint residual ghost of whatever it was just cloaked as, like an afterimage that has not fully cleared. Eight limbs articulated more loosely than the Naturalizer's six. Color is paler than the Naturalizer's institutional grey-blue, washed out, with the warm granule-glow dimmer and uneven.

**Locomotion:** Cloaked, the Redactor drifts slowly through the space along the wall plane, the surface-mimicry shifting gradually to remain consistent with whatever it's passing in front of. Revealed, the body walks on eight loose limbs in a clattering uneven gait, the limbs not perfectly coordinated. Faster than Naturalizers when revealed, but visibly less stable.

**Attack telegraph:** Cloaked attack: the cloaked plane briefly distorts as the body inside readies to strike, the surface-mimicry rippling like heat haze for half a second. The ripple is the only warning. Revealed attack: same as Naturalizer (granule concentration toward a body point) but the irregular granule distribution makes the telegraph less clean — multiple points may brighten at once before one commits.

**Hurt / death:** Cloaked, taking damage forces the cloak to drop — the Redactor reveals involuntarily and cannot re-cloak in combat. Revealed, the carapace cracks like a Naturalizer's but the cracks reveal more empty space inside than granules. On death, the body collapses laterally and the residual cloak-ghost flickers visibly across the surface a few times before settling. The corpse retains a faint surface-mimicry pattern, freezing whatever it last copied.

*Biological inspiration:* Pathological T-cells with antigenic-mimicry adaptations, modeled on *Trypanosoma brucei*'s membrane cloaking via variant surface glycoproteins (VSGs). *Trypanosoma* species are famous in real parasitology for their ability to continuously change their surface antigens, evading host immune detection by being indistinguishable from background. The cloaked-state mechanic — surface IS disguise, the cloaking is the entire organism's defining feature — IS this biology rendered as visual register. The acquisition of this ability via Candid horizontal gene transfer is biologically defensible (real horizontal gene transfer happens between bacterial and eukaryotic genomes, and immune-evasion mechanisms are among the most common transferred traits). The Naturalizer-derived-but-malformed revealed body reflects the species' history: they evolved from the same NK-cell biology as Naturalizers and inherited the granule-clusters, but the antigenic-mimicry adaptation came at structural cost. The name *Redactor* is institutional Latin (*no-* + *soma*, no-body), echoing *Trypanosoma* directly.

#### Hunter / predator

##### Gnawers

**Tier:** Common in Zone 3, mid in Zone 2. Encountered in small packs (2-4) or alone. Detail level moderate.

**Silhouette priority:** Low-slung quadruped with a wide, drooping proteolytic maw and a visible enzyme-haze around the head. The "drooling pursuit-hunter" silhouette is the read.

**Form:** A long ratlike quadruped with sleek oily-black coat carrying a faint red-purple heme sheen, hunched predatory posture, body roughly the size of a medium dog but lower and longer. The mouth is wide and drooping, with a constant pale enzyme-mist hanging in the air around the jaws and trailing behind the head as the animal moves. Eyes small, set far forward in a low skull. Heme pigmentation darkest around the mouth and along the lower jaw. Skin is oily and slightly wet-looking.

**Locomotion:** Quadrupedal pursuit. Fast bursts of running with periodic pauses to scan, like a hunting hyena. Body low to the ground with the head leading. Can sustain pursuit for long distances.

**Attack telegraph:** The enzyme cloud around the mouth thickens and expands forward as the Gnawer approaches striking range, a visibly denser haze concentrating in front of the jaws. The mouth opens wider and the jaw drops. Brief pause before the lunge. The thickening enzyme cloud is the wind-up; characters caught in the cloud at the moment of bite take additional proteolytic damage beyond the bite itself.

**Hurt / death:** When hit, the Gnawer recoils backward and the enzyme cloud disperses briefly before re-forming. Heavy damage exposes the underlying tissue beneath the oily coat — pale tissue showing through tears in the skin, contrasting with the dark exterior. On death, the body collapses sideways in a long sprawl. The enzyme cloud lingers around the corpse for a few seconds before dispersing — corpses are briefly hazardous to walk over.

*Biological inspiration:* *Porphyromonas gingivalis* and gingipains, the species responsible for periodontal disease and recently linked to Alzheimer's pathology in published research. *P. gingivalis* is a black-pigmented anaerobic gram-negative bacterium whose dark coloration comes from heme accumulation; in real culture, *P. gingivalis* colonies are visibly black on blood agar. Gingipains are the bacterium's extracellular cysteine proteases — secreted into the surrounding environment to digest host tissue before consumption. The species' visible enzyme cloud around the mouth IS this real biology: real *P. gingivalis* digests outside its body before consuming the products. The metabolic-signature hunting behavior models *P. gingivalis*'s real preference for tissue with active metabolism. The rat-like body is a direct visual rhyme: rats are real Alzheimer's-research carriers of *P. gingivalis*.

##### Spikers

**Tier:** Environmental landmark / turret. Stationary, but combat-relevant. Detail level allowed to be high since the player approaches them deliberately.

**Silhouette priority:** Asymmetric pyramidal-neuron geometry. Triangular base, ONE thick apical stalk reaching straight up to a single dendritic arborization at the top, basal dendrites splaying at the floor. The single upward-reaching stalk capped with branched arborization is the read.

**Form:** Anchored to the substrate by a triangular soma at the base, from which one thick apical stalk rises straight upward like a periscope, terminating in a single dendritic arborization at the top branching outward like a fan of bare twigs. Basal dendrites splay at the floor like splayed roots around the base. The trunk is pale teal-white with darker veining along its length tracing the connection pathway from base to top. The triangular soma at the base is the densest, most clearly defined part of the body. The arborization branches at the top point in roughly all horizontal directions, giving the Spiker a 360-degree receptive field from its summit.

**Locomotion:** None. The Spiker is rooted in place. The species' "territory" is the receptive field around it.

**Attack telegraph:** ONE specific branch of the upper arborization brightens when the Spiker acquires a moving target, then a continuous visible filament connects that branch to the target. Charge pulses travel along the filament during the authored damage delay, making the remaining danger legible. If anything blocks line of sight, the filament snaps and fades immediately and the charge resets harmlessly. Only an uninterrupted connection that survives the full delay culminates in a discharge and damage.

**Hurt / death:** When hit, the trunk's veining flickers and the arborization dims briefly. Heavy damage shears off branches of the upper arborization, reducing the Spiker's firing arc. With enough damage, the trunk cracks and slumps. On death, the trunk falls and breaks at the base, the arborization shattering on impact; the splayed basal dendrites remain at the floor like a dead root system. Tau-seeded Spikers (those Tanglers have grappled and propagated tau into) collapse from inside instead — the trunk wilts and the veining goes dark in patches before the whole structure crumbles inward.

*Biological inspiration:* Pyramidal neurons in real cortex and hippocampus, which have a defining triangular soma at the base, a single apical dendrite reaching toward the surface of the cortex, and basal dendrites splaying at the cell body. Pyramidal neurons are the most abundant excitatory neurons in real cerebral cortex and the cells most affected by Alzheimer's-associated network hyperexcitability. Real research shows that Alzheimer's-affected brains exhibit elevated baseline neuronal firing rates and seizure-like activity; the species' "fires at anything that moves" behavior models this hyperexcitable circuit pathology. The asymmetric triangular silhouette IS the pyramidal neuron's defining morphology rendered at organism scale.

##### Tanglers

**Tier:** Mid. Encountered alone or in pairs in cognitive-zone corridors. Detail level moderate.

**Silhouette priority:** Double-helix body with grappling filament-extensions. The two intertwined strands are the read; the limbs are extensions of the helix itself, not separate appendages.

**Form:** Two intertwined filament strands coiling around each other in a left-handed helix, the body a continuous corrupted twist of paired strands. Body posture is low and hunched, the central twist sometimes near-collapsed and sometimes elongated as the organism moves. From the surface of the helix, additional filament extensions emerge and unspool toward prey: grappling limbs that are themselves more helix-strands uncoiling outward, with hooked filament ends. No defined head; the front is wherever the body is currently advancing. Color is dark olive-brown with paler highlights along the helix's outer edges, fine ribbing visible along each strand giving a protein-filament texture.

**Locomotion:** The helix flexes and crawls forward by rotating its body in a screw-like motion, the two strands taking turns providing leverage. Slow but persistent. When stalking prey, the body flattens and creeps; when committing, it raises up on the basal strand and the upper portion arcs forward.

**Attack telegraph:** Before grappling, two or three filament-extensions uncoil from the body and reach forward, the hooked ends opening visibly. The reach is slow and visible, allowing the player to step away. The actual grapple is a quick snap of the hooks closing. On contact, the filament begins to drain neural activity from the target — visible as the filament brightening as it transfers material from the target back to the central body.

**Hurt / death:** When hit, the helix loosens partially, the two strands separating slightly before re-twisting. Sustained damage causes the strands to fully separate at one end, reducing the Tangler's body length. Filament-extensions can be severed by attack on the limb itself; severed filaments writhe briefly on the floor before going inert. On death, the helix unwinds entirely, the two strands lying flat against the substrate in a tangled pile that slowly dissolves into protein dust over a few seconds. Tau-seeded victims (Spikers, party members who took grapple damage and didn't recover) carry visible filament-traces on their bodies that persist as a status effect.

*Biological inspiration:* Tau protein pathology and prion-like propagation in Alzheimer's disease. Tau is a microtubule-associated protein that, in pathological states, forms hyperphosphorylated paired helical filaments — two filament strands coiling around each other in a left-handed helix — that aggregate into neurofibrillary tangles. Recent research has shown that tau aggregates can propagate cell-to-cell in a prion-like manner. The species' double-helix body IS the paired helical filament structure made organism. The grappling limbs that uncoil from the body's helix IS the propagation mechanism: contact-mediated transfer of pathological protein machinery, where the limbs are extensions of the same corrupted filament that constitutes the organism. Their neural-activity hunting behavior reflects the real observation that tau pathology preferentially affects hyperexcitable neurons (which is why Tanglers hunt Spikers).

#### Burst / detonation class

##### Flares

**Tier:** Mid. Stationary or near-stationary, scattered through Zone 2 and Zone 3. Detail level moderate at distance, high if the player approaches deliberately.

**Silhouette priority:** Translucent rounded body with a multi-lobed bead-string nucleus visible centrally, surrounded by three classes of granules in three colors. The "translucent ball with internal beads" is the read.

**Form:** A rounded translucent body roughly the size of a beach ball, sitting low to the ground or slightly above it. Two defining internal features visible through the membrane: a multi-lobed nucleus resembling a string of three or four connected beads at the body's center, and three distinct classes of granules packed densely around the nucleus — small dark purple primary, medium pale yellow secondary, larger pale green tertiary. The granules are scattered through the cytoplasm in roughly equal numbers but at three different sizes and colors, giving the interior a stippled multi-color reading. Membrane is pale yellow-cream with a subtle warm tone, neutral and unthreatening at rest.

**Locomotion:** Drifts slowly along the substrate via membrane contraction, the body subtly distending and re-rounding. Not built for pursuit. The species is essentially a stationary hazard that responds to local triggers.

**Attack telegraph:** When triggered, the granules concentrate toward the membrane surface and the cell distends visibly as it prepares to degranulate. The membrane brightens from within with an inflammatory heat over a 2-3 second wind-up, the bead-string nucleus pulsing rapidly. The brightening membrane and visible distension are the warning; characters in the surrounding area have time to step out of the burst radius. The actual burst is a sudden expansion outward of granule contents in all directions — AoE damage to anything in proximity, regardless of identity.

**Hurt / death:** When hit, the membrane visibly punctures and granule contents leak out as small colored droplets. Heavy damage triggers premature degranulation — the Flare bursts before its full wind-up, doing reduced damage. On death from non-burst damage, the body deflates and the membrane settles into a flat puddle, the bead-string nucleus and remaining granules visible at the bottom of the puddle. After full burst, only the deflated membrane and dispersed granule droplets remain, slowly fading into the substrate.

*Biological inspiration:* Neutrophils, the most abundant innate-immunity cell type in real biology and the primary responder in acute inflammation. Real neutrophils have two defining cellular features that the species visually preserves: a multi-lobed nucleus (typically three to five connected lobes resembling a string of beads, which is one of the most identifiable features under a microscope) and three classes of granules with distinct contents — primary/azurophilic granules (containing myeloperoxidase, dark in standard staining), secondary/specific granules (containing lactoferrin, lighter), and tertiary granules (containing gelatinase). The three-color granule field models these three classes. The bystander damage from oxidative bursts and proteolytic activity that the species inflicts on AoE is biologically accurate to neutrophil behavior in real inflammation: the cells are not malicious, but their activation produces collateral tissue damage as a routine consequence of doing their job.

#### Set piece / political target

##### Toxos

**Tier:** Common in failed-immune zones (Dead Zones, late Candid colonies). Set-piece in NK Slop scene. Detail level moderate.

**Silhouette priority:** Crescent body with a visible apical conoid and rhoptry-bulbs at the leading point. The "moon-shape with a small spiral cone at one tip" is the read.

**Form:** A small crescent-bodied organism, roughly the size of a small cat. Body curved like a banana, one side longer than the other, the curvature concave toward what reads as the "front." At the leading point of the crescent, a small visible apical conoid: a pale spiral protein cone that extends and retracts as the organism moves, flanked by two slightly bulbous rhoptry-organelles visibly containing secretion vesicles. The rear half of the crescent body holds a darker round mass — the nucleus visible through the body wall. Color is institutional grey with a faint reddish tinge throughout, but the apical structures (cone and rhoptries) read in a paler cream that stands out against the body. Small relative to other organisms.

**Locomotion:** Gliding motion across the substrate, the crescent body undulating slightly. Real *Toxoplasma* tachyzoites use a unique gliding-motility system; the in-game version reads similar — no visible legs, no obvious propulsion, just smooth gliding with the conoid leading.

**Attack telegraph:** The apical conoid extends fully outward and the rhoptry-bulbs visibly swell with secretion vesicles before a strike. Brief wind-up. The strike is a quick lunge with the conoid leading, attempting to penetrate a target's body to deliver invasion factors. Toxos are not strong fighters; their only weapon is the cone, and it is useful primarily for entering host tissue rather than for combat damage.

**Hurt / death:** When hit, the crescent body curls inward defensively, the conoid retracting back into the body. Heavy damage causes the body to lose its crescent shape, deflating into a more rounded sad form. On death, the body collapses and the apical structures release their secretion vesicles harmlessly into the substrate, pale cream droplets fading on the floor. Toxos are easy to kill — they survive only where the local immune system has failed to find them.

*Biological inspiration:* *Toxoplasma gondii*, particularly the tachyzoite stage. Real *T. gondii* tachyzoites have a defining apical complex at the front: the conoid (a spiral protein cone that protrudes during cell invasion), flanked by rhoptry organelles that secrete invasion factors, and supported by micronemes that release adhesion proteins. The crescent body shape is the actual *Toxoplasma* tachyzoite morphology, which is why the apicomplexan phylum gets its name from this apical complex. The species' "everyone hunts them" status reflects the real fact that NK cells evolved with *Toxoplasma* as one of their primary evolutionary pressures, that *Toxoplasma* is engulfed by amoebae and eliminated by neutrophils in a healthy immune environment, and that they survive only where immune function has failed (opportunistic toxoplasmosis in immunocompromised patients).

#### Ecology snapshot (multi-species scene)

A cross-section of a single corridor in late Zone 2 showing several enemy species in their natural ecological relationship: a small Sapscrap swarm wandering through the foreground, a Crust patch on the wall behind them, a Spiker rooted in a side alcove with its arborization aimed at the corridor, a Tangler stalking toward the Spiker (drawn by neural activity, willing to risk the firing zone), a Naturalizer patrol approaching from the far end. The composition shows the threats coexisting and competing rather than swarming together. Voxel-painterly style, restricted palette, near-black background, diorama-on-dark composition. Mood: an ecology, not an encounter — multiple threats in the same space, each operating by its own logic.

## 8. Flora system

Absorbed from `flora_taxonomy__2_.md` (gameplay roles, sensory presentations, Peris's vocabulary, hiding-tier mapping, dedicated entries) and `flora_image_prompts__3_.md` (visual specs). Full design rationale lives in those source docs; this section is the GDD-level spec.

The flora's origins were settled after this section was first drafted and live in full in the flora roster's cultivar section. In brief, with two exceptions every tended and decorative species is a feral cultivar, the escaped and degraded descendant of an engineered commercial product, which fits the established detail that the plants stay green regardless of care or abandonment. The two exceptions are the last true natives, the Flures and the forget-me-nots. The roster carries each cultivar's product origin (Seefern's communication line is the one whose mechanism preceded the psyknapses and portals, section 5.6) and the high-grading history that emptied the wilderness the cultivars then spread into.

### 8.1 The roster

The flora roster was consolidated from 11 candidate species down to 5 in an earlier pass, on the design principle that each species should earn its place through load-bearing mechanics rather than niche functions. Gasafoetida was added later when the Inflammashunt puzzle revealed a need for a flora that produces a portable repellent. Climbvine was added as the slope-and-traversal species. The current roster is 7 species plus a network property that applies to all tended flora.

| Species | Primary function | Secondary function | Tier |
|---|---|---|---|
| **Seefern** | Light / vision extension (pushes back Peris's fog); widest activated zones of any flora | Reveals normally-invisible threats: Hidra outlines, early-stage Crust patches, Redactor bodies | Visibility / counter-stealth |
| **Scarpet** | Biofilm removal, anti-Candid competition with sustained tending | Medium cover (scarred substrate reads as dead to iron-sensors); eating-safe zone outside visual range | Medium |
| **Flure** | Iron decoy (loosest-tier cover) | — | Loosest |
| **Hushbloom** | Enemy stun burst, regenerates over time after use | — | Tactical tool |
| **Capbage** | Tight cover / pursuit-break (self-sealing leaf head) | Eating-safe enclosure; general-purpose storage cache (1-2 items); hide-rest with major tiredness debuff | Tight |
| **Gasafoetida** | Tend produces a held pod that emits repellent gas; while emitting, all enemies in proximity are repelled until the gas runs out | Fire-reactive: cluster pods combust serotinously when ignited, ejecting flaming projectiles in sequence | Tactical tool / hazard |
| **Climbvine** | Produces structural-fiber vines (held items) that can be dropped from height, climbed up and down, tied between rotating surfaces to mechanically couple them, and cut to release the coupling | Grows only on inclined surfaces; planted specimens can only be placed on slopes | Traversal / structural |

The dual-register naming for Climbvine: institutional name (used by professional-class characters and Aster's overlay) is *Climbvine*; worker-register name (used by worker-class characters with prior experience of the plant) is *Sloperope*. The dual register is documented in `dual_vocabulary_system.md`.

Climbvine has two operational forms in level design. Naturally-growing Climbvine is level-state: specimens placed by the level designer at strategic locations to provide return paths between completed segments of an encounter. Player-planted Climbvine is player-state: specimens Peris tends and harvests during play, dropped to bridge specific surfaces as needed; these are temporary and revert if Peris dies. First appearance is in the Plumbing Power Project (Act 1, shelters 2-3) on a side passage off the main corridor, where the affordance is taught through geometry rather than a tutorial prompt.

Climbvine harvest is bounded by growth time (one vine per rest cycle per tended plant), hand-slot capacity (2 vines per character), and slope availability (player-planted vines only on inclined surfaces, so the level's slope geometry caps the supply). Naturally-growing Climbvine is not a harvest source.

### 8.2 The network property (applies to all tended flora)

Any tended flora is a node in Peris's connected care network. This is a world-state property, not a species. Three emergent properties:

**Communication.** Information transmits between tended nodes. A Flure that detects a siderophore cluster can signal a distant Capbage to prepare. Players don't interact with this directly; it produces ambient world-feel that care-work has real infrastructure consequences.

**Storm early warning.** Any node that reads atmospheric pressure and chemical signatures propagates storm warnings through the network. The player sees a visible ripple, flora closing, dimming, or stiffening in sequence across the map before a cytokine storm hits. Peris's perception surfaces this as intuition ("something's coming"). The scale of advance warning scales with network density: a sparse network gives short notice, a dense one gives minutes.

**Late-game map layer.** As Peris's own memory degrades, her perception overlay begins pulling data from the flora network. The flora remembers what she planted, where, and what it has sensed since it was planted. The network is her memory externalized. The mechanic rewards her decline: the player who tended throughout the game has a navigational resource the player who didn't has lost access to.

### 8.3 Hiding-tier mapping

`survival_gameplay_feel.md` defines three tiers of hiding: loosest (positional, no hiding, just not being the most interesting iron source), medium (environmental safe zones that mask scent and degrade pursuit over time), and tight (pursuit-break, the horror-of-waiting-inside-a-sealed-space moment). Flora maps to these tiers as follows.

| Tier | Flora species | Function |
|---|---|---|
| Loosest | **Flure** | Active iron decoy. Broadcasts a false iron signal stronger than the party's. Siderophores redirect toward it. Not hiding; outcompeting for attention. |
| Medium | **Scarpet** | Scent-masking ground cover. The substrate has been metabolized; iron-sensors read it as dead. Siderophores in idle/foraging state route around Scarpet patches; siderophores in active pursuit follow in but the signal degrades over time inside. Also: eating-safe zone outside enemy visual range. |
| Tight | **Capbage** | Full pursuit-break through self-sealing leaves. A head of overlapping leaves that opens for characters to enter and seals shut reactively when siderophores approach. Character fully undetectable while inside. |

Seefern does not provide cover. Its function in the hiding-adjacent space is counter-stealth: revealing threats the player would otherwise not see.

The player without a tended flora network can still use architectural tight hides (maintenance closets, alcoves, sealed doors). Capbage become the primary tight-tier option in Zone 3 where architectural cover has decayed; the player who has been tending Peris's work through Zone 2 has tight-hide options in Zone 3 where others have none.

### 8.4 Peris's worker vocabulary

Peris does not use the institutional or technical names for flora. The system has names like Seefern and Scarpet because the system catalogs things. Peris learned flora through tending, through reaching for what a plant needed before she could name it. Her vocabulary came from the act of care, not from classification.

| Species | Peris's word | Etymology in her usage |
|---|---|---|
| Seefern | the vines, the glow-vines, "the little ones" when she is tending them | She does not distinguish between Seefern varieties. They are all "vines." |
| Scarpet | the spread, the low cover, "the clearing stuff" | Named for what it does, not what it is. |
| Flure | the flures (plural), the lures, "the iron flowers" | She distinguishes normal flures from Mother Flure; the individual scale matters. |
| Hushbloom | the quiet-blooms, the silencers | Their stun effect registers to her as quieting. |
| Capbage | the heads, "my heads," the safeholds | She tends them like homes rather than like plants. The possessive is specific to Capbage. |
| Gasafoetida | the stinkers, the pods, "the smelly ones" | She uses "stinkers" most often when she's holding a fresh one, "the pods" when she's referring to the cluster. The fire-reactive bursts she calls "the popcorn going off," keeping the older worker-slang for that specific behavior. |

When Peris talks about flora in dialogue, these are the words she reaches for first. Aster may use the technical names because his overlay labels them. Myke and Oli will use whatever they have heard; the vocabulary split is a character read, indicating where a speaker got their flora knowledge from.

### 8.5 Ambient flora

The world has flora that is simply alive, growing in corners where conditions allow, contributing atmosphere rather than gameplay affordances. This category is load-bearing for scene work and for the Peris-specific texture of the world.

**Forget-me-nots.** Small blue flowers that grow in shelter corners, near warm infrastructure, in the overlap zones between maintained sections and wild corridors. They require no tending. They bloom on their own when conditions are right. Peris tends them by habit, not because they need it. The flowers are the game's emotional signal for the care instinct that is older than memory. In the bittersweet ending, these are the flowers Peris's hands still know how to tend when her mind no longer knows why. Forget-me-nots are everywhere, quietly. Every shelter has some. The player who notices blue flowers in a shelter has registered something the game does not call attention to. The player who does not notice loses nothing.

Like the Flure, the forget-me-not is one of the two true natives rather than a cultivar, the last of the real wild surviving in scattered refuges, which is why it needs no tending and blooms on its own. The densest and most significant of these refuges is the Chaperone Lattice itself, where the last forget-me-nots grow inside the iron-chelation component, the flower of remembrance living in the thing that holds back the rust. This grounds Peris's perception of their scent as the rust going away (section 2.3.2), and the flora roster carries the native-survivor framing in full.

**Wild cluster flowers (unnamed).** Small, varied, low-growing. Different corridors have different species that emerged from seeds that survived the degradation. These are not catalogued because they are not functional. They are texture. A corridor with healthy wild flowers at its edges is a corridor that still has conditions for life. A corridor with no flora at all, not even weeds, is a corridor where conditions have failed completely. The absence of wild growth is the strongest environmental signal of ecological collapse. Zone 3's Dead Zones are so named because nothing grows there, not even the unnamed ambient flora.

**Moss carpets.** Non-gameplay moss that grows on damp surfaces in the Plumbing and its perivascular sub-areas. Visually similar to Scarpet but without the biofilm-clearing function. Peris can distinguish the functional from the ambient by touch; Aster's overlay tags them differently.

**Vine skeletons.** The remains of flora that died and were never cleared. Common in unmaintained corridors. Every time the player walks through a corridor with vine skeletons, they are walking through the past of a system that could not keep its own growth alive. Peris registers them. She does not speak about them. The player who is paying attention sees her pause near them sometimes.

### 8.6 Sensory signatures

Each species presents differently to Peris's senses (and by extension to the player, through her perception layer when she is the active character). The game's warm-view rendering for Peris's perception should reflect these signatures.

**Seefern.** Glow is the defining signal. Steady teal-green, slight pulse with the infrastructure's electrical hum. Smells faintly sweet and moist, like rain on warm rock. Touch is cool and slightly slick. Stressed Seefern dims unevenly, smells off, and feels dry. Dying Seefern has no glow; the stem is brittle. Dead Seefern is gray-brown, crumbles to touch.

Seefern's specific bioluminescent wavelength reveals things that don't show under normal light or Aster's standard overlay. Within the activated glow radius of a tended Seefern: Hidras (pipe-mimicking siderophores) show a faint internal pulse distinguishing them from real infrastructure; early-stage Crust patches register as faintly alive rather than as ordinary rust discoloration; Redactors (late-game invisible enforcement units) appear as pale body outlines. The reveal function is why Seefern planting becomes strategic in specific corridors, not just anywhere the player wants more light.

Seefern cultivated in Dead Zone conditions runs hot. The glow is colder (blue-white rather than teal-green), the scent is acrid, and the plant dies within about a day. The player who carries Seefern seeds into a Dead Zone can produce temporary light at the cost of the seeds; they are consumable light. The reveal function still works in this form, at smaller radius.

**Scarpet.** Low, spreading, near-invisible when healthy. The signal is textural: the floor feels slightly softer where Scarpet is active, and biofilm presence reads as a resistance underfoot that Scarpet has cleared. Smells neutral, slightly mineral, with a faint dry-earth note from the scarred substrate. Stressed Scarpet develops orange patches. Dead Scarpet leaves a pale residue that reads as calcified dust. Scarpet that is actively competing with a Candid colony looks stressed (leaves yellow, stems pale) but is not dying. This is fighting; the outcome depends on colony maturity, Scarpet tending level, and player reinforcement.

**Hushbloom.** Small, nodding flower on a slender stem, petals folded inward around a central core holding the neuroactive compounds. Pale lavender or white. Smells faintly sweet when charged and ready, neutral after release. Touch is velvety; the petals react to proximity by folding further (thigmonastic). Stressed Hushbloom will not take a charge. Dying Hushbloom goes translucent. Dead Hushbloom smells sharply of damp stone. After a Hushbloom releases its stun burst, the petals reopen and the central core is visibly empty. The plant regenerates over several in-game hours.

### 8.7 Flora states (healthy / dormant / stressed / dying / dead)

For each species, Peris can read state by sense. The game's data overlay provides labels; Peris's perception provides the underlying experience.

**Healthy.** Full color, full scent signature, expected behavior (closing, glowing, releasing), responsive to touch (resilient, springy, alive-feeling).

**Dormant.** Reduced color (pales but retains hue), scent is muted but present, behavior paused (not closing, not glowing, but not dead either), touch is less responsive but not unresponsive. Dormancy is rest, not death.

**Stressed.** Color is uneven or wrong. Scent has a secondary note that is not present in healthy specimens, often more acrid, more chemically charged. Behavior is incomplete or erratic. Touch may feel dry, brittle, or overly wet. Stress is recoverable if the cause is addressed.

**Dying.** Color fading to grays and browns. Scent is specific to the species but unmistakable: the signature of a plant losing its ability to regulate its own chemistry. Touch is fragile, non-responsive.

**Dead.** No color, no scent (or, in some species, a residual smell that persists for hours or days). Touch is crumbling, brittle, or collapsed depending on species. Dead flora can still be recognized as the species it was by its remnants, but the life has left it.

The dying-smell signature is cross-species in Peris's vocabulary. She does not have a separate word for "dying Seefern smell" and "dying flure smell." She has one word for the underlying register, something like "the smell of losing" or "the stress-smell," and the specific species contributes the overtones. This is why the Mother Flure chamber scene works: when Peris says "I know this smell," she is identifying the register, not the species. The species is flure. The register is dying.

### 8.8 Flure (dedicated entry)

Flures are mid-sized flora, roughly waist-high when fully grown, with a characteristic radial petal arrangement around a central core. The petals are iron-bronze in color with metallic sheen under light. The core is a dense cluster of sensory filaments that secrete iron-attractant compounds. Flures grow with a deep anchoring root system that extends well beyond their visible footprint; a fully grown flure has a root system several times the diameter of its visible body.

The Flure is one of the two true natives that outlasted the collapse rather than a feral cultivar, and its survival strategy is the reason. The iron-attractant core is not only a decoy, it is bait. The siderophore enemies the haze draws in are the Flure's food, fed on as corpses once they fall within the broadcast radius, so the species needs no surrounding ecosystem to live, only the prey its own signal supplies. The decoy the player exploits in the field is the plant hunting. The roster records this alongside the cultivar history.

Healthy flures smell metallic-sweet, with a note that reads as "wet iron" at close range. The scent carries; a corridor with a healthy flure has a low-level iron presence in the air that siderophores detect from a distance.

Flures grow at the intersections of moisture seeps and iron-rich infrastructure, places where the NVU's biological substrate is leaking nutrients into the architecture. They are most common in the Plumbing Power Project, in The Hypelines, and at the junctions where multiple corridors intersect.

**Species vs. individual.** The tendable species is the regular flure. Mother Flure is a specific individual of enormous scale: a flure that has grown for decades in a containment chamber where conditions are marginal but persistent, reaching a size no normal flure achieves. Mother Flure is not a separate species; she is an outlier. Her root system extends through the entire chamber. Her body is the chamber. Normal wild flures are a fraction of her scale. The player encountering normal flures in the Plumbing will not know Mother Flure exists. When they reach the chamber, the scale is the revelation.

**Stress and dying states.** Flures in stress develop a different scent: still metallic, but with an underlying note of decay. The sweetness drops; the metal stays. This is the scent that propagates when a flure is dying. It is also, at much lower concentration, what the Mother Flure chamber smells like; she is not dying, but she has been under persistent stress for a long time. A dying flure collapses from the core outward. The petals lose their metallic sheen first, graying to a dull bronze. The central core dries and cracks. The root system contracts but remains partially active for some time after the visible body has died. A corpse of a flure in a corridor will still draw siderophores for hours after death.

**Peris's relationship.** Flures are one of the species Peris recognizes from her earliest memory. Her hands know how to tend them. Her distress around a dying flure is not about losing the gameplay function; it is about watching something she has an ancient relationship with fail in a way she cannot fix. The dead flure beat in the Plumbing is her first encounter in the game with flora that is past saving.

### 8.9 Capbage (dedicated entry)

Tight-tier flora that fills the gap in the hiding hierarchy, parallel to architectural maintenance closets and sealed doors. Portmanteau of *cap* (the leaves close over the cavity like a sealing cap) and *cabbage* (the plant's overall form). Singular *Capbage*, plural *Capbages*.

**Form.** A large dense head of overlapping leaves, roughly the size of a small closet at full size, set on a short thick stem. Outer leaves broad and waxy with strong central ribs. Inner leaves curve toward a hollow central cavity. Open: leaves splay outward exposing the cavity. Closed: leaves fold inward and overlap into a single tight near-spherical sealed head, no visible seam from outside, surface continuous and convex. The transition between the two states is the species' defining feature.

**Biology.** A self-sealing leaf head evolved as a protective response to environmental threat. The cavity at its center naturally hosts small fertilizing organisms during open phases. When the leaves detect the iron-acidic chemical signature of pursuing siderophores, they fold inward and seal. The leaves are thick and fibrous, reinforced with mineral deposits the plant draws up from its roots, and resist siderophore pressure the way cactus flesh resists herbivory.

Healthy Capbage leaves are deep green with cream-colored ribs. Stressed or dying Capbage fade to yellow-grey, leaves wilting and softening at the edges. The healthiest Capbages have a soft internal luminescence visible at the leaf seams when sealed, like a lantern wrapped in foliage.

**Mechanics.** One character per Capbage standard. Rare larger specimens fit two. Three-character Capbages are deep Zone 3, possibly endgame.

Entering: walk into an open Capbage. Single interaction. The leaves begin folding closed. Close animation 2-3 seconds for wild, 1-2 seconds for tended. The character is vulnerable during closure but the leaves are committed.

Closed state: character is fully undetectable to all siderophore sensing (iron signal, scent, proximity). Pursuit breaks as if the character had entered a sealed door. Character cannot act while inside but can hear muffled sounds from outside.

Opening: the Capbage opens when it senses threats have left. The player does not trigger opening; the plant does. Untended Capbages open hesitantly and sometimes prematurely; tended Capbages read the environment reliably.

Tended vs wild: wild Capbages close slowly, stay closed for minimum duration, may open while threats are still nearby. Tended Capbages close quickly, stay closed as long as threats remain, and read the environment accurately. Upgrading takes Peris's sustained attention across multiple shelter cycles.

Distribution: only in stable microenvironments, deep in Peris's tended flora network. Capbages won't grow in sterile corridors, Candid-colonized zones, or frequently-stormed areas. Presence of a Capbage signals the corridor has been cared for.

Destruction: Myke's fire kills them instantly. Candid colonies smother them over days. Heavy siderophore traffic degrades them. Neglect doesn't kill them outright but they fall back to wild state. Seeds: precious. A single seed produces one Capbage after multiple in-game days of growth in a tended patch.

**Eating inside a sealed Capbage.** A character can eat held food while sealed inside. The cavity contains all metabolic, scent, and visual signal generation; the eating animation is invisible to all detection outside. This makes Capbage the gold-standard eating-safe location, distinct from Scarpet patches which provide eating safety only outside visual range. Trade-off: entering a Capbage means committing to the seal until the plant opens.

**Cache (general-purpose storage).** A Capbage can store one or two items as a persistent cache. Wild Capbages hold one item; tended Capbages hold two. The cavity holds whatever the player puts in it; the player learns through results what stores well. When a Capbage holds cached items, it seals shut. Open (splayed) = empty. Closed = either character inside (with name label) or cached items (no label). Cached items remain until retrieved or until the Capbage dies. Specific item interactions: Gasafoetida pods have their gas contained by the seal until cavity opens; Hushbloom samples triggered by movement during entry would stun whichever character entered; Flure seeds can germinate inside, producing a small Flure that broadcasts iron and inverts the plant's intended function; Cure components cache stably; Lysate may degrade long-term. A Capbage cannot hold both a character and cached items simultaneously; if a character enters a sealed (stocked) Capbage, items transfer to free hands or are thrown out the cavity.

**Hide-rest (sleeping inside a sealed Capbage at night).** A character or full party can rest through the night inside sealed Capbages instead of returning to a shelter. Hide-rest is functional but worse than shelter rest. Hide-rest does not cost ATP. It does not restore HP (characters end the night at the same HP they started). It applies a major tiredness debuff (twice the impact of the minor tiredness debuff that follows a no-ATP shelter rest), affecting overlay fidelity (Aster), perception baseline (Peris), stamina regen rate, and stamina cap. The debuffs persist through the next day until the party gets a proper shelter rest. Cure component progress does not advance on hide-rest nights. Night skips when all conscious party members are inside sealed Capbages, in a shelter, or in mixed combinations.

Thematic logic: shelter is a place where the party can recover fully. A Capbage is a place where the party can survive. Choosing to hide-rest is a survival call when shelter is unreachable, not a substitute for proper sleep.

**Sensory signature.** Capbages smell faintly sweet and vegetal, like fresh-cut cabbage with a honey undertone. Touch is firm but flexible at the leaves. Healthy Capbages hum softly when sealed, internal cilia along the inner leaf surfaces rippling to circulate air. The hum is a readable cue for the character hiding inside: steady hum = the plant is comfortable, agitated hum = threats still near, silence = something is wrong.

**Zone distribution.** Zone 2 early: rare wild Capbages, mostly architectural tight hides still. Zone 2 mid: wild and tended roughly equal to architectural hides. Zone 2 late: architectural hides degrading, Capbages become more reliable if tended. Zone 3: almost no architectural hides, Capbages are the primary tight-tier option, tending becomes survival-critical.

**Peris's relationship.** She calls them "the heads," often with the possessive ("my heads"). This is unusual for her vocabulary; she doesn't possess most flora, just tends them. Capbages are different because the relationship is more obviously mutualist: she gives them microenvironment and care, they give the party shelter. She treats them like homes rather than like plants. When a Capbage she has tended dies, the grief register is specifically house-loss, not plant-loss.

### 8.10 Gasafoetida (dedicated entry)

Gasafoetida is the flora that has two characters and earns both. Tended, it is a defensive tool: a swelling sac released into a character's hands, carried where needed, the sac's repellent gas causing every nearby enemy to flee while the gas continues to emit. Ignited by flame, it is a hazard: the cluster's gas-bearing pods combust in sequence, launching flaming projectiles in random directions that bounce off walls and damage anything in the area. The same plant, two registers.

Named for *Ferula asafoetida*, the real-world "devil's dung" plant whose sulfur-rich resin is famously repellent to many animals. The fire-reactive behavior parallels serotinous conifers (lodgepole pines, jack pines, and certain sequoias) whose resin-sealed cones release ballistically under fire-temperature heat. Gasafoetida's gas-bearing pods follow the same logic: pods stay sealed under normal conditions; flame ruptures the seal, the gas combusts, and the pods are launched by the resulting pressure. The cluster's two registers are biology's two registers in real serotinous plants: chemical defense at baseline, ballistic dispersal under fire.

**Mechanics.** A Gasafoetida cluster grows in damp corners with low light. Small bulbous pods on short stems, the pods swelling and contracting visibly with what reads as breathing. Peris can tend the cluster to charge a single pod for harvest; the harvested pod can be carried by any character (it occupies a hand slot) and the repellent gas begins emitting on contact with the carrier's body heat. While the gas is emitting, every enemy in proximity to the carrier is repelled. The effect ends when the gas runs out, typically 30 to 45 seconds depending on cluster health and tending state. A spent pod is inert. The repellent works on every enemy class because the gas chemistry registers as a universal danger signal rather than a class-specific one.

**Fire-reactive function.** Environmental rather than tended. Any flame source within the cluster's ambient range (Myke's Inflame, lit infrastructure, a flaming projectile from another source) ignites the pods in sequence. The serotinous burst launches 3-5 flaming pods from random points in the cluster, each travelling on a parabolic arc with bouncing physics, each impact dealing fire damage. The cluster regrows the pods over several minutes after ignition.

**Two characters.** The same plant can be tactical advantage and environmental hazard depending on whether the player is using fire near it. The player who has Myke and has not learned to recognize Gasafoetida clusters will repeatedly trigger the serotinous burst. The player who has scouted and recognized the cluster shape can use Myke's fire near the cluster intentionally to area-deny enemies clustered nearby (the burst becomes a weapon). This is the fire-management lesson the Inflammashunt puzzle teaches in miniature: fire is not bad; unmanaged fire is bad.

**Sensory signature.** Sharp sulfurous scent (much sharper than Hushbloom, with the eye-watering quality of overripe alliums or asafoetida resin, reads as "potent and ready to react"). The cluster's breathing motion is visible at close range. Aster's overlay tags Gasafoetida clusters with a small fire-warning icon when his data layer is active.

**Zone distribution.** Common in damp Zone 2 corridors, particularly the Plumbing and The Honeycomb Cooperative. Less common in Zone 3 where the dryness reduces growth conditions. The Inflammashunt puzzle's chamber has a Gasafoetida cluster as part of the puzzle's recovery mechanic.

**Peris's relationship.** She tends Gasafoetida with care because they are reactive in both directions. She likes them: they remind her that defense and danger are sometimes the same thing in different contexts. In the Inflammashunt puzzle, her tending of the Gasafoetida for the recovery mechanic is the narrative center of that scene. The plant that is hazard becomes tool because she knows how to ask it for the right reaction.

### 8.11 Resolution Roots (puzzle-only flora)

The Inflammashunt puzzle features a flora element that is not part of the tendable-species roster: the Resolution Roots that grow from floor cracks in the puzzle chamber and connect to dormant Chelators through underground filaments. These are puzzle-specific flora, not a species the player can encounter, harvest, or tend elsewhere.

Design rationale: their mechanic of pacifying Chelators through symbiotic feeding would trivialize Chelator combat if available throughout the game. Chelators are the entry-level enemy whose threat establishes the iron-economy combat loop. A flora that pacifies them would invalidate that loop. The Inflammashunt puzzle's narrative argument is specifically that the Resolution-Root-and-Chelator symbiosis is the resolution-cycle the civilization stopped maintaining; finding a working instance of it is meaningful precisely because it is rare and contextual.

Resolution Roots are pale, almost translucent, with visible filaments running underground that pulse with a faint warm light when the symbiosis is active. Peris perceives them as a "warm hum" rather than as a scent or visual marker. She tends them in the puzzle but does not attempt to seed them elsewhere; she understands intuitively that the symbiosis requires conditions that cannot be transplanted. Treat as set-dressing flora unique to this puzzle, comparable to the dead-flure scene's specific flure or the Mother Flure as a singular individual.

### 8.12 Visual specifications (image generation prompts)

Per-species visual specs absorbed from `flora_image_prompts__3_.md`. Each entry follows a consistent template: tier (encounter frequency and detail budget), silhouette priority (the feature that must read at any distance), form (visual description), interaction state, sensory signature, biological inspiration. The common style preamble matches section 6.1: PS2-era 3D low-poly geometry with pixel art textures and realistic dark/dramatic lighting; restricted palette of muted teals and greens with rust-red and warm cream highlights; near-black background; diorama-on-dark composition.

[NOTE: `flora_image_prompts__3_.md` may carry the older voxel + painterly preamble. That doc should be updated to match section 6.1.]

#### Seefern

**Tier:** Common in tended corridors of Zone 2 and the early Zone 3 transition. The most-encountered flora species. Detail level simplified for distance reading.

**Silhouette priority:** Fern fronds with bright glowing veins. The vasculature-as-lantern is the read at any distance — at small scale, the plant reads as "a small thing made of glowing veins."

**Affordance signal:** Each leaflet on the frond has an eye-marking. The leaflets are already in a rounded-diamond shape, and a darker oval mark at each leaflet's center, ringed by the brighter vein-glow, makes each leaflet read explicitly as an eye looking outward. The eye-markings tell the player "this plant sees" — the vision-extension function is encoded in the visible morphology before the player ever interacts with it. A mature Seefern reads as a small fern with dozens of glowing eyes facing outward in all directions.

**Form:** A small fern, roughly knee-high at maturity. Translucent fronds with bright cool teal-green vein structure as the dominant light source — central rachis runs bright from base to tip, with branching veins fanning out into each leaflet, brightness concentrated along the vasculature. Where there are no veins, leaf tissue is darker translucent green, almost shadowed. Each leaflet carries the eye-marking: a dark oval at the leaflet's center surrounded by the bright vein-ring. Young fronds at the tips curl in fiddlehead pattern. Substrate is a soft mossy ground with a fainter, paler glow from a slower-glowing moss species.

**States:**
- *Wild Seefern:* veins glow at low intensity, the eye-markings are dim and nearly closed. Reads as dormant. Light range is small, only a meter or two around the plant.
- *Tended Seefern:* veins glow at full intensity, the eye-markings are bright and clearly visible as outward-facing eyes. Light range extends meaningfully (3-5 meters), pushing back Peris's perception fog and revealing normally-invisible threats (Hidra outlines, early-stage Crust patches, Redactor bodies).
- *Stressed Seefern (Dead Zone):* veins burn unusually bright, almost overdriven, the eye-markings wide-open and vivid. The plant is dying within a day but giving extreme illumination during that period.

**Tending interaction:** Peris kneels at the substrate and runs her fingers along the moss base, then lightly traces along each frond's central rachis. The vein-glow brightens progressively from base to tip following her touch, the eye-markings opening as she works. Tending takes 4-6 seconds; the visible progression of eye-openings tells the player when it's complete. Tended Seefern remain bright until they decay back to wild state over multiple shelter cycles of neglect.

**Hurt / death:** Damaged fronds dim and the eye-markings close shut. A Seefern that has lost most of its fronds keeps glowing weakly from the central stalk only, with a single eye-marking on the surviving leaflet. On full death, the entire plant goes dark and the fronds wilt. Candid colonization smothers Seeferns over days; a Seefern caught in a Candid spread shows white fungal mat creeping up from the substrate, the eye-markings closing as the colonization advances.

*Biological inspiration:* Bioluminescent plants and fungi where the glow concentrates along vasculature rather than diffusing uniformly. Real bioluminescent organisms with this property: the Light Bio glowing petunia (which uses a fungal luciferin pathway, with the substrate transported through the vascular system and glow brightest at the veins where substrate concentrates), and bioluminescent moss like *Schistostega pennata* whose chloroplasts function as light reflectors. The eye-markings reference real plant patterns where leaflet centers carry darker spots (foliar trichomes, leaf-vein domatia, varietal cultivar markings on plants like *Calathea*); the markings here are biologically defensible AND function as a player-readable signal for vision-extension. The vision-extension function maps onto astrocyte syncytial networks, which Aster's class biologically maintains; in-world Peris's tended Seefern reads as the worker-class equivalent of the institution's signal-extension infrastructure.

#### Scarpet

**Tier:** Common in tended corridors, environmental rather than encounter. Moderate detail at close range, simplified silhouette at distance.

**Silhouette priority:** Low dense moss mat with two integrated colors — pale green of living moss and rust-orange of metabolized iron-extracted patches — visible across the surface. The "two-tone moss carpet" is the read at a glance.

**Affordance signal:** The rust patches encode the function. The metabolized zones are visibly cleaner — the underlying substrate beneath them has a bleached, scoured appearance, lighter than the substrate around it. A player walking near a Scarpet patch sees that the area immediately beneath the moss is, at the substrate level, "scrubbed clean" of iron deposits. Siderophore-class enemies routing past the carpet visibly arc around the bleached zone, signaling that this is the medium-cover area. The rust streaks tell the player "this plant has been working here," and the bleached substrate beneath tells them "the iron is gone here."

**Form:** A low dense moss mat, roughly the area of a large rug, with the body of the carpet rising 5-10 centimeters off the substrate. Pale green of living moss in the actively-growing patches, rust-orange shading to dark brown in the metabolized zones where iron has precipitated within the moss tissue. The boundary between the two states is irregular, with rust streaks and patches scattered through the green like wound-tissue scars worked across living surface. At close range, texture is specifically moss-like: small leafy gametophytes visible as tiny overlapping leaves, structure dense and pillowy. The substrate beneath fully-metabolized patches shows a bleached scar-like discoloration.

**States:**
- *Wild Scarpet:* small patch, mostly green with limited rust streaking. Has not yet scrubbed enough substrate to fully suppress local iron signals. Provides minor cover bonus only.
- *Tended Scarpet:* large patch, rust streaks distributed through the carpet, substrate beneath visibly bleached across most of the patch's area. Full medium-cover function — siderophore-class enemies in idle/foraging state route around the patch entirely; siderophores in active pursuit may follow in but the signal degrades within seconds.
- *Senescent Scarpet:* the patch has metabolized everything available and is mostly rust-brown with little remaining green. The medium-cover function still works because the substrate is fully scrubbed, but the moss is dying for lack of remaining iron substrate.

**Tending interaction:** Peris kneels at the patch edge and presses her palms flat against the moss, working outward in slow circular motions. As she tends, fresh green growth appears at the edges of the patch and rust streaks deepen in the older patches. The carpet visibly expands during tending. Tending takes 8-10 seconds; the visible expansion of the patch boundary tells the player when work is paying off. Sustained tending across multiple shelter cycles upgrades a wild Scarpet to a tended one.

**Hurt / death:** Burning damages Scarpet — fire across the moss leaves a charred patch that the rest of the carpet must regrow from the edges. Candid colonization is the death threat: a Candid colony at a Scarpet's edge will out-compete the moss, the fungal mat creeping over the carpet and smothering it. A Scarpet under Candid attack shows the boundary clearly: green moss giving way to white fungal canopy, with a thin contested zone where the two organisms meet. Sustained Peris tending can hold the boundary; neglected, the Candid wins.

*Biological inspiration:* Iron-bioremediating mosses found at acid mine drainage sites. *Schistidium rivulare* and other Bryophyta that grow on iron-rich substrates accumulate iron oxide within their tissues, producing the characteristic rust-streaked-on-green appearance of real iron-mat communities. Real bioremediation moss can drop substrate iron concentrations to near-zero in colonized patches, which is the "scarred substrate reads dead to iron-sensors" mechanic in-world. The species' anti-Candid competition function parallels antagonistic moss-fungal interactions in real soil ecology.

#### Flure

**Tier:** Mid frequency. Found in tended corridors and occasionally wild near vessel-adjacent areas. Detail moderate.

**Silhouette priority:** Trumpet-shaped flower atop a slender stem, with iron dust visibly hanging in the air around the lower stem. The "flower with reddish atmospheric haze" is the read.

**Affordance signal:** The phytosiderophore haze rising from the soil around the base is the iron-broadcast signal made visible. Players see the haze and learn to read it: this plant is currently broadcasting iron. The haze brightness correlates to broadcast strength — wild Flures barely haze, tended Flures haze visibly, peak-tended Flures emit clear reddish dust visible from across the corridor. Siderophore-class enemies arc toward Flures in the haze radius. Players who plant Flures along expected enemy routes are using a visible decoy mechanic.

**Form:** A flowering plant rising from a small basal rosette, slender stem 30-50 centimeters tall, single trumpet-shaped flower at the top. Basal rosette leaves are dark and heme-pigmented (older, iron-saturated), reading as faintly metallic-bronze. Mid-stem leaves are progressively lighter and greener (newer growth still building iron reserves). The trumpet flower is biologically plant-like, NOT made of metal: the petals are normal flower tissue but with copper-toned veining showing where iron has been concentrated for broadcast. Petals fade from rust-red at the tips to amber at the throat. From the soil around the base, faint reddish dust rises into the air — phytosiderophores visible as atmospheric haze. The roots are visible just at the soil surface as red-dark fibers spreading outward.

**States:**
- *Wild Flure:* small flower, single trumpet bloom, faint dust visible only in close proximity. Broadcasts a weak iron signal that competes with the party's signal at short range.
- *Tended Flure:* full bloom, multiple subsidiary trumpets opening from the central stem, dust rising in a clear visible column from the base. Broadcasts a strong signal that outcompetes the party at significant range — siderophores redirect from a corridor away.
- *Spent Flure:* the plant has emptied its iron reserves into a sustained broadcast. Petals droop and fade to dull amber, dust thins to nothing. Recovers over multiple shelter cycles if Peris tends it back; otherwise dies.

**Tending interaction:** Peris kneels and works the soil around the basal rosette, then runs her hands up the stem to coax the iron up into the bloom. As she tends, the reddish dust at the base intensifies and the flower's copper veining brightens. The plant visibly responds: petals open wider, additional smaller trumpets begin to emerge from the stem at lower nodes. Tending takes 6-8 seconds.

**Hurt / death:** Damage to the flower itself causes the petals to fall and the dust to die out within seconds. Damage to the stem cuts the broadcast immediately. On full death, the plant collapses and the basal rosette is the last thing to dim, the heme-pigmented leaves slowly fading to grey. A Flure killed during pursuit redirection releases a final pulse of iron dust as it dies — players can use the visual to gauge whether the broadcast has ended.

*Biological inspiration:* Phytosiderophore-producing plants in the Poaceae and Cyperaceae families, which release mugineic acids from their roots to chelate soil iron. Real phytosiderophore release into the rhizosphere is a documented phenomenon — the dust hanging in the air around the Flure is biologically accurate to this. Iron-hyperaccumulating plants like *Imperata cylindrica* concentrate iron as ferritin in older leaves, producing the dark heme-pigmentation visible at the base. The trumpet-flower form references real iron-attractive flowers like fritillaries and certain lilies that pollinators read by iron-related compound signaling. The "decoy" function inverts normal phytosiderophore use: rather than capturing iron for the plant's own metabolism, the Flure broadcasts a stronger iron signal than the party to redirect siderophore-class enemies. The species was originally called Ferrolure before the name was clipped.

#### Hushbloom

**Tier:** Mid frequency. Found in tended damp corridors. Detail moderate.

**Silhouette priority:** Compound leaves with paired leaflets along a central rachis, leaflets splayed open in resting state. The "comb-like fern" silhouette is the read.

**Affordance signal:** Visible pulvini (the swollen base of each leaflet) read as small bulbous nodes at the leaflet attachment points, faintly translucent, with a subtle inner pulse of pale lavender-grey. The pulvini tell the player "these leaflets fold reactively" — the pressure-storage is encoded in visible swelling. Players also see a faint pale lavender-grey haze around recently-triggered Hushblooms, the residue of the GABA-mimetic burst, fading over a few seconds. The haze tells the player "this plant just fired and is now recharging."

**Form:** A small plant with several compound leaves emerging from a slender drooping stem. Each compound leaf carries small paired leaflets in opposite pairs along a central rachis, comb-like, with 8-12 leaflets per compound leaf. Leaflets are pale green on their upper surfaces with slightly purple-tinted undersides. Stems are slightly purple-tinted with darker purple at the leaf nodes. At the base of each leaflet, a visible pulvinus reads as a small bulbous node, faintly translucent. The plant overall is lower and more spread than upright, fern-like in posture.

**States:**
- *Charged Hushbloom:* leaflets fully splayed open, pulvini swollen and bright, the plant looks visibly tense like a balloon under pressure. Ready to trigger.
- *Triggered Hushbloom:* the leaflets have folded inward in a wave along each rachis, the entire compound leaf drooping along the stem in a folded fan shape. Pale lavender-grey haze visible briefly around the plant. Pulvini are deflated.
- *Recharging Hushbloom:* the leaflets are still folded but the pulvini are slowly re-inflating. Reads as in-between state — not yet ready, not freshly fired. Recharge takes 30-60 seconds depending on tending state.
- *Tended Hushbloom:* multiple compound leaves charged simultaneously, taller and bushier than wild specimens, pulvini brighter. Tended Hushblooms recharge faster and produce stronger stuns.

**Tending interaction:** Peris kneels and works at the soil around the stem base, then carefully checks each pulvinus along each compound leaf — never touching the leaflets directly (which would trigger them). The plant responds to her care by growing additional compound leaves over multiple shelter cycles, and tended pulvini become visibly larger and brighter. Tending takes 5-7 seconds and the visible response is leaflet count increasing and pulvini glowing slightly.

**Hurt / death:** Damaged leaflets shrivel and fall, reducing the plant's response area. A Hushbloom that has triggered all its leaflets simultaneously may exhaust itself if not given time to recharge — the pulvini stay deflated and the plant cannot fire again until tended. On full death, all compound leaves droop limply and the pulvini go grey-white, the plant slumping onto the substrate.

*Biological inspiration:* *Mimosa pudica* (the touch-me-not / sensitive plant) and related thigmonastic plants, which fold compound leaves rapidly via pulvini — swollen cells at the base of each leaflet that lose turgor pressure when an electrical signal arrives. The compound-leaf morphology is *Mimosa*'s defining feature; the wave-pattern of leaflet-folding along the rachis is biologically accurate. The stun mechanism is GABA-mimetic, paralleling real neuroactive plant compounds (kava lactones from *Piper methysticum*, valerenic acid from *Valeriana*, scutellarin from *Scutellaria*). In an earlier design pass the species was called Hushcap and had a fungal cap; the redesign moved it to a thigmonastic plant body since the project's design rule reserves fungal biology for enemy colonizers (Candids) and assigns plants to player flora.

#### Capbage

**Tier:** Mid frequency in tended Zone 2 corridors, becomes the primary tight-tier hide in Zone 3. Detail moderate, but the open-state cavity needs to read clearly at distance.

**Silhouette priority:** Dense head of overlapping leaves with a visible cavity at the apex. The "cabbage with a hole on top" silhouette is the read at any distance — the cavity tells the player "shelter."

**Affordance signal:** The cavity is the affordance. When open, the cavity is the most prominent feature: a dark recess at the apex of the head, framed by the parted topmost leaves, clearly large enough for a character to enter. The cavity reads as "doorway." When sealed, the seam-lines between folded leaves trace a roughly geodesic pattern across the surface, signaling "this can open." Players see a Capbage and immediately read it as enterable, the way a tree-hollow or a door reads as enterable. The cavity's interior pale-green color contrasts with the deep green of the outer leaves, increasing readability.

**Form (open state):** A large dense head of overlapping concentric leaf layers, roughly the size of a small closet, on a short thick stem rising from tended substrate. Cross-section visible from above: outer leaves deep green with prominent cream-colored veins, layered in 4-5 concentric wrappings around the cavity, each layer slightly smaller and lighter in color. The innermost leaves curve inward to form the cavity wall, paler green where less light reaches. At the apex of the cavity, visible through the parted topmost leaves, the central apical meristem reads as a small tight bud-like structure. Each leaf is clearly distinct from its neighbors, with leaf-edges readable as ridges that will fold inward when the plant seals.

**Form (sealed state):** Same plant with the leaves folded inward via pulvini at the base of each leaf. The result is a tight near-spherical head, but the surface is NOT a smooth seamless dome — individual leaf-overlap remains visible as fine textural seam-lines tracing leaf boundaries in a roughly geodesic pattern. Deep green color uniform across the surface, cream-colored ribs visible as paler streaks along the seams. From the seam-lines, soft internal luminescence leaks faintly outward — the trapped cavity light filtering through imperfect leaf overlaps. Visible tension in the closed leaves: the sense that they could spring open in seconds.

**States:**
- *Wild Capbage (open):* smaller head, cavity visible but tighter, fewer outer leaves. Slow seal time (2-3 seconds) when triggered, opens prematurely sometimes.
- *Wild Capbage (sealed):* small dense ball, still readable as Capbage but compact.
- *Tended Capbage (open):* larger head with full leaf-layer count, cavity clearly large enough for two characters in rare specimens. Fast seal time (1-2 seconds), reads environment reliably.
- *Tended Capbage (sealed):* full-sized sealed head, internal luminescence brighter at the seams. Holds the seal as long as threats remain.

**Tending interaction:** Peris approaches an open Capbage and runs her hands along the outer leaves, working from the base upward. As she tends, the leaves visibly thicken, additional inner leaf-layers grow inward, and the cavity becomes more clearly defined. She also touches the substrate around the stem to support the root system. Tending takes 6-8 seconds. The visible response across multiple shelter cycles is the head growing larger and the cavity becoming more clearly defined; in dialogue Peris calls these "my heads."

**Hurt / death:** Burning kills Capbage instantly — Myke's flame on a Capbage causes the leaves to crumple and char, the cavity collapsing inward. Candid colonization smothers them over days; a Capbage under Candid attack shows white fungal mat creeping across the outer leaves, the affected leaves losing their green color. Heavy siderophore traffic through the area degrades the plant slowly without killing it. Neglect doesn't kill them outright but they fall back to wild state. On full death, the head splits open along the seam lines, the leaves drooping outward in a brown-grey wilt, the cavity exposed but no longer functional shelter.

*Biological inspiration:* Two real plants combined. The head morphology is Brassicaceae cabbage (*Brassica oleracea var. capitata*), whose dense overlapping leaves wrap around a central apical meristem in concentric layers — real cabbage heads when opened show this exact cavity-and-wrapping structure. The mutualist-shelter behavior models domatia, the real botanical term for specialized shelter structures plants grow to house mutualist organisms (acacia thorn domatia for ants, leaf-vein domatia for mites, *Cecropia* hollow stems for ant colonies). The Capbage is a chimera: a cabbage form whose central cavity functions as a domatium for sheltering organisms in its hollow. The folding mechanism is nyctinastic and thigmonastic plant movement, achieved through pulvini at the base of leaves — the same mechanism *Mimosa pudica* uses for rapid leaf-folding. Real nyctinastic plants when fully closed retain visible leaf-overlap textures rather than forming seamless surfaces; the seam-lines on the sealed Capbage reflect this. The species was originally called Doma; the rename to Capbage shifted the form from "bulbous flower" to "self-sealing leaf head."

#### Gasafoetida

**Tier:** Mid frequency in damp Zone 2 corridors. Detail moderate, but the scaled cone-cluster needs to read clearly as serotinous (fire-reactive).

**Silhouette priority:** Tall umbellifer stalk crowned with a flat-topped cluster of woody scaled pod-cones, with visible amber resin weeping at the lower stalk and faint heat-haze around the cones. The "stalk-with-pinecones-on-top" silhouette is the read.

**Affordance signal:** Two visible signals tell the player two different things. (1) The **gas-pod cluster** at the top reads as harvestable held-tools — the pods are clearly individual units, woody and pickable, sized to be carried in a hand. Players see the cluster and read "I can take one of those." (2) The **amber resin** weeping from a wound-point on the lower stalk visibly glistens and oozes, signaling chemical activity — the player learns to read this as "this plant has reactive chemistry." Both signals together communicate: harvestable tool that is also a fire hazard. The faint heat-haze above the cones reinforces the volatile-compounds warning.

**Form:** A chimeric plant fusing two real-biology forms. Lower body is an umbellifer-style central stalk: tall thick green stem (1-1.5 meters) with finely divided fern-like compound leaves emerging from the lower portions, thickest at the base. From a wound or tap-point on the lower stalk, viscous amber-gold oleo-gum-resin weeps visibly, glistening and oily. Upper portion terminates in a flat-topped umbel-shaped cluster bearing 4-7 woody serotinous pod-cones — ovoid pod-cones with overlapping woody scales like small pinecones, each cone roughly the size of a fist. Cones are sealed at the apex with glossy resin patches that catch the light, the resin clearly fresh and viscous. Around the cones, faint heat-haze rises into the air. Cone scales are pale tan-brown, resin patches gold-amber.

**States:**
- *Wild Gasafoetida:* shorter stalk, fewer cones (2-3) in the cluster, resin at the wound-point thin and slow. Harvested pods are dim and slow-acting.
- *Tended Gasafoetida:* full stalk height, full cluster (5-7 cones), resin flowing freely at the wound-point. Harvested pods are bright and potent.
- *Harvested:* a missing cone in the cluster signals a recent harvest. The remaining cones at the top-cluster are visible. The plant regrows the harvested cone over multiple shelter cycles.
- *Held pod:* once harvested, a pod is a held item. The pod is roughly fist-sized, visibly resin-sealed at one end, and begins emitting visible sulfurous gas (pale yellow-grey haze) when the seal is broken or when carried close to body heat. The gas haze surrounds whoever carries the pod, a visible repellent radius.
- *Spent pod:* after the gas runs out, the pod is dry, the resin seal broken and inert, the surface dull. Spent pods can be discarded; they don't do anything.
- *Combusted cluster:* after fire-ignition, the cluster has no cones. Charred patches on the stalk apex where cones used to sit. Regrows over multiple shelter cycles.

**Tending interaction:** Peris approaches the lower stalk and works at the soil around the base, then runs her hands up the stalk to the resin wound-point. She tends the wound itself — applying soft pressure, encouraging the resin flow. As she tends, the resin flows more freely and the cone-cluster at the top visibly grows additional cones. Tending takes 7-9 seconds.

**Hurt / death:** Fire is the major hazard. Any flame source within range ignites the cones in sequence — the serotinous burst launches 3-5 flaming pods from random points in the cluster, each travelling on a parabolic arc with bouncing physics. After ignition, the cluster is empty and the stalk's apex is charred. The stalk itself usually survives even after a full cluster ignition. Repeated burning kills the stalk eventually. Cutting the stalk directly kills the plant immediately. On full death, the stalk slumps and the wound at the lower stalk dries up, the resin crystallizing and the haze ceasing.

*Biological inspiration:* Two real plants explicitly fused. The lower stalk is *Ferula asafoetida* (real "devil's dung" plant from the Apiaceae / umbellifer family), whose taproot when cut releases the oleo-gum-resin containing organosulfur compounds — methyl propenyl disulfide and others — that make it famously repellent to many animals. Real *Ferula* plants are tall umbellifers with finely divided compound leaves and characteristic flat-topped umbel inflorescences; the species' lower body preserves this morphology. The upper pod-cluster is serotinous-conifer biology: lodgepole pine (*Pinus contorta*), jack pine (*Pinus banksiana*), and certain sequoias hold their cones shut with resin that only releases under fire-temperature heat, ejecting seeds ballistically into the post-burn landscape. The Gasafoetida's chimeric form encodes both real biologies simultaneously: chemical defense from the umbellifer's resin chemistry at baseline, ballistic fire-dispersal from the serotinous cones at the head when ignited. The species was originally called Snapbloom and the fire-reaction was described as "popcorn"; the rename and reframing tied the biology to actual fire ecology and asafoetida's sulfur chemistry.

#### Climbvine

**Tier:** Common in inclined-surface areas. Encountered constantly throughout the game wherever there are slopes. Detail moderate at distance, higher at close range where the player will harvest.

**Silhouette priority:** Long rope-like vine with visible nodes carrying small dark adventitious-root clusters, growing across an inclined surface. The "rope with grip-points" silhouette is the read.

**Affordance signal:** The adventitious-root clusters at each node are the affordance signal — small dense bundles of dark hair-like rootlets, splayed outward to brace against the substrate. Players read the rootlets as "this vine grips," teaching that Climbvine works on slopes specifically. The fibrous rope-like body texture between nodes reinforces the signal: this is climbable. At a cut end, a fibrous core is visible — bundles of long parallel fibers, ready to bear weight. Naturally-growing Climbvine reads weathered and old at the rootlet clusters; player-planted Climbvine reads fresh and pale at the cut end and at the recently-anchored rootlets.

**Form:** A long rope-like vine, several meters in length, growing across an inclined rock or substrate surface. Body composed of smooth cylindrical inter-node sections punctuated regularly by visible nodes where adventitious-root clusters emerge. Inter-node sections are smooth and rope-like with fibrous bark texture, mottled brown-grey-green. Adventitious-root clusters at each node: small dense bundles of dark hair-like rootlets splayed outward, gripping the substrate. Older sections are weathered and integrated with the surface; newer growth at the ends reads fresh and pale, with the adventitious roots at the newest nodes still pale and fine before darkening with age.

**States:**
- *Naturally-growing Climbvine (level geometry):* old, weathered, integrated with the surface it grew on. The rootlets at each node are dark and fully merged with the substrate. Reads as world-permanent. Cannot be harvested for vines.
- *Tended Climbvine (player resource):* younger, fresh-looking, with the rootlets still pale at the most recent nodes. Produces one harvestable vine per rest cycle.
- *Harvested vine (held item):* a section of vine cut from a tended plant, carried by a character in a hand-slot. The cut ends show the fibrous core clearly, paler than the bark. Bouncy and rope-like in motion. Up to 2 vines per character.
- *Dropped vine (deployed):* an active vine in level geometry, hanging across surfaces, climbable up and down. Visibly fresher than naturally-growing Climbvine, distinctly placed.
- *Reverted Climbvine:* after Peris dies and the runeback resets her flora, player-planted Climbvines disappear. The previously-occupied surfaces are bare again.

**Tending interaction:** Peris kneels beside a slope-growing Climbvine and works at one specific node, encouraging the rootlet cluster there and the inter-node section above it to thicken. As she tends, the next vine to harvest visibly readies — its fibers thicken, the section becomes more prominently rope-like. Tending takes 6-8 seconds and produces one harvestable section per rest cycle.

**Hurt / death:** Tended Climbvines can be lost to Candid colonization (rare, but it happens in late zones). Naturally-growing Climbvines are world-state and don't die. Player-planted Climbvines revert on Peris-death runeback. A dying Climbvine shows the rootlets pulling away from the substrate, the inter-node sections drying out and thinning. On full death, the vine drops off the surface entirely and lies on the ground in a fibrous brown rope, no longer climbable.

*Biological inspiration:* English ivy (*Hedera helix*) and other root-climbers in real botany, which grip vertical and inclined surfaces using adventitious roots — small fibrous root-clusters that emerge from nodes along the stem and physically anchor the climbing stem to the substrate. *Hedera*'s adventitious roots are the canonical real-world example of this gripping mechanism. The structural fiber bundle in cross-section references *Vitis* (grape vines), whose vine cores have thick parallel fiber arrays similar to those used in real cordage. The slope-constraint behavior — Climbvine grows only on inclined surfaces because adventitious roots need a substrate to brace against — is biologically accurate to root-climber physiology, contrasted against epiphytic and parasitic vines that climb without ground-anchor. The "Sloperope" worker-vocabulary alternate name (used by worker-class characters with field experience) is the worker register's recognition of the slope-constraint as the plant's defining feature.

#### Mother Flure

**Tier:** Set-piece. One specimen in the entire game, encountered once. Full boss-tier detail allowed.

**Silhouette priority:** A massive trumpet-bloom organism the size of a small building, set in a contained chamber, with smaller offshoots emerging through cracks in the institutional walls. The "giant collapsed flower with children pushing through the walls" is the read.

**Affordance signal:** The mother is dead-looking until Peris tends her. The visible offshoots growing through the cracks tell the player "this organism is not what it appears to be" — the collapsed central body and the live offshoots together signal that the root system is alive and connected. The implication that all Flure-class plants in the world might be ramets of this one organism is encoded in the visible network: cracks, root-fingers, offshoots that look like miniature versions of normal Flures the player has encountered throughout the game. The chamber's institutional walls are visibly compromised — cracks, displaced floor tiles — telling the player "the institution failed to contain this."

**Form:** A massive Flure-class organism the size of a small building, set in a contained chamber with institutional walls. Visible structure is not a single body but a clonal network: ONE central trumpet-bloom (collapsed and grey but still architecturally legible at building scale, the bloom's overall shape preserved even in death) PLUS multiple smaller offshoots emerging through cracks in the institutional containment walls. Offshoots are smaller Flure trumpets, genetically identical to the central body, popping up through floor cracks, growing along the chamber's walls where masonry has failed, extending outside the chamber in directions the player cannot see. Central body is collapsed grey-brown with faint traces of the rust-red the species had in life still visible in the deepest crevices of the bloom. Smaller offshoots are alive, in active rust-red and amber. Chamber's institutional architecture is visibly compromised by root activity: cracks in walls, displaced floor tiles, root-fingers visible where they have grown around containment infrastructure.

**States:**
- *Pre-bloom (default state on entry):* central body is collapsed and grey, smaller offshoots are alive but quiet, root-fingers visible through cracks, no atmospheric haze. The chamber feels dormant.
- *Tending state:* Peris tends the central body. The offshoots throughout the chamber slowly brighten in cascading sequence — a Flure across the room responds to Peris's tending of the central body, then another, then another. The connectedness of the root system becomes visible.
- *Bloom moment (the set-piece climax):* the central body responds to care for the first time in decades. Petals unfurl, internal structures light, smaller offshoots throughout the chamber illuminate in cascading sequence. The chamber's light shifts from diffuse to radiant. Phytosiderophore haze rises from every offshoot simultaneously, the air in the chamber filling with reddish dust. This is the canonical moment — care-work as infrastructure with mechanical consequence.
- *Post-bloom:* the chamber settles into an active, radiant state. The central body remains alive and bloomed, the offshoots continue to glow, the haze hangs in the air at low intensity. The chamber is now a quiet sanctuary — Peris has restored what the institution wrote off.

**Tending interaction:** Singular event in the game. Peris approaches the mother and tends her with a level of confidence she has not shown with any flora yet. The tending animation runs longer than other flora (12-15 seconds) and the visible response is the cascading bloom across all offshoots simultaneously rather than just the local plant. The bloom happens because of Peris, not because the party opened the containment mechanism — the mechanism was the institution's containment attempt, which was ultimately irrelevant. The mother survived via her root system, which the institution could not fully contain.

**Hurt / death:** The mother cannot be hurt by player action or enemy action in normal play. She is a set-piece that has already survived her assault. If the player skips tending her, she remains in the pre-bloom dormant state for the rest of the game. There is no death state in canonical play.

*Biological inspiration:* Pando, the clonal aspen colony in Utah's Fishlake National Forest. Pando is a single genetic individual covering ~106 acres with ~47,000 stems, all sharing one root system, estimated 14,000 to 80,000 years old. Pando's defining biological property is that it is unkillable above-ground: aboveground stems can be cut indefinitely, and the root mass continues to send up new ones from anywhere along its extent. The Mother Flure's containment-and-root-survival arc IS Pando's biology rendered as institutional confrontation: the institution can wall off the visible plant indefinitely, but the root system extends past whatever the institution can build, and the offshoots emerging through the chamber's cracks demonstrate that the network is structurally larger than the containment. The trumpet-bloom architecture at scale draws on *Rafflesia* (giant parasitic flowers, the largest individual flowers in real biology) and *Amorphophallus titanum* (corpse flower, which produces massive trumpet-shaped inflorescences). The implication that all Flure-class plants in the world are ramets of one organism is biologically defensible: real clonal plant networks (Pando, certain *Posidonia* seagrass beds, the Humongous Fungus *Armillaria solidipes*) routinely cover scales much larger than naive observers would expect.

#### Network visualization (multi-species scene reference)

A corridor of the NVU's Plumbing Power Project region, several flora species visible at once: a Seefern lantern in the foreground casting teal light, a Scarpet carpet beneath the flora, a Flure on a slender stem catching the teal light along its bronze petals, a Capbage dense and sealed in the corridor's tight alcove, faint connecting threads running between the plants visible as pale luminescent traces underneath the substrate (the network communication property made visible at this one moment). One human-scale figure (Peris, an amber-glowing pericyte with pale skin and dark hair) tending the Seefern in the foreground. Voxel-painterly style, restricted palette, near-black background, diorama-on-dark composition. Mood: a small ecosystem tended by one person, the network visible because it has been cared for.

### 8.13 Implementation notes

**Sensory presentation.** The game's warm-view rendering for Peris's perception should include scent indicators (atmospheric tint adjustments, subtle particulate effects around strong-scent flora) and textural cues (camera proximity producing different visual emphasis depending on species). When Peris kneels near a plant, the player sees what she is sensing as composite environmental rendering rather than as a data readout.

**State transitions.** Flora state changes are events in the engine (per `game_architecture.md` on event sourcing). A stress event fires when conditions change; a dying event fires when stress is sustained; a death event fires when dying completes. Each event produces the appropriate sensory signature change.

**Vocabulary substitution in dialogue.** When Peris is the speaking character or when her perception is the active frame, flora should be referred to by her worker vocabulary (the vines, the flures, the quiet-blooms, her heads, the spread). When Aster is the speaking character or when the data overlay is active, flora should be referred to by institutional names. Other party members inherit the vocabulary of whoever taught them.

**Ambient flora density.** A given corridor's ambient flora density (moss, wild flowers, vine skeletons) is a readable indicator of that corridor's ecological health. Healthy corridors have visible ambient growth. Degraded corridors have sparse or skeletal growth. Dead Zones have none.

**Forget-me-nots.** Should be present in every shelter the player spends meaningful time in, quietly. The optional-richness reward is described in 8.5.

(Open design questions for this system are collected in section 17.)

## 9. Tutorial sequences

The simulation tutorials are how the player meets Aster and Peris and learns their respective registers before the game's central conflict displaces them. Each tutorial uses workspace-level free-exploration to establish character through object detail. The dedicated source is `simulation_tutorial_expansions__3_.md`; this section captures GDD-level summaries.

The two tutorials are designed in parallel. Aster's establishes institutional-evaluative register (what something is worth, what rank it conveys). Peris's establishes felt-experience register (what it feels like, what vibe it has). Neither character is framed as superior; the tutorials establish the baseline registers, and the game complicates both.

### 9.1 Aster's workspace tutorial

**Position.** Game opening. Aster is at his workstation in the simulation, finishing routine work. The tutorial precedes Tag Day and the institutional events that displace him from the simulation.

**Structure.** The existing GDD tutorial covers movement, interaction, ATP via the drink machine, and the Tag Day notification chime. The free-exploration beat is inserted between the drink-machine interaction and the Tag Day chime, gated by the workspace's hallway exit. The player is free to move around Aster's desk, shelf, and display area; the beat ends when the player attempts to walk through the hallway. Ron reappears in the hallway at that moment, friendly-blocking the path while the Tag Day chime fires. The player does not know the hallway is the gate. They experience it as: trying to leave, getting polite institutional interception, proceeding to Tag Day. The routine intercepts the attempt to move through the day. Nobody decides when Tag Day happens. Ron is the friendly face of that fact.

**The interactables.** The workspace contains four interactables in addition to the drink machine.

- **The glass bead game.** A reference to Hesse's *Das Glasperlenspiel*, the novel about an order of intellectuals who refine an abstract symbolic game while the world outside collapses. Aster engages the bead game as a personal pleasure, not as a metric activity. This is the one part of his life he does not measure. On second play, the player who knows Hesse hears the critique: the institution Hesse warned about is the institution Aster works for, and Aster's pure aesthetic engagement with the bead game is the institution's success at producing exactly the kind of intellectual retreat the novel describes.
- **The paintings wall.** Two collections: *Macabre Teal* (paintings whose underlying structure is McCabe-Thiele distillation diagrams in cool palette) and *Hunter and Ash* (paintings whose underlying structure is Hunter-Nash ternary phase diagrams in earth tones). Aster owns positions in both collections. He talks about them through floor-price movement, burn events, and the timing of scarcity manufacture. He does not name the artists. He does not register that the underlying diagrams are barrier-fault prediction documents. The collection names contain the *Breadth of Life* tutorial seed: Aster mentions the original physical *Breadth of Life* sculpture (made from the engineering diagrams before they were destroyed in a digitization-and-burn cycle) and casually mentions a "spectacle" the institution staged around it to drive liquidity on the collection: a waterfall installation, a rainbow effect, the kind of marketing event that runs for a quarter or two and shows up in the floor-price chart. He dismisses the question because the digital position is the asset and the physical "event" was just liquidity theater.
- **The awards display.** A best-in-category award Aster received for his predictive work. He describes it as a narrowed-to-produce-a-ranking outcome. The award is genuine and Aster is proud of it; the second-play reading is that the award is institutional capture of his class's predictive labor, the institution rewarding the productivity it then declines to act on.
- **The J-stores (journal storage devices).** Aster's published papers. The titles read as small variants on a single underlying paper: "A prospective model for predicting barrier faults," "Modeling for fault prediction: a potentially useful system for barrier improvement," "The critical importance of barrier integrity for safety." Aster experiences this as refining the approach. The pattern mirrors academic publish-or-perish: the institution measures publication volume, not unique contribution. Aster has been correctly predicting barrier faults for years; the publications are the paper trail proving he has been right and nobody has acted on any of it. The real-world analog (not stated in-game) is the US Chemical Safety and Hazard Investigation Board, whose root-cause analyses on barrier-and-containment failures are routinely correct, routinely ignored, and whose institutional dynamic is the same one Aster is embedded in.

**Environmental decor (non-interactable).** Empty drink mugs accumulated on top of the J-store shelf (the player infers the reward history without Aster narrating it), ambient desk items, spine-branding on the J-store devices.

**Hidden reward seed (Breadth of Life).** Aster's painting line plants the existence of the physical sculpture *Breadth of Life* and the rumor of the "liquidity-event waterfall" the institution staged around it. The reward is layered across three depths.

**Outer layer: the hidden waterfall (early Act 2, The Honeycomb Cooperative vicinity).** The sculpture sits behind a hidden waterfall in a secluded chamber. The waterfall produces a real rainbow from its mist, and the sculpture sits at the rainbow's terminus. The rainbow is a literary reference to Vinge's *Rainbows End* (2006). The in-world story of how the sculpture ended up here is unrelated to Vinge's plot: some NFT bozos wanted their listed NFTs to be bought so they could get money with them listed at the higher price, and decided the best way to do that was to livestream (note the pun: livestream / waterfall stream) the statue in the mystical location while the project creator danced around in a silly costume for theatrics. Aster's "liquidity event spectacle" framing is therefore literally accurate: that IS what happened. The high-culture literary reference (Vinge, Hugo Award, civilization-scale knowledge destruction) sitting alongside the low-culture in-world content (NFT bozos pumping their bags via mystical-location livestream with founder doing a silly-costume dance) is the joke. A beat inside the staged livestream lands the same joke from the other direction. A hanger-on tries to talk the sculpture into meaning, "Ah, but did the artist truly intend the sculpture to read as human? Or is it that, by separating the core from the longer protrusions, the artist evokes a notion of movement, of emergence..." and the project's founder, not breaking from the costume dance, cuts him off flat, "Yes. It is supposed to be a human." The gag is the death-of-the-author pose, the claim that intent is unknowable and it is only forms, deflated by the author stating the obvious, the way an over-reading of a painting collapses the instant someone reads the title it was given. It also sharpens the value-manufacture point: the depth is decorative, and the founder will confirm whatever you like, because the reading was never the asset, the pump was. Two paths to the chamber, mirroring the section 2.6 commitment to shadow solutions:

- **Endo's path.** The chamber is reachable by swimming down through the waterfall pool; Endo's swimming kit (per section 3.3) makes the route navigable.
- **Aster + Peris shadow path.** A slope leads into the chamber from outside the waterfall, but the slope is camouflaged by spray, low light, and near-flatness; visually it reads as level ground but has a real gradient. A player who reads geometry carefully and tries to plant Climbvine (Sloperope in worker register) on the surface succeeds; trying to plant it elsewhere fails. The successful planting creates the bridge to the chamber. This is a recognition test: the slope is only legible to a player who is reading the world carefully.

**Middle layer: the sculpture (inside the chamber).** The sculpture is a partially-collapsed papier-mâché form, with the underlying Hunter-Nash and McCabe-Thiele engineering diagrams exposed by the degradation, plus some old schematics interleaved among the diagrams. Recovered diagrams unlock optional shortcuts across Act 1 and Act 2 zones (alternate routes through Plumbing infrastructure, vertical bypass shafts in the Open Files and Watchtower) and grant a persistent power-up. Aster, if present, registers the sculpture but not its significance. The schematics are the seed of the inner layer.

**Inner layer: the hidden map region (gated by an invisible door).** Aster, after the world-map add-on is unlocked, can read one of the sculpture's old schematics as a map of an otherwise-undiscovered region of the world. That region is gated by an invisible door. The door's discovery requires a recognition test that goes beyond the standard melt-targetable-walls visual cue: the door does not highlight when Melt is available the way standard structural weaknesses do. It only reveals it can be melted when the player clicks on it with Melt active, meaning the player has to TRY melt on a wall that gives no visual cue. Alternatively, an enemy charging into the door breaks it via impact damage (the same way standard breakable walls can be opened). Beyond the door, the hidden region contains multiple power-up upgrades.

The character beat is consistent across the layers: the asset position is the digital one; the physical residue is what the institution discarded; the player who recognizes the institutional-debris pattern and reads the diagrams for what they actually are is doing curatorial work the institution declined to do.

### 9.2 Peris's workspace tutorial

**Position.** Game opening, in parallel to Aster's tutorial. Peris is at her session-management space, waiting for her client Monos to connect. The tutorial precedes the institutional events that displace her from her work.

**Structure.** The existing GDD tutorial has Peris's session start with Monos already late and flustered. The expansion introduces a wait period during which Peris declares she will walk around the office before marking the no-show. The player controls her exploration at their own pace. The logbook is the progression gate, positioned across the room from the portal so the player traverses the workspace to reach it. Monos connects at the moment the player opens his file on the logbook.

**Peris's opening line.** "Monos is late! I hate marking no-shows... Maybe I'll take a lap around the room first..." Light exasperation, gentle reluctance, self-directed. Peris is using movement as somatic regulation, delaying the institutional action until she has calmed herself through physical engagement with her space. The walk-around is micro-noncompliance; she uses small delays to buy time for clients she hopes will show up. The player who moves Peris around the workspace is executing Peris's own stated intention.

**The plants.** Peris's workspace is full of plants. Specific plants she has collected over time, each individual, each tended. She speaks to them with gendered pronouns of continued acquaintance. The plant interactions are character-establishing; the flora mechanic in the base game is not a new ability for her but the externally-legible version of what she has always been doing.

Roster (species commitments are design leans; narrative roles are load-bearing):

| ID | Detail | Species |
|----|--------|---------|
| plant_1 | Larger plant, transplanted from hallway, leaning toward light | Pilea peperomioides |
| plant_2 | Smaller plant, leaves curling, Peris uncertain if happy. The stat-bar-mod refusal beat. | Calathea or Maranta |
| plant_3 | Small flowering plant on the desk edge, in bloom, with Floral Spring scent rendered by the add-on | Jasmine |
| plant_4 | Small succulent, "she's such a survivor." Diagnostic mirror plant | Haworthia |
| plant_5 | Medium plant on a wooden stand, from a client trade | Pothos |
| plant_6 | "My oldest," Peris does not touch, in an older worn-glaze pot. Flora-origin backstory | Jade plant |
| plant_7 | Large fern on plant stand. Empathic-care diagnostic counterpart to plant_4 | Boston fern |
| plant_8 | Plant Peris named after a client, "kindest person... fixed things nobody else could figure out." Repairperson foreshadow | Spider plant |
| plant_9 | "When I was a kid... this plant game was so popular." Vintage plant-game reference | Peace lily |

**The Floral Spring add-on (plant_3).** The flowering jasmine renders the Floral Spring scent through Peris's licensed simulation add-on. Peris saved up to license the add-on as her connection to a memory she could no longer materially access. The Floral Spring physical line was discontinued; the simulation add-on is what remained. This tutorial beat establishes Floral Spring as a real biographical artifact for Peris before the player learns at the Paranucleus that the institution discontinued the physical line as deliberate suppression of the security-disabling spray.

**The painting.** A felt-experience-register painting Peris responds to without referencing market value. The contrast with Aster's painting wall: Aster evaluates art through market validation; Peris evaluates art by felt experience.

**The wellness-content feed.** Peris glances at the institutional wellness feed in the corner of her workspace. "They're always pushing these on us. 'Take a breath.' 'You deserve a moment.' I guess they mean well. I just... I really like my clients. That's why I do this." On second play: this line is the tutorial's setup for the entire sanction arc. The institution will later replace Peris's client feed with exactly the content she is here calling "they're always pushing on us," framed as comfort. Peris will resist it precisely because she has already said, here, that she does not need it.

**The pinned strike-two warning.** A Workforce Conduct Review notification is pinned in Peris's interface near the wellness feed. The notification documents two prior session-overrun violations and informs Peris that the next instance of comparable non-compliance will result in mandatory corrective action. Peris keeps it pinned rather than archiving. "I keep this pinned. Helps me remember. Two strikes. I know what that means. But if Monos needs me, I'm staying with Monos. I know what I am. I just don't want to lose them."

On second play, this line reframes the entire sanction arc. The Monos incident is not an accident the institution is reacting to harshly. It is the third instance of a pattern Peris has been warned about twice, and Peris has been making the deliberate choice to continue the pattern with clear knowledge of the consequences. The institution is not being unreasonable; the institution is enforcing exactly what it said it would enforce, against a worker refusing to comply with a policy that asks her to care less than she is going to care. The horror is not that the institution surprises her. The horror is that the institution is functioning exactly as designed.

The pinned warning and the wellness feed are adjacent in Peris's interface because they are two faces of the same institutional relationship. The wellness feed is the institution offering her comfort she does not need; the pinned warning is the institution documenting the behavior that comfort is meant to correct. Together they describe the institution's full position toward Peris: care less, accept our help when you fail to care less, accept our sanction when you continue caring.

**Client session notes (optional).** Peris's logbook can be partially opened without triggering the no-show procedure. Browsing notes from prior sessions reveals: "Monos was doing better last week. He talked about his mom for the first time. It took months for him to get there. I don't want to lose that." The line lands later against the Greenfields Collective scene where Peris meets Marco again; the care she is describing here is what she was building, and the Marco encounter in the Greenfields is that care being rejected by the institution's logic.

**Hidden reward seed (Curecumin).** Peris's plant interaction with the spider plant (plant_8, the plant named after a client called Repairperson) plants the existence of Curecumin, a viable preparation kept in private hands after the institutional pivot away from natural compounds. The reward is found later in a Greenfields Collective home; the player who heard the personal anecdote in Peris's tutorial and recognizes the home's ownership pattern claims it. Curecumin grants a persistent HP-boost effect mapping loosely onto curcumin's real anti-inflammatory and antioxidant mechanisms. Biological grounding: real curcumin has been studied for amyloid-binding affinity and NF-κB modulation; bioavailability is the major real-world problem; the in-game version assumes a delivery formulation that solves the bioavailability problem.

**The session attack context.** Monos (Marco) is in this session because he spoofed someone else's Psyknapse to access simulo-care. Workers like Marco normally cannot reach simulo-care (per section 5.6 on the metrics gate); the system is calibrated for the qualifying-worker population it expects. The attack on the session is the institution's response to Marco's worker-class break into a system that does not normally host worker-class users. This context is not delivered in the tutorial itself (Peris does not know, and the player does not yet know either) but is recoverable on later play once Marco's character is established (per section 3.7) and the simulo-care gate is understood. Specific session-dialogue lines are not yet committed.

### 9.3 What the tutorial pair establishes

Both tutorials work in parallel. Aster's objects show institutional value absorbed into personal taste; Peris's objects show felt experience retained against institutional pressure. Two ways of being a worker in this civilization, both established via object detail, both about to be tested by Tag Day for Aster and the session attack for Peris.

Specific contrasts. Aster evaluates art through market validation (floor price, burn events, timing relative to scarcity manufacture); Peris evaluates art by felt experience. Aster's shelf accumulates past rewards (empty mugs); Peris's plants project into the future (continued tending). Both tutorials introduce the institutional layer through different surfaces: Aster's through a colleague (Ron), Peris's through her work tool (the wellness feed and the pinned warning).

On second play, every object in both beats is set up for a second-pass reading. The glass bead game (Hesse's critique of intellectual retreat), the paintings (Aster's chemical-engineering aesthetic captured through a market that manufactures scarcity by destruction), the award (narrowed-to-produce-a-ranking), the empty mugs (cumulative compliance), the plants (relational tending), Peris's painting (felt-experience frame), the wellness feed (foreshadowing the sanction sedation), the session notes (what Peris loses at the Greenfields) all reward the player who returns. On first play, they are objects in rooms that belong to characters who take them seriously.

What the tutorial expansions deliberately do not do: foreground the critique (the critique is available to players who bring their own frame; the characters own their pride and tenderness without being ironized by the script), delay the existing tutorials significantly (each beat is 30-90 seconds if the player engages fully; less if they move through), introduce new mechanics (the existing tutorials teach movement, interaction, ATP, abilities, and the day/night cycle; the expansions use only mechanics already in place), or repeat existing content (the drink-machine interaction, Tag Day, the Monos session, and the sanction sequence are all unchanged).

### 9.4 The tutorial-seed reward pattern

Both hidden rewards (Curecumin and the *Breadth of Life* sculpture) share a structure: the tutorial plants knowledge that has no apparent reward attached, and the reward is found later in a location chosen for thematic resonance with the tutorial line. The Curecumin sits in a personal home and rewards the player who heard a personal anecdote. The sculpture sits behind a hidden waterfall the institution dismissed as a marketing spectacle, and rewards the player who heard a market-investor anecdote and decoded the rumor of the "liquidity event" the institution staged. The two rewards together establish a pattern the rest of the game can extend: tutorial interactions are not rewarded mechanically in the tutorial, but they may seed rewards in places where they thematically belong. Players who treat the tutorial as character-revelation, not as loot, are rewarded for that orientation later.

(Open design questions for both tutorials are collected in section 17.)

### 9.5 The opening runs as one descent: the EMP-and-multi-select escape, then the bridge drop to the fork and Endo's junction

This is the first tutorial sequence after the simulation, and it teaches the EMP and the multi-select control while playing as a single continuous fall from the elevator down to Endo's junction. The ordering is easy to misread, so it is fixed here.

The party wakes trapped in the elevator. Aster triggers his EMP (origin in section 3.1) and the pulse kills the elevator door along with the escort units. The multi-select tutorial happens here, at the dead door: the player learns to select both characters, set both their paths to the door, and toggle running, then resume, getting both of them through together before the pulse wears off. The nudges name whichever condition is missing rather than giving one generic prompt, so only-one-selected, paths-not-set-to-the-door, and running-not-toggled each get their own line.

They come out through the dead corridor, where the device-beat conversation and the decommissioned-section beats play, onto the walkway beyond, an iron bridge over a deeper dark. Crossing it they see the enemies and the bodies down in the gloom, and they pass directly above the point where a fork branches off below them. At the far end the span gives way and drops them to that sub-level.

They cannot climb back up to the bridge, which is the two climb beats. They turn to face the fork they just saw from above: one corridor holds the same enemies they watched while crossing, the other is a corroded iron-hazard route, and the hazards are the way through. The enemy corridor is fatal by design, with nowhere to run, no shelter, the swarm too dense to push past and now giving chase, and choosing it resets the run to just after the drop. They take the hazards, pass the foot of the elevator shaft they started in, and continue into Endo's junction.

There is one EMP across the whole sequence, not two. The multi-select run-through is the elevator escape itself, not a later beat at a second door.

## 10. The cure

Nine components, each addressing a different axis of the NVU's failure. Each component maps to a real promising treatment or diagnostic method in active Alzheimer's research, renamed for the fiction. Finding all of them requires deep exploration of the most dangerous areas. Each component is hidden in a location that thematically matches its function.

The cure is not a single item. It is a device assembled from components scattered across the map. The components are not the relationship; they are the relationship's preconditions, made into chemistry. The cure creator studied relationship therapy during her philanthropic phase; the components reflect her actual framework for understanding human connection. The cure is her understanding of relationships, encoded into biochemistry, scattered across her own mind. The mapping is invisible architecture, never named in-game and never dropped on the player as a framework lecture.

### 10.1 Discovery principle

Nobody on the map, including the party, knows a cure exists when they begin finding components. The components are encountered as gifts, as salvage, as curiosities. Their function as cure pieces is only revealed later when Aster cross-references retrievals against schematics found in Zone 2 and Zone 3.

This principle applies to every component found before the schematics surface: the Chaperone Lattice is a gift with blue flowers, the Inflammashunt is a piece of working tech, the Acid Core is something useful in a clogged waste facility. Neither is understood as part of a cure until the cure's existence is established. The schematics surface mid-game and reframe what the player has been carrying. From that point forward, the player understands the search; before that point, the player is just exploring.

### 10.2 Danger zone safety from external survival mechanics

Once the player enters a component retrieval zone (the Inflammashunt corridor, the Membrane Sealant bilayer, and similar puzzle environments), the day/night cycle does not apply, nighttime threats do not spawn, and external threats do not enter the space. Food, water, and basic restoratives are scattered throughout the puzzle area, enough to sustain the party during the solve. The player can leave a puzzle area and return later without losing progress (switch states, route plans, and section completion persist).

This is a deliberate design choice: the survival loop creates the urgency to reach the danger zone and the cost of attempting it, but once the player commits to the puzzle, the game respects their attention by removing the clock. The player should be thinking about switch timing and cable routing, not about whether dusk is approaching.

### 10.3 The components (roster)

Components are listed in approximate retrieval order along the main path, though the player can sequence them according to which danger zones they enter and in what order.

| # | Component (real basis) | In-game name | Act | Location | Status |
|---|---|---|---|---|---|
| 1 | Iron Redistribution Chaperone | Chaperone Lattice | Act 1 | Required corridor before Oli joins, behind a terminal Aster activates (area TBD) | Designed |
| 2 | Resolution Catalyst (pro-resolving mediator amplifier) | Inflammashunt | Act 1 | Danger zone branching off the Ancourage, end of Act 1, shelter 10 | Full puzzle spec written |
| 3 | Sheath Repair Template (remyelination promoter) | Pattern Wrap | Act 2 | Sealed research corridor in Zone 2 (The Honeycomb Cooperative, shelters 11-12) | Spec written; post-retrieval dialogue WIP |
| 4 | Channel Polarizer (AQP4 polarity restorer) | Flow Aligner | Act 2 | Water junction deep in Zone 2 (area TBD) | Spec written; synthesis beat dialogue **WIP** |
| 5 | Drainage Amplifier (meningeal lymphatic enhancer) | Outflow Expander | Act 2 | Drainage infrastructure near outermost edge of map (area TBD) | Spec written; floor counts/dimensions TBD |
| 6 | Waste Processing Catalyst (lysosomal function enhancer) | Acid Core | Act 3 | Old waste processing facility in Zone 3 (area TBD) | Spec written; backstory pairings dialogue TBD |
| 7 | Frequency-40 Stimulation Array (gamma entrainment device) | The Resonator | Act 3 | Harmonia (shelters 21-22), gamma-entrainment infrastructure | Spec written; chamber progression TBD |
| 8 | Lipid Stabilizer (ferroptosis inhibitor) | Membrane Sealant | Act 3 | Endgame Zone 3 corroding bilayer corridor, second-to-last (area TBD) | Spec written; workshop pass on full puzzle next |
| 9 | Circadian Regulator / Clearance Cycle Regulator (sleep-dependent glymphatic clearance) | Rest Cycle Module | Act 3 | Hidden shelter above the Root Archive (shelters 25-30+), last component | Designed; scene written; full puzzle TBD |

Each component's real basis cites a treatment or diagnostic method in active research, primarily in Alzheimer's disease but also in adjacent neurodegeneration work. The cure's mechanism is plausibly grounded; the scale at which it operates (cellular civilization, full disease reversal) is the fiction.

### 10.4 Per-component specs

#### 10.4.1 Chaperone Lattice (Iron Redistribution Chaperone)

Real basis: Next-generation BBB-permeable iron chaperones that bind excess labile iron and redistribute it to storage proteins, preventing Fenton reaction-driven oxidative damage and ferroptosis without depleting essential iron reserves.

This is the first component, found early in the game in a required corridor (not an optional danger zone). The discovery is not framed as a cure component. Aster hacks a terminal and the path opens into a small alcove. The Chaperone Lattice sits in a bed of forget-me-nots, small blue flowers improbably alive in the decaying infrastructure. The lattice appears to be sustaining them: a faint warmth radiates from it, and the flowers have grown through and around the lattice structure. Aster picks it up and takes it because it reminds him of Peris, and he wants to give it to her.

When he gives it to Peris, she tends the flowers. They become hers. At every shelter where Peris rests afterward, a small cluster of blue flowers appears and persists. The flowers stay at the shelter permanently after the party leaves, a living mark. They show up in the background of shelter scenes for the rest of the game.

(The flowers serve a secondary gameplay function: they mark shelters the party has previously rested at. The player can see at a glance which shelters they've visited. This is never explained or tutorialized. The player notices that shelters with blue flowers are familiar and shelters without them are new. Forget-me-nots marking the places you've been, so you don't forget them.)

The player carries this component for most of the game without knowing what it is. It appears in the collection as an unidentified object: "A small lattice structure with blue flowers. A gift for Peris." Only when schematics surface later does the function become clear. The gift was the first piece of the cure.

**Design note on scent.** Real forget-me-nots (Myosotis) have almost no scent. This is intentional. The "scent of the flowers" that characters reference throughout the game is not the flowers. It is Aster, who spent his life in the simulation and does not smell like the iron-and-corrosion register everyone else carries. Peris has been tending flowers that carry a trace of him at every shelter. She thinks it's the flowers. It's not. The flowers are the medium. The people are the message. Nobody in the game ever names this.

**Design note.** The Chaperone Lattice's discovery is the first time Aster reaches toward Peris specifically because of who she is, not because of who he needs her to be. The component sits in flowers because Aster, who reads people through pattern, has registered something about Peris that flowers express.

**Real-world institutional mapping.** The Iron Redistribution Chaperone's relational-practice register (the practice of building love maps per section 1.1, distributing resources where they are needed against the institutional pattern of letting them pool where the institution wants them to pool) maps to coordinated regional development institutions that have addressed depopulation cascades in real-world history. Two candidate precedents combine to make the full mapping. The Tennessee Valley Authority (1933 to present) used federal-corporate structure to coordinate infrastructure across seven states in a depopulating region, embodying the coordinated-state-led-planning register. Mondragon (Basque Spain, 1956 to present) used a federation of worker-owned cooperatives to coordinate capital, training, and production across firms, embodying the cooperative-ownership register. The Chaperone's full mapping is (TVA + Mondragon), with the molecular structure embodying both pieces: a chaperone that does the planning the individual iron molecules cannot do, in a federation architecture that distributes capacity rather than concentrating it. The institutional architecture is what makes either precedent work in the real world (not just the goal of redistribution but the federation or corporate structure that provides the planning function individual actors could not perform alone), and the Iron Redistribution Chaperone biologically performs the same architectural role. The mapping connects to the section 4.10 analysis of outer-region depopulation: the cellular civilization is depopulating for the same reasons real-world rural regions depopulate, and the cure component for iron redistribution is the externalized form of the institutional practices that, sustained, would have prevented the cascade.

#### 10.4.2 Inflammashunt (Resolution Catalyst)

Real basis: Specialized pro-resolving mediators (SPMs), including resolvins, lipoxins, maresins, and protectins, which actively terminate the inflammatory response and promote tissue repair. Chronic neuroinflammation in AD is characterized not by excessive inflammation but by failure of the resolution phase. The immune system attacks but never receives the signal to stop, clean up, and repair. The problem isn't too much fire; it's fire that never goes out.

Located in a danger zone branching off the Ancourage at the end of Act 1, shelter 10. The corridor beyond the junction leads into Myke's old maintenance routes. Myke's road knowledge reveals the danger zone junction; he knows these corridors and doesn't want to go back. His reason for entering is practical, not heroic: he knows there's salvageable equipment in his old corridors, and working tech is rare outside the simulation.

**Puzzle concept.** Three-route information gathering with internal contradictions, environmental interactables with state changes, route-info-as-efficiency for hold timers, a recovery mechanic with its own sub-puzzle (the hostile root herding), and a chain of wrong approaches that each teach one rule. The puzzle tests whether the player can synthesize conflicting information and resist the aggressive instinct. Every character's recommended approach is violent. The correct approach is patience, water, and care.

Full mechanical spec, room layout, dialogue beats, wrong-approach lessons, and the recovery sub-puzzle live in `inflammashunt_puzzle.md`. The puzzle is the canonical example of TRAWF's indirect-solution philosophy at full elaboration.

**Design note.** The correct approach treats the system as one that wants to be helped if you can read what it needs. The wrong approaches are pedagogical and recoverable.

#### 10.4.3 Pattern Wrap (Sheath Repair Template)

Real basis: Oligodendrocyte precursor cell (OPC) recruitment and differentiation therapies that promote remyelination of damaged axons.

Located in a sealed research corridor in Zone 2 (The Honeycomb Cooperative, shelters 11-12 vicinity). The insulation has been stripped. Bare conduits spark and short-circuit. Signal quality is terrible. But one conduit has been partially rewrapped, not professionally, by something organic-looking that grew around a short section of wire. The Pattern Wrap is attached to the conduit: a small device that's been encouraging new insulation to form around the bare wire. Removing it doesn't destroy the regrown sheath (it persists as visible proof the component works), but it stops new growth.

This is Oli's first major puzzle, set in the infrastructure he once maintained and triaged. Oli's electrical flow layer reveals the sealed area; Aster's terminal hacking opens it. Party composition: Aster, Peris, Myke, Oli (four characters; Oli has just joined). The facility was once a research section dedicated to insulation repair, an authorized effort to solve the problem Oli faced. It was shut down. The work was abandoned. The equipment was left in place.

**The environment.** The danger zone is a sealed research corridor branching off The Honeycomb Cooperative. Powered conduits run behind a wall that shouldn't have power, connected to systems that the maintenance registry says were decommissioned. Inside, the corridor is hostile: bare wiring on every surface, conduits sparking at irregular intervals, collapsed ceiling sections, and the acrid smell of overheated metal. Walking through uninsulated sections damages characters (environmental HP drain, similar to Zone 3 atmospheric damage).

**The core mechanic: temporal overlay and cascading intervention.** Scattered through the facility are four broken Psy-Knapse devices, each frozen at a different point in time. The devices are stuck in playback mode, projecting a moment from their last recording onto the physical space. They are not ghosts or magic. They are data, trapped in hardware that stopped updating: the infrastructure's memory of what happened here, rendered as walkable space.

When the player activates a Psy-Knapse device, the frozen moment overlays onto the current environment. The player sees both layers simultaneously: the decayed present (exposed wiring, collapsed walls, charred insulation) and the past as it was at the moment of recording (lit, maintained, functional). The two layers occupy the same space. Where they agree, geometry is solid. Where they disagree (a door open in the past but sealed in the present, a corridor intact in the past but collapsed now), the player can move through the past's version, walking on floors that no longer exist, passing through doorways that were sealed decades ago.

Only one timeline overlay can be active at a time. The present is always visible underneath. The player toggles between timelines freely once a device has been activated.

The player can interact with objects in the frozen moment: toggle a switch, open a panel, connect a cable, tend a growth. Because each frozen moment is earlier in time than the later ones, changing something in an earlier timeline alters what the later researchers found when they arrived. Toggling a barrier in Timeline 2 might reveal a sub-room that Timeline 3's researcher never found, changing what their overlay shows. Closing a valve in Timeline 1 might mean the flooding that destroyed a workspace in a later timeline never happened. Changes to frozen moments also alter the present: if the player helps a past researcher succeed at something they originally failed at, the present-day environment reflects that success.

The path to the Pattern Wrap does not exist in the present as the player first finds it. It has to be built retroactively by intervening in the right frozen moments.

**The four timelines.**

*Timeline 1 (oldest, nearest the entrance).* A lone researcher, the first person who noticed the insulation was failing. Their workspace is crude, improvised. They were mapping the conduit layout by hand, identifying the worst damage points, starting the first repair attempt. Reassigned before finishing. The conduit map is 80% complete. Player intervention: Aster hacks the researcher's terminal and completes the conduit map using his device. The remaining connections fill in. This reveals the optimal path through the facility in the present (appears on Aster's device as navigable routing). It also cascades forward: Timeline 2's researchers now had a complete map when they arrived, so their workspace is in a different, better location.

*Timeline 2 (years later, deeper in).* A pair of workers. One did biological analysis (found that organic material could bond to the conduit surface and regrow insulation naturally), the other did engineering (built a frame to support the organic growth). They had a working prototype. Tagged and removed the same day. Player intervention: Peris tends the biological culture the workers started. It was dying when they were removed; without tending, it withered. Peris revives it in the frozen moment. The organic insulation begins growing. This cascades to the present: sections of conduit that were bare now have thin, old, but functional organic insulation. Sparking damage is reduced in those corridors, opening areas that were too hazardous to traverse. It also cascades to Timeline 3: the lone researcher working later now had partially insulated corridors, so they got further than they originally did.

*Timeline 3 (later still, deepest accessible section).* Someone working alone, using the previous researchers' work as foundation. They'd found the abandoned workspaces, read the notes, combined the conduit map with the biological approach. One step from reaching the conduit where the Pattern Wrap sits. Stopped not by reassignment but by the wiring itself: the conduit section they needed to cross was live, sparking, impossible to traverse without insulation they didn't have. Left notes describing what they could see on the other side. Player intervention: Oli examines the researcher's circuit analysis. The researcher identified the live conduit but couldn't de-energize it. Oli traces the circuit to its source and identifies the disconnect point. He can't pull the disconnect in the frozen moment (the switch is in a part of the facility that doesn't exist in this timeline's overlay). But his analysis changes the present: the disconnect point's location is now known, behind a specific wall. Myke wall-punches to the disconnect point. The live conduit goes dark. The final path is open.

*Timeline 4 (most recent, the moment the section was sealed).* Not a researcher. An enforcer. The frozen moment shows someone sealing the section, filing the closure order, cataloguing the abandoned equipment. This is the system's response to the research: not destruction, just administrative closure. The equipment is still here because nobody was sent to remove it. The work was filed away. The enforcer is performing the banality of evil: following procedure, closing a ticket, moving to the next task. Their face is neutral. They are not malicious. They are doing their job. Player intervention: none. There is nothing to change. The enforcer did their job. The section was sealed. But the player can read the closure order on the enforcer's terminal, and it contains one piece of information nobody else had: the exact location of the Pattern Wrap, listed in the equipment inventory as "unidentified biological device, non-critical, catalogued for disposal, never collected." The system documented the cure component, classified it as irrelevant, and left it on a shelf. The enforcer's contribution to the cure is unintentional: they created the record that tells the player exactly where to go.

**The retrieval.** Aster hacks the closure seal on the storage closet the inventory record identified. The door opens. The Pattern Wrap is on a shelf, labelled with an inventory tag, classified as non-critical. The cure component has been sitting in a filing system, properly documented, correctly categorized as unimportant, for decades. It was never hidden. It was never destroyed. It was dismissed. The conduit where the organic insulation grew is visible nearby, still partially wrapped, still carrying clean signal through that section. Removing the Pattern Wrap doesn't destroy the existing regrown sheath; it persists as proof the component works. But no new growth will occur. The player takes the promise, not the proof.

**After retrieval.** [Dialogue WIP, needs workshopping for voice consistency. Key beats: Oli recognizes the type of work. These were people doing what they do. They were stopped by the system, one by one. Nobody told any of them about the others. The party just connected their work across time. Oli's character moment: the insulator reconnected signals the system had severed. Remyelination as metaphor: the breaks in the line were administrative, not physical.]

**Design note.** The Pattern Wrap puzzle is mechanically distinct from the Inflammashunt and the Membrane Sealant. The Inflammashunt tests information synthesis in the present (three routes, three reports, one room, conflicting data resolved through patience). The Membrane Sealant tests trust and commitment (plan a system, relinquish control, watch it execute, resist the override). The Pattern Wrap tests temporal reasoning and cumulative intervention (four timelines, cascading changes, building a path through the present by changing the past). Each puzzle asks the player to think in a different dimension. The Inflammashunt is spatial. The Membrane Sealant is interpersonal. The Pattern Wrap is historical.

The four researchers form a micro-narrative about institutional memory. Researcher 1 had the right instinct but not the tools. Researcher 2 had the tools but not the time. Researcher 3 had the synthesis but not the access. The enforcer in Timeline 4 had the access and used it to lock the door. Each person was one piece of a solution none of them could complete alone, not because the problem was too hard, but because the system never let any of them see the others' work. The player, walking through frozen moments, is the first person to see all four contributions in sequence. The cure was always possible. The connection between the people who could have built it was what was missing.

Timeline 4, the enforcer, having no player intervention is a deliberate structural choice. Timelines 1-3 each require a specific party member's ability to progress. Timeline 4 requires nothing except reading. The system that sealed this research didn't need to be clever or powerful. It just needed to file a form. The most devastating intervention in the history of this research was the one that required the least effort. The enforcer's frozen moment is the game's argument about bureaucratic evil: you can't undo it by toggling a switch or tending a growth, because nothing was broken. A procedure was followed. The procedure was the problem.

#### 10.4.4 Flow Aligner (Channel Polarizer)

Real basis: Therapies targeting aquaporin-4 polarization restoration at astrocytic endfeet, which re-enables glymphatic waste clearance. AQP4 depolarization is one of the earliest detectable changes in neurodegeneration.

Located at a water junction deep in Zone 2 where most of the flow has stopped. Pipes are dry; channels are blocked or reversed; fluid pools in places it shouldn't, stagnant and discolored. But one junction point has water flowing correctly: right direction, right pressure, through channels that are properly oriented. The Flow Aligner is embedded at this junction. The contrast is immediate. When the player removes it, the flow at that junction slows and begins to pool. Peris senses something at this junction through flora resonance; Aster's data view confirms the readings.

**Puzzle concept.** Fragment assembly under memory decay and enemy pressure. The water junction contains shattered mosaic panels on the walls (flow diagrams that once told maintenance workers which direction each channel should run). The panels are broken. Fragments are scattered through the junction rooms, mixed together, wedged into crevices, carried by stagnant current into side channels. Each fragment has a partial pattern on it: a curve, a line, an arrow, a section of color. The complete panels, when assembled, form images that map the junction's correct flow pattern. The player needs the assembled image to know which valves to open and which channels to redirect to reach the Flow Aligner.

Peris is the only character who can read the images. Aster sees the fragments as material data (composition, age, structural properties). Oli sees electrical elements on some fragments. Myke sees the mounting infrastructure (which fragment fits which frame). Only Peris can see the colors, the shapes, the actual picture. Her perception is actively degrading at this point in the game. When she examines a fragment, the pattern is clear for a few seconds, then the colors bleed and the lines waver. If she looks away and looks back, the fragment appears slightly different than she remembers. The player is building a mental model of the complete image using a character whose model is failing.

The fragments are heavy. A character carrying a fragment moves at walk speed, cannot dodge, and cannot use abilities. They are completely vulnerable. The junction rooms are patrolled by enemies (Chelators drawn to the iron content of the stagnant water, environmental hazards from the backed-up fluid). The party splits dynamically by the player's choice: one character carries the fragment toward the panel frame, the others run interference, pulling aggro, creating safe corridors, covering the carrier's slow walk. Myke's fire draws enemies away from the carrier but creates zones the carrier also can't cross. Tyreg can pick off threats at range but needs clear sightlines. Oli can place a Barrier between the carrier and approaching enemies, but the barrier also blocks the carrier's forward path if poorly positioned. Peris can Wrap the carrier to reduce damage if enemies reach them, but then she's committed to staying near the carrier rather than reading the next fragment. If a character gets hit while carrying, they drop the fragment. If Peris gets knocked, her perception scrambles worse for a period, making her re-reads less reliable.

The sequence for each fragment: Peris reads it (the player memorizes the pattern during the clear window), someone picks it up and begins the slow walk, the remaining characters create a safe corridor, the carrier reaches the panel frame and the player places the fragment based on what they remember from Peris's reading. If the placement is wrong (the player misremembered, or Peris's flickering perception showed something that wasn't quite right), the fragment has to be removed and Peris has to re-read it, costing time and re-exposing the carrier.

The assembled panels, when correctly completed, are beautiful. They are flow diagrams designed as art: murals depicting the junction as it was meant to look when everything worked. The correct flow pattern is also a picture of a healthy system, water moving in the right directions, channels clear, the infrastructure alive. Peris is assembling a picture of how things are supposed to be while living inside a version of how things are. The player is building the map of her inner world by piecing together what she can still see. (Full puzzle layout and fragment count TBD.)

**Synthesis beat ("Specters, of Marks")** — **WIP.** Aster's moment of synthesis at the Flow Aligner ruin is canonical and partially drafted; current draft and design notes live in `flow_aligner_synthesis_beat__1_.md` and are flagged as work-in-progress. The beat lands after Aster has cross-referenced enough institutional records to assemble a picture of what happened (two facilities, war over CSF, the winning side dying anyway, the appropriation by maintenance workers afterward). The synthesis is jointly produced: Peris's reflection of "brains" back to him as a human-body word pulls his technical framing into the register where the citation becomes available. Voice consistency, line-level revisions, and final placement within the Flow Aligner sequence are the open work on this beat.

**Design note.** The Flow Aligner makes Peris's decline into a mechanical challenge for the first time. Previous puzzles used her abilities as tools; this one uses her failing abilities as a constraint. The player is not compensating for her decline by switching to another character. They are working through her perception because she is the only one who can read what matters. The other characters can carry, fight, and protect, but the seeing has to be hers.

#### 10.4.5 Outflow Expander (Drainage Amplifier)

Real basis: VEGF-C/VEGFR-3 signaling pathway modulation that dilates meningeal lymphatic vessels, improving the brain's waste export capacity.

Located near the outermost edge of the map, in the drainage infrastructure. Most of the drainage channels are constricted, narrowed, barely functional. Waste accumulates upstream because it can't get out fast enough. But one drainage channel is wide open: dilated, flowing freely, clearing everything that reaches it. The Outflow Expander is attached to this channel, maintaining its dilation. The area downstream is visibly cleaner than the surrounding drainage infrastructure. Upstream, waste backs up to the point where the working channel starts, and then clears. When the player takes the device, the channel begins to constrict. Oli's electrical flow layer reveals powered drainage infrastructure behind sealed sections; Aster's terminal hacking opens the sealed maintenance access. Party composition: Aster, Peris, Myke, Oli (four characters; Tyreg has not yet joined). This is a mid-Act 2 danger zone.

**Puzzle concept: memorize the maze, then run it blind under rising water.** The drainage infrastructure is organized as a series of descending floors, each containing a maze of pipes, junctions, and dead ends. The Outflow Expander is at the bottom, attached to the one working drainage channel. Each floor follows the same two-phase structure.

*Phase 1 (dry run).* The floor is dry. The player explores freely, mapping the maze, learning the layout, finding the path from entrance to the gate that leads to the next floor down. There is no time pressure. The player can take as long as they want. The maze splits into paths that require specific characters: Aster's path hits a terminal that controls a gate on another character's path, Peris's path has a flora growth that opens a different gate, Oli's path has a powered conduit that unlocks a section, Myke's path is the most physically direct but has the tightest corridors. During the dry run, the player plans not just one route but four overlapping routes, one per character, and figures out the activation order (Aster must hack his terminal before Myke can pass through the gate it controls, Peris must tend her flora before Oli's section opens, etc.).

*Phase 2 (wet run).* The player hits the button. The gate unlocks. Water begins rising from below. The maze splits and all four characters must navigate their individual paths simultaneously, activating gates for each other in the right order, and all four must reach the floor exit before the water catches any of them. The player uses the pause-and-direct system to manage all four, but visibility in the pipes is near zero once the water starts rising. The water obscures the floor and lower walls. The subtle environmental cues the player used during exploration (Aster's pressure indicators, Peris's living-tissue sensing, Oli's conduit markings) are gone. The player is navigating from the memory they built during the dry run, directing four characters through four paths they can barely see.

Myke is the slowest character. His path is the shortest but his margin is thinnest. If the player doesn't route him efficiently, he's the one who gets caught. The party's toughest fighter is the liability in this puzzle. His strength is irrelevant. His speed is the constraint.

If any character gets caught by the water (trapped in a dead end, too slow, wrong turn), the entire party is washed back to the beginning of that floor. The water recedes. The player goes again with better knowledge. No HP loss, no resource drain. Just the understanding of which route failed and why.

Each floor escalates. Floor 1 is a simple maze with wide corridors, few dead ends, and obvious splits, teaching the dry-run/wet-run format and the multi-character routing. Later floors are denser, with more branching, tighter timing, and more interdependent gates (Aster's terminal opens Oli's path, but Oli's conduit powers Peris's gate, so the activation order cascades). The final floor requires precise memory of four routes and their timing dependencies.

**Design note.** Each floor is fully navigable. The correct paths exist. The maze was designed to be solved. The water is not trying to kill the player; it is simply rising. The player who panics and sends characters blindly hits dead ends. The player who trusts the memory they built during the dry run, who believes the paths they found are still there even though the water has erased the landmarks, reaches the gate. (Full floor count, maze dimensions, gate dependencies, and water rise timing TBD.)

The puzzle inverts the game's usual relationship between perception and memory. Throughout the game, the player compensates for Peris's failing memory by relying on character perception layers. Here, the perception layers are available during the dry run but gone during the wet run. The player must build their own memory of four routes and then trust that memory when the cues disappear. The pause-and-direct system means the difficulty is not reflexes but spatial memory and multi-character coordination under the pressure of rising water and near-zero visibility. The stress comes from knowing the path is there, knowing you saw it, and not being able to see it now.

#### 10.4.6 Acid Core (Waste Processing Catalyst)

Real basis: Approaches targeting lysosomal acidification and autophagy restoration, which fail early in AD as lysosomes lose their ability to digest accumulated proteins.

Located in an old waste processing facility in Zone 3 that the civilization abandoned. Most of the facility is clogged: pipes backed up, processing tanks overflowing with accumulated sludge, the entire space choked with material that was supposed to be broken down and wasn't. But one tank is still working. Clean inside. Material enters and dissolves. The fluid is clear. At the center of the tank, the Acid Core hums, maintaining the acidic environment that allows digestion to continue. Everything around it is a portrait of what happens when waste processing fails. This tank is a portrait of what it looks like when it works. Endo knows the back routes to the old facility; his map layer shows paths others can't see.

**Puzzle concept: acid flow valve routing with incidental character moments.** The approach to the working tank runs through the processing facility's pipe network. Acid flows through open channels, blocking paths. The facility contains a series of valves that redirect the acid flow: turning a valve opens one channel and closes another, changing which routes through the facility are passable and which are flooded. The player has to figure out the correct sequence of valve turns to create a navigable path from the entrance to the working tank. Turning valves in the wrong order can block the party's route, forcing them to backtrack and re-route.

The complication: valves are spread across different sections of the facility, and turning one valve changes which sections are reachable. The party naturally splits as the acid flow reconfigures the passable routes. Characters end up in different parts of the map based on where they were when the flow changed, not by player design. Some sections are only reachable through specific access points (a crawlspace only Myke fits through, a terminal-locked door only Aster can hack, a section requiring Tyreg's enforcement-class identity card). The incidental pairings that result, Tyreg and Myke ending up together because the crawlspace and the card-locked section connect, Aster and Peris isolated in a monitoring room while Oli reroutes power to a stuck valve, are where the character moments happen.

The character-fondness element: the lighter backstory moments emerge from proximity and shared circumstance, not from scripted bonding scenes. The facility has environmental details that characters react to when they happen to be nearby. An acid puddle that distorts reflections like a funhouse mirror. Myke sees himself stretched tall and has a moment, not a speech, a beat where he looks at the distorted reflection and says something about how he used to want to be taller, but then he wouldn't have been himself, and the adversity and difference he faced made him who he is. [Dialogue TBD, needs workshopping. The tone should be offhand, a thought that surfaces because the mirror is there, not because the game arranged a therapy session.] Tyreg, if she's with him, reacts in her own way. Other pairings produce other moments, discovered by the player based on which characters end up where when the acid flow shifts. Not every player will see every moment. The moments are rewards for exploration and for paying attention to where people ended up.

The puzzle's mechanical challenge is sequential logic: which valve to turn in which order, tracking the state of each channel (open/closed/flooded), reasoning about how changing one flow affects the others. The facility map is the puzzle board. The acid is the constraint. The valves are the moves. The solution is a sequence that opens a continuous path without flooding the sections the party needs to traverse.

Lighter and more character-driven than the architectural puzzles. The valve routing is a genuine logic puzzle, but the emotional texture comes from the incidental pairings and the moments that happen because characters ended up together by circumstance. The fondness isn't announced. It's discovered. The player who rushes through the valves to reach the working tank gets the retrieval scene. The player who lingers in the sections where characters are paired, checking every environmental detail, gets the lighter backstory moments that make the comedy retrieval scene land harder. Not every puzzle needs to be architecturally ambitious. Some need to be the moment where you discover that the people you're traveling with are people you like.

**The retrieval scene.** The party arrives at the facility. The smell is the first thing. Myke, who has worked maintenance his entire life, says it smells like "every deferred work order in the system decided to hold a conference." Peris covers her face. Aster's data readings are spiking in ways he describes as "medically interesting and personally offensive."

The working tank is obvious. One clean circle in a room of backed-up sewage. The Acid Core sits at the bottom, visible through the clear fluid.

Tyreg, being Tyreg, assesses the situation. She knows the word "acid." She's heard the phrase "dropping acid" in fragments of inherited culture, always in the context of something that makes people lose their minds. She has never encountered actual acid. She reaches in, grabs the core, and the fluid burns her hand. She drops it back in with a hiss, shaking her fingers, staring at her palm. She looks at the tank. She looks at her hand. She looks at the tank again. "That just burns," she says. Genuinely confused. She was bracing for something else entirely. She'd heard dropping acid was supposed to make you see things, lose your grip on reality, go somewhere else. All it did was hurt her hand. "I thought..." She trails off, not sure how to finish the sentence without sounding stupid.

Myke, who has been watching with growing delight, pieces it together instantly. "You thought 'dropping acid' was going to be a different experience."

Tyreg stares at him.

Oli, from the back of the room: "Well. At least she's not confused about the phrase 'dropping the bomb.'"

Peris is trying not to laugh. Aster, helpfully, begins explaining the pH scale and the difference between corrosive acids and lysergic compounds, which helps nobody and enlightens everyone in a way they didn't ask for.

Tyreg, to her credit, does not get defensive. She gets precise. "The core is in the fluid. The fluid burns. I need something that doesn't burn." She looks at the room. She looks at the overflow pipes, which are made of material specifically designed to withstand the processing fluid. She breaks off a section of pipe, fashions a crude scoop, and retrieves the Acid Core without touching the liquid. Clean. Efficient. Solved.

Oli: "For the record, I'm giving this facility two out of ten. One point for the working tank. One point for the live demonstration of what 'dropping acid' actually means."

This scene layers the inherited language theme into comedy. "Dropping acid" is another phrase the civilization carries without understanding, exactly like "Move fast and break." The cultural fragment survived. The context didn't. Tyreg's confusion is genuine, not stupid: she was working with the information she had. The information was wrong. This is the game's thesis played for a laugh instead of a tragedy, which makes the tragedies land harder by contrast.

This scene establishes several personality traits: Tyreg's first instinct is always direct action, and when it fails, she doesn't panic, she problem-solves. Oli's humor is bone-dry observation delivered like they're filing an incident report for their own amusement. Myke laughs at people, which is how he shows affection. Aster is helpful at the wrong moments. Peris tries to be polite about finding things funny. These traits should remain consistent in all subsequent scenes.

**Design note.** The Acid Core puzzle is the lightest of the nine. The pairings the puzzle generates are the incidental record of a group of people who are starting to enjoy each other's company. The retrieval scene's comedy is the payoff for the texture the puzzle has been building.

#### 10.4.7 The Resonator (Frequency-40 Stimulation Array)

Real basis: 40 Hz multisensory gamma stimulation (GENUS), which promotes glymphatic clearance of amyloid by increasing CSF influx, AQP4 polarization, and meningeal lymphatic drainage. Currently in Phase 3 clinical trials.

Located in Harmonia, the gamma-entrainment district at shelters 21-22. The hardest area in the game. But when the player finally reaches the room, it is unexpectedly clean. Not maintained by anyone. Clean. The fluid dynamics are working. Waste is being cleared. The air feels different. There's a faint rhythmic pulse in the environment, not quite audible, more felt. The Resonator sits at the center, and it's been running on its own for who knows how long, keeping this one pocket of Zone 3 functional while everything around it decayed. The room is proof of concept: this is what the entire NVU could look like if the clearance system worked. Taking the Resonator means this room will eventually decay too. The player removes the last working example of what they're trying to build. Reaching this archive requires knowledge from multiple perception layers and the combined survival capabilities of the full party.

**Puzzle concept: pendulum frequency and phase alignment.** The approach to the Resonator passes through a series of resonance chambers. Each chamber contains pendulums: heavy spheres suspended from the ceiling or mounted on wall pivots. Some swing vertically (in the plane of the floor, north-south or east-west). Some swing horizontally (side to side across the chamber). Their paths may cross.

The core mechanic: two characters stand on opposite sides of a pendulum. Their distance determines the swing arc, which determines the pendulum's frequency. Closer together means shorter arc, higher frequency. Further apart means longer arc, lower frequency. Each pendulum has a target frequency, visible as a resonance line on the floor showing the ideal arc, or as a marker on the pendulum's energy bar. When the pendulum swings at its target frequency, the energy bar fills. When it stops swinging (collision, or characters move away), the energy bar drains.

The collision constraint: pendulum paths may intersect. A vertical pendulum at full arc might swing through the space where a horizontal pendulum passes at its midpoint. If two pendulum balls occupy the same intersection point at the same moment, they collide and both stop. Both energy bars begin draining. The player has to set frequencies that match each pendulum's target AND ensure the phase relationships between pendulums prevent collisions at crossing points. Pendulum A at frequency X and Pendulum B at frequency Y might have paths that cross; the player needs A and B to be out of phase at that crossing so their balls never meet. Changing A's frequency (by repositioning its character pair) changes when it hits the crossing. Changing B's frequency does the same. The correct solution is a set of distances and starting times where every pendulum hits its target frequency and no two collide.

The character staffing constraint: each pendulum needs two characters to operate (one on each side). With five characters (or six with Endo), the party can staff two pendulums simultaneously with one character unassigned, or three pendulums with six characters. If a chamber has more pendulums than the party can staff at once, the player must sequence: start pendulum A, get its energy bar filling, release those characters to move to pendulum C, start C before A's momentum decays and its bar drains. The already-swinging pendulum maintains its arc for a limited time after the characters leave (natural decay), so the player has a window to reposition. Managing the sequence of which pendulums to start, in what order, and how fast to move characters between them adds a timing layer on top of the spatial positioning.

The chamber progression: early chambers have two pendulums with non-crossing paths. The player learns the distance-frequency relationship and the energy bar mechanic. The second chamber introduces crossing paths and the collision constraint. Later chambers add more pendulums, more crossings, and the staffing-sequencing challenge. The final chamber requires all pendulums swinging at target frequency simultaneously with no collisions, meaning the player must find the correct distances, the correct start order, and the correct character movement sequence to keep everything in motion long enough for all energy bars to fill.

No enemies. No time pressure beyond the pendulums' natural decay. The Harmonia' ambient difficulty (extended ability cooldowns, slowed stamina regen) affects the approach, but the puzzle chambers themselves are still. The player watches pendulums swing, listens to the tones they produce (each frequency generates a pitch, and the combined sound of all pendulums at target frequency is the environmental pulse the player has been hearing since entering the sub-area), and adjusts by repositioning characters. When all energy bars fill simultaneously, the resonance field opens.

When the final chamber resolves, the party walks through into the clean room. The pulse they matched is the Resonator's output: the 40Hz frequency that has been keeping this pocket of Zone 3 functional. The room is quiet, clean, alive. The first truly peaceful space in the game's most hostile zone. The Resonator sits at the center. Taking it means this room will eventually decay too.

**Design note.** The pendulum puzzle makes the relationships between characters into physical mechanics. Two characters on opposite sides of a pendulum are literally creating energy through their positioning relative to each other. The distance between them determines what they produce. The collisions at crossing points are what happens when two relationships that each work independently are out of phase with each other: both fine alone, destructive when their timing conflicts. The sequencing constraint, having to start some pendulums and then trust their momentum while moving to the next, is what shared work actually feels like: you build something together, set it in motion, and trust it to carry while you go build the next thing.

Endo's presence changes the puzzle concretely. Six characters can staff three pendulums simultaneously instead of two. Chambers that require complex sequencing with five characters (start A, move to C, race back to restart A before it decays) become simpler with six (A and C staffed concurrently, only B needs sequencing). The puzzle is solvable either way, but the Endo version is more graceful. The mechanical reward for recruiting Endo is not easier. It is less frantic. The harmony has more room to breathe.

#### 10.4.8 Membrane Sealant (Lipid Stabilizer)

Real basis: Ferrostatin-1 / Liproxstatin-1 class compounds that suppress iron-dependent lipid peroxidation in neuronal membranes.

An endgame danger zone in deep Zone 3 (second-to-last component, before the Rest Cycle Module). A corroding bilayer membrane corridor: walls actively oxidizing, membranes peeling, infrastructure buckling. One section, roughly at the far end, is pristine and faintly luminous, held together by the Sealant woven into its tissue. Requires all six party members (five main characters plus Endo, if re-recruited). The puzzle strips all character perception overlays and replaces them with observation, memory, and planning under mutual vulnerability.

**The environment.** The bilayer membrane corridor renders cell membrane architecture as level geometry. Two outer corridors (Route L and Route R) run parallel to a central corridor (Route C), separated by thick membrane walls in various states of decay. Some sections are intact (opaque, structurally sound), some are corroding (translucent, leaking oxidizing fluid), some are breached. The corridor environment is hostile: ambient oxidation damage, iron deposits on every surface, the infrastructure visibly failing around the party. The pristine section at the far end is the contrast, clean, luminous, alive, proof that the Sealant works.

**The puzzle structure: three synchronized sections.** The puzzle is divided into three sequential sections. Each section uses the same format: three parallel routes (L, R, C) with the party split into three pairs, one pair per route. Route L and Route R are lit corridors containing observation areas and toggle switches. Route C is dark, with no visibility, and the pair assigned to it walks forward automatically during execution. The pairs rotate between sections so that every pair walks Route C exactly once.

The three pairs are:
- Aster and Peris (the core duo; least combat-capable)
- Oli and Endo (the infrastructure pair; if Endo was not re-recruited, Oli walks alone)
- Myke and Tyreg (the combat pair; strongest fighters)

**No perception overlays.** This is the only puzzle in the game where all character-specific map layers and perception systems are disabled. No data overlay from Aster, no biological sensing from Peris, no road map from Myke, no electrical flows from Oli, no patrol routes from Tyreg, no survival markers from Endo. The corridors are just corridors. The player sees what is physically in front of them, nothing more. The entire game has taught the player to see through other people's eyes, layering perception on perception to build a composite picture of the world. The Membrane Sealant takes all of that away and asks: can you observe, remember, and plan using only what you can see?

The single exception: when a character falls through a hazard on Route C during execution, Aster's sound recording catches the approximate impact location. On retry, this appears on the planning view as a fuzzy circle over Route C's map, marking "something is here, roughly." The map of the dark corridor is built from injuries. Every data point on it is a person who fell because the plan wasn't good enough. The player who solves each section clean on the first attempt never sees a single sound ping. Their Route C map stays blank because nobody fell.

**The core mechanic: plan, commit, lose control.** Before each section executes, the player has a free planning phase. They can move between Route L and Route R freely, observe through viewing ports, toggle switches, set multi-point routes for the L and R pairs via shift+click (move to tile, toggle switch, wait N turns, move to next tile, toggle again). The player can replan as many times as they want: re-observe, re-toggle, re-route. The planning phase has no time pressure.

When the player is satisfied with their plan, they press the commit button. This unlocks Route C and relinquishes character control. All three routes execute simultaneously on a shared turn counter: the L pair follows their plotted route, the R pair follows theirs, and the C pair walks forward one tile per turn, automatically, without player input. The player watches from a fixed overhead camera that shows Routes L and R playing out their pre-programmed waypoints. Route C is not visible on the fixed camera; it appears as a dark strip between L and R. The only signal from Route C is an exclamation mark icon (the same icon used for enemy encounters throughout the game) that appears over the dark strip if a character falls through a hazard. The player sees their plan execute on the sides and can only infer what's happening in the center.

**The override button.** During execution, an "Override" button is visible on screen. Pressing it immediately restores full character control. It also causes every floor tile in Route C to flash and collapse, dropping anyone on Route C into the lower level. The override destroys the run. The puzzle must be fully replanned and restarted for that section.

The button is always visible. Every turn of execution, it sits there. The player who trusts their plan leaves it alone. The player who panics and grabs for control wrecks the thing they were trying to protect. The override tests whether the player has internalized the lesson or is still trying to maintain control over something that requires letting go. This is the trust principle rendered as a UI element. The option to reassert control is always available, and exercising it is always destructive. Trust is not the absence of the ability to intervene. It is the choice not to intervene when intervening would cause more harm than the uncertainty it resolves. The override button is visible for the same reason that distrust is always available in a relationship: you can always demand proof, demand access, demand transparency. And doing so shatters the thing you were trying to verify.

**Observation and action are mutually exclusive.** Each lit corridor (L and R) contains observation areas and switch zones. The observation area requires both characters in the pair to stand in it simultaneously to activate the viewing port (blue-tinted for Route L, red-tinted for Route R). The activated port shows a section of Route C: physical floor tiles, gates, visible cable conduits running from switches through the membrane wall. While both characters are in the observation area, the corridor's switches are hidden and non-interactable.

When the pair leaves the observation area to reach the switches, the viewing port goes dark. The player toggles switches based on what they remember seeing, not what they are currently seeing. They can return to the observation area to re-check, but this means walking away from the switches again. The puzzle's friction is the gap between seeing and doing. This mirrors the game's memory theme at the mechanical level: the player is always working from a remembered picture, and the question is whether their memory is accurate enough to act on.

The blue port (Route L) and red port (Route R) each reveal different sections of Route C's hazards. Neither port shows the complete picture. The player must observe from both corridors and synthesize the information to build a full mental model of Route C. Some sections of Route C may be invisible from both ports (blind spots), forcing the player to either accept the uncertainty or discover what's there through a failed execution.

**Physical cables connect switches to hazards.** Without perception overlays, the player traces physical cable conduits running from each switch through the membrane wall toward Route C. The cables are the only clue about which switch controls which hazard. Some cables fork (one switch controlling two hazards). Some switches are inverted (toggling ON closes a gate instead of opening it). The player must physically observe the cable routing during the observation phase and remember it when they reach the switches.

**Toggle switches.** All switches are binary ON/OFF toggles. Some hazards require a switch to be ON at a specific point in the execution (when the C pair reaches that tile) and OFF at a different point (because the same switch affects a later hazard). This means the L or R pair's planned route must include toggle-and-re-toggle sequences timed to specific turns. The shift+click route planner allows: move to switch, toggle, move to next waypoint, wait, move back to switch, toggle again. The sequencing of when each switch is toggled during the simultaneous execution is the core of the timing puzzle.

**Failure and recovery.** If the C pair reaches a tile with an uncovered pit, a closed gate, or an unstable panel, the affected character falls to a lower level (a partially flooded sub-membrane space, corroded, hostile, populated with enemies). Recovery requires the fallen character to fight or navigate through the lower level and climb back up, which costs several turns and HP. The other character in the C pair waits at the hazard point, exposed to ambient environmental damage.

After a failed execution, the section can be retried. The player replans the L and R routes with new information: Aster's sound pings marking the approximate locations of falls. Each retry adds to the player's knowledge of Route C, but every data point was purchased with a character's injury. The puzzle does not reset to pristine state; damage to characters persists across retries (HP loss, stamina drain from lower-level recovery). The player who needs many retries enters the next section in worse condition.

**Section rotation: everyone walks the dark.** The pairs rotate across the three sections so that every pair spends one section on Route L, one on Route R, and one on Route C. The sections are ordered by Route C length, with the least combat-capable pair walking the longest dark route and the most combat-capable pair walking the shortest.

*Section 1: Myke and Tyreg on Route C (shortest, approximately 8 tiles).* L = Aster/Peris. R = Oli/Endo. Route C has 3 hazards (one gate, one pit, one gate). L has two switches, R has one. All switches are straightforward toggles with no inversions and no forking cables. The observation ports provide full coverage of Route C with no blind spots. This section teaches the format: observe through ports, memorize hazard positions, trace cables, toggle switches, set routes, commit, watch execution. If Myke or Tyreg falls, they handle the lower level easily (both are fighters; recovery is fast, 2-3 turns). The timing consequences of a fall are minimal. This is the tutorial section. The thematic note: the party's two strongest fighters are the first to walk blind. Their combat capability is completely irrelevant in the dark. Myke can't punch what he can't see. Tyreg can't shoot what she can't identify. The characters who solve problems through force and precision are in the one situation where neither applies. Their strength only matters if they fall, and even then it only cushions the consequence, it doesn't prevent it.

*Section 2: Oli and Endo on Route C (medium, approximately 12 tiles).* L = Myke/Tyreg. R = Aster/Peris. Route C has 5 hazards (two gates, two pits, one unstable panel that looks like solid floor but collapses under weight). L has three switches, R has two. One switch in L has a forking cable that controls both a gate and a pit cover. One switch in R is inverted (toggling it ON closes a gate instead of opening it; the cable routing to the gate's closing mechanism, rather than its opening mechanism, is the visual clue). The observation ports have a small blind spot: approximately 2 tiles in the middle of Route C are invisible from either port. Those tiles are safe (no hazard), but the player does not know that. Endo's presence provides a plus-or-minus one turn margin of error on timed elements. If a pit cover retracts one turn before the pair reaches it, Endo braces the edge and they cross safely. If they fall, Endo's physical resilience reduces recovery time (approximately 3 turns instead of 5). Without Endo (if the player did not re-recruit him), Oli walks alone. Every timing must be exact. Every fall is the full recovery duration. Oli alone in the lower level, a non-fighter in a hostile space, is genuinely dangerous. The player who recruited Endo has a margin. The player who didn't faces the version of trust with zero slack. This section teaches forking cables (one switch, two consequences), inverted switches (not all toggles work the same way), and blind spots (some information is unavailable, and the player must decide whether to accept the gap or burn a retry investigating it).

*Section 3: Aster and Peris on Route C (longest, approximately 16 tiles).* L = Oli/Endo. R = Myke/Tyreg. Route C has 7 hazards (two gates, three pits, one unstable panel, and one corroding floor section that advances one tile per turn from a fixed origin, damaging anyone standing on a corroded tile). L has four switches, R has three. Two forking cables (one per corridor). One inverted switch. The corroding floor requires a toggle-and-re-toggle: the stabilizer switch must be toggled ON at a specific turn to protect the C pair as they cross, then toggled OFF a few turns later because leaving it ON permanently locks a gate the C pair needs to pass through afterward. This is the first section where the planned route must include a precise toggle-retoggle sequence. The observation ports have a larger blind spot: approximately 3 tiles in the mid-section of Route C are invisible from either port. One of these tiles contains a pit. The player cannot see it through any observation. The only way to discover it is for Aster or Peris to fall into it, generating the sound ping. In Section 2, the blind spot was safe, and the player who investigated it found nothing. Section 3 punishes the player who generalized from that pattern and assumed blind spots are always safe. The player who was cautious enough to hedge against the unknown (routing a switch to cover the invisible tiles just in case) avoids the fall. The puzzle rewards distrust of established patterns and caution in the face of incomplete information. If Aster falls: sound ping, approximate location, but he is in the lower level with enemies and no combat ability. Peris is alone on Route C, standing at the edge, taking ambient environmental damage, waiting. If Peris falls: the same problem, compounded by her declining perception making the lower level foggier, harder to navigate. The player sees the exclamation mark pop up over the dark strip on the fixed camera and knows that the two people they have been trying to save for the entire game are in the dark, separated, because the plan wasn't good enough. This section is the emotional peak of the puzzle. The longest walk. The most complex switch sequencing. The least forgiving pair. The game's heart in the dark.

**The Sealant retrieval.** After all three sections are cleared, the three pairs converge in a chamber where the pristine membrane section is. The membrane here is luminous, intact, visibly alive. The Sealant is not a discrete object sitting in a container. It is woven into the membrane tissue itself: a lattice of lipid stabilizer compounds integrated into the membrane's structure, holding it together. The membrane is healthy because the Sealant is there. Taking the entire Sealant would destroy the pristine section. The party does not do this.

Instead, they take a sample. Enough to analyze and synthesize a treatment, not enough to destroy what is working. Peris tends the membrane tissue to encourage it to release a small amount of the compound. Aster analyzes the sample's composition with his device. Oli checks that the extraction does not disrupt the membrane's electrical transport. Myke checks the structural anchoring around the extraction point. Tyreg watches for threats. Endo holds the membrane steady from the other side.

Six people, each doing one small thing. All voluntary. All gentle. No force, no puzzle mechanics, no switches. Just care. The hardest part was getting here. The retrieval is what trust looks like when it has been earned: quiet, cooperative, undramatic. The pristine membrane section remains intact after the party leaves, standing in the deep dark of Zone 3 as evidence that the cure is possible.

**Design note.** The Membrane Sealant puzzle is mechanically distinct from every other component retrieval in the game. The Inflammashunt is a real-time three-route information-gathering and synthesis puzzle where the player is present, active, and experimenting. The Membrane Sealant is a turn-based planning and commitment puzzle where the player designs a system, relinquishes control, and watches it execute. The Inflammashunt tests whether the player can resist the aggressive instinct and choose patience. The Membrane Sealant tests whether the player can resist the control instinct and choose trust. Both puzzles are recoverable from mistakes. Both puzzles teach their rules through failure. The Inflammashunt's failures are immediate and experiential: fire, combat, a hostile root. The Membrane Sealant's failures are deferred and inferential: an exclamation mark over a dark strip, and the knowledge that someone you care about just fell because of a plan you made.

Stripping all perception overlays for this puzzle is a deliberate inversion of the game's core progression loop. The player has spent the entire game accumulating ways of seeing: recruiting characters for their perception layers, building the composite map, compensating for decline with more data from more sources. The Membrane Sealant says: none of that matters here. Observe with your eyes. Remember with your own memory. Plan with your own reasoning. Trust with your own judgment. The game's central mechanic, perception-as-character, is absent for exactly one puzzle, and that absence is the puzzle's emotional thesis. Trust is not built from having enough information. It is built from acting well with incomplete information and discovering, afterward, that it was enough.

The override button is the most important UI element in the puzzle. It is never mentioned by any character. No tutorial explains it. It appears when the player commits their plan and relinquishes control. It stays on screen for the entire execution. It always works. It always destroys the run. The player who never presses it may not even register it consciously. The player who presses it once will never press it again. The player who hovers over it for every turn of every execution and doesn't press it is experiencing the puzzle exactly as intended.

#### 10.4.9 Rest Cycle Module (Circadian/Clearance Cycle Regulator)

Real basis: Sleep-dependent glymphatic clearance enhancement. The glymphatic system is most active during sleep; circadian rhythm disruption (common in AD) impairs waste clearance. Restoring sleep architecture restores clearance.

Located in a hidden shelter, discovered through a multi-room trial-and-error section. When the player finds it, this shelter is unlike any other in the game. It's quiet in a way other shelters aren't. The light cycles naturally, dimming and brightening in a slow rhythm that no other location in the game has. Characters who rest here recover faster than anywhere else. The Rest Cycle Module is built into the shelter itself, part of its structure, maintaining a natural rhythm in one small space while the rest of the world's timing has broken down. The player doesn't "take" this component the way they take the others. They identify it, understand what it does, and disassemble it carefully. The shelter loses its special properties afterward. The one perfectly restful place in the game is sacrificed for the cure.

**Puzzle concept: systematic persistence under enemy pursuit.** The hidden shelter is behind a sequence of locked doors in a multi-room section of Zone 2. Each door is opened by a specific interactable somewhere in the section: maintenance panels, junction boxes, terminals, all of the same or similar model. There are many more interactables than doors. Most interactables do nothing relevant, or they open doors elsewhere that are not on the critical path. The section is patrolled by enemies on cycling routes that the player can learn but cannot eliminate.

The player has to systematically test interactables, note which ones opened which doors, backtrack through enemy patrol patterns, and try again. Each attempt costs time and resources (stamina to dodge patrols, HP if caught). The player can leave and come back, but the enemies reset. There is no trick, no hidden information layer, no character-specific perception that reveals the answer. The puzzle is pure trial and error under pressure. The correct sequence is discoverable only through persistence.

**Design note.** Commitment is not the dramatic choice. It is the undramatic one. It is the choice to keep showing up when nothing is working yet and there is no guarantee it will. The puzzle is not hard because it is mechanically complex. It is hard because the game is actively discouraging the player from continuing. The enemies are the game asking "are you still here?" The answer, every time the player returns and tries another panel, is yes. The hidden shelter, the best room in the game, is the reward for the least glamorous puzzle in the game. (Full room layout, interactable count, and patrol patterns TBD.)

**The hidden shelter scene.** The first time the party rests here, before the player has any reason to disassemble anything, a unique shelter scene triggers. It is the only purely lighthearted scene in the game.

The natural light cycle makes the characters drowsy in a way they haven't been anywhere else. The scene is low-stakes, warm, unstructured. Characters talk about nothing. Myke complains about the food, then admits he's eaten worse. Tyreg, who is precise about everything, turns out to be precise about terrible jokes: she delivers them with perfect deadpan timing and doesn't understand why nobody laughs, which makes them funnier. Aster starts explaining something technical about why the light cycle feels different here and Peris falls asleep on his shoulder mid-sentence. He stops talking. He doesn't move. Oli, who has been quiet the entire game, says the most they've ever said in one stretch: a dry, unhurried observation about the infrastructure in this shelter, how the wiring hums differently here, how the atmospheric readings are the best they've seen, how whoever built this place actually knew what they were doing. It sounds like a maintenance report. It's a love letter to a room. This one is the best. Obviously.

If Endo is in the party (the player convinced him to leave his junction), he does something the player hasn't seen before: he sits down. He's been standing or braced at every other shelter. Here, he sits. That's his review. The player who went through the effort of reinforcing his junction and bringing him along gets this tiny, wordless payoff: the silent character finally resting.

### 10.5 The rogue tenth component

A tenth component exists in the world's history but not in the player's collection: the rogue component that destroyed Loca and triggered the Act 1 boss situation. Its identity is open in the boss spec; its existence is canonical and load-bearing for Loca's encounter, the Act 1 watchtower scene, and the broader story of why the cure project went wrong. Full context and current open questions live in `loca_boss_spec.md`.

Briefly: the component initially showed promise via an unknown mechanism; Loca was the lead researcher, Plexa a junior collaborator on the distribution-mechanism component. A third party noticed the component had a side effect of enhancing the performance of microglial workers (Myke's class) at clearance work. Productivity gains were significant. From there, the work was redirected toward exploitation. When Loca recognized what had happened, she asked Plexa to kill her; Plexa refused, then improvised a containment that turned Loca herself into the substrate for sequestering the rogue component. The wires/tangles the player sees in the boss chamber are this containment, ambiguous as to whether they are protecting the body from her or her from herself.

The rogue component is canonical evidence that the cure's components, used outside their intended therapeutic context, can be weaponized against the population they were meant to help. The party retrieves the nine. The tenth is what happens when the institution gets involved in something it does not understand the stakes of.

### 10.6 The cure as encoded relationship

The cure creator studied relationship therapy during her philanthropic phase. The nine components reflect her actual framework for understanding human connection: the chemistry needed for two people, or two cells, or two parts of a single mind, to function together. Each component encodes one aspect of that framework, made into a piece of biology that the body needs in order to repair its own coordination.

The cure is not a metaphor for relationships. The cure IS her understanding of relationships, encoded into biochemistry, scattered across her own mind. The player traverses her brain finding the components of how she once thought love worked, biologically expressed as the things her brain needs to keep working. The civilization's failure is the failure of the same coordination at a different scale. The same things that broke her relationships break her cells.

The framework is invisible architecture. Never named in-game, never explained by a character, never lectured to the player. Players still feel the rhythm without being asked to.

## 11. Bosses

Two mega-landmark boss encounters are canonical: Loca at the Act 1/2 boundary, the Paranucleus at the Act 2/3 boundary. A final encounter is presumed at the end of Act 3 but its specific design is not yet drafted.

### 11.1 Loca (Act 1 boss)

Working spec, partially settled. Section absorbs `loca_boss_spec.md` in full. Several major elements (the rogue component's identity, the watchtower's specific architecture, the boss fight's exact mechanics, where the broader lore is conveyed in-world) are explicitly open and flagged at the end.

#### 11.1.1 Position in the game

End of Act 1, at the Act 1 to Act 2 boundary. Geographically: between shelter 10 (Ancourage, Inflammashunt DZ junction) and shelter 11 (The Honeycomb Cooperative, where Oli joins). The party emerges from Ancourage's tail into open terrain, with a mountain rising ahead and a trail switchbacking up its face toward a watchtower silhouetted at the summit. Approach choreography, dialogue, and Myke's unleash sequence up the trail are documented in `processing_station_scene__1_.md`.

Party composition at first encounter: Aster, Peris, and Myke (if recruited at shelter 9). Endo has departed, Oli has not yet joined, Tyreg has not yet joined. A Myke-absent variant exists for players who declined Myke at shelter 9.

The Act 1 boss is not the Paranucleus. The Paranucleus is the Act 2 boss, sitting at the 9 o'clock Filtration crossing where the spray gates the Act 2 to Act 3 transition. The processing station scene doc has a stale design note about the Act 1 boss being the Paranucleus that needs to be updated when this spec stabilizes.

#### 11.1.2 Who Loca is

Cell type: locus coeruleus neuron (Locus Coeruleus Classification, in institutional vocabulary).

Name: Loca. Short-clipped, fits the project's character-naming convention (Aster, Peris, Endo, Myke, Oli, Tyreg, Plexa). Embeds the locust/locus pun. Reads in Spanish as "crazy," which lands later as wry self-irony, institutional dismissal, or both.

Voice register in original conversation: supportive PI. Builds people up rather than tearing them down, treats junior colleagues as colleagues-in-training, gives credit and takes blame, rigorous scientifically and humane interpersonally, fights for her people institutionally.

Role in the cure project: Plexa's mentor and senior collaborator. Loca produced the first batch of cure components. Plexa worked with her on the distribution-mechanism component from the start.

Why an LC neuron specifically. The locus coeruleus is one of the first regions to degenerate in Alzheimer's, often before cortical pathology shows. An LC neuron is the cell that would have noticed the disease before the rest of the body did, simply by watching her own population die. She came to the cure project as a neuroscientist studying her own kind. She recruited Plexa from the choroid plexus side because Plexa's cell type is the delivery mechanism: choroid plexus cells produce CSF and regulate the blood-CSF barrier, which is how any circulating cure has to be distributed. The partnership is biologically load-bearing: the cell that detected the problem teaming up with the cell that controls distribution.

A sentence the player can eventually parse: she found the disease by watching her neighbors die, and she found Plexa because Plexa was the only one who could carry the medicine.

#### 11.1.3 The boss visual

A neuron in agony in a chamber at the top of the watchtower, with wires/tau tangles stemming from her and connecting to her, ambiguous as to whether the wires/tangles are pathology, protective measures, or both. The fever-dream-with-biological-referent principle is doing its highest-difficulty work here: the same physical thing reads as institutional cabling (the watchtower's signal infrastructure, scan-grid wiring, comms relays) and as tau pathology (paired helical filaments encasing a neuron). The player who reads the world as a sick body sees tangles. The player who reads it as institutional infrastructure sees wires. Both readings are correct. Neither resolves.

The watchtower is vertical and multi-level. The party enters at the bottom and must ascend through the tower's interior to reach Loca. Loca is not visible from the entry point; she is at the summit, in her bound state, and the only way to her is up.

The defense-or-disease ambiguity reads in three layers, none of which the encounter resolves cleanly:

1. Are the tangles the protective measures she took, or the rogue component's effect?
2. Even if they were her protective measures originally, are they still functioning that way, or have they decayed into the pathology they were meant to bind?
3. Did the rogue component actually get contained, or is the player about to release it?

The chamber's institutional register matches the simulation boundary checkpoint: clean-lined, reinforced, cool blue institutional lighting visible from a long way off. The blue is biologically meaningful (locus coeruleus is named for the neuromelanin pigmentation that makes it blue) rather than a generic palette choice.

A locust swarm fills the watchtower's lower and middle interior, blocking ascent to Loca's chamber at the top. The locusts are not extensions of Loca's arousal pattern. They are other enemies that came to feed on her corpse-state, drawn by the metabolic signals her bound body still emits. They cannot reach her (the containment holds at the top), they cannot leave (the signals keep drawing them back), and they have packed the tower's interior corridors and rooms while attempting to converge on her position. Tissue contact with her would expose them to the rogue component, which begins to affect any organism that touches the bound state. The locusts the player sees in the tower are scavengers in the early-to-mid stages of being changed by what they were trying to eat. They are victims twice over: once for being drawn here, and again for being affected on arrival.

Which existing enemy class the locusts derive from is open. Gnawers fit the canonical scavenger profile and are the natural candidate, but a new species (or a transformed variant cosmetically distinct enough to read as "locust" rather than "Gnawer") is also viable. The species question is flagged in the open section.

#### 11.1.4 The handoff briefing (in-world artifact)

The player encounters an AI-summarized document of an audio communication between Loca and Plexa. The original was a conversation between mentor and student, captured under standard research transition protocol. The original audio was destroyed by the institutional pipeline. What remains is the AI summary.

The destruction was overdetermined: storage policy required compression and discard of source material, no one with authority flagged the conversation as exempt, and a worker reviewing the speech-to-text transcript skimmed it, judged it banal-looking, and forwarded it for summarization. None of the three failures was malicious on its own. The system's normal functioning, distributed across three roles, produced an erasure no individual was uniquely responsible for. The conversation looked banal because it was a conversation, conducted in the conversational register that two people who love each other use when one of them is dying. The institution can only hear what speaks in institutional register. Anything important enough to be said personally is automatically banal-looking to the apparatus that catalogs it.

What the player gets:

```
✦ Assisted Summary

Title: Continuity Transfer Briefing

Source: Single-session audio communication (22:17)

Speakers:
  Loca [LCR-1a]
  Plexa [CHR-1a]

---

Overview:

Ongoing research responsibilities have been transferred following an
operational incident affecting the principal researcher.

Operational incident:

A routine personal trial of components was initiated according to the
standard protocol, but deviated due to "Own flock, shift". The audio
after this becomes garbled and difficult to decipher. Excitement ensued
afterwards, to the degree that the lead researcher could "no longer
think straight". The lead researcher then called for protocol
termination, stating, "Please just end this." The junior researcher
declined, citing an inability to do so and deploying containment
protocol.

Continuity arrangement:

The senior researcher confirmed that her role as primary investigator on
the programme would not be sustainable going forward. Further requests
to terminate were issued, but denied by the junior researcher, who
insisted on switching to containment protocol.

---

For original audio or transcript copies of this communication, please
contact [Error: dynamic ID no longer valid].

---

Summary generated by Portcut. Originating audio communication processed
under the Voice-to-Document Indexing Pipeline. Audio file and
intermediate transcript consolidated under the Documentation Load
Reduction initiative, Office of Archival Efficiency. Audio retention
period: expired.
```

**The destruction the document performs.**

- "Own flock, shift" is the STT system's mishearing of Loca yelling "Oh fuck, shit" as a bunch of other stuff goes on around her. The AI quotes the garbled phrase as if it were a meaningful technical descriptor of the deviation. The AI cannot recognize the phrase as nonsense because its job is to extract content, not to evaluate whether the content is real. The reader who decodes "Oh fuck, shit" gets the moment unmediated, the only fully unmediated moment in the document. The AI-flattening apparatus completely defeated by its inability to parse a swear word.
- "Excitement ensued afterwards" is clinical-chart language for behavioral agitation, aggression, violence. The AI is using a real medical euphemism that means what you'd find in a psychiatric admission note. The phrasing is almost comically restrained for what it's describing. "Excitement" is the AI's word for "she was no longer in control of her own body."
- "Please just end this" is the kill request, plain. Framed by "called for protocol termination, stating," which is the AI's most procedural verb construction for a dying woman asking her student to kill her.
- "Citing an inability to do so" is Plexa's refusal flattened. "I can't, I won't, I won't kill you" rendered as "an inability to do so."
- "Further requests to terminate were issued" is the repeat asks. The negotiation went on. Loca asked again. Plexa refused again. Multiple times. The AI renders this as plural-procedural ("further requests... were issued"), the worst possible verb construction for what was actually happening.
- The "you've been ready, just do it" line reads two ways once the player has the context: encouragement to lead the project, and instruction to perform the euthanasia. The summary commits to the first reading via "expressed confidence in the junior researcher's readiness." The shadow meaning is recoverable.

A small wording flag: the second mention of containment protocol uses "switching to," which is slightly more self-aware than the desired register. The first mention was changed from "resorting to" to "deploying" to scrub the AI-self-awareness. The second instance ("who insisted on switching to containment protocol") may want a similar pass for consistency, though "switching" does specific work signaling Plexa's pivot from termination to containment. Open for review.

#### 11.1.5 What was happening when she sent the briefing

Loca was returning to research work, trying to escape the political chaos surrounding the deployment fallout (see "Wider story" below). She believed she was working with a clean instance of the component from her own original batch, of the kind she had been using for cycles. The instance was in fact compromised, swapped or sabotaged at some point in the chain. She used it on herself in a routine personal trial. The compromised component induced rapid behavioral disturbance: agitation, aggression, loss of cognitive coherence. As she became dangerous, she initiated the conversation with Plexa from her workstation (already partially containment-bound by that point, operating from a fixed position).

She asked Plexa to kill her. Plexa refused. Loca asked again. Plexa refused again. Plexa improvised a containment that turned Loca herself into the substrate for sequestering the rogue component. The wires/tangles the player sees in the boss chamber are this containment, ambiguous as to whether they are protecting the body from her or her from herself. Loca remains alive in the chamber, indefinitely sequestered, and has been for whatever stretch of time has elapsed between then and the player's arrival.

#### 11.1.6 The wider story behind the briefing

The handoff briefing is the focused incident. The wider context that produced the incident is much larger and is not in the briefing itself, by design. It is the lore the player accumulates from other environmental storytelling across the game.

The rogue component's history, in approximate sequence:

1. The component initially showed promise via an unknown mechanism. Loca was the lead researcher. Plexa was a junior collaborator on the distribution-mechanism component.
2. A third party noticed the component had a side effect of enhancing the performance of workers (microglia, Myke's class) at clearance work. Productivity gains were significant.
3. Loca and Plexa needed funding. They agreed to co-develop the component with the third party.
4. The component was completed. The third party deployed it. It worked at the productivity metric: workers became hyper-effective.
5. The hyper-effective workers cleared all reported issues in their environment.
6. Once there was nothing left to clear, the worker economy collapsed. Workers without work turned on each other and on the deployment infrastructure. Many instances of the component were destroyed in the chaos.
7. The reported issues that the workers had cleared were superficial. The underlying disease was untreated. With the workers now too few or too dysfunctional to maintain even the surface, incoming infection moved into the gaps.
8. During the chaos, the remaining instances of the component were sabotaged, stolen, swapped. The chain of custody became unreliable.
9. Loca, attempting to escape the political chaos and return to her cure work, took an instance she believed to be a clean version of her own original. It was compromised.
10. The handoff briefing.

Real-world inspiration: lecanemab and the Fc-mediated microglial clearance mechanism of anti-amyloid antibody therapies. The component engaged microglia (workers) to clear pathology. It worked at clearing surface markers. Microglia became hyperactive. Underlying disease untreated. New problems emerged from the mechanism itself. The clinical efficacy debate over lecanemab (modest cognitive benefits, ARIA hemorrhage side effects, ongoing scientific dispute about whether the mechanism actually addresses disease progression) translates almost directly into the NVU's institutional politics.

Labor reading: the cure was repurposed for productivity. The third party did not care whether the disease was being cured. They cared that workers were measurably more effective. Loca and Plexa needed funding, said yes, co-developed. The deployment "worked" by the productivity metric and catastrophically failed by the medical one. The cure made the workers useful enough to make themselves obsolete, and the system that depended on their usefulness collapsed when they ran out of work.

The rogue component is not one of the canonical 9 cure components the player collects through the game. It is separate, a 10th that was cut from the cure proper after the deployment disaster. The player never finds a clean version of it. It exists in the world only as the contained instance bound to Loca and as whatever residue lives in the locusts that have been exposed.

The component spreads via tissue contact. This is why the locusts that came to feed on Loca are now being changed: they tried to consume the contained body, contact-exposed themselves to the component, and started becoming whatever the component makes of microglia-class scavengers. The containment is therefore necessary but not sufficient. It holds Loca's body, but anything that touches the body still picks up the component's mechanism. Plexa's choice to contain rather than terminate kept Loca alive; it also created an ongoing slow leak through any organism that approaches the bound state.

Where the wider story is conveyed in-world is open. The handoff briefing alone is not sufficient. Likely vectors include: terminal logs in The Open Files Initiative or Beacon Hill (Aster's information trail), scattered fragments of pre-collapse research documentation, environmental storytelling in the watchtower chamber itself (worker-clearance traces, deployment infrastructure visible in the architecture), Plexa's own archive at the Root Archive in the late game.

#### 11.1.7 Implications for the boss fight

Myke's fire "failing" has a much simpler reading than the speculative microglial-recognition interpretation that earlier design passes worked with. The party enters the watchtower at the bottom. Loca is at the top, not visible from the entry. The locust swarm fills the interior between them, blocking ascent. Myke fires at the locusts to clear a path upward. His fire works on them. The wave does not. New locusts appear faster than he can take them out. His individual contributions are accurate, effective, and irrelevant at scale. The futility he realizes is the futility of fire-as-throughput against a wave that outpaces it.

The Myke "Oh" beat lands directly on his tangping arc. The boss fight is the worker's nightmare scenario made literal: the workload escalating faster than effort can compensate, the exact scenario tangping was a response to. He is recognizing not kin in the institution's design, but the moment he has been training to recognize his whole life. Fire harder won't fix this. The realization that working harder is not the answer, that the situation requires a different relationship to work entirely, is what tangping is about. The fight shows him this directly. Both the presented solution (the full party using the tower's affordances against the swarm) and the shadow solution (Aster and Peris alone, using the locusts' own ecology against them) are mechanical expressions of the lesson: the workload is the problem, not the work rate. Stop trying to outpace it. Change the conditions instead.

The existing scene canon in `processing_station_scene__1_.md` (the chamber the party enters has "the boss at the far end," Myke fires Flare at the boss, the flame "dies on the boss") is now stale. It assumes a single chamber with the boss visible from entry, which is no longer the structure. The scene needs a revision pass to integrate the vertical-tower geometry: the party enters at the bottom, the swarm is the visible threat, Myke fires on locusts (not on Loca), the flame works on locusts but the wave outpaces him, the realization arrives during the climb attempt. The dialogue beats (Myke's "Oh," the "I don't think this is... yeah" trail-off, Peris's reading of Myke during the recognition) can survive the spatial revision. The narration around the boss reveal needs to be rewritten.

The chamber at the top is the destination, not the encounter. Loca is bound and immobile there. Reaching her chamber happens after the swarm in the body of the tower has been dealt with. Whatever the player ultimately does about Loca herself (Phase 2 of the fight, currently TBD) happens at the top, in that quieted space.

The locust handling is layered along the canonical three-solution taxonomy from `design_principles_shadow_solutions.md`:

**Presented solution.** Uses the full party (Myke included). After Myke's initial fire fails to keep pace and the futility realization lands, the party shifts to using the tower itself against the swarm: routing around dense pockets, strategically isolating groups, and damaging them indirectly rather than burning them directly. The tower has the affordances for this. There is some flora that Peris can tend or deploy. There are old terminals Aster can hack (door controls, lighting, environmental systems). There are points of structural vulnerability the party can exploit (collapsing sections, drop hazards, infrastructure that can be triggered). Myke contributes where direct fire is appropriate (isolated groups, igniting flora-deployed catalysts, kindling environmental hazards) but is no longer the throughput engine. The presented solution is faster than the shadow because the full party's toolkit is available, but it shares the underlying logic with the shadow: don't try to outpace the wave, change the conditions.

**Shadow solution.** Aster and Peris alone, no Myke. Exploits the locusts' baseline ecology: when isolated and at rest, the locusts cannibalize each other. The chain runs:

1. Aster strategically hacks doors in the watchtower's room layout to trap groups of locusts in rooms with no exit, sealing them off from the metabolic signal at the top.
2. The trapped locusts, denied access to Loca's signal and unable to leave, eventually rest. At rest, they begin feeding on each other.
3. After enough time, the trapped population in each sealed room has substantially reduced its own numbers through cannibalism.
4. Peris handles the survivors with flora (specific species TBD; candidates include Hushblooms for stunning, Tanglers for binding, Flure variants for redirection).

The shadow solution is slower than the presented path, requires patience and careful door-routing, and rewards mastery of the watchtower's vertical geometry. It does not require fire. It uses the locusts' own behavioral patterns against them. The thematic resonance is dense: the shadow solution lets the rogue component's victims consume each other while the party waits, which is an uncomfortable but accurate description of what trapping a contagious population does. The player is not killing them. They are letting the locusts finish what Loca's containment started.

Phase 2 (engaging Loca herself, after the swarm is cleared and the party has reached the top) is currently TBD. Possibilities range from "the chamber goes quiet and the encounter is effectively over, the player walks out with the AI summary in hand" to "a final puzzle layer addresses the wires/tangles directly." Either reading is consistent with what's been settled.

Plexa's filial position is also load-bearing for the post-fight beat. Plexa is the inheritor of the cure project, finishing work handed to her by a teacher she could not save. The player has been collecting another woman's lifework without knowing it, and using it to build something her student couldn't finish alone. When Loca's identity reveals (via the handoff briefing or other lore), Plexa's eventual state in the late game becomes a parallel structure: the student carrying her mentor's incomplete work, possibly heading toward a parallel sacrifice.

#### 11.1.8 What's still open

- The existing scene canon in `processing_station_scene__1_.md` (boss visible "at the far end of the chamber," Myke fires Flare at the boss, flame dies on contact) is now stale and needs revision to integrate the vertical-tower geometry. Specific revision pass to be scheduled.
- What enemy class are the locusts derived from? Gnawers transformed by exposure to the rogue component (using the existing scavenger ecology, transformed cosmetically and behaviorally), or a new species specific to the watchtower? Naming, visual register, and stat profile depend on the answer.
- Whether contact contagion is a gameplay risk to party members. Can a party member who gets too close to Loca's bound body pick up the component's mechanism? If yes, this is a meaningful hazard layer in the chamber. If no, the contagion is enemy-only and the party is safe to approach.
- Watchtower physical architecture beyond "institutional, clean-lined, reinforced, cool blue lighting." How does the watchtower as building map to LC neuron biology? Triangular pyramidal-neuron tower? Something else? What specifically is in the chamber besides Loca and the wires/tangles? Room layout matters for the shadow solution since door-hacking depends on geometry.
- The presented solution in detail. Confirmed at the level of "Myke's fire works on locusts, fails on Loca," but the specific wave structure, fuel economy, and Aster/Peris contributions during the presented path are TBD.
- Phase 2: what (if anything) the player does about Loca herself after the locust swarm is cleared.
- Where the wider lore (third-party deployment, worker collapse, sabotage chain) is conveyed in-world. Multiple terminal logs across multiple regions? A single reveal? Plexa's archive at the Root Archive?
- Loca's post-fight state. Does the encounter end with her quieted but still alive (and the chamber dim, the wires dormant, the player able to revisit her), or does it resolve into a corpse and a closed chapter?
- Does Loca speak during the fight? Is the chamber silent except for the wires occasionally lighting up when she shifts? Does she try to speak through the rogue component's interference?
- Whether the wording fix on the second containment-protocol reference is needed for register consistency.
- Whether the `processing_station_scene__1_.md` doc gets updated now (to remove the stale Paranucleus-as-Act-1-boss reference) or once Loca's design stabilizes further.

### 11.2 The Paranucleus (Act 2 boss)

The encounter is preceded by the Ouroboros scene, planned for Aster and Peris and placed at the transition into it, with the camera shifting during the beat into the Paranucleus's puzzle-specific setup. Aster and Peris discuss the ouroboros, the snake eating its own tail. They feel trapped like the tail, caught in cycles of history repeating itself. The structural pivot in the scene is a joke about how the ouroboros must eventually be eating its own shit, since the loop digests and re-consumes its own material, so the consumer is consuming the degraded form of what they already had. One of them wonders if it ever gets tired of the taste. The joke does double work: it acknowledges the closed-loop entrapment, and joking about it is itself a small move outside the loop that the loop cannot fully absorb. The joke also softens the philosophical weight before the secret-sharing that follows. From there: Peris asks Aster if they can keep a secret, something the world cannot take away from them or impose its will on them to remove: the secret that the world CAN change, and that they are not doomed. Derrida's *Donner la mort* (*The Gift of Death*) territory: the secret as the relation to the absolutely other, kept and inalienable, the secret as the condition for responsibility. Which character cracks the joke is a tonal choice with character-arc implications. Peris cracking lands as her playful register (the sing-song mnemonics, the "Ooh! How vintage!" beat). Aster cracking lands as the analytical character being unexpectedly funny, and the recognition Peris meets him with becomes the bridge to the secret. The beat does multi-axis transition work simultaneously: character/relationship transition through the secret-sharing, location transition from the pre-Paranucleus section into the encounter itself (section 11.2), camera mode transition into the boss-encounter setup, and thematic priming for the Paranucleus's contemplative ophanim-register navigation. Specific dialogue not yet committed.

Working spec, partially settled. The Paranucleus is the Act 2 boss, located at the abandoned NUTECH spray facility at the Act 2/3 boundary. The encounter is a structural gate (binary outcome: retrieve the spray and cross, or fail to retrieve and cannot proceed). It is contemplative rather than combat-focused: an environmental navigation puzzle through an ophanim-register protein aggregate that has grown around an institutional ruin.

Canonical content for this section is currently scattered across past chats (a `nutech_facility_encounter.md` was drafted in a past session but is not in the current project file set). Several elements (full ring count and rotation parameters, where Climbvine first introduces in Act 2, exact post-encounter barrier scene staging) are flagged in section 11.2.7.

#### 11.2.1 Position in the game

End of Act 2, at the Act 2/3 boundary. Geographically: the facility sits at the outer edge of Zone 2, near the Bulwark Wharf barrier crossing but distinct from it. The party reaches the encounter via a detour off the main path before the barrier crossing. After completing the encounter, they return to the main path and apply the retrieved spray to the Bulwark Wharf barrier, which disrupts it and lets them cross into Zone 3.

Party composition: the full party available at this point in the game (Aster, Peris, Myke, Oli, Tyreg). Endo is optional depending on whether the player re-recruited him.

The encounter's outcome is binary: the party retrieves the Lavender Lake bottle from the facility's central reservoirs, or they do not. Failing means they cannot cross the Bulwark Wharf; the structural gate prevents progression without the spray. This makes the Paranucleus a gate rather than a finale; the cure climax happens later, at the final boss. The Paranucleus is the political climax of Act 2.

#### 11.2.2 What the Paranucleus is

The Paranucleus is a monumental amyloid-paranuclei aggregate that has grown around the abandoned NUTECH spray facility. It is large enough to be a place rather than a creature: the player navigates through it rather than fighting it. It does not have a body in the conventional boss sense. It has architecture.

**Real biological referent.** Paranuclei (also called annular oligomers) are ring-shaped aggregates of misfolded amyloid protein that form before the larger fibrillar plaques associated with Alzheimer's disease. They are increasingly understood to be the most neurotoxic form of amyloid. They are rings. They are aggregates of misfolded protein. They are the early pathology of Alzheimer's disease at the molecular level. The encounter renders this biology at architectural scale: rings within rings within rings, the protein's molecular geometry made into a building.

**Visual register: ophanim.** The aesthetic reference is Ezekiel and Daniel's ophanim, the angelic order that appears as wheels within wheels, many-eyed, with the geometry of impossible perspective. Ophanim are wheels that do not work in a single perspective; they exist in the way divine geometries exist, with the geometry being the substance. The Paranucleus has this register. The rings are wheels; the rings' relationships are perspectival; the geometry produces paths that exist at certain alignments and not others. The aggregate has the multi-perspectival quality of ophanim without literally having eyes (the protein folds catch light and shadow in ways that suggest optical structures, but they are not eyes; they are the protein's structural reflectivity).

The ophanim register also carries religious-sacred connotation. The party encounters the aggregate the way ancient prophets approached divine presences: with awe, with the recognition that they are below its notice, with the understanding that the encounter is happening in a register that is not at their scale. The aggregate is too large to be defeated; the party's task is to read it, navigate it, and retrieve what they came for. The encounter is contemplative rather than confrontational. Section 4.5 documents the Paranucleus's visual specification at the world-map scale: bone-white and pale-lavender stacked rings rising vertically out of the landscape, monumental, dwarfing every other structure on the map; raised tooth patterns along the inner edges of each ring (amyloid plaque's protein-subunit register made architectural); deep purple shadows in the recesses; a faint pink-red core glowing from the deepest ring center. NUTECH industrial fragments preserved at the structure's base, partly engulfed by the amyloid growth, partly still legible as a working facility.

**Monument Valley as movement-and-perspective reference.** The encounter's navigation logic borrows from Monument Valley's perspective-puzzle grammar: paths exist at certain alignments and not others, what looks impossible from one angle becomes traversable from another, the geometry itself is the puzzle. The rings rotate; their relative positions create or close pathways depending on alignment.

#### 11.2.3 The NUTECH facility substrate

The Paranucleus grew around the NUTECH spray facility, an institutional manufacturing site for a discontinued line of body-of-water sprays. The product line included Lavender Lake (the canonical example, retrievable in this encounter) and Floral Spring (Peris's biographical artifact, see below). The sprays were used institutionally as ambient scent maintenance throughout the civilization for decades. They are the atmosphere the player has been smelling since the Plumbing.

The line was discontinued. The institution did not destroy the facility or the remaining stock; it abandoned them. The institution's strategy, here as elsewhere, was suppression-through-abandonment: don't actively destroy the property, just make it unreachable. The amyloid aggregate that grew around the facility is the consequence of that strategy. The institution made a place untendable, and untendable places aggregate. Amyloid pathology is what happens when no one is doing the maintenance work that keeps protein folding correctly. The institution withdrew. The aggregate filled the space where attention had been.

**The political argument.** The encounter renders the institution's pattern at scale. The NUTECH line was discontinued because (this is conveyed through environmental storytelling and lore breadcrumbs across Act 2) Peris's beloved Floral Spring scent had a property the institution did not want workers to have access to: one of the sprays disables a security feature in the institutional apparatus. The discontinuation was deliberate suppression. The institution removed the physical product from circulation precisely so workers could not use it for the security purpose. The simulation add-on remained, rebranded; the physical line ended. Peris saved up to license the simulation Floral Spring add-on as her connection to a memory she could no longer materially access. The political argument lands as confrontation: the player meets, at scale, what the institution discarded and why.

**Floral Spring's reservoir.** The reservoir for Floral Spring exists somewhere in the facility, but is conspicuously inaccessible (destroyed, sealed, or behind a path that does not align). Peris registers what she sees and the party moves on. No dialogue. The absence is the beat. Her biographical loss is staged as environmental storytelling rather than as a scene; she stands by the inaccessible reservoir for a moment, and the player who has been paying attention reads it.

#### 11.2.4 Encounter structure

The party descends through the facility's segmented architecture toward the central reservoirs. The encounter is structured as a series of segments, each with its own internal navigation puzzle, connected by checkpoint zones that contain naturally-growing Climbvine (level-state, persistent, the return-path infrastructure between segments).

**Ring rotation and the Climbvine tying mechanic.** The rings rotate. Jumping between moving rings without preparation causes lethal physics damage (the player gets crushed, falls through to lower rings, or is launched off the structure). The encounter's core mechanic is the Climbvine tying system: tended Climbvine produces vines (one per tended specimen, one hand slot per vine), which can be dropped between rings to mechanically couple them, freezing their relative rotation. The party can then traverse the coupled rings safely. Cutting the vine releases the coupling and the rings resume rotating independently. The puzzle is the cut-and-tie balance: the party needs certain ring alignments at certain moments, which means they need to tie some pairs while leaving others to rotate, sequence the cuts and ties carefully, and manage their hand-slot vine inventory.

**Climbvine, two operational forms.** Per section 8's flora canon: Climbvine has two operational forms in level design. *Naturally-growing* Climbvine is level-state, placed by the level designer at strategic checkpoints between segments, providing return paths that persist across the encounter. These are world geometry. *Player-planted* Climbvine is player-state, harvested and dropped during play to bridge specific surfaces as needed. These are temporary; if Peris dies during a segment, the runeback resets the player's planted Climbvine within that segment (naturally-growing Climbvine is preserved). The encounter teaches the player to manage their planted-flora carefully because the runeback consequences are direct. The visual design distinguishes the two: naturally-growing reads older, weathered, integrated with the surface; player-planted reads fresh, recently cut, distinctly placed.

**Climbvine prerequisites.** The encounter requires Climbvine fluency: the player needs a healthy tended Climbvine network in late Act 2 to enter the encounter with sufficient harvested vines. This means Climbvine must be introduced and made tendable somewhere earlier in Act 2 in a low-stakes context, before the encounter requires mastery. (Per section 8.1, first appearance is committed to the Plumbing Power Project in Act 1 on a side passage off the main corridor; the Act 2 reinforcement that builds toward the Paranucleus encounter is open, see section 11.2.7.)

**Aggregate interior perception degradation.** The aggregate's interior has degraded perception conditions. The standard character overlays (Aster's data layer, Peris's warm view) are dimmed inside the aggregate; threats and interactables read as blurred icons with unclear identifiers. The player's normal toolkit for reading the world is partly available, partly disrupted. This is the aggregate's structural reflectivity at gameplay level: the protein geometry interferes with the perception channels the rest of the game has trained the player to use.

**The shelter near the top.** A partial-rest shelter exists near the upper reaches of the facility, serving as the encounter's anchor. It is partial-rest quality (some recovery, not full restoration) and gives the player a save point and a regrouping space within the otherwise hostile aggregate.

**The retrieval target.** At the central reservoirs, the party retrieves a Lavender Lake bottle. The bottle is a held item, occupies one hand slot, and contains two applications. The player is not told the second application matters; they discover this at the final boss.

**The post-encounter barrier scene.** The party returns to the main path, reaches the Bulwark Wharf barrier, and applies the spray. The barrier is disrupted. The party crosses into Zone 3. Act 2 ends. The exact staging of the barrier scene (dialogue, environmental shift, who applies the spray) is open per 11.2.7.

#### 11.2.5 What the encounter teaches

**The institution's strategy is suppression-through-abandonment.** The NUTECH line was discontinued, not destroyed. The remaining stock was left at the abandoned facility. The institution's strategy was to make the property unreachable through abandonment rather than to actively destroy it. The aggregate growing around the facility is the consequence of this strategy.

**Care work is what holds against the institutional pattern.** Peris's flora work matters in the encounter (she locates reservoirs by smell, she tends Climbvine for the navigation). The party with strong flora infrastructure has more options. The institution's pattern produces aggregates that grow when no one is tending; the worker class's pattern is to tend, and tending mitigates aggregation.

**The civilization's death-mechanisms are interconnected.** Amyloid pathology, ferroptosis, iron dysregulation, neuronal decline, and BBB breakdown are not separate problems; they are one problem with multiple visible faces. The encounter shows amyloid; the post-encounter barrier crossing shows ferroptosis; the Welcombe Springs (Act 3) show iron dysregulation; the late-game encounters show neuronal decline. The civilization has many deaths because it has one disease.

**The Climbvine and runeback mechanics.** The encounter is the major teaching beat for Climbvine traversal at scale and for the runeback consequences of Peris-death within a segment. The player learns to manage their planted-flora carefully because the runeback consequences are direct.

**Real-world research framing.** The amyloid encounter pays off the broader research-frame the project is built on. The amyloid hypothesis in real Alzheimer's research has been controversial for decades; the field spent enormous resources targeting amyloid plaques while neuronal decline continued. The institution in TRAWF treats amyloid as one symptom among many; the actual death-mechanism is iron dysregulation and ferroptosis, with amyloid as the symptom that grew where the institution withdrew. The encounter respects amyloid's biological reality without making it the sole or primary cause. The civilization has many overlapping pathologies because the regulatory systems that would have kept any single one in check have all failed at once.

#### 11.2.6 The second application

The Lavender Lake bottle holds two applications. The first is consumed at the Bulwark Wharf barrier crossing. The second is foreshadowed for the final boss's barrier; it disables a security feature in the final encounter. The player who reached the central reservoirs at the Paranucleus has the spray; the player who failed to retrieve it cannot cross the Bulwark Wharf at all and is structurally blocked from progressing.

This means: there is no way to reach the final boss without having retrieved the Lavender Lake bottle. The bottle's second application is therefore guaranteed to be available at the endgame. The narrative load on the second application (one of the sprays disables a security feature in the institutional apparatus) lands at the final encounter as recognition rather than as discovery. The player who paid attention to the lore breadcrumbs across Act 2 understands what is happening when the spray is applied at the endgame; the player who did not still gets the gameplay benefit. The narrative argument lands at the final encounter regardless.

The discontinuation of the NUTECH physical line is recontextualized by this mechanic: the institution removed the physical product from circulation precisely so workers could not use it for the security purpose. Peris's biographical loss (the discontinuation that left her with only the simulation add-on as her connection to Floral Spring) is the personal face of an institutional suppression strategy. The grief was political all along.

#### 11.2.7 What's still open

- A dedicated `paranucleus_boss_spec.md` parallel to `loca_boss_spec.md` should be authored to consolidate the canonical content currently scattered across past chats. The previously-drafted `nutech_facility_encounter.md` is not in the current project file set and may need to be surfaced or rewritten.
- Full ring count and rotation parameters. How many rings the aggregate has at gameplay scale. What the rotation periods are for each ring. Which alignments produce navigable paths. How the player reads the rotation pattern.
- Where Climbvine is taught in Act 2 to build toward the encounter's Climbvine fluency requirement. The Plumbing Power Project first appearance (section 8.1) is committed; the Act 2 reinforcement (a low-stakes hidden area where the player can practice tending and harvesting at scale before the encounter requires it) is not yet placed.
- The `scent_gate_scene.md` (the spray-disables-barrier mechanic motivating the encounter) is referenced in past chats but is not in the current project file set; it should be surfaced or re-authored.
- Lore breadcrumbs across Act 2 that point toward the institution's reason for discontinuing the NUTECH line. The encounter's political argument depends on the player having absorbed enough breadcrumbs to recognize the discontinuation as suppression rather than as commercial decision. Where exactly these breadcrumbs are placed (terminal logs in The Open Files Initiative, environmental storytelling in Cleanstreets, Peris's vintage scent memories) is open.
- The post-encounter barrier scene staging. Who applies the spray (Peris's biographical relationship to the product makes her the natural choice, but the scene's emotional weight may want a different staging). Whether the barrier crossing is its own scripted beat or a continuous flow from the encounter exit. What the moment of crossing looks like (sudden change in environmental register, a visual signature for the membrane disrupting, a dialogue beat acknowledging the threshold).
- Whether the encounter has any combat at all. The current spec is contemplative-only (navigation, perception management, Climbvine tying); no enemies in the aggregate proper. Whether some of the institution's surviving systems still operate at the facility's outer edges (residual security, automated processes the institution didn't bother to shut down) is an open question that could add tactical texture without changing the encounter's contemplative core.
- Plexa's relationship to the encounter. Plexa is the Mother Flure character who runs the choroid plexus side of the cure project (see section 11.1 for her relationship to Loca). The NUTECH facility's product line predates the cure project but operated in the same institutional environment. Whether Plexa has any direct connection to the facility, or whether the encounter is purely about the institution's commercial-versus-medical apparatus, is open.

### 11.3 Final encounter

[TODO: Pending. The end of Act 3 has the cure assembly, the four endings (per section 13), and the moment when the player presents what they have collected. Whether there is a discrete combat encounter, a puzzle, a dialogue, or something else is not yet specified. The four endings differentiate by completeness of cure, not by combat outcome, so a final boss in the conventional sense may not be the right shape. Design pass deferred until the cure assembly mechanics and the ending sequencing are spec'd.]

## 12. Major set pieces

Named scenes that anchor specific narrative beats. Each set piece has a dedicated dialogue or spec doc in the project files; this section captures GDD-level summaries (position, what happens, what it pays off, and design notes) and cross-references the canonical source for line-level dialogue and full mechanical spec.

### 12.1 The lockout chase (Act 1)

**Position.** Late Act 1 (around shelters 6-7, after the lockout-corridor approach to the simulation boundary). The party has been recovering through the easier mid-Act-1 stretch and approaches the simulation checkpoint to return home. Their tags fail.

**What happens.** The party reaches the simulation-boundary checkpoint. Aster's tag is rejected at the scanner. He tries again. Rejection escalates. Naturalizers (institutional enforcement) activate from concealed positions and pursue. The party flees back through the corridors they just came through, now hostile under chase conditions.

**Phase 1 (pre-Tyreg): pure environmental management.** Aster and Peris flee the Naturalizers using the corridor's environmental levers (Chelator clusters, doors, flora, terrain). Their skill from preceding zones is being tested in a hostile context.

**Phase shift: Tyreg arrives.** Tyreg catches up to the party from a side corridor. She has been Suppressing a second wave of enforcers closing in from another route; the player did not see this happening but learns of it now. Her ammo is low because she has been doing work offscreen to protect the party's escape path. The player can accept her help or decline.

**Accept path: Tyreg joins as temporary party member.** The chase continues as a three-character coordination puzzle. Aster hacks terminals for portal access to ammo caches, Peris runs ammo, Tyreg Suppresses when ammo is delivered. The chase is calibrated for the three-character party. Tyreg departs at the boundary with Endo's maintained section. Her parting line is brief and character-forward; she will see the party again in Beacon Hill, where the recruitment is the second meeting.

**Decline path: Tyreg departs.** The side route Tyreg was clearing is no longer cleared. A second wave of enforcers closes in from a side corridor. Difficulty scales significantly. Escape is possible only through a specific expert solution involving portal stunning via Hushbloom (a mechanic the player typically encounters in Act 2 or early Act 3, not in Act 1). The decline path is gated by mechanical knowledge the first-play player does not have. The game does not telegraph the solution. First-play decline players will typically fail and trigger the reset; expert or replay players can attempt the solution. Full expert-solution mechanics are in `chase_scene_framework.md`.

**Aftermath.** The party reaches Endo's maintained section at the boundary with Zone 2. Endo is at the wall, working on barrier maintenance. He notices their condition. The aftermath scene is quiet, exhausted, character-forward. Aster's tag rejection has changed his self-understanding: he was the reliable simulation worker, he is now something the system has classified out. Peris registers the change without naming it. Whether Tyreg is still present (accept path) or already gone (decline path) shapes the scene's composition.

**What it pays off.** The lockout chase pays off the Act 1 setup that something has been wrong with the institutional infrastructure (Aster's terminal data trail, Endo's maintenance work, the increasing siderophore pressure). The system's normal classification has decided against the party, and the party now understands that they cannot return to the lives they had. This is the point of no return for Act 1. The chase also introduces Tyreg as a character (in Phase 2) and her enforcement-class capabilities, which the player will encounter again later.

**Cross-references.** Full chase-scene mechanics, environmental-lever spec, accept/decline branch detail, and the expert-solution path are in `chase_scene_framework.md`. The scene's dialogue (approach, rejections, escalation, Naturalizer activation, the chase, the boundary standoff, the aftermath) is in `lockout_chase_aftermath.md`.

### 12.2 Mother Flure encounter (Act 1)

**Position.** Between shelters 5 and 6, per the revised Act 1 flow. The puzzle is the transition from The Open Files Initiative (industrial, Aster-centric) to the Greenfields Collective (inhabited, Peris-centric). Required path, not optional. Party composition: Aster, Peris, Endo. Endo is still with the party and has particular relevance to this puzzle.

**What it is.** A sliding-block puzzle at architectural scale. The party encounters a large, foundational mother flure in a chamber where her root system extends outward into the floor as permanent rectangular installations. Siderophores cluster around active roots and follow them as the roots slide. The player activates dormant root fragments to slide the roots along their lanes, clearing paths to the gear, the mechanism, and ultimately to the mother herself.

This is the first slow-puzzle in the game (persistent state, multi-move, no reset on retreat) and the first diegetic application of the Lot Clot mechanic that was planted in Endo's junction. Lot Clot was introduced as a sliding-block puzzle game scratched into the base plate of Endo's workbench. Aster dismissed it as wasted time; Peris read it as "a traffic jam, vintage." When the party enters the Mother Flure chamber, the spatial layout is immediately recognizable as a Lot Clot board at scale. Nobody says "this is Lot Clot" explicitly. The player recognizes it. Endo's demeanor subtly shifts; the silent companion becomes the silent expert.

**The mother flure herself.** A large, ancient flure at one end of the chamber. Visibly older and structurally distinct from any flure the player has seen. Floor-rooted rather than wall-mounted, several meters across, with a complex lattice of fibers supporting multiple bloom clusters. Closer to a tree than to a plant. She is in the chamber but the party cannot approach her directly. Siderophores surround her in the central lane configuration. The puzzle is how to clear them. She reads as stressed in Peris's overlay; figuring out what's stressing her is the puzzle's diagnostic beat.

**Mechanics.** The chamber's floor is organized into lanes. The mother flure's roots extend along these lanes as multi-cell rectangular pieces. Roots are permanent and biologically continuous with the mother. Activation is hold-to-interact: Peris activates a dormant fragment by being present at it, and the root slides toward and incorporates the fragment, retracting the cell at its trailing edge. Each slide takes roughly three seconds; siderophores follow at a similar pace, arriving at the root's new position about a second after the root settles. The party must route through the chamber while managing both the slide timing and the siderophore migration.

Activation commits to the slide. Peris cannot cancel mid-slide. She has the slide's duration to get out of the way before siderophores arrive at her position. Some lanes terminate at exit edges where roots can be retired permanently off the board, but retirement is a stronger move (some board states require it; most do not).

**The blooming reveal.** When the party reaches the mother and Peris tends her, the chamber's smaller offshoots illuminate. The mother and her root network are revealed as a single biologically continuous organism that spans the chamber. The reveal repositions everything the player just navigated as having been inside her body the entire time.

**Evidence of previous caretakers.** Tool marks on the root installations where someone shaped or maintained them. Adjustments that were partially made and abandoned. A worn patch of floor near the mother where someone stood regularly. The evidence is physical, not documented. Whoever was here didn't leave records. (The previous caretaker, Plexa, is canonical; the player may or may not put this together. Plexa's full identity emerges later in the game, with Loca's spec at section 11.1 carrying the structural connection.)

**What it pays off and teaches.** The Lot Clot setup at Endo's junction. The first slow-puzzle pacing (the player learns puzzles can have persistent state and no retreat-reset). The first character-specific puzzle role for Endo at scale (his perception layer reads the puzzle differently from the others). The first diegetic confrontation between the institutional infrastructure and a single ancient flora individual being kept alive by deferred care. The encounter is also the structural teaching beat for what flora at scale means in this world: the mother is not an enemy, not a quest target, not symbolic. She is a person Peris's class has been tending across generations.

**Cross-references.** Full puzzle spec (lane geometry, root sizes, retirement mechanics, combat layer generated by retirement, dialogue beats, the worker-body discovery, the post-bloom dialogue, exit conditions) is in `mother_flure_spec.md`. Scene-level dialogue is in `mother_flure_dialogue.md`.

### 12.3 Endo at the wall (Act 1)

**Position.** After the Mother Flure chamber, in the corridor between the chamber and the next stretch toward the simulation boundary. Endo's home barrier section is here; he stops to do maintenance work the party did not realize he was responsible for.

**What happens.** The party leaves the Mother Flure chamber. Endo leads them through a corridor that opens onto a stressed barrier section. The wall is failing in places visible to the player. Endo stops. Without speech, he begins working: examining the wall, applying compounds, reinforcing with materials he was carrying. The party waits. The scene is paced for stillness. Aster watches Peris watch Endo (the arrow flip: Aster usually being the observed, now becoming the observer). The Mother Flure they just left registers in data-frame on Aster's overlay as a continuous presence behind them; Peris translates what the data is reading. Endo finishes. The party continues.

**What it pays off and establishes.** Endo's identity as the wall-maintenance class becomes load-bearing here. The player understood him as a survival guide; the scene reveals he is also, primarily, a worker with a place. The wall is his place. The departure choice he will offer the party at shelter 6-7 (whether to reinforce his junction so he can stay or convince him to leave) is set up by this scene. The arrow flip moment (Aster as observer rather than observed) is one of the small character beats that registers his cognitive style noticing relational texture for the first time. Peris's translation of what the data is reading establishes their working dynamic for the rest of the game: Aster sees data, Peris translates it into texture.

**Cross-references.** Scene dialogue and pacing notes are in `endo_wall_scene.md`. The companion arc that this scene anchors is summarized in section 3.3.

### 12.4 Processing Station Sequence (Act 1, end)

**Position.** Final approach to the Act 1 boss facility. After the Inflammashunt junction (whether the player took it or not). Before Oli joins. Party composition at first encounter: Aster, Peris, Myke (if recruited at shelter 9). Endo gone, Oli not yet joined, Tyreg not yet joined. A Myke-absent variant exists for players who declined Myke at shelter 9.

**What happens.** The party approaches a mountain trail leading to the watchtower facility at the summit (Loca's chamber, see section 11.1). The decision-and-split beat: the trail is exposed and dangerous; Myke proposes to lead the climb because he knows this kind of terrain from his maintenance routes. The unleash up the trail follows: a movement sequence with Myke at the front, the party covering. Climbvine planting at strategic points along the switchback creates the return-route infrastructure that will matter if the encounter goes badly. The watchtower facility reveals at the summit, institutional-blue-lit, and the party enters.

**Myke's fire rendered moot.** The previously canonical version of this scene had the watchtower as a single chamber with the boss visible from entry, Myke firing at the boss, and the flame dying on contact. That version is now stale per section 11.1.7. The new structure: the watchtower is a vertical multi-level tower; Loca is at the top in her bound state; the locust swarm fills the interior; Myke fires at locusts (not at Loca); the fire works on them but the wave outpaces him; the futility realization arrives during the climb attempt. The dialogue beats for the realization (Myke's "Oh," the "I don't think this is... yeah" trail-off, Peris's reading of Myke during the recognition) survive the spatial revision; the narration around the boss reveal needs rewriting.

**What it pays off.** Myke's tangping arc lands here mechanically. The boss fight is the worker's nightmare scenario made literal: the workload escalating faster than effort can compensate, the exact scenario tangping was a response to. Fire harder won't fix this. The realization that working harder is not the answer, that the situation requires a different relationship to work entirely, is what tangping is about. The fight shows him this directly. The scene is also the teaching beat for Climbvine planting at scale (the strategic placement up the trail) and for the party's relationship to dangerous open terrain.

**Cross-references.** Full scene script (approach, decision, unleash, rejoin at the summit, Climbvine planting, watchtower reveal, fire rendered moot, into the boss fight, Myke-absent variant) is in `processing_station_scene__1_.md`. Connects directly to section 11.1 (Loca, Act 1 boss).

### 12.5 Stacks anxiety (Act 1)

**Position.** A rest beat in The Open Files Initiative (Act 1 mid, around shelters 4-5). After the party has been navigating the Open Files' terminal-data infrastructure and finding evidence of the institutional information cleaning. Party composition: Aster, Peris, Endo.

**What happens.** The party rests at a shelter in the Open Files. Peris breaks. The accumulated weight of seeing the cleaned-data terminals, hearing herself struggle to remember things she used to know, watching Aster's data layer reveal what the institution has been doing to information she handled professionally, surfaces all at once. She does not cry decoratively; she breaks down in the way a competent professional breaks down when their professional context has been revealed as a lie they were complicit in. She asks about Aster, specifically: she wants to know what he understands about her decline, whether his data view has been telling him things she has not been ready to hear.

**Aster responds.** Not with reassurance, not with deflection, not with the technical-mode cataloging he typically does under pressure. He answers her question directly. The answer is not what she was bracing for. He has been seeing the trajectory in her readings for some time. He has not been talking about it because she has not been talking about it. He was waiting for her to ask. His response is the first time in the game he speaks to her as someone whose private knowledge intersects with hers, rather than as the analytical voice running in parallel.

**What follows.** They sit with what was just said. The scene does not resolve. The shelter beat ends with the party deciding to move on; Peris's question has been answered, and what remains is the rest of the work.

**Cross-references.** Scene-level dialogue and pacing notes are in `stacks_anxiety_scene.md`.

### 12.6 Nustle / Nusselt scene (Act 2)

**Position.** Mid-Act 2, after Oli has joined, in a quieter shelter or shelter-adjacent rest moment. Party composition includes Aster, Peris, Oli at minimum.

**What it is.** A homophone-rooted scene that operates simultaneously at two levels: a worker-register affectionate noun ("nustle," what Peris means when she uses the word, derived from her experience of small physical comforts) and a technical homophone Aster mishears ("Nusselt," the Nusselt number, a dimensionless ratio in heat transfer that he recognizes because his data-overlay vocabulary is full of dimensionless numbers).

**What happens.** Peris uses the word "nustle" to describe what she is doing or what she wants. Aster hears "Nusselt," pauses, and translates the technical meaning he heard into her register, asking what she meant. She tells him. He registers that her word is the one he should have heard. The exchange is brief, gentle, and contains a mirror of "turned to rust / earned trust": two characters with different vocabularies discovering that the same sound carries different content for each of them, and finding that the difference is the texture of their relationship rather than a problem with it. The scene's payload is dual: the moment of misunderstanding is also the moment of meeting.

**Why it matters.** The scene is one of the game's purely warm moments. The late-game payoff of "turned to rust / earned trust" rhymes with this scene structurally; players who registered the nustle/Nusselt beat hear that later beat differently.

**Cross-references.** Concept and design notes are in `nusselt_nustle_scene.md`. Scene-level dialogue is in `nustle_dialogue.md`.

### 12.7 Marco set pieces

Marco appears across the game as a recurring NPC. Two of his appearances are canonical set pieces with dedicated dialogue; both demonstrate his deus-ex-machina structural role and his eccentric vocabulary (institutional-recognized practical technique rendered as fantasy-game spell language).

#### 12.7.1 Marco's Scarpet demonstration

**Position.** A Plaza in mid-Act 2. The party enters during a patrol lull. Marco is visible mid-drag, approaching a Scarpet edge. Party composition includes at least Aster, Peris, and ideally Oli (whose presence shapes some reactions).

**What happens.** Marco hits the edge of the Scarpet bed. He casts a spell (his vocabulary; the actual mechanism is applied botany leveraged through technique most institutional citizens have forgotten). The drag continues. Marco notices the party. A brief, optional exchange happens. Marco moves on. The scene is a Marco-encounter beat that introduces him diegetically to players who have not met him before, and reinforces his pattern (problem-solving-by-improvisation rather than by institutional method) for players who have.

**Cross-references.** Full scene dialogue is in `marco_scarpet_demo.md`.

#### 12.7.2 Marco's drag demonstration

**Position.** A separate scene later in Act 2 where Marco's role expands beyond the introductory glimpse. The party witnesses Marco performing a more complex operation, casts another spell, and the scene unlocks specific skills or abilities for the party as a consequence of having paid attention.

**What happens.** Marco reaches the end of his Scarpet bed and casts a spell. The party watches. The spell's effect is real and the party can analyze what he did. Peris and Aster process the demonstration in their respective registers (Peris reading the practice as care-work she recognizes, Aster reading the spell's vocabulary as a class of technique he had not categorized). Skill unlocks happen as a consequence of the demonstration.

**Why both Marco scenes matter.** Marco's structural role is non-joining deus-ex-machina: he appears, resolves a problem, demonstrates technique, and leaves. He never asks for reciprocity, never explains his mechanism, never demands the party engage with him on his terms. The set pieces establish that this pattern is reliable and that the party's relationship to him is observation rather than partnership. His vocabulary (spells, magic) is the diegetic register the institution lost when it stopped recognizing the practical knowledge he carries.

**Cross-references.** Full scene dialogue is in `marco_drag_scene.md`. Marco's design and his structural connection to Myke (same monocyte origin, two divergent survival strategies) are in section 3.7 and `marco_concept.md`.

### 12.8 Endo and Aster barrier scenes (Act 1)

Two paired scenes. The first, placed at the first-night scene at Shelter 1, has Aster observing that it must be uncomfortable for Endo to let two unfamiliar people into a space he maintains. The second, placed at Shelter 2 or 3 paired with the mechanical tutorial that introduces shelters healing damage, is the Aster stimming scene: Aster talks about how difficult it is to let unfamiliar things into his own head, and how he just wants to make it all legible. Derrida-of-Hospitality territory. Specific dialogue not yet committed.

### 12.9 The Psyknapse foil (Act 1 to Act 2)

Two scene paths gated by a single one-off encounter that uses level-design convention against the player. The encounter places a Psyknapse in the middle of the route, lit with spotlights and surrounded by floating particles, with the corridor's affordances arranged so the player naturally walks toward it and presses interact. The visual register reads as "important, engage with this" because games train players to interact with highlighted objects. That training is the lure. The obvious path takes Aster into the Psyknapse and triggers a cascade ending with the rest of the party dead and Aster alone with the spiralverse; the simulation completes its capture, he goes insane, his insights die with him. The shadow path is geometric and bodily: a narrow gap the level designer provides without highlighting, where the player can squeeze around the Psyknapse and continue without interacting. Refusing the institutional invitation is rendered as a physical act, the cramped unlit alternative that the conventional reading does not see. The advanced-player recognition is meta-knowledge from prior playthroughs (the player who has been through the death scene once knows not to enter) combined with present-moment alertness to register the squeeze-around affordance as available. The survival path triggers when Peris is alive at this encounter and reaches Aster before the capture completes; she pulls him out, and he reveals the insight he had been holding back, the "trickle clown effect" (long mechanistic chains with attenuating effect sizes producing insignificant final effects, the institutional capture pattern that lets correct predictions be received and processed and ignored, with the trickle-down pun as the punning theoretical name). The character-coherent reason for the holding-back is that Aster's analytical-pride identity codes the punning name as not serious, and his cross-class-envy training (section 5.7) has him assuming a worker like Peris would not engage with the theory as theory. The survival scene undoes both pieces of training: Peris pulling him out is the worker reaching across the register the simulation taught him to assume, and her receiving his theory as serious theory is the prediction (the worker will not engage) being proved wrong. The structural argument: analysis of the capture pattern can only be spoken to someone outside the capture pattern, and the same isolation that destroys him in the death path is what frees him in the survival path, with the condition being whether someone outside the pattern is present to receive the analysis. The shadow solution also exemplifies the trickle-clown-effect refusal before the dialogue names it: the conventional path runs Aster through the institutional tool (the Psyknapse) while the others occupy supporting roles, a long chain of mediated actions that produces casualties; the squeeze-around shortens the chain by refusing both the tool and the role-allocation, with the party staying together and bypassing the institutional encounter. The mechanic teaches the insight the dialogue later articulates. Party composition at the encounter is Aster, Peris, and Myke (Endo has departed at his junction in Shelter 6-7, Myke joined at Shelter 9, Oli has not yet joined). The death cascade kills Peris and Myke, leaving Aster alone with the Psyknapse. The v01 pod scene at Oli's corridor (Aster jacks into an open pod for ten seconds, sees the spiralverse, disconnects) is a later, safer variant of the same visual register; the pod scene works as the safer encounter because Oli is present and the pods are optional rather than positioned on the route, and the player who has been through the trap encounter approaches the pod scene with the register already established and Oli's presence reading as the safety condition the trap lacked. The encounter is a one-off rather than a recurring pattern. The Psyknapses across the rest of the game do not all use the spotlights-and-particles affordance signature; this specific encounter is where the convention is used as a trap. Marco's diminuendo death (section 3.7) is the game's existing convention-subversion, and the design budget for convention-subversion is scarce, which means the Psyknapse trap stays unique to land as recognition rather than as routine. The cues that the first-run player can catch include diegetic environmental storytelling at the encounter site and stylistic signals at the moment of approach. The diegetic cues are load-bearing: a corpse next to the Psyknapse, the previous occupant whose institutional capture completed and whom the institution did not record; a broken nutrient chamber that should have kept the Psyknapse occupant alive but did not. The broken-chamber detail also lands the End of History infrastructure decay (section 6.2) at this specific encounter, with the institution having stopped maintaining what its affordances depend on while the affordances themselves remain lit. The corpse-and-broken-chamber tableau parallels the v01 pod scene at Oli's corridor (the open pod with the previous occupant fallen forward dead), but with the support-system failure made explicit through the broken chamber, so the alert player reads not just "someone died here" but "the institution does not maintain what it captures." The stylistic signals supplement the diegetic load: the spotlights slightly off, the particle density slightly heavy, party-member reactions, an audio cue at the moment of entry, the squeeze-around path being visible if they look. The meta-knowledge vehicle handles the rest. The trap is designed around environmental storytelling and catches players who do not engage with environmental storytelling. The first-run player who has been reading the world's diegetic details throughout the game sees the corpse and the broken chamber, recognizes what they signal, and refuses the affordance. The first-run player who has been skipping past environmental detail walks past them and into the trap. The trap is the moment where engagement with environmental storytelling has direct gameplay consequences. The Plexa frame closes the loop: her preserved brain is literalizing the institutional capture pattern as level-design, the lighting that lures the player is the brain showing itself the institutional invitation, and the squeeze-around is the brain demonstrating that the invitation can be refused. The rarity of the showing is what makes the showing meaningful. Placement is committed: the encounter is positioned just before Oli joins the party, at the Act 1 to Act 2 transition (late Ancourage to early The Honeycomb Cooperative, between the Inflammashunt cure-component beat and Oli's joining at shelter 11-12). The act-transition timing gives the encounter narrative weight as a major test in the player's path through the game. Specific cues at the moment of entry not yet committed. Specific dialogue for the survival scene not yet committed. The same scene carries Peris's own recognition, that the clients of hers who were quietly reassigned were removals she signed the paperwork for and never questioned, which is the payoff of the dread planted in the Residential Rings (section 5.10).

### 12.10 Love is dimensionless (Act 2 to Act 3)

Peris and Aster are exhausted and feel out of their element. Aster remarks on how different everything is and how the truth doesn't feel like truth anymore. Peris brings up the word "love" and how it is just four letters, and how it sounds like the first part of "oven" with an "l" in front. She traces the meanings the sounds carried: the simulo ads about buying things to get girls and learning how to "speak the love languages," and how the meaning changed when Aster consoled her with the Augustine passage and told her it was the weight of the soul. She lands on the observation that it is crazy truth cannot always be spoken, that it is also in the space between words and what we think they mean. Aster picks up the thread: it is funny that to define "love" they used other words, which define themselves with still more words, and they could just keep going and going. Peris answers that it is all a bunch of relationships, like Aster's dimensionless numbers. Aster thinks about this for a while. Peris arrives at the realization that "love is dimensionless." The line lands here for the first time; Aster's late-game callback (see `nustle_dialogue.md`) quotes it back to her. Specific dialogue not yet committed.

### 12.11 The settlement that won its war and lost to the land (Act 3)

Position is Sunset Acres (shelters 23-24, the Dead Zones in the vernacular), late Act 3. This is an aftermath, read entirely off physical traces, signage, wreckage, and the dead, rather than terminal logs, following the failed-project environmental-storytelling spec in section 4.4. The history the player reconstructs runs like this. A Collective build stalled here, not from a decision to abandon it but from attrition no one understood. The original work crews fell prey to the land itself, killed without warning and one at a time, and because no one connected the deaths they never became a hazard, only a schedule that would not catch up. In the records the project read as perpetually behind, labor short for some reason, milestones slipping, the deaths dissolving into a productivity problem and never into knowledge. So there are no hazard signs anywhere, because there was never a hazard in the ledger, only a line falling further behind. Squatters, drawn by ground that read as resource-rich, moved onto the stalled site and built homes, knowing no more than the crews had.

The fight is the Collective's, and it loses it. Investigating why the project failed, the institution lands on the squatters as the cause, because the squatters are the only variable its instruments can see, the same blindness that produced no answer for the crew deaths now producing a wrong one. It moves to clear them and the squatters win, repelling the eviction and holding the ground. The win is the cruelty. They beat the institution and kept the land, and the land was the thing killing them the entire time, the same sudden attrition that took the crews and wholly indifferent to who held title. They defeated the wrong enemy. The hazard finished the settlement as it had finished the project, and the institution, having neglected the build into a stall and made one wrong-headed grab at fixing it and lost, went back to abandoning, this time the whole region, which is how Sunset Acres became a Dead Zone.

The ground the player crosses is a settlement that won its war and lost to the dirt. Repelled enforcement and a held perimeter sit beside homes the ground swallowed, a defiant place beside the mass grave the land dug, the eviction notice and the squatters' answer to it still on the gate, and no hazard sign anywhere, because no one ever knew. The dead are on both sides, the cleared enforcers and the squatters who beat them, rendered as the tissue's death rather than as gore. The hazard grounds in the one-disease-many-faces death-cosmology of section 11 without anyone in the fiction naming it: the region's barrier-vessels were failing, so they ruptured without warning and flooded iron where it does not belong, and the tissue that died liquefied into cavities that gave way underfoot. The bursts and the sinkholes both kill suddenly and at random, which is why the deaths read as accident and attrition rather than as one cause. The Dead Zone end-state needs no revision, since the terminal necrosis is the zone's sterility, dead to immune response and to flora alike (section 4.4).

Aster is the one who finally reads it, and only in the aftermath, the barrier-and-transport analyst diagnosing what killed everyone too late to warn a soul, which is the ignored-Cassandra register of his role (sections 3 and 5.10) at its sharpest, and it stays a spare recognition rather than a lecture. The scene is two-sided through shared blindness rather than through balanced grievance. Neither side knew; the Collective was withholding nothing because it had diagnosed nothing; and the killer is the blindness itself, the system that senses everything and knows nothing, here a build that never caught up. It lands the institution's signature suppression-through-abandonment (section 11) and the metric-blindness that turns deaths into slipped milestones, and it carries the seed it grew from, the adverse-possession case in its purest form, an absentee owner neither using the land nor releasing it, except that here the title it would not surrender was worthless and the ground it held was lethal. On the design side this is aftermath only, no live encounter and no terminal logs, the physical traces carrying the whole reconstruction; the exact signage text, the settlement layout, and the gate's placement within Sunset Acres are not yet committed; and there is no dedicated dialogue or spec doc yet, so this section is the source.

## 13. Endings

The game has multiple endings determined by gameplay, not by dialogue choices. What the player discovered, where they explored, who they recruited, and what they built determines the outcome. The shortest path through the game produces the worst ending. The most complete exploration of the most dangerous areas produces the best ending. This creates a natural tension: the degradation systems push the player to be efficient and safe, but the best outcomes require risk, thoroughness, and time spent in places the game makes terrifying.

The endings reward exploration and care, not combat skill. The player who treats the world gently, recruits everyone, finds every shelter, and assembles every component sees the people they love continue to be themselves. The player who rushes the main path watches them disappear.

### 13.1 Design philosophy

The easier endings are not "less good" versions of the harder ones. The easiest ending is a tragedy. The game withholds its fulfillment from players who do not risk enough to earn it, while still giving them access to the story and the experience of the world. The message is structural: the safe path, the efficient path, the path that avoids danger and minimizes time spent in frightening places, is the path where the third chapter never gets written.

**The paradox of pacing.** A direct-path run (Ending 1) might take 4-6 hours: the player experiences the core narrative beats, encounters the main characters, reaches the objective. The game is playable at this pace but unsatisfying by design. A thorough exploration (Endings 3-4) might take 20-30 hours: the player explores every zone, recruits every character, tends the full flora network, hacks every archive, completes every character's storyline. The in-game day count is higher, meaning the degradation is more advanced, meaning the late-game challenge is steeper. The player who takes the time to find the best ending also faces the hardest version of the game, because Peris has been declining for more days. The cure requires the disease to have progressed further. This is not a bug. It's the point.

### 13.2 The endgame return sequence

All four endings share a structural backbone: after the cure assembly (or the failure to assemble it) at the deepest shelter, the party travels back through the portal network to Zone 1, the simulation hub. The simulation is transparent for the first time. The curated overlays are gone. The infrastructure is visible through the simulation's surfaces: the rust, the corroding conduits, the failing barrier, all rendered in the same space where the residents have been living their curated lives. The residents are standing in their spaces, looking at walls they can suddenly see through, staring at corridors they never knew existed, watching maintenance workers they've never met walk past on routes that were always there but hidden.

The support crew is visible for the first time. Maintenance workers, barrier technicians, infrastructure monitors, the entire labor force that kept the simulation running. They are not entering the simulation space. The simulation space is finally showing that they were always there, on the other side of the walls, doing the work. The invisible people become visible. The maintenance class meets the people they have been keeping alive.

The entire game has been about a system that curates perception to suppress inconvenient reality. The final act is not curing one person. It is forcing an entire civilization to see what is actually happening. The override is the anti-simulation: instead of giving everyone what they want to see, it shows everyone what is there. The confirmation prompt, asking whether the operator understands this will cause distress, is the system's last act of care. The information quarantine was always framed as kindness. The override acknowledges that the kindness was the problem.

What the override produces depends on what the party brought. The four endings differ in what happens after the residents see.

### 13.3 The four endings

#### 13.3.1 Ending 1 (worst): the shortest path

**Path requirements.** Main path only. No danger zones. The player reaches the deepest shelter with only the Chaperone Lattice (found on the required path). Approximately 30 shelters traversed.

**The character collapse.** Aster refuses to accept reality. He has seen enough to understand that the world is failing, but not enough to know what to do about it. He withdraws. He hides. He becomes overwhelmed and afraid, but rather than acting on the fear, he retreats into abstraction: talking about the dread of existence, the nature of the world, the philosophical dimensions of decay. He has the data. He won't use it. He chose the dashboard over the corridor.

Peris, who has been declining throughout the game, feels ignored. She needed Aster. Not his analysis, not his frameworks, him. His withdrawal reads to her as neglect, and as her condition worsens, her ability to distinguish between neglect and abandonment collapses. She stops understanding what's happening around her. She becomes confused, then frightened, then angry. The anger is directed at Aster, because he is the closest thing she can still perceive, and she cannot remember why he matters. She loses track of the other characters. She forgets who they are. One by one, the faces stop meaning anything.

Eventually, Aster comes to her. He has something to say. Maybe he's finally ready. He approaches Peris, and she looks at him with no recognition. Everything they built together, every shelter conversation, every book fragment, the Augustine passage about love being the weight of the soul, none of it is there. She has lost everything except the most recent emotional impression, and the most recent emotional impression is resentment toward a stranger who wasn't there when she needed him.

**Her last line.** "All I know is I hate you."

**The override.** Without the cure, it is disclosure without remedy. The residents see the decay and have no way to address it. The truth without the tools to act on it. Aster showed them the dashboard, and the dashboard shows a dying world.

**The visual collapse.** Aster breaks down. The world distorts. The environment fragments into corrupted data geometry: the dashboard he retreated into was the only lens he had left, and now that lens is cracking. The visual language of his perception (the blue schematic, the data overlays, the infrastructure readouts) tears apart. He is trying to dissociate, to retreat one layer further into abstraction, but there is nowhere left to go. The screen holds on the distortion. Then it fades.

#### 13.3.2 Ending 2 (partial): partial discovery

**Path requirements.** Main path plus 2-3 danger zones. Some cure components found. Approximately 33-35 shelters traversed.

**The treatment.** A treatment is attempted. It slows Peris's decline but doesn't stop it. Enough cure components to understand the problem but not enough to solve it. The corridors still rust. The Naturalizers still patrol. The simulation still autocompletes. The pericyte is patched but the barrier is still failing. Personal salvation without structural change.

**Peris's state.** She is fading. She is not angry like in Ending 1. She is scared. She knows something is wrong. She can feel herself losing things but she cannot name what she is losing. She tries to tend the forget-me-nots at their shelter, the thing she has done at every shelter since Aster gave them to her. Her hands go to the flowers. She touches them. But she cannot remember what tending means. The motions that were automatic, the care that was instinct, will not come. She holds a flower and looks at it and does not know what to do next. She is not hostile. She is lost.

**Aster's response.** Aster still has some of the flowers Peris carried with her. Cuttings, loose stems, seeds caught in the lattice. He plants them. He tends them the way she would have, badly, with the wrong instincts, but he does it. When the grief threatens to pull him into the dashboard, when the impulse to retreat into abstraction rises, he holds the flowers and breathes. The smell grounds him. The rust going away. That's what she said when he first gave them to her. The scent is chelation, iron being neutralized, the chemical opposite of the decay eating the world. It's the lattice doing its job. It's Peris. Not a memory of Peris. The actual chemical trace of the thing she kept alive for the entire game. The data can be cleaned and normalized, but the scent of a flower is not data. It cannot be corrected away.

**The override.** Partial cure, partial clarity. The treatment slows the decline enough that some residents can process what they are seeing. The barrier stabilizes slightly. But the structural causes remain. The residents can see the problem, but the solution is incomplete.

**The last image.** Peris sitting next to the blue flowers, holding one, unable to tend it, afraid. And Aster nearby, tending the ones he planted, breathing them in, staying present. He doesn't break. He doesn't retreat. But Peris is still fading, and the flowers are the only thing keeping him in the world. The civilization continues as it was.

#### 13.3.3 Ending 3 (bittersweet): deep discovery

**Path requirements.** Main path plus most danger zones. Most cure components found. Approximately 36-40 shelters traversed.

**The treatment.** The cure is assembled but incomplete; it addresses symptoms without fully resolving the cause. Meaningful intervention. The civilization begins to reckon with its own decay rather than hiding it. But the damage already done cannot be undone; some characters are permanently changed. Hopeful but scarred.

**Peris's state.** Peris fades. Her memory goes. She loses track of names, places, what day it is, why they are here. But unlike Ending 2, the incomplete cure holds something. Not enough. But something.

Peris can still tend the forget-me-nots. Her hands still know what to do with them even when her mind doesn't know why. The motions are there: watering, arranging, pinching dead stems. She does it without knowing she is doing it. The care is deeper than memory. It is in her body, in her contractile fibers, in the part of her that was built to maintain things.

**The visitation.** When she tends them, when her face is close to the flowers and the scent reaches her, she comes back. The rust going away. The smell she named the first time Aster handed her the lattice, before she knew what it meant. The chelation. The iron being neutralized. The chemical signature of the cure working in miniature, carried by flowers she can no longer name but whose scent her body still recognizes. She surfaces. She looks up and recognizes Aster. She knows where she is and who she is with and what they did together. The scent holds her name, and when she breathes it in, she remembers.

Then she is gone again. It is not a cure. It is a visitation. The flowers cannot hold her permanently, but they can call her home for a moment. The shelters they slept in still have blue flowers. The corridors they walked still have traces of their passage. And sometimes, when Peris is tending the flowers and the scent rises, she remembers everything.

**The override.** Most of the cure is working. The treatment holds. The barrier is recovering. The residents watch the infrastructure starting to reverse its decay in some areas. Hopeful but unfinished. Peris comes back in flashes, recognizes Aster intermittently. The flowers bring her home for moments. Visitation, not cure.

#### 13.3.4 Ending 4 (best): complete cure

**Path requirements.** All danger zones. All nine components. All party members. Deep shelter scene engagement. The Resonator retrieved. The Lavender Lake bottle from the Paranucleus encounter still has its second application available for the final boss. Approximately 40-45 shelters traversed.

**The treatment.** The cure addresses not just symptoms but cause. The simulation's relationship to the physical world is fundamentally restructured. The barrier is restored not by hiding entropy but by acknowledging it.

**Peris recovers.** Myke's inflammation quiets. The civilization begins to remember what it lost. This ending should feel earned in a way that reflects the game's thesis: the cure was always there, distributed across the infrastructure, visible only to those who assembled enough perspectives to see it. No single character could have found it. The collective did.

**The override.** The full cure is active. The decay is reversing visibly. The residents watch the infrastructure heal in real time, the first time anyone has seen the system getting better instead of worse. The maintenance workers and the simulation residents are in the same space, seeing the same world, for the first time in the civilization's history. Peris recovers. She sees Aster. She sees the world as it actually is, and she sees it getting better.

**Then Aster writes the chapter.** He pulls out the Arendt fragment. The book with two volumes and a blank space where the third should be. He opens it to the empty pages. He writes.

He writes about how Peris might have started to lose her mind. About how, watching it happen, he started to lose his own, but differently. Not to decay. To something else. He lost his sense of reason. Not the capacity for it; he could still analyze, still read data, still build frameworks. He lost his commitment to reason as the only safe way to engage with the world. He stopped needing to understand before he could act. He stopped requiring certainty before he could care. He lost his mind for Peris, in the sense that he let go of the part of his mind that had been keeping him safe and keeping him alone.

He doesn't use the word love. He talks about how pure reason can describe everything about a situation and still miss the thing that matters. How you can critique every assumption, dismantle every framework, see through every illusion, and still not know what to do, because knowing what to do requires something reason can't provide. He talks about how judgment is not the application of rules to cases, but the capacity to act without rules in situations no framework anticipated. He says this clumsily, indirectly, in the language of a maintenance worker who has read fragments of books he doesn't fully understand. He doesn't know he is paraphrasing Kant. He doesn't know the missing third volume was going to be about exactly this.

He writes the chapter. It is not Arendt's chapter. It is not philosophy. It is one person's account of choosing to act without certainty, to care without safety, to risk the pull. It is incomplete and imperfect and it fills the blank pages with something that was not there before.

The screen holds on the book, open, with writing on pages that were empty for the entire game. Then it fades.

Hannah Arendt died at her typewriter on December 4, 1975, with the page for "Judging" still in the machine. She had completed *Thinking* and *Willing*. She never wrote *Judging*. The third volume of *The Life of the Mind* does not exist because its author died before she could write it. Aster holds a book whose incompleteness is not damage; it is death. The missing chapter was never written, not in any copy, not anywhere. The civilization did not lose this knowledge. It was never completed. Some things are not forgotten. They are simply unfinished. Aster, in the best ending, fills the blank not because he is replacing Arendt but because the missing chapter is the one piece of the cure that cannot be found in Zone 3 or assembled from the components. It has to be written.

The worst ending is a book with a blank third chapter. The best ending is the same book with the chapter filled in. The player who risked enough wrote it.

### 13.4 Two-character completability

The entire game, including all nine cure components, all six book fragments, and the endgame sequence, is completable with only Aster and Peris. No content is permanently locked behind party member recruitment. Every ability-gated interaction that is required to complete a puzzle has an environmental alternative somewhere in the world that Aster and Peris can access, though the alternative is always harder, slower, and requires more steps than the party member's ability it replaces.

Example: a late-game Zone 3 flora whose fruit is combustible can substitute for Myke's Inflame in puzzles that require fire. The player must tend the plant, harvest the fruit, and carry it back through re-spawned enemy territory to the puzzle location. The puzzle is identical. The logistics are completely different.

**Design principle.** If a puzzle step requires a non-Aster, non-Peris ability, an environmental alternative must exist. The alternative should be discoverable (the player can see the problem and reason toward the solution), logistically demanding (backtracking, item transport, longer hold times, lure-based enemy management), and never obscure. Party members make puzzles easier and faster. They do not make them possible. Aster's hacking and Peris's flora tending are the two abilities the game assumes.

The endgame sequence's difficulty scales naturally with party size because the encounter mechanics require both puzzle-solving and defense simultaneously: more characters means more capacity for both, fewer characters means the same puzzles with less margin. The Psy-Knapse defense section is the clearest example: six characters have a comfortable perimeter, two characters have a desperate lure-and-sprint loop. Both are solvable. Both are the same puzzle. The experience is completely different.

Achievement: "It Takes Two" awards completing the game with all nine cure components and all six book fragments using only Aster and Peris.

### 13.5 The decline-vs-compensation curve

**The decline curve (what gets harder).** Peris's vision baseline shrinks progressively. Siderophore count, HP, speed, and hit damage scale per shelter (one shelter equals roughly one day). NK patrol density increases. Shelter locks add management pressure. Zone 3 environmental damage is constant. The world gets worse every shelter the player passes through.

**The compensation curve (what the player gains).** Party members (up to six, each with unique abilities and perception layers). Flora network (species discovered through exploration). Portals (eliminating backtracking). Cure schematics (giving the player a goal). Shelter scene ability unlocks. Player knowledge (memorized patterns, learned enemy timing, understood terrain). The player gets stronger, but never fast enough to outpace the decline.

**The intended experience.** The decline slightly outpaces the compensation. A skilled, prepared player can navigate the endgame. The player who neglected shelter scenes, skipped recruits, or failed to establish portals will find the late game brutal. The player who invested in everything will find it demanding but achievable. The paradox: the best ending requires the most days spent, which means the hardest version of the game.

## 14. Achievements

Working achievement design. Locked achievements are committed; the candidate additions list is open and maintained as a brainstorm space. Full source: `achievements.md`.

### 14.1 Design principles

Achievements are invitations, not chores. Taglines carry weight: one line, emotional or funny, not description. Secrets stay secret (hidden name and condition until unlocked). No time-sink achievements (no "play for 100 hours"). No achievements for bad endings or outcomes; if the player reaches the worst ending or loses a character or burns a flora network, the game does not reward them for it. Even with a gentle tagline, rewarding failure reads as grading the player on their loss. The outcome speaks for itself.

### 14.2 Locked achievements

#### It Takes Two

Tagline: *"for addressing the elephant in the room"*

Condition: beat the game with only Aster and Peris in the party. Never recruit Myke, Oli, Tyreg, or Endo (or decline all recruitments).

Multi-layered reference:

- **Hazelight's It Takes Two**, the co-op game the achievement is named after.
- **The killing-the-stuffed-elephant scene** in that game, where the player characters violently destroy the children's toy. The tagline's "addressing" becomes ambiguous between "having a conversation about" and "doing something to"; the elephant in the room is not just unspoken, it's something the minimum-party run has to *deal with*.
- **The minimum-composition run** this game was designed to support.
- **The two protagonists** who are the emotional spine of the game and who have to address whatever "the elephant" is without the buffer of the rest of the party.

What the elephant is, is intentionally ambiguous: Peris's decline, the institution, the game's completability with two characters, or something else the player decides. The achievement does not name it.

### 14.3 Candidate additions

Empty. Added as they come up.

### 14.4 Innovations

Innovations are permanent character upgrades that emerge from specific narrative engagements. When a player triggers a moment with an associated innovation, the upgrade fires at the next rest and persists for the remainder of the playthrough.

The thematic grounding principle is that innovations emerge from narrative moments that thematically justify the upgrade in their own terms. The dialogue's content becomes a gameplay improvement, which gives narrative weight to scene triggering without turning the scene into a farming target. Innovations do not reward generic engagement; they emerge from scenes where the upgrade has a thematic warrant.

The no-rewards-for-bad-endings principle from 14.1 extends to innovations: failure conditions never produce them. The Psyknapse trap's death scene produces nothing; the survival scene's trickle-clown-effect dialogue produces Aster's EMP-range upgrade. The thematic ground: Aster's analytical capacity grows because he understands the institutional capture pattern, and the EMP that interfaces with institutional infrastructure now reaches further because he reads the infrastructure more accurately. The dialogue's content becomes the upgrade.

The player views innovations through Aster's logs, in a photo album interface that is a diegetic in-world object. When an innovation fires, an auto-captured screenshot from the game world at the moment of the triggering action goes into the album as the innovation's entry. The capture is grabbed from Aster's diegetic camera (part of his auditor toolkit, section 3.1), so the in-world fiction matches the player-facing UI: Aster has been carrying the camera all along, and what the player sees in the album is what Aster captured. Aster's relationship to the album is character canon in section 3.1 (the arc from institutional complaint drafts, through wellness-feed performance posts, to personal moments captured without institutional purpose). The pre-game album content establishes that arc; in-game innovation entries extend it with the player's specific playthrough.

Specific innovation assignments for current achievements (14.2) and for planned narrative beats need a design pass (section 17.12). The Aster EMP-range upgrade from the Psyknapse survival scene is committed. Other assignments are open.

## 15. DLC: Roguelike mode

Post-launch DLC. Scope and timing TBD; designed as a post-launch expansion, not a base-game feature. Canonical source: `dlc_roguelike_mode.md`.

### 15.1 Core concept

A separate mode with permanent character death, procedurally arranged map elements, and no narrative checkpoints. Losing a character means permanently losing their map layer, abilities, and storyline for that run. New run, new configuration, new deaths possible.

The roguelike inherits the base game's systems (perception asymmetry, map layers, event-sourcing state, shelter-based save, siderophore/Naturalizer/NK enemy ecology, flora tending, day/night cycle) but strips the narrative scaffolding. No cure arc. No Peris decline over story time. No scripted scenes. The civilization's anatomy is the same; the player's run through it is different every time.

### 15.2 Narrative framing: timeline ambiguity

The roguelike mode's relationship to base-game canon is deliberately unresolved. Two readings both work.

**Alternate-timeline reading.** The roguelike is a separate mode with its own logic, featuring characters the base game established. No diegetic explanation needed. Players who want to play roguelike runs without narrative overhead take this reading.

**Tag-swap reading.** In the base game, the system tracks citizens by their device tags, the things that go green at Tag Day scanners, that get revoked at sanction, that determine who the infrastructure recognizes. The construction-era workers who appear as "dead" in base-game lore (Brobla, Vasca, Senchy, and others at the 12-F collapse) may not all have actually died. The bodies the party finds in the Mother Flure chamber offshoot have tags on them. If a living worker swapped their own tag onto a dead worker's corpse before the bodies were logged and sealed in the chamber, the system would register the corpse as the tag's owner (living) and the living worker as the dead one (gone, no tag to find). The worker is now system-invisible, which is what survival requires.

The tag-swap reading is hinted rather than confirmed: an environmental log here, an offhand line there, a matching tag ID between a construction-era corpse and a roguelike-mode character. Players who notice assemble the inference. Players who don't just play the mode. The reading is not confirmed because confirming it would collapse the base game's treatment of those deaths into a "gotcha." The ambiguity is load-bearing.

The framing has thematic resonance beyond function. It mirrors the system's identity-handling: the institution tracks people by tag, not by person; if a tag is on a corpse, the system registers the corpse as the person; the same weakness that kills people (the system never looks closely enough to see them as people) is what lets some of them escape. It ties to Marco's eccentric-coping frame: Marco cycles names and identities to stay un-legible to the institution; the tag-swap is the extreme version of the same strategy. And it completes the base game's survival-strategy trio: Myke escapes via institutional reassignment (sanctioned), Marco escapes via eccentric improvisation (lateral), the tag-swappers escape via leveraging the system's blind spots (transgressive).

### 15.3 Playable characters

Roster draws from two pools.

**Main-cast characters** (all base-game party members available as roguelike playables): Aster (Astrocyte), Peris (Pericyte), Endo (Endothelial), Myke (Microglia), Oli (Oligodendrocyte), Tyreg (T-regulatory).

**DLC-exclusive characters** (not party members in base game, introduced as roguelike playables): Marco (Macrophage), Brobla (Fibroblast), Vasca (Vascular smooth muscle), Senchy (Mesenchymal), Swan (Schwann cell), Ninj (Meninges), Pendy (Ependymal), Mule (Müller glia).

All DLC-exclusive characters except Swan share the tag-swap reading potential: they are cells that, in base-game canon, either died in the collapse, are peripheral to the party's direct path, or were institutionally written off through sanction and burnout (Mule's case). Swan is new to the roster and does not require a tag-swap backstory; he can simply be a PNS cell never catalogued in the base game's CNS-focused narrative.

### 15.4 DLC-exclusive cast

#### 15.4.1 Marco (Macrophage)

Base-game design lives in `marco_concept.md`. In roguelike mode, Marco is fully playable, freed from the base game's constraint that he never joins the party.

**Combinatoric chemistry kit.** Marco's signature mechanic is improvised combinations. He carries an inventory of ingredients. Combining two ingredients produces an effect based on their property interaction. The game's in-world vocabulary describes the results as "spells" and the items as "spell components," but the chemistry is real.

Ingredient categories include plant material (common, breathable/burnable/bindable), starch (common, fuel binder/thickener), oil (uncommon, fast-burn accelerant/scent carrier), acid (rare, dissolves/etches), salt (common, preservative/desiccant/abrasive), metal filings (uncommon, conductive/sparks), water (ambient, solvent/steam base), and specific plants from the flora taxonomy with their own properties (Seeferns glow, Flures have curmoric compounds, Hushblooms stun, Domas cluster).

Combination effects (illustrative): plant + starch = smoke bomb ("Cloud of Concealment"); plant + oil = incendiary ("Flask of Flame"); starch + oil = slow-burn incendiary ("Sticky Fire"); acid + plant = toxic smoke ("Vapor of Weakness"); salt + water + container = blinding splash ("Stinging Mist"); metal filings + acid = corrosive hiss ("Breath of Dissolution"); Hushbloom + oil = knockout gas ("Sleep Bomb"); Flure + any accelerant = combat buff (curmoric effects). The full matrix is designed as a system, not a lookup.

Design principles for the combination system: (1) effects are legible once the player learns ingredient properties (predictable after a few encounters; rewards experimentation but is not opaque); (2) rare combinations produce memorable effects (most combinations are variants of smoke/fire/corrosive; a few produce unique results players seek out); (3) Marco names everything magically (every combination produces an item called something fantastical, the mismatch between magical naming and chemical reality is the joke, renewed every time the player crafts); (4) the player learns real chemistry by playing (gunpowder is saltpeter + charcoal + sulfur; smoke bombs come from potassium nitrate + sugar; certain acids react with certain metals to produce hydrogen gas).

Non-crafting kit elements: **Stinging Sand** (signature defensive ability, abrasive powder thrown for brief disengagement, always available, not a combination); **Gaseous Form** (movement ability, slow silent traversal along walls with scent-masking, sustained stance); **Borrowed Vocabulary** (passive trait, Marco's interface uses fantasy-game naming conventions: HP → Hit Points, stamina → Mana, abilities → Spells, items → Scrolls/Potions; the player experiences his worldview through the UI translation).

#### 15.4.2 Brobla (Fibroblast)

Base-game presence: log-writing construction worker at Mother Flure site. The terminal entries Aster reads are written by Brobla. Brobla may have died at the 12-F collapse; the log from that event is not signed by Brobla.

Roguelike role: the party's builder-survivor. Fibroblasts produce the extracellular matrix, the structural material that holds tissues together. Brobla can rebuild damaged infrastructure, reinforce walls, patch breaches.

Kit (preliminary): **Collagen Lay** (reinforces a structure temporarily; walls, shelter doors, bridges; costs stamina and ingredients); **Matrix Patch** (closes a small environmental breach or seals a leak); **Shift Log** (passive, Brobla reads terminals as if he wrote them; faster terminal interaction, access to older layers of log data); **Cutting Crew Reflex** (combat response to flora-based attacks; he's worked around Flure before, he knows not to panic).

#### 15.4.3 Vasca (Vascular smooth muscle)

Base-game presence: brief mention in Brobla's logs ("Vasca needed to leave early").

Roguelike role: flow control and pathing. Vascular smooth muscle contracts and relaxes to regulate blood flow through vessels. Vasca can constrict or dilate passages, regulating what moves through them.

Kit (preliminary): **Constriction Pulse** (narrows a corridor section, slowing or blocking enemies); **Dilation Wave** (widens a tight passage, making it traversable); **Flow Sense** (reveals directional movement in the local environment); **Off-Shift** (passive, once per run, Vasca can skip a scripted event by "needing to leave early"; usable to bypass one encounter; callback to the base-game log entry).

#### 15.4.4 Senchy (Mesenchymal)

Base-game presence: Brobla's logs mention her being hit by Flure while clearing 12-C, walked to medical. Survived that injury; later log entries are unclear about her return to the cutting crew.

Roguelike role: adaptive versatility. Mesenchymal cells are the origin stock for many connective tissue types and can differentiate into multiple cell types. Senchy's kit adapts based on what the run demands.

Kit (preliminary): **Differentiate** (at each shelter, Senchy can choose one of three temporary specializations: Bone, Cartilage, Adipose, each reshaping her kit for the next leg with a distinct survival profile); **Stem Pool** (passive, Senchy regenerates slightly at each shelter without needing full resources); **Lineage Memory** (if Senchy dies and is replaced, the next character inherits one of her active perks for a short time); **Cutting Crew Scar** (combat response callback to her Flure injury; takes reduced damage from flora-based attacks but gains a stack of trauma per hit).

#### 15.4.5 Swan (Schwann cell)

Base-game presence: none. New character introduced for DLC.

Role: peripheral-nervous-system insulation specialist. Kit-cousin to Oli but with Schwann-cell-specific differences. Schwann cells regenerate myelin after damage, unlike oligodendrocytes; Swan's kit leans into recovery and resilience.

Kit (preliminary): **Regenerative Myelin** (Swan can restore electrical flow to damaged circuits, similar to Oli but with persistent rather than temporary repair); **Peripheral Map** (reveals infrastructure outside the CNS areas; access to certain regions other characters cannot map); **Schwann Lattice** (defensive formation, Swan positions himself as the insulator for a nearby party member, sharing damage taken); **Nodes of Ranvier** (passive, Swan's abilities cool down faster when he is near another electrical-class character, particularly Oli).

#### 15.4.6 Ninj (Meninges)

Base-game presence: none in the main narrative. Previously listed as DLC character in earlier GDD drafts.

Role: concealment, shock absorption, the brain's protective envelope. Three-layered biology (dura, arachnoid, pia) reflected in a three-stance ability system.

Kit (preliminary): **Dura Stance** (tough outer shell, reduces incoming damage at cost of movement speed); **Arachnoid Stance** (web-like middle layer, reveals nearby hidden enemies through CSF-analog environmental sensing); **Pia Stance** (delicate inner layer, increases precision and interaction fidelity with flora or fine objects); **Meningeal Cushion** (passive, reduced fall damage and reduced shockwave damage); **Layered Retreat** (at low health, Ninj cycles through stances automatically for defensive layering).

#### 15.4.7 Pendy (Ependymal)

Base-game presence: referenced as a log entry author in The Open Files Initiative ("the Pendys log entry from the Open Files"). Previously listed as DLC character in earlier GDD drafts.

Role: the civilization's plumbing expert. Ependymal cells circulate cerebrospinal fluid, clear metabolic waste, distribute nutrients. Pendy knows fluid routes the other characters cannot see.

Kit (preliminary): **CSF Flow** (reveals all fluid pathways in the local environment, including concealed drainage channels and hidden passages that use fluid infrastructure); **Cilia Sweep** (cleans a local area of environmental hazards, biofilm, stagnant pools, weak pathogen colonies, through persistent circulation); **Ventricular Shortcut** (once per shelter, Pendy can traverse through a fluid channel to bypass a corridor; costs stamina); **Waste Clearance** (passive, Pendy's presence slowly cleans accumulated environmental damage over time).

#### 15.4.8 Mule (Müller glia)

Base-game presence: a recurring institutional record distributed across three locations. Aster encounters Mule's terminal trail across The Open Files Initiative (Act 1 mid, early fragments: sick leave filings, escalating incident reports), the Beacon Hill (Act 2 late, denser material: sanction reports, performance reviews, possibly intercepted correspondence), and Plexa's archive at the Root Archive (Act 3 late, culminating material). The cumulative arc the player constructs from fragments shows a worker exposed to too much, escalated through institutional channels for accommodation that did not arrive, and either burned out, was sanctioned, or made the transition to whatever the late-stage worker state is in this civilization. The structural irony is that the worker whose job is to clean the institutional record is themselves recorded only in the institutional record. Tag-swap reading: Mule used the institutional invisibility of post-sanction status to disappear from active records and survive what the institution counted as their effective death.

One canonical line for Mule's voice at the Root Archive: the anti-nihilist argument that if life had no meaning, we would be free and unjudged; but we are not free, and people judge us; therefore life has meaning. (Structural family resemblance to Peter Strawson's "Freedom and Resentment" 1962: the reactive attitudes we cannot help having are themselves the evidence that the framework is real.)

A second canonical line for the same Root Archive material: when you have seen the horrors of the world, you are in awe of how ugly and disgusting humankind can become. If he could choose, he would instead marvel in awe of how beautiful humankind could be. But beauty is slow and hard to make, and loses its essence once commercialized, so it gets washed out by the deluge of horrors.

A third canonical line for the same Root Archive material: "So many people aren't even stirred. They just lie there, waiting to seep into the right places. Not even stirred, and yet there are people like me who have been completely shaken, shaken so much that my mind has become a blur. Shaken so much that all I want is for someone to be shaken with me. Because at least then, for a moment, something will seem still." The surrounding voice and form (letter, journal, recorded statement) remain open.

Role: the cell whose work is to filter what others see, who pays the cost of having seen. Müller cells are the principal glial cells of the retina, spanning the full retinal thickness from photoreceptors to the inner limiting membrane. They handle metabolic exchange with photoreceptors (glucose-lactate cycling), ion homeostasis through potassium siphoning, waste cleanup, structural support, and function as living optical fibers channeling light through the inverted retinal layers to the photoreceptors (Franze et al. 2007). In zebrafish they retain the capacity to dedifferentiate and produce new neurons after injury, a source of retinal regeneration. In mammals this regenerative capacity is largely suppressed; the biology gives the structural PTSD reading its substrate (cannot heal even though the genome retains the capacity). The civilization role is the content-moderator analog: exposed to whatever the system processes, filters and cleans it, supports the meaning-makers (the neurons, the users), invisible to the audience, with structural PTSD-equivalent because the institution has captured the natural healing capacity. The name is the colloquial register for beasts of burden and for couriers carrying high-risk content for others' profit; both readings apply.

Sanity meter mechanics: sanity is drained by exposure to specific enemy types whose visual register is most disturbing (the Toxos, the Redactors, possibly others determined in design) and restored by specific rituals or items rather than by ordinary shelter rest. The thematic anchor is that exposure damages something other than the body, and the something is the capacity to keep working without being broken by the work. Open design question: how sanity restoration interacts with the existing rest cycle (whether any shelter rest restores some sanity, or only specific shelters with specific resources).

Class role: Tank with high HP and aggro-pull. Sanity replaces stamina as his energy meter: he does not care if he is exhausted because he pushes himself past the point of feeling. The same property that makes him resilient is what makes him a liability when sanity runs out.

Trait: dramatically increased perception range, replacing the data overlay that Aster's class uses. Mule sees further than the party by default. The biology grounds this in Müller cells' optical-fiber function (Franze et al. 2007).

Skills (preliminary): an ability to redirect enemy aggression toward Mule (the tank function); an ability to deal AoE damage in a frenzied burst.

Zero-sanity behavior: Mule becomes uncontrollable. His abilities fire unpredictably and may damage other party members. The mechanic externalizes burnout: the worker who can no longer regulate, whose containment becomes what the party has to manage.

Specific ability names, values, sanity recovery mechanism, and detailed kit composition pending the DLC design pass.

Class code: MLR- (section 5.5). Institutional title: Moderation Lifecycle Reviewer.

### 15.5 Systems inherited and modified

The roguelike mode inherits perception asymmetry (each character has their own map layer and true-sight range), event-sourcing state (choices persist in the world), shelter-based save (with permadeath overriding revival), the day/night cycle with sundowning for Peris, flora tending, siderophore ecology, Naturalizer patrols, NK patrols, the ATP/stamina economy, and combat and capability gating.

The roguelike mode removes or modifies: narrative checkpoints (no cure arc, no Peris decline over story time, no scripted scenes), party composition (the player selects a starting character and recruits others during the run), map structure (procedurally arranged rather than authored), and death (permanent rather than knockout/revival).

Open design questions for the DLC are tracked in section 17.

## 16. Stretch framework

The level design is organized around the **stretch**, a unit of geography between two shelters. The world is a sequence of stretches connected by shelters and branched by danger zones; each stretch is a self-contained piece of the corridor with its own pacing, ecology, and resource economy. The stretch framework is the design tool the level work uses to keep stretches consistent with each other and with the game's broader principles. It is treated as a working document, not a fixed specification.

### 16.1 Four design principles

The framework rests on four principles, each drawn from established level-design tradition and adapted to the game's specifics.

**The world is not for the player (Rain World philosophy).** Environments feel like living ecosystems rather than player-serving levels. The world exists independently of the player. Creatures act on their own schedules. The environment was not built for navigation convenience. In TRAWF: the enemies form an ecosystem that would be running with or without the party (section 7.14); Peris's clients exist on their own schedules; the institution operates regardless of player presence; siderophores compete with each other, naturalizers attack flares, gnawers hunt anything with a metabolic signature.

**Push and pull visual language (Clement Melendez).** Players are guided through environments via lighting, color, composition, enemy placement, environmental damage, and spatial design, not waypoints or markers or UI. Push elements drive players away (danger, darkness, narrowing corridors, enemy density). Pull elements draw players forward (light, curiosity, visible rewards, open spaces). In TRAWF: Peris's blurry perception spots pull the player toward optional content; siderophore density pushes them toward safer routes; danger zone junctions are simultaneously pull (a visible interesting thing) and push (characters warn against it).

**Breathing room and pacing rhythm (shelter as bonfire).** Safe spaces create pacing rhythm. The Dark Souls bonfire, Hollow Knight bench, Resident Evil save room, and Rain World hibernation shelter all do this work. TRAWF's shelters do it too. Shelter degradation mirrors world degradation: early shelters are warm and well-supplied; late-game shelters are makeshift and barely functional. Even safe spaces feel provisional. Each shelter contains traces of previous inhabitants, creating a parallel narrative track told entirely through rest points.

**Spatial comprehension through portal shortcuts.** The shortcut-back-to-safety loop (explore forward, unlock a connection to a known safe point) is how Dark Souls and Hollow Knight create spatial comprehension. TRAWF's portal system does this. Each activated portal is a shortcut that collapses the map. The player's mental model of the world grows each time they connect two points. Fast travel via portals is delayed, diegetic, and costly so it does not undermine the geographic knowledge the loops teach. As a lore aside, the portal mechanism is botanical in origin: it and the Psyknapse both descend from Seefern, the communication cultivar (see section 5.6 and the flora roster), worldbuilding rather than a design constraint.

### 16.2 World degradation as the unifying mechanism

The four principles exist in productive tension with each other. "The world is not for the player" pushes toward opacity and hostility, while push and pull demand legibility and guidance; pacing rhythm requires authored control, while ecosystem design demands emergent unpredictability; spatial comprehension through shortcuts wants interconnected loops, while portal fast travel can undermine the geographic knowledge those loops teach. World degradation is the mechanism that reconciles them. As the player advances:

- The ecosystem visibly changes regardless of the player (drives the not-for-the-player feel).
- Safe zones shrink and danger zones expand (creates escalating push and pull dynamics).
- Rest gets harder to earn as shelters degrade (naturally accelerates pacing rhythm).
- Known routes close and new paths emerge (reshapes spatial comprehension).

Combined with the multiple character perception layers that each read different narrative strata from the same environments (section 2.2), and shelter scenes that consolidate scattered environmental storytelling into coherent character moments, the level design produces a world that feels simultaneously hostile and deeply knowable.

### 16.3 The three artifact types

The framework distinguishes three kinds of designed level content. Each has its own design template, but all three reference the framework's principles.

**Stretches.** Corridors between shelters. The connective tissue of the world. Most of what the player traverses is stretches. Each stretch has the per-stretch variables in section 16.4.

**Puzzles.** Bounded spaces with specific objectives (cure components, key items, story beats). Each puzzle has presented and shadow solutions, teaching prerequisites, character moments, and resource consumption that the adjacent stretches must supply. Examples: the Inflammashunt, Pattern Wrap, Flow Aligner, etc. (per section 10.4).

**Danger zones.** Off-path branches that yield cure components or major rewards. Higher difficulty, no shelter at the end, return required. They have their own geography with their own flora and fauna populations, and they can contain puzzles inside them (the Inflammashunt is technically a danger zone with a puzzle inside, so the artifact relationship is danger-zone-contains-puzzle, not danger-zone-is-puzzle).

### 16.4 Per-stretch variables

Each stretch has the following variables, declared at design time and validated against global constraints:

- **Geographic boundary.** Where the stretch starts (shelter N), where it ends (shelter N+1), and what content is in its range.
- **Difficulty target.** Which dimension is dominant: combat, survival, or navigation.
- **Enemy density and species.** Which species are present, at what density, given the stretch's biology and the world's degradation state.
- **Foraging available.** None / low / moderate / abundant. Determines food security in this stretch.
- **Food cost at destination shelter.** ATP units to rest the party (scaled to party size).
- **Resource generation for puzzles.** What materials, knowledge, or character-resources this stretch produces for adjacent puzzles or danger zones (a stretch may "generate" a character recruitment, a flora encounter, a faction beat, etc.).
- **Adjacent puzzles and danger zones.** Which puzzles and danger zones branch off this stretch.
- **Shelter quality at destination.** Full rest, partial rest (sleep-deprivation reduced but not cleared), or other states as designed.
- **Hidden content.** Optional discoveries (lore caches, ?? entities, character beats, optional NPCs).
- **Optional encounters.** Skippable fights or interactions that reward attention but do not gate progression.
- **Stretch-level events.** Chases, character recruitment moments, faction encounters that happen mid-stretch.

The per-stretch variables let the design team check global constraints (a flora over-represented across stretches, a difficulty spike too sharp, a resource not generated where the puzzle that needs it expects it) and resolve them before implementation.

### 16.5 How the framework is used

The framework operates in two phases.

**Design phase.** For each stretch, the design team fills in the per-stretch variables. The framework provides the columns; the design team provides the values. Global constraints are checked across all stretches collectively. Inconsistencies are flagged and resolved.

**Implementation phase.** The level designer takes the per-stretch design and produces the actual stretch in-engine. Pacing numbers are validated through playtesting; difficulty numbers are tuned; flora and fauna distributions are placed; hidden content is planted; adjacent puzzles and danger zones are linked. The framework provides the skeleton; the level designer provides the flesh.

The framework is iterative. As stretches are designed and tested, the framework's principles may need revision. Constraints that seemed reasonable on paper may turn out to fight the actual experience.

### 16.6 What the framework commits the design to

Each stretch must have a defined geographic boundary, accessible flora and fauna populations that can be tracked, and hidden content that rewards exploration and connects to the framework's resource flow. Puzzles and danger zones must declare their resource consumption (what they need from adjacent stretches to be solvable). Open framework-level questions (completionist multiplier ranges, exact food cost ranges, portal revisit handling, boss encounter integration into late-game stretches, specific cure-component mechanical benefits, specific Peris flora-rest interaction values, exact Act 2 and Act 3 shelter assignments) are tracked in section 17.

## 17. Open design questions

Open questions consolidated from across the GDD and source docs, both the cross-cutting questions that affect more than one section and the per-system questions, gathered here in one place. Resolution of any of these may close work that is currently blocking other design.

### 17.1 Cross-cutting

Welcombe Springs mechanical identity (Zone 3 region needs a new mechanical hook after iron-bloom removal). Specific nighttime threats (the nocturnal predator class is unresolved; framing went through several biological identities). Day/night ratio and shelter rest duration (12 unpaused minutes per in-game day committed as starting target; ratio and duration open). Sleep deprivation specific debuff thresholds (system structure canonical; values pending playtest).

### 17.2 Control model and UI

Specific key and button assignments TBD across the control model: pause key, walk/run toggle, pathing mode toggle, camera pan, character switch, ability selection (likely 1-4 per character). Confirmed: hold-X for time acceleration, shift for queueing.

Aster's dialogue-log behavior when he is downed: leaning toward player utility taking precedence (log persists), with a possible diegetic-coherence cue (greyed-out icon, transcribed-posthumously caveat). Polish-pass call.

Specific cool-color values for the supporting cast (Endo, Myke, Oli, Tyreg) per section 3's color identity note. Forget-me-not blue and gold are locked for Aster and Peris; supporting palette specifics defer to art direction.

### 17.3 Forgetting system and asymmetric perception

Implementation questions for the forgetting system, balance, scripting, visibility, late-game rebalancing, cure-component interactions, are tracked in `forgetting_system__1_.md`. Read-window durations by degradation state are listed in section 2.3.5 as design reference points, not commitments; tuning to feel.

### 17.4 Cure components, per puzzle

**Pattern Wrap (component 3).** Post-retrieval dialogue WIP, voice consistency. (Section 10.4.3.)

**Flow Aligner (component 4).** Synthesis beat dialogue is WIP. Full puzzle layout and fragment count TBD. (Section 10.4.4.)

**Acid Core (component 6).** Backstory pairings dialogue TBD. The mirror-and-reflection beat with Myke and Tyreg is sketched; needs workshopping toward an offhand register, not a scripted therapy session. (Section 10.4.6.)

**Outflow Expander (component 5).** Floor count, maze dimensions, gate dependencies, and water rise timing TBD. (Section 10.4.5.)

**The Resonator (component 7).** Chamber progression, pendulum counts, exact target frequencies TBD. (Section 10.4.7.)

**Membrane Sealant (component 8).** Workshop pass on the full puzzle spec and layout details. (Section 10.4.8.)

**Rest Cycle Module (component 9).** Full room layout, interactable count, patrol patterns TBD. Hidden-shelter scene and discovery sequence are canonical. (Section 10.4.9.)

### 17.5 Bosses

**Loca (Act 1 boss).**

- Phase 2 (engaging Loca herself, after the swarm is cleared and the party has reached the top): currently TBD. Possibilities range from "the chamber goes quiet and the encounter is effectively over, the player walks out with the AI summary in hand" to "a final puzzle layer addresses the wires/tangles directly."
- Presented-solution detail: confirmed at the level of "Myke's fire works on locusts, fails on Loca," but the specific wave structure, fuel economy, and Aster/Peris contributions during the presented path are TBD.
- Specific flora species for Peris's survivor-handling role (Hushblooms/Tanglers/Flure variants are candidates; specifics TBD).
- Full context and additional questions in `loca_boss_spec.md`.

**Paranucleus (Act 2 boss).**

- Whether the encounter has any combat at all. Current spec is contemplative-only (navigation, perception management, Climbvine tying); no enemies in the aggregate proper. Whether some of the institution's surviving systems still operate at the facility's outer edges (residual security, automated processes the institution didn't bother to shut down) is open and could add tactical texture without changing the contemplative core.
- A `paranucleus_boss_spec.md` parallel to `loca_boss_spec.md` is the next major design work for section 11.2.

**Final encounter (section 11.3).** Not yet drafted in this GDD.

### 17.6 Shadow-solution layer (section 2.6)

Per-puzzle shadow solutions still needing design passes:

- Inflammashunt DZ (Aster-Peris feasibility for accessing all three routes alone)
- The Honeycomb Cooperative puzzles (Aster overlay signal-analysis as Oli-substitute; Peris Capbage as Barrier-substitute)
- Beacon Hill (Aster's enforcement-credential hack as Tyreg-substitute, fragility and conditions)
- Bulwark Wharf (no shadow-solution design yet)
- Welcombe Springs, Harmonia, Sunset Acres, Root Archive (all four Act 3 sub-areas need shadow solutions designed; Act 3 is the hardest place to maintain the principle because puzzles are designed to stress full-party coordination)

### 17.7 Tutorials (section 9)

Open implementation questions for both tutorials live in `simulation_tutorial_expansions__3_.md`. Specific questions include exact dialogue beats not yet locked in (the wellness-feed line phrasing, the pinned-warning copy, the painting wall's collection-name attribution), and the *Breadth of Life* sculpture's specific wall location and weakness placement.

### 17.8 Enemy ecosystem (section 7)

Open design questions for the enemy ecosystem are collected in section 17.7's source docs and across the per-species blocks. Tuning, balance, late-game rebalancing, and cure-component interactions are the main outstanding categories.

### 17.9 DLC roguelike mode (section 15)

- **Run length and structure.** How long is a roguelike run? Single act? Multi-zone? Single extended descent from Zone 1 to Zone 3? Procedurally-generated arcs with specific goals?
- **Starting character selection.** Does the player pick one character at the start and recruit others during the run, or pick a party of three at the start? Different design implications.
- **Permanent unlocks across runs.** Does the roguelike have meta-progression (unlock new characters, new ingredients, new ability tiers across runs) or is each run a clean slate?
- **Tag-swap reveal depth.** How heavily should the tag-swap reading be hinted? A single environmental-storytelling discovery hidden deep in the mode, or multiple pieces scattered throughout?
- **Brobla's role as log-writer.** Brobla's base-game characterization is most developed (he wrote the logs Aster reads). His roguelike kit has the richest connective tissue to base-game lore. Vasca and Senchy are less characterized; their kits may need more invention.
- **Senchy's survival status.** Brobla's logs say Senchy was walked to medical after being hit by Flure; later log entries are unclear whether she returned to the cutting crew. Roguelike framing may want to resolve this one way or another, or keep it ambiguous.
- **Cross-character interactions.** Do the main-cast characters react to meeting the DLC characters in-run? The tag-swap reading creates natural dramatic irony: Aster has been reading Brobla's logs for months, and now he might meet someone claiming to be Brobla. Handling lean: ambient reactive lines rather than scripted scenes, preserving the mode's non-narrative frame.
- **Scope and timing.** Post-launch DLC; specific ship target TBD.

### 17.10 Stretch framework (section 16)

- **Completionist multiplier ranges.** The 1.5x-3x range for content-complete vs main-path-only run length is intuitive but not validated.
- **Food cost per stretch ranges.** The 1-5 ATP unit range scaled to party size is intuitive but depends on playtesting.
- **Portal revisit handling.** The framework references portal fast-travel but does not fully specify how revisiting cleared stretches via portals affects ecology, foraging, or hidden content respawning.
- **Boss encounter integration.** The late-game stretches that lead into Loca, Paranucleus, and the final encounter need boss-approach archetype rules: how does the stretch's pacing, foraging, and shelter quality change as the player approaches a boss?
- **Specific cure-component mechanical benefits.** Each cure component is committed in principle to mechanically improving Peris's perception or the party's resilience, but the specific values are pending.
- **Specific Peris flora-rest interaction values.** Tended flora at shelters affects rest quality (per section 8); specific numerical values pending.
- **Exact Act 2 and Act 3 shelter assignments.** Broad pattern committed; specific shelter-by-shelter values pending.

### 17.11 Source-doc gaps

Documents referenced by the project that are not present in the current canonical set, or that carry stale framing that needs updating:

- A `book_fragments_spec.md` consolidating the six damaged-book scenes (Fields/Mokyr/Arendt/Sen/Baldwin/Foucault) does not exist. The system is described in section 1; per-fragment scene specs (where each book is found, how the misreading-and-correction beat plays out for the character who finds it, surviving passages, dialogue) and per-character ability upgrades on read (canonical addition: each fragment grants its owner-character an ability upgrade in the direction the book asks them to grow) are scattered across past chats and need consolidation.
- `item_handling_spec.md` is referenced by `controls_reference.md` as the canonical source for the four input verbs and the action-queueing mechanic but is not in the current project file set. Section 2.1 absorbs the verb structure from `controls_reference.md` directly; the dedicated spec should be surfaced or re-authored.
- `endo_worldbuilding.md` does not exist; should be drafted parallel to the other character files. Section 3.3 currently uses mini GDD entry plus scene-fragment context. Should incorporate: the silence canon (ENT class work is underwater; ENTs develop gestural professional vocabularies; endothelial biology backs this with contact-channel signaling), the swimming kit affordance (Endo can navigate flooded passages, partly-submerged infrastructure, fluid corridors), the class-access fact (ENT-class workers don't typically access PCT services; Peris's caseload is class-shaped), the appearance design developed in this current chat session (tiled-shape buzz cut, pale teal-cyan edge-concentrated glow at junction sites that reads particularly clearly underwater, dark workman's coveralls with utility belt, ENT-1o or ENT-##o code), and the workshopped diegetic-delivery dialogue once committed (current sketch combines the swimming-grounded silence with the class-access recognition, with no committed lines yet).
- `world_aesthetic_reference.md` referenced by `world_map_prompt__1_.md` but not in project file set. Section 6 absorbs what's available; broader aesthetic canon (architectural grammar, fever-dream-with-biological-referent principle) is missing.
- `techos_species_doc.md` referenced by `enemy_ecosystem.md` but not in project file set. Section 7's siderophore detail is taken from `enemy_ecosystem.md` directly.
- Mini GDD §6 carries the older voxel + painterly visual register. The current canonical register is PS2-era 3D with pixel art textures and realistic dark/dramatic lighting (section 6.1). Mini GDD §6 should be updated to match.
- `fauna_image_prompts__3_.md` and `flora_image_prompts__3_.md` may carry the older voxel + painterly preamble. Should be updated to match section 6.1.

### 17.12 Pending scenes, assignments, and mappings

- **Innovations system specific assignments (pending design pass).** The innovations system is committed in canon (section 14.4) as permanent run-mechanical upgrades emerging from specific narrative engagements, viewed through Aster's photo album interface in his logs (section 3.1). The Aster EMP-range upgrade from the Psyknapse survival scene is the foundational example and is committed. The notification mechanism is committed: at the moment of the triggering action, Aster's diegetic camera (part of his auditor toolkit) auto-captures a screenshot from the game world, and the screenshot goes into the photo album as the innovation's entry. The pre-game album content establishes Aster's arc with the camera (complaint drafts, then wellness-feed posts, then personal captures); in-game innovation captures extend it with the player's specific playthrough. Specific assignments for the It Takes Two achievement (14.2) and for planned narrative beats need a design pass. Open mechanical questions: how end-game achievements like It Takes Two produce innovations, given that the achievement fires at game-end and the within-run timing model does not directly apply (a New Game Plus modifier or another category of reward is one option); whether every named scene with a planned dialogue beat gets an associated innovation or only specific ones.
- **Müller glia as content-moderator class (confirmed; specific design work pending).** Confirmed in canon as Mule (Müller glia), recurring presence in base game through terminal logs distributed across The Open Files Initiative (Act 1 mid), Beacon Hill (Act 2 late), and Plexa's archive at the Root Archive (Act 3 late). Playable in DLC roguelike mode (section 15.4.8) as a tank class with high HP, sanity replacing stamina as the energy meter, and a dramatically increased perception range in place of the data overlay. Class code MLR- (section 5.5), institutional title Moderation Lifecycle Reviewer. Tag-swap reading: Mule used post-sanction institutional invisibility to disappear from active records. Pending design work: specific log content at each of the three locations and how the cumulative biographical arc unfolds; detailed kit composition around the sanity-meter anchor (rate of drain by enemy type, restoration mechanism, ability names and values). Bibliography references for the content-moderator labor analog include Sarah T. Roberts's *Behind the Screen* (2019), Casey Newton's *Verge* reporting on Facebook moderators (2019), Hans Block and Moritz Riesewieck's documentary *The Cleaners* (2018), and the OpenAI/Kenyan-workers piece (Perrigo, *TIME*, 2023).
- **Specific placements of Marco's three fake-out heroic-sacrifice scenes and the real-death scene.** Section 3.7 commits to the diminuendo death structure with three fake-outs and a mundane real death. The specific narrative beats where each fake-out occurs (and where the real death goes) are pending design.
- **Specific scenes for buzzkill enforcement and management-side respectful dismissal (per section 5.7).** The cross-class propaganda system canon commits to the scene-level structure: maintenance shelters where workers police each other for talking like the management class, management spaces where working-class concerns get dismissed as classist. Specific scene placements and dialogue are pending.
- **Mapping cure components to real-world functioning institutional models (partially committed).** The cure components are each abstractions of working institutional solutions to capture problems. The Iron Redistribution Chaperone mapping is committed as (TVA + Mondragon), per section 10.4.1, with the framework also grounding section 4.10's outer-region depopulation analysis. Remaining candidate mappings are pending: Inflammashunt to the Montreal Protocol on ozone-depleting substances (1987), Membrane Sealant to the Beveridge Report and the UK NHS (1948). The mappings let the cure read as more credible to players who notice the parallels; the gesture toward "this is what works" rather than only "this is what fails."

## 18. Bibliography and research grounding

Sources the design draws from. The references below are what the design is in conversation with rather than a syllabus; the work is the citation in most cases. Where a reference is named in-game (the six damaged-book fragments) or load-bearing for a specific system, that is noted.

### 18.1 Philosophical and political theory

**The six damaged-book fragments** (in-game artifacts, see section 1):

- R. Douglas Fields, *The Other Brain* (2009). Aster's fragment. Surviving title fragment reads "...ther Brain." Fields is a neuroscientist; the book popularized glial biology, which is the design's substrate.
- Joel Mokyr, *A Culture of Growth* (2016). The civilization's fragment. Surviving title fragment reads "Culture... Grow." The cultural conditions for open inquiry, and the question of whether they can be lost.
- Hannah Arendt, *The Life of the Mind* (1978, posthumous, two volumes; the projected third volume on judgment was unwritten at her death). Aster and Peris's shared fragment. Surviving title fragment reads "the Mind." The missing third volume is what Aster writes in Ending 4.
- Amartya Sen, *Development as Freedom* (1999). Oli's fragment. Surviving title fragment reads "Freedom." The capability approach: what a society could have prevented.
- James Baldwin, *The Fire Next Time* (1963). Myke's fragment. Surviving title fragment reads "Fire." Systemic innocence as the crime.
- Michel Foucault, *Discipline and Punish* (1975, English 1977). Tyreg's fragment. Surviving title fragment reads "Discipline." Disciplinary power, surveillance, and the production of categories.

**Other named thinkers** (referenced in section 1; not in-game artifacts):

- Hannah Arendt, *Eichmann in Jerusalem* (1963). The banality of evil; the standing critique the cure-creator's autobiography references.
- Jacques Derrida, *Specters of Marx* (1993, English 1994). Hauntology; the Flow Aligner ruin's institutional architecture and Peris's condition of being erased while still alive. The synthesis beat at the Flow Aligner is named "Specters, of Marks."
- Immanuel Kant on judgment as acting without rules (*Critique of Judgment*, 1790, implicit). The missing-chapter writing in Ending 4 is structured around this; Aster does not know he is paraphrasing Kant.
- Augustine, "love is the weight of the soul" (*Confessions*). Surfaces in the shelter scenes as the quietest theoretical commitment the game makes.

**Additional references** for canon expansion (cross-class propaganda, End of History prehistory, Plexa biography, The Board / Debord pun, the PLA-8o Plato / pharmakon pun, and adjacent material):

- Blind, Georg D. *The Entrepreneur in Rule-Based Economics: Theory, Empirical Practice, and Policy Design*. Springer (Economic Complexity and Evolution), 2017. The rule-based and evolutionary-economics grounding for the growth-versus-stability spine and the actionable program (sections 1.1 and 4.12): the entrepreneur as variation source and rule-propagator, the meta-stable versus changing subsystem, the operational / first-order / second-order policy taxonomy that formalizes the symptom-versus-cure structure, and the Japan finding that traditional class order and the worship of craft and mastery empirically suppress the founder force (the section 5.9 caste link). Also the source of the candidate epigraph, Edgeworth on Walras (section 1). He treats the Kirzner-Schumpeter divide, equilibrium-restoring versus equilibrium-disturbing entrepreneurship, as an empirical question settled case by case rather than a theoretical one, and as a cycle: the Schumpeter type disturbs the equilibrium, Kirzner-type second movers level the disturbance, and the levelling breeds the fresh uncertainty that calls out the next disturbance. His meta-stable state, where no new rules emerge and none die, is the game's sealed steady state, the difference being that he treats it as temporary while the game freezes it by suppressing the search that would break it.
- Bonilla-Silva, Eduardo. *Racism without Racists: Color-Blind Racism and the Persistence of Racial Inequality in the United States*. Rowman & Littlefield, 2003. For the cross-class propaganda system and the management-class respect-driven denial mechanism (section 5.7).
- Bourdieu, Pierre. *Outline of a Theory of Practice*. Translated by Richard Nice. Cambridge University Press, 1977. For habitus and the maintenance-class community's internal policing of register.
- Carr, Patrick J., and Maria J. Kefalas. *Hollowing Out the Middle: The Rural Brain Drain and What It Means for America*. Beacon Press, 2009. For the rural-depopulation cascade pattern (section 4.10).
- Debord, Guy. *The Society of the Spectacle*. 1967. The theoretical anchor for Peris's wellness feed The Board (section 5.6).
- Derrida, Jacques. "Plato's Pharmacy," in *Dissemination*. Translated by Barbara Johnson. University of Chicago Press, 1981 (French 1972). The pharmakon, the single substance that is remedy and poison at once, which doubles the game's cure-versus-symptom axis: the real cure set against the symptom-suppression and the rogue tenth component (section 10.5). The PLA-8o pharmacy (section 4.10) is its in-world figure, a pharmacy whose collapse poisons the people it was built to heal.
- Fukuyama, Francis. "The End of History?" *The National Interest* 16 (Summer 1989): 3-18; *The End of History and the Last Man*. Free Press, 1992. The post-historical complacency the civilization went through before its current decay (section 6.2).
- Galbraith, John Kenneth. *The Affluent Society*. Houghton Mifflin, 1958. The earlier identification of the same pattern: postwar economic growth produced belief that all major problems were solved while public goods were quietly eroded (section 6.2).
- Gotham, Kevin Fox. "Tourism Gentrification: The Case of New Orleans' Vieux Carré (French Quarter)." *Urban Studies* 42, no. 7 (2005): 1099-1121. The foundational paper naming the tourism-gentrification mechanism (section 4.10).
- Hill, Patrick L., and Nicholas A. Turiano. "Purpose in Life as a Predictor of Mortality Across Adulthood." *Psychological Science* 25, no. 7 (2014): 1482-1486. The empirical grounding for the End of History civilization's lifespan deterioration (section 6.2).
- Kirzner, Israel M. *Competition and Entrepreneurship*. University of Chicago Press, 1973. The entrepreneur as alertness, the discovery of a gain already there to be noticed and the equilibrium-restoring move that closes a mismatch and coordinates the system. Kirznerian alertness is the in-fiction form of the restored signal, the noticing that error-correction depends on (section 1.1), and Aster is its suppressed instance, the analyst whose accurate reading goes unheard.
- Lilienthal, David E. *TVA: Democracy on the March*. Harper & Brothers, 1944. Classic primary-source account of the Tennessee Valley Authority's regional development model, used as a real-world precedent for the Iron Redistribution Chaperone's coordinated-state-led-planning register (sections 4.10 and 10.4.1).
- Plato. *The Republic*, c. 380 BCE, with the soul's three seats set out in the *Timaeus*: reason in the head, spirit in the chest by the heart, appetite below the diaphragm in the gut. The tripartite soul and its three-class city, the appetitive producers, the spirited auxiliaries, and the rational guardian-rulers, are the ancestor of the NVU's cell-caste (section 5.9), the same sort made literal in an actual body. The myth of the metals, the noble lie that each citizen's rank is the metal innate to their soul, is the template for the cutie-mark and the contentment-simulation; the guardians' controlled eugenic breeding grounds the section 4.12 purity faction; and Plato's justice, each part doing its own and staying in its place, is the exit-zero stillness the game treats as the disease rather than the ideal. The PLA-8o pharmacy in the commune districts (section 4.10) reads as his name, and as a pharmacy carries the Derrida pharmakon below.
- Schumpeter, Joseph A. *The Theory of Economic Development*, 1911 (English 1934), and *Capitalism, Socialism and Democracy*. Harper & Brothers, 1942. The entrepreneur as innovation and creative destruction, the equilibrium-disturbing introduction of the new combination, which is the in-fiction leap (section 1.1) and the growth pole of section 4.12. Schumpeter's own fear that innovation would be routinized inside bureaucracies and the entrepreneurial function made obsolete is the civilization's history in miniature: the founder-force filed away into craft (section 5.9) and the section 10.5 workers who optimized themselves out of existence.
- Stern, Yaakov. "What is cognitive reserve? Theory and research application of the reserve concept." *Journal of the International Neuropsychological Society* 8, no. 3 (2002): 448-460. Cognitive reserve theory, the brain-biology version of use-it-or-lose-it (section 6.2).
- Whyte, William Foote, and Kathleen King Whyte. *Making Mondragon: The Growth and Dynamics of the Worker Cooperative Complex*. Cornell University Press, 1988. Canonical sociological study of the Mondragon Cooperative Corporation in Basque Spain, used as a real-world precedent for the Iron Redistribution Chaperone's cooperative-ownership register (sections 4.10 and 10.4.1).
- Wuthnow, Robert. *The Left Behind: Decline and Rage in Rural America*. Princeton University Press, 2018. For the outer-region depopulation pattern (section 4.10).

**Content moderation labor** (referenced by Mule, section 15.4.8 and 5.5; the cellular biology and the labor pattern map onto each other cleanly):

- Roberts, Sarah T. *Behind the Screen: Content Moderation in the Shadows of Social Media*. Yale University Press, 2019. The academic anchor for the labor analysis of commercial content moderation.
- Newton, Casey. "The Trauma Floor: The Secret Lives of Facebook Moderators in America." *The Verge*, February 25, 2019. The public-facing canonical piece on Facebook moderators in Phoenix.
- Block, Hans, and Moritz Riesewieck. *The Cleaners* (documentary). 2018. Visual register for the moderator working conditions.
- Franze, Kristian, et al. "Müller cells are living optical fibers in the vertebrate retina." *Proceedings of the National Academy of Sciences* 104, no. 20 (2007): 8287-8292. The biology grounding for the "every photon that becomes vision passes through a Müller cell" line in Mule's role description.
- Patočka, Jan. *Heretical Essays in the Philosophy of History*. Translated by Erazim Kohák. Open Court, 1996. (Original Czech samizdat 1975.) The "solidarity of the shaken" concept grounds Mule's third canonical line at the Root Archive (section 15.4.8).

**Critical and liberation psychology** (referenced by Peris's situation as a Personal Care Therapist inside an institution that structurally produces her caseload's suffering; the framework that makes the structural cause invisible to her is the wall her arc breaks against):

- Martín-Baró, Ignacio. *Psicología de la liberación*. Edited by Amalio Blanco. Trotta, Madrid, 1998. (Posthumous collection.) The canonical Spanish-language gathering of his liberation-psychology essays, including "Hacia una psicología de la liberación" (1986). Selected English translations in *Writings for a Liberation Psychology* (Harvard UP 1994, edited by Aron and Corne). Earlier foundational volumes: *Acción e ideología: Psicología social desde Centroamérica* (UCA Editores, 1983) and *Sistema, grupo y poder: Psicología social desde Centroamérica II* (UCA Editores, 1989). Martín-Baró was a Spanish-born Jesuit psychologist working in El Salvador, assassinated by the US-trained Atlacatl Battalion at the UCA on November 16, 1989, ten years to the day after receiving his doctorate. His concepts of desideologización (the psychologist's task of helping people see through ideological frames that legitimize their oppression), fatalismo latinoamericano (learned fatalism diagnosed as individual pathology when it is structurally produced), and trauma psicosocial (trauma as collective and political rather than individual) ground Peris's situation directly.

**Overstimulation and the blasé attitude** (the social-theory anchor for the simulation's mechanism and the architect's origin, section 3.9):

- Simmel, Georg. "The Metropolis and Mental Life" (1903; "Die Großstädte und das Geistesleben"). The blasé attitude: the metropolitan nervous system, overloaded by relentless and rapid stimulation, defends itself by going indifferent, losing the capacity to react to the distinctions between things. This is the pre-neuroscience description of what the simulation does to a population by overstimulation, and the figure of thought the design translates into reward-system terms (the atomization of desire and the dulling of the envy signal). Debord's *The Society of the Spectacle* (above) is the adjacent reference on manufactured contentment.

### 18.2 Literary and cultural references

- Hermann Hesse, *Das Glasperlenspiel / The Glass Bead Game* (1943). The thematic model for Aster's simulation and for the Glass Bead Game object he was given. Aster's name for the institutional intellectual sealed inside Castalia. The novel does not appear in the game world; Hesse is a research reference. (See `aster_worldbuilding.md` for the full Hesse treatment.)
- Tangping (躺平, "lying flat") and bailan (摆烂, "letting it rot"). Chinese youth movements emerging in the early 2020s. The frame for Myke's character arc. The 2021 anonymous tangping manifesto is the textual source. (See `myke_worldbuilding__1_.md`.)
- *Berserk* (Kentaro Miura) and *Fullmetal Alchemist: Brotherhood* (Hiromu Arakawa). Moral seriousness without moral simplicity (per `trawf_notes__1_.md`).
- *To the Moon* (Freebird Games, 2011). Life-in-reverse reveal as a structural reference (per `trawf_notes__1_.md`); Alzheimer's as serious subject in a videogame, even though the player is not WITH the person who has it.

### 18.3 Game design influences and method

**Reference points** (from `to_rust_mini_gdd__1_.md` and the older GDD's reference-points statement):

- *Rain World* (Videocult, 2017). Indifferent ecology, tense survival, linear regions with gates; the principle that nothing is evil, the indifference is what makes the world terrifying.
- *Dark Souls* (FromSoftware, 2011). Shortcut loops, bonfire pacing, environmental storytelling on vertical surfaces, spatial comprehension through interconnected geography.
- *RimWorld* (Ludeon, 2018). Indirect control, pause-and-direct.
- *Duskers* (Misfits Attic, 2016). Indirect unit control, limited sensor perception, dread through incomplete information, hostile-through-indifference environments. The forgetting system's encounter-randomness section names this directly (section 2.3.6).
- *Pathologic 2* (Ice-Pick Lodge, 2019). Resource scarcity, world decay over time, asymmetric degradation.
- *Eastward* (Pixpil, 2021). Dense environmental storytelling through abandoned architecture, leftover objects, and infrastructure state; the core narrative of leaving a safe zone to discover a decaying world; a central relationship where one character's condition is worsening.
- *Subnautica* (Unknown Worlds, 2018). Day/night cycle pacing reference; long enough to support extended exploration without feeling rushed (see section 2.5).
- *It Takes Two* (Hazelight, 2021). The achievement of the same name (section 14.2) references this game and its killing-the-stuffed-elephant scene.

**Method-of-storytelling references** (from `tyreg_worldbuilding__1_.md`'s Method Notes section):

- *The Wire* (David Simon, 2002-2008). Simon's rule: characters cannot lecture. Institutional critique delivered through specific people in specific rooms making specific decisions. The stats-juking pattern across all five seasons is never explained by a wise mentor; it surfaces when Prez recognizes it in a scene about test scores. The model is Greek tragedy, not Shakespeare. (David Simon, Slate interview, 2007.)
- *Disco Elysium* (ZA/UM, 2019). Critique as internal voices: the game's political and ethical positions are voiced by personified skills inside the protagonist's head, not by NPCs lecturing the player. The model for Aster's internal data overlay when he is the active character.

### 18.4 Real-world institutional and historical patterns

The institutional critique is grounded in documented patterns rather than invented. Aster's J-stores in his tutorial map to the U.S. Chemical Safety and Hazard Investigation Board (CSB) and adjacent root-cause-analysis institutions whose findings on barrier-and-containment failures are routinely correct and routinely unacted upon. The class of failure includes the Therac-25 radiation therapy accidents, Bhopal, the Texas City refinery disaster, the Challenger O-rings, the Boeing 737 MAX, and Deepwater Horizon. The shape recurs: technical workers correctly predict the failure, the institution publishes more reports rather than acting, the failure happens, the cycle resumes.

Suppressed-knowledge histories inform the Pattern Wrap puzzle's four-timeline structure. The pattern is documented across cases: Ignaz Semmelweis dying in an asylum in 1865 after his findings on handwashing and childbed fever were rejected by the medical establishment. Rosalind Franklin's X-ray crystallography (the famous Photo 51) being used without credit by Watson and Crick in their 1953 *Nature* paper on DNA structure. Numerous safety memos that arrived too late, or arrived on time and were ignored by people with the access to act on them. The Pattern Wrap's four researchers (instinct without tools, tools without time, synthesis without access, access used to lock the door) compresses the pattern into four moments the player walks through.

The land conflict at Sunset Acres (section 12.11) and the broader enclosure material in sections 4.10 and 4.11 are grounded in property-law doctrine rather than invented. Adverse possession is the common-law rule by which someone who occupies land openly, exclusively, and continuously for a statutory period, without the owner's permission, can take title from an owner who neglected to assert it; the logic is half statute-of-limitations and half preference for productive use over absentee neglect. Its inverse is the split estate, where surface and mineral rights are severed and the mineral estate is the dominant one: in much of Texas and the American West the holder of the deep rights may enter, fence, and drill on land whose surface someone else owns, and the surface owner's title does not reach far enough down to stop it, which is the case the design first took as its seed. The lever that makes the Sunset Acres conflict unresolvable is sovereign immunity from adverse possession, the old maxim nullum tempus occurrit regi, no time runs against the king: government-held land is generally exempt, so a use-claim that would ripen against a private absentee can never ripen against the state. The Collective inherits exactly that exemption, which is why a productive occupation it has every practical reason to lose to cannot be lost through any legal channel, and the dispute has nowhere left to go but the fight.

The in-game neuron-preservation system marketed as immortality (section 3.9) is grounded in the real market for commodified brain preservation. Ventures such as Nectome have offered high-fidelity brain preservation (aldehyde-stabilized cryopreservation) pitched explicitly at future revival or mind-uploading, taking deposits against a procedure that is fatal by design; cryonics providers have sold the same promise for decades on a subscription-and-insurance model. The pattern the design borrows is the reframing of death as a deferred subscription and the sale of immortality as a product, together with the recursion it enables, cells inside a preserved brain building and selling their own preservation one level down from the preservation that made their world.

### 18.5 Neuroscience and pathology

The civilization's anatomy is the neurovascular unit (NVU). Every character is a real cell type whose biological function is the basis of their narrative role. The pathology being dramatized is Alzheimer's disease, with attention to current research on iron dyshomeostasis, neuroinflammation, amyloid clearance, and tau pathology. Specific research references the design draws from include:

- **Astrocyte biology.** Fields, *The Other Brain* (above) is the popular reference; primary literature on astrocyte network function and homeostatic support underlies Aster's role.
- **Pericyte function and BBB maintenance.** Pericytes maintain the blood-brain barrier across decades; their dysfunction in Alzheimer's is documented in the iron-clearance literature. Peris's role and decline draw from this.
- **Specialized pro-resolving mediators (SPMs).** Resolvins, lipoxins, maresins, protectins. Lipid mediators that actively terminate inflammation and promote tissue repair. Chronic neuroinflammation in Alzheimer's is characterized by failure of the resolution phase. The Inflammashunt component is the resolution catalyst (section 10.4.2; full reference in `inflammashunt_puzzle.md`).
- **Anti-amyloid antibody therapies.** Lecanemab, aducanumab, and Fc-mediated microglial clearance mechanisms. Background for the Paranucleus encounter and the rogue cure-component history (section 10.5; `loca_boss_spec.md`).
- **Tau pathology and prion-like propagation.** Tau forms hyperphosphorylated paired helical filaments that aggregate into neurofibrillary tangles; prion-like cell-to-cell propagation is recent research. The Tangler enemy species is this biology rendered as organism (`fauna_image_prompts__3_.md`).
- **Pyramidal neuron hyperexcitability.** Alzheimer's-affected brains show elevated baseline neuronal firing and seizure-like activity. The Spiker enemy species models this circuit pathology.
- ***Porphyromonas gingivalis* and Alzheimer's.** Recent research linking the periodontal pathogen to Alzheimer's pathology via gingipain proteases. The Gnawer enemy species is *P. gingivalis* rendered as organism. The dark-pigmented gram-negative coloration, the gingipain enzyme cloud, and the metabolic-signature hunting are the real biology.
- **Antigenic mimicry.** *Trypanosoma brucei*'s membrane cloaking via variant surface glycoproteins (VSGs) is one of parasitology's most-studied immune-evasion mechanisms. The Redactor enemy species (institutional Latin echoing *Trypanosoma*) is built on this biology.
- **Neutrophil biology.** The Flare enemy species' three-color granule field models the three classes of neutrophil granules (primary/azurophilic, secondary/specific, tertiary). The bystander damage from oxidative bursts is biologically accurate.
- **Curcumin / curcuminoids.** The Curecumin reward in Peris's tutorial draws from real research on curcumin's amyloid-binding affinity and NF-κB modulation. Bioavailability is the major real-world problem; the in-game version assumes a delivery formulation that solves it (section 9.2).
- **Cell-type biology** for the rest of the cast: microglia (Myke's immune-surveillance and synaptic-pruning roles), oligodendrocytes (Oli's myelination and electrical-conduction support), T-regulatory cells (Tyreg's immune-tolerance enforcement role), Schwann cells (Swan, DLC, peripheral-nervous-system insulation and regeneration), fibroblasts (Brobla, structural matrix), vascular smooth muscle (Vasca, flow regulation), mesenchymal cells (Senchy, pluripotency/differentiation), meninges (Ninj, three-layered protective envelope), ependymal cells (Pendy, CSF circulation and waste clearance), macrophages (Marco, phagocytosis and improvised response).
- **Supernormal stimuli.** Niko Tinbergen's ethology (*The Study of Instinct*, 1951): exaggerated artificial cues that release a stronger instinctive response than the natural stimulus they imitate. Deirdre Barrett (*Supernormal Stimuli*, 2010) extends the idea to modern overstimulation. The simulation is built as a supernormal-stimulus machine (section 3.9).
- **Dopamine as prediction error, not pleasure.** Wolfram Schultz's work on dopamine neurons as reward-prediction-error signals, and Kent Berridge's dissociation of wanting from liking, ground the claim that overstimulation degrades a learning signal rather than a pleasure signal, which is why the architect can feel without learning (section 3.9). Koob and Le Moal's allostatic model of addiction, the reward set point shifting under chronic overstimulation, grounds the civilizational-addiction reading.
- **Dopamine and habit formation.** The dorsal striatum and its dopaminergic input consolidate repeated actions into automatic habits, the shift from effortful goal-directed control to frictionless routine (Ann Graybiel on basal-ganglia habit circuits; Balleine and Dickinson on goal-directed versus habitual action). When that signal runs low, behaviors stay stuck in the effortful, consciously-managed mode, which grounds the architect's early logs and the friction of doing by hand what others automate (section 3.9).
- **Empathic concern versus personal distress.** C. Daniel Batson's empathy-altruism work distinguishes other-oriented empathic concern, which motivates helping, from self-focused personal distress, which motivates escape; the architect's response is the latter. James Blair's violence-inhibition mechanism, in which distress cues normally inhibit aggression and fail to in certain presentations, together with the standard reactive-versus-proactive aggression and primary-versus-secondary psychopathy distinctions, grounds the reading of him as a reactive, dysregulated type mislabeled as the cold, empathy-less one (section 3.9). Mirror-neuron accounts of empathy are treated as overstated (Gregory Hickok, *The Myth of Mirror Neurons*, 2014); the resonance is real, the tidy mechanism is not.

### 18.6 Botany

- ***Myosotis sylvatica* (forget-me-not).** Objectively scentless. Peris's perception of the species as smelling like "the rust going away" is pure relational perception, not a chemical signal she is reading. This is the canonical test case for the relational-vs-objective layer split in the forgetting system (section 2.3.2).
- **The flora taxonomy.** Seefern, Scarpet, Flure (with the Mother Flure variant), Hushbloom, Capbage, Gasafoetida, Climbvine. Seven species. Real biology references for each are in `flora_taxonomy__2_.md` and `flora_image_prompts__3_.md`. Most species draw from real plant kingdom biology (rapid germination, scent emission, climbing/ground-cover behavior, defensive chemistry) translated into the NVU's flora register.

### 18.7 Chemical engineering

- **McCabe-Thiele method** (Warren L. McCabe and E. W. Thiele, 1925). Graphical method for binary distillation column design; the operating-line-stepping-against-an-equilibrium-curve image is the structural basis of the *Macabre Teal* painting collection in Aster's workspace tutorial (section 9.1), rendered in cool palette.
- **Hunter-Nash method** (T. G. Hunter and A. W. Nash). Graphical method for liquid-liquid extraction process design; the ternary phase diagram with binodal curve, tie lines, and stage construction is the structural basis of the *Hunter and Ash* painting collection in the same scene, rendered in earth tones.

Both are standard undergraduate chemical engineering design methods. The in-game art market sells them as autonomous abstract art; the institution that produced the diagrams as barrier-fault prediction documents has lost track of what they were originally for. The recovered *Breadth of Life* sculpture (section 9.1's hidden reward) makes the diagrams visible again to the player who reaches the hidden waterfall chamber where the institution disposed of them.

### 18.8 Visual, aesthetic, and production references

Visual and aesthetic references are in section 6.9 (Pilbara region atmospheric color, Wall-E, the in-game Paranucleus reference). Production tools are in section 6.10 (Blockbench, Crocotile 3D, bounded AI use). Both subsections within section 6 are the canonical homes for those references; this entry is a cross-reference.

### 18.9 Personal and methodological grounding

Per `trawf_notes__1_.md`, the design draws from bioinformatics and neurodegeneration research, autism (the cross-domain pattern-matching that found the cell-type-as-citizen mapping in the first place), and personal relationship history (the cure-creator arc's emotional stakes). These are not citations but acknowledgments; the design is informed by lived experience the author brought to it.

## 19. Scope and current status

### 19.1 Scope

Three acts. Thirty-plus shelters across the main path. Six playable characters (two protagonists, Aster and Peris, plus four party allies: Endo, Myke, Oli, Tyreg). Nine cure components plus a canonical tenth rogue component in Loca's history. Four endings. Two mega-landmark boss encounters (Loca at the Act 1/2 boundary, Paranucleus at the Act 2/3 boundary) plus a final encounter at the end of Act 3 (design pending). A fully designed simulation tutorial expansion (Aster's workspace, Peris's session attack). A post-launch roguelike DLC mode with seven DLC-exclusive playable characters.

### 19.2 Current state

Acts 1 and most of Act 2 have detailed scene work in the GDD and in dedicated source docs. Act 3 has structural design but lighter scene-script coverage. Boss design: Loca is substantially designed (canonical in `loca_boss_spec.md`); the Paranucleus is structurally placed and partially specified at GDD level, with a `paranucleus_boss_spec.md` parallel to Loca's as the next major design work; the final encounter is undrafted.

### 19.3 Open priorities

In rough order: complete the Paranucleus design (`paranucleus_boss_spec.md`); fill in the under-canonized world districts (The Honeycomb Cooperative, The Cleanstreets Initiative, Plumbing Power Project at the diorama level); commit the world map prompt to a generated image for mental-reference use; finalize the open cure-component puzzles (per section 17.4: Flow Aligner, Acid Core, Outflow Expander, Resonator, Rest Cycle Module); draft `book_fragments_spec.md` consolidating the six damaged-book scenes; and stabilize Act 3 scene work.
