# Paranucleus — Fable hand-off spec (geometry-only) + biological asset kit

**Why this doc exists.** Fable balks when a prompt names biology ("amyloid", "protein", "oligomer"). So this doc splits into two halves:

- **§A–§B: pure geometry.** Forms, counts, ratios — every biology word scrubbed. **These are the parts you paste into Fable.** A geometry generator can build them with zero biology knowledge.
- **§C: biological grounding + citations.** Provenance only — this is *for you*, so the shapes stay defensible. **Do NOT paste §C into Fable** (it's the part that trips it).

A working parametric build already exists in [`build_paranucleus.py`](build_paranucleus.py) (run it into a live Blender via `python /c/tmp/blsend.py < blender/paranucleus/build_paranucleus.py`). §D lists its knobs. Use Fable when you want it to *re-imagine* the geometry from the description; use the script when you want the deterministic, canon-parameterized version.

---

## §A. The landmark — geometry-only description (paste to Fable)

> A colossal ceremonial monument built as a **vertical stack of broad flat rings** — each ring an annular disc with an open hole in its center. Each ring is smaller in radius than the one below it, so the stack rises as a **stepped cone** tapering toward the top. Every ring is hollow and their central holes **line up into one open shaft** running straight down the middle. Around the **inner rim of each ring** stands a **crown of small raised rectangular teeth**, evenly spaced (tooth count a multiple of 6). Between consecutive rings sit **recessed darker bands**. Nested into the base, a few **smaller concentric rings step down and inward** toward the center like an amphitheatre — rings within rings within rings. At the **bottom center of the shaft**, a **concentrated light source glows and shines up** through the aligned holes, so that seen from directly above it reads as a **single small bright point at the heart**. Material: matte **bone-white and pale-lavender**, alternating ring to ring; the recessed bands a **deep purple**; the central glow a **saturated pink-red** — the only saturated warm color anywhere in the scene. Around the base, a **scatter of small grey rectangular buildings**, some tucked under the lowest ring's overhang as if half-swallowed by it. Setting: a **hazy gray-purple background**, soft even ambient light, **no harsh directional sun**. **Low-poly faceted geometry** with pixel-art textures. Monumental in scale — the grey buildings are specks against it.

**Parameter table** (hand these numbers to Fable if it accepts them, or tweak in the script):

| Knob | Value | Meaning |
|---|---|---|
| stacked rings | 6 (open) | vertical tiers; count is deliberately loose |
| base ring outer radius | 14 | widest, lowest ring |
| top ring outer radius | 4.8 | narrowest, highest ring |
| base pore radius | 8.0 | central hole at the base (wide) |
| top pore radius | 3.3 | central hole at the top (open eye) |
| ring band height | 1.8 | keep thin → reads as stacked *wheels*, not a cake |
| recess gap | 1.6 | the deep-purple shadow band between rings |
| teeth per ring | multiple of 6 | ~1.6-unit arc spacing; the subunit register |
| concentric base ridges | 2 (lower 3 tiers) | the "rings within rings" grooves |
| central-well rings | 3 | concentric rings descending to the core |
| core color / glow | pink-red, mid strength | boss-exclusive saturated warm point |

---

## §B. Biological asset kit — geometry-only primitives (paste to Fable)

The landmark is built from one motif scaled up. Here is the motif chain, each as a neutral geometry spec + a one-line micro-prompt. **No biology words** — safe to feed Fable directly.

### B1. Subunit ribbon ("hairpin")
Geometry: a **short flat ribbon** — a rectangular strip a few units long, gently thick, **bent into a hairpin**: two straight parallel segments joined by one **tight U-turn** at a single end, all lying flat in one plane. Faceted, low-poly.
Ratios: strip width ≈ 1.0, thickness ≈ 0.2, each straight run ≈ 3.0 long, turn radius ≈ 0.6.
> *A short flat faceted ribbon, like a folded strip of tape, bent into a hairpin — two straight parallel legs joined by a tight U-turn at one end, lying flat. Low-poly.*

### B2. Rosette ring ("paranucleus" unit — the namesake)
Geometry: take **5 or 6 copies** of the B1 ribbon and arrange them **radially around a central axis**, evenly spaced like spokes/petals, leaving a **small round hole (pore) in the middle**. Result: a small doughnut/rosette — central hole, serrated rim. (5 = pentamer, 6 = hexamer.)
> *Five (or six) identical faceted hairpin ribbons arranged radially like spokes around a central axis, evenly spaced, leaving a small round hole in the middle — a small serrated doughnut/rosette. Low-poly.*

### B3. Concentric pore ring ("annular" assembly)
Geometry: **nest 2–3 rosette rings concentrically** (a smaller one inside a bigger one), sharing the central hole, optionally each rotated slightly — **rings within rings**. Keep the central pore open through all of them.
Ratios (real-world scale, for proportion): outer ring ≈ 8–12 across, central pore ≈ 2–2.5 across, adjacent ring walls ≈ 0.6–1.2 apart.
> *Two or three serrated rosette rings nested concentrically, sharing one open central hole, each slightly rotated — rings within rings, a doughnut of doughnuts. Low-poly.*

### B4. Compose up → the landmark
Scale the B3 concentric-ring assembly to monumental size, then **stack copies vertically with decreasing radius** (§A). The rosette's radial subunits become the **inner-edge teeth**; the shared central hole becomes the **open shaft**; put the **pink-red glow at the bottom of the hole**. That's the whole monument from one motif.

---

## §C. Biological grounding (provenance only — do NOT paste into the generator)

Canon (GDD §4.5 / §11.2.2): the Paranucleus is a monumental **amyloid-paranuclei aggregate** — "**annular oligomers**, ring-shaped aggregates of misfolded amyloid, the early pre-fibrillar / most-neurotoxic form... **rings within rings within rings**, the protein's molecular geometry made into a building," in the **ophanim** register (wheels within wheels). The tooth crown = "amyloid plaque's protein-subunit register made architectural." Pink-red core is boss-landmark-exclusive; local sky is gray/purple.

Real structural biology the shapes honor (according to PubMed):

- **The "paranucleus" is a real Aβ term.** Aβ42 preferentially exists as **pentamer/hexamer units called paranuclei**, which self-associate into larger oligomers; Aβ40 does not form them — Bitan, Vollers & Teplow 2003, *J Biol Chem* ([DOI](https://doi.org/10.1074/jbc.M300825200)); Bitan et al. 2003, *JACS* ([DOI](https://doi.org/10.1021/ja0349296)). → **B2 uses 5 or 6 subunits.**
- **Annular protofibrils are ring-shaped pore-formers** on a pathway distinct from fibrils, associated with diffuse plaques — Lasagna-Reeves, Glabe & Kayed 2011, *J Biol Chem* ([DOI](https://doi.org/10.1074/jbc.M111.236257)). → **the open central pore + glowing core.**
- **Aβ42 oligomers / annular protofibrils model as concentric β-barrels** — identical subunits, adjacent barrel walls 0.6–1.2 nm apart — Durell & Guy 2021, *Proteins* ([DOI](https://doi.org/10.1002/prot.26249)). → **B3's "rings within rings," and the concentric-ring monument.**
- Typical annular-protofibril proportions: ~8–12 nm outer diameter, ~2–2.5 nm central pore.

Monomer note: the B1 ribbon abstracts the **amyloid-β peptide's β-hairpin** (β-strand–turn–β-strand) it adopts in these assemblies. (The *fibril* cross-β fold and tau paired-helical filaments belong to a different asset — the Tangler enemy — not here.)

---

## §D. The deterministic build (already working)

[`build_paranucleus.py`](build_paranucleus.py) builds the whole landmark parametrically in a live Blender and renders a hero + top-down. All knobs live at the top of the file (mirrored in §A's table). Ring count and rotation are canonically **open** (GDD §11.2.7), so `N_RINGS` is a free dial. Next passes: pixel-art `amyloid_bone` tile material (a proposed atlas row), a less "cake-like" outer profile, the rotating-ring gameplay variant, and GLB export to `resources/models/paranucleus/` when it's shippable.
