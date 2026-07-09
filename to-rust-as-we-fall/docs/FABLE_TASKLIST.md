# Fable Task List — procgen fidelity pass

Backlog for **Claude Fable**. The district-architecture procedural generation (base shapes → lattice
elements) is being built bottom-up by Opus. Opus gets the structure and parameters right, but the
painterly, organic fidelity of the reference plates (`reference-images/architecture/*.png`) is where
Fable is expected to outrun it. **When Fable is back: revisit each item below and, where Opus fell
short of the plate, remake the generator closer to the reference.**

How to read this: each element lists what Opus built, then the concrete gaps vs the plate. A gap is a
Fable task. Compare the live showcase (`--preview=architecture_showcase`) against the plate before and
after.

---

## Ground rules (keep, whoever builds)
- **Bottom-up + parametric:** base shape → lattice elements layered on edges/faces. Every knob a
  `[PARAMETER]`; every sample through `SeededRng` (determinism law + the RNG lint).
- **Match the plate, not the previous capture** (see the recursive-decomposition memory). Look at the
  actual reference image, decompose whole → parts → primitives, rebuild.
- **Low-poly geometry, detail in the (pixel-art) texture.** Don't over-model what a texture can carry.

---

## Base shapes — DONE (Opus), likely fine
PPP = squat cylinder, Honeycomb = tall box. Proportions verified against the plates. No known gap.

## Lattice 1 — honeyframe (Honeycomb facade)
**Opus built:** subdivide each box face into a ~4×6 grid; each cell → a rounded-rect window in a
raised constant-width cream frame + a warm lit pane. Reads as a honeycomb facade.

**Gaps vs the plate — REMAINING (Fable):**
- **Organic junctions.** The plate's frame struts *melt* together at the crossings (Gaudí-ish pinched
  blobs, concave sides). Opus's is a cleaner geometric lattice — the "round toward the vertex" junction
  is approximated, not sculpted. Fable: sculpt the pinched, load-bearing-looking junctions.
- **Decay asymmetry.** Plate has a pristine face and a rusted, torn, vine-tangled face. Fable: a decay
  pass (rust streaks, broken cells, exposed structure, vines) — the painterly torn-open flank.
- **Window furniture** (geometry, not light): physical blinds at angles, planter sills, little balconies.

**DONE in Godot (was wrongly deferred):** per-pane window LIGHT variation (brightness/tint/off,
`window_panes` shader) · portrait cells + per-cell jitter (`cell_aspect`, `jitter`) · bevelled frame
moulding (`bevel`) · cornice + parapet + rooftop vent + stepped plinth silhouette.

## Lattice 2 — pipes  *(built by Opus)*
**Opus built:** SeededRng edge-descent tubes (`LatticeBuilder.pipes`). Density → pipe count; each pipe
walks down from the top with curve-sampled steps + a probability of a diagonal jog; occasionally a
shorter follower runs alongside. Works on box faces AND the cylinder (drapes both). Low-poly swept
tubes. On the PPP + Honeycomb.
**Gaps vs the plate — REMAINING (Fable):**
- **Spoked valve wheels** (rim + hub + radial spokes) where pipes meet the base — medium geometry.
- **Wall drip decals** — rust stains running onto the WALL below a pipe (a projected/decal pass, not
  the pipe mesh itself).

**DONE in Godot (was wrongly deferred):** varied per-pipe gauge + mixed-gauge BUNDLES · edge-hugging
runs · catenary sag · banded couplings · wall standoff brackets · rust/verdigris patina (per-ring
vertex colour).

## Lattice 3 — tracery (Beacon Hill pointed-arch window wall)  *(built by Opus)*
**Design (confirmed):** mullioned **glass curtain behind + stone tracery ribs in front** (two layers,
not holes in a solid wall). Pointed-arch (lancet) openings in vertical columns, wrapped on the drum.
**Opus built:** `LatticeBuilder.tracery` — lancet rib rings + lit glass panes wrapped on the Beacon
Hill cylinder. Tall pointed slots (near-parallel sides tapering to cusps), 2 rows × 12 cols, ribs
between, warm panes behind.
**Gaps vs the plate — REMAINING (Fable):**
- **Straight ribs.** The plate ribs *branch, interlace, and whiplash* (Art-Nouveau/Gothic tracery);
  Opus's are constant-width lancet rings. This is the biggest remaining visual gap.
- **Mullion sub-grid.** Each lancet is one pane; the plate is a fine grid of tiny lit panes (needs the
  per-row taper-clipped sub-grid — medium, and it multiplies vert count → pair with LOD).
- **Bell/beehive taper.** The drum is a straight cylinder; the plate is a bell (wider base, domed top).
  The base lathe is simple, but WRAPPING the tracery flush onto a varying radius is the medium part.

**DONE in Godot (was wrongly deferred):** big-central width hierarchy (`col_pattern`/`bays`) · crown of
roundels / clerestory ring (`clerestory`) · moulded rib cross-section (`bevel`) · per-pane window light.

---

## Build pipeline (the ordered steps, per the director)
1. **Base shapes** — DONE (cylinder / box per building).
2. **Lattice** — DONE v1 (honeyframe, pipes, tracery) + the enrichment pass. Fidelity gaps above.
3. **Entrances** — DONE v1 (`LatticeBuilder.entrances`): grand main portal (jambs/lintel/recessed
   doors/canopy/steps) + a teal enforcement side door, on box + drum. Fable-grade remaining: a true
   ARCHED head (currently rectangular), lamps/sconces flanking the door, and carving a base zone in the
   facade so the door isn't over the bottom windows (currently the portal projects proud of them).
4. **Signs** — DONE v1: a billboarded `Label3D` nameplate (real readable text) over each main door.
   Remaining: the carved-plaque geometry + secondary NOTICE signs (e.g. "READING ROOM OPENS / ONE DAY
   ONLY") — text as a baked pixel-art texture on a plaque if we don't want live Label3D everywhere.
5. **Base / foundation** — the stepped PLINTH is done (in the honeyframe crown pass + the door steps).
   Remaining: greenery (planters, vines, the Beacon Hill corner shrubs) + a cobble apron.
6. **Voronoi organic decorations** — a decoration pass: consider HALF the object (decor mirrored),
   scatter a few "focal points", draw Voronoi cells, then merge cells — merging harder the further from
   a focal point. Builds on the existing Fable/Blender Voronoi code, which IS present (it's under the
   gitignored `blender/`, so ripgrep/Glob skip it — use `find`):
   `blender/skills/building-generation/gen_voronoi_holemesh.py` (Voronoi web + holes; `build_holemesh`
   already has a `merge`/`merge_start` falloff — currently RADIAL from centre; generalize to N focal
   points) and `gen_blob_mass.py`. Both ship near(3D)+far(impostor) LOD from the same params. Open
   question: author the decor in Blender and export, or port the Voronoi merge natively to GDScript.

## Cross-cutting Fable tasks
- **Texture density variation** — the grime shader varies rust/wear via world-noise, but the plates
  have *authored* grime (streaks under windows, pooling at the base, patina in the recesses). Fable:
  author-directed weathering masks, not just noise.
- **Silhouette richness** — the Honeycomb now has a cornice + parapet + plinth, and Beacon Hill a
  roundel clerestory (both DONE in Godot). Still Fable-grade: cupolas, finials, awnings, and the PPP's
  onion dome + lantern (curved/organic roof forms), plus per-district signage (the entrances/signs
  pipeline steps).
- **The other 8 districts** — only PPP + Honeycomb exist. Open Files, Hypelines, Greenfields,
  Ancourage, Beacon Hill, Bulwark Wharf, Cleanstreets, Zone-3 still need base + lattice (decomposition
  recipes for several are in the `hero_building_showcase` memory / earlier decomposition JSON).
- **LOD / impostor** — showcase heroes are heavy (honeyframe alone ~28k verts). Real district use needs
  a near/far LOD or impostor pass before these ship into a walkable level.
