# Testing and release gate

The tracked entry point for required validation is
`scripts/test-gate.ps1` at the repository root. It discovers Godot from
`-GodotPath`, `GODOT_BIN`, a repository-local executable, or `PATH`; invokes
Godot through the launcher's owned process boundary; preserves the child process's exit code; records stdout and
stderr under `.test-gate/`; and fails if a required test prints `SKIP` while
returning zero. Native runner invocations launch the independent
`res://scenes/system/test_bootstrap.tscn` scene; required standalone authority
verifiers launch as explicit Godot scripts from the gate manifests. The shared
preflight manifest runs `res://tools/verify_agent_player_input_boundary.gd`
exactly once before any requested release tier. Thus standalone Headless,
Windowed, and Web launches, the combined Windowed+Web workflow, and Release/All
all dynamically verify the same cursor/input and forbidden-mutation boundary
without duplicating it inside their tier manifests. The canonical Headless tier
then includes `res://tools/verify_persona_decision_pipeline.gd` and the
generated-action graph verifier
`res://tools/verify_generated_actionable_approaches.gd`; running only
`--test-all` does not satisfy the gate. The Windowed manifest also
requires `res://tools/verify_generated_interaction_truth.gd`, which proves a
pre-click rendered affordance becomes a newer framebuffer-visible success on
the same retained source token after its generated one-shot disables.
If the TestRunner autoload
cannot compile, that scene exits immediately instead of leaving the ordinary
main menu alive until the gate timeout.

Do not use the ignored `godot.bat` as a release gate. It is a developer
convenience left on some workstations, is absent from clean checkouts, and is
not what CI executes.

## Canonical commands

Run these from the repository root in PowerShell:

```powershell
# Proves synthetic exit propagation, required-skip rejection, bounded timeout
# handling/process cleanup, child-environment propagation, and native
# parser-failure bootstrap wiring.
& .\scripts\test-gate.ps1 -SelfTest

# One shared contained agent-input-boundary preflight, then the complete
# deterministic/headless suite, persona-decision validation, and generated
# actionable-graph verifiers. This is intentionally not capped at 30 seconds.
& .\scripts\test-gate.ps1 -Tier Headless

# One safe focused Headless diagnostic. The value must be exactly one
# lowercase --test-[a-z0-9-]+ token; the launcher supplies test_bootstrap and
# --fail-on-skip and retains the same native containment as a required tier.
& .\scripts\test-gate.ps1 `
  -FocusedHeadlessTest '--test-basin-fill-proof'

# The same strict diagnostic surface in the real Windowed renderer. Use this
# for framebuffer, physical ray-pick, visibility, and presentation-lifetime
# regressions instead of treating a Headless simulation as rendered evidence.
& .\scripts\test-gate.ps1 `
  -FocusedWindowedTest '--test-player-observation'

# Explicit maintenance only: regenerate all nine committed generated specs from
# their persisted seeds/settings, export both replay mirrors, and verify exact
# spec-derived replay parity. This mode is exclusive and privately contained.
& .\scripts\test-gate.ps1 -RegenerateGeneratedBaselines

# Real framebuffer, presentation-only observation, physics-pick, hover, click,
# walk, interaction contract, the Basin authored-spawn journey, the generated
# player-surface scenario matrix (flat/spiral, chain/random/setpiece,
# run-session, survival, and mode comparison), the generated stretch input
# loop, exact retained-token generated interaction-result truth, and the
# player-input persona probe.
# The shared contained agent-input-boundary preflight runs once before these
# Windowed legs.
# Requires a desktop display (CI supplies Xvfb).
& .\scripts\test-gate.ps1 -Tier Windowed

# Release Web export plus the real Basin journey, the exact generated seed-5
# HIDE/whole-party-Rally roundtrip, the adversarial static-green result-pulse
# contract, and a generic boot/input/error smoke in headless Chromium. The gate
# installs the pinned npm dependencies and Playwright Chromium runtime when needed.
# The shared contained agent-input-boundary preflight runs once before export.
# Requires Web export templates, Node.js 22+, and the Web GDExtension binary.
& .\scripts\test-gate.ps1 -Tier Web

# One shared contained agent-input-boundary preflight, then fresh Native+Web
# persona evidence and its combined 4+4 distillation preview. Both tiers must
# run in this one process so they share one gate run directory.
& .\scripts\test-gate.ps1 -Tier Windowed,Web

# All required release tiers in order.
& .\scripts\test-gate.ps1 -Tier Release
```

Use `-GodotPath`, `-BrowserPath`, or the `GODOT_BIN` / `CHROME_BIN`
environment variables when discovery is ambiguous. `-TimeoutSeconds` applies
to each child invocation and defaults to one hour. A timeout exits 124.

## Tier contracts

Every ordinary tier launch first runs exactly one Headless-mode
`verify_agent_player_input_boundary.gd` shared preflight through the launcher's
artifact-owned Native containment. A combined `Windowed,Web` or
`Release` / `All` launch still runs that preflight only once.

| Tier | Required work | What it does not replace |
| --- | --- | --- |
| `Headless` | After the shared preflight: `--test-all`, the Aster drink item/presenter save-restore authority verifier, `verify_persona_decision_pipeline.gd`, and `verify_generated_actionable_approaches.gd`, with exact nonzero exit propagation and zero accepted skips | Framebuffer/browser truth |
| `Windowed` | `--test-player-contract` over every registered preview entry, the required `--test-player-observation` framebuffer/occlusion boundary, the Basin's authored-spawn safe and missed-rise journeys, the fixed DeanTakahashi/EazySpeezy by repeat-0/repeat-1 Native persona cohort through the central shipped-input executor, the required generated player-surface scenario matrix covering flat/spiral, chain/random/setpiece, run-session, survival, and mode comparison, the generated-stretch real-input loop, and `verify_generated_interaction_truth.gd` proving a pre-click rendered affordance becomes a newer framebuffer-visible success on the same retained source token after one-shot disable | WebAssembly and browser-platform behavior |
| `Web` | Fresh release export, required artifact check, pinned Playwright Chromium, the fixed DeanTakahashi/EazySpeezy by repeat-0/repeat-1 Web persona cohort through the real browser input/click chain, the exact generated seed-5 Capbage HIDE/whole-party-Rally roundtrip, the adversarial static-green suppressed-pulse negative contract, plus a generic canvas boot/input/error smoke | A level-specific unscripted human playtest |
| `Release` / `All` | Headless, then Windowed, then Web | Nothing in the three required automated tiers |

Each required Native invocation receives a clean artifact-owned Godot
`user://` root under the gate run directory. Persona traces, settings, or save
data from an earlier workstation run therefore cannot satisfy a later gate,
and the exact trace files used by the invocation remain beside its stdout and
stderr logs. The launcher self-test enforces this isolation on Windows and
XDG-based hosts. The Web gate likewise uses a fresh export, a fresh Playwright
browser context, and a run-owned output directory. Neither platform may reuse
prior persona traces or browser/Godot state as release evidence.

On Windows, every Godot process started by this gate uses the private
never-input desktop and exact kill-on-close Job boundary described below. This
includes `LaunchMode Headless`, dedicated Headless script verifiers, Windowed
tests, Web export, the Web reporter's GDScript distillation preview, and the
final cross-platform distillation preview. `--headless` is an engine request,
not proof that Windows cannot create an alert or renderer companion HWND.
Agents must therefore use `-FocusedHeadlessTest` or `-FocusedWindowedTest` for
a focused runner flag and must not invoke Godot directly. A test whose claim
depends on a framebuffer, physical pointer ray, window/display behavior, or a
cue surviving completed draws must use `-FocusedWindowedTest`.

The Headless, Windowed, and Web movement contracts all require a positive
count of full-XYZ samples taken while a real command is in flight. Native
journeys sample once after every advanced simulation step; the Web bridge
samples every presented frame. Boot, idle, and already-settled frames do not
satisfy this requirement, so accepting a command without observing its
in-flight presentation is a failure.

The shared `movement_continuity/v1` receipt also brackets each covered action
with a settled origin and settled endpoint. A passing episode needs multiple
strict interior rendered frames and scheduler ticks, bounded full-XYZ steps,
and agreement among logical position, render projection, `global_position`,
and `global_transform.origin`. It accumulates sub-threshold movement while an
actor claims to be settled, so neither a synchronized endpoint snap nor slow
hidden drift can pass merely because all authorities agree afterward. Basin
coverage accepts no discontinuity exemption. Testing code may not synthesize or
self-authorize a portal receipt: this contract currently fails every
discontinuity closed. A future non-Basin portal gate may admit an authored hop
only by consuming fresh, non-replayable lineage issued by the production portal
mechanic and binding its subject, authority, serial, endpoints, projection, and
presenter transforms.

Windowed and Web persona evidence uses `persona_decision_trace_v3` JSONL.
Persona policy receives the complete validated `player_observation_v1` and no
other gameplay input: not world coordinates, transforms, node names, authored
routes, mechanism state, completion flags, or solver data. Each decision
hash-covers the exact observation before input, canonically de-duplicated
multi-frame observations in first-seen chronological order while the command is
in flight, the exact observation after settling, the persona rule and rationale,
and the shipped-input receipt. Before, samples, and after must form one
non-reordered observation chronology.
The trace writer derives feedback and outcome from those observations; callers
cannot supply either. In particular, an interaction is accepted or refused
only from a newly presented result serial bound to the opaque token of the
exact affordance visible before the click. The reader and distiller recompute
the derivation and reject forged, stale, other-target, or feedback-free claims.
Move and Rally proof must follow a monotonic causal presentation lineage bound
to the chosen target token and every intended HUD portrait token. An unrelated
cue, camera/viewport drift, or generic movement delta is not causal proof.
An accepted production command that later stops short retains `accepted: true`:
its only valid terminal lineage is `accepted -> progress -> interrupted`, with
a visible non-empty interruption reason. Native and Web validators must treat
that lineage as terminal-but-undemonstrated. They must neither rewrite the input
as refused nor synthesize `arrival`, and it cannot advance or promote a policy
whose expected result was successful arrival.

The writer also derives the persona goal from persisted visible evidence and
overwrites caller goal claims. For the Basin, Eazy requires an exact visible
REST/SHELTER success plus the same action's visible full-party secured/settled
cue. Dean requires a visible Basin-rise warning followed chronologically by
same-label, same-destination `SWEPT` active and arrival cues for every portrait
in the visible warning roster. Only a hash-valid trace whose derived summary
states both `trace_complete: true` and `persona_goal_reached: true` can
contribute support; one ineligible decision forces the run incomplete.

Promotion is also cohort-atomic. Each platform independently requires the
fixed Basin matrix `DeanTakahashi, EazySpeezy` x repeat indexes `0, 1`. Every
trace's final `persona_strict_validation_v1` receipt embeds the same
`persona_strict_invocation_manifest_v1`, whose member proofs bind run/trace
identity, repeat, platform, fragment, versioned authored-content identity,
gameplay-build identity (`gameplay_build_fingerprint_schema` plus
`gameplay_build_fingerprint`), summary hash, decision count, and derived
completion/goal. The distiller rebuilds that
manifest from all supplied traces instead of trusting the reporter's copy. A
filtered, interrupted, duplicate, mixed-content, missing-member, failed, or
otherwise partial invocation remains unattested and contributes zero support.
A later failed receipt revokes an earlier green receipt.

Authored-content identity is stable and versioned. Authored fragments use
`authored_fragment_resource_bytes_v1`; generated layouts use
`generated_spec_semantic_v1`, excluding runtime/platform bookkeeping. The
schema and SHA-256 digest form one identity, so Native and Web evidence for the
same authored Basin bytes agree while genuinely changed content does not.
Fragment-scoped nodes may promote from repeated, distinct, full-goal traces of
the same content. Global nodes additionally require distinct content
identities; repeated boots of one layout cannot manufacture generality.
Gameplay-build identity is recorded separately under
`gameplay_build_resource_set_bytes_v1` for the executable/export that supplied
mechanics. It does not count as authored-content diversity, and
evidence from behaviorally different builds cannot pool even when their level
resource bytes match.

Required automated Windowed and Web players own only application-local input.
Native automation injects `InputEventMouseMotion`, `InputEventMouseButton`, and
keyboard events through Godot's production `Input` surface; browser automation
injects pointer and keyboard events into the exported canvas. No test, persona,
replay, diagnostic, or capture helper may warp the workstation cursor or invoke
OS-level mouse automation. Both the launcher self-test and the tracked
agent-input verifier recursively scan the project's executable/test source
extensions. They reject the `warp_mouse` symbol or string with any receiver or
dynamic-dispatch shape, including identifiers assembled from two or more string
fragments. Automated helpers additionally reject cursor capture/confinement,
native pointer APIs, and desktop automation libraries.
The whole-project window-lifetime scan rejects window reposition, foreground,
and mode changes everywhere except the single reviewed
`res://tools/offscreen_window.gd` implementation. Mutation fixtures cover
direct, whitespace-separated, dynamically constructed, `DisplayServer`,
`Viewport`, native OS, `Window` properties, setters, dynamic calls, and typed
or getter-derived aliases in GDScript and C#. Negative-control fixtures ensure
ordinary game-node transforms remain legal, so weakening or over-broadening a
scanner fails the launcher's own self-test.

On Windows, geometric parking alone is not the isolation boundary: Windows may
clamp an ordinary top-level game window back onto a monitor, and even a
Headless launch can raise a native alert. Before any gate-owned Godot process starts,
the tracked launcher retains the exact desktop currently receiving user input,
then creates a private Win32 desktop in the current window station. It never
activates that desktop and continuously proves that `OpenInputDesktop` still
names the retained input desktop rather than the private desktop. A dedicated
thread binds to the private desktop and creates the Godot owner outside the current virtual
desktop. That owner is a never-shown `WS_POPUP` with `WS_DISABLED` and
`WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`, without `WS_VISIBLE` or
`WS_EX_APPWINDOW`, and its thread runs a blocking message pump until the test
ends.

When the configured Godot path names the official Windows `*_console.exe`
wrapper, Windowed legs resolve its sibling GUI engine and launch that engine
directly; the wrapper is not allowed to introduce an intermediate top-level
window. Headless and export legs may retain the console wrapper, but wrapper
and engine companion are members of the same exact Job and inherit the private
desktop. The launcher uses native `CreateProcessW` with the root assigned to the
private desktop through `STARTUPINFO.lpDesktop`, requests `SW_HIDE`, redirects
its logs, and creates it suspended. Before resume, the launcher also assigns the
root to a kill-on-close Job Object, so every ordinary descendant joins the same
bounded process tree. The job also carries `JOB_OBJECT_UILIMIT_DESKTOP`, which
blocks `CreateDesktop` and `SwitchDesktop`. This is defense in depth, not the
monitoring boundary: Windows does not document that flag as blocking
`OpenDesktop` plus `SetThreadDesktop`, and `JOB_OBJECT_UILIMIT_HANDLES` cannot be
used because Godot must consume the reviewed cross-process `--wid` owner. The
desktop monitor, hidden owner, and process-tree
boundary are therefore established and attested before `ResumeThread`; a
startup `ShowWindow` or focus request cannot race onto the user's input desktop.

The launcher passes the owner's decimal HWND to Godot with `--wid`. Godot's
Windows backend creates the main render HWND as a host-owned `WS_POPUP`, not a
`WS_CHILD`; `GetParent(render) == host` is therefore the required ownership
proof. After the exact class-`Engine` render HWND appears in the exact launched
GUI PID, the launcher disables OS input on that handle and is the only component
allowed to reveal it, using `SW_SHOWNOACTIVATE`. The render HWND must then keep
`WS_VISIBLE` for a real swapchain while both it and its owner remain wholly
outside the virtual desktop on the private, non-input desktop. The requested
Godot position is normalized to `(0, virtual-desktop height + margin)` rather
than reusing physical desktop coordinates, which remains outside layouts whose
monitors extend above or left of the primary display.

Before every sample, the launcher obtains the complete, duplicate-free PID list
from `JobObjectBasicProcessIdList`; parent-process ancestry is not authority. It
enumerates both the private desktop and the retained original input desktop.
Windowed render establishment samples every millisecond until input is disabled;
established Windowed surfaces and non-rendering Headless/export processes are
attested every 25 ms. Any top-level HWND owned by an exact job PID on the
retained input desktop fails the lane, even when hidden, zero-area, disabled,
owner-bound, or lacking `WS_EX_APPWINDOW`. The lane also fails if the retained
desktop ceases to be the current input desktop. Each isolation log records its
sample count, input-window sample count, and the verbatim first escaped-HWND
snapshot before terminating the job. The launcher pins
the first render HWND and requires that exact handle to remain directly owned by
the hidden host for the entire live process lifetime; disappearance,
replacement, or reparenting fails immediately. Every sample also proves that
the private desktop is not the input desktop, that the owner thread remains
bound to it, that owner and render rectangles remain off-desktop, that expected
styles and input disabling remain in force, and that no owner, render, or
auxiliary HWND owns foreground focus. Narrowly classified Windows driver/WGL,
IME/text-services, and zero-area no-activate input-indicator helper HWNDs are
accepted only in their exact inert shapes. Every other process-owned top-level
HWND is forbidden. A Default IME is classified from its current live render or
WGL binding, exact PID/thread binding, and inert HWND properties in the same
sample. During established-render teardown, Windows may clear the IME's Win32
owner first; the exact same-sample
`ImmGetDefaultIMEWnd(accepted render-or-WGL HWND)` reverse binding remains
authority for that zero-area helper and its exact MSCTF child. An earlier
sample or accumulated ledger is never authority, and there is no startup grace
period. Any positive-area intersection with the virtual desktop,
including a single pixel, is a violation; touching an edge without overlap is
not. The launcher kills the exact process tree and exits 66 on any violation or
if no real visible-style render HWND establishes isolation.

The launcher's self-test builds a real Windows GUI fixture that receives
`STARTUPINFO/SW_HIDE`, creates an `Engine` popup, and immediately calls
`ShowWindow(SW_SHOW)`. It must prove that monitoring was installed before
resume, that the startup show request was initially hidden, and that the later
visible-style surface exists only on the private non-input desktop, remains
owner-bound/off-desktop/input-disabled, and never takes focus. The same self-test
detaches a real Default IME after hiding an established render surface: a
bounded clean exit must pass, while an otherwise identical live root must still
fail with exit 66 after the teardown poll. The isolation ledger proves the
ownerless helper was sampled in both lanes rather than relying on a final-HWND
snapshot. It also
locks the one-pixel intersection boundary, rejects unsafe auxiliary windows, and
proves native exit-code propagation. A mandatory adversarial lane moves a fresh
fixture thread onto the retained input desktop and creates a positive-area
top-level HWND there. That HWND omits `WS_VISIBLE` and is never passed to
`ShowWindow`, so the fixture paints no pixel; nevertheless, exact job-PID input
enumeration must preserve its HWND/class/title/geometry in the violation ledger,
terminate the job, and return 66. Its first GUI root starts a delayed
in-job descendant that inherits the log handles and exits after the root; the
descendant's final marker must be captured before a second GUI root can start.
Another fixture deliberately stops pumping its window thread while both root
and descendant remain alive; the two-second timeout must still return 124 and
leave both exact PIDs dead. This prevents synchronous input-disabling work,
root-only waits, or inherited output handles from defeating timeout cleanup.
A fourth contained GUI lane exits 37 and must preserve that exact nonzero code,
its isolation attestation, exclusive log closure, and a dead root PID. Thus the
ordinary synthetic exit test cannot conceal a Windows-native propagation bug.
An additional Headless-mode adversarial lane creates a visible, unowned
`ALERT: headless fixture` top-level window after process resume. Its process is
born on the private desktop with `SW_HIDE` and exact Job membership; the input
desktop ledger must remain empty, the private top-level must be recorded and
rejected, the whole Job must drain, and the lane must return 66. This proves
that a nominally Headless alert cannot appear on the user's desktop. The
self-test also invokes the tracked launcher with a malformed mixed-case
focused flag and requires exit 64, while exact valid flags assemble only
`test_bootstrap`, that one test token, and `--fail-on-skip`.

At ordinary process teardown, a 1 ms bounded attestation loop distinguishes the
final HWND disappearing just before the root process handle signals from a live
process that dropped or replaced its render surface; there is no unmonitored
grace sleep. After the root signals, the launcher captures its native exit code
and continues the same private/input desktop attestation while the exact Job
Object PID list drains to zero before it reads or rewrites redirected logs. A
lingering descendant is a cleanup failure: the
whole job is terminated and the lane exits 66. Timeout and containment failures
terminate the job with 124 and 66 respectively, then require the same zero-active
proof. Bounded shared-file reads/writes tolerate Windows handle-table teardown,
and every Windows native Godot child also receives a separate
`.window-isolation.log` so a
stdout finalization fault cannot erase its containment verdict.
Host construction, environment restoration, partial launch, and managed wrapper
disposal all share the same ownership scope. A host thread/desktop, process,
job, or log handle that cannot be cleaned within its bounded retry is a gate
failure, never a warning attached to an otherwise-green lane.

Godot consumes `--position` and `--wid` before GDScript can inspect the ordinary
user-argument array. The native launcher therefore proves those exact process
arguments, desktop assignment, HWND ownership, style, position, input isolation,
and lifetime. `test_bootstrap.gd` independently requires canonical position,
parent, host-mode, and app-local-input environment tokens plus a native window
handle, then checks that the actual surface matches the requested position and
remains completely off-desktop during `_enter_tree()`. GDScript cannot compare
the consumed engine arguments themselves. Arbitrary `--wid` hosting is not
editor embedding, so exact argument binding and parentage are correctly proven
by the launcher with the native process command line and `GetParent`, rather
than `Engine.is_embedded_in_editor()`.
An invalid contract hides and parks the surface and requests exit 66 before
`_ready()` can dispatch tests; the valid contract is then checked continuously.
Non-Windows display hosts (including CI Xvfb) use the geometric fallback:
process-start offscreen position, pre-first-frame corrective parking, and
per-frame offscreen assertion. These constraints preserve a real framebuffer,
physics picking, and the shipped input route without moving the user's cursor,
taking focus, or exposing a test window on the user's desktop.

`persona_decision_trace_v2` traces and existing v2 library provenance remain
readable diagnostic history but are inadmissible and non-executable until fresh
v3 cohorts are distilled, even when their old hashes and caller-made outcomes
are valid. The current decision trees are partial, hand-enrolled
policies for specific personas and situations. Generalized bulk non-AI level
play is a future consumer of sufficiently earned nodes, not a capability the
current library or player has completed. These paragraphs define release
requirements; they do not claim that a current full Native or Web v3 cohort has
passed. Only fresh gate artifacts and their recomputed manifests establish
that result.

## Persona cohort archive and promotion

The gate only writes a combined preview; a gate `PASS` never mutates
`data/playthroughs/decision_library.json`. Produce promotable Native and Web
evidence in the same launcher process, then run the tracked promotion helper
from the repository root:

```powershell
& .\scripts\test-gate.ps1 -Tier Windowed,Web

# Default is a dry run. Supply the exact printed gate run directory; do not
# select "latest" in a shared worktree.
& .\scripts\promote-persona-cohort.ps1 `
  -GateRunDirectory .\.test-gate\<run-id> `
  -GodotPath $env:GODOT_BIN

# After reviewing the dry-run result, repeat explicitly to update canonical.
& .\scripts\promote-persona-cohort.ps1 `
  -GateRunDirectory .\.test-gate\<run-id> `
  -GodotPath $env:GODOT_BIN `
  -Promote

# Fast fixture coverage for matrix/path rejection and atomic backup behavior.
& .\scripts\promote-persona-cohort.ps1 -SelfTest
```

The dry run leaves a self-contained validation staging directory under the
selected gate run and proves that the canonical library's bytes did not
change. `-Promote` instead creates
`data/playthroughs/decision_traces/cohorts/<run-id>/`, refuses to merge with an
existing archive, and stores the exact eight manifest primaries, original
manifests/report/preview, the canonical preimage, and rebased manifests whose
trace paths point at the archived copies. It re-distills those archived eight
against the frozen preimage, reruns combined validation through the rebased
manifests, and requires the result to be byte- and hash-identical to the gate
preview while the live canonical preimage remains unchanged.

Only then does `-Promote` use a same-directory temporary file and atomic file
replacement. The replacement's prior canonical bytes, verified postimage,
rebased validation report, and a SHA-256 inventory remain in the durable
archive. Direct distiller `--in-place` is not the release promotion workflow:
it does not supply this archive, baseline binding, or recoverable replacement.
Commit or otherwise preserve the cohort archive together with the promoted
library before deleting `.test-gate/<run-id>/`.

The generated-stretch discovery loop deliberately emits the separate
`generated_strategy_decision_trace_v1` diagnostic schema. Its `first_read` and
`risk_seeking` strategies have no persona ID and must record
`eligible_for_learning: false` plus
`persona_tree_ineligible_reason: unnamed_strategy_not_persona`, even when they
reach the visible goal. Those traces are useful for finding missing predicates
and controls, but they cannot enter the persona distiller. Bulk non-AI level
testing may consume only already-eligible named-persona nodes, evaluated from
`player_observation_v1` and executed through the same shipped input driver.
A newly observed strategy becomes tree evidence only after it is enrolled as a
documented real persona rule and independently repeated through the full
hash-valid goal-reaching Windowed/Web contract.

Generated presentation recovery is recorded with the semantic verbs
`camera_recenter`, `camera_zoom`, `camera_rotate`, and `camera_pan`. Every such record remains
`world_change: false` and persona-learning-ineligible, but its `input_receipt`
must prove the exact shipped Home, wheel, paired held Q/E, or paired W/A/S/D
packet and bind both the before-observation capture serial and the first
post-input capture serial. A rotation receipt contains exactly one unmodified
Q-or-E down/up pair from one timed hold, records its direction and duration,
and reports zero production events; it never substitutes repeated frame-rate-
dependent taps or a direct camera mutation.
The canonical observation fields are the only accepted trace shape; legacy
`observation` and `outcome.observation` aliases are rejected rather than
silently normalized into new evidence.

The generated Windowed loop is wall-clock bounded without making wall time a
policy input. Each visible path permits at most 24 decisions and receives
`clamp(60 s + 15 s * generated node count, 120 s, 240 s)`; the shared
three-path deadline is the sum of those budgets plus 30 seconds. The runner
prints and records a heartbeat while it waits on real frames. Four seconds
without a validated visible causal change fails the path; an accepted Rally
fails after three seconds if no intended body starts moving, or after 1.5
seconds of stable incomplete member motion. Exact target-result waits retain
their absolute ceiling. A watchdog abort releases every held synthetic input,
preserves the partial observation/receipt evidence, emits a hash-covered
`trace_complete: false` summary, and fails the required lane. It must never
skip, advance scheduler time, alter gameplay state, or influence target/action
selection.

`player_observation_v1` is the exclusive persona policy input and is persisted
in full for every before/sample/after record. It exposes both the visible
affordance records and two derived policy indexes: sorted, de-duplicated exact
`visible_affordance_verbs` and `visible_affordance_consequences`. Validation
recomputes these lists solely from the current visible affordances. Learned
interaction and route predicates use exact array membership in these lists,
never fixed `affordances.N` positions or substring fallbacks. An unrecognized
visible interaction remains valid recorded play but proposes no policy node.
Rendered input-hint chips are also observation text cues: their current glyph
labels and descriptions must disappear when their inherited UI flow is hidden,
so an automated player can discover only the camera and action controls a human
can currently read.
Policy promotion canonicalizes recursively nested singleton `all` and `any`
wrappers before storing or signing a policy, while preserving every genuine
multi-branch predicate. The pipeline verifier must prove that equivalent flat
and singleton-wrapped Native/Web evidence merges without a policy conflict.

The Web tier exports to a fresh per-run artifact directory, so an old
`build/web` cannot make a broken export look green. It runs
`npm run test:web:basin` with `--repeat-each=2` against that exact export.
Playwright's repeat index is recorded as both the deterministic evidence seed
and run index, and is encoded into each trace/run ID and JSONL artifact name;
the repeat metadata identifies independent authored boots but never drives a
character or mutates the level. In every passing repeat, EazySpeezy must enter
the Basin from the authored spawn using real browser key and pointer input.
Eazy must use one held-RMB Rally for the whole visible party through the
annotated ladder graph, interact with the visible crossing control, and observe
the persistent `CROSSING STAGING` consequence while every visible-roster member
physically reaches its stable hold vertex. Eazy must then observe
`CROSSING ARMED` before the next MID beat launches that exact roster. After the
crossing, Eazy must use a second held-RMB Rally to settle that same visible
roster at the marked shelter, select the full party, and click the visible
`REST PARTY` affordance to complete the fragment. DeanTakahashi's passing run
must enter the bowl, deliberately miss the rise, and sample warning, forced
carry, and return-shelf arrival.

The same Web spec also boots an e2e-only generated-stretch entry with exact
seed 5, standard complexity, a seven-node budget, and no spiral. Starting from
the exported authored spawn, the browser player must discover `HIDE` from
`player_observation_v1`, issue one real pointer interaction, retain the first
exact-source success and first exact `HIDDEN` observations within eight capture
serials, and prove that `HIDDEN` is still current before taking another action.
It then chooses a visible destination from a fresh observation and issues one
held-RMB Rally over the exact visible portrait roster. All three bodies must
return through accepted/progress/arrival presentation lineage with movement
sample growth and continuous, portal-free transform evidence. The post-choice
assertion oracle separately verifies the exact generated semantic fingerprint,
budget, and absence of fallback; those private facts never select an action.

An additional e2e-only Web entry places the production interaction-result
presenter on an exact static Capbage-green emissive box. Its first real pointer
interaction mints a normal logical success and on-screen pulse geometry, then
the fixture suppresses only that transient pulse's own material and shows a
neutral `CONTROL RECEIVED` acknowledgement through the ordinary preview-note
presenter. Sampling beyond the complete production pulse lifetime must observe
zero exact-source `interaction_result` cues. A second real pointer interaction,
chosen independently from a fresh player observation, must restore exactly one
newer production success cue. The fixture entries are absent from the ordinary
fragment picker and direct chunk registry; `?e2e=1` may select only their
immutable launch entries. They expose read-only post-choice diagnostics and no
command, teleport, trigger, or gameplay-state mutation bridge.

That quarantine is enforced structurally, not by checking that fixture tokens
exist somewhere in source. The Web contract parses the complete top-level
`PREVIEW_ENTRIES` and `CHUNK_SCENES` containers and the ordinary picker,
handoff, CLI/id, stage, and resolver functions; mutation vectors must fail if
either fixture is wired into any of them or if MainMenu loses its Web + exact
`?e2e=1` guard. Each fixture journey also starts once without `e2e=1`, enables
observation through history only after MainMenu has evaluated that URL, and
uses the focused menu controls to enter Fragments. It must reach an empty
ordinary picker state rather than the requested fixture before reloading with
the authorized query and running the positive journey.

The generic smoke independently checks platform boot, cross-origin isolation, browser
input, and page/console/network errors. Other flagship levels still need their
authored key verb driven through the real click chain, as required by
`LEVEL_PLAYABILITY_CHECKLIST.md`.

The Web validation reporter may seal only that exact two-persona,
two-repeat-index invocation, and only from Playwright's invocation-wide `onEnd`
verdict. A filtered, interrupted, single-persona, or otherwise partial
diagnostic run leaves its trace unattested. A receipt is not sufficient by
itself: distillation must be given the four primary traces together and must
independently reproduce their one green cohort manifest. The pure contract,
generated seed-5, and static-green pulse tests are not persona cohort members
and mint no trace; they remain inside the invocation-wide Basin-spec result,
so any failure still vetoes a green cohort seal.

The Basin browser bridge samples presentation every frame, independently of
its throttled JavaScript state publication. The Web journey snapshots every
covered command before launch—including both held-RMB whole-party Rallies—and
requires later movement-sample growth for every intended member before arrival.
For an automatically launched assisted traversal, it
snapshots immediately before launch and independently requires movement-only
growth from every intended participant; this remains fail-closed when a short
fast-forwarded traversal begins and ends between throttled JavaScript
publications. It rejects transient drift using each character's accumulated
full-XYZ `global_position`, `global_transform.origin`, and logical-to-render
projection errors, rejects non-finite values, and proves every observed level
transition matches one directional runtime graph edge with walkable endpoints
and a ladder annotation.

A group receipt is atomic only when one production event names exactly the
intended roster and every named member has the same accepted result. A
whole-group refusal is atomic only when it emits no movement event and refuses
every intended member consistently. Missing members, extra members, multiple
events, or mixed member outcomes make the decision ineligible and force the
hash-covered run summary's `trace_complete` field to `false`.

By default, `-Tier Web` runs `npm ci` and installs the pinned Playwright
Chromium before testing. CI performs `npx playwright install --with-deps
chromium` explicitly, then passes `-WebDependenciesReady` to avoid repeating
that clean installation. Only use that switch when the current checkout's
`node_modules` and Playwright browser runtime have already been installed.

## Failure semantics

- A child nonzero exit is returned unchanged by the gate.
- A required `SKIP` with an otherwise-zero child exit becomes gate exit 86.
- A successful Web export missing a required artifact exits 87.
- A zero-exit child that emits a Godot script/parser/runtime fault exits 88.
- A child timeout exits 124.
- On Windows, a timeout terminates the exact launched process tree (including
  Godot's engine child) so it cannot leak into and invalidate the next tier.
- Logs, Playwright traces/screenshots on failure, and the generic Web
  screenshot/report are written to `.test-gate/<run>/`.

GitHub Actions performs a clean-checkout build of the ignored Linux and Web
GDExtension binaries from the pinned `godot-cpp` revision before invoking the
same launcher. This matters: local `bin/*.dll`, `bin/*.so`, and `bin/*.wasm`
files are intentionally not versioned and cannot be assumed to exist in CI.

## Regression coverage rules

A regression must enter through the boundary where the player experienced the
failure. Directly mutating character positions or calling an internal movement
method can test simulation logic, but it does not cover camera picking,
selection, input routing, controller wiring, or an exported browser build. A
real-input regression must start at the authored spawn, use production
keyboard/pointer events, assert that commands were accepted, and prove the
physical completion condition.

Headless pointer tests must not certify pixel-radius picking from Godot's
`64x64` default framebuffer. Before projecting a world point or exercising a
fixed-pixel pick radius, use the contained Native gameplay geometry
(`1152x648`), restore any prior viewport size afterward, and assert what the
shipped resolver identifies at that exact pixel (open ground, character, or
interactable) before issuing the command. Merely asserting that the projected
pixel is in bounds is insufficient: at `64x64`, a normal 56-pixel portrait/body
pick radius covers almost the entire view and can silently turn a distant
ground Rally into a character-anchored Rally.

### Approval and playthrough evidence boundary

Persona decision quality and control-surface fidelity are independent test
axes. A persona or policy test proves representative choices; an input or
command test proves that those choices crossed a player-accessible boundary.
Neither result substitutes for the other unless the same run proves both. If a
player cannot perform the same action through the shipped controls from the
same authored state, it is not playthrough evidence.

- Every world-changing action in approval, persona, AI-playthrough,
  optimal-playthrough, and release-journey evidence must enter through a
  shipped keyboard/pointer, controller, touch, or player-command boundary.
  Read-only observations may inspect the result but cannot create it. Direct
  callbacks, singleton movement helpers, mechanism methods, or state writes
  belong only in named unit or diagnostic tests and cannot establish playable
  approval. For the current promotable Native/Web persona contract, every active
  action additionally needs a mechanically issued keyboard/pointer ledger from
  the shipped driver. `player_command` is allowed only for a passive wait that
  changes no world state. Controller and touch remain reserved/nonpromotable
  until they have equivalent mechanical-issuance and presentation-proof
  contracts.
- Public observation, receipt, snapshot, and `get_*_presentation_state` seams
  must be projection-only. Reading them may not advance a scheduler, consume a
  pending transition, change a phase or progress value, redraw a presenter,
  increment a render receipt, or manufacture the cue being reported. Production
  process/signal handlers must establish the presentation before an observer can
  attest it; repeated reads of unchanged state must be behaviorally inert.
- Web persona policy and target selection may consume only a validated
  `player_observation_v1` value. The broader `__trawfE2E` payload is a
  post-choice mechanism/transform oracle: `characters`, `chunk`, `anchors`,
  ladder graph data, and named gameplay click targets cannot select an action,
  subject, destination, or wait. Observation selectors must cross the guarded
  policy-input seam, and pointer/key execution must reject targets or cues that
  were not produced by that seam. The only named bridge click target allowed
  before a measured Web journey is the allowlisted main-menu boot control.
  Keep mutation vectors for raw bridge pulls, direct private-field reads,
  nested `player_observation` unwrapping, named gameplay bridge targets, and
  unguarded persona input dispatch. Private bridge reads remain legal only in
  post-choice assertion helpers and never flow back into the next decision.
- Production group verbs remain atomic at the harness boundary. Rally, party
  transfer, and collective interaction cannot be hidden as singleton selection
  and actions. Rally is one held production gesture over exactly every portrait
  visible in the HUD roster, not a hard-coded party list; `select_party` binds
  that same exact full roster. If any visible portrait has no shipped input
  binding, the whole command fails closed before movement. Record requested
  membership and each member's accepted or refused result. One
  accepted group event means every intended member was accepted. Mixed
  accepted/refused membership is a failed command and failed evidence, never a
  partial success; an atomic refusal emits no movement event and produces no
  partial mutation.
- Direct mutation of position, level, stats, mechanism phase, or completion is
  prohibited during the measured run. Snap or teleport cannot replace
  navigation. An authored portal is the only exception, and only when
  exercised through its production interaction and portal mechanic.
- Fixture staging and reset must be visibly quarantined as setup or teardown.
  Start a fresh evidence baseline afterward: elapsed time, command counts,
  movement samples, receipts, proximity, and completion produced by setup do
  not count. The first counted event must be player-facing.
- Every accepted or refused movement or state-change request needs
  player-observable feedback. Acceptance needs the appropriate command,
  progress, state, or consequence cue; refusal needs a reason or refusal cue
  and no partial mutation. Event logs, return values, and final-state parity are
  supporting evidence only. A silent receipt cannot make the decision eligible.
  Move/Rally evidence must bind the exact visible target and portrait tokens
  through a monotonic causal presentation lineage; camera motion or an unrelated
  generic cue is not command feedback.
- A passive wait does not issue production input, but it is not a blind spot.
  The release validator keeps a separate, post-hoc event cursor that never enters
  persona policy and never increments `production_event_count`. If authoritative
  state changes during that interval, the before/samples/after chronology must
  contain a newly rendered causal cue. A player-facing forced traversal must bind
  the affected opaque portrait/body token and show both active and arrival phases;
  a same-label cue on another character, an event-log row, or final-state parity
  cannot attest it.
- Briefing visibility is not feedback visibility. `H` may hide the optional
  `InstructionsMargin`, but command acceptance/refusal, movement/state receipts,
  and consequence warning/progress/arrival cues must remain observable through
  `StatusMargin`, the HUD, or consequence presentation. Windowed and Web persona
  coverage hides the briefing before measured actions and must still record
  those cues.
- Persona decision-tree promotion is run-atomic. A hash-valid decision is
  still ineligible unless its hash-covered summary records both
  `trace_complete: true` and `persona_goal_reached: true`. Failed, aborted, or
  budget-exhausted runs contribute no support—not even for earlier decisions
  that happened to match their local expectation, and not when the same partial
  prefix repeats enough times to meet the ordinary support threshold. The
  recorder must set `trace_complete: false` when any decision in the run is
  quarantined by the evidence classifier; an outer test failure alone is not a
  sufficient safeguard because the JSONL artifact can be distilled later.
- Promotion is also strict-invocation-atomic. After the fixed Dean/Eazy by
  repeat-0/repeat-1 matrix and preview assertions finish, Windowed or Web may
  append validation records embedding one platform-local cohort manifest. Each
  receipt binds the run identity and summary hash to the current
  platform/persona contract, validator, invocation ID, check/failure counts,
  exact decision count, content identity, and complete member proof. The
  distiller independently reconstructs the manifest from the whole set. The
  final validation record is authoritative: a later failed receipt revokes an
  earlier partial green seal. Missing receipts, failed receipts, stale
  contract/version/validator IDs, platform mismatches, filtered/interrupted
  cohorts, or decision-count mismatches contribute zero support. Thus every
  pre-attestation trace remains readable for diagnosis but must be replayed
  under the current v3 contract before it can update a tree.

When a focused fixture must stage a character, it must use the authoritative
GameState placement API, update the character's level where applicable, and
then assert that the live Node3D's full `global_transform.origin` matches
`GameState.get_render_position()` in X, Y, and Z. The test must label that
operation fixture-only and establish its evidence baseline afterward; staged
travel or proximity cannot satisfy an integration assertion. Integration
scenarios must trigger registered world interactables through their physical
source/receipt path; calling a consequence callback directly is only valid in
a named, low-level unit test of that callback.

### Transform and navigation baseline

- In graph-backed previews, every authored spawn and settled arrival must use
  the Y of its level-aware navigation node. Tests compare authoritative data Y
  with `grid_to_world(world_to_grid(position), character_level).y` and verify
  that the Y-inferred level matches the stored character level. Data and a
  presenter agreeing on the same incorrect Y is not a pass.
- In gridless previews, a downward physics ray supplies floor truth. Excluding
  party collision bodies, tests require both authoritative data Y and the live
  CharacterBody root's `global_transform.origin.y` to contact the collision
  floor; the root uses the feet convention, not an actor-center offset.
- Continuous movement coverage is fail-closed in all three required tiers.
  While a command is moving or externally traversing, Headless and Windowed
  sample once after every advanced simulation step and Web samples every
  presented frame; every covered command must finish with a positive in-flight
  count. Each sample requires finite full-XYZ logical, projected-render, live
  `global_position`, and live `global_transform.origin` values, and accumulates
  the maximum logical-to-render and presenter-to-render errors. Matching only
  at the destination cannot hide a one-step or one-frame transform split.
- A covered graph-backed arrival must settle on the level-aware graph floor
  and rerun full presenter parity. A level change is valid only through an
  annotated, typed connector between two walkable graph vertices. Multi-level
  journeys record both endpoint cells and levels plus the executed connector
  category/kind/type, then match that receipt to the directional runtime ladder
  edge; planar proximity, a shared XZ cell, or a plausible final Y is not
  sufficient navigation evidence.

- A whole-party Rally aimed at another floor is one intent independent of portrait
  multi-selection. Required coverage keeps the singleton portrait selection unchanged,
  records one rally_members event with one distinct target-floor graph vertex per
  available member, executes an annotated connector for every member, and samples each
  live transform while the routes are in flight. Three numeric selections followed by
  three ordinary movement clicks do not cover Rally.
- Every movement command records acceptance or refusal through its
  player-facing feedback path. Refusal identifies why no route or action was
  committed. Acceptance exposes command initiation and, when movement follows,
  in-flight and arrival feedback. Silent mutation, silent refusal, and
  endpoint-only success all fail this contract.

### Consequence presentation baseline

- Every release-critical player-facing consequence must have a representative failure-path test;
  a success journey that avoids the hazard is a control, not coverage of that hazard.
- The test samples three distinct phases from the live scene controller: a visible warning before
  commitment, a visible active cause/effect cue while authority is changing, and a named
  arrival/aftermath cue after completion. Windowed and Web coverage must sample actual rendered
  link parts inside the camera frame; a logical visibility/request latch is not framebuffer proof.
  Forced movement must also expose an involuntary-motion presenter state.
- Assertions read the portable presentation receipt carried by authority and match its event,
  cause, subject, effect, and destination to the visible cue. Inferring intent from a traversal ID,
  accepting an endpoint alone, or proving only transform parity does not satisfy this contract.
- Multi-subject consequences require one cue per affected subject but one coalesced fallback
  message per causal event. Ordinary direct movement and safe-path controls assert that they do not
  produce forced-consequence feedback.
- The Web tier must repeat the representative consequence through real canvas input and sample the
  semantic warning/active/arrival state from the exported build; native-only feedback is not enough.
- Restore/replay tests rebuild an in-progress active cue without replaying its initial toast.

Every `--test-*` entry point is audited by the runner's tier manifest. A new
test that can skip for display/platform reasons must be declared Windowed or
Diagnostic; it cannot silently join the Headless release surface. The manifest
also verifies the release-required Headless and Windowed entry points, including
the standalone Aster drink verifier and Windowed persona probe. The separate
shared-preflight manifest requires exactly one contained agent-player-boundary
verifier before tier dispatch; file existence alone is not coverage. Required
gate invocations always pass `--fail-on-skip`, and the outer launcher rejects a
zero-exit `SKIP:` line as a second line of defense.

A test that awaits `RenderingServer.frame_post_draw`, samples framebuffer
pixels, exercises physical viewport picking, or claims that a cue survived real
draws is Windowed evidence. It must have a Windowed-classified entry point and
must run through `-FocusedWindowedTest` or the required Windowed tier. Headless
may unit-test the same state machine with explicit logical receipts, but that
result cannot be described as framebuffer or rendered proof and must not be the
only release coverage for the claim.

## Focused diagnostics

Focused `--test-*` flags remain useful during development, but they are not a
substitute for a required tier. Never launch Godot directly for a focused run;
on Windows even `--headless` can create an alert or GUI companion. Use the
tracked launcher's exclusive focused mode:

```powershell
& .\scripts\test-gate.ps1 `
  -FocusedHeadlessTest '--test-basin-fill-proof'

& .\scripts\test-gate.ps1 `
  -FocusedWindowedTest '--test-player-observation'
```

Both focused parameters accept exactly one case-sensitive lowercase
`--test-[a-z0-9-]+` token. They reject whitespace, a second option, `=...`
payloads, underscores, mixed case, resource paths, direct scripts, any
combination with `-Tier`, and any attempt to request both modes. The launcher supplies
`res://scenes/system/test_bootstrap.tscn` and `--fail-on-skip`; callers cannot
omit or replace either. A focused command is still diagnostic rather than a
release gate; the manifest-owned required tier remains authoritative. Headless
evidence cannot approve a claim whose behavior depends on rendering or
windowed input dispatch.

## Generated-baseline maintenance

Never invoke `tools/regenerate_generated_stretch_specs.gd` or
`tools/export_stretch_replays.gd` directly. Use the exclusive launcher mode:

```powershell
& .\scripts\test-gate.ps1 -RegenerateGeneratedBaselines
```

The launcher regenerates all nine committed specs from each snapshot's existing
deterministic settings, writes the game replay and `level-sketch` mirror for
each spec, and then runs `--test-generated-replay --fail-on-skip`. All three
Godot children use the same private never-input-desktop and exact-Job
containment as release tests. A partial manual export is not valid freshness
evidence; the command succeeds only when all nine spec/replay/mirror triples
match exactly.

## Playing the game for real (browser, real input) — READ THIS BEFORE DRIVING THE GAME

**Never click at guessed pixel coordinates.** The game publishes exactly what a player can see and
act on, with screen positions. Guessing coordinates wastes runs, produces false "the game is broken"
conclusions, and is not playing — it is flailing. (Learned the hard way 2026-08-07: four failed runs
concluding "movement doesn't work" when the real problem was the wrong mouse button and a target
that was never under the cursor.)

### The observation bridge

Boot the web export with **`?e2e=1`** — without it the bridge does not exist and `globalThis.__trawfE2E`
is null. Then `page.evaluate(() => globalThis.__trawfE2E)` gives you:

| Field | What it is |
| --- | --- |
| `player_observation.state.affordances` | **The play surface.** One entry per thing you can act on: `{kind, verb, consequence, screen:[x,y], token}`. `screen` is where to click. |
| `player_observation.state.visible_affordance_verbs` | The verb vocabulary currently available, e.g. `["HIDE","MOVE","TAKE LYSATE"]` |
| `player_observation.state.cues` | Party bodies with screen positions, plus instruction text currently on screen |
| `click_targets` | Named destinations the chunk exposes — e.g. `exit_shelter`, `upper_deck`, `bowl_center` |
| `move_refusals` | **Why a move did not commit.** Check this before concluding movement is broken. |
| `characters`, `selected_characters`, `active_character` | Who exists, who is selected |
| `chunk` | Run state: `branch_span_states`, `blocked_nodes`, completion, route phase |
| `paused`, `ready`, `stage` | Lifecycle |

### The loop

Perceive → choose → act → verify, exactly like a player:

1. Read `affordances`; pick one by its **verb**, not by where you think it is.
2. Click its `screen` point with the **RIGHT** button to commit a move/interaction.
3. Re-read the bridge. Confirm the intent landed: `selected_characters`, `chunk` progress, and
   critically `move_refusals` — an empty click is a refusal with a reason, not a mystery.
4. `Space` pauses without stopping the UI lane, so pause, read, decide, unpause. Screenshot while
   paused if you need to look.

### What else the bridge is for

It is not only a click oracle. It carries the timing a real decision needs and that a screenshot
cannot show: **movement durations**, when a character would **enter an enemy's detection range**,
and the **schedule of environmental hazards** (a channel's next onset, a basin's next commit). Those
are the numbers a player is actually reasoning about, so a driver that ignores them is not playing
the game either — it is walking through it with its eyes shut. Prefer reading a hazard's next onset
over sampling frames until something happens; the analytic value is the authority and the frames are
cosmetic.

### Re-export or you are testing the past

`build/web` never rebuilds itself. Export before every play session:
`../Godot_v4.7-stable_win64_console.exe --headless --path "." --export-release "Web" build/web/index.html`
A five-day-old export happily hides every fix made since, and the run will look like a regression.
