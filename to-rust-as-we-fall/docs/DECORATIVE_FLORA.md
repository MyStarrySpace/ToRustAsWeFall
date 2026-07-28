# Decorative Flora — the ornamental invasives (director, 2026-07-12)

The director's brief: decorative flora with NO gameplay value that does NOT highlight like
functional flora. Several species play on INVASIVE flora that were planted to make things pretty.
Because these are scenery, they expose no READ, TEND, CLEAR, reward, or stat mutation; functional
flora keeps those affordances unambiguous.
This doc details each species, how they get removed or stay on death, and how they interact with
the runback mechanic (the wipe-restart within a run, and the roguelite's death ledger).

## Canon grounding

- GDD L957: "the renewable infrastructure has become decorative. The aesthetic of sustainability
  survives as branding while the substance has died." L965: "performative gardens... ornamental,
  or just for show."
- GDD L1469 (the cultivar rule): every tended AND decorative species is a feral cultivar — "the
  escaped and degraded descendant of an engineered commercial product." So the decoratives KEEP
  THEIR COMMERCIAL BRAND NAMES: the product line survives as the species name.
- flora_taxonomy.md "Ambient flora" is the parent category (forget-me-nots, unnamed wild
  clusters, moss carpets, vine skeletons). The ornamental invasives are its new sub-register,
  DISTINCT from the wild clusters: the wild flowers are survivors; these are colonizers that were
  *installed*. A corridor full of ornamentals is not a corridor with conditions for life — it is
  a corridor something was paid to beautify. Learning to read that difference is the point.

## Interaction grammar

- Decorative flora takes NO hover outline and NO SHIFT-reveal — the interaction grammar treats it
  as scenery, exactly like a wall. New players will try to tend it; nothing responds.
- Decorative planting history can still be legible through shape, placement, and runback state.
  It does not need a bespoke interaction to explain that it is decorative.
- If a future placement blocks a route or hides a clue, that placement must use a separate typed
  gameplay object with a real consequence; the general decorative class remains scenery.

## The species (feral cultivar brand lines)

### Verdanta™ — the lawn that swallows walls
The corporate groundcover pile: a uniform, impossibly even green carpet that climbs anything
(kudzu/English-ivy register). Sold to make dead facades read alive; still doing its job.
- **Visual:** flat emerald pile patches on floors and up wall bases; unnervingly uniform; a faint
  plastic sheen. No glow, no sway.
- **On death / runback: STAYS and SPREADS.** Each runback (a wipe-restart, or a roguelite death
  recorded in the run ledger) grows +1 Verdanta patch near where the party fell. The world gets
  prettier and deader with every attempt — your failures are landscaped over. The spread count is
  seeded from the run's death ledger, so replay reproduces it.
- **Interaction:** none. A route-blocking or clue-covering patch must be authored as a distinct
  functional object, not silently promoted from this decorative class.

### Curbelia™ — the median bedding rows
Identical pastel blossoms in dead-straight rows: street-median bedding stock (Bradford-pear /
municipal-planting register). Planted by the meter, by contract.
- **Visual:** low ranked rows of one-color flowers along walkway edges and building aprons;
  always in lines, never in drifts — geometry is the tell that nothing wild grows this way.
- **On death / runback: STAYS, unchanged.** Contract plantings do not care that you died. Their
  indifference is the read.
- **Interaction:** none.

### Lilypall™ — the pond dresser
Pale rosette rafts that tile a water surface edge-to-edge (water-hyacinth register). Sold to make
stagnant basins read as garden ponds; chokes them instead.
- **Visual:** floating pastel rosettes on any standing water (channels pools, basin set pieces);
  drift slowly; never bridge anything (they part under weight — the pretty lie of a crossing).
- **On death / runback: RE-ROLLED.** The rafts drift between attempts — each runback deals a new
  arrangement (seeded per attempt index). Purely cosmetic variation that makes a re-run's water
  read freshly, and teaches they carry no information.
- **Interaction:** none. Water-level changes (the basin set piece) beach or float them —
  cosmetic response only.

### Festoona™ — the celebration vine
Garland vine strung across archways and between posts (wisteria register), engineered to bloom in
draped catenaries. Installed for openings, festivals, inspections; never taken down.
- **Visual:** hanging bloom garlands on arches, gantries, banner lines; the party-that-ended
  read. In the Aghora it is everywhere and still fed.
- **On death / runback: DROOPS.** The instance stays but flips to a wilted state for the rest of
  the run — the celebration is over, and the level quietly marks how many attempts this place has
  cost.
- **Interaction:** none beyond the state read.

## Placement (the generator's decor pass)

Decoratives place OUTSIDE the gameplay budget (they cost no node budget, carry no archetype) as a
decor density knob per node: denser near institutional/maintained registers (Cleanstreets,
Greenfields aprons, the Aghora), absent in Dead Zones (canon: nothing grows there — not even the
pretty things; their absence stays the strongest collapse signal). Verdanta's runback spread adds
patches beyond the base density, near recorded fall positions.

## Build state (v1 BUILT, 2026-07-12)

- `DecorativeFlora` (scripts/game/objects/decorative_flora.gd): the 4 species' procedural
  visuals; dormant scenery (not interactive, not ray-pickable, never wired into the white outline
  grammar), with no reveal/clear state.
- Loader (`data_fragment_chunk`): object kinds `decorative_flora` and `spike_strip`; the runback
  decor pass runs
  in the wipe restart — Verdanta +1 patch near the fall (seeded from fragment id + wipe count),
  Festoona droops, Lilypall re-rolls; Curbelia untouched; host reset restores the authored street.
- Demo: **`--preview=hostile_streets`** ("Hostile Streets (decor + studs)", top of the picker) —
  all four species + two spike strips + a lure-across-the-studs pack + wipe-restart runbacks.
- Guarded by `--test-decorative-flora` (in `--test-all`): the non-interactive scenery contract,
  both stud drains (party + enemy), all four runback rules, and host reset.
- Generator placement (decor density per node register, Verdanta spread off the RunSession death
  ledger) is queued with the element-vocabulary track (ROGUELITE_RUN.md "Next").
