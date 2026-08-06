# The Balancing Basin — level spec

Status: DESIGNED (2026-07-31), director-approved for build. "Balancing Basin"
is a working name — descriptive English; christening is the director's.
Design method citations refer to `docs/DESIGN_METHOD.md`; composition law to
`docs/DESIGN_PRINCIPLES.md` (P-numbers) and the level-authoring panel rules.

## The feeling (rule 1)

Enter on a wide, quiet bowl floor — dwellers grazing in the dark, exits
visible on the far rim. The first fill is dread ON A SCHEDULE: the inflow
header groans, the surface shivers, and everything on the floor — the party
AND the dwellers — has the same few seconds to climb. Mid-level, fear turns
into use: the player stops running from the water and starts scheduling it.
By the exit they read the room like a dockworker reads tides. The curve is
dread → scramble → literacy → mastery.

## One bowl, three maps (rules 3, 12)

A single cistern bowl. The ONE master state variable is the water level —
`LOW / MID / HIGH` — scheduler-committed, never sampled. Each level is a
different map over the same geometry:

- **LOW** — the bowl floor is the map: walkable end to end, dwellers graze
  it, the drain shelf and stash alcoves are reachable. Everything above is
  visible but disconnected (catwalk stairs end in air).
- **MID** — the floor is drowned (kill on contact, same predicate as below).
  The float ring rides up to deck height: debris rafts align into crossings
  that exist at NO other level, meeting the catwalk stairs. The bowl becomes
  a ring-and-spoke map.
- **HIGH** — catwalks only. Floats pin against the rim and stop being a
  path; the water prices everything below. The map is at its smallest and
  the sentry's ground is at its most valuable.

Raising the water is editing the topology (rule 12): cause at the header,
effect across the whole room.

## The rota (P5, panel rules 9/14/15)

The fill cycle is NON-UNIFORM: short window, short window, LONG window,
repeat. Pure data (periods/durations/phases in the .tres), analytic
next-onsets, identical at 1x and 10x, enrolled in
`--test-puzzle-fast-forward-invariance`. Every fill telegraphs four seconds before
onset on its own scheduler tag (header groan + surface shiver, a world-space current
route to the named return shelf, and an offscreen-safe status read).
**One hazard, one predicate:** the flood check that drowns a dweller is the
check that drowns a party member — taught by a SCHEDULED demonstration kill
on a dweller during the first fill (P18), never left to the ecology.

The long window is the strategic prize. Knowing WHICH window is long is
worth a detour; hitting ANY window perfectly is worth a resource. That
asymmetry is the level's market.

## The three branches (rules 15, 16) — error / foresight / resource

Every crossing (floor traverses at LOW, float-ring crossings at MID) can be
made three ways. No branch gates; each buys on its own axis:

1. **Self-timing** — free. Watch the water, go on your own read. Priced in
   ERROR: the windows default narrow, and a mistimed step is a sweep. The
   free path's failures are the advertisement for the other two.
2. **The rota chart** — a priced detour. The chart hangs on the gantry over
   the inflow header, VISIBLE from the whole bowl floor (the tradeoff is
   advertised before any crossing — you can always see that a schedule
   exists). Reading it pays FORESIGHT: which window is the LONG one, so
   waiting converts into scheduling. Execution stays manual — the chart
   widens your margin, it doesn't hold your hand.
3. **Aster's read** — no detour. Logged at the crossing, it makes the
   timing PERFECT: the party is held at the lip and launched on the
   flood→dry transition automatically — the wash_relay FlowTerminal assist
   grammar (`_flow_assist_poll` / `_flow_assist_cross`), promoted to a kit
   verb. (On the spiral the terminals only display the number; the relay's
   terminal is the auto-perfect mechanic the director cited.) In the relay
   it is unpriced; here it is priced as RESOURCE — each log debits Aster's
   stamina from the same closed bar the sprints draw on, with a cooldown on
   re-log (both via existing grammar: `adjust_stat` + a scheduler tag) —
   and scoped to the NEXT onset only: perfection without foresight.

Chart + Aster is the deluxe crossing for players who paid on both axes;
chart + manual is the confident gambler; Aster alone is the impatient
tactician; bare hands is the purist run the fail-forward loop keeps honest.

## Enemies, braided in (rules 11, 13; panel rules 1/3/5/8)

- **Floor dwellers** — drawn from the siderophore set (Sapscraps) so flure
  play stays legal. They graze the LOW floor between the party and the far
  side. The fill EVICTS them: on the telegraph they break for the same
  stairs the player wants (species/behavior to be canon-checked against
  `fauna_roster.md` at build). The hazard is the tool both ways: schedule a
  fill to sweep the floor clear — or mistime one and share a staircase with
  everything else that's fleeing it.
- **The catwalk sentry** — posted above, owning a sightline that matters:
  the gantry approach and the chart landing sit inside its detect radius
  (asserted in the fragment test, panel rule 5). The chart's price is a
  stealth problem, not a lock. Tight hides (Capbage) sit at the gantry
  mouth, honest-tell style.
- **One pressure survives the finale** (panel rule 3): the sentry never
  lures and never drowns — the exit leg is priced at every water level.

Stealth and puzzle share the same ground at the same time (rule 13): the
hide-dash-hide rhythm past the sentry is metered by the same stamina bar
Aster's reads spend, and the dweller eviction runs on the same rota the
crossings do. Two currencies — time and stamina — and every branch is an
exchange rate between them.

## Failure and pricing (P11, rule 14)

A swept character travels WITH the inflow current back to distinct safe graph
vertices on the west `START / CURRENT RETURN` shelf where the party first arrived.
The failure therefore loses understood progress; it never grants an otherwise
unearned east-side advance or reveals a mystery destination. A directional current
trail, involuntary carry pose, named destination, and arrival pulse remain visible
through the authoritative traversal. The character lands mobile with the bar debited.
`restart_on_wipe: true`. Round-trip pricing throughout:
the gantry detour is climbed at one water level and returned under another;
what you cross at MID you re-cross on the way back, and the rota has moved.

## Perception lock (P2) and the shadow (P10)

Registers: **Aster = WHEN** (the rota, the perfect launch) composed with
**Peris = WHERE** through her flora-network register — Seeferns rooted on
the float ring light as one NETWORK, showing which rafts belong to the same
chain before the water proves it (canon-check the species/network read at
build; no mechanical solve-data beyond the network property). Revert either
ability and the level gets strictly harder, not differently flavored.

**The shadow:** the Presented solve rides the LONG window (found via chart
or bought via Aster). The never-hinted Aster+Peris shadow chains TWO SHORT
windows with a mid-water wait on a float — same hazard, same numbers,
strictly harder, blessed with its own playthrough test (never latent).

## Kit inventory (rule 2 — compose; extend only where the verb is missing)

The reusable water-state, moving-platform, route-adjustment, and generation model is documented in
`docs/RISING_WATER_AND_MOVING_PLATFORM_ARCHETYPE.md`.

EXISTS (compose as-is; provenance per the 2026-07-31 recon):
- The **`sump`** (`scene_chunk.gd` `_spawn_sump`, data-spawnable) — the
  portable 3-state water piece: DRAINED/MID/FLOODED pump, float platform,
  reversible ledge inter-level link, penned enemy drowned at FLOODED. The
  showcase Bay C valve/float-bridge/drown is its embedded cousin (walkable
  floats ONLY at MID via dynamic blockers). Their drown is ENEMY-only —
  players are blocked out of the water cells.
- The **`Channel` kit** (`channel.gd`) — analytic cadence (period/dur/
  phase, scheduler-tagged onsets, telegraph), the `hold()` valve verb, and
  the PLAYER-capable sweep: locked external traversal to a chunk-supplied
  dest Callable, hp bite committed on arrival. This is where party
  drown/sweep parity comes from.
- The **FlowTerminal assist** (wash_relay, inline) — the auto-perfect
  crossing (hold-at-lip, depart-on-flood→dry), replay/FF-safe.
- Plus: `exit_shelter`; Capbage/Scarpet; Flure; roam/patrol enemies with
  cross-level moves; the multi-level grid + inter-level links; CrawlTunnel;
  the closed stamina field; the two-lane scheduler.

KIT WORK (each proved in its own fragment BEFORE composition):
1. **Bowl-wide water level as a data-fragment verb** — a `BasinWater`-
   class kit object marrying the sump's committed level state (float
   walkability, ledge links) with the Channel's body resolution (party
   swept + bitten, enemy drowned — one waterline predicate at commit).
   The non-uniform rota needs NO new cadence code. The proving fragment uses
   an 18-second tutorial LOW so a first-time player can read and climb, then a
   4-second pressure LOW and a 14-second mastery/recovery LOW. This is a PHASE
   LADDER—or, equivalently, a dwell-list with prefix-sum analytic next-onsets—
   not a hidden timing exception.
2. **Aster's auto-perfect crossing** — extract wash_relay's FlowTerminal
   assist into a reusable "hold at lip, launch on the next dry beat" verb
   any crossing can consume, priced (stamina debit + cooldown).
3. **The rota chart** — an info surface that renders a window schedule
   (existence visible at distance, content readable up close).
4. **Dweller eviction** — fill-telegraph → break-for-refuge behavior;
   compose from existing FSM verbs (re-anchor `set_roam` / cross-level
   move to a chunk-supplied refuge), one new class max.

DEFERRED: the Sokoban-style cart push for gantry access leans on the push
system still in flight in a parallel session — v1 gantry access composes an
existing priced verb (stealth past the sentry + a climb) instead. Revisit
when the push kit lands.

## Build plan

- **Phase 1 — `basin_fill_proof`** (kit fragment): the bowl, the rota, the
  three maps, drown parity, dweller eviction, sweep-with-inflow. Tests:
  analytic rota inequalities, FF-invariance, demonstration kill, naive
  route fails.
- **Phase 2 — branches**: chart + Aster perfect-launch + pricing asserts
  (stamina 80–98% of the bar on the intended route; marginal value of each
  branch proven by driving all three in the playthrough test).
- **Phase 3 — the Basin**: full composition + sentry + shadow test +
  dressing (the world argues for itself: who balanced this basin, what
  flowed through it, why they left) + registry wiring + preview entry.

Wins go through `exit_shelter`. Working names stay descriptive English.
