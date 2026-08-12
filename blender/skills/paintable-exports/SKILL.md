---
name: paintable-exports
description: The systemic paintable-asset pipeline — blender/paintlib/ builds clean-topology pieces with per-object hand-paintable textures (couch/bench grammar), exports game-ready GLTF into resources/models/, and hands every piece to BlockBench as OBJ+MTL+PNG. Use for ANY area needing paintable exports — furniture, Endo's junction, elevator/bridge, procedural building elements, enemies, flora. Companion to low-poly (builds) and pixel-atlas-texturing (the older one-atlas flow).
---

# Paintable Exports — the systemic pipeline

One library, one layout, two entry points. Everything the Peris furniture rebuild
learned is captured in `blender/paintlib/`; every future area reuses it instead of
re-growing a bespoke script.

## The layout (same for every area)

```
blender/<area>/build_<thing>.py    the area script: builders + layout + export calls
blender/<area>/obj-exports/        BlockBench hand-off: <Piece>.obj + .mtl + <Piece>_tex.png
blender/<area>/painted/            DROP HAND-PAINTED <Piece>_tex.png HERE — wins on rebuild
blender/<area>/<thing>.blend       saved editable master (script writes it)
to-rust-as-we-fall/resources/models/<area>/   game-ready GLTF + textures (committed)
```

Worked example: `blender/peris-sim/build_furniture_v2.py` (furniture, plant
displays, the Monos room, prop OBJs, j-store recolours — all through paintlib).

## Entry point A — procedural pieces (new furniture, building elements, props)

```python
import sys, os
sys.path.insert(0, os.path.join(REPO, "blender"))
import paintlib as pl
from paintlib import Builder, DETAIL_SCREEN  # + other detail tags

pl.register_parts({"pipe_rust": {"rgb": (0.30, 0.16, 0.09)},
                   "warn_lamp": {"rgb": (0.9, 0.6, 0.2), "emit": (1.0, 0.55, 0.2)}},
                  emit_strength={"warn_lamp": 1.8})

b = Builder()                       # boxes (skip= butting faces), ngon_prism,
b.box(..., "pipe_rust")             # annulus (ALWAYS closed), disc
piece = b.finish("PumpHousing")

pl.texture_object(piece, OBJ_EXPORTS_DIR, painted_dir=PAINTED_DIR)
pl.export_gltf([piece], RES_PATH)                       # game-ready
pl.export_obj([piece], OBJX + "/PumpHousing.obj")       # BlockBench hand-off
```

`texture_object` gives the object per-face UV islands packed into the smallest
square that fits (32 px/m default; pass 16 for far-away interiors), paints the
starter atlas in the couch/bench grammar (flat fill + 1px darker edge border +
detail painters), and attaches the material. An emissive texture exists ONLY if
a part declares `"emit"` — no phantom emission layers.

**The painted/ round-trip:** the artist imports the OBJ into BlockBench, paints
`<Piece>_tex.png`, and saves it into `blender/<area>/painted/`. On the next build
the painted file wins over the generated starter (which is still written into
obj-exports/ as a reference). Valid while the piece's GEOMETRY is unchanged —
editing geometry re-lays the UVs, so repaint after shape changes.

Custom face treatments: `MY_TAG = pl.register_detail("hazard", fn)` where
`fn(tile, mask, base, isl, px_per_m)` writes pixels; tag faces with
`b.box(..., detail=MY_TAG)`.

## Entry point B — existing assets (endo junction, elevator, bridge, imports)

```
blender.exe -b --python blender/export_paintables.py -- \
    --in to-rust-as-we-fall/resources/models/elevator/bridge.glb --joined
```

Splits any GLTF/GLB/blend/OBJ into OBJ+MTL+textures under
`blender/<area>/obj-exports/` (area inferred from the resources path). Embedded
gltf textures are unpacked and shipped beside the OBJ. `--joined` exports ONE obj
(right for structural assets with dozens of sub-pieces — the bridge has 72);
omit it for per-object splits. Existing UVs and textures pass through untouched.
The painted texture goes back beside the source asset under its original name
(these assets keep their own texture layout, not the paintlib grammar).

## Enemies & flora

Creature/flora GEOMETRY comes from their own generators (`creature-grammar` /
`stylized-plant-builder` skills). To make them paintable, call
`pl.texture_object` on the generated meshes before export (entry point A) — or,
for already-shipped gltfs, run entry point B on the asset. SDF-meshed creatures
have organic topology: expect many small islands; consider px_per_m 16–24.

## Repetition is a TEXTURE, not geometry — alpha pixel-art cards

**(Director, 2026-08-10.) A perforated or repeated form is DRAWN, not modeled.** A grate
is ONE plane wearing a transparent texture with the grate drawn as pixel art — never a
modeled lattice of bars. Foliage is pixel-art leaf CARDS — never a solid leaf-shaped mesh
per leaf. Modelling the repetition spends triangles for a *worse* read: bars alias into
mush at gameplay distance while a drawn grate stays crisp, and the detail ends up
somewhere an artist cannot edit.

- **Scale is fixed: 1 m = 32×32 px** (`DEFAULT_PX_PER_M`). A 2 m grate tile is 64×64.
  Never redraw at a "nicer" resolution — footgun #14 in `stylized-plant-builder` is the
  same law from the flora side.
- **Card only the repetition; keep the STRUCTURE modeled.** A grate keeps its frame, lift
  handles, and the dark pit plate that sells the drop; only the woven bar field is a card.
  A vine's body stays a mesh (it holds the form); its leaves are cards.
- Leaf silhouettes, phyllotaxy, the canonical low-res palette, and the UV-orientation trap
  live in the `stylized-plant-builder` skill. Its standing rule holds: leaves are separate
  cards, never painted onto one branch card.

## A STATE CHANGE IS AN ANIMATION — rig it, with an armature and weights

**(Director, 2026-08-10.) When a thing changes state, the player watches it CHANGE.
Not two bodies swapped, not a repaint, not a flipbook — a rigged transition.** Read
any flora spec and the transition is the readable thing: the Seefern's "vein-glow
brightens progressively from base to tip following her touch, the eye-markings
opening as she works... the visible progression of eye-openings tells the player
when it's complete"; the Hushbloom's leaflets "folded inward IN A WAVE along each
rachis"; the Scarpet that "visibly expands during tending". The animation IS the
progress bar — swapping endpoints throws away the only thing that communicates.

- **Rig with a real ARMATURE and weight painting.** Bones along the thing that
  bends — a rachis, a stem, a leaf's length — and weights that let it bend
  smoothly instead of hinging at one joint. `blender/paintlib/rig.py` owns the
  helpers: bone chains, automatic weights from the chain, actions, and the export.
- **A card must be SUBDIVIDED to bend.** A quad has four corners and cannot fold;
  `Builder.card(..., segments=N)` splits it along its length so a bone chain has
  something to move. Cards still carry their detail as pixel art — rigging changes
  how a card MOVES, never where its detail lives.
- **Animations ship in the gltf** (`export_animations`), so Godot imports an
  `AnimationPlayer` with the clips named after the transition (`tend`, `trigger`,
  `seal`). The runtime PLAYS a clip; it never poses bones by hand. Clips must
  ride **NLA tracks** (`export_animation_mode="NLA_TRACKS"`): the ACTIONS mode
  carries only the armature's *active* action, so a piece with five clips ships
  two and the omission is silent.
- **ONE RIGGED SUBJECT PER GLTF.** Exporting a family together looks tidier and is
  wrong: NLA_TRACKS samples every selected armature across every clip, so each
  subject's animations come out carrying constant rest-pose tracks for all the
  others' bones. Nothing looks broken — the tracks are constant — so the cost is
  paid quietly in file size, in load time, and in a flood of "couldn't resolve
  track" warnings the moment a scene instantiates one subject without its
  siblings. Four flora species in one file produced **7401 warnings in a single
  suite run** and a 336k-line log that would hide any real error in it. Split the
  export, then verify by reading the gltf back: each file's channel-targeted node
  count should equal that subject's own bone count.
- **Timing law still applies.** An animation is COSMETIC: the data layer owns the
  state and the scheduler owns when it commits. Never gate a state change on an
  animation finishing (see the fast-forward invariance law) — start the clip when
  the state commits and let it play.
- **A completed tending ends in a BRIGHT FLASH.** The flash is the "done" signal
  the player reads without a meter; it belongs at the END of the tend clip. glTF
  animates node transforms and not material properties, so a flash is something
  that CHANGES SIZE: a card parked at ~0.001 scale that snaps to 1.0 and back.
  **Draw it like anything else** — a bare quad has a hard rectangular silhouette
  and reads as a lit piece of cardboard standing in the plant. Give it card art
  whose alpha falls to nothing well inside the quad, quantised so it steps like
  the rest of the pixel art, and lie it FLAT over what completed (the patch lit,
  not a billboard planted in it).
- **Falling leaves and other shed parts** are keyframed detachables, not
  simulation — the `procedural-animation` skill covers the deterministic-fall
  playbook and its origin-vs-mesh-centre footgun. Shed a leaf as its own card on
  its own short clip.

### The rig gate — `rig.validate()`, every rigged piece, build-breaking

Two defects are invisible in a static render *and* in the build log, and both ship
silently:

- **A dead bone** — weighted to nothing. It rotates through the entire clip and
  deforms nothing at all.
- **An orphan vertex** — in no vertex group. It ignores every bone, stays behind,
  and tears the mesh open.

Automatic weights produce dead bones *routinely* wherever several similar strips
crowd one another: the first rigged Hushbloom shipped with five (`leaf0_3`,
`leaf3_3`, `leaf4_2`, `leaf4_3`, `leaf7_3`) and looked perfectly fine until the
gate was written. Where the topology is known — and for a procedural piece it
always is — **paint the weights** with `rig.weight_chain_strip` and bind with
`kind='ARMATURE_NAME'` so nothing is guessed.

**Bones may never outnumber the subdivisions they deform.** Past that point the
extra joints have no distinct rows to move, so their rotation is averaged away:
the detail is compressed out rather than gained. `weight_chain_strip` enforces
this by construction (bones = rows − 1), and `validate(..., segments_by_prefix)`
asserts it for hand-built chains.

**That bound is a CEILING, not a target — match the chain to the MOTION.** A chain
is for motion that travels: a fold running out along a rachis, a stem bending. A
motion that is uniform wants ONE bone. The Scarpet's tending expansion is uniform
— the whole boundary moves outward together — and a row-per-segment chain got it
wrong twice at once: each bone scaled about its own head and tore the mat into
strips, and the patch grew along its length instead of outward from where Peris
kneels. One bone at the centre, everything weighted to it, was both simpler and
correct. Ask what the motion IS before reaching for a chain.

**A part that rides a body it is not continuous with gets a PARENTED chain**
(`{"prefix": ..., "parent": "<bone>"}`), which parents without connecting so each
keeps its own head. Scaling the parent then carries the child's offset with it —
which is how the Scarpet's tufts spread with the patch instead of sliding out from
under it, and it means the tufts need no keyframes of their own.

**Pose-render every clip before believing it.** Both of those defects passed
`validate()` — the rig was structurally sound and deforming exactly as instructed,
just wrong. A rest pose cannot show them. Render start/middle/end of each clip and
look, and render the flash frame specifically: it lasts a few frames and sits
between the sampling points a start/mid/end sweep uses.

### THE REST POSE IS A STATE — and it is the FIRST one the player sees

A body that has played nothing is not "unposed", it is **idle**, and idle is a
state you are responsible for authoring. Every joint rests at scale 1.0 and zero
rotation, so anything a clip only ever *hides* is fully visible until something
plays. Four species shipped wearing their tending flare permanently that way: a
1.7 x 1.5 m emissive starburst over a 1.36 m carpet, on every plant in the world.
The flare stopped meaning "the work took", and the one moment it was meant to fire
was the moment it went out.

- **Park the armature in its idle stance and export it posed.** `rig.park(arm,
  {...})` after the clips, plus `export_rest_position_armature=False` in the
  exporter — **that flag defaults to TRUE**, and with it on, a Blender pose is
  silently discarded and the file ships the rest position regardless.
- **Do not fix it by shrinking the geometry.** The atlas packer allots texels by
  a part's PHYSICAL size, so a flash card modelled tiny comes out with no artwork
  on it. The card stays full size; its bone is parked shut.
- **A clip must START where the body rests.** The Scarpet's tend opened at 0.70
  while rest was 1.0, so tending snapped the patch 30% smaller and spent eight
  seconds returning it to exactly the size it began at — zero visible change
  across the whole transition, which is the one thing the clip exists to show.
  Model the idle state and have clips move AWAY from it: tending now grows the
  patch above its authored size.
- **Verify on the SHIPPED file, not the .blend.** Parse the gltf and assert each
  hide-only joint's node scale is its shut value, and render the rest pose by
  importing the exported gltf into an empty scene with nothing played. No clip
  frame is this frame, so a start/mid/end sweep can never show it.

### Reading a card back into geometry

- **The card's STATES are the clip list.** `blender/previews/ENT-0xx_*.png` is one
  file per state — ENT-016 is wild/tended/spent, ENT-019 is
  wild/tended/harvested/held_pod/spent_pod/combusted. Those filenames are the
  transitions the piece owes; the rig's job is the motion BETWEEN them.
- **Overlap the pieces that form a wall.** Nine petals at a 0.125 m throat and a
  0.30 m rim need ~0.23 m of card each to close the funnel; narrower and the
  trumpet reads as separate prongs. And keep a drawn rib CLOSE IN VALUE to its
  field — a hard dark rib reads as a gap and breaks the wall apart again.
- **Jag a rim across its WIDTH, never per row.** Varying a silhouette's half-width
  by row notches a V down the middle of every petal; cut alpha by column in the
  top few rows instead.
- **A stacked column will show its seams, so make them NODES.** Segments are what
  let a stem bend, and their joins band whatever you do — end each segment a
  little fatter than the next begins and the artifact becomes the swelling a real
  stem has at its nodes.
- **Weight the small late additions.** A resin drop, a bead, anything appended
  after the main loops falls outside every `range()` you wrote and ships as
  orphan verts. `rig.validate` catches it — the Gasafoetida's wound-drop was
  exactly 10 orphans, one 5-sided prism.
- **Export defensively.** GLTF_SEPARATE rewrites the .gltf and .bin in place, and
  replacing a file an engine still holds open fails partway and leaves a stale
  header beside fresh buffers. Delete the targets first and retry the op.

**Godot caches imports.** After re-exporting a rig, delete
`.godot/imported/<file>-*` and reimport before trusting an in-engine probe — a
stale `.scn` will report the OLD weights and send you chasing a fixed bug.

## The UV gate — every model gets an Opus subagent, no exceptions

**(Director, 2026-08-10.) A piece is not built until its UVs have been audited, and
the audit is done by a dedicated Opus subagent — one per model.** Not by the builder,
and not by eye: the two failures that matter are invisible in a render and invisible
in the viewport, and they were shipped repeatedly because "the card looks right" was
treated as the acceptance test.

What the audit catches:

- **Hard overlap** — two faces claim the same texel. Painting one paints the other;
  the atlas cannot be hand-edited at all, so the whole `painted/` round-trip is dead
  for that piece.
- **Zero gutter** — two islands merely touch. No overlap, so a naive check passes,
  but they share edge texels the instant the painter dilates or a mip is generated,
  and colour bleeds across a seam that looked clean.
- **UVs outside 0–1** — the island samples the wrap, not its own pixels.

`scripts/uv_audit.py` is the instrument: it rasterizes every face **at the piece's
REAL atlas resolution** (auditing at a convenient 1024 passes pieces that bleed at
their actual 128) and reports per-object status, island count, coverage, hard-overlap
texels, and island pairs closer than the minimum gutter. Run it headless against the
saved `.blend`, or through the MCP `execute` transport against the file the director
has open:

```
blender.exe -b blender/<area>/<thing>.blend --python \
    blender/skills/paintable-exports/scripts/uv_audit.py -- --res 512 --json C:/tmp/uv.json
```

**Dispatch: one Opus subagent per model.** Give it the piece name, its atlas
resolution (read the exported `<Piece>_tex.png` header — do not assume), and the
script. It runs the audit, and when the verdict is not PASS it reads the packer
(`blender/paintlib/boxatlas.py`, `atlas.py`) to name the root cause in the LAYOUT
rather than reporting the symptom. A `no_uv_layer` result is not a failure: flat
palette pieces set `ob["no_atlas"]` and legitimately carry no atlas.

Fix the packer, never the individual piece — a gutter bug in an `ngon_prism`'s
cap/side packing is every prism in every district, and hand-nudging one piece's
islands leaves the other forty broken.

## Invariants (each was a shipped bug before it was a rule)

- **Half-texel inset** is built into paintlib — UV corners map to texel centres,
  never island-rect edges (edge-mapping samples the gutter → grey thin parts).
- **Tiny islands (≤4px) skip the edge border** — a border would swallow the fill.
- **Atlas background is warm dust**, never grey/black.
- **Emissive only where a part declares it**; per-part strength via EMIT_STRENGTH.
- **Rings close their loop** (`(i+1) % sides`) — see "Draw complex shapes
  COMPLETELY" in the pixel-atlas-texturing skill.
- **World scale**: the Peris/Aster rooms place furniture at 1.75x, displays at
  1.3x — model real-world metres and scale at PLACEMENT, never in the mesh.
- **Prop scenes** (watering can, logbook console pattern) reference fixed
  OBJ+PNG paths and provide their own material — overwrite those paths, never
  rename them.
- After a re-export, run the area's tests (`--test-peris-sim`,
  `verify_peris_room_assets.gd`, scene-load) before committing.


## The surface grammar — seams, edgewear, contact shadows (2026-07-30)

Every `texture_object` bake now carries the shared surface grammar in BOTH
paint paths (boxatlas for Builder pieces, atlas islands for bmesh pieces).
Any area build gets all of it free; these are the laws:

- **Seam borders.** Every island/box border IS a mesh edge — the 1px dark
  border is the seam read between shapes. The BOTTOM border doubles dark
  (contact grime): shapes sit, never float. v-up law: in atlas array coords
  the row `y0+h-1` is the WORLD TOP of a face.
- **Edgewear chips.** Exposed borders collect 1-2px posterized chips of
  worn-through steel (`_steel_lift` — lerp toward the catch-light, visible
  on ANY base). Densest on top edges and upper corners, sparse nicks down
  verticals, none on bottom faces. Deterministic: keyed by face seed so
  rebuilds reproduce identical pixels and same-size faces never clone.
- **Grounding band.** Side faces >= 12px tall get one extra posterized dark
  step above the base shade — the form reads as standing.
- **Contact seams.** Builder groups serialize their world `center`; the
  painter derives per-shape AABBs and, for every BOX face, projects any
  other shape's touching footprint through the face's own corner-UV mapping
  (orientation/mirroring always correct). A RESTING shape paints a grime
  step + seam outline of its footprint; a shape passing THROUGH paints the
  outline only. Clipped edges paint nothing; footprints covering >= 92% of
  a face are skipped (butting-scale). Note the honest subtlety: a resting
  footprint is mostly hidden UNDER its shape — the visible residue is the
  grounding line at the base, which is the point.
- **Determinism law (all of the above):** geometry-derived + face-seeded;
  never wall-clock, never unseeded random. A rebake with unchanged geometry
  is pixel-identical, so `painted/` overrides stay valid by the same
  contract as before.

Knobs live in `boxatlas.py` (`_worn_outline`, `_paint_contacts`,
`_CONTACT_EPS`) and `atlas.py` (the island border block). If an area wants
a different wear density, add a painter variant — don't fork the laws.
