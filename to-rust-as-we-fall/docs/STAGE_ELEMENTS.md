# Stage Elements Register — non-building level elements per progression stage, and how they look

**Owner: the director** (edit freely). Drafted 2026-07-12 on the director's ask: "flesh out some
more non-building level elements for each stage and how they look." Everything here is PROPOSED
until approved; working names are DESCRIPTIVE, never new world-nouns (the ENVIRONMENT_ELEMENTS
law). This register is LOOK-FIRST: mechanics stay one line with a cross-reference — deep
mechanism design lives in ENVIRONMENT_ELEMENTS.md (per-district) and ECOLOGY_COMBOS.md
(flora×fauna); this doc owns what populates a generated level's GROUND at each stage and what the
player's eye reads.

**Stages** are the combine-characters learning ramp (curriculum stages 1–6; every PREVIEW_ENTRIES
row carries one). Working alignment to the canonical shelter spans (act1_timeline.md — the
director can slide this):

| Stage | Shelters | Districts (canonical) | Teaching beat |
|-------|----------|----------------------|---------------|
| 1 | 1–3 | Section 3B, Plumbing Power Project | single character; read the room |
| 2 | 4–7 | Greenfields Collective, The Open Files Initiative | pair verbs (WHERE + WHEN) |
| 3 | 8–10 | The Hypelines, Ancourage | trio forming; routing pressure |
| 4 | 11–14 | The Honeycomb Cooperative, The Cleanstreets Initiative | full party; institutional pressure |
| 5 | 15–18 | Beacon Hill, Bulwark Wharf | mastery; choice density |
| 6 | 19+ | Welcombe Springs, Harmonia, Sunset Acres, Root Archive (Act 3 — PROPOSAL, GDD L505/L729) | diagnosis |

## The four ambient dials (the descent's visual spine)

Every stage sets these four dials before any element is placed — they are what makes a generated
level READ as its stage even before a mechanic fires. (Engine terms: 32 px/m pixel-art atlas
materials, flat simple forms, painted detail — the texture-over-geometry law; glow discipline per
the palette registry below.)

1. **Iron** — rust coverage and saturation. Stage 1: stain fans at joints. Stage 6: whole
   surfaces gone to umber, rust dust in the air.
2. **Flora health** — the canon ladder (flora_taxonomy "Ambient flora"): wild clusters + quiet
   forget-me-nots (life) → decorative invasives only (installed prettiness, DECORATIVE_FLORA.md)
   → vine skeletons (the past) → NOTHING (Dead Zone silence — the strongest collapse signal;
   absence is the element).
3. **Light temperature** — terminal green `#5ce87f` = powered institutional; amber = inhabited
   warmth; cool blue-white = enforcement/preservation; magenta = the Aghora only; gray-purple
   lavender = the amyloid signature; pink-red = the Paranucleus core ONLY. A stage reads by which
   registers still burn and which have died to gray.
4. **Human trace freshness** — tended (today) → habitual (worn paths, knotted tags) → abandoned
   (drifts, tape) → given up (middens). Peris pauses near the old ones; the game never points.

Interaction grammar (unchanged, every stage): interactive elements are CLICK-GATED by default
with the outline/verb grammar; everything that hurts telegraphs pause-readably before it bites;
timed elements ride the scheduler (fast-forward invariant); pure dressing carries NO outline.

---

## Stage 1 — Section 3B / the Plumbing (read the room)

1. **Iron stain fans** (AMBIENT). Rust bleeding down from every pipe joint and bolt line in
   fan-shaped runs. LOOK: decal quads hugging surfaces, ochre core → deep umber edge with
   pixel-dither falloff, dead matte against the metal's sheen. Density is the degradation read —
   the player learns "rust marks where the body is failing" here, at stain scale, before it ever
   costs them anything. CANON: the title. COMPOSABLE-NOW (tile-atlas decals).
2. **Drip stalactites + beat puddles** (AMBIENT, teaching). Mineral drip cones under leaking
   runs; the puddles below pulse a faint ripple ring ON THE WASH CADENCE (cosmetic, reads the
   scheduler tick). LOOK: gray-green cones 10–30 cm, wet-dark floor discs, a 1 px ripple ring
   that brightens a beat before each surge — the flow-strip telegraph taught as scenery before
   the channels ask you to bet a crossing on it. CANON: CHANNELS_DESIGN "always-on tell".
   COMPOSABLE-NOW (Channel cadence + decal).
3. **Maintenance tag ribbons** (AMBIENT, human trace). Faded cloth work-tags knotted to valve
   stems and rail posts — the tending practice that lapsed (GDD L727), left as knots. LOOK: 2–3
   small cloth quads per cluster, washed-out work-order colors (dull cyan, safety orange gone
   pink), slight cosmetic sway. Fresh knots cluster near shelters; deeper in they're bleached.
4. **Pipe gantry catwalk** (WALKABLE FURNITURE). A low steel service walk along the big runs:
   kick plates, mesh deck, one handrail. LOOK: dark steel, mesh reads as a 2-tone dither tile,
   terminal-green inspection lamp every N metres (the powered-institutional register). Teaches
   inter-level links gently (a knee-height first "floor above"). COMPOSABLE-NOW (grid levels +
   ladder links exist).
5. **Condensation moss sheets** (AMBIENT). The canon non-gameplay moss on damp walls — visually
   near-Scarpet but matte, no function; Peris can tell by touch, Aster's overlay tags them apart.
   LOOK: dark teal-green sheets with a wet sheen line at the top edge, never glowing (glow
   belongs to Seefern). CANON: flora_taxonomy moss carpets. COMPOSABLE-NOW (decal).

## Stage 2 — Greenfields / the Open Files (pair verbs)

1. **Raised-bed allotments** (AMBIENT + flora sockets). The cooperative's planting beds in rows:
   timber frames, soil mounds. Most gone woody — vine skeletons holding a crop's shape with the
   life out of it — but beds near shelters still live, and forget-me-nots sit quietly at bed
   corners (canon: every shelter has some). LOOK: weathered plank frames (32 px/m wood tile),
   umber soil, sparse silver-dry stalks; the LIVING bed reads by its two saturated greens and its
   blue corner dots. Functional flora (Seefern/Hushbloom) sockets into beds in generated levels —
   the bed is the WHERE hint. NEEDS-BUILD: a `planter_bed` loader kind (a dressing box + flora
   socket anchor).
2. **Clothesline spans** (AMBIENT, sightline). Ground-level laundry lines between leaning poles
   (the roof motif brought down). Hung cloth breaks LOS — ambient concealment geometry that
   telegraphs its flimsiness by swaying. LOOK: sagging catenary line (the banner-line builder
   reused), 2–4 cloth quads, vertex-painted faded dyes, always in motion.
3. **Community board pylons** (INTERACTIVE, lore surface). Freestanding notice totems: layered
   paper scraps, staples, one still-running terminal-green message strip cycling institutional
   text. LOOK: a 2.2 m concrete slab pylon, paper texture patches at reading height, the green
   strip's glow spilling 20 cm. Click = read (INSPECTION); the strip's text is a DialogueData
   key, never inline. NEEDS-BUILD: `notice_pylon` kind (Interactable + text hookup).
4. **Data conduit troughs** (AMBIENT, teaching WHEN). Open Files floor furniture: cable runs
   under glass floor-strips, information PULSING along them in one direction — terminal green
   packets sliding through the dark. Dead runs are shattered and dark. LOOK: a 30 cm glass strip
   flush with the floor, emissive packet dashes moving on the scheduler (direction = toward the
   live archive: a compass the level bakes into its floor). The Aster-read teaching surface —
   pair-stage WHERE/WHEN grammar in scenery. COMPOSABLE-NOW (emissive scroll shader).
5. **Card-index drifts** (TERRAIN COST). Spilled data-cards drifted ankle-deep against walls and
   in corners — leaf litter made of records. Walking through is slowed (mud-speed) and LOUD
   (detection radius bump while in the drift). LOOK: off-white rectangle confetti in banked
   drifts with a dishevelled top surface; disturbed cards flutter (cosmetic particles). Teaches
   terrain cost + noise discipline before stealth stages. NEEDS-BUILD: `card_drift` kind (a
   CandidZone-pattern coverage zone: speed + detection modifier, no damage).

## Stage 3 — the Hypelines / Ancourage (trio, routing pressure)

1. **Overhead conveyor lines** (HAZARD + mobile cover). The distribution economy still moving:
   suspended hook-and-bucket lines crossing the level on the scheduler. Under a loaded bucket =
   a drop-hazard cell that telegraphs (the bucket rattles + its floor shadow saturates one beat
   before a drop); walking WITH a big bucket = moving concealment (ECOLOGY_COMBOS hook). LOOK:
   dark steel rail overhead, rust-orange buckets at intervals, a soft moving floor shadow —
   the level's metronome made visible. NEEDS-BUILD: `conveyor_line` kind (phase-parameterized
   like Channel; drops predicted analytically, never frame-sampled).
2. **Sorting chutes + tip bins** (INTERACTIVE, lure verb). Wall-fed funnels over wheeled bins.
   Tipping a bin (INSPECTION) dumps a clatter of goods: a one-shot NOISE lure — the Flure's
   grammar with junk instead of scent. LOOK: galvanized funnel mouths, a bin heaped over the rim,
   spill fans of small boxes on the floor where past tips happened (the tell that it works).
3. **Pallet stack mazes** (SOFT COVER). Crate walls of undelivered goods: full cover that
   Gnawers CHEW — a stack visibly loses cells (chew notches, sawdust cones) on a scheduled
   cadence until the wall opens. LOOK: strapped crate cubes, stencil marks, bite-scalloped edges
   appearing over time. Destructible-cover teaching for trio repositioning. NEEDS-BUILD:
   `pallet_stack` kind (occupancy cells + staged mesh swap).
4. **Anchor bollard fields + chain runs** (TRAVERSAL). Ancourage's foundation register: massive
   rusted anchor drums with catenary chains between them. Chains are walkable balance lines
   (slow, exposed, no rail); the drums are hold points. LOOK: 1.5 m iron drums streaked with
   stain fans, chain links thick as forearms, sag that cosmetic-sways underfoot. CANON: Ancourage
   = foundation layer. COMPOSABLE-NOW (CrawlTunnel authored path, crawl grammar).
5. **Shunt vents** (WHEN read). Sealed Inflammashunt hatches with warning chevrons; one in N
   lives, exhaling steam on a strict cadence — crossing costs a scald unless timed. LOOK: round
   iron hatch flush with the ground, worn yellow-black chevron ring, breath of white steam
   with a pressure-hiss pre-tell (the vent ring glows dull orange one beat before). CANON:
   Ancourage's Inflammashunt DZ junction (act1_timeline). NEEDS-BUILD: `steam_vent` kind
   (Channel-pattern timed hazard, single cell).

## Stage 4 — the Honeycomb / Cleanstreets (full party, institutional pressure)

1. **Plaza rain-sails** (SIGHTLINE). Tensioned canvas sails on lean poles over plaza cells —
   overhead cover that breaks Spiker/watch sightlines from above, bought at the price of not
   seeing up either. LOOK: the stall-canvas language scaled up: 3–5 m triangles, sun-bleached
   vertex-painted dyes, taut (not sagging — tension is the read that they're maintained).
2. **Tactile guidance strips** (PATROL READ). Transit-plaza paving with raised guide lines — and
   the Naturalizers PATROL ALONG THEM (the routes are baked into the floor; reading the strips IS
   reading the patrol map — Tyreg's layer foreshadowed in concrete). LOOK: pale strips with
   raised-dot texture crossing the plaza in clean arcs, polished bright along the center by
   passage — the wear line is the tell.
3. **Anti-homeless architecture 21–24** (BUILT/PROPOSED — SET_PIECES). Cleanstreets is their
   densest zone; the spike strip is live (`spike_strip`), the leaning rail / partition chicane /
   anti-sit cylinder are the approved-pending set. This stage is where the city's hostility
   becomes the party's toolkit.
4. **Checkpoint queue rails** (FUNNEL). Crowd-control serpentines in brushed steel — single-file
   geometry (the chicane's civic cousin): packs thread them one at a time; so do you. LOOK:
   waist-high rail loops, queue-worn floor, one dead ticket pylon per run with a cool-blue lamp
   (enforcement register) that may still scan (stealth spice, one in N live).
5. **Civic planter monoliths** (DECOR ANCHOR). Concrete cubes crowned with DECORATIVE invasives
   (Verdanta pile, Curbelia rows — DECORATIVE_FLORA.md): the performative-garden register at
   full density (GDD L965). LOOK: bush-hammered concrete, staining at the drip line, impossibly
   even green on top. Peris's Y-read lights the crown yellow; there is never anything to take.

## Stage 5 — Beacon Hill / Bulwark Wharf (mastery, choice density)

1. **Archive crate columns** (CLIMB + TOPPLE). Preservation-as-capture made physical:
   shrink-wrapped object stacks in numbered columns, climbable, top-heavy — a push topples one
   (BG3-push grammar) into a bridge or a block. LOOK: translucent wrap over anonymous shapes
   (the wrap's specular is the read), stencilled accession numbers, dust shoulders.
2. **Preservation lamp lecterns** (LIGHT INVERSION). Reading stands under cool-white cone lamps.
   The lit cone is the DANGEROUS place (watched, catalogued): standing in it maxes your
   detection profile. LOOK: brass-dark lectern, a hard-edged white light cone with dust motes,
   blackness around it — the game's one place where light means exposed, taught at mastery.
3. **Barrier gantry cranes** (BRAKE GRAMMAR ECHO). Bulwark's maintenance cranes with hanging
   plate loads that traverse on the scheduler; a park brake at the base holds a load where you
   set it (the Paranucleus brake verb, street-scale, learned before the finale needs it). LOOK:
   riveted gantry legs, a slab load on chains, cool worklights; the brake pedestal reuses the
   NUTECH caliper silhouette.
4. **Sluice mouths + tide gates** (TIMED WATER). The seawall register: barred outfall mouths
   whose gates lift on a tide cadence — crossable channels that flood back (the water-basin set
   piece extracted to district furniture). LOOK: green-slimed stone lips, dripping bar gates,
   high-water staining that MARKS the flood line (the always-on tell is painted on the wall).
5. **Quarantine tape webs** (RISK GATE). Candid-contested barriers: biofilm-fouled tape and
   fencing across the fast route. Passing through is the Candid trade (hp for the shortcut +
   scan-blindness); around is long. LOOK: sagging tape runs gone stiff and pale, biofilm sheets
   webbing the gaps (the CandidZone mat vocabulary, vertical), warning placards bleached blank.

## Stage 6 — Act 3 registers (diagnosis; PROPOSAL like everything Act 3)

1. **Mineral terrace shelves** (Welcombe Springs). The failed spa's iron-mineral terraces:
   travertine shelf pools stepping down a slope, crusted rims. Some rims are load-bearing, some
   are shell — the crust CRACK-TELEGRAPHS (spreading fracture lines + a dry tick) before a plate
   drops. LOOK: banded ochre/bone terraces, standing mineral water with a dead-flat mirror
   surface, rim crusts like pie edges; beautiful and untrustworthy — the wellness lie as terrain.
2. **Entrainment light poles** (Harmonia). Fields of pole-mounted strobe heads, mostly dead. The
   live ones pulse the gamma beat; inside a live pool your OWN reads sharpen (TRACE lookahead +1)
   but so does your visibility — diagnosis stage trades. LOOK: clinical white poles, opal
   heads, a soft 40 Hz-suggesting flicker (rendered as a gentle pulse, never a real strobe),
   overgrowth threading dead heads. CANON: Harmonia = gamma entrainment infrastructure.
3. **Give-up middens** (Sunset Acres). Drifts of surrendered belongings — carts, bundles, shoes
   — banked where people stopped carrying them. Pure loot-vs-time reads: rummaging is slow and
   loud, mostly yields nothing. LOOK: monochrome-dusted heaps with one saturated object per
   midden (the eye-catch that may or may not be worth it); Peris pauses at these (canon: she
   registers vine skeletons — this is the human rhyme).
4. **Root conduit buttresses** (Root Archive outskirts). Cathedral-scale cable-roots from the
   deep archive breaching the ground and arching back in — walkable inter-level highways at the
   endgame's threshold. LOOK: bone-pale sheathing over braided dark cable (the Paranucleus
   bone/lavender language quoted at ground scale), gray-purple region light, NO pink-red (the
   core's color stays the core's).
5. **The verge line** (Dead Zone boundary — the anti-element). The line where even the unnamed
   wild flora stops. No fence, no sign: flora density falls to zero across three metres and the
   soundscape loses its insect layer. LOOK: nothing — which is the point. Generators enforce it
   by CLAMPING all flora/decor density to zero past the line (absence as the strongest signal —
   flora_taxonomy's law). COMPOSABLE-NOW (a decor-density mask).

---

## Build order (when approved)

The generator consumes these as loader object kinds + decor-pass density entries (the
DECORATIVE_FLORA placement pattern). Cheapest-first, teaching-critical first: stage-1 ambients
(pure dressing, no mechanics) → `card_drift` + `steam_vent` (CandidZone/Channel patterns,
nearly free) → `notice_pylon` + `planter_bed` (Interactable + socket) → `conveyor_line` +
`pallet_stack` (new mechanics, phase-parameterized) → the stage-5/6 set pieces as their
districts come online. Every interactive kind ships with its outline wrap, its telegraph, and a
`--test-*` guard; every ambient obeys the four dials.
