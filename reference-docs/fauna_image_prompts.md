# Fauna Image Generation Prompts

A list of image generation prompts for each enemy species in the game's threat ecology, intended for feeding into a generator to produce concept and reference imagery. Each prompt is self-contained: it can be pasted directly into a generator without additional context. Prompts assume the game's voxel-painterly aesthetic (Blockbench and Crocotile base geometry with painterly atmospheric textures).

Common style preamble that should be prepended or appended to every prompt:

> Voxel and low-poly base geometry with painterly atmospheric textures applied over it. Hand-painted brush detail visible on every surface. Restricted palette: muted teals and greens with rust-red and warm cream highlights, near-black background. Diorama-on-dark composition. Soft lighting from one direction, diffuse fill. Single specimen at frame center, isolated against the void. Subject reads as biological organism, not as machine.

## Entry structure

Each entry follows the same template, designed to give the artist the affordances a working creature needs:

- **Tier.** Common (high encounter frequency, simplified detail, silhouette has to read at distance and small size), Mid (moderate frequency), or Rare/Elite (low frequency, full boss-tier detail allowed). Detail budget scales inversely with tier.
- **Silhouette priority.** The one feature that must read at any distance and any zoom. If everything else dissolves, this is what tells the player "that is a Sapscrap" or "that is a Naturalizer."
- **Locomotion.** What moves the body across ground. Where the limbs are, how they engage the substrate.
- **Attack telegraph.** What part of the body changes state to signal an incoming attack. Where the player should look during the wind-up.
- **Hurt / death.** What flinches, breaks, or collapses when hit; what destroyed parts look like.
- **Biological inspiration.** The real-world organism or chemistry the design is grounded in.

The roster is organized roughly by combat role and zone, paralleling the structure of the enemy ecosystem doc.

## Siderophore class

The four siderophore species share a metabolic class but compete with each other. They are iron-foraging organisms.

### Sapscraps

**Tier:** Common. Workhorse swarm enemy, encountered constantly. Silhouette must read clearly at small scale and from across a corridor.

**Silhouette priority:** Three radial palps in C3 symmetry around a central recessed mouth. From above, the organism is a triangular three-pointed shape; from the side, it is a low disc with three forward-projecting hooks. The three-fold radial body plan is the read.

**Form:** Disc-like body sitting low to the ground, roughly chest-high to a small dog. Three forward-projecting hooked palps emerge in C3 symmetry from around a recessed central mouth-pit. Surface is a deep red-violet plated chitin (the iron-enterobactin complex color), simple and matte rather than detailed. The chelating clamps at the palp tips are the only sharply-rendered feature on the body; everything else stays simplified for visual economy.

**Locomotion:** Glides on three short stub-legs hidden beneath the disc body, one per palp segment. Movement is smooth and low to the ground, not insect-scuttling. The body rotates around its center as it changes direction (radial symmetry means there is no front; whichever palp is engaging is the front).

**Attack telegraph:** A single palp brightens with iron concentration (deep red-violet shifting toward magenta) and extends slightly outward as the chelating clamp opens. Brief wind-up, perhaps half a second. The lit palp is the attack direction.

**Hurt / death:** When hit, the body flattens slightly and one palp may snap off if the damage was direct. On death, the disc collapses inward toward its center and the palps splay outward in a triradiate flat shape — the corpse reads as a small dark three-pointed star on the floor. Other Sapscraps route around dead Sapscraps rather than feeding on them (siderophore class doesn't cannibalize).

*Biological inspiration:* Catecholate-class siderophores, particularly enterobactin from *E. coli*, which is a triscatecholate molecule with C3 symmetry that wraps around iron through six oxygen atoms in octahedral coordination. The species' three-fold radial body plan IS the molecular geometry. The deep red-violet color is the actual color of the iron-enterobactin complex.

### Ferrules

**Tier:** Mid. Less common than Sapscraps but still encountered in groups at vessel-breach sites. Detail level moderate.

**Silhouette priority:** Translucent body with a single bright internal core. From any angle, the read is "soft glowing organism with a chartreuse-yellow heart visible through its skin."

**Form:** Soft amphipod-like body, gelatinous and slightly elongated, roughly the size of a small backpack. Outer surface pale green-yellow translucency, flexible rather than chitinous. Inside the body, a single visible cyclic structure (the chromophore) glows chartreuse-yellow, the surrounding gel diffusing the glow outward into a halo. The chromophore pulses slowly with the protein's folding cycle, a steady rhythm that distinguishes the organism from background lighting.

**Locomotion:** Low gliding motion on multiple short flexible feeding tendrils underneath, the way a sea slug glides on its foot. The body undulates slightly as it moves. Slower than Sapscraps.

**Attack telegraph:** The chromophore intensifies and concentrates toward the front of the body (the direction of attack) as a feeding tendril extends. The pulse rhythm accelerates from slow to rapid as the attack winds up. Bright telegraph; the player can read the direction from the chromophore's shift.

**Hurt / death:** When hit, the gel body deforms visibly and the chromophore flickers. On death, the gel deflates and the chromophore dims to a faint residual ember before going out entirely. The corpse is a flat translucent puddle with a small dark spot at the center where the chromophore was, leaking a faint glow at the puddle's edges for a few seconds before fading.

*Biological inspiration:* Pyoverdines from *Pseudomonas aeruginosa*, whose chromophore is a folded dihydroxyquinoline ring system fused around a planar fluorescent core. Pyoverdines fluoresce yellow-green under UV because the chromophore traps electron states in the ring. The species' translucent body housing a single visible chromophore IS the molecular structure made organism. *P. aeruginosa* in real infections is associated with vascular damage sites (wounds, burns, catheters), which the breach-clustering behavior reflects.

### Hidras

**Tier:** Mid. Stationary or slow-moving, common in conduit corridors. Player encounters them as ambient infrastructure-mimic threats.

**Silhouette priority:** Three-fold blade segments along a coiled body. When motionless against cabling, the silhouette flattens; when alerted, the blades rotate slightly and the helix uncoils, breaking the disguise.

**Form:** Long multi-segmented body, roughly arm-thick. Each segment carries three radial blade-fins in C3 symmetry. The body coils in a propeller-twist along its length, segments rotating gradually relative to each other. Blade fins are flat and broad, mottled grey-bronze with metallic sheen at the edges. Recesses between segments are darker, almost black. Eyes are small dark pinholes distributed along the body, one or two per segment.

**Locomotion:** Snake-like undulation, but the propeller-twist gives the movement a screwing motion as the body advances. When camouflaged, motionless against infrastructure. When pursuing, the body unspools from its disguise position and slithers along the substrate, blades flicking outward at each segment.

**Attack telegraph:** The body coils tighter and the blades along the front segments rotate to fully extended position, catching light. Brief still-pose before strike. The strike itself is a fast lunge with the head segment leading, the front blades cutting forward.

**Hurt / death:** When hit, individual blade-fins can be sheared off — the body remains alive but loses C3 symmetry at the damaged segment, the asymmetry visibly affecting locomotion. Severed segments separate from the body but continue twitching for a few seconds. On full death, the body uncoils flat against the substrate, blades drooping outward; the corpse reads as a long ribbed strip with the propeller-twist relaxed.

*Biological inspiration:* Hydroxamate-class siderophores (desferrioxamine from *Streptomyces*, ferrichrome from *Aspergillus*), which form octahedral iron-coordination cages where three bidentate hydroxamate groups wrap around an iron atom in a propeller geometry: three blades meeting at a center, three-fold helical symmetry. The species' three-fold blade-segment body plan IS this molecular geometry. The chain-of-octahedra body extends the molecule into a multi-segmented organism. Earlier in the project the species was called Chains; the rename to Hidras committed to the segmented-helical morphology.

### Crusts

**Tier:** Environmental landmark, not mobile. Treated as terrain rather than as an enemy that approaches the player. Detail level allowed to be high since the player can study it at close range.

**Silhouette priority:** Hexagonal pore-array waxy mat fused into a wall section. The hexagonal close-packing is the read.

**Form:** A thick layered wax-mat colony covering a wall section, the surface architecture an intricate hexagonal close-packed pore array. Matte cream-pale between the pores, each pore a deep dark recess set in the hexagonal grid. Cross-section visible at the colony's edge: three or four layers of pore-arrays stacked vertically, the entire structure built into and partially fusing with the wall it grew on. Color shifts subtly across the colony from pale cream at the older center to faint rust-tint at the actively-growing edge. The boundary between Crust and substrate is effectively gone at the center.

**Locomotion:** None. The colony does not move. The "expansion" the player observes is the slow growth of the colony's outer edge over time — visible across multiple visits to the same area, but never within a single combat encounter.

**Attack telegraph:** When something approaches, pores in the near vicinity dilate visibly and emit a faint puff of acidic vapor — a hazard zone forms in front of the active pores for a few seconds before damaging contact. The dilating pores are the telegraph; the player can step around the affected area.

**Hurt / death:** When attacked, the colony loses sections rather than dying. Damaged areas of the mat crack and flake away, exposing the bare wall beneath. The colony cannot be fully killed in normal play; sustained burning (Myke's flame, environmental fires) clears the colony from a region for the rest of the encounter. The colony will grow back if the player returns much later.

*Biological inspiration:* Mycobactin-class siderophores produced by *Mycobacterium tuberculosis*, which are membrane-embedded rather than secreted: the molecule sits IN the lipid bilayer of the bacterium's outer surface. Real mycobacterial colonies under electron microscopy show a cratered wax-mat structure with the lipid membrane pocked by transmembrane pores arranged in hexagonal close-packing. The species' visual register is this colony architecture made readable at human scale: the hexagonal pore-array IS the mycolic acid arrangement on a real *Mycobacterium* surface. The wall-paranoia behavior reflects mycobacterial intracellular pathogen biology, where the bacterium hides in host membrane infrastructure.

## Colonizer / environment-changer

### Candids

**Tier:** Environmental landmark, not mobile. Like Crusts, the colony is terrain that the player navigates around rather than an enemy that approaches. High detail allowed at close range.

**Silhouette priority:** Three-strata layered fungal architecture. The basal carpet, the chained mid-layer, and the upper canopy must read as three distinct horizontal bands.

**Form:** A fungal biofilm colony with three architectural strata visible in cross-section. Bottom: dense pebbled carpet of small round yeast-cells. Middle: forest of vertical chained pseudohyphal cells stretching upward in connected segments. Top: horizontal canopy of branched true-hyphae forming a filament cap. Pale yellow-cream throughout, with the basal layer slightly darker (older yeast) and the canopy slightly translucent (newer hyphae). Around the colony, a bleached pH-shifted zone where the institutional flooring is visibly compromised.

**Locomotion:** None. Colony grows over the course of the game, expanding its territory by hours of in-world time, never by a single encounter.

**Attack telegraph:** Passive area denial. The bleached pH-shifted zone visibly extends from the colony's edge a meter or so, and characters who stand in this zone take continuous damage. The visible discoloration IS the telegraph; standing on bleached substrate is the warning.

**Hurt / death:** Like Crusts, Candids cannot be killed outright. Burning damages the canopy layer, exposing the chained mid-layer beneath, which is more vulnerable. Sustained burning collapses the colony down through its strata until only the basal yeast layer remains — at which point the colony is dormant for the rest of the encounter. The hurt-state visually shows charred patches in the canopy and the layered structure exposed where the canopy has burned away. Scarpet outcompetes Candids at the colony edge through sustained tending; in regions where Peris has Scarpet established, Candid colonies retreat over time.

*Biological inspiration:* *Candida albicans* biofilms in real immunocompromised infections, which form the canonical three-layer structure: basal yeast layer at the substrate, middle pseudohyphal layer of elongated chained cells, upper true-hyphal layer of branched filaments. The species' three-strata architecture IS the *Candida* biofilm morphology. The pH-shifting and environment-hostile behavior models real Candida biofilm chemistry: secreted aspartyl proteases, biofilm-mediated drug resistance, and the suppression of competing microbiota. The fungal-vs-bacterial distinction is part of the project's design rule that player flora are plants and enemy colonizers are fungal or bacterial.

## Scavenger / engulfer

### Meebs

**Tier:** Common in some zones, rare in others. Detail level moderate. Silhouette must be readable from above and at distance.

**Silhouette priority:** Translucent blob with multiple food cups (mouth-pits) distributed across the body surface, oriented in all directions. The "many mouths" reading is the species ID.

**Form:** A translucent amoeboid organism roughly the size of a small dog, gelatinous and roughly spherical at rest, deforming continuously as it moves. Multiple food cups (deep concave invaginations of the membrane) scattered across the body surface, each puckering outward like a mouth-pit. The body is translucent enough to show internal organization: a centrally-positioned nucleus, contractile vacuoles pulsing slightly, food vacuoles full of partially-digested material visible as darker irregular shapes. Color is pale green-grey, almost transparent at the edges.

**Locomotion:** Pseudopod extension and retraction. The organism flows toward its target rather than walking — pseudopods extend in the direction of movement, then the rest of the body flows after them. No clear front or back; orientation is wherever the largest pseudopod is currently extending. Slow, inexorable rather than fast.

**Attack telegraph:** When close to a target, one of the food cups orients toward the target and dilates wider, the membrane around it puckering outward. The cup brightens as digestive enzymes concentrate. Brief delay before the cup snaps forward to suction onto the target. The dilating, brightening cup is the telegraph; the player can move out of its line of approach.

**Hurt / death:** When hit, the gel body deforms and pseudopods retract briefly. Sustained damage causes the body to lose cohesion: it visibly thins at the edges, the internal organelles exposed through increasingly transparent membrane. On death, the gel collapses into a flat puddle, the nucleus and vacuoles settling at the bottom. The puddle remains briefly visible before being absorbed back into the substrate.

*Biological inspiration:* Free-living pathogenic amoebae, particularly *Naegleria fowleri* (the brain-eating amoeba) whose defining morphological feature is the amoebostome or food cup: a deep invagination of the cell membrane that suctions onto target cells and pulls pieces off. *Naegleria* in real cases of primary amoebic meningoencephalitis uses these food cups to consume host tissue. The species' multiple-food-cup body plan IS this feeding apparatus distributed across the surface. The visible internal chaos (nucleus, vacuoles, partial-digestion contents) is biologically accurate to the *Naegleria* trophozoite stage.

## Enforcement class

### Naturalizers

**Tier:** Rare/Elite. Encountered in patrols of two or three. Player encounters them infrequently but at close range, with full boss-tier detail at the model level. Mid encounter frequency in institutional zones.

**Silhouette priority:** Low quadrupedal-or-hexapodal beetle-like body with a translucent dorsal carapace, glowing internal granule clusters visible through the carapace as warm orange-yellow dots packed together like pomegranate seeds. The "internal lights through translucent shell" is the read at any distance.

**Form:** A polished beetle-like organism walking on six short stubby limbs, body close to the ground, deceptively soft posture. Dorsal carapace is grey-blue with translucent patches across the back revealing dense granule clusters inside, glinting warm orange-yellow. The granules are packed tightly inside the carapace, visible as a stippled luminous interior. A single sharper pale yellow band across the head where sensory receptors cluster. The silhouette is decidedly NOT humanoid: low, focused, polished.

**Locomotion:** Walks on six legs, three per side, in a smooth coordinated gait. Movement is steady and purposeful rather than fast — they patrol rather than chase, but commit when they engage. They can pivot in place by using their legs alternately.

**Attack telegraph:** When engaging a target, the granule clusters concentrate visibly toward a single point on the body — the contact synapse — usually the front of the head or one of the forelegs. That point begins to glow more intensely as granules pack into it, and a brief stillness precedes the strike. The bright concentration point is the attack telegraph and the visual marker for where the deployment will land.

**Hurt / death:** When hit, the dorsal carapace can crack, exposing more of the internal granule field. Heavy damage causes granules to leak out as small glowing droplets that fall to the substrate. On death, the legs collapse and the body settles flat, the carapace cracking fully and the granule field dimming over a few seconds before going dark. The corpse leaves a faint warm afterglow on the floor briefly before fading.

*Biological inspiration:* Natural killer (NK) cells, the innate-immunity lymphocyte class whose killing apparatus is stored INSIDE the cell as cytotoxic granules pre-loaded with perforin (which forms membrane pores in target cells) and granzymes (proteases that trigger apoptosis). Real NK cells deploy this payload through a focused contact synapse called the immunological synapse: the granules concentrate at the contact point and release their contents into the target cell. The species' translucent carapace revealing internal granule clusters IS this biology made visible. The contact-synapse glow models the real synaptic deployment. The bipedal-power-armor humanoid silhouette of earlier design passes was wrong; real NK cells are amorphous lymphocytes with internal payloads, and the species' visual register reflects that.

### Redactors

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

## Hunter / predator

### Gnawers

**Tier:** Common in Zone 3, mid in Zone 2. Encountered in small packs (2-4) or alone. Detail level moderate.

**Silhouette priority:** Low-slung quadruped with a wide, drooping proteolytic maw and a visible enzyme-haze around the head. The "drooling pursuit-hunter" silhouette is the read.

**Form:** A long ratlike quadruped with sleek oily-black coat carrying a faint red-purple heme sheen, hunched predatory posture, body roughly the size of a medium dog but lower and longer. The mouth is wide and drooping, with a constant pale enzyme-mist hanging in the air around the jaws and trailing behind the head as the animal moves. Eyes small, set far forward in a low skull. Heme pigmentation darkest around the mouth and along the lower jaw. Skin is oily and slightly wet-looking.

**Locomotion:** Quadrupedal pursuit. Fast bursts of running with periodic pauses to scan, like a hunting hyena. Body low to the ground with the head leading. Can sustain pursuit for long distances.

**Attack telegraph:** The enzyme cloud around the mouth thickens and expands forward as the Gnawer approaches striking range, a visibly denser haze concentrating in front of the jaws. The mouth opens wider and the jaw drops. Brief pause before the lunge. The thickening enzyme cloud is the wind-up; characters caught in the cloud at the moment of bite take additional proteolytic damage beyond the bite itself.

**Hurt / death:** When hit, the Gnawer recoils backward and the enzyme cloud disperses briefly before re-forming. Heavy damage exposes the underlying tissue beneath the oily coat — pale tissue showing through tears in the skin, contrasting with the dark exterior. On death, the body collapses sideways in a long sprawl. The enzyme cloud lingers around the corpse for a few seconds before dispersing — corpses are briefly hazardous to walk over.

*Biological inspiration:* *Porphyromonas gingivalis* and gingipains, the species responsible for periodontal disease and recently linked to Alzheimer's pathology in published research. *P. gingivalis* is a black-pigmented anaerobic gram-negative bacterium whose dark coloration comes from heme accumulation; in real culture, *P. gingivalis* colonies are visibly black on blood agar. Gingipains are the bacterium's extracellular cysteine proteases — secreted into the surrounding environment to digest host tissue before consumption. The species' visible enzyme cloud around the mouth IS this real biology: real *P. gingivalis* digests outside its body before consuming the products. The metabolic-signature hunting behavior models *P. gingivalis*'s real preference for tissue with active metabolism. The rat-like body is a direct visual rhyme: rats are real Alzheimer's-research carriers of *P. gingivalis*.

### Spikers

**Tier:** Environmental landmark / turret. Stationary, but combat-relevant. Detail level allowed to be high since the player approaches them deliberately.

**Silhouette priority:** Asymmetric pyramidal-neuron geometry. Triangular base, ONE thick apical stalk reaching straight up to a single dendritic arborization at the top, basal dendrites splaying at the floor. The single upward-reaching stalk capped with branched arborization is the read.

**Form:** Anchored to the substrate by a triangular soma at the base, from which one thick apical stalk rises straight upward like a periscope, terminating in a single dendritic arborization at the top branching outward like a fan of bare twigs. Basal dendrites splay at the floor like splayed roots around the base. The trunk is pale teal-white with darker veining along its length tracing the connection pathway from base to top. The triangular soma at the base is the densest, most clearly defined part of the body. The arborization branches at the top point in roughly all horizontal directions, giving the Spiker a 360-degree receptive field from its summit.

**Locomotion:** None. The Spiker is rooted in place. The species' "territory" is the receptive field around it.

**Attack telegraph:** ONE specific branch of the upper arborization brightens when the Spiker acquires a moving target, then a continuous visible filament connects that branch to the target. Charge pulses travel along the filament during the authored damage delay, making the remaining danger legible. If anything blocks line of sight, the filament snaps and fades immediately and the charge resets harmlessly. Only an uninterrupted connection that survives the full delay culminates in a discharge and damage.

**Hurt / death:** When hit, the trunk's veining flickers and the arborization dims briefly. Heavy damage shears off branches of the upper arborization, reducing the Spiker's firing arc. With enough damage, the trunk cracks and slumps. On death, the trunk falls and breaks at the base, the arborization shattering on impact; the splayed basal dendrites remain at the floor like a dead root system. Tau-seeded Spikers (those Tanglers have grappled and propagated tau into) collapse from inside instead — the trunk wilts and the veining goes dark in patches before the whole structure crumbles inward.

*Biological inspiration:* Pyramidal neurons in real cortex and hippocampus, which have a defining triangular soma at the base, a single apical dendrite reaching toward the surface of the cortex, and basal dendrites splaying at the cell body. Pyramidal neurons are the most abundant excitatory neurons in real cerebral cortex and the cells most affected by Alzheimer's-associated network hyperexcitability. Real research shows that Alzheimer's-affected brains exhibit elevated baseline neuronal firing rates and seizure-like activity; the species' "fires at anything that moves" behavior models this hyperexcitable circuit pathology. The asymmetric triangular silhouette IS the pyramidal neuron's defining morphology rendered at organism scale.

### Tanglers

**Tier:** Mid. Encountered alone or in pairs in cognitive-zone corridors. Detail level moderate.

**Silhouette priority:** Double-helix body with grappling filament-extensions. The two intertwined strands are the read; the limbs are extensions of the helix itself, not separate appendages.

**Form:** Two intertwined filament strands coiling around each other in a left-handed helix, the body a continuous corrupted twist of paired strands. Body posture is low and hunched, the central twist sometimes near-collapsed and sometimes elongated as the organism moves. From the surface of the helix, additional filament extensions emerge and unspool toward prey: grappling limbs that are themselves more helix-strands uncoiling outward, with hooked filament ends. No defined head; the front is wherever the body is currently advancing. Color is dark olive-brown with paler highlights along the helix's outer edges, fine ribbing visible along each strand giving a protein-filament texture.

**Locomotion:** The helix flexes and crawls forward by rotating its body in a screw-like motion, the two strands taking turns providing leverage. Slow but persistent. When stalking prey, the body flattens and creeps; when committing, it raises up on the basal strand and the upper portion arcs forward.

**Attack telegraph:** Before grappling, two or three filament-extensions uncoil from the body and reach forward, the hooked ends opening visibly. The reach is slow and visible, allowing the player to step away. The actual grapple is a quick snap of the hooks closing. On contact, the filament begins to drain neural activity from the target — visible as the filament brightening as it transfers material from the target back to the central body.

**Hurt / death:** When hit, the helix loosens partially, the two strands separating slightly before re-twisting. Sustained damage causes the strands to fully separate at one end, reducing the Tangler's body length. Filament-extensions can be severed by attack on the limb itself; severed filaments writhe briefly on the floor before going inert. On death, the helix unwinds entirely, the two strands lying flat against the substrate in a tangled pile that slowly dissolves into protein dust over a few seconds. Tau-seeded victims (Spikers, party members who took grapple damage and didn't recover) carry visible filament-traces on their bodies that persist as a status effect.

*Biological inspiration:* Tau protein pathology and prion-like propagation in Alzheimer's disease. Tau is a microtubule-associated protein that, in pathological states, forms hyperphosphorylated paired helical filaments — two filament strands coiling around each other in a left-handed helix — that aggregate into neurofibrillary tangles. Recent research has shown that tau aggregates can propagate cell-to-cell in a prion-like manner. The species' double-helix body IS the paired helical filament structure made organism. The grappling limbs that uncoil from the body's helix IS the propagation mechanism: contact-mediated transfer of pathological protein machinery, where the limbs are extensions of the same corrupted filament that constitutes the organism. Their neural-activity hunting behavior reflects the real observation that tau pathology preferentially affects hyperexcitable neurons (which is why Tanglers hunt Spikers).

## Burst / detonation class

### Flares

**Tier:** Mid. Stationary or near-stationary, scattered through Zone 2 and Zone 3. Detail level moderate at distance, high if the player approaches deliberately.

**Silhouette priority:** Translucent rounded body with a multi-lobed bead-string nucleus visible centrally, surrounded by three classes of granules in three colors. The "translucent ball with internal beads" is the read.

**Form:** A rounded translucent body roughly the size of a beach ball, sitting low to the ground or slightly above it. Two defining internal features visible through the membrane: a multi-lobed nucleus resembling a string of three or four connected beads at the body's center, and three distinct classes of granules packed densely around the nucleus — small dark purple primary, medium pale yellow secondary, larger pale green tertiary. The granules are scattered through the cytoplasm in roughly equal numbers but at three different sizes and colors, giving the interior a stippled multi-color reading. Membrane is pale yellow-cream with a subtle warm tone, neutral and unthreatening at rest.

**Locomotion:** Drifts slowly along the substrate via membrane contraction, the body subtly distending and re-rounding. Not built for pursuit. The species is essentially a stationary hazard that responds to local triggers.

**Attack telegraph:** When triggered, the granules concentrate toward the membrane surface and the cell distends visibly as it prepares to degranulate. The membrane brightens from within with an inflammatory heat over a 2-3 second wind-up, the bead-string nucleus pulsing rapidly. The brightening membrane and visible distension are the warning; characters in the surrounding area have time to step out of the burst radius. The actual burst is a sudden expansion outward of granule contents in all directions — AoE damage to anything in proximity, regardless of identity.

**Hurt / death:** When hit, the membrane visibly punctures and granule contents leak out as small colored droplets. Heavy damage triggers premature degranulation — the Flare bursts before its full wind-up, doing reduced damage. On death from non-burst damage, the body deflates and the membrane settles into a flat puddle, the bead-string nucleus and remaining granules visible at the bottom of the puddle. After full burst, only the deflated membrane and dispersed granule droplets remain, slowly fading into the substrate.

*Biological inspiration:* Neutrophils, the most abundant innate-immunity cell type in real biology and the primary responder in acute inflammation. Real neutrophils have two defining cellular features that the species visually preserves: a multi-lobed nucleus (typically three to five connected lobes resembling a string of beads, which is one of the most identifiable features under a microscope) and three classes of granules with distinct contents — primary/azurophilic granules (containing myeloperoxidase, dark in standard staining), secondary/specific granules (containing lactoferrin, lighter), and tertiary granules (containing gelatinase). The three-color granule field models these three classes. The bystander damage from oxidative bursts and proteolytic activity that the species inflicts on AoE is biologically accurate to neutrophil behavior in real inflammation: the cells are not malicious, but their activation produces collateral tissue damage as a routine consequence of doing their job.

## Set piece / political target

### Toxos

**Tier:** Common in failed-immune zones (Dead Zones, late Candid colonies). Set-piece in NK Slop scene. Detail level moderate.

**Silhouette priority:** Crescent body with a visible apical conoid and rhoptry-bulbs at the leading point. The "moon-shape with a small spiral cone at one tip" is the read.

**Form:** A small crescent-bodied organism, roughly the size of a small cat. Body curved like a banana, one side longer than the other, the curvature concave toward what reads as the "front." At the leading point of the crescent, a small visible apical conoid: a pale spiral protein cone that extends and retracts as the organism moves, flanked by two slightly bulbous rhoptry-organelles visibly containing secretion vesicles. The rear half of the crescent body holds a darker round mass — the nucleus visible through the body wall. Color is institutional grey with a faint reddish tinge throughout, but the apical structures (cone and rhoptries) read in a paler cream that stands out against the body. Small relative to other organisms.

**Locomotion:** Gliding motion across the substrate, the crescent body undulating slightly. Real *Toxoplasma* tachyzoites use a unique gliding-motility system; the in-game version reads similar — no visible legs, no obvious propulsion, just smooth gliding with the conoid leading.

**Attack telegraph:** The apical conoid extends fully outward and the rhoptry-bulbs visibly swell with secretion vesicles before a strike. Brief wind-up. The strike is a quick lunge with the conoid leading, attempting to penetrate a target's body to deliver invasion factors. Toxos are not strong fighters; their only weapon is the cone, and it is useful primarily for entering host tissue rather than for combat damage.

**Hurt / death:** When hit, the crescent body curls inward defensively, the conoid retracting back into the body. Heavy damage causes the body to lose its crescent shape, deflating into a more rounded sad form. On death, the body collapses and the apical structures release their secretion vesicles harmlessly into the substrate, pale cream droplets fading on the floor. Toxos are easy to kill — they survive only where the local immune system has failed to find them.

*Biological inspiration:* *Toxoplasma gondii*, particularly the tachyzoite stage. Real *T. gondii* tachyzoites have a defining apical complex at the front: the conoid (a spiral protein cone that protrudes during cell invasion), flanked by rhoptry organelles that secrete invasion factors, and supported by micronemes that release adhesion proteins. The crescent body shape is the actual *Toxoplasma* tachyzoite morphology, which is why the apicomplexan phylum gets its name from this apical complex. The species' "everyone hunts them" status reflects the real fact that NK cells evolved with *Toxoplasma* as one of their primary evolutionary pressures, that *Toxoplasma* is engulfed by amoebae and eliminated by neutrophils in a healthy immune environment, and that they survive only where immune function has failed (opportunistic toxoplasmosis in immunocompromised patients).

## Ecology snapshot (not a single species, scene reference)

A cross-section of a single corridor in late Zone 2 showing several enemy species in their natural ecological relationship: a small Sapscrap swarm wandering through the foreground, a Crust patch on the wall behind them, a Spiker rooted in a side alcove with its arborization aimed at the corridor, a Tangler stalking toward the Spiker (drawn by neural activity, willing to risk the firing zone), a Naturalizer patrol approaching from the far end. The composition shows the threats coexisting and competing rather than swarming together. Voxel-painterly style, restricted palette, near-black background, diorama-on-dark composition. Mood: an ecology, not an encounter — multiple threats in the same space, each operating by its own logic.
