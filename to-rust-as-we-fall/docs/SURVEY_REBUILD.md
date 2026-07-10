# SURVEY REBUILD — redo every non-director construction, measure-first

The director's method (2026-07-10, verbatim spirit): measure like an architect FIRST — a datum
grid/survey — then construct every pass from those measurements; ground new parts in what is already
generated so topology FLOWS; reconcile lattice-vs-decoration at the MEASUREMENT stage (restructure
the lattice around reserved shapes, or build the shape into the base) — never "see a shape, slap a
representative primitive." The primitive-collage passes produced floating pipes, lattice/decoration
collisions, wedge holes, and off-scale windows; all of it is to be re-derived.

## What is DIRECTOR-DESIGNED (keep the design; only re-express its measurements)
- The recursive connected awnings algorithm (geometry lab algo 2 → open_files massing).
- The LatticeGraph junction engine + tracery / honeyframe S_A-S_B / voronoi (voronoi→focal→mirror)
  recipes, and the rackwork faces-extrude spec.
- The red-shell hole test, the chroma/player-contract testing system, the detail SHEETS
  (`reference-images/architecture/sheets/*.png`) as the asset vocabulary.

## What was SLAPPED and must be re-derived survey-first
All eight review composites (plumbing_lobed, canopy_piers, ancourage_domes, beacon_domed,
hypelines_mound, greenfields_stack, bulwark_towers, zone3_split), the draped-pipes pass, the
universal white-stone entrance assemblies, lattice FIELD sizing (tracery pane grids, honeyframe
cells vs storeys, rack drawer strata), hash-scattered gameplay anchors, ledge treatments.

---

## THE PROMPT (paste to start each rebuild session)

> Work on the SURVEY REBUILD (docs/SURVEY_REBUILD.md). Method is non-negotiable, in this order:
> **(1) DECOMPOSE** the reference plate recursively (whole → parts → sub-parts, proportions as
> ratios, palette; reference-images/architecture/<kind>.png — read the image, not stale docs).
> **(2) SURVEY** — write the building's measured drawing AS DATA before any mesh: datum heights
> (plinth / storeys / eave / crown), the plan axis-and-bay grid, the silhouette profile r(y) or
> w(y), and RESERVATIONS for every planned part — openings, decorations, lattice fields, sockets.
> Every number in the survey traces to a plate ratio. **(3) RECONCILE** at the survey: if two parts
> want the same wall, restructure the lattice field around the reservation or fold the part into
> the base — collisions must be impossible before meshing. **(4) CONSTRUCT** every pass (massing,
> lattice, openings, pipes, details, anchors) FROM the survey — one coordinate authority; grow new
> geometry from existing construction points (the awnings way: each part chains off the previous
> part's edges) — prefer one lofted/lathed profile over intersecting primitives. **(5) VERIFY**
> like a player and a surveyor: windowed captures compared against the PLATE (not the previous
> capture), red-shell scan for the massing, survey.validate() headless (every part inside a
> reservation, zero unreserved overlaps), suites green, commit per building.
> Constraints: palette = dark desaturated verdigris + rust, authored grime; terminal green #5ce87f
> is the only standard emissive (amber only where a plate demands it). Detail parts come from the
> sheets vocabulary by their catalog names. Canonical names from reference-docs. Known traps:
> SurfaceTool.generate_normals() after append_from DROPS earlier surfaces; --script mode compiles
> Variant-inference `:=` as errors; winding comes from construction frames, never 3D dot-tests;
> pixel-verify anything visual (flags lie). Requirements per building = docs/BUILDING_REVIEW.md
> alterations, but re-derived through the survey, never bolted on.

---

## TASK LIST (ordered; one commit per numbered item minimum)

**0. Survey infrastructure** (`scripts/generation/building_survey.gd`)
   - `BuildingSurvey.from_spec(spec, plate_ratios)`: datums {plinth, storey[], eave, crown},
     plan grid (axes, bays, corner chamfers), silhouette profile (absorbs massing_radius_at),
     reservations (typed rects/arcs: opening / lattice_field / decoration / socket), socket
     registry (doors, bridges, lanes, weak points, balcony slots — replaces hash scatter).
   - `validate()`: loud strings for unreserved overlaps, parts off-datum, sockets off-surface.
   - Headless test `--test-building-survey` (in --test-all): validate() clean for every BUILDINGS
     entry + reservation-overlap red case.
   - Rewire existing consumers (pipes r_at, anchors, entrances) to read the survey.

**1. Per-building re-derivation** (worst review scores first; each: survey → construct → capture
    vs plate → red-shell → commit)
   1. plumbing_power — lobed skirt as ONE lofted lathe profile (lobe count/amplitude from plate),
      drum, onion dome as profile continuation; SPIRAL FLUME as a survey helix (trough + railing
      datums, green water emissive); capillary-slit windows + handwheel cluster as reservations;
      entry-hood idiom.
   2. hypelines — one continuous three-tier lathe profile; arms as WALKABLE LANES: deck geometry
      with width/rail datums, grid cells + inter-level links registered so the level layer docks
      them (extends the existing bridge-socket table).
   3. cleanstreets — pavilion surveyed: pier grid datums, canopy slab + horn profile as one loft,
      dais/steps, divider-fin lanes, toll-gate side portal; honeycomb corner perforations reserved.
   4. greenfields — storey datums drive FOUR wavy slab rings (one wave function shared by slabs
      and wall undulation); the declared-but-missing `balconies` lattice built on those datums;
      teal-lit roof terrace (projections sheet: planted terrace).
   5. ancourage — dome cluster lofted from the eave ring (no intersecting spheres); rose apertures
      + louver vent reserved into the dome; vent flare-stack; root-fan ground pipes on the profile.
   6. beacon_hill — FIVE colossal arch-bay reservations (0.28–0.76 H); tracery restructured around
      them; pane grid storey-scaled inside bays only (fixes the off-scale window rectangles);
      dome shoulder as drum-profile continuation.
   7. bulwark_wharf — towers grown from the box corners (shared edges, not embedded cylinders);
      framed membrane panel + ONE rose aperture (0.28 W) as the face reservation; barrier wall.
   8. zone3 — split massing from plan datums; cornice as profile feature; slat-canopy porch row.
   9. honeycomb — facade bay grid = the tracery cell grid EXACTLY (3×6), one window+vent+planter
      per cell from the sheet; intact-front / torn-side asymmetry; ring-balustrade parapet.
   10. open_files — keep the awnings (director-designed); re-express rack strata on drawer-module
       datums; vaulted hex-arch portal + cyan scan-beam curtain as ITS entrance idiom; sign board.

**2. Detail-sheet asset generators** (`scripts/generation/detail_sheet_builder.gd`) — every sheet
   asset (doors 1-7, portals 1-5, windows 1-7, tops 1-7, columns 1-6, signage 1-5) as a parametric
   builder whose ONLY inputs are survey measurements + a socket; a detail showcase fragment
   (picker: one plinth per asset); wire into building surveys as reservations.

**3. Entrance idiom overhaul** — delete the universal white-stone door; each district's survey
   places ITS idiom (kiosk / scan-arch / toll gate / hex-arch / entry-hood) from the sheets.

**4. Verification & review loop** — rerun the 10-agent plate comparison on the rebuilt row;
   target match ≥ 6/10 per building; fold residual alterations back into surveys; player-contract
   sweep stays green; red-shell specimens for every rebuilt massing (per-shot budget).

**5. Texture hookup** — UV baker reads survey datums as panel seams (edge wear along REAL
   construction lines); voronoi-as-pixel-art organic fill for reserved organic zones.
