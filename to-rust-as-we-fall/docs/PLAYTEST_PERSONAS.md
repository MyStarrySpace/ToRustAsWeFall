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

## The decision harvest (AI play → persona decision space)
The third leg beside the solver (optimal) and the personas (biased): the AI
plays a fragment FOR REAL and every decision is recorded with its rationale
and the observed state. Harness: `--ai-playthrough` (env: AI_PLAY_FRAGMENT /
AI_PLAY_DECISIONS / AI_PLAY_TRACE) executes a decision file and dumps a
rich final observation; the AI plays by GROWING the file — run, read,
decide, append, rerun (the deterministic prefix makes this honest). Traces
live in `data/playthroughs/decision_traces/` and distill into DECISION
NODES that slowly build out the personas' decision space.

First harvest (pump_hall, 2026-07-31 — cleared in 31 decisions, two real
mistakes, both priced):
1. **Observe from cover first** — hold at a MEDIUM hide and sample the
   walks before committing to any route. (Seeds: Skumnut.)
2. **Two samples are not a loop** — I extrapolated a patrol's reach from
   two observations and dashed through its detect envelope: spotted twice,
   75 hp. Patrol reach = walk line + detect + PURSUIT; observe a full loop
   or buy the window. (Seeds: Skumnut's observation discipline; also the
   exact failure a chart/read branch exists to sell past.)
3. **Break on recover** — a striking enemy's recover beat is the disengage
   window; run THEN. (Seeds: a future tactical node.)
4. **Exposure beats stamina on watched ground** — run the crossing, walk
   elsewhere; never burn a member's bar below the next crossing's cost.
   (Seeds: EazySpeezy/Skumnut pacing.)
5. **A Capbage hides ONE body** — my slot spread parked two members beside
   the leaf. A party needs a leaf each or staggered turns. (Also a
   level-design lint candidate: party fragments want party-sized hides.)
6. **The far post IS the window** — when a room's owner stands at its far
   post, go immediately; waiting for "better" spends the window.
7. **A commit needs a settled, SELECTED body AT the console** — three
   refusals taught this one rest: mid-stride bodies cannot bed down, the
   actor must be in the active party, and must stand within the
   interaction radius. (Already encoded: Skumnut settles; Dean mashes the
   wrong actor on purpose.)

THE LIBRARY-DRIVEN STRATEGIST (built): the harvested nodes live in
`data/playthroughs/decision_library.json` and a policy engine in the runner
plays them — sense from the fragment's registries (threats/cover/objective),
act by the nodes (observe-from-cover until walks stop surprising, cross on
the far-post window, run funded watched legs, break to cover on commitment,
commit rests settled/selected/adjacent). Skumnut IS this strategist
everywhere except the basin (which keeps his deep scripted proof); he runs
in the fragment sweep on every registered fragment with zero per-fragment
code. Completion is RECORDED, not required — an honest strategist retreats
where a specialist gate blocks him; each recorded failure names the next
node to harvest.

SECOND HARVEST (sprint_gap, played IN CHARACTER as EazySpeezy — capturing
each actor's decision style, not just decisions): five new nodes —
read_the_heading (the far post is only a window when the walk faces AWAY;
his launch into the turnaround cost a windup at arm's length),
caboose_pays_more (the slowest bar sets the party sprint), sacrifice_is_
not_a_timesave (the downed walker cost a 75hp retrieve round-trip + revive
wait — always slower than the window skipped), pursuit_defeats_medium_cover
(a scarpet sheds watchers, not pursuers), wake_before_group_rest — RETIRED same
day: the director picked the fix (the party rest now ABSORBS an in-shelter
solo rester), and the absorb GREENED an inherited suite red (capbage
retrieve's rest) plus exposed that resets must wake bedded members. A
harvested wart became a rule change within hours — the loop working.

THE HARVEST'S BIGGEST CATCH SO FAR — a determinism leak in the harness
itself: running one decision file twice produced two different worlds. The
preview host's _process advances the scheduler by REAL frame delta, so the
boot-settle frames injected wall-clock jitter that forked knife-edge
timelines. Fixed for AI playthroughs (the tree pauses before boot; all sim
time flows through explicit headless_advance; verified identical across 4
runs). The persona probes' own per-beat frame awaits carry the same jitter
class — their asserts are threshold-robust by design, but the "replays
identically" guarantee currently holds for AI playthroughs, and hardening
the probes the same way (where input frames aren't needed) is on file.

## Adding a persona / an enrollment
One row in the PROBE_PERSONAS table (reflex callable + assert callable) or
one row in PROBE_FRAGMENTS (fragment id + per-fragment price facts the
exploiter asserts against). Keep each persona to a few reflexes a REAL
player type has — a persona that plays well finds nothing.
