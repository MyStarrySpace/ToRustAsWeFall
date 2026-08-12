# Creature Pipeline — survey → layout → construct → unwrap → paint → rig → states → export

The workflow for building a rigged, textured, animated creature (enemy, NPC, party member)
from concept art, entirely through the live Blender MCP bridge. Proven on two creatures with
opposite body plans:

- **Ferrule** (`blender/fauna/ferrule/*_v3.py`) — segmented arch, translation-driven slinky,
  contract `tools/verify_ferrule_v3_model.gd` (37 checks).
- **Sapscrap** (`blender/fauna/sapscrap/*.py`) — radial maw-sphere with limbs, body-throw
  lunge, contract `tools/verify_sapscrap_model.gd` (33 checks, species-adapted).

**Read this BEFORE modelling any new creature.** The stages are ordered; every rule cites the
concrete failure that created it. Scripts are stage-per-file — copy the closest species' set
and adapt. Two interpreter families, don't mix them: the **bpy stages** (build / uv / rig /
render / export) run through `blend.py` against the live session; **survey, paint, gate,
probe, and webp-assembly are plain SYSTEM-python scripts** (PIL/numpy — Blender's python has
no PIL) run directly from the species dir (paint/assembly resolve their manifest/config
beside their own file).

**Reaching Blender:** the bpy stages run through `blend.py` (beside this file) — a socket
client for the Blender Lab MCP add-on on localhost:9876. Blender must be OPEN with the
add-on's server started. Usage: `python blend.py <script.py>` executes the script in the live
session and prints a JSON envelope; CHECK ITS `status` FIELD — the process exits 0 even on
Blender errors. Concept references live under
`to-rust-as-we-fall/reference-images/concept/fauna/` (gitignored — browse with Bash, not Grep/Glob).

**Bootstrap for a NEW species:** create `resources/models/fauna/<name>/` and drop a small
placeholder PNG per material sheet name BEFORE the first build — the build's `material()`
loads the sheets by path, and the first real paint pass overwrites the placeholders.

**Rebuild order after ANY geometry change:** build → uv → repaint → `img.reload()` → rig →
render. Skipping uv/paint leaves stale sheets on new topology. The rig scripts are
idempotent (they purge the previous rig + its actions first), so POSE-only re-authoring can
re-run rig → gate alone; any geometry change still needs the full chain.

## 0. Survey the concept FIRST (director's method: measure and mark points, then build)

Never lay out forms by eye. Pick the authority image(s) and survey them into numbers
(`survey_ferrule_v3.py`, `survey_sapscrap.py`):

- Segment the panel: body = darkness gate, accents = colour gate (tune per sheet — the
  Ferrule's chevron needed `g >= r - 15` because its yellow-greens have r≈g; the Sapscrap's
  cast shadow needed a saturation+value gate to exclude). Label connected components — the
  painted plates ARE the sections.
- Emit a normalised point table (origin on the ground under the nose, +x rearward,
  1.0 = silhouette height): per-plate centroid/bbox/area, global L/H, apex, clearances,
  GROUND-CONTACT runs, accent centroids/tips.
- **A turnaround beats a silhouette**: with front/side/back views the width axis is measured
  (Sapscrap); with one side panel it must be invented and declared (Ferrule).
- Write an annotated overlay PNG and LOOK at it before building.

What surveys catch that eyes miss: the Ferrule head rode on TWO ground pads with the mouth
chevron recessed between them (built flat, the teeth vanished inside the head); its two accent
pendants were a sagittal PINCER pair, not bilateral arms. For ambiguous reads spawn independent
read agents (anatomy / proportion / motion lenses) and reconcile — the numbers stay the
placement authority, the reads settle interpretation.

## 1. Lay forms onto the surveyed points

- One deterministic generator per visual grammar (`chunk()` hulls for faceted stone; icosphere
  + sag shaping for the Sapscrap ball). Seeded LCG only — a rebuild must reproduce every
  vertex; never `random`/wall-clock.
- Place every part at its surveyed station. Only invent what the source cannot show, and say
  so in the script header.
- KNIT ≈ 1.15–1.2: oversize parts so neighbours interpenetrate; inscribed shapes only touch at
  extremes and read as a rock pile.
- Clamp: no vertex below Z=0.

## 2. CONSTRUCT the actual mesh (the step the first Sapscrap skipped)

**Primitives at the surveyed points are the survey, not the mesh** — shipped raw they read as
"a bunch of shapes cobbled together" (director). The construction pass makes parts grow from
the body:

- **Project attachment loops onto the host surface**: `on_shell()` in `build_sapscrap.py`
  maps a point onto the (deformed) body ellipsoid; sleeve roots and collar rear loops are
  conformed to it, so limbs/maw lips meet the shell along its curve instead of being tubes
  pushed through a sphere.
- **Ring sleeves** (`ring_sleeve()`): telescoping segments with radius-step lips for limb and
  socket banding.
- **Dissolve to plate scale**: `dissolve_limit` 10–26° (after a small seeded vertex jitter to
  break coplanarity) so facets merge into readable plates. Angular slab grammar = fewer hull
  points + high dissolve angle; the Ferrule front only matched its concept after pebbles
  became slabs.
- **Booleans**: cutter cones must bore in from OUTSIDE the surface (solve the surface point,
  park the wide cap just proud of it). **The operand object must carry the host's WORLD
  transform** (`tmp.matrix_world = obj.matrix_world`) — booleans evaluate operands in world
  space, so an operand left at the origin lands displaced by the host's parent offset in
  local space (every sapscrap sleeve and its maw cutter once drifted 0.30 rearward: floating
  horn island, INTERNAL maw cavity, orphaned claws). After `new_from_object` baking, PURGE
  null material slots and find material indices BY IDENTITY — the bake can inject a null slot
  that shifts every index (the invisible-gullet bug). Guard the merge loudly: a union-find
  island count on the result (`build_sapscrap.py` raises on `islands != 1`) plus a KDTree
  claw-seating check. Prove dark cavities with a rendered PIXEL PROBE — a durable stage file
  (`probe_maw_sapscrap.py`: front render, sample the maw-centre RGB, assert mean < 80),
  never a face-count guard alone.

## 3. UVs: per-part islands, never the tiling level atlas (director's law)

Organic forms are unwrapped so texels BELONG to the creature ("so they don't look like we just
farted a texture onto them"). `uv_ferrule_v3.py` / `uv_sapscrap.py`:

- Smart-project each mesh into its own allocated cell (body parts on the body sheet, accent
  parts on their own sheet). Margins between cells. Ops need real context: select the object,
  make it active, EDIT mode.
- Emit the face manifest — per face: UV polygon, world normal z, world height, island id.
  The painter consumes this; it is what lets paint follow anatomy. **The manifest's OUT path
  must be ABSOLUTE into the species dir** (`blender/fauna/<name>/uv_manifest_<name>.json`) —
  the uv stage runs inside Blender whose cwd is arbitrary, and the paint stage resolves the
  manifest beside its own file; a relative path silently pairs a fresh unwrap with a stale
  manifest.
- **Re-run unwrap + paint after ANY geometry change** — stale sheets on new topology read as
  random blotches.

## 4. Paint through the manifest

`paint_ferrule_v3.py` / `paint_sapscrap.py`: per-face flat tones — height ramp (dark belly →
lit spine) + facing (lit crowns, near-black undersides) + per-face jitter so adjacent facets
never merge. Seams ONLY on island borders (edges used once within an island) — outlining every
face reads as wireframe. Wear is anatomical (rust/stain clusters low or on upper flanks per
the concept), grain is a small seeded tile jitter, palettes are tight and hard-pixelled.
Reload images in the live session after repainting (`img.reload()`).

## 5. Rig: one bone per section, full weights, DISCONNECTED chains

- EVERY mesh section gets its own bone; every vertex painted to it at weight 1.0
  (`vertex_groups.clear()`, one group, `REPLACE`). Rigid plates articulate at seams — full
  weights are correct and cheap. Keep a BIND map mesh-name → bone-name; fail loudly on
  unbound meshes.
- **A boolean-MERGED body takes REGION weights**: classify each shell vertex by geometry
  (inside a limb/horn capsule around the sleeve axis AND outside the body ellipsoid → that
  limb's bone; else the body bone — `shell_region()` in `rig_sapscrap.py`), still rigid 1.0
  per vertex. Guard the counts (raise if a region catches implausibly few verts).
- **A bone whose pose SCALE animates (squash/stretch) must be WORLD-AXIS-ALIGNED** — pose
  scale is diagonal in the bone's local frame, so a squash on a tilted bone shrinks along
  the tilt and barely reads (the sapscrap crouch lost 2/3 of its squash until the body bone
  was re-pointed vertical).
- **`use_connect = False` on every bone.** Blender IGNORES pose translation on connected
  bones — the Ferrule's slinky was silently dead for a whole revision while pixel-diff guards
  "passed" on rotation-only motion. Parenting alone gives the hierarchy.
- The spine chain follows the SURVEYED body curve so bone-local +Y runs along the body;
  leaf chains (mouth, jaws, hands, tail) hang off it and carry the big rotations.
- Bake object offsets into vertices before binding; never set `matrix_parent_inverse` when
  parenting to the rig (it cancels the root offset and shifts the export frame).
- **Probe bone-local axes empirically before authoring poses**: translate one bone ±0.2 on
  each axis in the live scene and measure a mesh landmark's world response — or read
  `bone.matrix_local.to_3x3()` columns and CONVERT world intent to local values
  (`local_loc()` / `rotx_sign()` in `rig_sapscrap.py` author whole pose tables as world
  directions). Roll conventions flip local Z depending on the bone's world direction — on
  the Ferrule, "down" was +Z on the arch bones and −Z on the head bones, and on its
  neck/head bones local +Y ("pull") points mostly DOWN-forward, which is how the landed
  strike ended up 25 percent below the floor. Theorizing gets this wrong; probing takes a
  minute.
- The rig scripts purge their previous rig + actions first (idempotent), so pose-only
  iteration is rig → gate. Without that purge a second run creates `Rig.001` and orphans
  the renderer.

## 6. Actions are GAMEPLAY STATES, not clips

- Name each action's ROLE (camp loop / telegraph / strike / seize+recover) and record the
  mapping in the wrapper's metadata (`action_roles`, `action_chain`) so the Enemy FSM wiring
  (windup → charge/impact → recover) reads intent from the asset. BOTH wrappers carry it and
  both verifiers assert the keys exist.
- **Key poses CHAIN**: the telegraph's held end pose == the strike's first pose; the strike's
  landed end == the seize's first. No pops when the runtime sequences them.
- Author every action starting from `clear_pose()` (zero all pose-bone loc/rot/scale) and end
  the authoring pass with `animation_data.action = None` — otherwise the previous action's
  end pose leaks into the next action's keyframes.
- A telegraph HOLDS its readable pose (the Ferrule perch holds 4 frames); a strike-from-above
  stays high at mid-flight and descends onto the target — author attack poses as named
  per-bone tables (`PERCH` / `LAND` in `rig_ferrule_v3.py`, `CROUCH` / `LANDED` in
  `rig_sapscrap.py`) tuned by live probes.
- Body motion rides chain-axis translation — as a gather/release WAVE, not a block shift:
  offset each bone's keyframes by a per-bone phase lag (the Ferrule idle's `i*7`-frame spine
  offset with growing amplitude). Leaf bones carry 10–30° rotations. Spine rotations
  compound — keep them small and deliberate (antisymmetric pitches shape an arch; uniform
  signs unroll it and swing the free end UP).
- Paired parts (jaws, hands, arms) get OPPOSING rotation signs — or phase offsets — so they
  clamp or alternate instead of swinging in unison.
- **Natural-motion laws** (each caught by a frame-panel review, worth a workflow of
  independent lens agents — weight/timing, overlap/follow-through, arcs/readability — over
  the rendered frames):
  - Stagger arrivals with per-bone frame lags (`pose_named(..., lag=LAG_TRAIL)` /
    `pose_spine(..., lag=...)`); simultaneous arrival on every bone reads as a pose snap.
    Impacts get a held squash frame, a visible rebound, and a DECAYING settle over 3-5
    frames; extremities overshoot the pose and come back. Put the jolt ON the contact
    frame, not a beat later.
  - Contacts hit at PEAK speed: key a mostly-open/mostly-high pose ONE frame before the
    contact so the Bezier cannot cushion into it; spend the slow frames AFTER contact. A
    close that eases in reads as mushing; a re-open should be slower than the close.
  - A chained body's height lives in its ANCESTORS' channels (the arch's raise is in the
    rear bones' pitches + drops): a launch "explodes" through the pull/forward channel
    ONLY, and airborne bones need an explicit flight HOLD key — otherwise the curve eases
    toward the landing arrival from the moment of launch and the pounce sags into a dig.
  - **Loop seams: never place cycle keys with a modulo wrap** — Blender F-curves clamp at
    the first/last key, so the "wrapped" segment flattens (frozen tail) and the loop pops
    at the seam. Sample the cycle as a sine across the whole range PLUS one key a full
    period past the end (`range(1, 66, 8)` for a 64f loop), and make breath asymmetric
    (fast inhale, slow exhale) so it doesn't tick like a metronome.
- **Blender 5.x slot trap**: after `ad.action = act` ALWAYS set
  `ad.action_slot = act.slots[0]`, or the action can silently not evaluate (we shipped
  rest-pose "animation" strips this way). Purge stale actions in the build's `wipe()`
  (`use_fake_user` keeps them alive and renames rebuilds to `.001`).
- **Gate on SILHOUETTE, not pixel counts** — a durable stage file per species
  (`gate_ferrule.py` / `gate_sapscrap.py`, system python): render the actions' KEY frames
  with ONE camera fit at rest, then assert alpha-bbox ratios (a perch must RAISE height
  ≥ 1.2×; a strike's top row stays high mid-flight then DESCENDS; a landed pose sits ON the
  ground — `bot` within ~6% of rest, the check that caught the Ferrule landing 25% below
  the floor; a crouch squashes H ≥ 10% and shifts rearward). Calibrate direction signs from
  a known motion (the sapscrap gate derives image-space "rearward" from its own windup), and
  point the camera PERPENDICULAR to the body's long axis — end-on, "extends" measures limb
  splay instead of reach. Pixel-diff guards pass on any motion, including the wrong motion.
  Render with a wide margin and NO ground plane, or the frame/floor saturates the bbox and
  every ratio reads 1.00.

## 7. Export + verify + deliver

- Export via a copy of `export_ferrule_v3.py` / `export_sapscrap.py`: GLTF_SEPARATE, external
  .bin + sheets, `export_yup` (mouth on +Z = runtime forward), ACTIONS mode with force
  sampling. Both scripts HARD-FAIL on a non-opaque exported material (`SystemExit` on the
  `non_opaque` list); the headless verifier asserts opacity again after import.
- Thin wrapper `.tscn` in `scenes/props/biota/<species>_visual.tscn` (forward / impact /
  rear-anchor sockets + `action_roles` + `action_chain` metadata) and a species-adapted copy
  of the verifier: adjust texture count (no emissive if the species doesn't glow), name
  tokens (mouth/segment/anchor + signal-or-claw), bounds bands to the species scale,
  expected action names. Run it:
  `cd to-rust-as-we-fall && ../Godot_v4.7-stable_win64_console.exe --headless --path . --import`
  then `... --headless --path . --script tools/verify_<species>_model.gd`.
- Name sections for the contract tokens from the start (mouth/segment/anchor/...).
- **Animated loops**: render full frame sequences (`render_anim.py`, driven by the species
  dir's `anim_config.json` — keys: rig, out, margin, azimuth, elevation, fps, actions[]),
  then `python assemble_webp.py <prefix>` (system python) assembles animated WebPs via PIL
  `save_all` with `exact=True` — without it lossy WebP stores grey DCT garbage UNDER
  fully-transparent pixels: invisible in playback, but it reads as edge streaks/clipping to
  any alpha-blind audit — and MOTION-GUARDS every loop (first vs mid frame diff — a static
  "animation" shipped once). Re-render sequences AND stills after any rig change — stale media on a live
  page misreports the asset.
- **LOOK at the rendered frames before delivering.** The gates check specific ratios, not
  overall visual correctness — logical success is not visual success.

## Gotchas index (the fast list)

- `blend.py` bridge always exits 0 — check the JSON `status`; never `>/dev/null && …`.
- Blender 5.1: engine enum is `BLENDER_EEVEE`; exports strip cameras/lights — every render
  script rebuilds its own rig AND purges its own stale scaffolding (Ground planes) BEFORE
  computing camera bounds.
- **Fit render cameras to the ANIMATED ENVELOPE, never the rest pose** — sweep the evaluated
  world bbox across EVERY frame of every action (`animated_envelope()` in
  `render_actions.py` / `render_anim.py`; a strided sweep missed the one frame where the
  landing dip peaked) with a small margin (~1.12), and size BOTH axes: the vertical view is
  only `ortho_scale * res_y/res_x`, so covering the largest dimension alone let a tall pose
  clip the BOTTOM edge — `ortho_scale = max(span, height * res_x/res_y) * margin`. Rest-fit
  cameras clipped the coil's head, left a tail-sliver streak, and a pose pinned at the
  frame edge silently FLATTENS any silhouette measurement made on that render. Audit with
  an alpha-gated edge scan (no opaque pixel on ANY of the four frame borders).
- Multi-line `str.replace` patches no-op silently when the target drifted — rewrite whole
  functions/blocks, and keep an output assert (leftover-token scan) so a no-op can't ship.
- `use_connect=True` kills pose translation (§5). Boolean operands need the host's world
  transform, and merged results get an island-count guard (§2). Null material slots after
  boolean bakes (§2). Action slots (§6). Pixel-probe dark regions (§2). Pose scale needs a
  world-aligned bone (§5).
- Masters + pipeline scripts live in `blender/fauna/<name>/`; runtime gets only exported
  gltf/bin/sheets under `resources/models/fauna/<name>/`; wrapper `.tscn` in
  `scenes/props/biota/<species>_visual.tscn`; verifier in `to-rust-as-we-fall/tools/`.

---

## THE PROPORTION CONTRACT — measure the sheet, seam the parts, then fan out

(Director, 2026-08-12, looking at a Gnawer: *"it looks so derpy and the proportions
are so off"*.) He was right, and the reason is a process failure, not a modelling
one: parts had been nudged **one dimension at a time**, each change eyeballed
against the last render instead of the whole animal measured against the sheet. A
creature built that way drifts — every individual tweak looks like an improvement
and the silhouette still reads wrong.

The fix is to make proportion a **contract that is measured before anything is
modelled**, then hand each body part to its own agent working against that contract
and against a shared seam.

### 1. MEASURE THE SHEET FIRST — numbers, not impressions

Threshold the turnaround, split it into its views by empty columns, and for each
view record the silhouette **aspect** and a **band profile** (width at each tenth
of height, as a percentage of that view's width). This is cheap, deterministic, and
it is the target every agent is held to.

    front  W/H = 1.34   bands 27 43 54 66 75 81 86 86 89 100
    side   W/H = 2.03
    rear   W/H = 1.21

Then render the CURRENT model and measure it **the same way** — same script, same
metric — so the deltas are comparable. Key the model's mask off the corner pixel,
never off a luminance threshold: a dark creature on a dark backdrop keys as the
whole frame and reports a perfect 1.00 aspect for every view, which is what
happened the first time.

    model  front 1.70 vs 1.34   (27% too wide for its height)
    model  side  1.44 vs 2.03   (29% too short for its length)
    model  front bands peak 100 at 40% down, fall to 71 at the feet;
           the sheet climbs monotonically to 100 AT the feet

That last line is the whole "T where the sheet is a triangle" finding expressed as
a number, and a number is something an agent can be held to.

### 2. NAME THE SEAMS BEFORE SPLITTING THE WORK

Parts join at ONE ring both own (see the graft law). So before any agent starts,
write down every seam as an explicit contract: **centre, normal, radius, segment
count**. Every agent building a part that meets that seam is given the same numbers
and must build FROM them. This is what makes parallel part-modelling safe — two
agents cannot disagree about where the neck is if the neck ring is a constant they
were both handed.

A seam contract for a quadruped looks like:

    neck   centre=(0,+0.31,0.29) normal=(0,+1,0) r=0.085 seg=12
    hip_fl centre=(-0.16,+0.20,0.19) normal=(-0.5,+0.3,-0.8) r=0.065 seg=10
    ...

### 3. FAN OUT — ONE AGENT PER PART, EACH HELD TO ITS OWN BOUNDS

Give each agent: its seam ring(s) verbatim, the sheet views cropped to ITS part
with the measured bounds of that part in each view, and the pipeline laws. Require
it to report back the bounds its part actually achieves, so the claim is checkable
without opening Blender.

Agents return **parameters, not meshes** — a dict of measured dimensions and shape
spec for their part. The integrator assembles them into the build script. This
keeps the run deterministic, avoids two agents writing the same file, and makes
every part's contribution reviewable as a diff of numbers.

### 4. VERIFY AT THE WHOLE-ANIMAL LEVEL, NOT PER PART

A set of individually-correct parts still reads wrong if the assembly drifts, so
re-run step 1's measurement on the assembled creature and diff it against the
sheet. The acceptance test is the aspect and band profile of the WHOLE silhouette
in every view — not "does each part look like its crop".

**The standing trap this replaces:** eyeballing a render against the previous
render. That measures progress against yourself, never against the sheet, and it is
how a creature ends up derpy one defensible tweak at a time.

### 5. THE SILHOUETTE DOES NOT TELL YOU WHICH PART OWNS A PIXEL

First run of this method on the Gnawer: **six parts measured, six rejected by their
checkers, zero confirmed.** That is the process working, and the failures shared one
root cause worth stating as a law.

**A part measured off the outline is measured wrong.** The carapace agent reported
its dorsal skirt reaching y_frac 0.690 with "blade tips at (0.062,0.690)"; its
checker traced the front edge row by row, found it descends monotonically with NO
local minimum, and identified the whole region as an unbroken FORELIMB shank running
into a bone-tan foot. The torso agent's two "measured confirmations" were likewise
matches to limbs. Both had traced the silhouette and attributed it to their own part.

Two cheap tests catch this every time:

- **Sum test.** A part cannot be wider than the whole animal at the same height. The
  carapace's skirt came out 0.482 m across at a row where the entire front
  silhouette spans 0.475 m — 7 mm wider than everything, leaving negative room for
  the two forelegs plainly visible there.
- **Cross-view consistency.** A symmetric assembly must give the same outer extreme
  in front and rear. Front said 0.690, rear said 0.582; the rear view (limb tucked
  inboard, so the part is unoccluded) was the honest read. **Prefer the view where
  your part is NOT occluded, and say which view you used.**

So: require every agent to name, per bound, WHICH VIEW it read and WHY that view is
unoccluded for its part — and to run the sum test before reporting.

### 6. THE CONTRACT ITSELF MUST BE CHECKED — MINE WAS NOT SELF-CONSISTENT

The same run caught an error in the brief rather than in the work: I fixed the hood
ridge at **Z = 0.40** while stating a target box height of **0.305**. A ridge cannot
sit at 0.40 on an animal 0.305 tall. Agents split over it — one derived a
self-consistent 0.410 m height from the fixed seam, another reconciled to 0.298 via
a ground plane — and a contract that different parts resolve differently is exactly
the drift this method exists to prevent.

A second conflict was real rather than arithmetic: the fixed rear ridge
(0, -0.22, 0.36) puts the crest 0.10-0.13 m ABOVE where the sheet shows it (Z~0.268
at that Y). The sheet and the seam genuinely disagree, and the part that owns the
seam surfaced it instead of silently building to one of them — which is the correct
behaviour and should be required explicitly.

**Before fanning out, verify the contract against itself:** every fixed seam must
lie inside the stated target box, and the box must be derivable from the sheet's own
aspects. Have one agent do nothing but try to break the contract before any part is
measured.

Encouraging sign worth keeping: the feet checker validated its own tooling by
reproducing the brief's published front band profile (it got 28 43 54 66 75 81 87 87
90 100 against the stated 27 43 54 66 75 81 86 86 89 100) before trusting any of its
own measurements. Require that self-check.
