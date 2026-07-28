# Gameplay Objects — the reusable kit vocabulary and its composition contract

The law is `docs/DESIGN_PRINCIPLES.md` §P-KIT: **chunks compose, kits own consequences,
and when a kit lacks a verb you extend the kit** — never fork the logic into a chunk
script. This page is the working inventory that law governs: what the objects are, what
each one owns, and the canonical shapes for composing them. The from-scratch wash_ascent
chunk (`scripts/fragments/chunks/wash_ascent_chunk.gd`) is the maintained worked example.

## The contract, in one paragraph

A kit object (`scripts/game/objects/*.gd`) owns its **mechanism and its consequence**:
cadence, catch, carry, damage, concealment, state authority, save/restore, scheduler
tags. A composing chunk supplies only **policy and presentation**: where things are
(scene-node placements), which characters/enemies are eligible, where "downstream" lands
(a `dest` Callable), and how the chunk's own visuals react (bound to the kit's signals).
If you find yourself re-implementing a catch, a teleport, a hide tick, or a win check in
chunk code, stop — either the kit already has the verb, or the kit should gain it
(backward-compatible export/method/signal, documented at the declaration).

## The vocabulary

| Object | Class / file | Owns | Chunk supplies |
| --- | --- | --- | --- |
| **Channel** | `Channel` — `objects/channel.gd` | Flood cadence (epoch-analytic, FF/replay-safe), catch poll, the RESERVED→CARRYING→IMPACT sweep transaction, fail-forward hp bite, refractory, state authority (`kit:channel:<tag>`) | `configure(x, half, z_half, period, dur, phase, tag, z_center)`, `set_sweep(gs, party, dest, opts)`, `start(sched, gs)`; bind visuals to `telegraphed`/`flood_started`/`flood_ended`; `owns_visuals=false` when the scene brings modeled water; `hold(duration)` is the valve verb |
| **Flure** | `Flure` — `objects/flure.gd` (extends `Interactable`) | The lure transaction: activation nonce, target pulling via enemy `lured` state, settle/park, deferred targets, state authority | `configure(gs, pos, target_ids, attract, radius, color)`, property tuning, `set_enemy_resolver`, connect `flure_activated`; only Sapscraps/Aembers/Hidras answer (ecology law) |
| **Capbage / hide flora** | pieces + engine concealment | `GameState.set_character_concealment` (CONCEAL_NONE/MEDIUM/FULL) drives detection; derived state, replay-rebuilt | The proximity TICK (per `_process`/`headless_process`): set the tier from hide-zone distance. Scarpet = MEDIUM, Capbage = FULL |
| **CrawlTunnel** | `objects/crawl_tunnel.gd` | Conceal+slow+authored-path traversal, the PORTAL RULE (one-at-a-time group queueing) | Mouth placement, `set_group_provider` |
| **PortalPad** | `objects/portal_pad.gd` | Pair transit, one-at-a-time group crossing | Destinations. NOT a win object — no completion/rest semantics |
| **Interactable** | `objects/interactable.gd` | Click-gated activation (INSPECTION default), outline/verb grammar, dwell | Verb text, radius, trigger handler. Never re-add a per-chunk highlight |
| **exit_shelter** | `data_fragment_chunk._spawn_exit_shelter` (loader-local) | Click-gated rest-to-complete, downed-guard preflight, atomic `command_party_rest`, sanctuary region | **EXTRACTION LEDGER**: this is the one win object and it is not yet a class — refuge_run/generated_stretch re-implementations are the evidence it wants inheriting. Until extracted, a slice exit stays a thin completion and says so (see wash_ascent `_on_portal`) |

## Canonical composition shapes

**Channel with scene-owned visuals** (wash_ascent `_build_wash_channels`): the kit owns
the wash; the chunk's piece-built water binds to the signals.

```gdscript
var ch := Channel.new()
ch.owns_visuals = false                  # the modeled water sheets are the view
ch.telegraph_lead = TELEGRAPH_LEAD
ch.configure(cx, half, 1.4, period, dur, grace + phase, "wash_ascent_ch%d" % i, 0.6)
ch.telegraphed.connect(_on_channel_telegraph.bind(i))
ch.flood_started.connect(_set_wash_state.bind(i, "flood"))
ch.flood_ended.connect(_on_channel_flood_ended.bind(i))
add_child(ch)
# at reset: ch.set_sweep(gs, PARTY_IDS, _sweep_landing.bind(i), {"party_hp": 6.0, ...})
#           ch.start(sched, gs)
# the valve: ch.hold(VALVE_HOLD_WINDOW)   — ends an in-flight flood, skips swallowed
#           onsets to the next analytic beat; presentation reacts via the signals
```

**Flure** (lure_relay is the full relay; wash_ascent's lonely flure is the minimal one):
`.new()` → `configure(gs, ...)` → property tuning → resolver/provider Callables → signal
connects → `add_child`. An empty target list is legal — the wash_ascent story beat "the
flure sings, nothing answers" is the wiring working, not a stub.

**Concealment tick** (wash_ascent `_tick_concealment`): a hide element is the engine
tier set from proximity every step, in BOTH `_process` and `headless_process` so play
and headless agree. Concealment is derived state — never logged, rebuilt on replay.

## Rules of thumb

- Scheduler tags belong to the kit (`<tag>_onset`, `<tag>_sweep`, ...). A chunk never
  cancels a kit's tags — it calls the kit's verbs (`hold`, `reset`, `flood_now`).
- The `dest` Callable is *the only spatial policy* a chunk hands a Channel. Spread
  landings by identity so a party never stacks a cell.
- Kit visuals are legacy primitives in places (Channel bed/water, Flure glow bulb). In
  piece-built scenes: `owns_visuals = false` (Channel) or hide the bulb (Flure) and let
  library pieces be the body — the no-primitives lint checks what RENDERS.
- New verbs go in the kit with a doc comment at the declaration (the way
  `Channel.hold()` and `telegraph_lead` were added), keeping defaults that leave every
  existing scene byte-identical in behavior.
