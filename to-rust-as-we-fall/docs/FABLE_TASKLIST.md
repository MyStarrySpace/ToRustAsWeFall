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

**Gaps vs the plate (Fable pass):**
- **Organic junctions.** The plate's frame struts *melt* together at the crossings (Gaudí-ish pinched
  blobs, concave sides). Opus's version is a cleaner geometric lattice — the "round toward the vertex"
  junction is approximated, not sculpted. Fable: sculpt the pinched, load-bearing-looking junctions.
- **Window variation.** Plate windows differ — some lit, some dark, blinds at angles, planter sills,
  little balconies. Opus's are uniform warm panes. Fable: per-window variation + sills/blinds.
- **Cell aspect + irregularity.** Plate cells are slightly portrait and subtly *irregular* (hand-made,
  not a perfect grid). Opus's grid is perfectly regular. Fable: gentle per-cell jitter.
- **Frame profile.** Plate frames have moulded/bevelled cross-sections catching light; Opus's frame is
  a flat raised band. Fable: a real moulding profile.
- **Decay asymmetry.** Plate has a pristine face and a rusted, torn, vine-tangled face. Not built at
  all yet — a decay pass (rust streaks, broken cells, exposed structure, vines).

## Lattice 2 — pipes  *(built by Opus)*
**Opus built:** SeededRng edge-descent tubes (`LatticeBuilder.pipes`). Density → pipe count; each pipe
walks down from the top with curve-sampled steps + a probability of a diagonal jog; occasionally a
shorter follower runs alongside. Works on box faces AND the cylinder (drapes both). Low-poly swept
tubes. On the PPP + Honeycomb.
**Gaps vs the plate (Fable pass):**
- **No sag.** Pipes are straight polylines; the plates have catenary droop between anchors.
- **No fittings.** Couplings, valves, elbow joints, wall brackets, drip funnels — none. The plate pipes
  read as plumbing *because* of the hardware.
- **No staining / patina.** Rust runs, verdigris, drip stains under the pipes.
- **Single gauge.** One radius + one follower; the plates bundle varied-diameter runs.
- Pipes run down face centres, not hugging the corner edges / recesses like the reference.

## Lattice 3 — tracery (Beacon Hill pointed-arch window wall)  *(built by Opus)*
**Design (confirmed):** mullioned **glass curtain behind + stone tracery ribs in front** (two layers,
not holes in a solid wall). Pointed-arch (lancet) openings in vertical columns, wrapped on the drum.
**Opus built:** `LatticeBuilder.tracery` — lancet rib rings + lit glass panes wrapped on the Beacon
Hill cylinder. Tall pointed slots (near-parallel sides tapering to cusps), 2 rows × 12 cols, ribs
between, warm panes behind.
**Gaps vs the plate (Fable pass):**
- **Solid panes, no mullions.** The plate windows are a fine grid of tiny lit panes; Opus's are one
  flat emissive pane per opening.
- **Straight ribs.** The plate ribs *branch, interlace, and whiplash* (Art-Nouveau/Gothic tracery);
  Opus's are simple constant-width lancet rings. This is the biggest visual gap.
- **No hierarchy.** Uniform lancets; the plate has a big central lancet with smaller flankers + little
  vertical slots between, and a **crown of roundels / clerestory ring** at the top.
- **Bell taper.** Beacon Hill's base is a straight cylinder; the plate is a bell/beehive (wider base,
  domed top). A base-shape refinement.
- Rib cross-section is a flat raised band, not a moulded profile.

---

## Build pipeline (the ordered steps, per the director)
1. **Base shapes** — DONE (cylinder / box per building).
2. **Lattice** — DONE v1 (honeyframe, pipes, tracery). Fidelity gaps above.
3. **Entrances** — main + side entrances (e.g. maintenance, enforcement vestibule). The Beacon Hill
   plate literally has a grand "Reading Room" main door + a teal "Enforcement Vestibule — Authorized
   Access Only" side door.
4. **Signs** — building nameplates + notices (Beacon Hill has the carved name cartouche + a lit
   "READING ROOM OPENS / ONE DAY ONLY" notice).
5. **Base / foundation** — the plinth the building sits on: elevated-from-ground step, greenery
   (planters, vines), cobble apron.
6. **Voronoi organic decorations** — a decoration pass: consider HALF the object (decor mirrored),
   scatter a few "focal points", draw Voronoi cells, then merge cells — merging harder the further from
   a focal point. Meant to build on the earlier Fable/Blender Voronoi code (`gen_voronoi_holemesh` /
   `gen_blob_mass`). **STATUS: that Blender code is NOT in this checkout** — `blender/` has no `.py`
   files here and it's gitignored, so it isn't recoverable from git. Options: restore the Blender
   sources, or reconstruct the algorithm natively in `LatticeBuilder` (GDScript) from the spec above.

## Cross-cutting Fable tasks
- **Texture density variation** — the grime shader varies rust/wear via world-noise, but the plates
  have *authored* grime (streaks under windows, pooling at the base, patina in the recesses). Fable:
  author-directed weathering masks, not just noise.
- **Silhouette richness** — plates have crowns, cupolas, finials, parapets, awnings, signage. Base
  shapes are bare. Fable: the crown/roof/signage pass per district.
- **The other 8 districts** — only PPP + Honeycomb exist. Open Files, Hypelines, Greenfields,
  Ancourage, Beacon Hill, Bulwark Wharf, Cleanstreets, Zone-3 still need base + lattice (decomposition
  recipes for several are in the `hero_building_showcase` memory / earlier decomposition JSON).
- **LOD / impostor** — showcase heroes are heavy (honeyframe alone ~28k verts). Real district use needs
  a near/far LOD or impostor pass before these ship into a walkable level.
