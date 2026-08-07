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

## 2. Generated-stretch geometry renders SOLID BLACK on the web build

Every floor and wall of the generated stretch draws as a flat black silhouette against the
background. Props and flora render in colour (green plants, the amber cache, character capsules), and
the authored Peris room in the same build renders **fully lit and textured** — so this is specific to
generated geometry under the GL Compatibility renderer that the web export uses, not a global
lighting failure.

The level is technically playable but unreadable: you cannot see floor edges, elevation, or where a
walkable surface ends. Given P-SHOWN — the world is supposed to be the primary channel — a black
level is the most complete possible failure of that law.

## 3. BLOCKING: the stretch cannot be completed — it demands a control it never offers

Replayed properly off the observation bridge (`?e2e=1` → `player_observation.state.affordances`),
choosing by VERB and clicking the published screen point, with `move_refusals` read after every act.
Fourteen steps, thirty-odd distinct ground targets, the goal marker tracked the whole way.

The game states the gate clearly and diegetically, through the refusal channel:

> `aster: The route crosses an open cut. Work the lit EXTEND terminal first.`
> `aster: No route to that deck.`

**But an EXTEND terminal is never offered.** Across all fourteen steps the available verb set stayed
exactly `[MOVE, HIDE, TAKE LYSATE]`. No terminal, no extend, no branch-producer affordance ever
appeared — and `click_targets.exit_shelter` stayed `visible:false` throughout. `branch_00` reports
`blocked_cells (16,4) (16,5) (16,6)` with `bridge_collision_enabled: false`, i.e. the cut is in place
and was never bridged.

So the composition has a **gating requirement with no reachable supplier** — the exact failure the
port model names as a hard error (a deficit on a progress-gating input), and the same family as the
fail-open branch gate fixed earlier the same day. The player is told what to do and given no way to
do it. Seed 80713, custom teaching profile.

This is the finding that matters most from the session: every headless gate passes on this stretch —
solvability, curriculum, spec integrity, replay — because they check the SPINE, and the spine is
satisfiable. What is not satisfiable is the *player's* route to the control that opens it.

## 4. The instruction banner never goes away and covers the level

*"All three characters start topped off. Run and cast abilities spend stamina; ATP pays for shelter
rest unless an experimental scarcity preset is selected."* sits across the middle of the screen for
the entire session. Pressing **H** (Hide) removes the control-key list but not this banner, and not
the CARRY / CONSUME panel bottom-left. Both occlude level geometry permanently.

## 5. Explanatory prose drawn over the world — a P-SHOWN violation in the shipping path

Hovering the exit shelter draws, in large text across the level: **`ENTER SHELTER`** and
**`-> Completes once the conscious party is inside; starts canonical rest only where recovery is
needed`**. That is a rules explanation rendered into the play space. Under P-SHOWN the shelter should
*show* that it is a shelter and *show* who is inside it; a sentence describing its completion
semantics is the precise thing that law exists to stop. It is also unreadable-by-design clutter at
this text size over black geometry.

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
