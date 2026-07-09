# Fable Task List — procgen geometry pass

Backlog for **Claude Fable**. The district-architecture procedural generation is being built
bottom-up. The split is by DIFFICULTY OF THE MATH, not by pipeline stage:

> **Fable owns the complex math + geometry. Opus owns the simple calculations.**

Anything that is boolean/CSG/blend, collision/overlap resolution, organic/curved surface fitting, or
watertight mesh topology goes to **Fable** — Opus keeps botching those (holes, parts poking through,
straight where the plate whiplashes). Opus keeps the cheap parametric bits: primitive placement,
per-knob layout, per-pane window light, signage text/placement, and all the wiring
(showcase/registry/tests/determinism). Opus should NOT keep grinding the hard-geometry items below —
log the gap and leave it for Fable rather than shipping a leaky approximation.

Reference plates: `reference-images/architecture/*.png`. Compare the live showcase
(`--preview=architecture_showcase`) against the plate before and after.

---

## Division of labor

**Opus (simple calculations — do these now):**
- Primitive base shapes (a cylinder, a box) and their parametric knobs.
- Layout math: spacing, per-cell grid subdivision indices, edge sampling, seed plumbing.
- Per-pane window LIGHT (vertex-colour brightness/tint/off lookup) — pure data, no geometry.
- Signage: text content + placement (Label3D / plaque transform).
- All wiring: showcase chunk, PREVIEW registry, tests, RNG lint, hygiene.

**Fable (complex math + geometry — LOG, don't grind in Opus):**
- **All the lattices** (honeyframe, pipes, tracery). Not just painterly fidelity — the GEOMETRY
  itself is wrong: parts show through, shells still leak, junctions are straight where the plate
  branches/interlaces/whiplashes. The organic surface-fit + watertight topology is Fable's.
- **Overlap / collision resolution** — keep elements from intersecting each other or the wall, and
  clip/remove the ones that do (pipes crossing windows, an entrance sitting over the bottom windows,
  decor punching through the lattice). Needs real occupancy/collision math, not eyeballed offsets.
- **Complex base shapes** — a base that starts as a cylinder then MERGES with other shapes at the
  bottom (the PPP's lobed foot), or a SPLIT-BASE structure (the Hypelines). Boolean/blend/SDF-union
  massing, not a single lathe/box.
- **Roads / lines cutting through buildings** — negative-space carving where a road or line optionally
  slices a building. Boolean subtraction against the massing.
- **Voronoi organic decorations** — the mirror-half + focal-point merge pass (see step 6 below).
- **LOD / impostor** — near/far decimation once the heroes ship into a walkable level.

---

## Ground rules (keep, whoever builds)
- **Bottom-up + parametric:** base shape → lattice elements layered on edges/faces. Every knob a
  `[PARAMETER]`; every sample through `SeededRng` (determinism law + the RNG lint).
- **Match the plate, not the previous capture** (see the recursive-decomposition memory). Look at the
  actual reference image, decompose whole → parts → primitives, rebuild.
- **Low-poly geometry, detail in the (pixel-art) texture.** Don't over-model what a texture can carry.
- **Watertight or it's Fable's.** If a mesh leaks (holes, see-through at grazing angles, self-overlap),
  that's the complex-topology signal — hand it to Fable, don't patch it in Opus.

---

## Base shapes — simple ones DONE (Opus); MERGED / SPLIT bases → Fable
**Opus built (simple, fine):** PPP = squat cylinder, Honeycomb = tall box, Beacon Hill = cylinder.
Proportions verified against the plates. A single lathe or box is Opus's to keep.

**Fable (complex massing — boolean/blend, don't approximate in Opus):**
- **Merged base** — the PPP is not a plain cylinder: the drum MERGES with a wider lobed foot at the
  bottom (the plate's dominant lobed base). That's an SDF-union / blend of the drum with base masses,
  not a taller cylinder. Beacon Hill's bell/beehive taper (wider base, domed top) is the same class.
- **Split base** — the Hypelines' structure splits at the base (two feet / a straddle). Needs the
  massing to branch, not a single primitive.
- Both feed everything downstream (a lattice must wrap the MERGED surface, an entrance must sit on the
  real foot), so these are the highest-leverage Fable base tasks.

## Lattice 1 — honeyframe (Honeycomb facade)
**Opus built:** subdivide each box face into a ~4×6 grid; each cell → a rounded-rect window in a
raised constant-width cream frame + a warm lit pane. Reads as a honeycomb facade.

**Gaps vs the plate — REMAINING (Fable):**
- **GEOMETRY (not just fidelity).** The lattice still shows parts through the wall / through itself at
  grazing angles and doesn't sit watertight on the box. The correct topology is Fable's — Opus should
  stop patching winding/caps here.
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
- **GEOMETRY.** Pipes cross windows / clip the wall (no overlap resolution) and still show through at
  some angles. Routing them AROUND the openings (the overlap-resolution task) is Fable's.
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
- **GEOMETRY.** The ribs still show through the drum / each other at grazing angles and the wrap isn't
  watertight. Correct topology + the curved-surface fit is Fable's.
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
1. **Base shapes** — simple ones DONE (cylinder / box). MERGED (PPP lobed foot) + SPLIT (Hypelines)
   bases → Fable (see Base shapes + Division of labor above).
2. **Lattice** — Opus placed v1 (honeyframe, pipes, tracery), but the GEOMETRY leaks (parts show
   through, not watertight) → the correct organic topology is Fable's, not just the painterly fidelity.
3. **Entrances** — DONE v1 (`LatticeBuilder.entrances`): grand main portal (jambs/lintel/recessed
   doors/canopy/steps) + a teal enforcement side door, on box + drum. Fable-grade remaining: a true
   ARCHED head (currently rectangular), lamps/sconces flanking the door, and — **this is the
   overlap-resolution task** — carving a base zone in the facade so the door isn't sitting over the
   bottom windows (the portal currently projects proud of them; needs real occupancy math, → Fable).
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
- **Overlap / collision resolution** — the load-bearing one. Elements are placed independently and
  intersect (pipes over windows, the entrance over the bottom windows, decor through the lattice, a
  lattice through the wall). Fable: real occupancy/collision math that either routes elements AROUND
  each other or clips/removes the overlapped part — not eyeballed per-element offsets. Every other
  geometry task depends on this reading clean.
- **Roads / lines through buildings** — a road or line may optionally cut through a building; carve the
  negative space (boolean subtraction against the massing) so the cut reads, rather than clipping.
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
