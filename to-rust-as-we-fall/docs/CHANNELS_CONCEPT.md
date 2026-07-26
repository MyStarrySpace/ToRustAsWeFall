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
