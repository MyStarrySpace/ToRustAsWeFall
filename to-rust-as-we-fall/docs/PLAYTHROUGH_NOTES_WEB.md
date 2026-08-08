# Playthrough notes — real browser, real input (2026-08-07)

Method: web export served locally, driven through Chromium with Playwright using actual mouse and
keyboard input — no data-layer shortcuts, no force-fired gates. Screenshots at every beat. Two runs:
the authored intro (Peris's sim) and a **freshly generated stretch** (seed 80713, custom teaching
profile, generated live from the picker's GENERATED SEED control).

This is the first time the game has been played end-to-end in a browser by anything other than a
person, and it found things no headless test can see. Findings are ordered by severity.

---

## 1. ~~HUD/input mismatch~~ — RETRACTED, I misread the glyph

**This finding was wrong and is withdrawn.** I reported that the HUD advertised LEFT-click for Move
while the game required RIGHT. It does not. Verified three ways after the fact:

- `project.godot` binds the `command` action to `button_index: 2` — right mouse.
- The hint passes the literal fallback `"RMB"` (`fragment_preview_sequence.gd:2362`).
- Cropping and enlarging the actual pixels: the glyph convention is that the **light** half marks the
  active button (`mouse_left.svg` lights `M5 … H5Z`, the left half; `mouse_right.svg` lights
  `M16.8 … 27`, the right half). The rendered glyph has its **right** half lit. It is the correct
  right-mouse icon.

I read a 20-pixel icon at a glance and asserted a blocking UI bug from it, which put a phantom item on
the director's backlog. The real reason my early clicks did nothing is finding 3's lesson: I was
clicking at *guessed screen coordinates* that were not valid ground targets. The moment I clicked
coordinates the game itself published, movement worked immediately. Same button throughout.

Lesson kept deliberately: **verify a visual claim against the asset or the binding before reporting
it.** A screenshot at a glance is a hypothesis, not evidence.

## 2. Generated levels render BLACK — DIAGNOSED (three causes, two fixed)

Not web-specific: Forward+ and GL Compatibility are pixel-identical, so the browser was only showing
what desktop already did. Chased by measuring the live scene rather than reading code — every
code-reading hypothesis (triplanar-under-Compatibility, missing textures, fog of war, the perception
overlay shaders, scene exposure) was wrong, and each died to one probe.

**Cause 1 — the ground was being faded as a camera occluder. FIXED.** Camera occlusion picks
occluders by AABB height against a minimum (the preview passes 2.0). A floor slab is 0.16 m thick and
should never qualify, but the floor is committed as ONE merged surface, so on a warped spiral stretch
its bounding box spans the whole descent — measured **14.88 m** — and passes the gate. Proven by
painting the floor unshaded magenta: **dark purple while wrapped, pure (255,0,255) once exempt.** That
same probe also disproved the "something dims the whole scene" theory: nothing does.

**Cause 2 — the floors were wound inside-out. FIXED.** `_tri_auto` derives each face normal from its
winding, and the top face was emitted `(A,C,B),(A,D,C)`. Measured on the live mesh: first vertices
carried normals **(0.13, −0.96, −0.24)** — the surface you walk on pointed DOWN and was lit from
behind. Now **(−0.13, 0.96, 0.24)**. Invisible to every test because the material disables culling, so
the geometry still draws; it just never lights.

**Cause 3 — a multiplication stack that bottoms out. NOT a bug; needs a tuning ruling.** With both
fixes in, the floor is still black, and the arithmetic explains it exactly:

| Measured | Value |
| --- | --- |
| Floor with its real material | `(0,0,1)` |
| Same floor, texture removed (albedo only) | `(6,12,12)` |
| Same albedo unshaded (what full light would give) | ≈ `(97,117,117)` |

So the biome's capped lighting delivers only **~6%** of albedo, then the floor tint (0.38) and a dark
tile (`deck_metal`, average `(51,54,62)` ≈ 0.2) multiply it down another 5×. 0.38 × 0.2 × 0.06 ≈
**0.005** — visually black. Triplanar is innocent: disabling it changes nothing, because the texel it
samples is dark either way.

**Why cranking the lights never appeared to help** (and cost me two wrong conclusions):
`_apply_preview_lighting()` is called from `_sync_preview_time_presentation()`, which fires on every
preview clock update — so any environment override is overwritten within a frame or two. Lighting
cannot be tested by setting it from outside; it has to be changed at the source.

**FOG IS RULED OUT (windowed capture, 2026-08-07).** The open question from the original run --
"is the whole level black, is it the fog shader?" -- is answered NO. Captured the generated stretch
windowed at 1280x720 with fog ON, then again with `fog_of_war_enabled = false`: the large black
polygons are pixel-unchanged. Disabling fog only adds the Aster Data overlay's cyan structure
edges. So the level's SHAPE is legible through the overlay while the floor SURFACES stay black.

Both committed fixes are visibly working -- some tiles now light (the teal/blue deck on the right
of the frame) and the party, route markers and highlighted object all read. What remains black is
the rest of the floor, which is exactly the multiplication stack above, still awaiting the ruling.

One methodological note worth keeping: the first capture's numeric check said the floor band
averaged (75, 66, 60) and looked fine. It was sampling UI chrome, not floor -- the briefing panel
and CARRY/CONSUME panel occupy much of the frame. LOOKING at the image immediately contradicted the
number. A screen-average is not a measurement of the thing you meant to measure.

**The ruling needed:** how bright should a generated floor read? Reaching a legible dark floor (~25%)
needs roughly an order of magnitude, taken from any mix of the biome's `ambient_energy_ceiling` /
`directional_energy_ceiling`, the `floor_tint`, or a brighter tile. This is squarely a P-SHOWN
question — a level the player cannot see is the most complete failure of "the world is the primary
channel" available.

## 3. ~~BLOCKING: the stretch demands a control it never offers~~ — RETRACTED, my method was wrong

**This finding was wrong and is withdrawn.** I reported that the stretch was uncompletable because
the refusal channel demanded an EXTEND terminal that the game never offered:

> `aster: The route crosses an open cut. Work the lit EXTEND terminal first.`

Across fourteen steps the published verb set stayed exactly `[MOVE, HIDE, TAKE LYSATE]`, so I
concluded the composition had a **gating requirement with no reachable supplier**. It does not. The
terminal is there, and the gating chain is well formed. Measured in a live scene:

| Check | Result |
| --- | --- |
| Producer nodes present and visible | `BranchSpanProducer_branch_00`, `_branch_02` |
| Terminal Interactable | label `EXTEND`, enabled, no `required_character`, radius 1.8 |
| Outline target wired (so it highlights AND publishes) | yes, via `_wire_outline` |
| Service vertex from the production resolver | cell **(15, 12)**, walkable |
| Path from the party spawn | **21 waypoints — reachable** |
| Triggered through the real one-shot receipt | `extending → bridged`, gap removed |
| Reachable region after bridging | grows to x = 39, next gate is `generated_cistern_bridge_gap` |
| Controls inside that region | `OPEN FIRST SLUICE` (enabled), `TEND`, `WAIT FOR CLEAR` (staged) |

So the chain reads: work the EXTEND terminal → the cut closes → the region opens to the cistern
bridge → its sluice control is already reachable. That is exactly the shape the port model wants.

**Why I got it wrong, and the lesson that matters more than the finding:** I played entirely off
`player_observation.state.affordances`, and that list is *by design* only what is *currently on
screen, unoccluded, and unfogged* — `_affordance_snapshot()` filters every candidate through
`visible_rect.has_point`, `_render_point_visible`, and `_interaction_hit_is_player_visible`. It
answers "what can I click this instant", never "what exists in this level". I never panned the
camera or walked toward the terminal, so it never entered the list, and I read its absence as
non-existence. **An empty verb list is a statement about the camera, not about the level.**

Two things follow, both now in the method doc:
- Exploration must drive the camera, not just consume the affordance list.
- Reachability is a question for the *navigation resolver* (`resolve_navigation_location` +
  `find_multi_level_path` on the unwarped position), never for the affordance list.

One trap worth recording: this stretch is spiral-**warped**, so a node's `global_position` is in
visual space and comparing it to grid cells is meaningless — it made the terminals look like they sat
off-grid at z = 15/17 on an 80×13 board. The production path unwarps first, via the
`flat_authored_position` meta or `coord_map.to_data()`. Measure through that seam or the numbers lie.

Scope: verified on the default teaching stretch (`generated_teaching_channels_shelter_1_to_2`), the
same family and mechanism as the browser run, not on seed 80713 specifically.

## 4. ~~The instruction banner never goes away~~ — MOSTLY RETRACTED, that is the preview harness

The banner I complained about is `fragment_preview_sequence.gd:3709` -- the FRAGMENT PREVIEW's own
status note, set as `_note_default`. I was playing inside the dev preview shell, so it is the
harness describing the harness, not shipping game UI dressing the world.

H's behaviour is also deliberate and already under test: `real H input hides the optional briefing`
and `H leaves the persistent status surface and current receipt visible` both pass. H is specified
to hide the briefing and KEEP the status surface, so "H doesn't hide it" is the contract working.

What survives: preview chrome that sits across the middle of the play area is still bad for
eyeballing a level in the preview, which is what the preview is for. That is a dev-surface polish
item, not a P-SHOWN violation, and it should be weighed as such.

## 5. The hover consequence is sourced from a QA metadata field — CONFIRMED, measured

Hovering the exit shelter draws **`ENTER SHELTER`** and **`-> Completes once the conscious party is
inside; starts canonical rest only where recovery is needed`**. Traced: every generated node sets
`consequence_preview` from `playable_section.predicted_effect`
(`generated_stretch_chunk.gd:9403`).

`predicted_effect` is QA/design metadata -- it sits beside `failure_prediction`,
`observable_evidence` and `likely_misconception`, which are review fields, not player copy. Using
one as the hover line is a category error independent of taste.

Measured across `data/generated_stretches/*.json`:

| | |
| --- | --- |
| Generated nodes shipping a hover consequence | 36 |
| Of those, longer than 60 chars | **36 / 36** |
| Length: min / median / p90 / max | 83 / 83 / 105 / **144** |

Against the hand-authored register in the same UI: `Bridge the marked downstream gap after a delay`
(45), `Extend or retract every %s drawer` (33). The generated line is 2-3x that, and reads as spec
prose: *"The exact interacting character takes the visible physical load if they are in range and
have a free hand"* (105).

This is player-facing WRITING, which is the director's to set, so it is not being rewritten
unilaterally. The decision needed is the register: (a) emit a dedicated terse player line in the
generator and leave `predicted_effect` to QA, (b) reuse the already-terse authored
`relationship_label` (e.g. `PARTY ENTERS`), or (c) show the verb alone and let the world carry the
consequence, which is the strictest P-SHOWN reading.

---

## What went RIGHT, and is worth protecting

- **The authored intro plays beautifully in a browser.** Peris's room renders fully lit; hovering an
  interactable shows the cursor verb (`// INSPECT //`) *and* the dashed path-preview ribbon;
  right-click commits; she walks; the CARE LOGBOOK triggers and narrates; **F** fast-forwards
  cleanly; the story advances through Monos's dialogue in his exact halting register. Click keeps its
  promise the whole way.
- **Generation from a seed works live in the browser.** Typing a seed and pressing *Play seed* built
  a complete stretch — nodes, resource claims, route markers, three-character party, populated HUD —
  in under thirty seconds, with the world-state event log streaming correctly.
- **Zero GDScript runtime errors** across every run. No `Cannot call method … on a null value`, no
  page errors, nothing in the console but WebGL performance chatter.
- **The overlay stack works**: Aster Data / Peris Flora / Endo Survival toggle independently on F1–F3
  and combine, exactly as the panel claims.

## Method notes for the next run

The harness lives in `play.mjs` (server + boot helper) beside the spec files. A run is: serve
`build/web`, boot Chromium, wait ~40 s for the wasm boot, click **Fragments**, set the seed field,
press **Play seed**. Re-export before playing or you are testing a stale build — `build/web` does not
rebuild itself, and an export five days old will happily hide every fix made since.
