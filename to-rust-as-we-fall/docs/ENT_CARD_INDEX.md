# ENT concept cards — what each one is, and which build answers it

The cards live in `blender/previews/` (gitignored, alongside the other art sources). They are the
VISUAL authority: the written specs in `reference-docs/flora_image_prompts.md` and the fauna roster
say what a thing does, and the card says what it looks like. Where they differ, the card decides
silhouette, colour and scale.

This index exists because ten of the thirteen fauna were modelled without anyone opening their card.
The flora builders all cite theirs in a comment; only `build_redactor.py` does among the fauna. Two
concrete costs of that are recorded below.

## Flora — every one card-checked

| Card | States | Species | Build |
|---|---|---|---|
| ENT-014 | wild / tended / stressed | Seefern | `build_flora_rigged.py` |
| ENT-015 | wild / tended / senescent | Scarpet | `build_flora_rigged.py` |
| ENT-016 | wild / tended / spent | Flure | `build_flora_rigged.py` |
| ENT-017 | charged / tended / triggered / recharging | Hushbloom | `build_flora_rigged.py` |
| ENT-018 | wild+tended × open+sealed | Capbage | `build_flora_rigged.py` |
| ENT-019 | wild / tended / harvested / held_pod / spent_pod / combusted | Gasafoetida (+ the pod) | `build_flora_rigged.py` |
| ENT-020 | naturally / tended / harvested / deployed | Climbvine (plant + the cutting) | `build_flora_rigged.py` |
| ENT-021 | dormant / bloomed | **Mother Flure** | `build_flora_rigged.py` |

**ENT-020 cost one rebuild.** The Climbvine was modelled from the written spec before the card
directory was found. Its `naturally` and `tended` frames are the same vine on the same wall, and the
only difference between them is that the tended one has flushed green — so the leaves ARE the
tending signal, and the first build showed nothing for a tending but a slightly thicker internode.
The card also gave the scale the words could not: pale against its dark substrate, and rootlets that
are small dark nubs at closely spaced nodes rather than fans a quarter of the vine's length.

**ENT-021 was unidentified for a long time** and repeatedly flagged as matching no species. It is the
Mother Flure: its two frames are exactly the "pre-bloom (default state on entry)" and "bloom moment
(the set-piece climax)" her spec names.

## Fauna — identified so far

| Card | Species | Build | Against the card? |
|---|---|---|---|
| ENT-001 | Sapscrap — the three-palp C3 body, a squat lens on three clamping limbs | `build_sapscrap.py` | not yet checked |
| ENT-004 | Crust — a pale slab on a wall under a dense hexagonal pore array | `build_crust.py` | **checked, and it holds**: the pore field is ONE drawn card and only the dilating mouths are modelled |
| ENT-008 (cloaked / revealed) | Redactor | `build_redactor.py` | yes — it cites the card |
| ENT-011 | Hidra — a pale segmented helix wound along a conduit run | `build_hidra.py` | **rebuilt to match** |
| ENT-012 | Flare — a translucent membrane with three granule classes banked inside | `build_flare.py` | **diverges; a correction was attempted and reverted** |

ENT-002, 003, 005, 006, 007, 009, 010, 013 are the remaining eight and are **not yet mapped**.
Identify them from the roster in `reference-docs/fauna_roster.md`; the card numbering does NOT follow
the roster order (ENT-011 is the Hidra, third in the roster; ENT-012 the Flare, tenth). ENT-013 is a
segmented crescent body with one dark aperture and two pale bumps aft — most likely the Toxo, whose
"crescent body carries an apical conoid invasion complex", but it has not been confirmed.

### The two confirmed divergences

**Hidra (ENT-011) — FIXED.** It had been built as a Sapscrap: three blades per segment in C3, which
is that animal's geometry (card ENT-001 is the real thing, three palps and all), plus a lit cutting
edge invented outright — the roster gives the Hidra no tell of its own, because being SEEN is the
whole event. It is now twenty short links winding three turns along the conduit it passes for, with
the curvature and torsion solved from the coil the card draws.

The lesson that got it there: **measure the coil, do not derive it.** Where a pose-built helix's axis
lands depends on bone-frame conventions, and three separate derivations put the cable at 38 degrees to
the animal — a helix beside the cabling instead of around it. The build now reads the axis off the
parked body (centroid, then the dominant direction of the spread) and moves the conduit onto it, so
retuning the coil moves the cable with it.

**Flare (ENT-012) — still open.** The card is a translucent membrane with the granule classes visible
INSIDE it: cream, mint and purple beads around larger pale nuclear lobes. The build has three emissive
beads stuck proud of an opaque skin, because sealed inside an opaque body they were invisible and "the
membrane brightens" had nothing to show. The material is an alpha CUTOUT, so real translucency is not
available at all.

An attempt to replace the beads with per-class granule CARDS riding just proud of the membrane was
made and **reverted**: at any card size that stays inside the body's silhouette the beads read as a
few large blobs rather than a field, and the body narrows above and below its widest ring, so a card
scaled off the maximum radius hangs off the edges and stops reading as anything under a skin.

**Where the next attempt should start:** the Crust already solves this shape of problem. Its pore
field is painted into the body's own surface with a `register_detail` painter and only the few pores
that MOVE are modelled. Do the same here — draw the granule field into the membrane's texture so the
density and the three colours come from the card, and keep three small emissive cards on the existing
per-class bones purely for the lighting sequence the prime clip needs. The palette already carries
`flare_granule_azur` / `_specific` / `_tertiary` for it.

## The rule this index serves

Open the card before modelling, and cite it in the builder's docstring the way the flora builders
do. A written spec tells you what a thing is for; only the card tells you what it looks like, and
"eyeball the rendered cards against the ENT references" is not satisfiable if nobody knows which
reference belongs to which build.
