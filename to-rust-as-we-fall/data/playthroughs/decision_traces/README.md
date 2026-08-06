# Persona decision evidence

Persona decisions are recorded as `persona_decision_trace_v3` JSONL. A trace
is evidence about the complete player-reproducible decision chain:

```text
full player_observation_v1 before -> persona rationale -> public decision
  -> shipped input -> de-duplicated presented-frame observations -> full after
  -> writer-derived visible feedback/outcome -> writer-derived persona goal
```

The trace is append-only and hash-chained. Run identifiers, seeds, content
fingerprint schema/digest pairs, repeat indexes, baselines, observations, input
receipts, derived results, summaries, manifests, and validation receipts must be
deterministic. Dates, wall-clock time, absolute workstation paths, hidden
solution data, private AI state, world transforms, and fixture movement do not
belong in a measured trace. `persona_decision_trace_v2` files remain readable
diagnostic history, but they are inadmissible for v3 policy promotion.

## Runtime integration

Use `PersonaDecisionTrace` from
`res://scripts/testing/persona_decision_trace.gd`.

1. Boot the authored scene through the same entry path as the player.
2. End fixture quarantine and establish a fresh `evidence_baseline_id`.
3. Compute a stable authored-content identity with `ContentFingerprint`: authored
   fragments use `authored_fragment_resource_bytes_v1`; generated layouts use
   `generated_spec_semantic_v1`. The latter hashes a canonical semantic
   projection and excludes runtime/platform bookkeeping. Also record a separate
   stable `gameplay_build_fingerprint_schema` and
   `gameplay_build_fingerprint` for the executable/export that supplied the
   mechanics. The current schema is `gameplay_build_resource_set_bytes_v1`.
   Content and build identity answer different questions and must
   never be collapsed; behaviorally different builds cannot pool evidence.
4. Call `begin()` with a stable `run_id`, `trace_id`, persona, fragment, seed,
   `repeat_index`, content-fingerprint schema and SHA-256 digest,
   gameplay-build schema and SHA-256 digest, execution platform, and
   authored-state origin.
5. For each decision, give policy only the complete validated
   `player_observation_v1`. Persist the exact `observation_before`, record the
   persona rule/rationale and public decision, execute it through the shipped
   input driver, capture observations from every relevant presented frame,
   settle, and persist the exact `observation_after`. Before, samples in first
   seen order, and after must form one chronological sequence. Pass the raw
   observations and input receipt to `append_decision()`; do not supply feedback
   or outcome. The writer canonically de-duplicates repeated samples without
   reordering the remaining chronology.
6. Call `finish()` with a requested `trace_complete` value and diagnostics.
   Do not supply `persona_goal_reached` or goal proof. The writer derives the
   supported persona goal from the persisted observation sequence and forces
   the trace incomplete when any decision is ineligible or the goal is unproven.
7. Do not validate a trace inside its individual run. For the Basin, assemble
   exactly DeanTakahashi and EazySpeezy at repeat indexes 0 and 1 for one
   execution platform, one authored-content identity, and one gameplay-build
   identity. Create one
   `persona_strict_invocation_manifest_v1` over all four trace documents.
8. Only after the full platform invocation and its preview assertions finish,
   append a `persona_strict_validation_v1` record to each trace. The receipt
   embeds the common manifest and binds its member's run/trace identity, repeat,
   platform, fragment, content and gameplay-build identities, summary hash,
   exact decision count, derived completion, and goal. A failed invocation
   appends failed receipts; an interrupted or filtered invocation remains
   unattested.

Validation records are also append-only and hash-chained. More than one is
allowed so a sealing error or later invocation failure can revoke a partial
green write; the final record is authoritative. The Native and Web validators
are `godot_windowed_persona_probe` and `playwright_persona_probe`; current
contract IDs end in `_v3`. Native and Web manifests are independent. A trace
without the current final receipt and a complete recomputable platform cohort
is readable for diagnosis but cannot update a tree.

Every policy input and recorded observation declares `player_observation_v1`
and persists the full validated snapshot. Its state allowlist is deliberately
narrow: the shared controller's HUD portrait bars/status/selection,
opaque-token affordances (`token`, `kind`, `verb`, presented consequence, and
screen coordinate), sorted de-duplicated exact `visible_affordance_verbs` and
`visible_affordance_consequences` recomputed from those current affordances,
visible cue records, and semantic viewport bins. Policy predicates use exact
`contains` membership on these lists rather than fixed affordance indexes; an
unrecognized interaction records no `learning_candidate`. Unknown
fields are rejected. Internal node names are not tokens. A `player_observable`
label cannot admit world coordinates, levels, grid cells, detection ranges,
private FSM state, completion flags, solve anchors, validators, or raw
action-receipt history.

Optional briefing/help text is neither observation authority nor the sole
feedback channel. A persona may hide it through the shipped `H` input, but
command acceptance/refusal, movement progress, and consequence cues must remain
player-observable elsewhere and be sampled into the trace. The input receipt is
corroboration, not presentation feedback.

The writer derives feedback and outcome from the chronological
before/sample/after sequence
and the input receipt, and `read_trace()` recomputes both. For interaction, only
a visible `interaction_result` with a presentation serial newer than the
pre-click value and a `source_token` matching the exact visible target token can
establish success or refusal. A stale result, a different target's result, or a
silent state change is ineligible. Every accepted or refused movement or state
change likewise requires a visible presentation delta; no caller-authored
success boolean can replace it. Move and Rally require a monotonic causal
presentation lineage bound to the chosen target token and every intended HUD
portrait token. An unrelated cue, camera/viewport drift, or a generic movement
delta cannot prove that the issued command caused the claimed result.

Supported persona goals are writer-derived and reader-recomputed. Basin Eazy
requires a new exact-target REST/SHELTER success and the same action's visible
full-party secured/settled cue. Basin Dean requires a visible Basin-rise warning
followed chronologically by same-label, same-destination `SWEPT` active and
arrival cues for every portrait in the warning's visible HUD roster.

A group decision such as Rally remains one decision, one held gesture, and one
production event over exactly every portrait visible in the HUD roster.
`select_party` binds that same exact full roster. Their receipts record
`member_results` for every intended character. If any visible portrait has no
shipped binding, the whole action fails closed before movement. Singleton
commands cannot be assembled after the fact and labeled Rally.

For the current promotable Native/Web persona contract, every active action must
have a mechanically issued keyboard/pointer ledger from the shipped driver.
`player_command` is allowed only for a passive wait that changes no world state.
Controller and touch are reserved boundary labels until equivalent mechanical
issuance and presentation-proof contracts are implemented; records using them
are currently diagnostic/nonpromotable. Direct state mutation, singleton moves,
snap, and teleport are forbidden. The sole teleport exception is an authored
portal entered through its production interaction and portal mechanic.

`learning_candidate` is optional. Omitting it records a decision without
proposing a policy update. A candidate must explicitly provide:

- a lower-snake-case `node_id` and human-readable `rule`;
- a `condition` over the recorded observation;
- the public `action` actually executed;
- an `expected` predicate over the recorded outcome;
- a `scope` (`fragment`, `mechanic`, or `global`) and numeric priority.

Predicates use `all`, `any`, `not`, or a leaf with `path`, `op`, and `value`.
Supported leaf operators are `eq`, `neq`, `lt`, `lte`, `gt`, `gte`,
`contains`, and `exists`. Before policy storage and signature comparison, the
distiller recursively collapses singleton `all` and `any` wrappers to their
child; genuine multi-branch predicates remain ordered and intact. This makes
equivalent platform encodings merge without treating different logic as the
same policy.

## Distillation

Preview a focused four-trace, single-platform update without touching the
canonical library:

```powershell
& $env:GODOT_BIN --headless --path . `
  --script res://tools/distill_persona_decision_library.gd -- `
  --trace=<native-or-web-dean-repeat-0.jsonl> `
  --trace=<native-or-web-dean-repeat-1.jsonl> `
  --trace=<native-or-web-eazy-repeat-0.jsonl> `
  --trace=<native-or-web-eazy-repeat-1.jsonl> `
  --output=user://decision_library.preview.json
```

This direct command is useful for diagnosis, but direct `--in-place` is not the
release promotion path. A promotable update requires one fresh combined 4+4
cohort and the tracked archive/promotion helper. From the repository root:

```powershell
# Windowed and Web must run together; separate invocations cannot aggregate.
& .\scripts\test-gate.ps1 -Tier Windowed,Web

# Dry run: validates and re-distills archived copies without changing canonical.
& .\scripts\promote-persona-cohort.ps1 `
  -GateRunDirectory .\.test-gate\<run-id> `
  -GodotPath $env:GODOT_BIN

# Explicit promotion after review.
& .\scripts\promote-persona-cohort.ps1 `
  -GateRunDirectory .\.test-gate\<run-id> `
  -GodotPath $env:GODOT_BIN `
  -Promote

# Does not invoke Godot or touch the canonical project library.
& .\scripts\promote-persona-cohort.ps1 -SelfTest
```

The default dry run stages a self-contained archive beneath the selected gate
run. `-Promote` writes the durable archive to
`data/playthroughs/decision_traces/cohorts/<run-id>/` and refuses to overwrite
or merge an existing cohort. It preserves byte-exact source traces,
manifests, combined report/preview, and canonical preimage. It also writes
rebased artifact manifests whose `traces[].path` values name the archived
copies, then uses those copies for a frozen-preimage re-distillation and second
combined validation. Candidate and gate preview must match byte-for-byte and by
SHA-256, and the live canonical file must still match the archived preimage.
Promotion uses same-directory atomic replacement, retains a recoverable backup
and verified postimage, and inventories the self-contained archive so it
remains auditable after `.test-gate` is removed.

The distiller:

- verifies every record hash and the complete chain;
- gates the whole run on its hash-covered `trace_complete: true` and
  `persona_goal_reached: true` summary before consuming any decisions;
- independently rescans every decision and rejects the whole run if even one
  action crosses the human-playable evidence boundary;
- requires the final current strict-validation receipt, bound to the run and
  summary, with an exact decision count and a green whole-invocation verdict;
- groups all four platform traces, reconstructs the fixed Dean/Eazy by
  repeat-0/repeat-1 manifest, and rejects a caller-authored subset or mismatch;
- recomputes playthrough eligibility instead of trusting a trace flag;
- rejects internal mutation, fixture evidence, missing feedback, unrelated
  receipts, decomposed group verbs, incomplete visible rosters, unbound members,
  missing per-member results, active `player_command`, and unproved controller or
  touch input;
- requires move/Rally proof to bind the chosen target and exact HUD portrait
  tokens through a monotonic presentation lineage, never a generic cue or camera
  drift;
- never infers a machine branch from prose;
- deduplicates exact record hashes;
- preserves support, contradiction, run, fragment, persona, authored-content,
  gameplay-build, and receipt provenance, and prevents behaviorally different
  builds from pooling;
- validates a node only after support from at least two distinct traces and
  runs with no contradiction; fragment nodes may use repeated full-goal runs on
  the same authored content, while a global node also needs two distinct
  authored-content identities (configurable with `--minimum-support`);
- emits deterministic per-persona trees containing validated nodes only.

Historical `persona_decision_library_v1` prose is retained as
`legacy_unverified`, but is not eligible for automation. It must be re-earned
through fresh player-reproducible v3 cohorts before a non-AI generated-level
player may execute it. Existing v2 traces and v2 library provenance remain
readable for diagnosis but are non-executable and cannot gain support through
migration alone. The current v3 trees are partial, bespoke policies. A general
bulk non-AI player that chooses from level observations is a future goal, not a
completed capability.

The Native Windowed and Web Chromium release gates each produce their own
isolated cohort. Native uses an artifact-owned Godot `user://`; Web uses a fresh
export, browser context, and run-owned artifact directory. This contract does
not assert that the latest full cohorts are green; only fresh gate outputs and
successful independent distillation establish that.

Run the focused pipeline verifier after changing this contract:

```powershell
& $env:GODOT_BIN --headless --path . `
  --script res://tools/verify_persona_decision_pipeline.gd
```
