# Flora — concept references and prompts

Flora is the one category where references ALREADY EXIST — never regenerate what
canon already covers. The canonical prompt file is
`reference-docs/flora_image_prompts.md` (self-contained prompts per species, with
tier / silhouette / affordance / states / tending / death per entry), and a full
card-art pass was already generated and modeled from:

| Sheet piece | Canonical prompt | Generated cards | Card model |
|---|---|---|---|
| Seefern (`seefern`) | flora_image_prompts.md § Seefern | `blender/previews/ENT-014_{wild,tended,stressed}.png` | alien_entities blends |
| Scarpet (`scarpet`) | § Scarpet | `ENT-015_{wild,tended,senescent}.png` | alien_entities blends |
| Flure (`flure`) | § Flure | `ENT-016_{wild,tended,spent}.png` | alien_entities blends |
| Hushbloom (`hushbloom`) | § Hushbloom | `ENT-017_{tended,charged,recharging}.png` | alien_entities blends |
| Capbage (`capbage`) | § Capbage | `ENT-018_*.png` | alien_entities blends |
| Gasafoetida (`gasafoetida`) | § Gasafoetida | `ENT-019_*.png` | alien_entities blends |
| Climbvine (`climbvine`) | § Climbvine | `ENT-020_*.png` | alien_entities blends |
| Mother Flure (`mother_flure`) | § Mother Flure (set-piece) | — | — |
| scene reference | § scene ref | `ENT-021_*.png` | — |

The blends live at `blender/alien_entities_v1.blend` / `_v2.blend` (card-billboard
technique, `blender/skills/alien-entity-cards/SKILL.md`; textures under
`blender/textures/entity/`). **Rework of any of the eight sheet flora pieces
starts from its ENT card, not from a new generation.** (Everything here is under
gitignored dirs — browse with `ls`, not Grep/Glob.)

## New prompts — the two species without cards

Both prompts embed the canonical preamble from flora_image_prompts.md.

### ForgetMeNots (`forget_me_nots`)

Canon (flora_taxonomy): small blue flowers in low untended clusters — the quiet
care signal in shelter corners. Not tendable, no states, no glow of its own.

> Voxel and low-poly base geometry with painterly atmospheric textures applied
> over it. Hand-painted brush detail visible on every surface. Restricted
> palette: muted teals and greens dominant, warm cream highlights, near-black
> background. Diorama-on-dark composition. Soft lighting from one direction,
> diffuse fill. Single specimen at frame center, isolated against the void. A
> low untended cluster of small five-petaled forget-me-not flowers, soft
> desaturated blue with tiny warm centers, on short slender stems rising from a
> ragged pad of leaves. Humble and quiet — no glow, no bioluminescence, just a
> patch of ordinary blue flowers persisting in an industrial corner, a small
> human gesture of care in a dark place.

### ResolutionRoots (`resolution_roots`)

Canon (flora_taxonomy): Inflammashunt-only — pale roots rising from floor
cracks, their underground filaments running toward the dormant Chelators. Never
transplanted, never weaponized.

> Voxel and low-poly base geometry with painterly atmospheric textures applied
> over it. Hand-painted brush detail visible on every surface. Restricted
> palette: muted teals and greens dominant, warm cream highlights, near-black
> background. Diorama-on-dark composition. Soft lighting from one direction,
> diffuse fill. Single specimen at frame center, isolated against the void.
> Pale bone-white roots rising up OUT of cracks in a dark industrial floor —
> smooth tapering root tips emerging like fingers, with thin pale surface
> filaments running along the floor away from them toward something unseen.
> The growth reads as coming from deep below, not planted; faint, almost
> luminous pallor against the dark slab, no bright glow.
