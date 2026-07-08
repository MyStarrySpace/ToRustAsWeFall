# Architecture Generator — Build Spec (geometry-only, image-referenced)

**What this file is.** A description-scrubbed, hand-off copy of [`ARCHITECTURE_DESIGN.md`](ARCHITECTURE_DESIGN.md) for driving the Blender build. It states **only geometry, materials, and parameters**, and it points at rendered reference images for the *look* — so the build brief carries no descriptive prose that trips content filters. The design rationale, the canon citations, and the second "reading" of every form live in the design doc; **this file deliberately omits all of that** and says, in its place, *match the reference image.*

**Precedence.** `ARCHITECTURE_DESIGN.md` remains the source of truth for design intent. This file is the source of truth for *phrasing to hand a model.* If they differ, the design doc wins on what to build; this file wins on how to word it. Keep the two in sync when parameters change (regenerate this from the design doc's §3/§4).

**The one rule that replaces all descriptive language:** for any building, **open its reference image first.** The image defines the appearance. The text here defines only the buildable knob values. Do not describe what a form "resembles" — build the geometry and match the picture.

---

## 0. The reference images are the visual bible

Ten rendered hero buildings are staged at [`../reference-images/architecture/`](../reference-images/architecture/). Each is one complete freestanding building at a three-quarter low angle on a near-black background — the acceptance target for its archetype.

| Archetype | Reference image |
|---|---|
| Dwelling block — Greenfields Collective | `greenfields_collective.png` |
| Records hall — The Open Files Initiative | `open_files_initiative.png` |
| Pump-house — Plumbing Power Project | `plumbing_power_project.png` |
| Distribution exchange — The Hypelines | `hypelines.png` |
| Worker-housing block — The Honeycomb Cooperative | `honeycomb_cooperative.png` |
| Transit pavilion — The Cleanstreets Initiative | `cleanstreets_initiative.png` |
| Reading-room hall — Beacon Hill | `beacon_hill.png` |
| Valve control-house — Ancourage | `ancourage.png` |
| Barrier-maintenance gatehouse — Bulwark Wharf | `bulwark_wharf.png` |
| Zone-3 eroded outlet (the everyday building, decayed) | `zone3_eroded_ruin.png` |

---

## 1. Style / render register

Low-poly faceted base geometry in the PlayStation-2-era register — simplified silhouettes, modest polygon count, surfaces gently tapered and chamfered rather than smoothly curved or voxel-blocky. Pixel-art textures at ~32px/m, grid-aligned, limited palette, sharp pixel edges, hand-tiled. Realistic lighting and soft shadow over the whole. **Post-solarpunk in decline** ("solarpunk-Wall·E"): the sweeping, curved, grown-not-built framework of a sustainable civilization, now rusting — the forms are still there, the function isn't.

**Palette lock.** Muted cool teals and greens dominant on architecture; warm cream and brown on natural materials; near-black background. Ferric-red iron-oxide streaks run down exposed metal like drip-marks; rust-colored particulate dust settles on horizontal surfaces; a faint sepia/amber haze filters interior light. **Two saturated lighting anchors only** — warm orange firelight and cold cyan-white scanner light — with terminal-green (`#5ce87f`) accents on screens and readouts. Diorama-on-dark composition, single structure at frame center.

**Geometry grammar.** Every surface curves, branches, spirals, or tapers — **anti-grid, never boxy-gridded.** Load-bearing structure itself branches (see §3.13). Curves are realized as facets (tapered boxes, octagonal lathes, chamfered tiers, offset stacks, coils).

**The two-read rule, stated without description:** every element should read two ways at once — as institutional infrastructure **and** as something grown and organic. **Do not name or describe the organic read.** It is carried entirely by the reference images and by the curved/branched geometry — match those and the second read lands on its own.

**Forbidden:** saturated pink-red anywhere except boss landmarks (reserved). No suburban-gabled or flat-sci-fi roofs. No perfectly gridded facades.

*For isolated element sheets (§5), swap the composition line for: orthographic-ish studio lighting, plain dark background, the element repeated as a labeled row of 3–5 variants, no surrounding building — a kit-of-parts sheet.*

---

## 2. Global constraints (build rules)

1. **Grown, not built — anti-grid, curved, branched, fractal.** Prefer swept / lofted / branched / spiraled / coiled masses over box extrusions. Rooms repeat in shape but vary in size. Larger masses branch into smaller ones. Realize curves via facets.
2. **The two-read look comes from the images, not from words.** Match the reference image's silhouette, surface, and proportions; the "reads as two things at once" quality is a property of that geometry, and is never to be described in the brief.
3. **PS2 low-poly + pixel-texture + realistic lighting.** Faceted, modest poly, gently curved (not smooth, not cubic). Grid-aligned limited-palette pixel textures. Real shadows/AO.
4. **Palette lock** (as §1). Two saturated light anchors. Pink-red saturation forbidden except boss landmarks.
5. **Decay is an authored layer, not noise.** The solarpunk bones stay legible under the rust — you can always read what the place was supposed to be. Decay = authored streak maps, char, weeping corrosion, collapse scars.
6. **Bureaucratic / surveillance overlay.** Scan-grid checkpoints and reader arches; class-coded signage (four registers — see §3.9); aspirational names over failed function; anti-loiter hostile fixtures; "Flow Optimization" toll gates; opening-hours run backward (convenience always-open, culture rare-and-hyped).

---

## 3. Parameter taxonomy — the generator knobs

Each knob is a generator parameter with an enumerated option set. A **district preset** (§6) is a weighting over these. Everything reduces to `spatial_grammar` ops (`slab`/`wall`/`recess`/`on`/`on_wall`/`span`/`row`/`stairs`/`pbox`/`coil`) + tile-atlas materials.

### 3.1 Massing / base shell
`shell ∈ {`
- `curved_balcony_tower` — vertical tiered, each tier a tapered slab with a wrapping balcony ring
- `spiral_organic_mass` — a coil-driven skin spiraling up a core
- `fractal_branch_cluster` — a trunk mass spawning child masses at decreasing size
- `ring_corridor_segment` — a curved arc of repeated cells (Greenfields)
- `layered_panel_wall` — a double-layer wall of translucent apertured panels (Bulwark)
- `drawer_stack_monolith` — floor-to-ceiling drawer slabs cut into sightline canyons (Open Files)
- `dome` — a translucent-skinned dome
- `stacked_ring_monument` — chalk-white tiered rings (boss only)
- `cave_shell_plus_catwalk` — raw rock/sand shell with inserted facility-metal structure (Junction)
- `pod_cluster_mass` — a clump of rounded pods/bubbles fused into one bulbous mass (Hypelines hub; Ancourage twin domes). Children are near-equal rounded lobes fused at the surface. Faceted metaball / merged `pbox` lobes.
- `bell_dome_tower` — a single smooth-shouldered bell/bottle silhouette rising to a rounded dome (Beacon Hill).
`}`
Sub-knobs: `tier_count`, `tier_taper` (0–0.4 inset/tier), `footprint_curve` (0=octagonal, 1=strongly lobed), `branch_depth`, `branch_size_falloff`, `asymmetry`, `lobe_count`, `lobe_fusion` (0=distinct pods, 1=smoothed single mass).

### 3.2 Height
`storeys` (1–8+), `storey_height` (m), `ground_floor_tall` (bool), `setback_schedule` (list of stepped-back tiers).

### 3.3 Crown / roof
Curved/branched/vertical only — never gabled-suburban or flat. `crown ∈ {`
- `domed_cap` — low faceted lathe dome
- `branched_canopy` — roof splits into 2–3 tapered fingers
- `balcony_terrace` — flat planted terrace (alive / desiccated / performative-dead)
- `renewable_crown` — solar-array / wind-vane rig (functional / neglected / decorative)
- `pore_vent_cap` — aperture cluster venting haze
- `service_bulkhead` — utilitarian metal cap with readouts
- `spired_cluster` — a bundle of tapering vertical spires/pinnacles of unequal height (Open Files). A cluster of tapered-box fins.
- `flare_stack` — a slim vent stack venting a live warm-orange flame on a cadence (Ancourage). Also the frame's firelight anchor.
`}` + `crown_overhang` (m), `crown_greenery` (0–1), `crown_finial ∈ {none, cupola, lantern, vane}` (small cap ornament — the Plumbing cupola).

### 3.4 Facade rhythm
`rhythm ∈ {`
- `even_bay` — regular bays
- `varisize_cell` — same shape, varying size (the canonical grown read)
- `stacked_drawer` — dense horizontal drawer bands (Open Files)
- `sparse_alcove` — long blank runs punctuated by recessed alcoves
- `toll_chokepoint` — a wide wall pinched to a single metered gate
- `honeycomb_tessellation` — the whole facade packed as rounded-hexagon cells, each a window bay (Honeycomb). `varisize_cell` at its dense-packed limit.
- `mesh_lattice_infill` — structural bays spanned by an open cellular (Voronoi) mesh-screen instead of a solid wall (Open Files base, Bulwark skin). Built by `gen_voronoi_holemesh`, inset into the bay.
`}` + `bay_width`, `bay_jitter`, `blank_run_ratio`.

### 3.5 Window types
`recess` opening + inset pane box. `window ∈ {`
- `pore_round` — round/oval translucent aperture. Sub-variant `rose_spoked` — radial spoke-mullions divide the aperture like a rose window (Bulwark).
- `hairline_slit` — tall narrow vertical slit, often in branching rows
- `balcony_bay` — floor-height opening onto a balcony
- `drawer_face` — a record-drawer front reading as a window band (Open Files)
- `shuttered_metal` — rolling metal shutter, half-lowered
- `scan_grille` — barred/grilled aperture at a checkpoint
- `honeycomb_cell` — a rounded-hexagon window cell, packed edge-to-edge in a `honeycomb_tessellation` facade (Honeycomb). Each carries its own sill/planter.
- `spoked_vent` — a round vent-porthole covered by a wheel-spoke grille (Ancourage domes).
`}` + `glazing ∈ {dark, terminal-green-lit, warm-lit, boarded, broken}`, `frame_material`, `sill_depth`.

### 3.6 Door / entry
`recess` + door leaf + optional threshold apparatus. `door ∈ {`
- `dilating_aperture` — a dilating aperture (airlock)
- `cycling_slab` — a dwelling door on a shift-schedule cycle (open / closed / mid-cycle)
- `scan_arch` — a reader checkpoint arch you pass through (scan-bar brightens on cadence)
- `toll_gate` — single-file metered "Flow Optimization" gate
- `enforcement_vestibule` — a double-door airlock with a scan cone between (Beacon Hill)
- `service_hatch` — small utilitarian maintenance hatch/grate
- `blast_bulkhead` — heavy sealed door
- `arched_portal` — a plain round-arched recessed doorway with a solid leaf (Greenfields). The civic/residential default.
`}` + `threshold_apparatus ∈ {none, scan-bar, toll-meter, spike-strip, plaque}`, `leaf_state`, `entry_throat ∈ {flush, recessed, lit_tunnel}` (Open Files = `lit_tunnel`, a deep throat washed with cyan light streaming out).

### 3.7 Awnings / canopies / projections
`on_wall` decor over the entry/street. `projection ∈ {`
- `translucent_canopy` — a taut translucent canopy
- `slat_canopy` — faceted metal slat awning, rust-streaked
- `cantilever_balcony` — projecting balcony slab with a post-rail `row`
- `signage_bracket` — an arm carrying a hanging sign
- `hostile_ledge` — a slanted no-stand ledge (enforcement, not shelter)
- `conveyor_spur` — a powered belt spur feeding the building
- `transit_viaduct` — a large elevated tubular conduit-highway branching off and running out of frame, lit traffic riding its top (Hypelines). `conveyor_spur` at district-infrastructure scale; a `span` at ride height.
- `entry_hood` — a small faceted curved/low hood over a single door (Plumbing; Zone-3 ruin). A door-shelter, **not** a building roof — keep it minor.
`}` + `projection_depth`, `projection_condition ∈ {intact, sagging, collapsed, retracted}`. Branching *columns* that carry a canopy are `structure` (§3.13), not projections.

### 3.8 Surface material & pattern
`material ∈ { rock, sand, facility_metal, grate, rust_iron, biolum_teal, deck_metal, wall_panel, layered_panel, char_crust, paving_civic, mineral_crust }` (from `blender/textures/gen_tiles.py` stems + proposed additions); each surface picks a material + a variation (`crc32(name)%4`). `pattern_overlay ∈ {`
- `panel_seam` — riveted metal panel seams
- `diamond_plate` — deck-metal tread
- `crosshatch_bars` — grating
- `layered_translucent` — smooth-layered translucent striation (Bulwark panels)
- `wrapped_cable` — bundled-cable / wrapped-conduit striping on runs (heavy on Hypelines)
- `substrate_grooved` — a grooved underlayer exposed at eroded surfaces in Zone 3
- `scale_shingle` — overlapping fish-scale/shingle tiling on a curved drum or dome (Plumbing flank; Ancourage domes). A pixel-tile pattern.
- `whiplash_tracery` — raised Art-Nouveau vine-rib relief webbing across the facade and framing the openings (Beacon Hill; Greenfields ribs). Thin `on_wall` relief strips or baked into the tile. The strongest grown-not-built facade cue.
- `cellular_mesh` — an open Voronoi hole-mesh screen (from `gen_voronoi_holemesh`) as a skin or bay infill (Open Files, Bulwark). Pairs with `mesh_lattice_infill`.
- `honeycomb_relief` — raised rounded-hexagon cell relief tiling a wall (Honeycomb).
`}`

### 3.9 Signage / propaganda / wayfinding
`sign_register ∈ { institutional_project, government_aspirational, corporate_rebrand, picturesque_community }` (**closed set — do not extend**) × `sign_condition ∈ { pristine, ironic_over_failure, hyped_rare_opening, always_open_convenience }`. `on_wall` panels with emissive text. `sign_form ∈ {`
- `wall_plaque`, `hanging_bracket_sign`, `backlit_arch_banner`, `projected_floor_text`, `monument_plaque`
- `regulatory_placard` — a small rounded-rectangle rule/prohibition plaque, often clustered ("NO LOITERING · NO SITTING · NO RESTING"; "STANDING ONLY BEYOND THIS POINT" — Cleanstreets)
- `numeric_designator` — a large stamped sector/unit number ("6", "7" — Bulwark)
- `status_readout` — a live line-item status board ("PORE CLAMP · P01 OK · P02 FAIL · P03 SEALED"; "FLOW OPTIMIZATION TOLL GATE"), terminal-green
`}` + **`district_emblem`** — a per-district logo mark on plaques (Greenfields/Open Files crest; Honeycomb three-cell flower; Cleanstreets four-point sparkle; Ancourage smiley-flower mascot).

### 3.10 Decay overlay stack (authored maps, not noise)
`decay ∈ {`
- `none` — tended/optimized surfaces
- `ferric_bleed` — iron-oxide streaks running down from seams/openings
- `oxide_dust` — rust particulate settled on horizontals
- `sepia_haze` — amber interior-light filter
- `char_burn` — fire-fuel char crusting (Ancourage)
- `weeping_corrosion` — apertures corroding/weeping (Bulwark)
- `collapse_scar` — sinkhole/give-way scarring
- `candid_mat` — white encrustation mat creeping up
- `mineral_drip` — a molten drip-crust engulfing the shell, oozing off ledges and pooling as runnels on the ground (Zone-3 ruin). **Palette guard: render desaturated rust-brown / dun, NOT saturated pink-red** (pink-red is boss-only).
`}` + `decay_amount` (0–1), `bones_legibility` (≥0.4 — the form stays readable).

### 3.11 Emissive / terminal accents
`emissive_use ∈ {terminal_green (#5ce87f), scanner_cyan_white, firelight_orange, watchtower_blue (one boss interior only), flora_teal, none}` on terminals, scan-bars, flow-strip telegraphs (brighten one beat before a hazard), portal pads, override consoles, valve readouts. Fixtures: `fluid_spill_glow` (a valve/trough spilling glowing terminal-green fluid — Plumbing), `flare_flame` (a warm-orange flame plume on a `flare_stack` — Ancourage), `lit_tunnel` throat (cyan streaming from a deep entry — Open Files). `emissive_strength`, `telegraph_pulse` (bool). **Pink-red core allowed only on boss landmarks.**

### 3.12 Street-level furniture
`furniture[] ⊂ { drink_machine, recharge_pod, toll_meter, herd_space_booth, memorial_monument, anti_homeless_spikes, rotary_valve_wheel, relief_console (+ dummy variant), conveyor_belt, record_drawer_terminal, workbench, terminal_kiosk (freestanding pedestal terminal, green screen), wall_sconce_lantern (warm door lantern), planter_trough (under-window/rail planter box), bollard_row (short posts ringing a plaza), street_lamp (post lamp), queue_rail (switchback rails into a gate), flywheel_gear (large decorative rotating wheel — Hypelines), pipe_root_spread (a fan of drainage conduits erupting from the base and crawling across the ground — Ancourage, Zone-3) }`. Parameter per item: functional / neglected / dummy.

### 3.13 Structural columns / ribs — the branching frame
The load-bearing structure branches (six of ten heroes carry tiers/canopies on splitting members). Realize as tapered `pbox`/tapered-box members with recursive child branches, or `on_wall` relief ribs. `structure ∈ {`
- `branching_tree_column` — a column splitting upward into 2–4 tapering limbs to carry a tier or canopy (Greenfields piers)
- `mushroom_canopy_column` — a column flaring at the top into a broad sweeping cap (Cleanstreets pavilion)
- `tapered_pier` — a plain waisted/tapered load pier framing bays (Bulwark)
- `buttress_fin` — a clustered full-height exterior rib/buttress (Open Files; continues into the `spired_cluster` crown)
- `vine_rib_web` — thin structural ribs webbing across the facade and branching around openings (Beacon Hill; structural read of `whiplash_tracery`)
- `strut_truss` — an open branched truss supporting a `transit_viaduct` or elevated mass (Hypelines)
- `none` — plain wall-bearing
`}` + `branch_depth`, `branch_splay`, `taper`, `fuse_to_canopy` (limbs merge into a cap).

---

## 4. Archetype build table — image + knobs (no prose)

For each: **open the image, match it**, then set these knobs. No further description is given by design.

### 4.1 Greenfields Collective — `greenfields_collective.png`
Silhouette: a lobed 3-tier arc, balconies wrapping each tier, all units identical, warm-lit, no rust.
`shell=ring_corridor_segment (lobed arc)` · `storeys=3` · `tier_taper=0.2` · `footprint_curve=high` · `structure=branching_tree_column` · `rhythm=even_bay (identical units — the sameness is the point)` · `window=balcony_bay + pore_round (identical per dwelling), glazing=warm-lit` · `door=arched_portal (cycling)` · `crown=balcony_terrace (planted, tended)` · `projection=cantilever_balcony` · `furniture=[planter_trough, wall_sconce_lantern, bollard_row, drink_machine]` · `sign=picturesque_community + district_emblem crest, pristine` · `decay=none` · `emissive=flora_teal + warm`.

### 4.2 The Open Files Initiative — `open_files_initiative.png`
Silhouette: a tall cathedral-like slab of vertical drawer fins, a bundle of spires up top, a glowing cyan tunnel entry at the base.
`shell=drawer_stack_monolith (canyon-cut fins)` · `storeys≈6` · `asymmetry=high` · `structure=buttress_fin` · `crown=spired_cluster` · `rhythm=stacked_drawer + mesh_lattice_infill (base arcade)` · `window=drawer_face + scan_grille` · `door=scan_arch, entry_throat=lit_tunnel` · `furniture=[terminal_kiosk ×2, street_lamp]` · `sign=government_aspirational backlit_arch_banner + crest emblem` · `decay=oxide_dust + sepia_haze` · `emissive=terminal_green drawers + scanner_cyan_white tunnel`.

### 4.3 Plumbing Power Project — `plumbing_power_project.png`
Silhouette: a faceted drum wound by an external climbing trough-ramp, domed cap with a cupola, valve-wheels and a green spill at the base.
`shell=spiral_organic_mass (octagonal drum + external climbing trough-ramp + inclined shaft wing)` · `storeys=3` · `material=facility_metal + rust_iron` · `pattern=scale_shingle` · `crown=domed_cap, crown_finial=cupola` · `window=hairline_slit` · `door=service_hatch, projection=entry_hood` · `furniture=[rotary_valve_wheel ×4]` · `projection=conveyor_spur→trough` · `sign=institutional_project` · `decay=ferric_bleed (heavy)` · `emissive=terminal_green flow-strip (telegraph_pulse) + fluid_spill_glow`.

### 4.4 The Hypelines — `hypelines.png`
Silhouette: a bulbous fused-pod hub with big tubular pipe-highways radiating off it (lit traffic), a large side wheel, cable-wrapped all over.
`shell=pod_cluster_mass (hub)` · `structure=strut_truss` · `projection=transit_viaduct ×3 (lit traffic)` · `rhythm=toll_chokepoint` · `door=toll_gate` · `furniture=[flywheel_gear, toll_meter, queue_rail]` · `pattern=wrapped_cable (heavy)` · `sign=corporate_rebrand hanging_bracket_sign + ghost lettering ("IRON HEART")` · `decay=ferric_bleed + oxide_dust` · `emissive=terminal_green meters`.

### 4.5 The Honeycomb Cooperative — `honeycomb_cooperative.png`
Silhouette: two faces of one block — a clean honeycomb-window street face, and a stripped/rusted flank with a blown-out bay and orange sparks. Frame both at once.
`shell=curved_balcony_tower` · `storeys=5` · `rhythm=honeycomb_tessellation` · `window=honeycomb_cell (broken on flank)` · `furniture=[relief_console (dummy variant), planter_trough (display face only)]` · `decay=collapse_scar (flank only); display face pristine` · `sign=picturesque_community × ironic_over_failure + three-cell-flower emblem` · `emissive=firelight_orange sparks on a cadence (flank; grating in place, insulation stripped beneath it)`.

### 4.6 The Cleanstreets Initiative — `cleanstreets_initiative.png`
Silhouette: a low pavilion on a sweeping mushroom-column canopy, every surface refusing rest (extended spikes, slanted ledges), rule-placards everywhere.
`shell=ring_corridor_segment (open pavilion)` · `storeys=1` · `structure=mushroom_canopy_column` · `crown=branched_canopy (low sweep)` · `door=toll_gate (platform entry)` · `projection=hostile_ledge throughout` · `furniture=[anti_homeless_spikes (extended by default; retract only for the timed sweep window), memorial_monument, toll_meter, queue_rail]` · `sign=government_aspirational + regulatory_placard clusters + four-point-sparkle emblem, pristine` · `decay=oxide_dust (edges only — enforcement surfaces immaculate)` · `emissive=scanner_cyan_white at gate`.

### 4.7 Beacon Hill — `beacon_hill.png`
Silhouette: a tall bell/bottle tower webbed in whiplash stone tracery, sealed doors, an enforcement vestibule with a cyan-lit armored door. Ferric-red sky.
`shell=bell_dome_tower` · `storeys=3 (tall)` · `pattern=whiplash_tracery` / `structure=vine_rib_web` · `window=hairline_slit (dark, stacks faintly visible within)` · `door=enforcement_vestibule` · `furniture=[wall_sconce_lantern]` · `sign=picturesque_community × hyped_rare_opening ("READING ROOM OPENS — ONE DAY ONLY")` · `decay=decay_amount≈0 + sepia_haze (no rust)` · `emissive=scanner_cyan_white scan cone + terminal_green hours board`.

### 4.8 Ancourage — `ancourage.png`
Silhouette: a squat twin-dome pod with a live flare on top, a fan of black drainage pipes crawling from the base across the ground, a cheerful mascot plaque.
`shell=pod_cluster_mass (twin domes)` · `storeys=1–2` · `material=facility_metal + char_crust` · `crown=flare_stack (live flame, telegraph_pulse)` · `window=spoked_vent + scan_grille (terminal-green glazing)` · `door=service_hatch` · `furniture=[rotary_valve_wheel (wall), pipe_root_spread, relief_console]` · `sign=corporate_rebrand (cheerful) + smiley-flower mascot emblem, incongruously pristine` · `decay=char_burn + ferric_bleed` · `emissive=firelight_orange flare + terminal_green terminals`.

### 4.9 Bulwark Wharf — `bulwark_wharf.png`
Silhouette: a squat gatehouse built against a huge purple apertured wall; round rose-spoked apertures in three states; a PORE-CLAMP status board; a stamped "6". Gray-purple haze.
`shell=layered_panel_wall + squat gatehouse mass` · `storeys=2` · `window=pore_round/rose_spoked (three states: intact / weeping / clamped)` · `pattern=cellular_mesh (wall skin), layered_translucent (panels)` · `door=blast_bulkhead` · `furniture=[relief_console (pore-clamp), terminal_kiosk]` · `sign=numeric_designator + fortified-crossing designator + status_readout ("PORE CLAMP")` · `decay=weeping_corrosion` · `emissive=terminal_green clamp readouts` · sky: gray-purple haze (boundary exception).

### 4.10 Zone-3 eroded outlet — `zone3_eroded_ruin.png`
Silhouette: a small storefront consumed by a rust-brown molten drip, pipe-roots crawling across the ground, an "ALWAYS OPEN" sign gone dark, the bones still legible.
`shell=fractal_branch_cluster (small trunk + one annex)` (the everyday outlet, decayed) · `storeys=2, ground_floor_tall=true` · `rhythm=varisize_cell` · `window=shuttered_metal (broken) + hairline_slit (boarded)` · `projection=entry_hood (collapsed)` · `furniture=[pipe_root_spread, record_drawer_terminal (dead)]` · `sign=corporate_rebrand × always_open_convenience ("ALWAYS OPEN"), dead/unlit` · `decay=mineral_drip (DESATURATED rust-brown, not pink) + collapse_scar + ferric_bleed + candid_mat (flank)` · `bones_legibility≈0.5` · `emissive=none`.

---

## 5. Element sheets (kit-of-parts)

There are no new parameters here — an element sheet is just a **labeled-row render of one §3 knob's option set** (all windows in a row, all crowns in a row, all structural columns in a row, etc.), faceted low-poly variants on a plain dark background, one menu per knob. Build straight from §3 (the options) and §4 (the per-building presets); generate a sheet, when you want one, by lining up a single knob's variants. Don't read the design doc for these — everything you need is §3 above.

---

## 6. District presets

A district preset is just a weighting over the §3 knobs. **Each building in §4 already IS its district's preset** (its image + knob set), so §4 is the working preset list — build from it directly. Zone rule: Zone 2 = architectural surfaces with the underlayer showing only at cracks/edges; Zone 3 = surfaces erode and the grooved underlayer is exposed (`underlayer_through`/`bones_legibility` ramp with zone). This build brief is self-contained; you do not need to open the design doc.

---

## 7. Build prompt for Fable (copy-paste)

> Build a **parametric Blender generator** for the buildings of a game world, in a **low-poly PlayStation-2-era faceted style with 32px/m pixel-art tile textures and realistic lighting**. Work in a live Blender over the socket (`python /c/tmp/blsend.py < script.py`); render each result to `C:\tmp\*.png` so it can be checked.
>
> **The look is defined by reference images**, one per building, in [`../reference-images/architecture/`](../reference-images/architecture/) — open each and match its silhouette, surface, and proportions. Do not infer meaning from the forms; just build the geometry to match the picture.
>
> **Palette lock:** muted teal/green architecture, warm cream/brown on natural materials, near-black background, ferric-red rust streaks on exposed metal, two saturated light anchors only (warm orange fire, cold cyan-white scanner), terminal-green `#5ce87f` on screens. **No saturated pink-red** (reserved for boss landmarks, not in this set).
>
> **Geometry grammar:** every surface curves, tapers, branches, spirals — anti-grid, never boxy. Realize curves as facets (tapered boxes, octagonal lathes, chamfered tiers, coils). Load-bearing structure itself branches (tree-columns, buttress-fins, mushroom-canopy columns — see §3.13).
>
> **Parameters:** implement the knobs in §3 of this file — massing (§3.1), height (§3.2), crown (§3.3), facade rhythm (§3.4), windows (§3.5), doors (§3.6), projections (§3.7), material/pattern (§3.8), signage (§3.9), decay (§3.10), emissive (§3.11), furniture (§3.12), structural columns (§3.13). Each building in §4 is a preset of these knobs plus its reference image.
>
> **Reuse the building-generation skill** at `blender/skills/building-generation/` — its `helpers.py` (deterministic `h01`, faceted `finish`, `alpha_flags`, demo scaffolding) and its two generators (`gen_voronoi_holemesh` for `cellular_mesh` / `mesh_lattice_infill`; `gen_blob_mass` for `pod_cluster_mass`). Every generator is deterministic (hash an index, never `randf`), faceted, and ships a NEAR mesh + a FAR flat-plane impostor.
>
> **Start with one building** — pick `plumbing_power_project.png` (it has shipped material references and a coil/spiral toolkit) — get it matching its image, then generalize the knobs across the other nine.

---

## 8. Keeping this file in sync

When §3/§4 change in `ARCHITECTURE_DESIGN.md`, regenerate this file's §3/§4 from them and **scrub every biology-adjacent word**, using the identifier map below and the design doc's §3.0 provenance. The second "reading" of each form is **never** transcribed here — it lives in the images and in the design doc. Same scrub pattern as `blender/paranucleus/PARANUCLEUS_FABLE_SPEC.md`.

**The design-doc↔safe-name identifier map** (needed only to cross-walk this file against `ARCHITECTURE_DESIGN.md`) is kept on the design-doc side, at [`ARCHITECTURE_DESIGN.md`](ARCHITECTURE_DESIGN.md) §3.0a — so this build brief itself stays free of the meaning-bearing names. Each renamed knob here is the same knob there, under its safe name.

Kept as-is in both (genuine industrial/geology/botanical cover, low flag risk): `pore_round`/`pore_vent_cap`/`spoked_vent`, `ferric_bleed`, `weeping_corrosion`, `substrate_grooved`, `cellular_mesh`, `bones_legibility`, `flora_teal`, `biolum_teal`, `scale_shingle`, `pipe_root_spread`. The in-world signage string "PORE CLAMP" is a quoted readout, not a knob — leave it.
