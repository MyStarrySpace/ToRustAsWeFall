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

| Card | Species | Build | Checked against the card? |
|---|---|---|---|
| ENT-008 (cloaked / revealed) | Redactor | `build_redactor.py` | yes — it cites the card |
| ENT-011 | **Hidra** | `build_hidra.py` | **no — and it does not match** |
| ENT-012 | **Flare** | `build_flare.py` | **no — and it diverges** |

ENT-001..007, ENT-009, ENT-010, ENT-013 are the remaining ten single-state fauna and are **not yet
mapped**. Identify them from the roster in `reference-docs/fauna_roster.md` (Sapscraps, Ferrules,
Hidras, Crusts, Candids, Meebs, Gnawers, Spikers, Tanglers, Flares, Naturalizers, Redactors, Toxos);
the card numbering does NOT follow the roster order.

### The two confirmed divergences

**Hidra (ENT-011).** The card is a pale, smooth, long segmented helix wound round a straight core,
lying along a conduit run — something a player walks past. The build is a dark bronze worm carrying
three blades per segment in C3 and a lit cutting edge. C3 is the **Sapscrap's** geometry (its body is
the siderophore's C3 symmetry); a Hidra is the hydroxamate iron-cage propeller, and the propeller is
the helix. The lit edge is invented: the roster gives the Hidra no tell of its own, because being
SEEN is the whole event — it is a reveal-gate, not a fight. A correction pass removed the blades and
the lit edge and repainted it pale, and still did not reach the card's read; it was reverted rather
than shipped half-done. What it needs is the geometry rebuilt as a helix around a visible core, not
a recolour.

**Flare (ENT-012).** The card is a translucent membrane with the granule classes visible INSIDE it —
cream, mint and purple granules around larger pale nuclear lobes. The build moved its granules proud
of an opaque skin, because sealed inside an opaque body they were invisible and "the membrane
brightens" had nothing to show. That was a reasonable answer to the wrong constraint: the fauna
material is an alpha CUTOUT, so real translucency is not available, but the granule field is
repetition and repetition is drawn — a granule card riding just proud of the surface would read as
granules seen through a membrane without needing transparency.

## The rule this index serves

Open the card before modelling, and cite it in the builder's docstring the way the flora builders
do. A written spec tells you what a thing is for; only the card tells you what it looks like, and
"eyeball the rendered cards against the ENT references" is not satisfiable if nobody knows which
reference belongs to which build.
