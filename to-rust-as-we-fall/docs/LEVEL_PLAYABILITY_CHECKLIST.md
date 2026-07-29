# Level Playability Checklist — lessons toward one-shot levels

Director's charge (2026-07-29): *"write whatever you need to avoid making these same
mistakes again. Our goal in the future would be to one-shot complete, fun levels with
systems thinking principles to assist in level design."* This page is the distilled
failure ledger from the wash_ascent build — every rule below was violated once and
caught late. Read it WITH `DESIGN_PRINCIPLES.md`, `SYSTEMS_THINKING_PUZZLE_STANDARD.md`,
`ECOLOGY_COMBOS.md`, and the level-authoring skill before building; run its checks
before calling any level done.

## 1. "Green" is not "playable" — play it before shipping it

Data-layer playthrough tests prove SOLVABILITY; they force-fire gates, teleport
actors, and never click anything. Every wash_ascent playability failure the director
hit in real play was invisible to a green data-layer suite:

- The flure that "worked" in tests never fired from a real right-click (three stacked
  causes: the strict source validator refused settle-motion arrivals; a superseding
  carry silently killed the committed walk; the interaction stop-ring parks farther
  than the validator's reach).
- The test harness itself frame-mixed (parked characters at RENDER coordinates
  through a DATA api) — only visible on a warped scene.

**Checklist:** before declaring a level done, (a) the data-layer playthrough test,
(b) the windowed `--test-player-contract --contract=<id>` sweep, (c) at least one
probe that drives the level's KEY verb through the real click chain
(`interaction_requested` → walk → arrival → trigger) from a legitimate player
position. A commit-red in the contract sweep is a playability bug, never noise —
the harness now dumps party data positions on every commit failure.

## 2. One frame to rule the data layer

On warped scenes (coord_map) every position is either DATA (flat) or RENDER (world)
— and every API is one or the other. Every frame-mixing bug shipped silently until
something walked to garbage:

- `GameState.data_frame_bounds` is the permanent tripwire: set it in every warped
  chunk; any data-layer move command outside the authored frame warns loudly.
- Rules of thumb: `global_position` is RENDER; `gs.get_position` is DATA;
  anything crossing the boundary goes through `coord_map.to_world/to_data` exactly
  once. Outline/auto-wire collection must use WARPED positions (`_wire_warped_outlines`
  pattern); harness teleports must use DATA.

## 3. The world's readability is structural, not decorative

- **The floor is the read.** Hazard ground and safe ground are DIFFERENT MATERIALS
  (wash spans = iron sluice beds, safe ground = wood planks). Never mix materials
  decoratively — a floor pattern either encodes a truth or it's noise.
- **Hazard spans sit on the tile grid** so the material boundary is exactly the
  kill-predicate boundary. If spans and tiles can't align, retune the spans, not
  the read (integer spans alone weren't enough; grid-ALIGNED spans were).
- **The visible effect covers exactly the danger** (water bands = integer arc
  pieces = the flood edge IS the kill edge).

## 4. Encounters must be answerable as played, not as scripted

- An enemy that becomes unlurable once aggroed must never hold ground the player
  must occupy (the cut gap-sentry sat in the waiting room; only un-alerted enemies
  take a Flure's bait).
- Lures need RELAY DISTANCE: the flure stands where firing it doesn't enter any
  watch, and its park point pulls enemies AWAY from the player's lane — a park on
  the flure itself drags the threat into the party point-blank, where distraction
  can't save them.
- Measure watch radii against every position the design EXPECTS the player to hold
  (waiting spots, control stands, work dwells) — cooperative parking drifts bodies
  ~a cell, so leave margin.
- Boundary-inclusive hazards bite at their exact edges: spawns, roam rings, and
  wait spots keep ≥0.3 margin off every inclusive boundary (a sentry whose roam
  ring TOUCHED s1 washed itself to death unattended; the party spawn sat exactly
  on s0 and an idle player was swept at boot).
- Every control stands on ground that does not pay the hazard the control
  addresses (valve/terminal in the dry gaps).

## 5. Player intent is sacred across interruptions

- A committed interaction must survive being interrupted: the coordinator re-drives
  the walk after a superseding carry (sweep/knockback/ride) instead of completing
  at the wrong spot; strict validators tolerate the arrival reality
  (stop-ring + cell parking ≈ interaction_radius + ~0.85) and retry once motion
  settles. "The click keeps its promise."
- Scenario re-arms reset EVERYTHING: `Enemy.reset_to_home()` (a polite set_roam
  leaves mid-pursuit enemies chasing ghosts with old damage across resets).

## 6. Systems thinking is the design method (see the CLAUDE.md rule)

Compose the canon systems — fauna grammar, flora incl. the network property,
canonical casts, kit objects — and let the level's depth be their interactions
(the finale here: the flure's doomed pull crossing the wash IS the demonstration,
the timing lesson, and the pad-clearing in one composed beat). If information or
behavior is missing, the canon system that owns it either exists (use it), is
planned (wait or ask the director), or the need is imaginary. Never bridge with an
invented mechanism; `--test-canon-mechanics` lints the enforceable slice.

## 7. The one-shot flow (assemble in this order)

1. Pick the composition from ECOLOGY_COMBOS / ENVIRONMENT_ELEMENTS; read the
   canon cards for every species/flora involved.
2. Author spans/zones ON the tile grid; floors encode danger; controls on safe
   ground; spawns/anchors off inclusive edges; one shelter per stretch + the
   no-soft-lock start region.
3. Price it by arithmetic (dry windows vs slowest walker; naive routes' arrival
   windows sit ON first onsets so sprint AND run-rush provably fail).
4. Wire `data_frame_bounds`, outlines (post-warp), and the fragment loader rows.
5. Tests in the same change: playthrough (pricing asserts + naive-fails + the
   composed solve + zero-sweep clean route + wall-time ceiling), the mech suite,
   FF invariance enrollment for timing puzzles.
6. Contract sweep + real-click probe of the key verb + captures (stage stills via
   the `_phase` sentinel; honest audit = hunt what shouldn't be there).
7. Only then: captures for the artifact, commit, picker row to the top.
