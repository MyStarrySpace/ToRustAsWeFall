# Flora Image Generation Prompts

A list of image generation prompts for each flora species in the game, intended for feeding into a generator to produce concept and reference imagery. Each prompt is self-contained: it can be pasted directly into a generator without additional context. Prompts assume the game's voxel-painterly aesthetic (Blockbench and Crocotile base geometry with painterly atmospheric textures).

Common style preamble that should be prepended or appended to every prompt:

> Voxel and low-poly base geometry with painterly atmospheric textures applied over it. Hand-painted brush detail visible on every surface. Restricted palette: muted teals and greens dominant, warm cream highlights, near-black background. Diorama-on-dark composition. Soft lighting from one direction, diffuse fill. Single specimen at frame center, isolated against the void.

## Entry structure

Each entry describes the plant's visual design only:

- **Silhouette priority.** The one feature that must read at any distance and any zoom.
- **Form.** The static look: shape, proportions, color, material, surface detail.
- **States.** The visual appearance of each distinct state.
- **Hurt / death.** What dying or destroyed flora looks like.

The roster includes each plant species, plus one set-piece (Mother Flure) and one scene reference.

## Seefern

**Silhouette priority:** Fern fronds with bright glowing veins. The veins-as-lantern is the read at any distance — at small scale, the plant reads as "a small thing made of glowing veins."

**Form:** A small fern, roughly knee-high at maturity. Translucent fronds with bright cool teal-green vein structure as the dominant light source — the central spine runs bright from base to tip, with branching veins fanning out into each leaflet, brightness concentrated along the veins. Where there are no veins, leaf tissue is darker translucent green, almost shadowed. Each leaflet carries an eye-marking: a dark oval at the leaflet's center surrounded by a bright vein-ring, so each leaflet reads as an eye looking outward. A mature Seefern reads as a small fern with dozens of glowing eyes facing outward in all directions. Young fronds at the tips curl in fiddlehead pattern. Substrate is a soft mossy ground with a fainter, paler glow from a slower-glowing moss species.

**States:**
- *Wild:* veins glow at low intensity, the eye-markings dim and nearly closed; reads as dormant.
- *Tended:* veins glow at full intensity, the eye-markings bright and clearly open as outward-facing eyes.
- *Stressed:* veins burn unusually bright, almost overdriven, the eye-markings wide-open and vivid.

**Hurt / death:** Damaged fronds dim and the eye-markings close shut. With most fronds lost, it glows weakly from the central stalk only, a single eye-marking on the surviving leaflet. On full death the plant goes dark and the fronds wilt. If colonized, white mold-like mat creeps up from the substrate and the eye-markings close as it advances.

## Scarpet

**Silhouette priority:** Low dense moss mat with two integrated colors — pale green of living moss and rust-orange of metabolized iron-extracted patches — visible across the surface. The "two-tone moss carpet" is the read at a glance.

**Form:** A low dense moss mat, roughly the area of a large rug, with the body of the carpet rising 5-10 centimeters off the substrate. Pale green of living moss in the actively-growing patches, rust-orange shading to dark brown in the metabolized zones where iron has precipitated within the moss tissue. The boundary between the two states is irregular, with rust streaks and patches scattered through the green like scars worked across living surface. At close range, texture is specifically moss-like: small leafy moss-shoots visible as tiny overlapping leaves, structure dense and pillowy. The substrate beneath fully-metabolized patches shows a bleached scar-like discoloration.

**States:**
- *Wild:* small patch, mostly green with limited rust streaking.
- *Tended:* large patch, rust streaks distributed through the carpet, substrate beneath visibly bleached across most of the patch's area.
- *Senescent:* mostly rust-brown with little remaining green; the moss looks dried and dying.

**Hurt / death:** Fire leaves a charred patch across the moss. Under colonization, green moss gives way to white mold-like canopy, with a thin contested boundary where the two meet.

## Flure

**Silhouette priority:** Trumpet-shaped flower atop a slender stem, with iron dust visibly hanging in the air around the lower stem. The "flower with reddish atmospheric haze" is the read.

**Form:** A flowering plant rising from a small basal rosette, slender stem 30-50 centimeters tall, single trumpet-shaped flower at the top. Basal rosette leaves are dark and iron-stained (older, iron-saturated), reading as faintly metallic-bronze. Mid-stem leaves are progressively lighter and greener. The trumpet flower is plant-like, NOT made of metal: the petals are normal flower tissue with copper-toned veining showing where iron has concentrated. Petals fade from rust-red at the tips to amber at the throat. From the soil around the base, faint reddish dust rises into the air as atmospheric haze. The roots are visible just at the soil surface as red-dark fibers spreading outward.

**States:**
- *Wild:* small flower, single trumpet bloom, faint dust visible only in close proximity.
- *Tended:* full bloom, multiple subsidiary trumpets opening from the central stem, dust rising in a clear visible column from the base.
- *Spent:* petals droop and fade to dull amber, dust thins to nothing.

**Hurt / death:** Damaged, the petals fall and the dust dies out. On full death the plant collapses, the basal rosette the last thing to dim, the iron-stained leaves fading to grey, with a final pulse of iron dust released as it dies.

## Hushbloom

**Silhouette priority:** Compound leaves with paired leaflets along a central spine, leaflets splayed open in resting state. The "comb-like fern" silhouette is the read.

**Form:** A small plant with several compound leaves emerging from a slender drooping stem. Each compound leaf carries small paired leaflets in opposite pairs along a central spine, comb-like, with 8-12 leaflets per compound leaf. Leaflets are pale green on their upper surfaces with slightly purple-tinted undersides. Stems are slightly purple-tinted with darker purple at the leaf nodes. At the base of each leaflet, a visible flex-node reads as a small bulbous node, faintly translucent, with a subtle inner pulse of pale lavender-grey. The plant overall is lower and more spread than upright, fern-like in posture.

**States:**
- *Charged:* leaflets fully splayed open, flex-nodes swollen and bright, the plant looks visibly tense like a balloon under pressure.
- *Triggered:* the leaflets have folded inward in a wave along each spine, the entire compound leaf drooping along the stem in a folded fan shape. Pale lavender-grey haze visible briefly around the plant. Flex-nodes deflated.
- *Recharging:* the leaflets still folded but the flex-nodes slowly re-inflating — an in-between look, not yet fully open.
- *Tended:* multiple compound leaves splayed simultaneously, taller and bushier than wild specimens, flex-nodes brighter.

**Hurt / death:** Damaged leaflets shrivel and fall. On full death, all compound leaves droop limply, the flex-nodes go grey-white, and the plant slumps onto the substrate.

## Capbage

**Silhouette priority:** Dense head of overlapping leaves with a visible cavity at the apex. The "cabbage with a hole on top" silhouette is the read at any distance.

**Form (open state):** A large dense head of overlapping concentric leaf layers, roughly the size of a small closet, on a short thick stem. Outer leaves deep green with prominent cream-colored veins, layered in 4-5 concentric wrappings around the cavity, each layer slightly smaller and lighter in color. The innermost leaves curve inward to form the cavity wall, paler green where less light reaches. At the apex of the cavity, visible through the parted topmost leaves, a central growth-bud reads as a small tight bud-like structure. The cavity is a dark recess at the apex, framed by the parted topmost leaves, its interior pale-green contrasting with the deep green of the outer leaves. Each leaf is clearly distinct from its neighbors, with leaf-edges readable as ridges.

**Form (sealed state):** Same plant with the leaves folded inward via flex-nodes at the base of each leaf. The result is a tight near-spherical head, but the surface is NOT a smooth seamless dome — individual leaf-overlap remains visible as fine textural seam-lines tracing leaf boundaries in a roughly geodesic pattern. Deep green color uniform across the surface, cream-colored ribs visible as paler streaks along the seams. From the seam-lines, soft internal luminescence leaks faintly outward. Visible tension in the closed leaves: the sense that they could spring open in seconds.

**States:**
- *Wild (open):* smaller head, cavity visible but tighter, fewer outer leaves.
- *Wild (sealed):* small dense ball, compact.
- *Tended (open):* larger head with full leaf-layer count, cavity clearly large.
- *Tended (sealed):* full-sized sealed head, internal luminescence brighter at the seams.

**Hurt / death:** Burning makes the leaves crumple and char, the cavity collapsing inward. Under colonization, white mold-like mat creeps across the outer leaves and the affected leaves lose their green. On full death the head splits open along the seam lines, the leaves drooping outward in a brown-grey wilt, the cavity exposed and slack.

## Gasafoetida

**Silhouette priority:** Tall umbrella-stalk crowned with a flat-topped cluster of woody scaled pod-cones, with visible amber resin weeping at the lower stalk and faint heat-haze around the cones. The "stalk-with-pinecones-on-top" silhouette is the read.

**Form:** A chimeric plant fusing two forms. Lower body is an umbrella-style central stalk: tall thick green stem (1-1.5 meters) with finely divided fern-like compound leaves emerging from the lower portions, thickest at the base. From a wound or tap-point on the lower stalk, viscous amber-gold gum-resin weeps visibly, glistening and oily. Upper portion terminates in a flat-topped umbrella-shaped cluster bearing 4-7 woody fire-reactive pod-cones — ovoid pod-cones with overlapping woody scales like small pinecones, each cone roughly the size of a fist. Cones are sealed at the apex with glossy resin patches that catch the light, the resin clearly fresh and viscous. Around the cones, faint heat-haze rises into the air. Cone scales are pale tan-brown, resin patches gold-amber.

**States:**
- *Wild:* shorter stalk, fewer cones (2-3) in the cluster, resin at the wound-point thin and slow.
- *Tended:* full stalk height, full cluster (5-7 cones), resin flowing freely at the wound-point.
- *Harvested:* a visible gap in the cluster where a cone is missing.
- *Held pod:* a fist-sized woody pod, resin-sealed at one end, emitting a pale yellow-grey sulfurous gas haze around itself.
- *Spent pod:* dry, the resin seal broken and inert, the surface dull.
- *Combusted cluster:* the cluster has no cones, charred patches on the stalk apex where cones used to sit.

**Hurt / death:** On fire, the cones ignite and launch as flaming pods, leaving the cluster empty and the stalk apex charred. On full death the stalk slumps and the wound at the lower stalk dries up, the resin crystallizing and the haze ceasing.

## Climbvine

**Silhouette priority:** Long rope-like vine with visible nodes carrying small dark grip-root clusters, growing across an inclined surface. The "rope with grip-points" silhouette is the read.

**Form:** A long rope-like vine, several meters in length, growing across an inclined rock or substrate surface. Body composed of smooth cylindrical inter-node sections punctuated regularly by visible nodes where grip-root clusters emerge. Inter-node sections are smooth and rope-like with fibrous bark texture, mottled brown-grey-green. Grip-root clusters at each node: small dense bundles of dark hair-like rootlets splayed outward, gripping the substrate. At a cut end, a fibrous core is visible — bundles of long parallel fibers. Older sections are weathered and integrated with the surface; newer growth at the ends reads fresh and pale, with the grip-roots at the newest nodes still pale and fine before darkening with age.

**States:**
- *Naturally-growing:* old, weathered, integrated with the surface it grew on, the rootlets at each node dark and fully merged with the substrate.
- *Tended:* younger, fresh-looking, the rootlets still pale at the most recent nodes.
- *Harvested section:* a cut length of vine, the cut ends showing the fibrous core clearly, paler than the bark, bouncy and rope-like in motion.
- *Deployed:* an active vine hanging across surfaces, visibly fresher than naturally-growing Climbvine, distinctly placed.

**Hurt / death:** A dying Climbvine shows its rootlets pulling away from the substrate, the inter-node sections drying out and thinning. On full death the vine drops off the surface and lies on the ground as a fibrous brown rope.

## Mother Flure

**Silhouette priority:** A massive trumpet-bloom organism the size of a small building, set in a contained chamber, with smaller offshoots emerging through cracks in the walls. The "giant collapsed flower with children pushing through the walls" is the read.

**Form:** A massive Flure organism the size of a small building, set in a contained chamber with hard walls. Visible structure is not a single body but a clonal network: ONE central trumpet-bloom (collapsed and grey but still architecturally legible at building scale, the bloom's overall shape preserved even in death) PLUS multiple smaller offshoots emerging through cracks in the chamber walls. Offshoots are smaller Flure trumpets, identical to the central body, popping up through floor cracks, growing along the walls where masonry has failed, extending out of sight beyond the chamber. Central body is collapsed grey-brown with faint traces of rust-red still visible in the deepest crevices of the bloom. Smaller offshoots are alive, in active rust-red and amber. The chamber architecture is visibly compromised by root activity: cracks in walls, displaced floor tiles, root-fingers visible where they have grown around the structure.

**States:**
- *Dormant:* central body collapsed and grey, smaller offshoots alive but unlit, root-fingers visible through cracks, no atmospheric haze. The chamber reads dormant.
- *Bloomed:* the central petals unfurl and the internal structures light; smaller offshoots throughout the chamber illuminate. The chamber light shifts from diffuse to radiant. Reddish iron-broadcast haze rises from every offshoot simultaneously, filling the air with reddish dust.

## Network visualization (scene reference)

A corridor with several flora species visible at once: a Seefern lantern in the foreground casting teal light, a Scarpet carpet beneath the flora, a Flure on a slender stem catching the teal light along its bronze petals, a Capbage dense and sealed in a tight alcove, faint connecting threads running between the plants as pale luminescent traces underneath the substrate. One amber-glowing human-scale figure with pale skin and dark hair kneeling beside the Seefern in the foreground. Voxel-painterly style, restricted palette, near-black background, diorama-on-dark composition. Mood: a small ecosystem, the connecting network faintly visible.
