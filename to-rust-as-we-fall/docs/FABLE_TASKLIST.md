# Fable Task List — procgen geometry pass

Backlog for **Claude Fable**, who LEADS the district-architecture procedural generation. The hard part
is Fable's: boolean/CSG/blend, overlap/collision resolution, organic/curved surface fitting, and
watertight mesh topology. Opus's swept-tube / tiled approximations leak at grazing angles and read as
"sausages smashed together" — they are placeholders and armatures, not the target.

**Fable delegates DOWN to Opus.** Anything Fable finds simple and mechanical it can hand to Opus to do
later — per-pane window LIGHT (vertex-colour brightness/tint/off), signage text + placement, seed
plumbing, parametric knob layout, and all the wiring (showcase chunk, PREVIEW registry, tests, RNG
lint, hygiene). That keeps Fable's effort on the geometry. Items Opus has already taken are marked
**DONE** per section; treat them as done-unless-noted, and reclaim any you'd rather redo.

Reference plates: `reference-images/architecture/*.png`. Compare the live showcase
(`--preview=architecture_showcase`) against the plate before and after.

## Ground rules
- **Bottom-up + parametric:** base shape → lattice on edges/faces. Every knob a `[PARAMETER]`; every
  sample through `SeededRng` (determinism law + the RNG lint).
- **Match the plate, not the previous capture** — decompose whole → parts → primitives, rebuild.
- **Low-poly geometry, detail in the (pixel-art) texture.**
- **UNIFY, don't pile.** The plates' lattices are ONE fused organic surface (smooth-union / metaball
  merge, the way the Blender pipeline did it), never overlapping tubes. This is the single biggest
  quality lever across EVERY lattice — see **Organic merge** below.

---

## Organic merge — the "sausages" fix (highest-leverage, cross-lattice)
The Godot lattices sweep tubes and just OVERLAP them, so junctions read as separate sausages; the
Blender pipeline fused parts into one organic surface. **Investigation done (2026-07-09) — the
capability already exists in-engine.**

- **What Blender did = METABALLS** (`blender/skills/building-generation/gen_blob_mass.py`,
  `build_blob_mass`): one metaball element per sphere, `mb.resolution ≈ 0.30`, polygonised into ONE
  mesh (`new_from_object`). That's a smooth-min field union — overlapping spheres melt into one mass.
  (Cheaper parity variants also in the Blender code: `gen_voronoi_holemesh.build_holemesh` builds a
  WELDED shared-vertex web + `wireframe`/`solidify` with a `merge`/`merge_start` radial falloff;
  `gen_building.py` uses `remove_doubles` weld before `solidify`. No booleans/voxel-remesh anywhere.)
- **Godot equivalent already shipped:** `scripts/generation/sdf_mesher.gd` — `SdfMesher.build(prims,
  cell, color) -> {mesh, verts, tris, aabb}`. Prims carry a smooth-min blend radius **`k`**:
  `{"type":"capsule","a":Vec3,"b":Vec3,"r1","r2","k"}` (+ sphere/ellipsoid/box). Polynomial smooth-min
  + marching TETRAHEDRA + gradient normals → a clean closed manifold with fused junctions (exactly the
  metaball result). `CreatureGrammar._cap/_ell/_sph` shows the emit pattern. `cell` = voxel size
  (0.04–0.09 fine, 0.12 coarse); big `k` melts, small `k` stays sharp.
- **The sausages are specifically the SWEPT TUBES** — `lattice_builder._sweep_tube` (pipes) and
  `_sweep_rib` (tracery). The honeyframe/tracery FRAME RINGS already tile via shared cell rects (fine).
- **Recipe:** for each consecutive rib path-pair emit a `capsule` prim (`a,b` = the two points, `r =
  rib_radius`, `k ≈ rib_radius`); union a region's capsules and `SdfMesher.build(...)`. The smooth-min
  fuses crossings into organic tracery. Keep the GLASS on the SurfaceTool path (SDF carries no
  vertex-colour / two layers) — only the RIBS go through the SDF.
- **Risks:** (1) PERF — the tet pass scans the whole union AABB / cell³, so field the ribs **PER-BAY**
  (small AABB), never the whole drum at once (a full-facade field at cell 0.04 ≈ 12M voxels). (2) It
  produces free-floating fused tubes, not surface mouldings — either union a local wall slab into the
  field or let the ribs float proud. (3) `cell ≤ rib_radius` and `k ≈ rib_radius` or thin ribs facet /
  pinch off. Fallback if per-bay SDF is still too heavy: the welded shared-vertex graph (Blender
  technique 2/3) — dedupe path endpoints + weld coincident verts — welded-not-melted, but no sausages.

Apply to honeyframe (S_A/S_B junctions), tracery (the whole rib network), and pipe couplings — build
the capsule→SDF path once, reuse everywhere.

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

**Director's spec — the ALGORITHM given (verbatim), before Opus improvised its own tiling.** This is
the vertex-corner-cut construction the honeyframe was supposed to be (the setting "used on Welcombe").
It operates on the **subdivided box** (subdivide each face into a grid first — confirmed), per grid
vertex:
1. Get the vertices of the (subdivided) mesh.
2. From each vertex, find the edges going out in each direction.
3. Along each such edge, choose a point at **[PARAMETER, capped at 50%]** percent of the edge length
   *away from the vertex*. The short segments joining these points around a vertex form the set **S_A**.
4. Connect those points (→ the S_A corner-cut edges, one small cut across each corner near the vertex).
5. Then connect the points BETWEEN adjacent new points *along the edges* — the longer spans — to form
   the **S_B** edges (the straight runs between corner-cuts).
6. **Round the S_A edges so the curves cut TOWARD the vertex points** (concave, pinching in toward
   each grid vertex — this is what makes the junctions read organic / load-bearing, not a plain grid).

Net: every grid cell becomes a rounded opening; the frame = S_A (rounded corner-cuts) + S_B (straight
spans); the S_A rounding toward the vertices IS the melting-junction look. Opus instead did
"rounded-rect window inset per cell", which fakes the cells but NOT the S_A-toward-vertex pinch — so
the junctions read geometric, not organic. Build to THIS when the honeyframe is redone.

**Opus built (the improvisation to replace):** subdivide each box face into a ~4×6 grid; each cell → a
rounded-rect window in a raised constant-width cream frame + a warm lit pane. Reads as a honeycomb
facade, but the junction is the cell-inset fan, not the S_A concave cut toward the vertex.

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

**DONE in Godot (was wrongly deferred):** varied per-pipe gauge · a MIX of single + bundled runs
(`single_frac` — not every run is a double) · edge-hugging runs · catenary sag · banded couplings ·
wall standoff brackets · rust/verdigris patina (per-ring vertex colour). Sausage junctions at pipe
couplings should route through the **Organic merge** like the tracery ribs.

## Lattice 3 — tracery (Beacon Hill)  → DEFERRED TO FABLE (director, 2026-07-09)
**Opus tried and it doesn't land — hand the whole tracery to Fable.** Opus built three attempts (SDF
metaball fuse; then the algorithm-3 half-round junction merge which reads crisp at a front elevation
but breaks up into disconnected shards at gameplay camera angles). None reads like the plate in-game.
The current code (`LatticeBuilder.tracery`, `rib_merge:"junction"` default) is a PLACEHOLDER only —
Fable should rebuild the tracery from the decomposition below, not patch the Opus armature. The
entrances now RESERVE their bays (the tracery skips a bay per door via the `reserved` override), so
Fable can assume clear door space. Keep the `reserved` param when rebuilding.

**Design:** mullioned **glass curtain behind + stone tracery ribs in front** (two layers), on a
**bell/beehive** tower (wide base, domed top) — one continuous flowing Art-Nouveau rib NETWORK.

**Corrected decomposition (from the close-up plate, director 2026-07-09) — per bay, top → bottom:**
1. **Domed crown band** — a ring of small arched clerestory windows around the domed top; rooftop
   planters above the parapet.
2. **Nested double arch** — each tall window is capped by its OWN pointed arch, and a SECOND, LARGER
   arch nests above that one.
3. **Two commas in the tympanum** — between the inner and outer arch sit TWO comma / half-yin-yang
   shapes (mouchettes), mirror images facing each other.
4. **Tall gridded LARGE window** — the dominant element: a fine grid of small lit panes filling the bay.
5. **Flanking vesica lancets** — tall pointed OVALS (pointed at both ends) either side of the large
   window, each holding a thin lit almond light; in the plate they step DOWN and OUT in size.
6. **Mullion lines** down the bay boundaries; near the base they splay into ROOT/VINE tendrils around
   the doors and the "BEACON HILL / READING ROOM" plaque.

**Opus built the ARMATURE** (`LatticeBuilder.tracery`, commit f023862): all of 1–6 present, placed,
deterministic, tested. But the ribs are swept tubes that OVERLAP = the "sausages" read, and the bell
taper, the root-splay, and the interlacing are missing. **Fable:**
- Run the whole rib network through the **Organic merge** (top of doc) so it fuses into one surface —
  this is what will make it finally read like the plate.
- Add the **bell/beehive taper** (wrap the ribs flush onto a varying radius) and the **root splay** at
  the base; **step** the flanking vesicas down/out; interlace the ribs where the plate does.
- Per-pane window light + the seed plumbing are already Opus's (keep).

---

## Districts — bases established (Opus); lattices + complex massing for Fable
All 10 districts now exist in the showcase (`BaseShapeBuilder.BUILDINGS`) with a base primitive, so
Fable starts from a standing set, not a blank. Per district — what's built vs what's Fable's:

### The Open Files Initiative — base BUILT (composite)
**Shape (director's spec):** rectangular prisms combined with other rectangular prisms, each capped by
a TRIANGULAR prism that is an EQUILATERAL triangle, the slope connecting one prism up to the next. Opus
built this (`_open_files_mesh`) as a radial ring of tall rect-prism FINS around a core, each gabled
with an equilateral triangular prism, stepped in height (the jagged server-rack crown).
**Lattice (director's spec) → Fable:** like the pipes, but instead of pipes down the edges, take the
FACES and EXTRUDE them out by a [PARAMETER] depth — the recessed server-rack CHANNELS between the fins
(+ the emissive rack LEDs). Route junctions through the Organic merge.

### Greenfields Collective — base BUILT (box placeholder); BALCONY lattice → Fable
**Shape:** a rounded barrel block (~4 storeys); Opus placed a plain box, the rounded corners are Fable.
**Balcony lattice (director's spec) → Fable** — wrapping balconies constructed from the edges:
1. Mark every OTHER vertex.
2. Subdivide them horizontally, then push the two edges NEAREST the marked vertex OUT away from the
   building (along the building's normal).
3. Find the CENTRE of those two extruded edges, move back slightly, then drop DOWN to the lower balcony
   — that's the beam START point.
4. Build the BEAM up until a point set by the indicated curve [PARAMETER].
5. Draw the CURVE from there to the balcony.
6. Connect the balcony curves (the wrapping rail).
Organic curved beamwork = the Organic-merge / SDF class. Fable owns it.

### The others — base placeholders BUILT, real massing + lattice → Fable
- **The Hypelines** — placeholder drum. Real: a STACKED-BULB (onion/blob) tower with a SPLIT base
  (splayed feet) + radiating tube VIADUCTS. Blob-stack + split base = the merged/SDF massing class.
- **Ancourage** — placeholder squat drum. Real: a low DOME cap + heavy pipe DRAINAGE splaying from the
  base (ties into the Plumbing mains) + vent stacks.
- **Bulwark Wharf** — placeholder box gatehouse. Real: corner TURRETS, ROSE (circular tracery) windows,
  and the huge draped membrane BARRIER wall flanking it.
- **The Cleanstreets Initiative** — placeholder wide low box. Real: an open CANOPY roof on splayed
  tree/mushroom COLUMNS (a horizontal pavilion), baffles + deterrent spikes below.
- **Zone-3 Eroded Ruin** — placeholder faceted box. Real: the amyloid-DRIP decay melt (Organic-merge
  class) over a faceted 2–3 storey block + a lower porch.

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
- **All 10 districts now have a base** (see the Districts section above) — Fable owns their lattices +
  the complex massing flagged there, no longer the base primitives.
- **LOD / impostor** — showcase heroes are heavy (honeyframe ~28k verts; the SDF-fused tracery ~137k).
  Real district use needs a near/far LOD or impostor pass before these ship into a walkable level.
