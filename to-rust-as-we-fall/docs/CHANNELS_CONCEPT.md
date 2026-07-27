# Channels (Wash Relay) — Concept Art Direction

Two director concept plates (2026-07-26), uploaded to chat. Source images are not
in-repo — this doc is the persisted spec. Refresh from the originals if available.

## Plate A — STRUCTURE & LAYOUT (the brighter, teal-lit plate)

The read of the whole space, confirming the built layout and refining detail:

- **Central reservoir drum.** A monumental rusted-iron tank: vertical plate courses
  banded by 3–4 horizontal rivet rings, rust weeping down the seams, a square
  porthole/hatch with a small hand-wheel low on the front. Its TOP is a bright
  cyan-white glowing rim band inside a metal railing hoop, enclosing a disc of teal
  water with a central capped collar.
- **Spiral walkways.** Warm brown WOODEN PLANKS laid radially, following the curve,
  with insets of dark metal GRATING between plank runs. Stairs descend on one side.
  The deck coils around the drum, climbing.
- **Glowing water.** Cyan channel-water crosses the deck and runs the outer edge in
  bright troughs; embedded cyan light strips line the deck lips.
- **Doors / sector gates.** Colour-banded doors set into the dark perimeter wall
  (teal, rust-orange, purple bands) — the wordless sector signage.
- **Perimeter wall.** Dark vertical timber-like FINS forming the shaft wall, with
  warm wall-mounted LANTERNS.
- **Portal.** A vertical glowing RING on a wooden/metal stand PLUS a flat circular
  glowing PAD set into the deck beside it. On the branch side, dark beams frame a
  blue-lit pressure area.

## Plate B — AMBIANCE & LIGHTING (the dark, moody plate) — THE MOOD TARGET

Same geometry, dramatically re-lit. This is the grade to hit:

- **Dark, wet, high-contrast.** Deep shadow base; surfaces read WET and reflective,
  catching the coloured light in pools and glints (not the current matte look).
- **The RED / BLUE / PURPLE accent trio is the light** (matches the portal colour law
  and the director's stated palette):
  - **RED** — the wall lanterns on one side throw a warm red pool across deck + wall.
  - **BLUE / CYAN** — the channel water is the pervasive dominant glow; bright,
    saturated, lighting the deck from below and the drum's flank.
  - **PURPLE** — the portal ring + pad glow purple, pooling on the planks around them.
- **The drum rim** is a bright cyan-white band, the brightest thing up top.
- **Neon bloom** on the water/portal/rim; filmic contrast; near-black background.

## Plate C — DETAIL PLATES (5 close-ups, 2026-07-27) — ORGANIC OVERGROWTH

Five detail shots that push the look further and confirm the red/purple/cyan wet mood:

- **The iron is OVERGROWN with organic vasculature.** Vein-like tendrils (dark
  red-brown, faintly lit) climb the drum and the shaft walls in a branching network
  — the biological substrate leaking into the architecture (canon: the NVU substrate
  bleeding nutrients into the iron). Blue/purple **bioluminescent clusters** (mushroom/
  crystal nodes) gather at vein junctions and wall niches.
- **Director's method:** draw the organic detail as TEXTURE for now (not geometry),
  via a **Voronoi-inspired method** — Voronoi/Worley cell EDGES form the branching
  vein network naturally (see blender/skills/building-generation/gen_voronoi_holemesh
  `voronoi_edges`). Generator: blender/textures/gen_vasculature.py → an overlay laid
  on the iron surfaces (drum + walls), with emissive junction nodes for the clusters.
- Detail confirmations: the drum PORTHOLE is an octagonal wheel-mullion window onto
  teal water; the cyan WATER CHANNEL snakes bright through the plank+grate deck as the
  dominant light; alcove SHELTERS glow cyan inside; red lantern accents; the purple
  CURECUMIN portal ring-on-stand + pad over the dark well, garden through the lens.

## PROP AUDIT (director's ruling, 2026-07-27) — props one by one, not "a level with details"

The director compared the plates against the build and called the gap: the level got a
GLOBAL treatment (grade, wet, a vein texture) while the plates are made of INDIVIDUAL
PROPS, each with its own silhouette, materials, and story. Rule going forward — same as
the building showcase method: decompose each plate into props, build each prop as its
own piece against its reference crop, compare THE PROP to THE CROP before placing it.
A texture pass is never the answer to a prop.

Per-prop ledger (plate → prop → verdict):

| # | Prop (plate) | Reference shows | Build has | Verdict |
|---|---|---|---|---|
| 1 | Vein trunk (P3) | THICK 3D organic trunk climbing the drum: bulbous linked segments, side branches, root flare gripping the deck, purple-blue glowing bulb cluster at the foot | flat texture veins on the drum skin | FLAT-TEXTURE-ONLY → build the 3D prop |
| 2 | Biolume cluster (P1/P3/P4) | chunky mushroom-cap + crystal clusters, blue/violet, at wall bases and vein feet — real objects casting light | emissive pixel dots in the vein texture | FLAT-TEXTURE-ONLY → build the prop |
| 3 | Porthole assembly (P3) | octagonal RIVETED frame standing proud, cross-spoke wheel, bright teal WATER window with bubbles | painted-on octagon lines, dark | FLAT-TEXTURE-ONLY → build the assembly |
| 4 | Curecumin portal (P2) | THICK SEGMENTED ornate ring (blocky metal greebles), inner PURPLE neon ring, garden through the lens, mechanical base/stand, concentric-ring pad, side console with purple screen, ball-joint pipes snaking in | thin plain torus reading BLUE + a blue orb lens that hides the view | WRONG (shape + colour) → rebuild as an assembly |
| 5 | Neon crown ring (P1) | continuous bright white-cyan TUBE riding a railing over the drum rim — the brightest single element in the scene | a dashed faint ring of dots | PARTIAL → continuous tube + posts |
| 6 | Drum plate skin (P3) | blue-grey riveted courses, vertical seams, chips, drips | painted at true texel density, seams/portholes/drips | MATCH (keep) |
| 7 | Deck: planks + hex grate (P3/P4) | wood planks with hexagonal/diamond mesh grate insets, radial planks at the drum, worn | planks + grate insets exist; grate weaker than plate | PARTIAL (acceptable; revisit texel) |
| 8 | Wall tracery (P1/P3) | walls FULLY overgrown — vasculature forming ARCHED tracery (ogee/circle frames), dense, 3D depth | sparse star speckles; vein texture only on drum+shaft | FLAT/MISSING → arched tracery pass (wave 3) |
| 9 | Water channels in deck (P1/P4) | irregular organic-edged GLOWING cyan water sunk into the grate floor | neat rectangular strips | PARTIAL → irregular pool edges (wave 3) |
| 10 | Flood water (P5) | foamy TEXTURED cyan-white wash, waterfalls pouring over edges, splash at the door | featureless white slab | FLAT → foam texture + falls (wave 3) |
| 11 | Gate + dot-matrix sign (P4) | red perforated-dot sign panel over the gate, cyan neon strip beneath, torch sconces on posts | rust-dot sign exists, no neon strip/sconces | PARTIAL |
| 12 | Ball-joint pipes (P2) | pipes with blue-metal spherical joints snaking organically | none | MISSING (wave 2, portal dressing) |
| 13 | Red bar lamps over doors (P1/P4) | horizontal red light bars mounted above doorways | red lantern boxes on the deck | PARTIAL |
| 14 | Reservoir centre platform (P1) | small octagonal platform in the drum water + feed pipe | empty water disc | MISSING (wave 3) |
| 15 | Broken-plank pier edges (P2) | radial planks ending jagged/broken over the pit | neat straight edges | MISSING (wave 3) |

Build waves: **wave 1** = props 1, 2, 3, 5 (the drum-face set — recreates plate 3
conditions); **wave 2** = prop 4 + 12 (the portal assembly — hero story prop);
**wave 3** = 8, 9, 10, 11, 13, 14, 15 (environment passes). Each wave ships with a
capture compared against its plate, prop by prop, before it counts.

## Implementation ledger (this level's channels chunk + shared preview grade)

- **Grade (per-chunk lighting profile):** filmic tonemap + glow bloom + darker cool
  ambient for contrast; `get_preview_lighting_profile()` in `wash_relay_chunk.gd`,
  applied by `fragment_preview_sequence._apply_chunk_preview_lighting_profile`
  (extended to honour tonemap/bloom, reset to defaults for other chunks).
- **Rig (authored lights):** `_build_light_rig()` — water = the dominant cyan glow on
  every section, portals cast purple, lanterns lean red on one side + warm at the
  shelters, gates keep their palette hues, a bright cyan crown rim.
- **Wet surfaces:** lower roughness + specular on the deck (channels.glb tiled_mat)
  and the drum/dressing (paintlib), plus the runtime tinted-tile deck — so the
  coloured lights pool and glint like Plate B.
