# Enemy gameplay roster audit

Status: discussion draft, based on the playable repository and design corpus as of 2026-08-06.

## Why this document exists

The current fauna roster contains thirteen strong biological and visual concepts. That does not yet
mean the game contains thirteen different gameplay decisions. This audit separates:

- the role promised by the design;
- the behavior a player can encounter today;
- the decision that should make the species non-substitutable;
- the places where two species risk becoming different models on the same chase-and-hit behavior.

The standard is not “does it have different stats?” It is: **would replacing this threat with another
one change the player's prediction, positioning, timing, target priority, resource choice, or use of
the surrounding ecology?** If not, it is another bowl of oatmeal.

This is an audit and discussion surface, not new canon. Open recommendations below are proposals,
not settled implementation requirements.

## Current bottom line

The designed roster is more diverse than the playable roster.

- `Enemy` supplies one substantial shared behavior: patrol or roam, detect, alert, pursue, wind up,
  charge, impact, recover, search, return; it also supports lure, stun, damage, concealment loss,
  dodge, save/load, and deterministic replay.
- `Naturalizer` is the strongest species-specific mobile implementation. It adds the environmental
  hesitation-zone relationship used by the lockout chase, but most of its designed tag-enforcement
  and inter-species selectivity is not yet a general species rule.
- `Sapscrap` has its own tuning and visual, while its authored Open Files encounter provides a real
  iron-purge reroute. The subclass itself is still predominantly the shared Enemy behavior; the
  fixture-draining and swarm-level role are not yet portable species behavior.
- `CandidZone` is a real, mechanically distinct terrain threat: damage-over-time in exchange for
  full concealment from scans. Its palette entry still says `placeholder`, so implementation truth
  and generation metadata disagree.
- `ChainEnemy` is the existing Hidra runtime. Its tethered segmented body and segment-contact
  footprint are real; its wire/cable disguise and reveal interaction are not yet implemented.
- The remaining named species are presently design, visual, palette, or procedural-grammar entries,
  not portable species-specific gameplay implementations. Generated content can therefore advertise
  more fauna variety than the runtime can honestly deliver.

In practical terms, players currently get roughly four threat grammars—generic mobile attacker,
environmentally slowed elite attacker, tethered Hidra attacker, and damaging concealment terrain—
not thirteen.

## What the canonical GDD commits

The GDD is substantially more specific than the current runtime:

- Ecological threats are divided into autonomous enemies and deterministic environmental hazards.
- The thirteen species are an interacting ecology, not isolated encounters. They compete, hunt,
  avoid, reveal, suppress, and attract one another according to species rules.
- Combat is valid but “rarely the most efficient” answer. Reading the ecology and routing one threat
  through another is intended to be a primary play style.
- Enemy behavior is deterministic. Uncertainty comes from incomplete or stale character perception,
  not random enemy rules.
- Distribution records history: a quiet Spiker corridor, dead Spikers near Tanglers, or Flares under
  a Naturalizer route should let the player infer what happened before arrival.
- The ecology changes across acts as species displace one another, so revisiting an earlier region
  should not mean fighting the same population with larger numbers.
- Every species has an authored silhouette, locomotion, attack telegraph, hurt/death read, and
  biological basis in the GDD's visual-specification section.
- Aster's auto-evade package is meant to work only on species whose attack pattern has been scanned.
  The first encounter with an unscanned species therefore creates an observation problem, and a
  dodged charge can be redirected into another actor or environmental hazard.

The GDD explicitly acknowledges one missing source: `techos_species_doc.md`, which was supposed to
hold the full four-species siderophore specification. Its available material was folded into the GDD
from `enemy_ecosystem.md`, but the dedicated source itself is absent.

## Required retrieval map for future enemy work

Enemy-related work must consult the sources below before changing gameplay, a level, an encounter,
or procedural generation. The information was split across documents, which is why reading only the
runtime or only the short roster produces a false picture of the design.

| Source | What it owns | Important caution |
|---|---|---|
| This audit | Current implementation truth, overlap risks, anti-oatmeal gate, and explicit director rulings | A design or palette entry is not counted as implemented without executable species behavior. |
| `../../reference-docs/to_rust_gdd_v02.md`, sections 2.7 and 7 | Thirteen-species ecology, deterministic-information model, inter-enemy matrix, progression effects, and full visual/telegraph specifications | It still contains stale fast-bolt wording for Spikers. Apply the rulings in this audit. |
| `../../reference-docs/fauna_roster.md` | Concise per-species niche, encounter role, tell, and counter | A mirror of the director's original; it can lag the rulings in this audit. |
| `../data/enemy_ecosystem.md` | Target-selection relationships, predation, avoidance, environmental effects, and distribution-as-history | These are design commitments, not evidence that the relationships run in-game. |
| `ECOLOGY_COMBOS.md` | Flora-by-fauna interaction matrix with canon/derived/open confidence labels | Preserve those confidence labels; do not turn a derived or open interaction into canon silently. |
| `../data/generation/content_palette.json` and `../scripts/generation/biomes.gd` | Names and content that generation may request | `implemented`/`placeholder` metadata can drift and must be checked against runtime classes and tests. |
| `../../reference-docs/fauna_image_prompts.md` | Silhouette, anatomy, motion, tell, damage, and corpse reads | Visual distinction supports gameplay identity but does not substitute for it. |
| `../scripts/game/ai/` and `../scripts/game/objects/` | What actually executes today | A generic `Enemy` configured with different numbers remains generic behavior. |

Precedence when sources disagree:

1. Explicit director rulings recorded in this audit.
2. Current canonical GDD and roster intent.
3. Companion ecology/composition documents at their stated confidence level.
4. Generation metadata and visuals, which describe availability but never prove behavior.

If a required reference is absent or stale, stop and surface that fact. Do not reconstruct the
missing mechanic from a palette tag, class name, visual silhouette, or remembered chat summary.

## Evidence labels

| Label | Meaning |
|---|---|
| **Implemented** | A reusable runtime class executes the species-defining choice, not just its presentation. |
| **Partial** | Some authored encounter or subclass behavior is real, but the complete role is not portable. |
| **Environmental** | Real gameplay exists as terrain or a field rather than a mobile enemy actor. |
| **Placeholder** | The name, tags, visual, grammar, or generation slot exists without species-defining runtime behavior. |
| **Unresolved** | Runtime behavior exists, but its canonical species identity has not been decided. |

## Roster at a glance

| Species | Designed gameplay role | Player question that should define it | Playable status today | Oatmeal risk |
|---|---|---|---|---|
| **Sapscraps** | Common iron-draining swarm | “What iron source will the swarm choose, and what will it strip if I wait?” | **Partial.** Dedicated tuning/visual and an authored iron-purge reroute; otherwise shared chase/charge behavior. | **High now.** Without portable swarm and fixture-drain rules, it is a small generic attacker. |
| **Ferrules** | Breach/chokepoint ambusher that punishes lingering | “When is the gap safe, and can I cross without dwelling in its flare zone?” | **Placeholder.** Palette, biome, visual assets, and design encounters exist; no Ferrule FSM. | **High.** Easily collapses into either a stationary Spiker or a generic pursuer unless lingering—not mere presence—is the trigger. |
| **Hidras** | Infrastructure mimic that ambushes unscanned movement | “Is that cable real, and do I spend perception before committing movement?” | **Partial.** `ChainEnemy` implements the segmented, tethered lunge and authoritative contact along the entire body. Wire/cable disguise, reveal, and the transition from scenery to attacker remain unbuilt. | **Medium-high.** Its reach is already distinct, but without infrastructure camouflage the defining prediction still overlaps an ordinary visible ambush. |
| **Crusts** | Regrowing wall colony that denies wall-hugging routes | “Which wall band is about to vent, and is clearing it worth temporary access?” | **Placeholder.** No portable Crust field or growth state found. | **Medium-high.** Risks becoming Candid-on-a-wall unless it specifically changes cover, edge routing, and wall access. |
| **Candids** | Toxic floor colony that suppresses other threats and scans | “Do I pay health to use the corridor enemies cannot safely use?” | **Environmental.** `CandidZone` applies DoT plus full concealment in data fragments. Growth layers, retreat, and most ecology remain unbuilt. | **Low for the existing strip; high for expansion.** The health-for-concealment inversion is already distinct and should remain its core. |
| **Meebs** | Slow indiscriminate engulfer and mobile ecosystem cleaner | “What can I feed it, and when does digestion open a passing window?” | **Placeholder.** Procedural visual grammar exists; no engulf/digest/target-size runtime. | **High.** A slow pursuer is only a speed variant until feeding and digestion change the room. |
| **Naturalizers** | Fixed-route institutional scan patrol with lethal enforcement | “Who will its scan classify as incoherent, and which environmental interference defeats that scan?” | **Implemented/partial.** Dedicated subclass, patrol/chase/strike, save authority, and hesitation zones are real. General tag classification and ecological target politics are incomplete. | **Medium.** It reads distinctly in authored chase content, but generic combat use can reduce it to a fast white attacker. |
| **Gnawers** | Pack hunter attracted to the strongest metabolic signal | “What is loudest metabolically, and can I redirect the pack before it surrounds us?” | **Placeholder.** Palette/design/visual grammar only; no metabolic target election or pack topology. | **High.** Otherwise just a faster multi-enemy pursuit. |
| **Spikers** | Rooted line-of-sight tether that locks, connects, and damages after a delay | “Can I break line of sight before the connection matures?” | **Placeholder.** No Spiker actor, target connection, delayed damage, or line-of-sight cancellation runtime found. | **Medium-high.** It needs a persistent, readable connection whose damage is prevented by breaking LOS—not a generic projectile or instant sniper hit. |
| **Tanglers** | Stealth grappler that punishes isolation and seeds a lasting status | “Who is exposed, who can perform the rescue, and can we redirect it toward neural prey?” | **Placeholder.** No grapple, rescue, or tau-status runtime found. | **High.** Without party-binding and rescue, it overlaps both Hidra ambush and Redactor grapple. |
| **Flares** | Neutral bomb whose delayed area burst hurts every side | “Should I trigger it now, and where will every actor be when it bursts?” | **Placeholder.** No neutral trigger/wind-up/AoE ecology actor found. | **Low in design, high in implementation risk.** Friendly-fire and player-controlled timing are inherently distinctive; a hostile AoE caster would not be. |
| **Toxos** | Weak failed-zone opportunist and ecological bait | “Which healthier predator can I pull toward this prey, and what does its presence tell me about the zone?” | **Placeholder.** Visual grammar/design only. | **Very high if treated as combat fodder.** Its best role may be ecological resource/indicator rather than conventional enemy. |
| **Redactors** | Late invisible enforcer requiring external revelation | “What evidence suggests an unseen patrol, and how do I make the ecosystem perceive it?” | **Placeholder.** Palette/design only; no cloak/reveal/attack runtime found. | **Medium-high.** Reveal-gating is distinct, but a post-reveal generic attacker wastes most of the concept. |

## The overlap clusters we should discuss

### Hidden threats: Hidras, Tanglers, Redactors

These currently share the broad pitch “something concealed attacks you.” Their non-overlapping
decisions should be protected:

- **Hidra:** authenticity and pre-commit inspection. It is infrastructure until disproved. The
  mistake is trusting an unverified route element.
- **Tangler:** formation and rescue. It should be readable before the grapple, but dangerous when a
  member is isolated. The mistake is failing party coverage.
- **Redactor:** perception infrastructure and indirect exposure. Evidence is ecological absence or
  spatial distortion; the solution is making the room able to see it. The mistake is trusting an
  apparently empty institutional space.

If all three merely decloak near the player and enter the shared pursuit FSM, keep one and cut or
redesign the others.

### Route denial: Ferrules, Spikers, Crusts, Candids

All four control where or when the player can cross, but should operate on different dimensions:

- **Ferrule:** dwell time in a chokepoint; movement through the gap is safer than hesitation.
- **Spiker:** sustained line of sight; it locks onto one target, draws a visible connection, and
  damages only if that connection survives its delay. Cover severs the connection and cancels the
  pending damage.
- **Crust:** wall-edge availability over a regrowth cycle; it removes perimeter safety and cover.
- **Candid:** floor chemistry; it exchanges health for concealment and ecological exclusion.

A palette swap over the same red damage strip would erase all four identities.

### Pursuers: Sapscraps, Meebs, Gnawers, Naturalizers

Move speed is not enough to separate these:

- **Sapscraps** choose iron and become dangerous through swarm mass and infrastructure depletion.
- **Meebs** choose engulfable biomass, pause to digest, and clear other small threats.
- **Gnawers** elect the loudest metabolic signal and coordinate as a surrounding pack.
- **Naturalizers** choose targets through institutional eligibility and follow predictable patrol
  jurisdiction.

The target-selection rule—not health, speed, or damage—should be the primary source of variety.

### “Fodder”: Sapscraps and Toxos

These should not both be weak bodies the player clears quickly. Sapscraps are a multiplying resource
pressure; Toxos are evidence that immune control has failed and bait for healthier predators. Toxos
may belong in the encounter-resource column rather than the hostile-combatant column.

## Anti-oatmeal implementation gate

Before a species moves from placeholder to implemented, record its answer on each axis:

| Axis | Required question |
|---|---|
| Target selection | What does it choose that another species would ignore? |
| Trigger | What player or world action activates it? |
| Spatial pressure | What formation, route, cover, or territory becomes newly important? |
| Temporal rhythm | What must be predicted: cadence, accumulation, digestion, growth, wind-up, or pursuit? |
| Consequence | What changes besides ordinary HP loss? |
| Counter | What intervention changes its rule rather than simply stunning or damaging it? |
| Ecology | What does it hunt, avoid, suppress, feed, reveal, or attract? |
| Information | What evidence lets a player predict and revise their model? |

A new species should differ from its nearest neighbor on at least three axes. At least one difference
must be in **target selection, spatial pressure, consequence, or ecology**. Stat changes, color,
silhouette, and animation do not count toward the three.

Every implementation review should also answer:

> If this actor were replaced with the shared `Enemy` and its numbers adjusted, which player decision
> would disappear?

If the answer is “none,” the species is not implemented yet.

## Suggested discussion order

1. **Fix the inventory truth.** Reconcile palette support with runtime reality. Candids have a real
   environmental implementation; most palette fauna do not. Generation should not present a
   placeholder identity as completed variety.
2. **Decide whether this is an enemy roster or a threat-ecology roster.** Crusts and Candids are
   terrain; Flares and Toxos may function primarily as manipulable ecosystem pieces. That is useful
   variety, not a defect, but the category should say so.
3. **Choose one representative from each overlap cluster for a complete vertical slice.** Build the
   species-defining target rule, consequence, counter, ecology interaction, and readable feedback
   together before multiplying variants.
4. **Make Sapscraps genuinely systemic.** Move iron choice, fixture depletion, and swarm behavior
   out of one authored encounter and into reusable species authority. They are the baseline against
   which the rest of the roster will be judged.
5. **Complete Naturalizer eligibility.** Preserve the patrol/jurisdiction behavior and make the scan
   decide among tagged party members and relevant fauna instead of behaving as generic aggro.
6. **Complete the Hidra identity already carried by `ChainEnemy`.** Preserve its tethered reach and
   whole-body contact, then add the authored wire/cable resting state, reveal evidence, and unspool
   transition. The legacy class name can remain for scene compatibility.
7. **Protect ecosystem interactions as gameplay, not flavor text.** A Meeb eating a Sapscrap, a
   Gnawer changing targets when a Flare bursts, or a revealed Redactor becoming visible to other
   fauna should alter authoritative targeting and produce inspectable evidence.

## Candidate first vertical slices

These are attractive because each tests a different kind of systemic identity:

| Candidate | What it proves | Why it is a good anti-oatmeal test |
|---|---|---|
| **Meeb + Sapscrap** | Cross-species predation, digestion delay, temporary route window | Proves enemies can be manipulated as actors in an ecology rather than separately fought. |
| **Spiker + movable cover** | Target lock, visible connection, delayed damage, and LOS cancellation | Proves a static enemy can create a cover-timing problem in which topology interrupts an attack already in progress. |
| **Flare + mixed room** | Neutral trigger, delayed all-sides AoE, aftermath attraction | Proves target allegiance is not the organizing rule for every threat. |
| **Tangler + two-member rescue** | Formation pressure, binding, rescue, persistent status | Proves party topology can matter more than damage output. |
| **Ferrule breach** | Linger threshold, timed gap crossing, decoy/douse counter | Proves “chokepoint ambusher” is not just a stationary generic attacker. |

## Naming and source hygiene

**Director ruling: Ferrules is the canonical current name.** The retired names must not be treated
as separate species or used for new content. The whole corpus now uses Ferrules — code, data, docs,
generation palette, and the `reference-docs/` mirror. `docs/concept-prompts/fauna.md` holds the
rename record; `--test-canon-fauna-names` fails on a retired name anywhere else.

**Director ruling: `ChainEnemy` is the Hidra runtime.** Its segmented body is meant to blend into
wires and similar infrastructure before it reveals and attacks. This identity is settled even
though the camouflage/reveal portion is not implemented yet.

**Director ruling: the Spiker is a delayed line-of-sight connection threat, not an instant-hit
sniper.** It locks onto a target, visibly connects to that target, and deals damage only after the
connection persists for the authored duration. Breaking line of sight immediately breaks the
connection and prevents that damage. The GDD's older “fast bolt” visual-spec wording is stale where
it conflicts with this rule; its rooted body, receptive field, target indiscrimination, and
directional telegraph remain applicable.

There is a second unresolved name, **Chelator**, in the Inflammashunt/Resolution Roots material. It
is explicitly not one of the thirteen roster entries. Existing discussion favors resolving that
role to Sapscraps, but this document does not make that ruling.

## Evidence used

- Canonical GDD enemy overview, roster, ecology matrix, gameplay implications, and visual specs:
  `../../reference-docs/to_rust_gdd_v02.md`, sections 2.7 and 7
- Canon roster: `../../reference-docs/fauna_roster.md`
- Current ecosystem interactions: `../data/enemy_ecosystem.md`
- Current generation inventory: `../data/generation/content_palette.json`
- Shared mobile behavior: `../scripts/game/ai/enemy.gd`
- Species/runtime subclasses: `../scripts/game/ai/sapscrap.gd`,
  `../scripts/game/ai/naturalizer.gd`, and the Hidra runtime
  `../scripts/game/ai/chain_enemy.gd`
- Implemented Candid terrain: `../scripts/game/objects/candid_zone.gd`
- Current biome promises: `../scripts/generation/biomes.gd`
- Visual-only procedural support: `../scripts/generation/creature_grammar.gd`
- Systems-thinking standard: `SYSTEMS_THINKING_PUZZLE_STANDARD.md`
