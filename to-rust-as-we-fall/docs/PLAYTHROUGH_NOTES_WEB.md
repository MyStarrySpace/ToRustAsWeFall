# Playthrough notes — real browser, real input (2026-08-07)

Method: web export served locally, driven through Chromium with Playwright using actual mouse and
keyboard input — no data-layer shortcuts, no force-fired gates. Screenshots at every beat. Two runs:
the authored intro (Peris's sim) and a **freshly generated stretch** (seed 80713, custom teaching
profile, generated live from the picker's GENERATED SEED control).

This is the first time the game has been played end-to-end in a browser by anything other than a
person, and it found things no headless test can see. Findings are ordered by severity.

---

## 1. HUD/input mismatch: the HUD advertises the wrong mouse button — BLOCKING for a new player

The bottom-centre control read says **`Move`** beside a **LEFT** mouse-button glyph. Movement is
committed with **RIGHT** click. Left-clicking open floor does nothing at all.

This cost four separate attempts to discover, with selection confirmed working in between
(`[MSG ] Selected: Aster`, `[MSG ] Selected: Peris` appear in the console while the party stays put).
A new player would left-click the floor, see nothing happen, and reasonably conclude the game is
broken before ever moving a character. Everything downstream of movement is unreachable until they
guess the other button.

Confirmed both ways: right-click on open floor moves and disperses the party correctly; left-click
never produces a move event.

## 2. Generated-stretch geometry renders SOLID BLACK on the web build

Every floor and wall of the generated stretch draws as a flat black silhouette against the
background. Props and flora render in colour (green plants, the amber cache, character capsules), and
the authored Peris room in the same build renders **fully lit and textured** — so this is specific to
generated geometry under the GL Compatibility renderer that the web export uses, not a global
lighting failure.

The level is technically playable but unreadable: you cannot see floor edges, elevation, or where a
walkable surface ends. Given P-SHOWN — the world is supposed to be the primary channel — a black
level is the most complete possible failure of that law.

## 3. Could not complete the stretch: the party never reaches the exit shelter

After ~3 minutes of real play with all three characters group-selected (portrait borders confirm the
selection), the run state stayed at `route_phase: "unstarted"` with `completed_nodes: []`. Individual
right-clicks on open floor move characters fine; right-clicks aimed at the shelter and along the
route toward it did not advance the party there.

Not yet diagnosed. Two candidates: the shelter is an Interactable rather than floor, so a move aimed
at it may need the click-to-walk-then-trigger path rather than a raw ground move; or group moves are
refused where a single-character move succeeds. Worth noting the party DID split naturally during
single-selection play, so per-character movement is healthy.

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
