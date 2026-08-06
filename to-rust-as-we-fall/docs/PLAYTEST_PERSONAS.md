# Playtest Personas — the roster, the pattern, the asserts

Automated players with the reflexes of REAL player types and no meta-knowledge.
A persona policy receives only the complete validated `player_observation_v1`;
it cannot supplement that observation with transforms, node names, authored
routes, mechanism state, completion flags, or solver data. An approval run
executes those choices through shipped player-facing commands or input. A
persona is not a walkthrough: it is a small set of
reflexes plus ONE invariant that must hold no matter what that
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

## Approval evidence boundary (hard rules)

Persona quality and control-surface fidelity are separate axes. The persona
policy answers **what a player would choose and why**. The executor answers
**whether that choice traveled through the same public boundary available to
the player**. A convincing Dean, Skumnut, or EazySpeezy decision does not make
an internal state edit into a valid playthrough action; conversely, perfect
mouse synthesis does not make a poor persona policy representative.
If a player cannot perform the same action through the shipped controls from
the same authored state, it is not playthrough evidence.

The following rules apply to every run offered as persona, playthrough, level
approval, or release evidence:

- Every world-changing action uses the shipped keyboard/pointer, controller,
  touch, or player-command boundary. Read-only observation may inspect public
  state after the action, but a test that calls an internal consequence
  callback, singleton movement helper, mechanism method, or state setter is a
  focused diagnostic, not playthrough evidence. Current promotable Native/Web
  persona actions require a mechanically issued keyboard/pointer ledger from
  the shipped driver. `player_command` is limited to passive wait; controller
  and touch remain reserved/nonpromotable until equivalent issuance and
  presentation-proof contracts exist.
- A group verb remains one group verb. Rally, party transfer, or another
  collective intent may not be secretly decomposed into singleton selection
  changes and one command per member. Rally is exactly one held gesture over
  every portrait visible in the HUD roster, and `select_party` binds that same
  exact full roster. If any visible portrait lacks a shipped input binding, the
  whole action fails closed before input or movement.
  The run must prove the production verb's membership, per-member
  acceptance/refusal, and completion behavior. Group acceptance is all-or-none:
  an accepted receipt requires every intended member to be accepted by that one
  event; otherwise the whole command must visibly refuse without movement and
  the trace is ineligible for policy learning.
- Direct gameplay-state mutation is forbidden during the measured run. This
  includes assigning positions, levels, stats, or mechanism phases and using a
  snap/teleport helper to bypass travel. The only teleport that counts as play
  is an authored portal entered through its production interaction/mechanic.
- Fixture-only staging and reset are allowed only in an explicitly named setup
  or teardown quarantine. Their events, movement samples, elapsed time, and
  resulting proximity cannot count toward the playthrough claim. Establish a
  fresh evidence baseline after setup and before the first player action.
- Every accepted or refused movement/state-change request must be observable to
  the player. Acceptance needs an appropriate visible/semantic start, progress,
  or consequence cue; refusal needs a player-facing reason or refusal cue. A
  changed internal value, input receipt, or logged return code alone is not
  feedback and cannot make a decision eligible. Move/Rally proof must bind the
  exact visible target and intended portrait tokens through a monotonic causal
  presentation lineage; camera drift or an unrelated generic cue is not proof.
- Passive waiting is still observed end to end. A validation-only event cursor
  may audit authoritative changes after the fact, but it is not policy input and
  does not turn the wait into issued production input. Any such change requires
  a new rendered causal cue; player-facing forced movement requires active and
  arrival cues on the exact affected opaque portrait/body binding.
- Optional briefing/help text is not a feedback channel. A persona may hide it
  with the shipped `H` control before measured play; command receipts,
  acceptance/refusal, movement progress, and consequence cues must remain
  player-observable elsewhere and must still be recorded in the trace.

Headless policy tests may validate pure decision-tree selection and static
authority boundaries at scale. A run that executes persona actions is Windowed
or Web: pointer routing, held gestures, rendered visibility, and player-facing
feedback are part of the evidence and cannot be upgraded from headless truth.

**Two harnesses:**
- `--test-chase-probe` — the scripted-level pass (lockout chase): the
  original streamer roster (panic_sprint, curious_clicker, door_camper,
  offshoot_stumbler, tyreg_accepter, competent_runner, dean_takahashi).
- `--test-persona-probe` — the Windowed approval pass. Its release contract
  boots the authored Basin for the fixed Dean Takahashi/EazySpeezy by
  repeat-0/repeat-1 Native cohort, observes only full `player_observation_v1`
  snapshots, executes shipped pointer/keyboard gestures, and records
  hash-chained v3 decisions. The Web release cohort independently repeats the
  same matrix in Chromium. Additional fragments/personas enroll only after they
  use that same observation, execution, goal, and cohort boundary. This is the
  required contract, not a claim that a fresh full Native or Web cohort is
  currently green.

The Native gate uses an artifact-owned clean Godot `user://`. The Web gate uses
a fresh export, Playwright browser context, and run-owned artifacts. Old saves,
settings, browser storage, traces, or library entries cannot satisfy either
cohort.

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
he requires the raw DEVICE-input layer rather than the player-facing semantic
command layer: synthetic mouse and keyboard through the REAL event pipeline.
Odd clicks (left/right/shift/
double), drags across the HUD band and panel seams, exact screen corners
and edges, key mashing, and ESC pause-menu spam. This is the persona for
the director's law: *a lot of bugs come from clicking in odd places,
dialogue, UI — not the happy path.*
- **The assert:** the UI layer cannot WEDGE the game. The tree is never left
  paused (a pause-menu leak is a bug; a player-chosen SPACE pause is not —
  resume it and continue), bodies and stats stay legal through the storm,
  and a settle leaves no stuck state. Complements the windowed
  `--test-player-contract` sweep (which pixel-verifies hover/click on
  desktop). The current DSP implementation remains in the legacy diagnostic
  quarantine; it does not become persona evidence until its policy reads the
  shared presentation-only observation schema on Windowed/Web.

### DeanTakahashi — the fumbler
No strategy, pure reaction (ported from the chase roster to the systems
pass): flees the nearest threat at a tick-hashed wrong-way angle, ignores
telegraphs, mashes whatever interactable is closest (right character or
not), repeats his last action, and re-attempts after every disaster with
zero adjustment.
- In the Basin approval run, Dean periodically attempts a pointless held-RMB
  Rally toward an arbitrary visible floor target. The policy decision is the
  attempt: either an authoritative acceptance or an exact zero-event,
  whole-party visible refusal can support that node. A mixed-member result,
  partial movement, or silent refusal is ineligible evidence.
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

## Legacy breadth diagnostics (not persona evidence)
`--test-persona-seed-sweep` and `--test-persona-fragment-sweep` are retained
as compatibility diagnostics while breadth coverage is rebuilt on
`PlayerObservationController`. They read private registries, exact simulation
state, and/or advance the scheduler directly. The test manifest therefore
classifies both as `diagnostic`; their assertions can find mechanism bugs, but
their runs cannot approve a level, claim human-playable coverage, create v3
persona evidence, or update the decision library.

## Sufficiency: persona evidence and a real browser playthrough
Headless decision-tree checks and legacy diagnostics never substitute for a
Windowed or Web persona run. Browser evidence must independently exercise the
exported build's visible controls and record compatible v3 provenance. Native
and Web each require their own complete, recomputable cohort; one platform can
never attest the other.

The historical 2026-07-31 comparison below predates this boundary and is
retained only as diagnostic context; its old headless persona runs are not
current approval evidence.

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
The canonical harvest runs through `PersonaPlayerController`: policy receives
only the complete `player_observation_v1`, sends decisions through
`AgentPlayerInputDriver`, and records a `persona_decision_trace_v3` chain. The
compatibility `--ai-playthrough` entry point still executes old
world-coordinate/named-target scripts for bug reproduction, but it is explicitly
a legacy diagnostic; its JSONL cannot seed or update a persona tree.

Persona policy conditions do not depend on screen-sort array indexes. Each
observation derives sorted, de-duplicated exact visible affordance verb and
consequence lists from the current presentation. Ladder, console, and shelter
candidates use exact membership in those lists. A fumbler may still click an
unrecognized prompt such as `READ ROTA CHART`; that decision remains trace
evidence but emits no guessed or fallback learning candidate.

Every v3 decision stores the exact observation before input, canonically
de-duplicated observations from the command's presented frames in first-seen
order, and the exact observation after settling. That before/samples/after
sequence must remain chronological. It is hash-covered together with
persona/rule/rationale and the production input receipt. Callers do not author
feedback or outcome. The trace
writer derives them from visible presentation deltas and the input receipt, and
the reader and distiller recompute them. An interaction result must be visible,
newer than the pre-click serial, and bound to the opaque token of the exact
affordance visible before the click. Other-target or stale results are not
evidence. The writer likewise derives each supported persona goal from the
persisted observation sequence; a caller cannot assert its own goal proof.
Move/Rally proof additionally follows a monotonic presentation lineage bound to
the chosen target and exact HUD portrait tokens; a camera delta or unrelated cue
cannot establish causality.
Production acceptance is not revoked by a later Basin sweep or other authored
interruption. Such a command records the exact visible terminal lineage
`accepted -> progress -> interrupted`, retains `accepted: true`, and supplies a
non-empty stopped-short reason. The decision is settled but not demonstrated:
it cannot advance a successful-arrival policy, contribute support for that
expected result, or be mislabeled as either a refusal or an arrival.

Traces with direct mutation, singleton movement disguised as a collective verb,
hidden target-addressed actions, or missing visible acceptance/refusal feedback
are quarantined and cannot update `data/playthroughs/decision_library.json`.
The hash-covered run summary must state both derived
`trace_complete: true` and `persona_goal_reached: true`; a locally successful
decision from an interrupted, budget-exhausted, or failed run contributes zero
support even when the same partial prefix repeats.

Promotion additionally requires a platform-local
`persona_strict_invocation_manifest_v1` covering exactly Dean and Eazy at
repeat indexes 0 and 1. Each trace's current v3 validation receipt embeds that
manifest and binds its run, repeat, versioned authored-content identity,
separate gameplay-build identity (`gameplay_build_fingerprint_schema` plus
`gameplay_build_fingerprint`), summary hash, decision count, completion, and
goal. The distiller reconstructs the manifest
from all four supplied traces. A filtered, interrupted, duplicate,
missing-member, mixed-content, stale, failed, or pre-attestation cohort is
diagnostic-only; a later failed receipt revokes an earlier green one. Native and
Web form independent cohorts, so success on one platform cannot stand in for
the other.

Authored-content provenance is a versioned `(schema, SHA-256 digest)` identity.
Authored fragments hash portable resource bytes; generated layouts hash their
canonical semantic specification without runtime/platform metadata. Repeated distinct
full-goal runs on one content identity can promote a fragment-scoped node. A
global node also needs support from distinct content identities, so repeat boots
of one layout cannot masquerade as generality. Gameplay-build identity uses
`gameplay_build_resource_set_bytes_v1` and is recorded separately for the
executable/export that supplied mechanics; it does
not count as content diversity, and behaviorally different builds cannot pool
evidence. All v2 traces and existing v2 library provenance remain readable
diagnostics but are inadmissible and non-executable until fresh v3 cohorts are
distilled.

Tree updates remain conservative: identical normalized decisions increase
support and add provenance; a novel node is proposed for review rather than
silently changing a persona's policy. The current trees are partial, bespoke
policies, not a generalized non-AI player. Bulk generated-level replay from
level observations is the intended future use once enough eligible nodes and
actions have been enrolled and validated.

Historical pre-v2 harvest notes (pump_hall, 2026-07-31 — useful design
context, but not eligible tree evidence):
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

THE BULK AUTOMATION TARGET: executable nodes live in
`data/playthroughs/decision_library.json`. A future generalized non-AI runner
may apply an eligible named-persona tree to generated levels only by evaluating
its policy
predicates against `player_observation_v1` and issuing the resulting action
through `AgentPlayerInputDriver`. It may not sense from fragment registries,
solver routes, target names, or gameplay transforms. The exact generated-spec
fingerprint schema and digest belong in provenance so evidence from two boots
of one layout cannot masquerade as cross-content generality. The current
partial, hand-enrolled trees do not yet constitute that generalized player.

The generated-stretch discovery loop's `first_read` and `risk_seeking` labels
are exploration strategies, not personalities. Their records use
`generated_strategy_decision_trace_v1`, carry no persona ID, and are always
tree-ineligible with `unnamed_strategy_not_persona`. A useful repeated choice
from that lane is a candidate for a documented real-persona rule; it must then
be replayed at least twice as that named persona through shipped input, exact
visible receipts, goal completion, hash-chain validation, and whole-invocation
attestation before it can update the tree. This keeps large generated-level
runs deterministic without allowing a generic solver to certify itself.

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
Document a few reflexes a REAL player type has, express every condition against
the full `player_observation_v1`, map every action to a shipped input boundary,
and add a writer-derived visible goal proof for each enrolled fragment. Then add
the persona/repeat identities to the fixed validator cohort and earn fresh
Native and Web v3 evidence. A persona that simply plays well finds nothing.
