# Enemy Ecosystem

Working document for inter-enemy dynamics in TRAWF. The NVU is not a zoo of discrete threats the party walks through. It is a dysfunctional ecosystem where every inhabitant is stressed by every other inhabitant. Enemies fight each other, avoid each other, eat each other, disrupt each other. The party is one more agent in a multi-sided mess, and sometimes the smartest play is letting two enemies handle each other while you slip through.

This document complements the enemy specs in the GDD and the canonical roster (`reference-docs/fauna_roster.md`, with per-species art specs in `reference-docs/fauna_image_prompts.md`). Where those documents describe what each enemy is and does, this one describes what they do to each other and how the player can read, route around, and weaponize those relationships.

## What this doc is and is not

This is a design reference for how enemies interact. It is not a master enemy list (that lives in the GDD) and it is not a combat balance document (that lives with the combat design work). The goal here is to establish that the NVU is an ecosystem whose inter-species dynamics emerge from the dysregulation that produced the civilization's collapse in the first place. The reason all these enemies are hostile to each other is the same reason the civilization is dying: the regulatory systems that kept their relationships functional have stopped working. Every enemy in the NVU is trying to do its old job in a context where its old job no longer makes sense.

## Roster quick-reference

The thirteen enemy types covered here, with one-line role summaries. Full specs are in the GDD or in `reference-docs/fauna_roster.md`.

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
| Redactors | Late-game invisible enforcers, deepest institutional class | Membrane-cloaked pathological T-cells; molecular mimicry via host-derived membrane sequestration (cf. *Trypanosoma* antigenic variation) |

## Siderophores compete with siderophores

The four siderophore species (Sapscraps, Ferrules, Hidras, Crusts) all share a class but they do not cooperate. They compete for iron, and because different species prefer different iron sources, they settle into territorial divisions when iron is abundant. Where iron is scarce they displace each other. A Crust patch on a pipe is denying that pipe's surface iron to every Sapscrap nearby. A Hidra burrowed into a conduit makes that conduit's iron unavailable to Ferrules. A Ferrule cluster near a breach is concentrating the local iron economy in a way that starves the smaller siderophores in adjacent corridors.

The competition is visible to the player as distribution patterns. Heavy Crust coverage on a stretch of wall correlates with reduced Sapscrap population in that stretch. Hidra-dominated conduit sections are quiet of other siderophores. The player who learns to read these patterns can infer which species will be present where before seeing them.

None of the siderophore species attack each other directly. Their competition is metabolic, not combative. But a Sapscrap displaced by Crust dominance is a Sapscrap looking for iron elsewhere, which may mean a Sapscrap that shows up in a corridor that was quiet yesterday. Shifts in one siderophore species' territory push other species into new areas.

## Candids poison the environment for everyone else

Candids change the chemistry of corridors they colonize. The local atmosphere shifts toward conditions that favor Candid biology: low oxygen, altered pH, biofilm matrix blanketing surfaces, reduced airflow. These conditions are hostile to almost every other enemy type, not because Candids attack them but because the environment itself becomes uninhabitable.

Tanglers avoid Candid zones because the biofilm chemistry disrupts their protein filament integrity. Their bodies would unweave if they stayed too long. They route around colonized areas.

Naturalizers' tag-scanning becomes noisy and unreliable in Candid air. The sensors are calibrated for healthy tissue chemistry, and the biofilm interferes. Naturalizer patrols skip colonized corridors because their equipment stops working there.

Siderophores have trouble navigating the altered iron gradients inside a colonized zone. The biofilm absorbs and locks iron in its matrix, denying it to the siderophore sensing systems. A heavily colonized corridor is a corridor that reads as iron-dead to a Sapscrap, which is a reason the Sapscrap doesn't go there.

The player can use this. Moving through a Candid colony is slow and consumable-reducing because the corridor is degraded, but it is also Naturalizer-free and Tangler-free and low on siderophores. The GDD calls this out in the Naturalizer section already. A party member with a compromised tag who needs to move through Naturalizer territory can route through a Candid zone instead, trading the tag-scan risk for the biofilm-exposure risk.

Candids themselves do not attack. They just make the area uninhabitable for everything else.

## Meebs eat what they can engulf

Meebs are indiscriminate predators. Anything within their detection range that is small enough to engulf gets engulfed. Siderophores are the primary food source. A Meeb rolling through a corridor clears out Sapscraps in its path, freezes while digesting, and continues drifting.

They cannot eat Candid colonies because the colony is too large and too embedded in the infrastructure. They ignore Tanglers because the filament structure is tougher than the siderophore bodies Meebs are built to digest; an attempted engulfment would fail. They do not engage Naturalizers, who are immune enforcement with defensive responses that would damage the Meeb. They cannot catch Gnawers, who are faster.

So Meebs are a natural siderophore predator and an obstacle to everything party-sized or smaller. A corridor that Meebs are patrolling is a corridor with low siderophore density. The player can route through Meeb corridors for relative safety from siderophores, accepting that the Meebs themselves are a threat.

A Meeb currently engulfing a siderophore is frozen and temporarily safe to pass. This is the player's window to move past a Meeb that would otherwise be dangerous. The engulfment takes several seconds. The Meeb is locked in place. The player who has observed this pattern can turn a Meeb encounter into a Meeb-assisted transit.

## Naturalizers have complicated immune politics

Naturalizers have a specific enforcement mandate: scan tags, remove incoherent presences. They ignore most pathogen-class enemies because siderophores, Candids, and Meebs do not carry tags at all. They are pathogens, not tagged entities. Naturalizers were built to enforce the body's internal coherence, not to fight external invaders.

The exceptions are biologically specific.

Naturalizers engage Toxos. Natural Killer cells are literally the immune response real biology evolved to kill Toxoplasma. In the NVU, this is preserved: Naturalizers on patrol will actively hunt Toxos if they detect them. Toxos in Naturalizer territory lose fast.

Naturalizers engage Tanglers if the tangles are disrupting tagged tissue. Tau pathology in a region the Naturalizers recognize as part of the body triggers their enforcement response. This is inconsistent because tau is technically a self-protein, so tag coherence is ambiguous; sometimes Naturalizers engage, sometimes they ignore.

Naturalizers and Flares have a failing alliance. In a healthy NVU they would be on the same side, both institutional immune response. In the dysfunctional NVU, Naturalizers have started scanning Flares as threats because Flare degranulation produces cellular debris that trips the tag-incoherence detector. They shoot each other sometimes. A Flare degranulation event in a Naturalizer patrol zone may produce a Naturalizer response against the surviving Flares. The immune system is turning on itself because the signaling that used to distinguish friend from debris has degraded.

The player can observe this. A corridor with Flare corpses and active Naturalizer patrols is a corridor where the system ate its own response team. This is one of the NVU's saddest environmental storytelling beats. The institutional enforcement is not evil; it is malfunctioning. The Flares were doing their jobs; the Naturalizers were doing theirs. The signals between them collapsed and now they kill each other.

## Gnawers hunt metabolic signatures, any metabolic signatures

Gnawers detect metabolic activity and converge on the strongest signal in range. They do not distinguish between party members, siderophores, Flares mid-degranulation, or Spikers completing a connection. They want the metabolic spike.

A siderophore feeding on iron produces a strong metabolic signal. Gnawers in range will latch onto feeding siderophores, ignoring the party entirely. The GDD already covers this as the core Gnawer mechanic: a living siderophore ecosystem is cover because the ecosystem generates louder signals than the party does.

Flares degranulating are a massive metabolic signal. Gnawers converge on a Flare burst site. The Flares are already dead or dying from the burst; the Gnawers arrive to scavenge. A Flare event in Gnawer territory produces a Gnawer pileup that takes both species offline for several seconds.

Spikers completing a damaging connection produce a brief metabolic spike at the discharge moment. Gnawers may converge on a Spiker that has just completed a connection before it can recover. A Spiker in Gnawer territory cannot complete connections often without being latched onto during the recovery window.

The ecological consequence is that Gnawers thin the populations of whatever is metabolically loud around them. Corridors with heavy Gnawer presence have quieter ecosystems because the loud species get eaten and the quiet species survive. The player who wants a quiet corridor should go where Gnawers have been for a while.

## Flares are ecosystem detonations

A Flare event is catastrophic for the local ecology. Flares converge on damage sites, arrive in packs, and degranulate in radial bursts that damage everything in radius. This includes other Flares that arrived in the same convergence, which means Flare packs kill themselves as part of their firing pattern. The enzyme burst also damages siderophores in range, Tanglers in range (the inflammatory environment degrades protein aggregates), Candid colony edges, and any other biological entity the burst touches.

Every Flare event reshuffles the local ecology. A corridor that had a Flare burst five minutes ago has:
- Reduced or eliminated siderophore population in the burst radius
- Damaged Tangler filaments if any were nearby
- Cellular debris that will attract Gnawers within minutes
- Possible Naturalizer response if the debris trips the tag-incoherence detector
- Chemical signaling that may flush Cytokine Storm systems (see GDD section 6.5)

The player can weaponize this. Triggering Flare convergence in an area the party does not want to stay in creates a temporary ecological void. The burst clears the immediate threats, and by the time other enemies drift back in, the party has moved on. Myke's Inflame explicitly generates damage signals that attract Flares; in a crowded corridor the player can use Myke as a Flare magnet deliberately, drawing the Flares to the damage site while the rest of the party slips around it.

The cost is that the Flare event is real, and getting caught in it is devastating. The player who miscalculates the timing takes the burst.

## Spikers connect to anything that moves

Spikers do not distinguish targets. When anything moving enters a Spiker's receptive field with a clear line of sight, the Spiker locks on and establishes a visible connection to it. The connection must remain unbroken for an authored delay before it discharges and deals damage. Breaking line of sight at any point immediately severs the connection, cancels the pending damage, and forces the Spiker to reacquire. Siderophores, Naturalizer patrols, Gnawers, Tanglers, and party members all follow the same rule.

The ecological consequence is that Spiker corridors tend to be depopulated of enemies that cannot reach cover before a connection matures. Siderophores learn to route around; those that do not get killed. Tanglers who hunt neural activity are drawn toward Spikers as a food source, but they must cross its connection field and repeatedly break line of sight or reach it before the delay expires. Many Tanglers die in exposed Spiker corridors before reaching the Spiker that drew them.

A Spiker that has been completing connections regularly for a long time has a corridor around it that is unusually quiet of other enemies. The player may find a Spiker's territory easier to traverse than a siderophore-swarmed one if they can route between sightline breaks. The corridor is clean because the Spiker cleaned it.

## Tanglers hunt neural activity

Tanglers feed on neural activity. They propagate by contact with cells that contain tau-compatible machinery, which means neural tissue. They are drawn to areas where neurons still fire, which in the dying NVU is a short list.

Spikers are a Tangler food source. Tanglers actively hunt Spikers because hyperexcitable neurons are the strongest neural activity signal in the NVU, and because tau pathology in real biology is known to target hyperexcitable neurons. A Tangler approaching a Spiker has to navigate the Spiker's connection field, and many die when they fail to break line of sight before the delay expires. The ones that succeed grapple the Spiker and propagate their tau into the Spiker's cellular machinery. A Spiker that has been tau-seeded eventually collapses. The player may find dead Spikers in corridors where Tangler populations have worked through the local Spiker population.

Tanglers avoid Candid colonies because the biofilm chemistry disrupts their filament integrity. Candid zones are Tangler-free, which the GDD already notes.

Tanglers are damaged by Flare degranulation because the inflammatory environment degrades protein aggregates. A Flare event in Tangler territory thins the Tangler population temporarily.

Tanglers are indifferent to siderophores because siderophores contain no neural tissue to convert. The two species pass each other without engaging. A corridor with both Tanglers and siderophores is a corridor where the two threats are operating in parallel without interference.

Tanglers are drawn to areas with existing tau pathology, which means the NVU's old cognitive-function zones (the Open Files Initiative, signal conduit networks, anywhere neurons were dense in the living architecture). The player can read corridor history by Tangler density: heavy Tangler presence means this was an area where thinking happened once.

## Toxos are everyone's target

If Toxos become a player-facing enemy beyond the NK Slop set piece, they occupy a specific ecological position: almost everything hunts them.

Naturalizers are built to kill Toxos. Real NK cells evolved specifically to handle Toxoplasma. In the NVU, Naturalizers in Toxo range engage immediately and do not route around them.

Gnawers are drawn to Toxo metabolism. Toxos in a Gnawer corridor get latched onto quickly.

Meebs can engulf Toxos because Toxo cell size is within Meeb digestion range. Meebs near Toxos eat them.

Flares do not specifically target Toxos, but a Flare burst near Toxos damages them.

Toxos survive best in corridors where the immune system has failed. Candid zones where Naturalizer scanning is disrupted. Areas where Naturalizer patrols have been killed by Flare friendly fire. Dead Zones where no immune response is functional anymore. Toxo distribution is a map of where the NVU's immune system has lost ground.

## Redactors are invisible to normal perception

Late-game enforcement class. Membrane-cloaked pathological T-cells that have adopted antigenic-mimicry biology from Candid horizontal gene transfer — the enforcement apparatus has learned to be undetectable. The name is institutional euphemism: to *redact* is to erase from the record, which is exactly what this class does to people. (The retired institutional-Latin name derived from *no-* + *soma*, no-body, echoing *Trypanosoma* — the real parasitic genus famous for membrane cloaking.) Workers adopted the institutional name rather than inventing their own because Redactors are relatively recent and workers who encountered them rarely survived to coin slang.

**Detection.** Redactors are invisible to all standard sensing: character sight, Aster's data overlay, Peris's warm perception. They don't trigger the ambient sound design other enemies produce. The corridor looks and feels empty when Redactors are patrolling it.

**How the player can see them.**

- **Tyreg's patrol-route map layer** reveals Redactor routes regardless of visibility. She's the same biological class (regulatory T-cell); her enforcement credentials recognize what they are under the cloak. This is the same mechanism by which Naturalizers ignore her.
- **Seefern light** reveals their physical body as a pale outline within the activated glow radius. A Seefern-lit corridor lets the player see Redactors directly.
- **Direct contact** (too late). When a Redactor engages, the player learns it was there.

**Engagement.** Silent wrap-grapple, similar to Tangler mechanics but without the proximity warning. A character grappled by an unseen Redactor is being attacked by something the player cannot address until they bring Seefern light into the area or have Tyreg confirm presence. The attack is not instantly lethal — it is a sustained contact that drains the character until they are down. Other party members can free the grappled character if they can see the Redactor (Seefern coverage, Tyreg present) or if they attack the grapple position blind (possible but wasteful of resources).

**Distribution.** Rare in late Zone 2 (Beacon Hill onward). More common in Zone 3. Densest near institutional infrastructure: the Checkpoint Plazas late game, the deep Beacon Hill, the The Cleanstreets Initiative near the civilization's surviving institutional nodes. Thematic: the more institutional a zone is, the more Redactors. Where the institution is strongest, its most evolved enforcement class operates.

**Ecosystem interactions.** Redactors occupy a specific niche — they are the institution's answer to ecological problems the civilization's standard enforcement (Naturalizers) can't handle. They hunt what Naturalizers can't see: Candid scouts, Toxo infiltrators, anyone with a tag failure that slipped past standard scanning. In this sense they are enforcement targeting the things the institution officially denies exist. They don't interact with other enemies the way most species do — they move through the ecology invisibly, picking off targets, and the ecology doesn't register their presence until biomass disappears.

The one exception: Seefern reveals them. A tended Seefern network in a Redactor-patrolled corridor produces something new — other enemies in that corridor can also see the Redactors, and a Flare burst or a Candid's environmental toxicity affects them normally once visible. Seefern light ecologically "exposes" them to the rest of the ecosystem, which has interesting late-game consequences in Zone 3 where Seefern-lit corridors become sites of chaotic multi-enemy engagement that Redactors triggered.

**Compositional run implications.** The Aster/Peris-only run is specifically harder in late-game Zone 2 and Zone 3 because neither character has Tyreg's patrol-route map layer. The player must compensate with aggressive Seefern cultivation in all institutional-heavy corridors. The player without Tyreg who has also neglected Peris's Seefern network walks through late-game Zone 2 being ambushed by enforcement they cannot see. This is intentional. Flora infrastructure as survival — the player who tended the network has a way to survive; the player who didn't has a problem.

**Counter (once visible).** Tyreg's gun works. Myke's fire works (and is unusually satisfying here — the institution's invisible elite burning). Oli's barrier can block Redactor pursuit. Peris's wrap can protect a grappled character while someone else addresses the Redactor. The Redactor's strength is the invisibility, not its combat capability. Once visible, it fights like a somewhat-weaker Naturalizer.

## The inter-enemy matrix

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

**Redactors are not in the matrix** because their cloaking makes them ecologically silent. Other enemies do not register their presence and do not interact with them under normal conditions. The exception is Seefern light: once a Redactor is revealed by Seefern glow, other enemies in the revealed area can perceive it and engage normally. A Flare burst in a Seefern-lit corridor damages visible Redactors. Candid toxicity affects revealed Redactors. Gnawers can lock onto revealed Redactor metabolism. This produces a late-game tactical pattern: the player who lights up a Redactor-patrolled corridor with Seeferns can make the corridor's own ecosystem turn against the Redactors, rather than confronting them directly. The enforcement becomes a target the moment it becomes visible.

## What this changes for gameplay

The enemy ecosystem has emergent behavior. The player does not just navigate enemies; they navigate enemy relationships. A corridor that looks empty might have had a Flare event that killed everything. A Tangler swarm concentrating in an area suggests Spikers nearby that the Tanglers are hunting. A suspiciously quiet Naturalizer patrol zone might be a Candid colony deadening their scans. A pile of dead Spikers indicates recent Tangler activity. A stretch of wall with Crust coverage has fewer Sapscraps for reasons the player can work out.

The player can weaponize these relationships. Leading a Tangler into a Candid zone degrades it. Drawing a Spiker connection onto a Tangler patrol can clear the patrol if the target remains exposed for the full delay. Triggering Flare convergence in a Gnawer-heavy area creates a Gnawer pileup that takes both species offline. Myke's fire triggers Flare convergence intentionally when the party needs a distraction. A party member who has been marked by a Naturalizer can wait in a Candid zone for the scan to lose its lock.

Enemy distribution tells corridor history. A corridor with heavy Candid colonization and no other threats had enemies once but the Candids drove them all out. A corridor with Spikers and no siderophores means the Spikers cleared the siderophores over time. A corridor with Tanglers and dead Spiker remains means the Tanglers fed here recently. A corridor with Flare corpses and active Naturalizer patrols is a corridor where the system ate its own response team.

The party is not the apex threat. In most combat games the player is the strongest thing in the room. In TRAWF, every encounter is multilateral. The enemies would be fighting each other even if the party was not there. The party walking through a corridor is a perturbation in an already-running system, not a force imposed on passive hazards.

## The political ecology

All these enemies were, at one point, part of a functioning system. Flares were immune responders doing their jobs. Naturalizers enforced tag coherence to preserve the body's integrity. Siderophores were part of normal iron economy. Candids lived in small colonies that the immune system managed. Spikers were normal neurons firing normal action potentials. Tanglers were not a thing at all until tau pathology emerged.

The reason they are all hostile to each other now is that the system regulating their relationships has collapsed. In a healthy NVU, Naturalizers do not scan Flares because tag coherence is stable. Flares do not fire AoE at nothing because damage signals are meaningful. Siderophores are fed by regulated iron distribution. The dysregulation that made the NVU dying made the enemies fight each other. They are all trying to do their old jobs in a context where their old jobs do not make sense anymore.

That is a real thing about neurodegeneration: the cells and molecules that maintain the brain start attacking the brain when regulation fails. The enemies hating each other is not a fantasy element; it is what neurodegeneration is. Cells losing the signals that told them when to stop.

This is also the thematic bridge to the game's politics. The NVU's institutional framework (funding decisions, resource allocation, regulatory oversight) failed in specific ways that produced the cellular dysfunction the party is now navigating. Naturalizers attacking Flares is the cellular-scale version of institutional departments turning on each other when the regulation between them stops working. The Candid colonies making Naturalizers unable to function is the cellular-scale version of an unmonitored population growing in a niche the enforcement class can no longer reach. Every inter-enemy relationship in the matrix has a real-world political analog, which is why the game's biology is doing the same work as its politics.

The player does not need to see this connection to enjoy the gameplay. The player who does see it finds a second layer that rewards attention. The ecosystem is the argument.

## Open design questions

The following are not yet resolved and should be addressed in future design passes.

Balance: whether the ecosystem interactions are primarily observed by the player or actively weaponizable. Both modes exist, but the ratio affects how much the player is meant to manipulate vs. read. A heavy manipulate-ratio turns the game into an ecosystem-engineering puzzle. A heavy read-ratio keeps it closer to survival with occasional clever moments.

Scripting vs. emergence: whether inter-enemy interactions are scripted encounters (Flares always converge at predictable sites) or emerge from AI behavior (Flares converge because damage signals cross their detection threshold). Emergent is cleaner worldbuilding but harder to tune; scripted is more reliable but reads more artificial.

Visibility to the player: how much of the ecosystem the player needs to understand for the game to work vs. how much should be discoverable. Aster's overlay can show some relationships (detection cones, metabolic signals). Other relationships are observed through pattern recognition across many encounters. The design should decide how much tutorialization to offer for this system.

Late-game rebalancing: whether the ecosystem changes over the course of the game as the NVU degrades further. Early game, the ecosystem relationships are dysfunctional but still following recognizable patterns. Late game, the dysfunction has progressed, and the patterns may break down further. Flares may start attacking Naturalizers more aggressively. Tanglers may expand out of neural zones as tau pathology spreads. The player should feel the system getting worse as they progress.

The critical design constraint on this feature is **readability**. The player has spent the early and mid game learning the ecosystem's patterns. Changing those patterns late game without signaling the change breaks the contract: the player's hard-earned knowledge becomes wrong without warning, which reads as the game cheating rather than the world changing. If late-game rebalancing is implemented, the changes must be signaled clearly to the player.

Signaling approaches worth considering:
- *Environmental cues.* Tanglers appearing outside their neural zones should be visually marked, either by the Tanglers themselves looking different (degraded, more aggressive morphology) or by the corridors carrying visible tau signs (filament residue on walls, Aster's overlay flagging tau presence in a zone where it was not before).
- *Character commentary.* Myke, Aster, or Oli noticing the change and naming it in dialogue. A line like "Those were not here before" or "Something changed in these corridors" lands the information with the player directly. This is the cheapest signaling method and works if the character voice stays consistent.
- *Terminal logs and Aster's overlay.* The information trail can include entries about the ecosystem's progression. A log entry reading "tau presence detected outside canonical neural zones" gives the attentive player the context for why Tanglers are showing up somewhere new.
- *Tutorial beat at the transition.* Whenever the ecosystem shifts, a short scripted encounter teaches the new pattern. The player meets the new behavior in a controlled context before it starts appearing everywhere.
- *Audiovisual distinction.* Enemies behaving in new ways (Flares attacking Naturalizers, Tanglers expanding range) should look and sound different enough that the player recognizes something has changed, even without dialogue.

The test for whether the signaling is adequate: a player who has been paying attention should be able to predict the new pattern from the cues, or should at minimum recognize "something changed and here is what it is" rather than "the game is behaving inconsistently." If the player cannot predict or quickly recognize the shift, the feature is broken regardless of how interesting the underlying biology is.

Default position given the readability constraint: implement late-game rebalancing only if the signaling is rigorously designed into the transition. If signaling would be insufficient or the design effort is disproportionate, hold the ecosystem stable and find other ways to escalate late-game difficulty.

Interactions with cure components: whether deploying a cure component locally changes enemy relationships. A Chaperone Lattice in a corridor redistributes iron, which changes siderophore territory. A Rest Cycle Module stabilizes local circadian signaling, which may affect Spiker firing patterns. These are cure-specific questions that the main cure design work should address, but the ecosystem document notes the question.
