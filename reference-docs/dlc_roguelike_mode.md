# DLC: Roguelike Mode — Design Asset

Post-launch DLC design for TRAWF's roguelike mode. This doc is the authoritative source for the roguelike design, replacing the DLC section previously in the GDD (around lines 3114-3122, "Roguelike mode: post-launch DLC" and "DLC characters"). That GDD section should be removed when this doc is adopted; a single line in the GDD can point here.

Scope and timing: TBD. Designed as a post-launch expansion, not a base-game feature.

## Core concept

A separate mode with permanent character death, procedurally arranged map elements, no narrative checkpoints. Losing a character means permanently losing their map layer, abilities, and storyline for that run. New run, new configuration, new deaths possible.

The roguelike inherits the base game's systems (perception asymmetry, map layers, event-sourcing state, shelter-based save, siderophore/naturalizer/NK enemy ecology, flora tending, day/night cycle) but strips the narrative scaffolding. No cure arc. No Peris decline over story time. No scripted scenes. The civilization's anatomy is the same; the player's run through it is different every time.

## Narrative framing — timeline ambiguity

The roguelike mode's relationship to the base game's canon is deliberately unresolved. Two readings both work:

1. **Alternate-timeline reading.** The roguelike is simply a separate mode with its own logic, featuring characters the base game established. No diegetic explanation needed. Players who want to just play roguelike runs without narrative overhead take this reading.

2. **Tag-swap reading.** In the base game, the system tracks citizens by their device tags — the things that go green at Tag Day scanners, that get revoked at sanction, that determine who the infrastructure recognizes. The construction-era workers who appear as "dead" in base-game lore (Brobla, Vasca, Senchy, and others at the 12-F collapse) may not all have actually died. The bodies the party finds in the Mother Flure chamber offshoot have tags on them. If a living worker swapped their own tag onto a dead worker's corpse before the bodies were logged and sealed in the chamber, the system would register the corpse as the tag's owner (living) and the living worker as the dead one (gone, no tag to find). The worker is now system-invisible, which is what survival requires.

The tag-swap reading is hinted rather than confirmed: an environmental log here, an offhand line there, a matching tag ID between a construction-era corpse and a roguelike-mode character. Players who notice assemble the inference. Players who don't just play the mode. The reading is not confirmed because confirming it would collapse the base game's treatment of those deaths into a "gotcha." The ambiguity is load-bearing.

This framing has thematic resonance beyond its function:

- It mirrors the system's identity-handling. The institution tracks people by tag, not by person. If a tag is on a corpse, the system registers the corpse as the person. The same weakness that kills people (the system never looks closely enough to see them as people) is what lets some of them escape.
- It ties to Marco's eccentric-coping frame. Marco cycles names and identities to stay un-legible to the institution. The tag-swap is the extreme version of the same strategy: stop using your own tag, use someone else's, let the system track a corpse instead of you.
- It completes the base game's survival-strategy trio: Myke escapes via institutional reassignment (sanctioned), Marco escapes via eccentric improvisation (lateral), the tag-swappers escape via leveraging the system's blind spots (transgressive).

## Playable characters

The roguelike mode's playable roster draws from two pools.

**Main-cast characters** (all base-game party members available as roguelike playables):
- Aster (Astrocyte)
- Peris (Pericyte)
- Endo (Endothelial)
- Myke (Microglia)
- Oli (Oligodendrocyte)
- Tyreg (T-regulatory)

**DLC-exclusive characters** (not party members in base game, introduced as roguelike playables):
- Marco (Macrophage) — base-game recurring NPC, non-joining. See `marco_concept.md`.
- Brobla (Fibroblast) — base-game construction-era terminal-log worker
- Vasca (Vascular smooth muscle) — base-game construction-era worker
- Senchy (Mesenchymal) — base-game construction-era worker
- Swan (Schwann cell) — new for DLC, peripheral-nervous-system insulator, kit-cousin to Oli
- Ninj (Meninges) — previously GDD-listed, concealment and shock absorption
- Pendy (Ependymal) — previously GDD-listed, ventricular system plumbing, knows fluid channels and hidden passages

All DLC-exclusive characters except Swan share the tag-swap reading potential — they are all cells that, in base-game canon, either died in the collapse or are peripheral to the party's direct path. Swan is new to the roster and does not require a tag-swap backstory; he can simply be a PNS cell never catalogued in the base game's CNS-focused narrative.

## Character design — DLC-exclusive cast

### Marco (Macrophage)

See `marco_concept.md` for base-game recurring-NPC design. In roguelike mode, Marco is fully playable, freed from the base game's constraint that he never joins the party.

**Combinatoric chemistry kit.** Marco's signature mechanic is improvised combinations. He carries an inventory of ingredients. Combining two ingredients produces an effect based on their property interaction. The game's in-world vocabulary describes the results as "spells" and the items as "spell components," but the chemistry is real — plant + starch produces smoke, plant + oil produces incendiary, acid + metal produces corrosive bubbling, and so on.

Ingredient categories (examples, not exhaustive):
- **Plant material.** Common. Breathable, burnable, bindable. Base for many combinations.
- **Starch.** Common. Fuel binder, thickener, slow-burn accelerant.
- **Oil.** Uncommon. Fast-burn accelerant, scent carrier, lubricant.
- **Acid.** Rare. Dissolves, etches, produces gases when mixed with plants or metals.
- **Salt.** Common. Preservative, desiccant, electrolyte, abrasive when ground.
- **Metal filings.** Uncommon. Conductive, sparks on impact, reactive with acids.
- **Water.** Ambient. Solvent, steam base, mix medium.
- **Specific plants** (from the flora taxonomy) have their own specific properties: Seeferns glow, Flures have curmoric compounds, Hushblooms stun, Domas cluster.

Combination effects (examples — the full matrix should be designed as a system, not a lookup):
- Plant + starch = smoke bomb ("Cloud of Concealment")
- Plant + oil = incendiary ("Flask of Flame")
- Starch + oil = slow-burn incendiary ("Sticky Fire")
- Acid + plant = toxic smoke ("Vapor of Weakness")
- Salt + water + container = blinding splash ("Stinging Mist")
- Metal filings + acid = corrosive hiss ("Breath of Dissolution")
- Hushbloom + oil = knockout gas ("Sleep Bomb")
- Flure + any accelerant = combat buff (curmoric effects)

Design principles for the combination system:
1. **Effects are legible once the player learns ingredient properties.** Players should be able to predict most combinations after encountering each ingredient a few times. The system rewards experimentation but is not opaque.
2. **Rare combinations produce memorable effects.** Most combinations are variants of smoke/fire/corrosive. A few ingredient combinations produce unique results that players remember and seek out.
3. **Marco names everything magically.** Every combination produces an item called something fantastical (Potion of X, Flask of Y, Scroll of Z, Bomb of W). The mismatch between the magical naming and the chemical reality is the joke, renewed every time the player crafts.
4. **The player learns real chemistry by playing.** If the combination system is designed accurately, players will end a campaign understanding that gunpowder is saltpeter + charcoal + sulfur, that smoke bombs come from potassium nitrate + sugar, that certain acids react with certain metals to produce hydrogen gas. The game teaches applied chemistry through its magic system.

Non-crafting kit elements:
- **Stinging Sand** — signature defensive ability, abrasive powder thrown at opponents for brief disengagement window. Not a combination; always available.
- **Gaseous Form** — movement ability, slow silent traversal along walls with scent-masking. Not a combination; a sustained stance.
- **Borrowed Vocabulary** — passive trait. Marco's interface uses fantasy-game naming conventions (HP → Hit Points, stamina → Mana, abilities → Spells, items → Scrolls/Potions). The player experiences his worldview through the UI translation.

### Brobla (Fibroblast)

**Base-game presence:** log-writing construction worker at Mother Flure site. The terminal entries Aster reads are written by Brobla. Brobla may have died at the 12-F collapse; the log from that event is not signed by Brobla.

**Roguelike role:** the party's builder-survivor. Fibroblasts produce the extracellular matrix — the structural material that holds tissues together. In game terms, Brobla can rebuild damaged infrastructure, reinforce walls, patch breaches.

**Kit (preliminary):**
- **Collagen Lay** — reinforces a structure temporarily (walls, shelter doors, bridges). Costs stamina and ingredients.
- **Matrix Patch** — closes a small environmental breach or seals a leak.
- **Shift Log** — passive, Brobla reads terminals as if he wrote them. Faster terminal interaction, access to older layers of log data.
- **Cutting Crew Reflex** — combat response to flora-based attacks (he's worked around Ferrolure before, he knows not to panic).

### Vasca (Vascular smooth muscle)

**Base-game presence:** brief mention in Brobla's logs ("Vasca needed to leave early").

**Roguelike role:** flow control and pathing. Vascular smooth muscle contracts and relaxes to regulate blood flow through vessels. In game terms, Vasca can constrict or dilate passages, regulating what moves through them.

**Kit (preliminary):**
- **Constriction Pulse** — narrows a corridor section, slowing or blocking enemies.
- **Dilation Wave** — widens a tight passage, making it traversable.
- **Flow Sense** — reveals directional movement in the local environment (which way things are going).
- **Off-Shift** — passive, once per run, Vasca can skip a scripted event by "needing to leave early." Usable to bypass one encounter. Callback to the base-game log entry.

### Senchy (Mesenchymal)

**Base-game presence:** Brobla's logs mention her being hit by Ferrolure while clearing 12-C, walked to medical. Survived that injury (present in later logs? — may need to check, but the base game treats her as part of the cutting crew, probably casualty at 12-F).

**Roguelike role:** adaptive versatility. Mesenchymal cells are the origin stock for many connective tissue types — they can differentiate into multiple cell types. In game terms, Senchy's kit adapts based on what the run demands.

**Kit (preliminary):**
- **Differentiate** — at each shelter, Senchy can choose one of three temporary specializations (Bone, Cartilage, Adipose) that reshape her kit for the next leg. Each gives a distinct survival profile.
- **Stem Pool** — passive, Senchy regenerates slightly at each shelter without needing full resources.
- **Lineage Memory** — if Senchy dies and is replaced by another run's character, the next character inherits one of her active perks for a short time.
- **Cutting Crew Scar** — combat response callback to her Ferrolure injury; takes reduced damage from flora-based attacks but gains a stack of trauma per hit.

### Swan (Schwann cell)

**Base-game presence:** none. New character introduced for DLC.

**Role:** peripheral-nervous-system insulation specialist. Kit-cousin to Oli but with Schwann-cell-specific differences. Schwann cells famously can regenerate myelin after damage, unlike oligodendrocytes. Swan's kit leans into recovery and resilience.

**Kit (preliminary):**
- **Regenerative Myelin** — Swan can restore electrical flow to damaged circuits, similar to Oli but with an additional effect: the regeneration sticks (persistent repair rather than temporary patch).
- **Peripheral Map** — reveals infrastructure outside the CNS areas of the map (areas the rest of the cast is less familiar with). In roguelike terms, access to certain regions that other characters cannot map.
- **Schwann Lattice** — defensive formation, Swan positions himself as the insulator for a nearby party member, sharing damage taken.
- **Nodes of Ranvier** — passive, Swan's abilities cool down faster when he is near another electrical-class character (Oli in particular).

### Ninj (Meninges)

**Base-game presence:** none in the main narrative. Previously listed as DLC character in the GDD.

**Role:** concealment, shock absorption, the brain's protective envelope. Three-layered biology (dura, arachnoid, pia) can be reflected in a three-stance ability system.

**Kit (preliminary):**
- **Dura Stance** — tough outer shell, reduces incoming damage significantly at the cost of movement speed.
- **Arachnoid Stance** — web-like middle layer, reveals nearby hidden enemies through the CSF-analog environmental sensing.
- **Pia Stance** — delicate inner layer, increases precision and interaction fidelity with flora or fine objects.
- **Meningeal Cushion** — passive, Ninj takes reduced fall damage and reduced shockwave damage.
- **Layered Retreat** — at low health, Ninj cycles through stances automatically for defensive layering.

### Pendy (Ependymal)

**Base-game presence:** referenced in Mother Flure spec doc as a log entry author in the Processing Stacks ("the Pendys log entry from the Stacks"). Previously listed as DLC character in the GDD.

**Role:** the civilization's plumbing expert. Ependymal cells circulate cerebrospinal fluid, clear metabolic waste, distribute nutrients. Pendy knows fluid routes the other characters cannot see.

**Kit (preliminary):**
- **CSF Flow** — reveals all fluid pathways in the local environment, including concealed drainage channels and hidden passages that use fluid infrastructure.
- **Cilia Sweep** — cleans a local area of environmental hazards (biofilm, stagnant pools, weak pathogen colonies) through persistent circulation.
- **Ventricular Shortcut** — once per shelter, Pendy can traverse through a fluid channel to bypass a corridor. Costs stamina.
- **Waste Clearance** — passive, Pendy's presence slowly cleans accumulated environmental damage over time.

## Systems inherited from base game

The roguelike mode inherits:

- Perception asymmetry (each character has their own map layer and true-sight range)
- Event-sourcing state (choices persist in the world)
- Shelter-based save (with permadeath overriding revival)
- Day/night cycle with sundowning for Peris
- Flora tending, siderophore ecology, Naturalizer patrols, NK patrols
- ATP/stamina economy
- Combat and capability gating

The roguelike mode removes or modifies:

- Narrative checkpoints — no cure arc, no Peris decline over story time, no scripted scenes
- Party composition — the player selects a starting character and recruits others during the run
- Map structure — procedurally arranged rather than authored
- Death — permanent rather than knockout/revival

## Open design questions

- **Run length and structure.** How long is a roguelike run? Single act? Multi-zone? Single extended descent from Zone 1 to Zone 3? Procedurally-generated arcs with specific goals?
- **Starting character selection.** Does the player pick one character at the start and recruit others during the run, or pick a party of three at the start? Different design implications.
- **Permanent unlocks across runs.** Does the roguelike have meta-progression (unlock new characters, new ingredients, new ability tiers across runs) or is each run a clean slate?
- **Tag-swap reveal depth.** How heavily should the tag-swap reading be hinted? A single environmental-storytelling discovery hidden deep in the mode, or multiple pieces scattered throughout?
- **Brobla's role as log-writer.** Brobla's base-game characterization is most developed (he wrote the logs Aster reads). His roguelike kit has the richest connective tissue to base-game lore. Vasca and Senchy are less characterized; their kits may need more invention.
- **Senchy's survival status.** Brobla's logs say Senchy was walked to medical after being hit by Ferrolure; later log entries are unclear whether she returned to the cutting crew. Roguelike framing may want to resolve this one way or another, or keep it ambiguous.
- **Cross-character interactions.** Do the main-cast characters (Aster, Peris, etc.) react to meeting the DLC characters in-run? The tag-swap reading creates natural dramatic irony: Aster has been reading Brobla's logs for months, and now he might meet someone claiming to be Brobla. Handling: ambient reactive lines rather than scripted scenes, preserving the mode's non-narrative frame.
