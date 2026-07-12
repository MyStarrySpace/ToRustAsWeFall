# Detail-Clearance Backlog — the measured-construction sweep (2026-07-12)

The director's report: smaller elements across the generators overlap/clip because they were
constructed from guessed constants instead of measurements (the Aghora staircase was one instance
of the class). A capture sweep of all 16 survey building kinds (three-quarter facades, seed 0)
confirmed the class and produced this ledger. The method for every fix is the same: derive the
element's placement from the SAME measured table/profile its neighbours use — never a constant.

## FIXED this pass (commit-verified by re-capture)

- **Pipe drapes crossing facade features** (the systematic one): `Lattice.pipes` now takes
  MEASURED `clear_lanes` — the caller derives them from the facade's real feature layout, and
  every run (walk, jogs, bundle offsets) stays inside one lane. The showcase wires them by
  lattice type: honeyframe/voronoi/rackwork → the solid border rim at the face edges (drapes ride
  the seams/arrises); tracery → the bay-boundary piers. Free wander is preserved for the bare
  vein-tendril kinds (ancourage, hypelines) whose wander IS the look. Verified: honeycomb's
  drapes ride the corner seams, no lit cell crossed.
- **Aghora exchange neon emblem buried in the dome**: the ring is a full vertical disc — its
  lower arc reaches heights where the dome is wider than at its centre, so the plane offset is
  now the MAX of the surveyed profile sampled over the ring's whole span (+0.16 clearance),
  with the table's `proud` kept as the authored minimum. Re-reconciles automatically under
  roll_vars ring-size rolls. Verified: full circle proud, brackets stretch to meet it.
- **Zone3 props/ties across the arch windows**: the porch props (full-height poles) and wall-tie
  anchors now reconcile against the window spans measured from the same table — a pole that
  would stand across an arch shifts to the nearest pier. Verified.

## OPEN (found by the sweep, ordered by visibility)

1. **Aghora exchange drapes** cross the terrace railing band and hanging banners (its `pipes`
   drape has no lanes). Needs lanes derived from the AGHORA survey's banner arcs + terrace
   sector — the generic `clear_lanes` mechanism is ready; only the measured arcs are missing.
2. **Cleanstreets**: the column-bowl rims pierce the swooping canopy sheet (bowl height vs the
   canopy's local wave height were never reconciled — clamp bowl tops below the measured canopy
   y at each column). Also: the floating blue orbs above the roofline read as untethered — decide
   lamp-on-pole (add the pole) or remove.
3. **Greenfields**: the parapet railing runs THROUGH the roof huts — skip rail segments crossing
   each hut's measured footprint, or inset the huts inboard of the rail ring.
4. **Bulwark wharf**: the fence webbing overshoots its panel frame at the bottom rail (strands
   exit the rect). Clamp strand endpoints to the frame's measured interior.
5. **Ancourage**: the descending cable bundle interpenetrates the white lintel light bar over the
   entrance (bundle path vs the lintel's measured band); the red accent orbs float untethered
   (same decision as cleanstreets' blue ones).
6. **Watchtower/tiered kinds**: white spire dots above the cage + cyan ledge dots — audit the
   accent-dot emitters for tethering (one shared pattern across kinds).
7. **Hypelines**: the pipe arms plunge into the mound without a join collar (not interpenetration
   of siblings, but the join reads unmeasured — a socket boss at each arm root would ground it).

## The rule this ledger enforces

Every entry above is the same failure: an element placed relative to ONE datum (a face plane, a
centre height, a lot constant) while its real neighbourhood is governed by ANOTHER measured
feature it never consulted. Fix = consult the feature's own table/profile at build time, the way
the survey's reservations already do inside `BuildingSurvey`. When a fix generalizes (like
`clear_lanes`), put the mechanism in the shared builder, opt kinds in with measured inputs.
