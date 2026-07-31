# Playtest Personas — the roster, the pattern, the asserts

Automated players with the reflexes of REAL player types, driven through the
data layer with no meta-knowledge. A persona is not a walkthrough: it is a
small set of reflexes plus ONE invariant that must hold no matter what that
playstyle does. Personas earn their keep by finding real bugs — Dean's
mindless tag-re-presenting found the spent-one-shot boundary scanner that
left the lockout chase unstartable after a wipe.

**The naming law (director's): personas are REAL personalities**, not
invented archetypes — the personality IS the spec. Dean Takahashi is famous
for fumbling the Cuphead tutorial; TheSpiffingBrit for videos breaking
"perfectly balanced" games; Twitch Plays (Pokémon) for a thousand
conflicting inputs steering one character; Shesez (Boundary Break) for
going out of bounds to see where the world's edges give. Name a new persona
after the real player whose reflexes it borrows.

**The pattern:** give a persona a reflex a real player has, watch what it
hits. Every choice a persona makes is TICK-HASHED (never `randf`, never the
wall clock) so a found bug replays identically.

**Two harnesses:**
- `--test-chase-probe` — the scripted-level pass (lockout chase): the
  original streamer roster (panic_sprint, curious_clicker, door_camper,
  offshoot_stumbler, tyreg_accepter, competent_runner, dean_takahashi).
- `--test-persona-probe` — the SYSTEMS pass (fragments with real
  economies; enrolled: basin_fill_proof, push_lab, channels_wash_intro,
  zone_transition_lab — a LIVE seeded generated stretch, seed 431).
  The roster below runs here. New fragments with prices enroll by adding a
  row. Where a fragment carries KNOWN ledger items awaiting the director's
  pick (the wash intro's exit gating), the probe asserts only undisputed
  invariants and RECORDS the contested behavior as a ledger line.

## The systems roster

### TheSpiffingBrit — the exploiter (the anti-Dean)
Tries to beat the game by BREAKING it: hunts degenerate loops, abuses
anything reusable, routes around gates rather than through them, and repeats
any exploit that pays until it stops paying.
- **Reflexes:** re-triggers every priced interactable as fast as the game
  allows; deliberately rides hazards to see if the punishment is secretly a
  ride; probes the win condition early and often; never takes the intended
  route when a cheaper-looking one exists.
- **The assert:** no exploit beats the authored price. Cooldowns cannot be
  spammed past their rate; a hazard bite is paid EVERY time (no refractory
  immunity across windows); knowledge surfaces never mutate stats;
  completion cannot occur before the earliest legal window. (Sanctuary rest
  heals are CANON free — the exploit scan never flags authored sanctuary.)
- **Scales by registry, not by hand:** his generic pass DERIVES its probes
  from the fragment's own registries — DOUBLE-DIP every interactable (second
  synchronous poke must never re-pay), COOLDOWN-rate every `assists()` read
  console, RIDE every `channels()` footprint twice (the wash must displace,
  never enrich). Registering a fragment enrolls it; no per-fragment code.
  (The wash intro keeps a hand-authored pass for its ledger-pending items.)

### DSP — the screen-space chaos player
Named for the streamer legendary for blaming the game — and for triggering
bugs by doing everything except the intended thing. Alone among the roster
he plays the INPUT layer, not the data layer: raw synthetic mouse and
keyboard through the REAL event pipeline. Odd clicks (left/right/shift/
double), drags across the HUD band and panel seams, exact screen corners
and edges, key mashing, and ESC pause-menu spam. This is the persona for
the director's law: *a lot of bugs come from clicking in odd places,
dialogue, UI — not the happy path.*
- **The assert:** the UI layer cannot WEDGE the game. The tree is never left
  paused (a pause-menu leak is a bug; a player-chosen SPACE pause is not —
  resume it and continue), bodies and stats stay legal through the storm,
  and a settle leaves no stuck state. Complements the windowed
  `--test-player-contract` sweep (which pixel-verifies hover/click on
  desktop); DSP runs headless so it rides in the bulk probe.

### DeanTakahashi — the fumbler
No strategy, pure reaction (ported from the chase roster to the systems
pass): flees the nearest threat at a tick-hashed wrong-way angle, ignores
telegraphs, mashes whatever interactable is closest (right character or
not), repeats his last action, and re-attempts after every disaster with
zero adjustment.
- **The assert:** the game never becomes UNSTARTABLE or soft-locked under
  pure fumbling. Wipes restart clean (the world re-arms), stats stay sane,
  and the simulation keeps ticking.

### TwitchPlays — the input storm
A thousand conflicting hands on one controller: starts everything and
finishes nothing — move then stop, queue a push then cancel it, click an
interactable then walk away mid-dwell, re-order every beat. The
state-machine race hunter.
- **The assert:** the storm leaves no wreckage. After a settle beat: no
  character is stuck in an external traversal, no push plan is orphaned,
  every body stands on a legal cell, stats are sane, and the scheduler
  still advances.

### Shesez — the boundary breaker
Goes where the camera crew goes: clicks outside the grid, into walls, onto
cells that exist only on the other floor, at hazard edges, and walks the
perimeter of everything.
- **The assert:** the world's edges hold. No command ever lands a character
  out of bounds or on a cell its floor does not allow; refused commands
  refuse cleanly (no partial state).

### Skumnut — the souls challenge runner
Incredible reflexes, pattern memorization, deep fluency in affordances and
tropes — and no head for overall puzzles or strategy. Watches the hazard
until he KNOWS its rhythm (empirically — he never reads a chart or logs a
console), positions before the window, and reacts to the state flip within
a beat.
- **Reflexes:** observe safely through full cycles, recording the pattern;
  stage at the crossing mouth; launch on REACTION the instant the window
  opens; never touch an instrument.
- **The assert:** reflex play is FAIR and sufficient. The observed pattern
  repeats exactly (a telegraphed rhythm never drifts — determinism as
  fairness), a reaction-timed crossing fits the window, and the level is
  BEATEN with zero instrument uses — the free branch genuinely wins
  (instruments sharpen, never gate, proven by play).

### PirateSoftware — the negative control
Stands in one place with the party and does absolutely nothing, forever.
Every experiment needs one.
- **The assert:** inaction never wins, and the world is honest about time.
  Doing nothing never completes a fragment; where pressure is authored, it
  LANDS on the idlers (the fill bites them); where nothing is authored to
  move, NOTHING moves (idle crates hold their exact cells — the world never
  drifts on its own). The full form — night falls and the idle party dies —
  enrolls when a night-threat fragment joins the roster.

### Prod — the variety streamer
Average skill everywhere, community first: he tries whatever looks
exciting, cool, or reaction-worthy, strategic or not — and never repeats a
mistake, because repeats bore chat.
- **Reflexes:** a novelty queue over every action the fragment offers
  (touch it, swim it, cross it, push it); anything that hurt or refused is
  blacklisted and never tried again.
- **The assert:** novelty-seeking play is safe coverage. He touches most of
  what the fragment offers without ever repeating a bad action, and the
  world holds through the tour.

### EazySpeezy — the speedrunner
Hunts leverage points: anything that shortens the run is tech — the assist
console's auto-launch, sprint on the crossing, the tightest legal line to
the win. Skips everything optional.
- **The assert:** the pacing floor holds. The fastest legal clear still
  cannot beat the authored minimum (no completion before the earliest legal
  window), and his time is LEDGERED as the fragment's empirical floor.

**Future candidates (real personalities, not yet built):** Jirard the
Completionist (touches and re-touches EVERYTHING — the re-arm/double-count
hunter).

## Invariants checked for EVERY persona, every beat
- Stats sane: hp/stamina/ATP finite and within [0, max].
- Bodies legal: every idle character stands in-bounds on a cell its grid
  level allows (moving/carried bodies exempt until they land).
- Time flows: the gameplay scheduler tick strictly advances.

## The two breadth sweeps (scale without per-fragment code)
Both are OUTSIDE --test-all (they're the wide net, not the fast feedback
loop) and both reuse the generic registry-derived probes, so neither needs
authoring per target:
- `--test-persona-seed-sweep` — the triad+DSP play a FRESH generated stretch
  per seed (5 seeds, ~20s). Run before touching generation; the main probe's
  seed 431 is the canary, and generation bugs hide in the seeds nobody
  booted.
- `--test-persona-fragment-sweep` — enumerates EVERY `data_fragment` entry
  in `PREVIEW_ENTRIES` and probes each with the triad+DSP. Because the
  exploit pass reads the fragment's registries, a newly registered data
  fragment is swept with zero new test code. This is the scalability
  guarantee: coverage grows with the content, not with the test file.

## Sufficiency: headless personas vs a real browser playthrough
Calibrated 2026-07-31 by driving the basin in Chrome (wasm export,
Playwright, the `scripts/serve_web.py` recipe) alongside the headless probe.

WHERE THEY AGREE (and did): the wasm build runs the identical data layer —
the browser session reproduced exactly what the personas assert headless
(walking into a grazer's range → spotted → pursuit → mauled; the fill on
the rota clock; the float road rising at MID; fail-forward leaving the
party alive), at 60fps with zero console errors.

ONLY THE PERSONAS COVER: scale (80+ runs across personas/fragments/seeds
in ~90s vs one 72s browser session), assertable internals (stat books,
cooldown math, cell legality, soft-locks, FF/replay invariance), and
adversarial breadth.

ONLY THE BROWSER COVERS: rendering truth (the compat/sRGB bug class is
invisible headless — the fog-veil bug proved it; this pass verified the
SHIFT-reveal outlines composite correctly in Chrome), the real OS→browser→
canvas input path (RMB move + held SHIFT both landed), platform truth
(~14s local boot for a 141 MB pck — a shipping concern; audio worklets;
the main menu swallows `--preview` args, so a patched page must click
Fragments to route), and unscripted emergence.

THE VERDICT: sufficient AS LAYERS, none alone. The probe is the bug net;
the windowed player-contract sweep is the pixel/input net on desktop; the
scripted browser drive is the platform net — run it per flagship fragment
before anything ships to web. Web polish items on file: pck size/boot,
water-surface legibility at MID under compat (emissives clip flat on web),
menu vs `--preview` arg routing.

## Adding a persona / an enrollment
One row in the PROBE_PERSONAS table (reflex callable + assert callable) or
one row in PROBE_FRAGMENTS (fragment id + per-fragment price facts the
exploiter asserts against). Keep each persona to a few reflexes a REAL
player type has — a persona that plays well finds nothing.
