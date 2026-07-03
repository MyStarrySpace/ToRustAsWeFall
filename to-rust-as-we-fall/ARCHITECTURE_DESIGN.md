# Procedural Architecture — Design Spec & Image-Generation Prompts

**Purpose.** This document does two coupled jobs for the procedural architecture generator that will live in `blender/`:

1. **It catalogs the parameter space** — every knob the generator will expose (massing, height, roof/crown, facade rhythm, windows, doors, awnings, surface pattern, signage, decay, emissive), each with an *enumerated option set* so it maps 1:1 onto a Blender parameter. This is the "what does the generator need" thinking.
2. **It emits image-generation prompts** — a shared style preamble plus self-contained prompts, structured per district, per building archetype, and per decorative element — so the concept imagery it produces can feed back in as visual reference for *tuning* the generator (silhouettes, proportions, which options read as "belongs here").

**The loop this doc drives:** `this doc → generate reference imagery → eyeball against canon → build/tune the Blender generator → generated buildings → back to imagery for the next pass`.

Style precedent: this mirrors [`reference-docs/flora_image_prompts.md`](../reference-docs/flora_image_prompts.md) — shared preamble, consistent per-entry template, canon citations, self-contained prompts.

---

## 0. Canon status & how to read this doc

- **Grounded in:** GDD `reference-docs/to_rust_gdd_v02.md` (§4 world, §5 districts, §6 render rules, §11 bosses, §12 aesthetics); series bible §2.4 "World Design: Grown, Not Built"; `act1_timeline.md`; the director-owned registers `ENVIRONMENT_ELEMENTS.md` and `ECOLOGY_COMBOS.md`; and the material palettes baked into the shipped GLB texture sets (`resources/models/elevator/` junction+bridge, `resources/models/aster-sim/` emissive maps).
- **Two canon-gap flags carried throughout:**
  - ⚠️ **`world_aesthetic_reference.md` is missing from the doc set.** GDD §6/§4.4 name it as the authoritative per-district *architectural-form* spec. The per-district **forms** below are reconstructed from second-tier sources — strong guidance, **not locked canon.** Ratify against that doc if/when it surfaces.
  - 🔧 **The discrete part vocabulary (roof / awning / window / door types) is canon-silent by design.** GDD §4.6 says the treatment is "open"; the research confirms canon "does not enumerate roof/awning/window/door types." Everything tagged **🔧 PROPOSED** below is invented *within* the global constraints (§2) and awaits director ratification. It is not being presented as canon.
- **Act 3 districts are `PROPOSAL`** (not yet canon) and are excluded from the full entries; they appear in the summary table only, marked.

---

## 1. Common style preamble

Prepend (or append) this to **every** prompt in this document. It locks the render register so generated reference matches what the Blender tool can actually build (faceted low-poly + pixel-tile textures + real lighting), and locks the palette so nothing drifts into generic sci-fi.

> Low-poly faceted base geometry in the PlayStation-2-era register — simplified silhouettes, modest polygon count, surfaces gently tapered and chamfered rather than smoothly curved or voxel-blocky. Pixel-art textures at ~32px/m, grid-aligned, limited palette, sharp pixel edges, hand-tiled. Realistic lighting and soft shadow layered over the whole. **Post-solarpunk in decline** ("solarpunk-Wall·E"): the sweeping, biomimetic, grown-not-built bones of a sustainable civilization, now rusting — the forms are still there, the life isn't. Restricted palette: muted cool teals and greens dominant on architecture, warm cream and brown on natural materials, near-black background. Ferric-red iron-oxide streaks bleed down exposed metal like tear-stains; rust-colored particulate dust settles on horizontal surfaces; a faint sepia/amber haze filters the interior light. Two saturated lighting anchors only — warm orange firelight and cold cyan-white scanner light, with terminal-green (#5ce87f) emissive accents on screens and readouts. Diorama-on-dark composition, single structure at frame center. **Every element should read two ways at once: institutional infrastructure AND biological tissue** (a pipe is also a vessel, a cable-bundle also a nerve fascicle, a wall-panel also a basement membrane, a catwalk-grate also trabecula). Do NOT use saturated pink-red (reserved for boss landmarks). Do NOT make it boxy-gridded — the base grammar is curved, branched, fractal, anti-grid.

For **isolated element sheets** (§7), swap the last two sentences for: *"Orthographic-ish studio lighting, plain dark background, the element repeated as a labeled row of 3–5 variants, no surrounding building — a reference sheet for a kit-of-parts."*

---

## 2. The architectural language (global constraints)

Every generated building obeys these six. They are the difference between "belongs in this world" and "generic sci-fi that happens to be rusty." (Sources: series bible §2.4; GDD §4.1, §4.3, §6.)

1. **Grown, not built — anti-grid, curved, fractal.** "Every surface curves. Nothing is gridded." Corridors branch and reconnect like capillary beds; rooms repeat in shape but vary in size like alveolar clusters; wiring wraps and spirals like myelin, not neat conduit; larger spaces branch fractally into smaller ones like bronchial trees. Prefer swept / lofted / branched / spiraled masses over box extrusions. **Generator realizes curves via facets** — tapered boxes, octagonal lathes, chamfered tiers, offset stacks, `coil`/`stairs_arc`.
2. **Two-read biomimicry (the histology underneath).** The solarpunk decay sits over a histology layer: walls like basement membrane (smooth-but-layered, faintly translucent, structure visible beneath); conduit bundles like nerve fascicles; filtration membranes with visible pores; channels lined with cilia-like projections. The *same object* must read as institutional infra to one player and as pathology to another. Neither reading resolves. This is the highest-value differentiator — author it into every structural element.
3. **PS2 low-poly + pixel-texture + realistic lighting.** Faceted, modest poly, gently-curved (not smooth, not cubic). Grid-aligned limited-palette pixel textures. Real shadows/AO.
4. **Palette lock.** Muted cool teal/green architecture + warm cream/brown natural materials + near-black background. Ferric-red oxidation streaks on exposed metal. Two saturated light anchors (warm orange fire; cyan-white/green scanner-terminal). **Pink-red saturation forbidden except boss landmarks.**
5. **Decay is a first-class layer, not noise.** The solarpunk "bones" stay legible under the rust — you can always read what the place was *supposed* to be. Decay is authored (streak maps, char, weeping corrosion, collapse scars), not random grunge.
6. **The bureaucratic / surveillance overlay.** The built environment is saturated with institutional-processing infrastructure: scan-grid checkpoints and tag-reader arches; class-coded signage (institutional-project / government-aspirational / corporate-rebrand / picturesque-community registers); ironic aspirational names over failed function; hostile/anti-homeless architecture; "Flow Optimization" toll gates; opening-hours run backward (convenience always-open, culture rare-and-hyped).

---

## 3. Parameter taxonomy — the generator knobs

Each knob is a generator parameter with an **enumerated option set**. Options tagged 🔧 are proposed (canon-silent vocabulary). A **district preset** (§6) is just a weighting over these options. Everything here must reduce to `spatial_grammar` ops (`slab`/`wall`/`recess`/`on`/`on_wall`/`span`/`row`/`stairs`/`pbox`/`coil`) + tile-atlas materials, so nothing is un-buildable.

### 3.1 Massing / base shell form
`shell ∈ {`
- `curved_balcony_tower` — vertical, tiered, each tier a tapered slab with a wrapping balcony ring (offset `slab_xz` tiers + `on_wall` balcony rail rows)
- `spiral_organic_mass` — myelin-wrap: a `coil`-driven skin spiraling up a core
- `fractal_branch_cluster` — bronchial/alveolar: a trunk mass that spawns child masses at decreasing size (recursive box-cluster)
- `ring_corridor_segment` — a curved arc of repeated dwelling cells (Greenfields)
- `membrane_panel_wall` — a bilayer wall of translucent pore-panels (Bulwark/Filtration)
- `drawer_stack_monolith` — floor-to-ceiling record-drawer slab cut into sightline canyons (Open Files)
- `dome` — the sim dome; light leaking through a translucent skin
- `stacked_ring_monument` — bone-white tiered rings (Paranucleus, boss only)
- `cave_shell_plus_catwalk` — raw rock/sand shell with an inserted facility-metal structure (Junction)
`}`

Massing sub-knobs: `tier_count`, `tier_taper` (0–0.4 inset per tier), `footprint_curve` (0=octagonal, 1=strongly lobed), `branch_depth`, `branch_size_falloff`, `asymmetry` (breaks the grid read).

### 3.2 Height / storeys
`storeys` (int, 1–8+), `storey_height` (m), `ground_floor_tall` (bool — taller commercial/lobby base), `setback_schedule` (list of tiers that step back). Zone-2 buildings mid-rise; boss landmarks monumental; Zone-3 patchy/low with tissue showing through.

### 3.3 Roof / crown 🔧
Canon-silent — keep it curved/branched/organic, never gabled-suburban or flat-sci-fi. `crown ∈ {`
- `domed_cap` 🔧 — low faceted lathe dome
- `branched_canopy` 🔧 — the roof splits into 2–3 tapered organic fingers (continues the grown grammar upward)
- `balcony_terrace` 🔧 — flat planted terrace (solarpunk green, parameter: alive/desiccated/performative-dead)
- `renewable_crown` 🔧 — solar-array / wind-vane / bio-energy rig on top (parameter: functional/neglected/decorative-only)
- `pore_vent_cap` 🔧 — membrane-pore cluster venting haze (histology read)
- `service_bulkhead` 🔧 — utilitarian metal cap with readouts (utility districts)
`}` + `crown_overhang` (m), `crown_greenery` (0–1).

### 3.4 Facade rhythm
How openings/decor repeat across a wall (drives `row` spacing). `rhythm ∈ {`
- `even_bay` — regular bays (institutional)
- `alveolar_vary` — same shape, varying size (the canonical grown read)
- `stacked_drawer` — dense horizontal drawer bands (Open Files)
- `sparse_alcove` — long blank runs punctuated by recessed alcoves (Greenfields cover)
- `toll_chokepoint` — a wide wall pinched to a single metered gate (Hypelines/Cleanstreets)
`}` + `bay_width`, `bay_jitter` (breaks grid), `blank_run_ratio`.

### 3.5 Window types 🔧
Realized as `recess` openings + an inset pane box (emissive or dark). `window ∈ {`
- `pore_round` 🔧 — round/oval membrane-pore window, faintly translucent (histology)
- `capillary_slit` 🔧 — tall narrow vertical slit, often in branching rows like a vessel
- `balcony_bay` 🔧 — floor-height opening onto a balcony (solarpunk)
- `drawer_face` 🔧 — a record-drawer front that reads as a window band (Open Files)
- `shuttered_metal` 🔧 — rolling metal shutter, half-lowered (failed-commerce)
- `scan_grille` 🔧 — barred/grilled aperture at a checkpoint
`}` + `glazing` ∈ {dark, terminal-green-lit, warm-lit, boarded, broken}, `frame_material`, `sill_depth`.

### 3.6 Door / entry types 🔧
`recess` + door leaf + optional threshold apparatus. `door ∈ {`
- `iris_membrane` 🔧 — a pore that dilates; reads as both airlock and biological sphincter
- `cycling_slab` 🔧 — dwelling door on the Facility shift-schedule cycle (Greenfields, parameter: open/closed/mid-cycle)
- `scan_arch` — a tag-reader checkpoint arch you pass *through* (the scan-bar brightens on cadence)
- `toll_gate` — single-file metered "Flow Optimization" gate
- `enforcement_vestibule` 🔧 — a double-door airlock with a scan cone between (Beacon Hill)
- `service_hatch` 🔧 — small utilitarian maintenance hatch/grate
- `blast_bulkhead` 🔧 — heavy sealed door (fortified crossing)
`}` + `threshold_apparatus` ∈ {none, scan-bar, toll-meter, spike-strip, plaque}, `leaf_state`.

### 3.7 Awnings / canopies / projections 🔧
`on_wall` decor protruding over the entry/street. `projection ∈ {`
- `membrane_awning` 🔧 — a taut translucent canopy, faintly veined (histology)
- `slat_canopy` 🔧 — faceted metal slat awning, rust-streaked
- `cantilever_balcony` 🔧 — projecting balcony slab with a rail row (`row` of posts)
- `signage_bracket` 🔧 — an arm carrying a hanging sign (see §3.9)
- `hostile_ledge` 🔧 — a slanted no-stand ledge (anti-homeless; enforcement, not shelter)
- `conveyor_spur` 🔧 — a powered belt spur feeding into the building (Hypelines)
`}` + `projection_depth`, `projection_condition` ∈ {intact, sagging, collapsed, retracted}.

### 3.8 Surface material & pattern
Drawn from the shipped tile-atlas stems (`blender/textures/gen_tiles.py`): `material ∈ { rock, sand, facility_metal, grate, rust_iron, biolum_teal, deck_metal, wall_panel }` + proposed additions 🔧 `{ membrane_panel, char_crust, paving_civic, amyloid_bone }`. Each surface picks a material + a variation (`crc32(name)%4`). `pattern_overlay ∈ {`
- `panel_seam` — riveted metal panel seams (facility_metal)
- `diamond_plate` — deck-metal tread
- `crosshatch_bars` — grating
- `basement_membrane` 🔧 — smooth-layered translucent striation (the key histology texture)
- `nerve_fascicle` 🔧 — bundled-cable / myelin-wrap striping on conduit runs
- `tissue_substrate` — pinkish biological floor with vessel grooves (shows through in Zone 3)
`}`

### 3.9 Signage / propaganda / wayfinding
`sign_register ∈ { institutional_project, government_aspirational, corporate_rebrand, picturesque_community }` × `sign_condition ∈ { pristine, ironic_over_failure, hyped_rare_opening, always_open_convenience }`. Realized as `on_wall` panels with emissive text. Class-coded: formal names on official signage, vernacular in speech. `sign_form ∈ {wall_plaque, hanging_bracket_sign, backlit_arch_banner, projected_floor_text, monument_plaque}`.

### 3.10 Rust / decay overlay stack
Independent per-surface overlays (authored maps, not noise). `decay ∈ {`
- `none` — tended/optimized surfaces (Greenfields; the enforcement apparatus in Cleanstreets)
- `ferric_bleed` — iron-oxide streaks running down from seams/openings ("tear stains")
- `oxide_dust` — rust particulate settled on horizontals ("rust pollen")
- `sepia_haze` — amber interior-light filter
- `char_burn` — fire-fuel char crusting (Ancourage)
- `weeping_corrosion` — membrane pores corroding/weeping (Bulwark/Filtration)
- `collapse_scar` — sinkhole/give-way scarring (Honeycomb faked slabs, Sunset Acres)
- `candid_mat` — white fungal colonization mat creeping up (enemy ecology)
`}` + `decay_amount` (0–1), `bones_legibility` (≥0.4 — the solarpunk form must stay readable).

### 3.11 Emissive / terminal accents (the signature)
`emissive_use ∈ {terminal_green (#5ce87f), scanner_cyan_white, firelight_orange, watchtower_blue (Loca only), flora_teal 🔧 (tended flora cores), none}` on: terminals, scan-bars, flow-strip telegraphs (brighten one beat before a hazard), portal pads, override consoles, valve readouts, flora cores. `emissive_strength`, `telegraph_pulse` (bool). **Pink-red core allowed only on boss landmarks.**

### 3.12 Street-level furniture
`furniture[] ⊂ { drink_machine, recharge_pod, toll_meter, herd_space_booth, memorial_monument, anti_homeless_spikes, rotary_valve_wheel, relief_console (+ dummy/Goodhart variant), conveyor_belt, record_drawer_terminal, workbench }`. Parameter per item: functional / neglected / dummy.

---

## 4. Building archetype prompts

Full self-contained image prompts (prepend §1 preamble). Each produces a "hero" reference for one buildable type. Template per entry: **Read** (silhouette priority), **Massing/knobs**, **Two-read**, **Prompt**.

### 4.1 Data-terminal tower — The Open Files Initiative
**Read:** floor-to-ceiling drawer-stack canyon crowned with a catwalk; terminal-green readouts pulsing in the dark.
**Massing/knobs:** `shell=drawer_stack_monolith`, `rhythm=stacked_drawer`, `crown=service_bulkhead`, `window=drawer_face`, `emissive=terminal_green`, `decay=oxide_dust + sepia_haze`.
**Two-read:** the drawer stacks read as bureaucratic record-archive AND as densely-packed cortical layers where thinking once happened (a dead cognitive zone).
**Prompt:** *A tall low-poly institutional structure built of floor-to-ceiling metal record-drawer stacks, cutting the interior into a narrow sightline canyon. Faceted, PS2-era geometry, gently chamfered — not smoothly curved, not cubic. An elevated metal-grate patrol catwalk runs along the top of the stacks. Chains of drawer-terminals glow terminal-green (#5ce87f) in the gloom, a cyan-white scan-arch pulsing at the aisle mouth. Rust-colored oxide dust settles on the drawer tops; faint sepia haze. Pixel-art tiled textures, muted teal-green metal with ferric-red bleed at the seams, near-black background. The stacks read simultaneously as a government data-archive and as the dense layered tissue of a cortex where cognition has gone dark.*

### 4.2 Residential dwelling block — Greenfields Collective
**Read:** a lit, populated, gently-curved ring corridor of identical optimized dwellings, doors mid-cycle; the only cover is the door alcoves.
**Massing/knobs:** `shell=ring_corridor_segment`, `rhythm=sparse_alcove`, `door=cycling_slab`, `crown=balcony_terrace (performative-dead)`, `furniture=[drink_machine, cooperative_flora_bed]`, `decay=none (tended/optimized)`.
**Two-read:** the identical repeating dwellings read as planned socialist optimization AND as alveolar clusters (same shape, varying size).
**Prompt:** *A gently-curving lit ring corridor lined with identical optimized residential dwellings, their doors caught mid-cycle on a shift schedule — some open, some sealing. Low-poly faceted PS2-era geometry, alveolar repetition (same door shape, subtly varying bay size), recessed door-alcoves the only shadowed cover. A drink machine glows warm against one wall; a small tended cooperative flora-bed with faint teal bioluminescence. Clean muted-teal wall panels, warm cream trim, no rust — this district is tended, not failing; its emptiness is a schedule, not poverty. Pixel-art tiled textures, near-black background beyond the lit ring.*

### 4.3 Checkpoint / tag-reader gate — Tag Day / Beacon Hill / Open Files
**Read:** a scan-arch you pass *through*, a cyan-white scan-bar sweeping the threshold, a scan cone drawn on the floor.
**Massing/knobs:** `door=scan_arch (+ enforcement_vestibule for Beacon)`, `threshold_apparatus=scan-bar`, `emissive=scanner_cyan_white`, `telegraph_pulse=true`, `sign_register=government_aspirational`.
**Two-read:** the arch reads as an institutional checkpoint AND as a vascular constriction / immune-checkpoint deciding who passes.
**Prompt:** *A low-poly institutional checkpoint arch spanning a corridor, a cold cyan-white scan-bar sweeping down through the opening on a cadence, a scan cone projected onto the floor tiles. Faceted PS2-era geometry, faintly curved. Barred scan-grille apertures flank the arch; a government-aspirational name-plaque glows above it, pristine even as the metal around it streaks with ferric-red rust. Terminal-green readouts at the operator console. Muted teal metal, near-black background. The arch reads at once as a bureaucratic tag-reader that decides who counts and as a biological checkpoint gating passage through a vessel.*

### 4.4 Pump-shaft junction — Plumbing Power Project / Channels
**Read:** a vertical ascending spiral of pump-run junctions and channel troughs, rust-red iron backwash, flow-strips that brighten before a surge.
**Massing/knobs:** `shell=spiral_organic_mass`, `material=facility_metal + grate + rust_iron`, `projection=conveyor_spur→trough`, `furniture=[rotary_valve_wheel]`, `emissive=terminal_green telegraph`, `decay=ferric_bleed heavy`.
**Two-read:** pipes/valves read as municipal water infrastructure AND as the perivascular plumbing of the NVU.
**Prompt:** *A vertical spiraling maintenance junction of industrial pump-runs and open channel-troughs, rust-red iron backwash staining the metal, inclined pump-shaft walls climbing out of frame. Low-poly faceted PS2-era geometry, the spiral realized as chamfered stepped segments. Rotary maintenance valve-wheels sit mid-fault (one run open amid constricted ones); emissive terminal-green flow-strips run along the troughs, brightening one beat before a surge. Heavy ferric-red bleed-streaks down every seam; metal grating over dark water below. Muted teal-and-rust palette, near-black void. The plumbing reads as both captured municipal water infrastructure and the perivascular channels of living tissue.*

### 4.5 Membrane crossing — Bulwark Wharf / Filtration
**Read:** a bilayer wall of translucent pore-panels, pores in three states (intact opaque / corroded weeping / breached open), under gray-purple haze.
**Massing/knobs:** `shell=membrane_panel_wall`, `window=pore_round`, `door=blast_bulkhead`, `furniture=[relief_console (pore-clamp)]`, `decay=weeping_corrosion`, sky exception: gray/purple haze.
**Two-read:** the wall reads as a fortified barrier-maintenance gate AND as the blood-brain barrier's basement membrane, ferroptotically weeping.
**Prompt:** *A bilayer membrane wall built of faceted translucent pore-panels, the pores in three visible states across its span — some intact and opaque, some corroded and weeping a rust-tinted fluid, one breached fully open. Low-poly PS2-era geometry, panels smooth-but-layered like basement membrane with structure faintly visible beneath. A heavy sealed blast-bulkhead at center; an ENT barrier-maintenance console with a pore-clamp readout glowing terminal-green. Gray-purple haze in the air (a boundary exception to the ferric-red sky). Muted teal-green with weeping ferric corrosion, near-black background. The wall reads as both a fortified institutional crossing and the failing membrane between vessel and brain tissue.*

*(Loca's watchtower, the Paranucleus rings, and the sim dome are one-off boss/landmark set pieces, not procedural-generator targets — expand on request. Presets for them are in §6.)*

---

### Whole-building heroes (§4.6–§4.16)

The archetypes above isolate one system each (a canyon, a corridor, a gate, a wall). The entries below frame **one complete freestanding building**, so every §3 knob is visible in a single image — massing, storeys, crown, facade rhythm, windows, entry, projections, signage, decay stack, and emissive accents together. These are the acceptance targets for a *whole* generated building: a procedural output should be able to stand beside its hero and read as a sibling.

**Composition line (appended inside each prompt):** *"Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond."* Sanctioned deviations: §4.11 straddles the two faces of its block; §4.14 says "roofline" for its squat mass; §4.16 frames a ruin.

### 4.6 Street-corner convenience outlet — generic Zone 2 (the everyday building)
**Read:** a small rounded-corner commercial block whose ALWAYS OPEN sign still glows while the street decays around it — the opening-hours-run-backward motif (GDD §4.11) as a single building. This is the ordinary background building the generator will mass-produce.
**Massing/knobs:** `shell=fractal_branch_cluster` (small trunk + one budded annex), `storeys=2`, `ground_floor_tall=true`, `rhythm=alveolar_vary`, `window=shuttered_metal (ground) + capillary_slit (upper)`, `projection=slat_canopy (sagging)`, `sign=corporate_rebrand × always_open_convenience`, `decay=ferric_bleed + oxide_dust (medium)`, `emissive=terminal_green sign`.
*(Placement scope: the ALWAYS-OPEN-vs-decay motif and its `corporate_rebrand` register are a **capitalist-idiom** read — weight this variant to The Hypelines and The Cleanstreets Initiative per GDD §4.11, and do NOT place it in the socialist-idiom districts (Greenfields Collective, The Honeycomb Cooperative), whose idiom has no always-open commerce. The bare convenience-block massing may still recur Zone-2-wide with other signage.)*
**Two-read:** a convenience outlet AND a reflex arc — the one pathway that still fires after everything deliberative has gone dark.
**Prompt:** *A small two-storey street-corner convenience outlet, a complete freestanding building with a rounded chamfered corner and one smaller annex mass budding off the main trunk like a branch — faceted PS2-era low-poly, nothing gridded. The tall ground floor's window is half-covered by a rusted rolling metal shutter; narrow capillary-slit windows sit above in a branching pair. A sagging faceted metal slat-awning shades the entry. An ALWAYS OPEN sign glows pristine terminal-green (#5ce87f) while ferric-red streaks bleed down the muted-teal wall panels around it and rust dust settles on every ledge. Warm cream trim, pixel-art tiled textures at 32px/m. The one building on the street whose lights never go out — commerce as the last reflex that still fires. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.7 Dwelling block — Greenfields Collective (whole building)
**Read:** a freestanding lobed arc of the district's ring corridor — stacked **identical** dwellings (the canonical statistically-perfect sameness), with alveolar variation carried by the lobed tiers and bay spacing, never by the units. Lit, tended, **no rust**: this district's emptiness is a schedule, not decay.
**Massing/knobs:** `shell=ring_corridor_segment (freestanding lobed arc)` ⚠️ *(hero-framing reconstruction — the district's one attested form is the ring corridor; ratify against `world_aesthetic_reference.md`)*, `storeys=3`, `tier_taper=0.2`, `footprint_curve=high`, `rhythm=sparse_alcove (street) / even_bay (identical units above)`, `window=balcony_bay + pore_round (identical per dwelling), glazing=warm-lit`, `door=cycling_slab`, `crown=balcony_terrace (alive/tended)`, `projection=cantilever_balcony`, `sign=picturesque_community, pristine`, `decay=none`, `emissive=flora_teal 🔧`.
**Two-read:** cooperative housing AND an alveolar cluster — the lobed tiers breathing at different sizes while every cell within them is exactly the same.
**Prompt:** *A complete freestanding dwelling block of the Greenfields Collective: a gently-lobed arc — a freestanding segment of the district's ring corridor — three faceted tiers stepped back from one another, wrapped by cantilevered balconies with low post-rails. The dwellings are IDENTICAL: statistically-perfect units, one rounded window shape repeated exactly along each tier; alveolar variation lives only in the lobed tier sizes and bay spacing, never in the units — optimization, not poverty, and nothing gridded. Street level is a run of recessed door-alcoves, the identical dwelling doors caught mid-cycle on the shift schedule — some open, some sealing. The crown is a planted terrace, genuinely tended, its cooperative flora beds glowing faint teal. Warm light in a scattering of windows. A pristine community plaque reads "Greenfields Collective." Clean muted-teal wall panels and warm cream trim with NO rust — this district is optimized and tended. Low-poly faceted PS2-era geometry, pixel-art tiles, realistic soft lighting. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.8 Records hall — The Open Files Initiative (whole building)
**Read:** a monolithic archive slab banded floor-to-ceiling with drawer faces, a scan-arch mouth at its base — a cortical column gone dark, a few cells still firing green.
**Massing/knobs:** `shell=drawer_stack_monolith (canyon-cut fins)`, `storeys≈6`, `asymmetry=high`, `bay_jitter=on`, `rhythm=stacked_drawer`, `window=drawer_face + scan_grille`, `door=scan_arch`, `crown=service_bulkhead` (grate catwalk ring in prose), `sign=government_aspirational backlit arch banner`, `decay=oxide_dust + sepia_haze`, `emissive=terminal_green drawer readouts + scanner cyan-white at entry`.
**Two-read:** a bureaucratic records archive AND a cortical column where thinking has gone dark.
**Prompt:** *A complete freestanding records hall of The Open Files Initiative: a massive archive slab cut by deep sightline-canyon recesses into a cluster of gently tapered, chamfered drawer-stack fins of unequal height — monumental but never perfectly gridded. Each fin is banded floor-to-ceiling with metal record-drawer faces, the bands subtly varying in depth and spacing, a sparse scattering of them glowing terminal-green (#5ce87f) like the last live cells in a dead cortex. A metal-grate catwalk rings the crown beneath a utilitarian service-bulkhead cap. At the base, the single entry is a tag-reader scan-arch, its cold cyan-white scan-bar caught mid-sweep, a scan cone projected on the paving. Above the arch a government-aspirational backlit banner reads "The Open Files Initiative," pristine over the rust-colored oxide dust settling on every drawer band; faint sepia haze in the air. Faceted PS2-era low-poly, pixel-art tiles, muted teal metal with ferric-red bleed at the seams. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.9 Pump-house — Plumbing Power Project (whole building)
**Read:** a faceted drum wound externally by its own climbing channel-trough, an inclined pump-shaft wing leaning against it — the district's ascending spiral compressed into one building.
**Massing/knobs:** `shell=spiral_organic_mass`, `storeys=3 (drum) + shaft wing`, `material=facility_metal + grate + rust_iron`, `window=capillary_slit`, `door=service_hatch`, `furniture=[rotary_valve_wheel ×3]`, `projection=conveyor_spur→trough`, `sign=institutional_project`, `decay=ferric_bleed (heavy)`, `emissive=terminal_green flow-strip, telegraph_pulse=true`.
**Two-read:** a municipal pump station AND a living vessel-organ wrapped in its own circulation.
**Prompt:** *A complete freestanding pump-house of the Plumbing Power Project: a faceted octagonal drum three storeys tall, wound externally by a spiraling open channel-trough that climbs its flank in chamfered stepped segments, with an inclined pump-shaft wing leaning into its side. Rotary maintenance valve-wheels stud the lower wall — one run open amid constricted ones. A terminal-green (#5ce87f) flow-strip runs along the trough and down to the service door, brightening one beat before a surge passes. Rust-red iron backwash and heavy ferric bleed streak every seam; metal grating decks the trough crossings; moisture seeps darken the base. Tall narrow capillary-slit windows in branching pairs. An institutional plaque reads "Plumbing Power Project." Low-poly PS2-era facets, pixel-art tiles, muted teal and rust palette. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.10 Distribution exchange — The Hypelines (whole building)
**Read:** a hub mass with elevated conveyor-conduits branching off it like vessels leaving a heart; the only pedestrian way in is a single-file toll gate — and the worn detour path beaten around it.
**Massing/knobs:** `shell=fractal_branch_cluster (hub + 3 conduit branches)`, `rhythm=toll_chokepoint`, `door=toll_gate`, `projection=conveyor_spur ×3`, `furniture=[rotary_valve_wheel (diverter variant), toll_meter]`, `sign=corporate_rebrand over pre-rebrand ghost lettering` 🔧 *(the "Iron Heart" ghost sign is a proposed visual translation of the canon rebrand-memory, which lives in resident speech)*, `decay=ferric_bleed + oxide_dust (heaviest at the conveyor joints)`, `emissive=terminal_green meters`.
**Two-read:** a logistics hub AND a vascular exchange where iron is the currency.
**Prompt:** *A complete freestanding distribution exchange of The Hypelines: a central faceted hub mass from which three elevated powered conveyor-belt conduits branch out and away at different heights — fractally, like vessels leaving a heart. Riding-height belts carry glinting iron stock into the hub. The only pedestrian entry is pinched to a single-file "Flow Optimization" toll gate with queue rails, its meter readout glowing terminal-green (#5ce87f) — and a worn unofficial detour path is beaten into the ground around the building's flank. A glossy corporate hanging bracket-sign reads "The Hypelines"; beneath it, older painted cooperative lettering — "IRON HEART" — ghosts faintly through the rebrand. A rotary diverter valve sits at a visible conduit branch node. Muted teal metal oxidizing ferric-red at every joint, PS2-era facets, pixel-art tiles. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.11 Worker-housing block — The Honeycomb Cooperative (whole building)
**Read:** two faces of one building — a freshly-finished street face that passes inspection, and a stripped flank where the function has rotted. Goodhart-as-masonry, framed to show both at once.
**Massing/knobs:** `shell=curved_balcony_tower (cell-repetition)`, `storeys=5`, `rhythm=alveolar_vary`, `window=pore_round; glazing=broken (flank)`, `furniture=[relief_console (dummy variant)]`, `decay=collapse_scar (flank only)`, `sign=picturesque_community × ironic_over_failure` *(the aspirational community name over Goodhart rot — signage that works hard to convince these workers of their dignity, per GDD §4.11)*, `emissive=firelight_orange (rust-lit ferric arc sparks) on a cadence`.
**Two-read:** cooperative worker housing AND tissue that scores healthy on every metric while dying behind the membrane.
**Prompt:** *A complete freestanding worker-housing block of The Honeycomb Cooperative, framed at an angle that shows two faces at once. The STREET face is freshly finished: clean repeated dwelling cells in the same shape at varying sizes, tidy panel seams, warm cream trim, a relief-valve console gleaming beside the entry beneath an aspirational community plaque. The FLANK is the truth: a grate-floored catwalk still in place along it, the signal conduits beneath the grating stripped of their insulation so bare wires arc up through it on a slow cadence — each spark rust-lit ferric-orange as it climbs the gap — and a floor-span bay collapsed inward where a faked hollow slab gave way. Half the wall consoles are dummies, finished to pass inspection and wired to nothing. Five faceted storeys, PS2-era low-poly, pixel-art tiles; muted teal panels pristine on the display face, ferric-red bleed only on the hidden flank. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter view straddling the good face and the rotten one, near-black void beyond.*

### 4.12 Transit pavilion — The Cleanstreets Initiative (whole building)
**Read:** a low civic tram shelter on a radial plaza whose every surface refuses rest. Nothing here is broken — it is *maintained against people*.
**Massing/knobs:** `shell=ring_corridor_segment (open pavilion)`, `storeys=1`, `crown=branched_canopy (low sweep)`, `door=toll_gate (platform entry)`, `projection=hostile_ledge throughout`, `furniture=[anti_homeless_spikes, memorial_monument, toll_meter]`, `sign=government_aspirational, pristine (the cheerful civic name over the grim function)`, `decay=oxide_dust (ambient edges only — the enforcement surfaces are kept immaculate)`, `emissive=cyan scan at gate`.
**Two-read:** a public transit amenity AND a vessel lined against anything that might lodge in it.
**Prompt:** *A complete freestanding tram pavilion of The Cleanstreets Initiative, set on a radial plaza: a low civic shelter with a sweeping faceted canopy whose every surface refuses rest — slanted no-stand ledges where benches should be, retractable spike strips extended hard across the rest pads — dropping flush only for the few-second retraction window of the scheduled sanitation sweep — and awkward partition fins dividing the waiting area into standing-only slots. Radial paving lanes funnel all foot traffic past a cheerful central memorial plaque standing on long-"consolidated" ground. The platform entry is a single-file credit toll gate; the platform edge is slanted so nothing can sit or sleep on it. Government-aspirational signage — a cheerful civic name over the grim function — kept immaculate: the enforcement surfaces are maintained against people, while ordinary oxide dust settles at the pavilion's unwatched edges and a worn unofficial path skirts the toll gate. Muted teal and warm cream, PS2-era facets, pixel-art tiles. Frame the complete freestanding building — full silhouette from ground line to canopy, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.13 Reading-room hall — Beacon Hill (whole building)
**Read:** a dignified, immaculately-kept archive hall whose doors are sealed — preservation as capture. The decay register here is gloom and closure, not corrosion.
**Massing/knobs:** `shell=curved_balcony_tower (older, ornamented solarpunk curves)`, `storeys=3, tall`, `window=capillary_slit (dark, stacks faintly visible within)`, `door=enforcement_vestibule`, `sign=picturesque_community × hyped_rare_opening 🔧` *(motif siting per ENVIRONMENT_ELEMENTS Beacon Hill — the GDD §4.11 idiom-to-district placement is canonically PENDING)*, `decay=decay_amount≈0 + sepia_haze (gloom register, no rust)`, `emissive=cyan-white scan cone in the vestibule + terminal-green hours board`.
**Two-read:** a preservation institution AND consolidated memory-tissue — the compacting stacks as dense engram laminae sealed behind a sclerosed opening, stored so tightly they can no longer be recalled.
**Prompt:** *A complete freestanding reading-room hall of Beacon Hill: a dignified archive building in the historic-preservation register — older solarpunk curves kept immaculate, the whole hall gloomy under the ferric-red haze. The tall entry doors are sealed; beside them an opening-hours board glows terminal-green (#5ce87f), hyping a single rare event — "READING ROOM OPENS — ONE DAY ONLY." The only way in is an enforcement vestibule: a double-door airlock porch with a cold cyan-white scan cone visible between its doors. Through tall dark capillary-slit windows set in a branching row, rolling compacting archive stacks are faintly visible inside — packed like dense tissue laminae, slid shut, a single open aisle of light between them. No rust — the decay here is gloom and closure, preservation-as-capture. Muted deep teals, warm cream trim, PS2-era facets, pixel-art tiles. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.14 Valve control-house — Ancourage (whole building)
**Read:** a squat utility building at a burned junction — char below, cheerful plaque above, a heat-fault still flaring on a cadence. Water-before-fire: the drainage valve drips beside the scorch.
**Massing/knobs:** `shell=fractal_branch_cluster (single squat trunk, no branches)`, `storeys=1–2`, `material=facility_metal + char_crust` 🔧, `window=scan_grille`, `door=service_hatch`, `furniture=[rotary_valve_wheel (wall-drainage), relief_console (control-terminal variant)]`, `sign=corporate_rebrand (cheerful register), incongruously pristine`, `decay=char_burn + ferric_bleed`, `emissive=firelight_orange flare vent + terminal_green terminals, telegraph_pulse=true`.
**Two-read:** a maintenance control-house AND scarred tissue where an unmanaged inflammatory burn keeps flaring.
**Prompt:** *A complete freestanding valve control-house of Ancourage, standing at a burned junction: a squat faceted utility building whose lower walls are crusted black with fire-fuel char, fused conduit bundles entering it half-melted and re-hardened. Wall drainage valves tie its plumbing back into the Plumbing Power Project mains; one drips steadily beside the scorch — water before fire. A heat-fault vent on the roofline breathes a slow warm-orange flare on a cadence, the single saturated firelight anchor in frame, brightening one beat before each flare. Control terminals glow terminal-green (#5ce87f) through a grilled window. Above the scorched entry, an incongruously pristine corporate-cheerful plaque reads "Ancourage." Muted teal metal beneath the burn, ferric-red streaks where oxidation meets soot, PS2-era facets, pixel-art tiles. Frame the complete freestanding building — full silhouette from ground line to roofline, three-quarter street-level view at a slight low angle, near-black void beyond.*

### 4.15 Barrier-maintenance gatehouse — Bulwark Wharf (whole building)
**Read:** a squat fortified ENT control-house built hard against the membrane wall — the crossing's *building*, in the district where the wall itself is the landmark. Completes district coverage: §4.5 frames the wall (linear infrastructure); this frames the freestanding structure beside it.
**Massing/knobs:** `shell=membrane_panel_wall + squat gatehouse mass`, `storeys=2`, `window=pore_round (three corrosion states)`, `door=blast_bulkhead`, `material=facility_metal + membrane_panel` 🔧, `furniture=[relief_console (pore-clamp variant)]`, `sign=fortified-crossing designator`, `decay=weeping_corrosion`, `emissive=terminal_green clamp readouts`; sky exception: gray-purple boundary haze (as §4.5).
**Two-read:** a fortified crossing checkpoint AND the failing membrane between vessel and tissue, tended by hand.
**Prompt:** *A complete freestanding barrier-maintenance gatehouse of Bulwark Wharf, built hard against a bilayer membrane wall: a squat two-storey fortified control-house whose own walls are framed facility-metal around inset membrane panes — smooth-but-layered like basement membrane, structure faintly visible beneath the surface. Round pore-windows show three states across its faces: intact and opaque, corroded and weeping a rust-tinted fluid, and one clamped shut with a maintenance ring. The entry is a heavy sealed blast-bulkhead; beside it an ENT barrier-maintenance console glows terminal-green (#5ce87f) with a pore-clamp readout. Weeping corrosion streaks below every failing pore; gray-purple haze hangs in the air — the boundary's exception to the ferric-red sky. Muted teal metal and translucent membrane, PS2-era facets, pixel-art tiles. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond. Reads as a fortified institutional crossing and as the failing membrane between vessel and brain tissue, kept alive by hand.*

### 4.16 Zone-3 eroded ruin — the everyday building, decayed (generic)
**Read:** the §4.6 convenience outlet at the far end of the zone axis — architecture eroding, tissue substrate showing through, the solarpunk bones still legible. This is the acceptance target for the generator's `tissue_through` / `bones_legibility` ramp (§6 zone rule); without it the eroded outputs have nothing to stand beside.
**Massing/knobs:** same shell as §4.6, `tissue_through=high`, `bones_legibility≈0.5`, `decay=collapse_scar + ferric_bleed + candid_mat (flank)`, `glazing=broken/boarded`, `emissive=none (the sign is dead)`, `pattern_overlay=tissue_substrate (exposed floor)`.
**Two-read:** a dead storefront AND tissue where the last reflex finally stopped firing.
**Prompt:** *The same two-storey street-corner convenience outlet, reached in Zone 3: half the shell eroded away, the faceted teal panels collapsed along one flank to expose pinkish biological tissue-substrate flooring, vessel-like grooves running through it where the architectural floor has worn through entirely. The rounded chamfered corner and the branching capillary-slit windows survive — the solarpunk bones still legible; you can read what this place was supposed to be — but the rolling shutter hangs broken, the slat-awning has collapsed, and the ALWAYS OPEN sign is dark, its glass dead. A white fungal candid-mat creeps up the shaded flank. Ferric-red bleed and rust dust over everything; the ground plane is more tissue than paving. PS2-era facets, pixel-art tiles, muted teal over pinkish substrate. Frame the complete freestanding ruin — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond. Reads as a dead storefront and as tissue where the last reflex finally stopped firing.*

---

### Named set-pieces (§4.17–)

Specific named locations from the lore, not generic district archetypes (cf. Mother Flure in the flora doc). Canon fixes the **story and meaning**; the **physical form** is 🔧 extrapolation where the GDD doesn't specify it.

### 4.17 PLA-8o's Pharmacy — the poisoned dispensary
**Canon (GDD §4.11):** "PLA-8o is a pharmacy where demoralized or automated work began killing people and a crowd raised signs to shut it down... the failure of its services is not one bad firm but the whole system indicted at once, which is what turns decay into storming." The name reads as **"Plato"** — the in-world figure of Derrida's *pharmakon*, the single substance that is **remedy and poison at once**: "a pharmacy whose collapse poisons the people it was built to heal" (GDD bibliography). Register = the **demoralized-collapse socialist idiom** (The Honeycomb Cooperative's register); specific district placement is **pending** per §4.11. Everything below the story is **🔧 extrapolation** — canon fixes no physical form.
**Read:** a Collective civic dispensary caught at the moment of its storming — a row of dispensing hatches, a jammed automated compounding line overflowing behind faked-finish panels, abandoned SHUT-IT-DOWN placards at the forced doors. The healing-green dispensary glow curdles sick and dim in the contaminated batch.
**Massing/knobs:** `shell=fractal_branch_cluster (squat civic dispensary hall)`, `storeys=1–2`, `rhythm=even_bay (row of dispensing hatches)`, `window=shuttered_metal (hatches half-rolled) + scan_grille`, `door=cycling_slab (forced open)`, `crown=service_bulkhead`, `furniture=[degraded compounding line, overflow vats, dispensary shelving, abandoned protest placards]`, `sign=picturesque_community × ironic_over_failure`, `decay=collapse_scar + weeping_corrosion (overflow) + ferric contamination`, `emissive=terminal_green dispensary glow going sick/dim + dead cyan-white scan counter`.
**Two-read:** a Collective pharmacy built to heal **AND** an iatrogenic lesion — the body's own remedy turned toxic, remedy and poison on the same shelf.
**Prompt:** *A complete freestanding Collective pharmacy — PLA-8o — caught at the moment of its storming: a squat civic dispensary hall, its street face a row of dispensing hatches half-rolled shut behind their shutters. The doors are forced open; abandoned hand-lettered placards lean against the frame, one reading "SHUT IT DOWN." Behind faked-finish wall panels a degraded automated compounding line has jammed and overflowed, a rust-tinted fluid weeping down the base. On the dispensary shelves, rows of vials: the healthy stock glows a clean terminal-green (#5ce87f), but the contaminated batch beside it has curdled — the same green gone sick and dim, ferric-red contamination bleeding through the fluid, remedy and poison on one shelf. An aspirational Collective community plaque still hangs above, protest signs raised over it. Low-poly faceted PS2-era geometry, pixel-art tiles, muted teal panels streaking ferric-red. Reads at once as a civic pharmacy built to heal and as an iatrogenic wound in the tissue — the cure that became the poison. Frame the complete freestanding building — full silhouette from ground line to crown, three-quarter street-level view at a slight low angle, near-black void beyond.*

---

## 5. Element sheets — the kit-of-parts references

**These are the highest-value prompts for building a *parameterized* generator**, because each sheet becomes a direct visual menu for one knob's option set. Use the element-sheet variant of the preamble (§1). Each prompt asks for a **labeled row of 3–5 faceted low-poly variants on a plain dark background** — a reference sheet, not a scene.

### 5.1 Window-types sheet (§3.5)
*A reference sheet: a row of 5 low-poly faceted window variants on a plain near-black background, orthographic studio lighting, each labeled — (1) a round translucent membrane-pore window; (2) a tall narrow capillary-slit window in a branching pair; (3) a floor-height balcony-bay opening; (4) a metal record-drawer face reading as a window band, glowing terminal-green; (5) a half-lowered rusted rolling metal shutter. Pixel-art tiled textures at 32px/m, muted teal metal with ferric-red streaks, sharp pixel edges. A kit-of-parts sheet for a procedural building generator.*

### 5.2 Door / entry-types sheet (§3.6)
*A reference sheet: a row of 5 faceted low-poly door/entry variants on plain near-black, each labeled — (1) an iris-membrane pore that dilates open (airlock-and-sphincter); (2) a cycling dwelling-slab door caught mid-cycle; (3) a tag-reader scan-arch with a cyan-white scan-bar; (4) a single-file "Flow Optimization" toll-meter gate; (5) a heavy sealed blast-bulkhead. PS2-era pixel-tiled geometry, muted teal with terminal-green readouts, ferric-red rust. Kit-of-parts reference for a procedural generator.*

### 5.3 Roof / crown-types sheet (§3.3) 🔧
*A reference sheet: a row of 5 faceted low-poly building-crown variants on plain near-black, each labeled — (1) a low faceted domed cap; (2) a branched organic canopy splitting into 2–3 tapered fingers; (3) a flat planted balcony-terrace, its greenery desiccated/performative; (4) a renewable-energy crown (neglected solar array + wind-vane); (5) a membrane-pore vent-cap venting faint haze. Muted teal metal, ferric-red streaks, pixel-art textures. All curved/organic, none gabled or flat-boxy. Kit-of-parts sheet.*

### 5.4 Awning / projection-types sheet (§3.7) 🔧
*A reference sheet: a row of 5 faceted low-poly wall-projection variants on plain near-black, each labeled — (1) a taut translucent veined membrane-awning; (2) a rust-streaked faceted metal slat-canopy; (3) a cantilevered balcony slab with a post-rail; (4) a signage bracket-arm carrying a hanging backlit sign; (5) a slanted anti-homeless no-stand ledge. PS2 pixel-tiled, muted teal + ferric red. Kit-of-parts reference.*

### 5.5 Signage sheet (§3.9)
*A reference sheet: a row of 4 low-poly signage variants on plain near-black, each labeled with its register — (1) institutional-project wall-plaque, pristine ("The Plumbing Power Project"); (2) government-aspirational backlit arch-banner ("The Open Files Initiative"); (3) corporate-rebrand hanging bracket-sign, glossy ("The Hypelines"); (4) picturesque-community monument-plaque ("Greenfields Collective"), ironic over a failed function. Terminal-green and warm backlighting, pixel-art text, muted teal metal with rust. Class-coded institutional signage kit.*

### 5.6 Surface-pattern & decay sheet (§3.8, §3.10)
*A reference sheet: two rows of low-poly wall-panel swatches on plain near-black. Top row (materials): riveted facility-metal panel-seam, deck-metal diamond-plate, crosshatch grating, smooth-layered translucent basement-membrane, myelin-wrap nerve-fascicle cabling, pinkish tissue-substrate with vessel grooves. Bottom row (decay overlays applied to a metal panel): ferric-red bleed-streaks, settled oxide dust, char-burn crust, weeping membrane corrosion, collapse-scar cracking, white candid fungal mat. 32px/m pixel-art tiles, muted teal palette, sharp edges. A material+decay atlas reference for the generator's tile system.*

---

## 6. Per-district style presets

Each preset is a **weighting over the §3 knobs** — the generator's "skin" for that district. Table covers all districts (⚠️ forms reconstructed, not locked canon; Act 3 = `PROPOSAL`). Prose entries in §4 cover the priority buildable set (built references exist for Junction/Bridge; early-game for Plumbing/Greenfields/Open Files).

| District (register) | Shell / silhouette | Dominant materials | Signage register | Signature furniture/decoration | Decay type | Emissive accent |
|---|---|---|---|---|---|---|
| **Section 3B / Junction** (institutional) | cave-shell + inserted metal catwalk checkpoint | rock, sand, facility_metal, grate, wall_panel | institutional designator | grates over void, workbench (Lot Clot game) | industrial grime | terminal-green readouts |
| **Iron Bridge** (none) | metal deck spanning a chasm | rust_iron, deck_metal, facility_metal | none | overlook rails, casualties visible through grating below | ferric-red rust | — |
| **Plumbing Power Project** (utility-grandiose) | vertical ascending spiral, pump shafts | facility_metal, grate, rust_iron, channel troughs | institutional-project | rotary valves mid-fault, flow-strips, moisture seeps | iron backwash streaks | terminal-green telegraph |
| **Greenfields Collective** (picturesque-socialist) | lit ring corridor, identical dwellings | clean wall_panel, cream/brown, flora beds | picturesque-community | cycling door-alcoves, drink machine, tended beds | none (tended/optimized) | warm + faint teal flora |
| **The Open Files Initiative** (govt-aspirational) | drawer-stack canyons + top catwalks | drawer metal, terminal panels, grate | government-aspirational | scan arches, terminal chains, tau-thickets | cleaned-data sterility, oxide dust | terminal-green screens |
| **The Hypelines** (corporate-rebrand) | branched conduit halls pinched to toll chokepoints | iron supply pipes, conveyor belts, diverters | corporate-marketing ("Iron Heart" memory) | "Flow Optimization" meters, worn detour paths, ride-able belts | iron-currency oxidation | terminal-green meters |
| **Ancourage** (corporate-cheerful) | burned junction, fused conduits | char_crust floor, heat-fused metal, drainage valves | corporate-cheerful | flaring heat-faults, control terminals, device housings | burn aftermath / char | firelight orange |
| **The Honeycomb Cooperative** (demoralized-socialist) | sealed stripped catwalks (grating in place, insulation stripped beneath), sump halls | bare-wire conduits, grate floors, settling tanks | picturesque-community (ironic over Goodhart rot) | dummy relief valves, faked hollow floor-slabs | Goodhart rot behind clean facade | rust-lit ferric-orange arc sparks |
| **The Cleanstreets Initiative** (capitalist-enclosure) | transit corridors, radial plazas, tram spans | paving_civic, monuments, spiked ledges | government-aspirational (cheerful name, grim function) | anti-homeless spikes (extended by default; sweep-cycle retraction), toll gates, memorial plaques | enclosure-as-landscaping (ambient oxide at the edges) | — |
| **Beacon Hill** (historic-preservation) | archive halls, rolling compacting stacks | preservation shelving, scanner gates | picturesque-community (preservation register) | backward-clock reading-room doors 🔧 (placement pending), enforcement vestibules, scan cones | preservation-as-capture, gloom | cyan-white scan cones |
| **Bulwark Wharf / Filtration** (fortified-crossing) | membrane walls with pores | membrane_panel, ENT consoles, blast-bulkheads | fortified-crossing | pore states (intact/corroded/breached), pore-clamp consoles | ferroptotic weeping, gray/purple haze | terminal-green clamp readouts |
| **Loca's Watchtower** (institutional, boss) | mountain + summit tower, switchback trail | reinforced clean-line metal | institutional | tau/wire tangles inside (signal-cabling↔pathology) | clinical | **watchtower blue** interior |
| **The Paranucleus** (corporate NUTECH, boss) | stacked bone-white/lavender rings + grey NUTECH base | amyloid_bone, tooth-patterned edges | corporate (NUTECH) | raised tooth patterns, purple recesses | amyloid engulfment | **pink-red core** (boss-only) |
| **Sim Dome** (—) | dome over central vessel | translucent skin | — | warm pastel glow leaking through | none (the "unreal" set) | leaking warm pastel |
| *Welcombe Springs* `PROPOSAL` | bath-house drainage terraces, steam-vent halls, broken funicular | (pending) | wellness-picturesque | (pending director) | Zone-3 tissue exposure | (pending) |
| *Harmonia* `PROPOSAL` | oscillator-track ferries, civic-pulse consoles | (pending) | wellness-picturesque | harmony-proxy gates | Zone-3 exposure | (pending) |
| *Sunset Acres* `PROPOSAL` | burial-plot "reserved lots", sinkhole scars | (pending) | cemetery-real-estate | collapsed lots over dead tissue | collapse scars | (pending) |
| *Root Archive* `PROPOSAL` | tag-scanned reading halls, deep vaults | (pending) | foundational-records | scanned reading halls | Zone-3 exposure | (pending) |

**Zone rule (GDD §6.6–6.7):** Zone 2 = architectural flooring over tissue, tissue only at cracks/edges. Zone 3 = the architecture erodes and biological tissue substrate shows through; "almost no architectural cover." The generator's `tissue_through` and `bones_legibility` knobs should ramp with zone.

---

## 7. Feeding imagery back into the generator

Once imagery is generated from this doc, the loop back into the Blender tool:

1. **Element sheets (§5) → the kit-of-parts.** Each labeled variant becomes one enumerated option in §3 — read its proportions, facet count, and which `spatial_grammar` ops reproduce it (`recess` opening + inset pane for a window; `on_wall` slat + `row` posts for an awning; tapered `slab_xz` tiers for a crown). The sheet is the acceptance target: a generated part should read as one of its variants.
2. **Archetype heroes (§4) → massing + preset validation.** Compare a generated building's silhouette against its archetype prompt output; tune `tier_taper`, `footprint_curve`, `branch_depth`, `bay_jitter` until the "grown, not built" read lands and it stops looking boxy-gridded.
3. **District presets (§6) → the "belongs here" gate.** Generate one hero per district, then A/B a procedurally-generated building beside it. If a stranger couldn't tell which district the procedural one belongs to, the preset weighting needs work.
4. **Surface/decay sheet (§5.6) → the tile atlas.** Feeds directly into `blender/textures/gen_tiles.py` — the proposed material additions (`membrane_panel`, `char_crust`, `paving_civic`, `amyloid_bone`) and decay overlays become new atlas rows.
5. **Two-read audit.** For every generated hero, ask both questions: does it read as institutional infrastructure? does it read as biological tissue? If either answer is "no," the histology layer (constraint §2.2) is under-authored.

## 8. Open questions for the director

- ⚠️ **Ratify or replace the reconstructed per-district forms (§6)** once `world_aesthetic_reference.md` surfaces — the *forms* are the least-locked part of this doc.
- 🔧 **Ratify the proposed part vocabularies** (roof/awning/window/door types, §3.3/3.5/3.6/3.7). These are invented within constraints; you own the final catalog.
- **Per-region path geometry** is canon-open (GDD §4.6) — paved roads vs raised walkways vs vessel-channels vs worn paths. Pick per district when we build streets.
- **Act 3 districts + faction architecture** (Aghora counterfeit-agora; purity-faction sleek in-group) are `PROPOSAL`/pending — out of scope until a design pass.
- **Scope of first generator build:** which district preset do we prototype first? (Recommend **Plumbing Power Project / Channels** — it has shipped material references, an existing spiral toolkit via `coil`, and an active gameplay stretch to drop buildings into.)
