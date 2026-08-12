# Flora Taxonomy — Refinement and Sensory Pass

Companion document to the GDD's flora taxonomy (Section 8), to `techos_species_doc.md`, and to `survival_gameplay_feel.md` (which defines the three-tier hiding system). The GDD defines the functional species with their gameplay roles, growth rates, and zone availability. This document adds what the GDD does not cover: Peris's worker vocabulary for each species, their sensory signatures, their state presentations, an ambient-flora category, and the mapping of flora to the hiding-tier system.

## Roster: 6 species + network property

The flora roster was consolidated from 11 candidate species down to 5 in an earlier pass, on the design principle that each species should earn its place through load-bearing mechanics rather than niche functions. Gasafoetida was added later when the Inflammashunt puzzle revealed a need for a flora that produces a portable repellent against any enemy, and the role was distinct enough from existing species to merit its own entry. Scope reduction also helps asset development; fewer models and animations to build, each one used more.

### The 6 species

| Species | Primary function | Secondary function | Tier |
|---|---|---|---|
| **Seefern** | Light / vision extension (pushes back Peris's fog); widest activated zones of any flora | Reveals normally-invisible threats: Hidra outlines, early-stage Crust patches, Redactor bodies | Visibility / counter-stealth |
| **Scarpet** | Biofilm removal, anti-Candid competition with sustained tending | Medium cover (scarred substrate reads as dead to iron-sensors); eating-safe zone outside visual range | Medium |
| **Flure** | Iron decoy (loosest-tier cover) | — | Loosest |
| **Hushbloom** | Enemy stun burst, regenerates over time after use | — | Tactical tool |
| **Capbage** | Tight cover / pursuit-break (self-sealing leaf head) | Eating-safe enclosure; general-purpose storage cache (1-2 items); hide-rest with major tiredness debuff | Tight |
| **Gasafoetida** | Tend produces a held pod that emits repellent gas; while emitting, all enemies in proximity are repelled until the gas runs out | Fire-reactive: cluster pods combust serotinously when ignited, ejecting flaming projectiles in sequence | Tactical tool / hazard |
| **Climbvine** | Produces structural-fiber vines (held items) that can be dropped from height, climbed up and down, tied between rotating surfaces to mechanically couple them, and cut to release the coupling | Grows only on inclined surfaces; planted specimens can only be placed on slopes; the slope-constraint shapes where Climbvine appears in level geometry | Traversal / structural |

**Climbvine institutional name vs Sloperope worker name.** Climbvine is the institutional name (used by professional-class characters and Aster's overlay; describes the visible behavior of climbing). Sloperope is the worker-register name (used by worker-class characters with prior experience of the plant; describes the placement constraint and use, "rope that grows on slopes"). The dual register is documented in `dual_vocabulary_system.md`; Climbvine is one of the few flora species with both registers committed.

**Naturally-growing vs player-planted.** Climbvine has two operational forms in level design. Naturally-growing Climbvine is level-state: specimens placed by the level designer at strategic locations to provide return paths between completed segments of an encounter. These do not revert under any condition; they are world geometry. Player-planted Climbvine is player-state: specimens Peris tends and harvests during play, dropped to bridge specific surfaces as needed. These are temporary; they revert if Peris dies and the runeback resets the player's planted flora (see `runeback_mechanic.md`). The visual design should distinguish the two: naturally-growing Climbvine reads as older, weathered, integrated with the surface it grew on; player-planted reads as fresh, recently-cut, distinctly placed.

**First appearance: Perivascular Channels (Act 1, shelters 2-3).** Climbvine first appears in a side passage off the main Channels corridor. A naturally-growing specimen grows on an inclined surface, leading down to a small alcove containing a lore cache or item pickup. The player tends the vine, harvests it, drops it, descends, retrieves the reward, climbs back up. No tutorial prompts; the affordance is the geometry and the visible plant. The player has already encountered flora-tending in earlier corridors (Seefern, Capbage, etc.) and applies the same interaction to Climbvine; the slope-and-vine geometry surfaces the drop-and-climb use without instruction. By the time the Paranucleus encounter requires Climbvine for serious puzzle navigation, the player has already used it once in a low-stakes context.

**Harvest rate-limiting.** Climbvine harvest is bounded along three dimensions to prevent infinite-supply trivialization of puzzles. (1) Growth time: a tended Climbvine plant produces one vine per rest cycle. The player tends, rests at shelter, returns to find a new vine ready for harvest. Multiple plants tended in parallel each produce independently. (2) Hand-slot capacity: a character carries up to 2 vines at once (one per hand); the party's practical carry is lower because most characters need hands free for tools and combat. (3) Slope availability: player-planted Climbvine can only exist on inclined surfaces, and the level's slope geometry is finite, so the player who has planted on every available slope has reached a hard cap. New plantings require old ones to be cut or to revert via runeback. The combined effect produces a meaningful but bounded supply; careful tending earlier in an encounter pays off later. Naturally-growing Climbvine is not a harvest source: the visible vines hanging between rings as level geometry are fixed in place. Only player-tended plants produce harvestable vines.

### The network property (applies to all tended flora, not a species)

Any tended flora is a node in Peris's connected care network. This is a world-state property, not a species. The more she tends, the more the network does. Three emergent properties:

**Communication.** Information transmits between tended nodes. A Flure that detects a siderophore cluster can signal a distant Capbage to prepare. Players don't interact with this directly; it produces ambient world-feel that care-work has real infrastructure consequences.

**Storm early warning.** Any node that reads atmospheric pressure and chemical signatures propagates storm warnings through the network. The player sees a visible ripple — flora closing, dimming, or stiffening in sequence across the map before a cytokine storm hits. Peris's perception surfaces this as intuition ("something's coming"). The scale of advance warning scales with network density — a sparse network gives short notice, a dense one gives minutes.

**Late-game map layer.** As Peris's own memory degrades, her perception overlay begins pulling data from the flora network. The flora remembers what she planted, where, and what it has sensed since it was planted. The network is her memory externalized. This payoff lands because of her decline — the player who tended throughout the game has a navigational resource the player who didn't has lost access to.

### Naming updates landed this session

| Old name | New name | Reasoning |
|---|---|---|
| Lumivine | **Seefern** | "See" (vision extension) + "fern" (form). Double-reading activates on second look. |
| Rustmoss | **Scarpet** | *Scar* (the moss has metabolized the iron-rich biofilm, leaving scarred substrate) + *carpet* (ground-cover form). The scarred ground reads as dead to iron-sensors; siderophores aren't as interested. |
| Ferrolure | **Flure** | Already settled previously. Mother Flure is a specific individual, not a separate species. |
| Veilcap | cut | Atmospheric filtering redundant with medium cover already provided by Seefern/Scarpet. |
| Rootwall | absorbed into Scarpet | Anti-Candid competition is what a well-tended Scarpet does at sustained effort. No separate species. |
| Stormcap | absorbed into network property | Storm warning is an emergent property of the tended network, not a species. |
| Threadweave / Pando | absorbed into network property | Communication between nodes is a property of any tended flora network, not a dedicated species. |
| Siphonbloom | cut | Peris's decline management lives in shelter rest and the main cure progression, not in a consumable flower. |
| Hushcap | **Hushbloom** | Dropped the fungal "cap." New biology is a thigmonastic plant like *Mimosa pudica* — reacts to proximity, releases a neuroactive burst. Regenerates after use. |
| Dead Zone Seedlings | cut (Seefern grows in Dead Zones if cultivated) | Seefern tended in Dead Zones burns hot and dies in a day, but it is the same species, not a hybrid. Different behavior under extreme stress, not a different plant. |

**Design decision this pass: player flora are all plants; enemy colonizers are fungal or bacterial.** This resolves confusion where "good" player flora (Veilcap, Hushcap, Threadweave) read as fungal while "bad" enemies (Candids, Hyphae) were also fungal. The game's thematic argument reads cleaner when care-work tends plants and colonization is fungal/bacterial growth. Biology has been re-specified accordingly for the surviving species.

### Naming updates landed this session (current edit pass)

| Old name | New name | Reasoning |
|---|---|---|
| Doma | **Capbage** | Portmanteau of *cap* (the leaves close shut) and *cabbage* (the plant form). Biology shifted from generic bulbous flower with petals to a dense head of overlapping cabbage-like leaves with a hollow central cavity that seals shut. Peris's vocabulary updated from "the blooms / my blooms" to "the heads / my heads." |
| Snapbloom | **Gasafoetida** | Portmanteau of *gas* and *asafoetida* (real-world *Ferula asafoetida*, "devil's dung," sulfur-rich resin famously repellent to many animals). The repellent function generalized from camouflaged-enemies-only to all enemies, mediated by a held pod that emits gas while emitting and depletes when the gas runs out. Fire-reactive function preserved, reframed from imprecise "popcorn" register to serotinous-cone biology (parallel to lodgepole pine, jack pine, and certain sequoias whose resin-sealed cones release ballistically under fire). |

## What the GDD taxonomy does and does not do

The GDD taxonomy is function-indexed. Each entry tells you what the flora does in the game (light, biofilm removal, spore filtering, enemy lure, etc.). This is the right organizing principle for design and implementation.

What the GDD taxonomy omits:
- How Peris perceives each species (her sensory read)
- What each species smells like, feels like, looks like at close range
- How the player can distinguish states (healthy vs. dormant vs. stressed vs. dying vs. dead) by sense rather than by data readout
- Ambient flora that has no gameplay function but exists in the world as texture
- Peris's worker vocabulary for each species (she does not say "Seefern" in the way Aster might; she has her own names for what she tends)
- How flora maps to the three-tier hiding system from `survival_gameplay_feel.md`

These omissions matter for scene writing. When Peris identifies a dying flure or notices a forget-me-not blooming in a shelter corner, she is drawing on a sensory vocabulary the GDD does not surface. This document fills that gap.

## Hiding-tier mapping

`survival_gameplay_feel.md` defines three tiers of hiding: **loosest** (positional, no hiding, just not being the most interesting iron source), **medium** (environmental safe zones that mask scent and degrade pursuit over time), and **tight** (pursuit-break, the horror-of-waiting-inside-a-sealed-space moment). Flora species map to these tiers as follows:

| Tier | Flora species | Function |
|---|---|---|
| Loosest | **Flure** | Active iron decoy. Broadcasts a false iron signal stronger than the party's. Siderophores redirect toward it. Not hiding; outcompeting for attention. |
| Medium | **Scarpet** | Scent-masking ground cover. The substrate has been metabolized; iron-sensors read it as dead. Siderophores in idle/foraging state route around Scarpet patches; siderophores in active pursuit follow in but the signal degrades over time inside. **Also: eating-safe zone.** Characters eating held food (starch, lysate) on a Scarpet patch generate no detectable metabolic signal as long as they remain outside enemy visual range during the eating animation. The metabolized substrate's chemistry suppresses both iron and metabolic signatures. Visual range remains the only constraint, which preserves stealth tension naturally (the player still has to position themselves out of patrol sightlines). |
| Tight | **Capbage** | Full pursuit-break through self-sealing leaves. A head of overlapping leaves that opens for characters to enter and seals shut reactively when siderophores approach, the leaves overlapping into a single closed sphere. Character fully undetectable while inside. |

Seefern does not provide cover. Its function in the hiding-adjacent space is counter-stealth: revealing threats the player would otherwise not see. See the Seefern sensory signature section for the reveal mechanic.

The player without a tended flora network can still use architectural tight hides (maintenance closets, alcoves, sealed doors). Capbage become the primary tight-tier option in Zone 3 where architectural cover has decayed; the player who has been tending Peris's work through Zone 2 has tight-hide options in Zone 3 where others have none.

## Peris's worker vocabulary

Peris does not use the institutional or technical names for flora. The system has names like Seefern and Scarpet because the system catalogs things. Peris learned flora through tending, through reaching for what a plant needed before she could name it. Her vocabulary came from the act of care, not from classification.

Her names for the tendable species:

| Species | Peris's word | Etymology in her usage |
|---|---|---|
| Seefern | the vines, the glow-vines, "the little ones" when she is tending them | She does not distinguish between Seefern varieties. They are all "vines." |
| Scarpet | the spread, the low cover, "the clearing stuff" | Named for what it does, not what it is. |
| Flure | the flures (plural), the lures, "the iron flowers" | She distinguishes normal flures from Mother Flure; the individual scale matters. |
| Hushbloom | the quiet-blooms, the silencers | Their stun effect registers to her as quieting. |
| Capbage | the heads, "my heads," the safeholds | She tends them like homes rather than like plants. The possessive is specific to Capbage. |
| Gasafoetida | the stinkers, the pods, "the smelly ones" | She uses "stinkers" most often when she's holding a fresh one, "the pods" when she's referring to the cluster as a whole. The fire-reactive bursts she calls "the popcorn going off" — she keeps the older worker-slang for that specific behavior even though the rest of her vocabulary for the plant has shifted. |

When Peris talks about flora in dialogue, these are the words she reaches for first. Aster may use the technical names because his overlay labels them. Myke and Oli will use whatever they have heard; if they have worked alongside Peris, they may adopt her words. If they learned from institutional training materials, they may use the GDD names. The vocabulary split is a character read: who a speaker names flora by tells you where they got their flora knowledge from.

## Ambient flora: the flowers that are not a gameplay system

The GDD does not enumerate non-tendable, non-functional flora. But the world has flora that is simply alive, growing in corners where conditions allow, contributing atmosphere rather than gameplay affordances. This category is load-bearing for scene work and for the Peris-specific texture of the world.

**Forget-me-nots.** Small blue flowers that grow in shelter corners, near warm infrastructure, in the overlap zones between maintained sections and wild corridors. They require no tending. They bloom on their own when conditions are right. Peris tends them by habit, not because they need it: she pinches dead stems, adjusts their moisture, rearranges them in arrangements she does not consciously design. The flowers are the game's emotional signal for the care instinct that is older than memory. In the bittersweet ending, these are the flowers Peris's hands still know how to tend when her mind no longer knows why. The scent — blue, faint, slightly sweet, layered with the iron-neutralization signature of the Chaperone Lattice — calls her back to herself briefly when she is near them.

Forget-me-nots are everywhere, quietly. Every shelter has some. The Residential Rings are dense with them. The Mother Flure chamber, once the bloom has activated the cascade, shows small blue blooms at the edges of the mother's root system — the chamber was full of them, dormant, the whole time. The player who notices blue flowers in a shelter has registered something the game does not call attention to. The player who does not notice loses nothing.

**Wild cluster flowers (unnamed).** Small, varied, low-growing. Different corridors have different species that emerged from seeds that survived the degradation. These are not catalogued because they are not functional. They are texture. A corridor with healthy wild flowers at its edges is a corridor that still has conditions for life. A corridor with no flora at all, not even weeds, is a corridor where conditions have failed completely. The absence of wild growth is the strongest environmental signal of ecological collapse. Zone 3's Dead Zones are so named because nothing grows there, not even the unnamed ambient flora. The silence of flora is louder than any data readout.

**Moss carpets.** Non-gameplay moss that grows on damp surfaces in the Channels and the Perivascular sub-areas. Visually similar to Scarpet but without the biofilm-clearing function — this is just moss. Peris can distinguish the functional from the ambient by touch; Aster's overlay tags them differently. The player learns to read moss type by where it is growing and how it looks.

**Vine skeletons.** The remains of flora that died and were never cleared. Common in unmaintained corridors. They look like flura in rigor: the shape persists, but the life is gone. Vine skeletons are the environmental version of the dead-flure beat scaled down: every time the player walks through a corridor with vine skeletons, they are walking through the past of a system that could not keep its own growth alive. Peris registers them. She does not speak about them. The player who is paying attention sees her pause near them sometimes.

## Sensory signatures

Each species presents differently to Peris's senses (and by extension to the player, through her perception layer when she is the active character). The game's warm-view rendering for Peris's perception should reflect these signatures.

**Seefern:** Glow is the defining signal. Steady teal-green, slight pulse with the infrastructure's electrical hum. Smells faintly sweet and moist, like rain on warm rock. Touch is cool and slightly slick (moisture on the surface). Stressed Seefern dims unevenly (patches of unlit stem), smells off (more like standing water), and feels dry. Dying Seefern has no glow; the stem is brittle. Dead Seefern is gray-brown, crumbles to touch.

*Reveal function:* Seefern's specific bioluminescent wavelength reveals things that don't show under normal light or Aster's standard overlay. Within the activated glow radius of a tended Seefern, the following become visible:

- **Hidras** (pipe-mimicking siderophores) show a faint internal pulse or outline distinguishing them from real infrastructure. A pipe-dense corridor lit by Seeferns lets the player see which "pipes" are alive before they peel off the wall.
- **Early-stage Crust patches** register as faintly alive rather than as ordinary rust discoloration. The player can identify them before they have established enough mass for Aster's overlay to flag them.
- **Redactors** (late-game invisible enforcement units — see enemy ecosystem) appear as pale body outlines within Seefern radius. Outside Seefern light they are undetectable except by Tyreg's patrol-route map layer.

The reveal function is why Seefern planting becomes strategic in specific corridors, not just anywhere the player wants more light. The player who tends Seeferns in pipe-heavy Maintenance Warrens sees Hidras coming. The player who tends Seeferns in late-game Checkpoint Plazas sees Redactors. The player who doesn't has walked into corridors where real infrastructure is indistinguishable from predators and enforcement is invisible.

*Dead Zone growth:* Seefern cultivated in Dead Zone conditions runs hot. The glow is colder (blue-white rather than teal-green), the scent is acrid (chemical defenses against the sterile substrate), and the plant dies within about a day. The player who carries Seefern seeds into a Dead Zone can produce temporary light at the cost of the seeds, but the resulting plants will not survive long enough to establish. They are consumable light. The reveal function still works in this form, at smaller radius.

**Scarpet:** Low, spreading, near-invisible when healthy (faint greenish-brown against substrate). The signal is textural: the floor feels slightly softer where Scarpet is active, and biofilm presence reads as a resistance underfoot that Scarpet has cleared. Smells neutral, slightly mineral, with a faint dry-earth note from the scarred substrate. Stressed Scarpet develops orange patches. Dead Scarpet leaves a pale residue that reads as calcified dust.

*Contest state:* Scarpet that is actively competing with a Candid colony (late-tended or specifically planted in colonized territory) looks stressed — leaves yellow, stems pale — but is not dying. This is fighting. Whether the Scarpet wins or loses is not visible until the competition resolves, which takes multiple in-game days. The outcome depends on colony maturity, Scarpet tending level, and whether the player reinforces it with repeat visits.

**Flure:** See dedicated section below.

**Hushbloom:** Small, nodding flower on a slender stem, petals folded inward around a central core holding the neuroactive compounds. Pale lavender or white, depending on subspecies. Smells faintly sweet when charged and ready, neutral after release. Touch is velvety; the petals react to proximity by folding further (thigmonastic — the same response that triggers the release). Stressed Hushbloom will not take a charge — the petals stay partly open and the compounds never concentrate. Dying Hushbloom goes translucent. Dead Hushbloom smells sharply of damp stone.

*Regeneration:* After a Hushbloom releases its stun burst, the petals reopen and the central core is visibly empty. The plant regenerates its neuroactive compounds over several in-game hours — roughly the span of a corridor traversal or two. Regenerated Hushbloom returns to its scent-sweet ready state and can be triggered again. Hushbloom destroyed outright (fire, Candid overgrowth, heavy enemy traffic) does not regenerate; the player has to replant from seed.

**Capbage:** See dedicated section below.

## Flora states as sensory readings

For each species, Peris can read state (healthy, dormant, stressed, dying, dead) by sense. The game's data overlay provides labels; Peris's perception provides the underlying experience. Key state signals:

**Healthy:** Full color, full scent signature, expected behavior (closing, glowing, releasing, etc.), responsive to touch (resilient, springy, alive-feeling).

**Dormant:** Reduced color (pales but retains hue), scent is muted but present, behavior paused (not closing, not glowing, but not dead either), touch is less responsive but not unresponsive. Dormancy is rest, not death. A dormant plant in the right microenvironment will re-activate.

**Stressed:** Color is uneven or wrong (patches that should not be there, hues that have shifted away from the species-typical). Scent has a secondary note that is not present in healthy specimens — often more acrid, more chemically charged, more "off." Behavior is incomplete or erratic. Touch may feel dry, brittle, or overly wet (depending on the stressor). Stress is recoverable if the cause is addressed.

**Dying:** Color fading to grays and browns. Scent is specific to the species but unmistakable — the signature of a plant losing its ability to regulate its own chemistry. This is the smell the dead flure leaves in the corridor, and the smell Peris recognizes in the Mother Flure chamber as the mother's stress response. Touch is fragile, non-responsive.

**Dead:** No color, no scent (or, in some species, a residual smell that persists for hours or days). Touch is crumbling, brittle, or collapsed depending on species. Dead flora can still be recognized as the species it was by its remnants, but the life has left it.

The dying-smell signature is cross-species in Peris's vocabulary. She does not have a separate word for "dying Seefern smell" and "dying flure smell." She has one word for the underlying register — something like "the smell of losing" or "the stress-smell" — and the specific species contributes the overtones. This is why the Mother Flure chamber scene works: when Peris says "I know this smell," she is identifying the register, not the species. The species is flure. The register is dying.

## Flure — dedicated entry

The GDD's Ferrolure entry is the gameplay spec. This is the species description as Peris experiences it and as the world presents it.

**Form.** Flures are mid-sized flora, roughly waist-high when fully grown, with a characteristic radial petal arrangement around a central core. The petals are iron-bronze in color with metallic sheen under light. The core is a dense cluster of sensory filaments that secrete iron-attractant compounds. Flures grow with a deep anchoring root system that extends well beyond their visible footprint — a fully grown flure has a root system several times the diameter of its visible body.

**Scent.** Healthy flures smell metallic-sweet, with a note that reads as "wet iron" at close range. The scent carries. A corridor with a healthy flure has a low-level iron presence in the air that siderophores detect from a distance.

**Where they grow.** Flures grow at the intersections of moisture seeps and iron-rich infrastructure — places where the NVU's biological substrate is leaking nutrients into the architecture. They are most common in the Perivascular Channels, in the Supply Lines, and at the junctions where multiple corridors intersect (because these junctions are structurally iron-dense). A corridor without flures is a corridor that either has no iron (rare) or has lost its moisture (common in later zones).

**Species vs. individual.** The GDD's Ferrolure entry describes the tendable species. Mother Flure is a specific individual of enormous scale: a flure that has grown for decades in a containment chamber where conditions are marginal but persistent, reaching a size no normal flure achieves. Mother Flure is not a separate species; she is an outlier. Her root system extends through the entire chamber. Her body is the chamber. Normal wild flures are a fraction of her scale and do not exhibit the portal-stress growth patterns her body shows. The player encountering normal flures in the Channels will not know Mother Flure exists. When they reach the chamber, the scale is the revelation.

**Stress states.** Flures in stress (low iron, damaged root system, poor moisture) develop a different scent: still metallic, but with an underlying note of decay. The sweetness drops; the metal stays. This is the scent that propagates when a flure is dying. It is also, at much lower concentration, what the Mother Flure chamber smells like — she is not dying, but she has been under persistent stress for a long time, and the stress register is present in her scent.

**Dying states.** A dying flure collapses from the core outward. The petals lose their metallic sheen first, graying to a dull bronze. The central core dries and cracks. The root system contracts but remains partially active for some time after the visible body has died, occasionally producing a faint last pulse of iron-attractant. A corpse of a flure in a corridor will still draw siderophores for hours after death, though with diminishing effectiveness. The smell persists longest — a dead flure's corpse retains the dying-stress signature for days before fading.

**Peris's relationship to flures.** Flures are one of the species Peris recognizes from her earliest memory. She may not remember where she learned them, but her hands know how to tend them. They are not particularly difficult flora to maintain in the right microenvironment. Her distress around a dying flure is not about losing the gameplay function; it is about watching something she has an ancient relationship with fail in a way she cannot fix. The dead flure beat in the Channels is her first encounter in the game with flora that is past saving. This registers to her in a specific way that is not fully describable to Aster.

## Capbage — dedicated entry (tight-tier flora)

Tight-tier flora that fills the gap in the hiding hierarchy — flora that functions as pursuit-break cover, parallel to architectural maintenance closets and sealed doors.

**Name.** Portmanteau of *cap* (the leaves close over the cavity like a sealing cap) and *cabbage* (the plant's overall form). The institutional vocabulary kept the worker coinage because no botanist managed to come up with anything better; the form was unfamiliar to the institution's existing taxonomy and the workers had already named it before research caught up. Singular *Capbage*, plural *Capbages*.

**Form.** A large dense head of overlapping leaves, roughly the size of a small closet at full size, set on a short thick stem rising from a tended substrate. The outer leaves are broad and waxy with strong central ribs. The inner leaves curve toward a hollow central cavity. When open the leaves splay outward like a cabbage that has been gently bloomed apart at the top, exposing the cavity. When closed the leaves fold inward and overlap into a single tight near-spherical sealed head — no visible seam from outside, the surface continuous and convex. The transition between the two states is the species' defining feature.

**Biology.** A self-sealing leaf head evolved as a protective response to environmental threat. The cavity at its center naturally hosts small fertilizing organisms during open phases (pollinators, gas-exchange symbionts). When the leaves detect the iron-acidic chemical signature of pursuing siderophores, they fold inward and seal, protecting whatever is inside. This behavior evolved because the cavity's symbionts are vulnerable; protecting them protects the Capbage. In the game, the party fills the role of those symbionts — the Capbage cannot tell the difference. The leaves are thick and fibrous, reinforced with mineral deposits the plant draws up from its roots, and resist siderophore pressure the way cactus flesh resists herbivory.

**Color signals health.** Healthy Capbage leaves are deep green with cream-colored ribs, with the innermost cavity a paler green where less light reaches. Stressed or dying Capbage fade to yellow-grey, leaves wilting and softening at the edges. The healthiest Capbages also have a soft internal luminescence visible at the leaf seams when sealed, like a lantern wrapped in foliage.

### Mechanics

**Capacity.** One character per Capbage is the standard. Rare larger specimens fit two. Three-character Capbages are deep Zone 3, possibly endgame — the player who finds one has a significant tactical resource.

**Entering.** Walk into an open Capbage. Single interaction. The leaves begin folding closed over the character. Close animation takes 2-3 seconds for a wild Capbage, 1-2 seconds for a tended one. During this window the character is vulnerable but the leaves are committed to the closure.

**Closed state.** Character is fully undetectable to all siderophore sensing (iron signal, scent, proximity). Pursuit breaks as if the character had entered a sealed door. Character cannot act while inside but can hear muffled sounds from outside — siderophore clicks, combat, footsteps.

**Opening.** The Capbage opens when it senses threats have left. The player does not trigger opening; the plant does. This is deliberately parallel to architectural tight hides where the player listens for the cue. Here the cue is the leaves relaxing their tension, a soft rustling unfolding sound, a shift in leaf curvature visible at the seam line as the head loosens. Untended Capbages open hesitantly and sometimes prematurely; tended Capbages read the environment reliably.

**Tended vs. wild.** Wild Capbages close slowly, stay closed for minimum duration, may open while threats are still nearby. Tended Capbages close quickly, stay closed as long as threats remain, and read the environment accurately. Upgrading a wild Capbage to a tended one takes Peris's sustained attention across multiple shelter cycles.

**Where they grow.** Only in stable microenvironments — deep in Peris's tended flora network. Capbages won't grow in sterile corridors, Candid-colonized zones, or frequently-stormed areas. Presence of a Capbage signals that this corridor has been cared for. Wild Capbages can be found in the transit between Zone 2 and Zone 3, in places where the NVU's biological substrate is still functioning even if unmaintained.

**Destruction.** Myke's fire kills them instantly. Candid colonies smother them over days. Heavy siderophore traffic through a Capbage's area degrades it. Neglect doesn't kill them outright (they're tougher than other flora) but they fall back to wild state.

**Seeds.** Precious. A single seed produces one Capbage after multiple in-game days of growth in a tended patch. Only mature, well-tended Capbages produce seeds — stressed Capbages don't reproduce. A robust Capbage network represents dozens of shelter cycles of investment.

**Eating inside a sealed Capbage.** A character can eat held food (starch, lysate, etc.) while sealed inside. The cavity contains all metabolic, scent, and visual signal generation; the eating animation is invisible to all detection outside. This makes Capbage the gold-standard eating-safe location, distinct from Scarpet patches which provide eating safety only outside visual range. The trade-off is commitment cost: entering a Capbage means committing to the seal until the plant opens, while Scarpet eating is a quick break.

**Cache (general-purpose storage).** A Capbage can store one or two items as a persistent cache. Wild Capbages hold one item; tended Capbages hold two. The cache mechanic: a character approaches an open Capbage, deposits a held item into the central cavity (single interaction), and the cavity holds the item until retrieved. Any held item can be cached, following the same one-rule-no-exceptions principle as endocytosis: the cavity holds whatever the player puts in it, and the player learns through results what stores well and what doesn't.

When a Capbage holds cached items, it seals shut, the leaves folding over the cavity in the same gesture they would use to seal over a sheltering character. The seal state is the visible cache indicator. An open (splayed-leaf) Capbage holds nothing. A closed (sealed) Capbage holds either cached items or a character inside. Character-occupied Capbages are distinguished by the character's name label hovering over the plant the way character labels appear anywhere else in the world; closed Capbages with no label hold cached items.

Cached items remain in the Capbage until retrieved or until the Capbage dies (in which case all cached items are lost). The cavity's atmospheric humidity and gas exchange preserve most food items the way cabbage refrigeration works in real biology, so starch and lysate cache well as long-term food storage. Other items behave according to their own properties: held tools (Climbvine sections, Gasafoetida pods, Hushbloom samples) cache as inventory expansion; reactive items behave reactively. The player learns the consequences through use.

Some items have specific storage interactions worth noting:

- **Gasafoetida pods** stored in a Capbage have their gas contained by the seal until the cavity opens. When the cavity opens (character entry, retrieval, plant death), the pod emerges still emitting and the gas releases into the corridor.
- **Hushbloom samples** triggered by movement during character entry would stun whichever character entered. The cavity's interior is a constrained space; jostling matters.
- **Flure seeds** can germinate in the Capbage's atmospheric humidity, producing a small Flure inside the cavity that broadcasts iron until it dies. A Capbage with a germinated Flure inside attracts siderophores to the Capbage itself — the opposite of the plant's intended function. The player who learns this learns not to cache Flure seeds in Capbages.
- **Cure components** are stable as cached items.
- **Lysate** kept long-term may degrade; the rotting timeline is slower than corridor-floor rot but not indefinite.

The cache mechanic gives Capbage a second purpose beyond character shelter and rewards Peris's tending across multiple zones: a tended Capbage network is a distributed storage system. Across many shelter cycles, players accumulate caches in Capbages throughout tended territory, expanding the party's effective inventory capacity.

**Cache vs character collision.** A Capbage cannot hold both a character and cached items simultaneously. When a character enters a sealed (stocked) Capbage, the entry triggers the cavity to open. If the character has free hands equal to or greater than the number of cached items, the items transfer to the hands as the leaves part. If not, the unaccommodated items are thrown out of the cavity using the same throw mechanic the player can trigger manually, landing on the substrate just outside the Capbage. The character then enters the empty cavity and the leaves seal again over them.

Once thrown items are on the substrate, they behave according to their normal physics and detection rules: food items attract mobile enemies that converge to consume them, reactive items continue their reactive behavior, stable items just sit there. There is no special "ejected from Capbage" state; the items are objects on the ground.

The dispersal of pursuing enemies happens on roughly the same timeline regardless of whether items were thrown out: once the character is sealed, the iron and scent signals are gone, and pursuers lose their target and disperse. Throwing items out doesn't meaningfully accelerate the clear. What it does is cost the player whatever they couldn't carry. A player with time to plan can manually retrieve cached items before deciding to hide (open the Capbage normally, transfer to hands, manage hand allocation, then re-enter). A player under pursuit may not have time and pays the cost of whatever didn't fit.

The closed-vs-open visual signal makes the mechanic legible. The player can see which Capbages are stocked and which are empty before approaching. Character labels above sealed Capbages further distinguish character-occupied from cache-occupied. Under pursuit, the closest Capbage may be closed; under planning, the player can route to an open one or manage hands first.

**Hide-rest (sleeping inside a sealed Capbage at night).** A character or full party can rest through the night inside sealed Capbages instead of returning to a shelter. Hide-rest is functional but worse than shelter rest. Mechanically:

- Hide-rest does NOT cost ATP (unlike shelter rest, which costs ATP to gain HP recovery).
- Hide-rest does NOT restore HP. Characters end the night at the same HP they started.
- Hide-rest applies a **major tiredness debuff** to all characters who hide-rested. Major tiredness is twice the impact of the minor tiredness debuff that follows a hungry shelter rest (no-ATP rest). Effects include reduced overlay fidelity (Aster reads less reliable data), reduced perception baseline (Peris's morning radius is smaller), reduced stamina regen rate, and reduced stamina cap. The debuffs persist through the next day until the party gets a proper shelter rest.
- Cure component progress does NOT advance on hide-rest nights. Some narrative beats and mechanical progressions require shelter sleep specifically; hide-rest covers survival but not recovery.

The night skips when all conscious party members are inside sealed Capbages (or in a shelter, or in mixed combinations of both — the rule is "all party members are in safe enclosed spaces"). Capbages count as safe enclosed spaces for the night-skip trigger.

The thematic logic: shelter is a place where the party can recover fully. A Capbage is a place where the party can survive. Choosing to hide-rest is a survival call when shelter is unreachable, not a substitute for proper sleep. The major tiredness debuff is the cost of sleeping cramped inside a plant instead of resting in a real bed. Players who hide-rest repeatedly accumulate compounding fatigue that eventually forces a return to shelter.

### Sensory signature

Capbages smell faintly sweet and vegetal, like a fresh-cut cabbage with a honey undertone. The scent deepens when one seals (internal cavity closed, concentrated aromatic compounds released between the inner leaves). Touch is firm but flexible at the leaves, with the central ribs reading as harder structural elements through the surface. Healthy Capbages hum softly when sealed — internal cilia along the inner leaf surfaces rippling to circulate air inside the cavity. The hum is a readable cue for the character hiding inside: steady hum = the plant is comfortable, agitated hum = threats still near, silence = something is wrong (the Capbage is stressed or dying).

### Zone distribution

- **Zone 2 early:** Rare wild Capbages. Mostly architectural tight hides still.
- **Zone 2 mid:** Wild and tended Capbages, roughly equal to architectural hides.
- **Zone 2 late:** Architectural hides degrading; Capbages become the more reliable option if tended.
- **Zone 3:** Almost no architectural hides. Capbages are the primary tight-tier option. Tending them becomes survival-critical.

### Peris's relationship to Capbage

Peris calls them "the heads," often with the possessive ("my heads"). This is unusual for her vocabulary — she doesn't possess most flora, just tends them. Capbages are different because the relationship is more obviously mutualist: she gives them microenvironment and care, they give the party shelter. She recognizes the exchange and names it with possession.

She also treats them like homes rather than like plants. When she approaches a Capbage she has tended, she touches the outer leaves the way someone touches the frame of a doorway they are passing through — acknowledgment, not inspection. When a Capbage she has tended dies, the grief register in her is specifically house-loss, not plant-loss.

### Open design questions

- **Movement between Capbages while sealed:** Probably not. Once sealed, the character is inside until the leaves open. Parallel to architectural tight hides.
- **Sealing with a pursuer partially inside:** Edge case. Default behavior: the leaves' threat detection triggers closure before a pursuer reaches the entrance. If closure is underway when a pursuer arrives, the leaves complete the seal and push the pursuer back.
- **Multiple Capbages in close proximity:** A cluster of Capbages could function as a multi-character hide with redundancy (if one is compromised, the others still protect). Worth exploring in late-game encounter design.

## Gasafoetida, dedicated entry

Gasafoetida is the flora that has two characters and earns both. Tended, it is a defensive tool: a swelling sac released into a character's hands, carried where needed, the sac's repellent gas causing every nearby enemy to flee while the gas continues to emit. Ignited by flame, it is a hazard: the cluster's gas-bearing pods combust in sequence, launching flaming projectiles in random directions that bounce off walls and damage anything in the area. The same plant; two registers.

The biology is grounded in real fire-ecology. Gasafoetida is named for *Ferula asafoetida*, the real-world "devil's dung" plant whose sulfur-rich resin is famously repellent to many animals. The fire-reactive behavior parallels serotinous conifers: lodgepole pines, jack pines, and certain sequoias hold their cones shut with resin that only releases under fire-temperature heat, ejecting seeds ballistically into the post-burn landscape. Gasafoetida's gas-bearing pods follow the same logic. The pods stay sealed under normal conditions; flame ruptures the seal, the gas combusts, and the pods are launched by the resulting pressure. The cluster's two registers are biology's two registers in real serotinous plants: chemical defense at baseline, ballistic dispersal under fire.

### Mechanics

A Gasafoetida cluster grows in damp corners with low light. The cluster takes the form of small bulbous pods on short stems, the pods swelling and contracting visibly with what reads as breathing. Peris can tend the cluster to charge a single pod for harvest; the harvested pod can be carried by any character (it occupies a hand slot) and the repellent gas begins emitting on contact with the carrier's body heat. While the gas is emitting, every enemy in proximity to the carrier is repelled. The effect ends when the gas runs out, typically 30 to 45 seconds depending on cluster health and tending state. A spent pod is inert; the carrier can drop or carry it, but it does nothing until disposed of and a new pod is harvested. The repellent works on every enemy class — siderophores, hunters, enforcement, pathology — because the gas chemistry registers as a universal danger signal rather than a class-specific one.

The fire-reactive function is environmental rather than tended. Any flame source within the cluster's ambient range (Myke's Inflame, lit infrastructure, a flaming projectile from another source) ignites the pods in sequence. The serotinous burst launches 3-5 flaming pods from random points in the cluster, each travelling on a parabolic arc with bouncing physics, each impact dealing fire damage. The cluster regrows the pods over several minutes after ignition. A player who knows where Gasafoetida grows can avoid igniting them; a player who does not has the burst event happen to them.

### The two characters

Gasafoetida's design tension is that the same plant can be a tactical advantage and an environmental hazard depending on whether the player is using fire near it. The player who has Myke in the party and has not learned to recognize Gasafoetida clusters will repeatedly trigger the serotinous burst. The player who has scouted and recognized the cluster shape can use Myke's fire near the cluster intentionally to area-deny enemies clustered nearby (the burst becomes a weapon).

This is the fire-management lesson the Inflammashunt puzzle teaches in miniature: fire is not bad; unmanaged fire is bad. Gasafoetida rewards the player who pays attention to where fire is being applied. Myke in particular has dialogue lines reflecting this: he comments on Gasafoetida clusters when the party walks past one, partly because he has the sensory range to notice them and partly because his Inflame ability is the proximate trigger.

### Sensory signature

Peris perceives Gasafoetida by a sharp sulfurous scent (much sharper than Hushbloom, with the eye-watering quality of overripe alliums or asafoetida resin, reads as "potent and ready to react"). The cluster's breathing motion is visible at close range. Aster's overlay tags Gasafoetida clusters with a small fire-warning icon when his data layer is active.

### Zone distribution

Common in damp Zone 2 corridors, particularly Channels and Maintenance Warrens. Less common in Zone 3, where the dryness reduces growth conditions. The Inflammashunt puzzle's chamber has a Gasafoetida cluster in the damp corner as part of the puzzle's recovery mechanic; this is canonical, established in the GDD's puzzle design.

### Peris's relationship to Gasafoetida

Peris tends Gasafoetida with care because they are reactive in both directions. She is gentle near them, recognizing that they will respond to whatever the environment does. She likes them: they remind her that defense and danger are sometimes the same thing in different contexts. She does not tend them often because each tending consumes the harvested pod, but she can pre-tend before known hostile encounters where a held repellent will let the party walk past anything.

In the Inflammashunt puzzle, Peris's tending of the Gasafoetida for the recovery mechanic is the narrative center of that scene. The plant that is hazard becomes tool because she knows how to ask it for the right reaction. This is character-coherent with her broader pattern: she does not eliminate threats, she finds the version of them that helps.

## Puzzle-only flora: Resolution Roots

The Inflammashunt puzzle features a flora element that is not part of the tendable-species roster: the Resolution Roots that grow from floor cracks in the puzzle chamber and connect to dormant Chelators through underground filaments. These are puzzle-specific flora, not a species the player can encounter, harvest, or tend elsewhere in the game.

Design rationale for keeping Resolution Roots puzzle-only: their mechanic of pacifying Chelators through symbiotic feeding would trivialize Chelator combat if available throughout the game. Chelators are the entry-level enemy whose threat establishes the iron-economy combat loop. A flora that pacifies them would invalidate that loop. The Inflammashunt puzzle's narrative argument is specifically that the Resolution-Root-and-Chelator symbiosis is the resolution-cycle the civilization stopped maintaining; finding a working instance of it is meaningful precisely because it is rare and contextual.

The Resolution Roots have a visual and sensory presentation distinct from the tendable species: they are pale, almost translucent, with visible filaments running underground that pulse with a faint warm light when the symbiosis is active. Peris perceives them as a "warm hum" rather than as a scent or visual marker. She tends them in the puzzle but does not attempt to seed them elsewhere; she understands intuitively that the symbiosis requires conditions that cannot be transplanted.

Treat Resolution Roots as set-dressing flora unique to this puzzle, comparable to the dead-flure scene's specific flure or the Mother Flure as a singular individual. They contribute to the puzzle's narrative weight without expanding the player's broader flora toolkit.

## Implementation notes

**Sensory presentation:** The game's warm-view rendering for Peris's perception should include scent indicators (atmospheric tint adjustments, subtle particulate effects around strong-scent flora) and textural cues (camera proximity producing different visual emphasis depending on species). When Peris kneels near a plant, the player sees what she is sensing as composite environmental rendering rather than as a data readout.

**State transitions:** Flora state changes are events in the engine (see `game_architecture.md` on event sourcing). A stress event fires when conditions change; a dying event fires when stress is sustained; a death event fires when dying completes. Each event produces the appropriate sensory signature change, visible to Peris's perception and recordable in the engram for later recall.

**Vocabulary substitution in dialogue:** When Peris is the speaking character or when her perception is the active frame, flora should be referred to by her worker vocabulary (the vines, the flures, the quiet-blooms, her heads, the spread). When Aster is the speaking character or when the data overlay is active, flora should be referred to by institutional names (Seefern, Scarpet, Flure, Hushbloom, Capbage). Other party members inherit the vocabulary of whoever taught them; Myke uses Peris's words for flora he has seen her tend, Oli uses whatever is in the maintenance registry for flora that appears in infrastructure.

**Ambient flora density:** A given corridor's ambient flora density (moss, wild flowers, vine skeletons) is a readable indicator of that corridor's ecological health. Healthy corridors have visible ambient growth. Degraded corridors have sparse or skeletal growth. Dead Zones have none. Artists should vary ambient flora presence across environments to support this reading.

**Forget-me-nots specifically:** Should be present in every shelter the player spends meaningful time in, quietly, without calling attention to themselves. The player who notices them is rewarded by the bittersweet ending payoff. The player who does not notice loses nothing.

## Open questions

- Whether Peris's worker vocabulary should appear in in-game UI elements (inventory labels, flora menu entries) or only in dialogue. If only in dialogue, the player learns her words through play rather than through interface. If in UI, the vocabulary becomes the canonical names and the GDD taxonomy names become internal reference only.
- Whether dying-flora scent should be mechanically detectable by the player (in some interface) or remain in the dialogue-and-perception layer only. Scent as gameplay information is a real design possibility but adds an interface element.
- Whether additional ambient-flora species should be named or remain unnamed texture. Naming them too thoroughly turns ambient flora into a second taxonomy; leaving them unnamed preserves the distinction between "things Peris actively tends" and "things that are simply alive." Default: leave ambient flora unnamed except for forget-me-nots.
