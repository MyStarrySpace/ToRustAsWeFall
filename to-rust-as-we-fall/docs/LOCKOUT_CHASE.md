# The Lockout Chase — corridor-level implementation spec (PROPOSED)

**Canon**: `reference-docs/chase_scene_framework.md` (now mirrored — the chase pattern is LOCKED:
trigger → distance → corridor/levers → phase shift → boundary → chase-end beat → aftermath, real
failure via reset; mechanics LOCKED: pause + speed-up always on, switching + abilities live,
stamina primary, levers core, sparse dialogue) + GDD §12.1 + `lockout_chase_aftermath.md` (the
scene draft/dialogue). This doc fills the framework's OWN open task: *"Specific corridor
geometry: where the offshoot portal is, where the gap window opens up, where the tight-hides are
inside the offshoot. Implementation-level spec needed when the scene moves to Godot."*
Everything here is FLEX-tier tuning under the locked shape; director approval required.

**Correction from the earlier draft of this doc:** the portal offshoot is NOT an exploit to
close. It is the **decline-path expert solution** (canon: portal-stun double-seal of an offshoot
with tight-hide spots — knowledge-gated, no UI flag, default no environmental hint). The
anti-cheese IS the knowledge gate: portal-stunning is taught in Act 2/3, the offshoot is unmarked
geometry, the gap window must be engineered with levers, and the two-portal seal is a
reasoning-step beyond every taught use. Nothing else needs closing.

## The corridor (checkpoint → boundary), segment by segment

Linear spine, ~150 wu, six segments + the plaza and the wall. Naturalizer base speed = party
sprint × 1.12 (framework start value 10–15%). Stamina budget: full-sprint collapses in S4;
sprint/walk alternation + competent levers arrives with margin (framework law). Levers never
regenerate mid-chase; a sealed door also blocks YOUR retreat.

- **S0 — the checkpoint plaza.** The simulation-boundary scan gates (the facility build, gap A —
  shared with the failed re-entry scene). Trigger: Aster's tag rejection escalates; Naturalizers
  activate from concealed wall niches (initial distance ~18 wu, seen and heard). Cool blue-white
  light; the scanner's rejection chirp is the starting gun.
- **S1 — the queue hall** (~20 wu). LEVER 1: a **sealable service door** at the hall's exit
  (first-sight readable: a lit panel + a heavy slab). Sealing costs ~2 s and buys the biggest
  single delay in the chase (the wave must cut through). Teaches the lever grammar immediately.
- **S2 — the conduit gallery** (~25 wu). LEVER 2: a **Chelator cluster** feeding on an iron
  seep along the left wall — the signature protocol-hesitation beat: Naturalizers detour wide of
  iron-feeding fauna (the framework's canon slowdown). Route the party THROUGH the cluster's
  apron (safe for them) and the pursuit line breaks around it.
- **S3 — the junction + THE OFFSHOOT** (~25 wu; the corridor's midpoint). Tyreg's side corridor
  enters here (phase shift + accept/decline choice, canon). The junction is watched by a fixed
  scan fan. And one of the junction's THREE portal terminals is different:
  - **The offshoot portal** sits recessed behind the junction's pipe bank — visually identical
    to the two ammo-cache terminals beside it (no flag, canon: "not flagged as mechanically
    important"). It ports into the **offshoot chamber**: a 6×4 dead-end maintenance pocket
    BETWEEN S3 and S4 (parallel to the spine, no walking connection), containing its own exit
    portal (returning to S4's mouth) and **two tight-hides** — a Capbage growth against the
    north wall and a collapsed locker shell against the south (capacity ONE each, standard
    tight-hide mechanics: CONCEAL_FULL, search-cycle behavior, listening-through-cover).
  - In normal play the offshoot is a *shortcut with a toll*: hacking the portal (Aster, ~3 s
    inside the scan fan — the sacrificial-activation grammar) skips S3's watched half. The
    expert solution lives in the same geometry (below).
- **S4 — the flooded undercut** (~30 wu). LEVER 3: a **Scarpet run** down the dry side
  (friction + signal — the party crosses clean; pursuit slips wide). LEVER 4 (accept path):
  **ammo cache A** behind portal terminal 2 (the Tyreg loop: Aster hacks, Peris runs, Tyreg
  Suppresses the lead rank).
- **S5 — the collapse shelf** (~30 wu). LEVER 5: a **weak wall** over the shelf (the built
  weak-wall object): pried as the party passes, it drops rubble across the lane — the late big
  delay, priced by the pry dwell. LEVER 6 (decline path pressure): the second wave enters HERE
  from the side corridor Tyreg would have cleared.
- **S6 — the boundary run** (~20 wu, lever-less by design). Pure stamina math: whatever margin
  the levers bought is spent here. **Endo's wall**: Naturalizers stop at the maintained line
  (canon — they do not cross into maintained territory; the wall registers a shelter region, so
  the sanctuary is mechanical, not scripted). Chase-end beat + the aftermath scene
  (`lockout_chase_aftermath.md`) play here.

**Close-approach escalation** (canon): 1st close = the warning beat (audio + a grab-whiff),
2nd = real damage (a landed strike), 3rd = caught → the reset fires (default reset rolls back
zone progress + kills zone flora; a carried extraction item preserves progress).

## The expert solution, placed (decline path)

Canon steps mapped onto the geometry above — Aster + Peris only, second wave live:

1. **Engineer the gap window**: seal S1's door AND break the line at S2's Chelator — with both
   levers spent, the pursuit gap at S3 peaks (~9 s at tuning start). That window is the only
   time the choreography fits; a player who spent the levers early or badly doesn't get it.
2. **Aster hacks the offshoot portal** (the 3 s activation inside the now-empty scan fan).
3. **Both enter.** Inside, **Peris stun-throws a Hushbloom at the offshoot's EXIT portal**
   (sealing the back door), both step back out through the entrance portal, **stun it from the
   corridor side**, and re-enter as the stun blooms — the two-portal seal, the reasoning step
   no taught use demonstrates (all taught uses stun ONE portal).
4. **Each takes a tight-hide** (one per character — capacity forces the split; the pair listens
   through cover as the waves sweep S3).
5. **Search cycle runs dry**: the Naturalizers patrol the spine, lose the trail (full conceal =
   never spotted; the search→return FSM already behaves this way), and move on. The stuns
   expire, the portals wake, the pair exits into an empty S4 and walks the rest.

Default: **no environmental hint** (the framework's stated default; the dead-Hushbloom-hint
variant is listed there as the alternative if the director wants a whisper).

## Buildability (against what exists today)

- ✅ EXISTS: pursuit/search/return FSM + two-tier detection (tight-hide = CONCEAL_FULL, the
  Capbage grammar); PortalPad + group queueing; weak walls; Scarpet; scheduler-
  driven waves; whiff/strike timing; stamina/sprint; shelter-region sanctuary at Endo's wall
  (the new law); wipe-restart (the reset's chassis — needs the zone-rollback + flora-kill
  flavor); real-input test machinery.
- ❌ NEEDS-BUILD (ordered): **Naturalizer** class (fixed-route scan, contact strike, granule
  tell, the protocol-hesitation hook); **Hushbloom** class (stun burst + carry/throw — unlocks
  this scene AND two register elements); **portal stun state** on PortalPad (stunned = no
  transit, timed, enemy-blocking); **Chelator cluster** object (iron-feeding fauna terrain
  piece with a pursuer-detour aura); **Tyreg** temp member + Suppress (the EMP ability grammar,
  ammo-fed) + the ammo-cache carry loop (compose: terminal → portal → the carry verb);
  the **close-approach director** (escalation counter on the scheduler); the checkpoint plaza
  geometry (shared with the failed re-entry — build once).
- Chunk: `lockout_chase` on the fragment loader; tests when built:
  `--test-lockout-chase-playthrough` (accept path three-hander to the wall),
  `--test-lockout-chase-expert` (decline path: the gap window is real, the double-seal holds,
  the search cycle dries, exit clean — all data-layer), plus the escalation counter
  (warning → damage → caught → reset) and "levers never regenerate."

## Variants + connections (from the framework, for the spec's completeness)

- Party variants: pair (decline), trio w/ Tyreg (accept). Aftermath is Aster+Peris alone either
  way (canon).
- Pays off: the terminal data trail, Endo's maintenance arc, the failed re-entry; sets up Tyreg's
  Archive Depths recruitment as a second meeting (accept) or first (decline).
- Future chases reuse this chunk's machinery: patrol-failure chases (Act 2), swarm flights,
  Peris-sundowning inversions, NK night infiltration (the framework's anticipated list).

## The chunk composition (structure v2 — PROPOSED, director approval)

"The corridors they just came through, now hostile" is the design material — so each segment
QUOTES a chunk the player has already learned, replayed in reverse under pursuit. One fragment,
one grid, one loader (no nested scene-chunks); each segment is that chunk's signature vocabulary
rebuilt as chase dressing + its lever:

| Seg | Quoted chunk | What it contributes under pursuit |
|-----|--------------|-----------------------------------|
| S0 | `facility_checkpoint` kind (built) | the plaza, scan gates, queue rails; the trigger |
| S1 | **stacks** (Open Files) | data-terminal ROWS as weave-lanes; conduit troughs pulsing AGAINST your direction (you run against the data flow); the door lever at the hall's exit |
| S2 | **pump_hall** | pipe gantries + the iron seep feeding THE CHELATOR CLUSTER |
| S3 | **lure_relay** | the watched junction fan grammar; Tyreg's side mouth; THREE look-alike portal terminals (two ammo caches + the unmarked offshoot) |
| S4 | **channels_wash_intro** | a REAL Channel wash strip crossing the corridor, flow-strip tell live — time it like the channels taught you; a wave following badly is SWEPT (the canon environmental slowdown); the Scarpet dry lane beside it |
| S5 | **sprint_gap** | the stamina squeeze; the weak-wall pry; the decline side-wave mouth |
| S6 | **endo_junction_stretch** | the maintained wall + hearth light + Endo working at a distance; the sanctuary region; the aftermath framing |

Pedagogy check: every lever is a mechanic the player used in the quoted chunk's own scene — the
chase tests the course they already passed, at speed, in reverse. Build order once approved:
S4 (the Channel object is loader-ready) → S1 terminals → S2 gantries → S3 junction dressing →
S5 → S6 visual upgrade.

## Build state (v1 BUILT 2026-07-12; pursuit fixed 2026-07-13)

`--preview=lockout_chase` ("The Lockout Chase (Act 1 climax)", picker top). Built: the checkpoint
plaza (the new `facility_checkpoint` kind) + scanner trigger -> scheduled Naturalizer waves; the
sealable door (holds cutters DOOR_HOLD_SECS, never re-opens); the Chelator hesitation zone (real
logged slow on every pursuer); the Scarpet lever; the UNMARKED offshoot pocket (portal pair,
two capacity-one Capbage tight-hides, SEAL points that spend carried Hushblooms to stun the pads
— pursuit walks to the receiver and follows through OPEN portals over a saved PortalPad transit,
so only the double-seal locks the pocket); Tyreg's
junction choice (accept = v1 auto-Suppress escort, 3 charges; crossing S4 without her fires the
side wave); Endo's wall = a real shelter region + the completing rest. Failure = party wipe ->
the loader restart. Guarded by `--test-lockout-chase` (24 asserts, in `--test-all`).

Follow-ups (the framework's full fidelity): Tyreg as temporarily CONTROLLABLE + the ammo-cache
portal loop (hack/carry/deliver), the close-approach escalation director (warning -> damage ->
caught) instead of native strikes only, the zone-rollback + flora-kill reset flavor, weak-wall
lever at S5, aftermath dialogue from lockout_chase_aftermath.md, and the real-input leg.

2026-07-13: **the chase actually chases** — `Enemy.engage_target()` (chase-grade acquisition
honouring every detection gate: downed / sheltered / fully-concealed targets refused) + the
chunk's pursuit director (0.8 s scheduler poll re-engaging any pursuer that dropped to a
scanning state toward the nearest party member). No detection-radius leash; tight-hides and
Endo's wall still break the track. Red/green: the wave previously stood at the plaza forever.

## Playtest probe round 1 (2026-07-13) — the streamer-persona pass

`--test-chase-probe` (diagnostic, not in --test-all) drives six no-meta-knowledge strategies and
prints traces. Findings FIXED this round:
- Sprint-only used to WIN untouched -> pursuer speed 6.0 (effective ~3.4 vs the rescan
  tail-chase) + Naturalizer CONTACT-strike timing (windup 0.35 / recover 0.55 — the canon
  "lethal contact-strike"; the default lunge dance whiffed on runners forever). Now: sprint dies
  at x=136; ONE well-played lever completes at 75/50 hp; Tyreg's route completes at 75/100.
- The wipe-restart dropped the party 4 wu from live re-posted pursuers (instant re-wipe, the
  alt-F4 trace) -> the chunk's restart despawns the waves, cancels the timeline, resets the
  scanner ("Quiet again. The scanner waits. So do they.").
- The sealed door re-stunned forever (an infinite freezer) -> holds each cutter EXACTLY once.
- The unsealed offshoot was accidentally safe (pursuit toward the disconnected island moved
  nobody) -> pursuers now WALK to the pad, port in, and punish unsealed campers; with nothing
  visible to hunt they port back out (no dead-end camping).
- Zero guidance -> the RUN-east directive + niche-activation notes + the close-call warning beat
  ("Right behind you—", the escalation's first rung).

REMAINING (round 2, director's call): scarpet reads as a hide but MEDIUM tier = death vs contact
pursuit (teach it, or make scarpet FRICTION that slows pursuers); the Tyreg beat is a pedestal
click with no drama; the framework's optional dead-Hushbloom hint at the offshoot; the full
3-close-approaches-then-caught escalation rung; sprint/stamina integration for the whole party in
preview mode.

## Playtest round 2 (2026-07-13) — frame drops, the breaker, terrain

**THE FRAME DROPS, measured and fixed** (`--test-chase-perf`, kept as a diagnostic with
PERF_MODE bisection arms + Enemy.PROF accumulators): headless data-side steps averaged 110 ms
with 1.8 s spikes. The bisection walk: not pursuit A* path length, not detection, not tweens
alone, not get_position — the payload was the chase pack inside the COOPERATIVE PLANNER: six
pursuers re-planning every rescan against each other's reservations drove the space-time search
into deep wait-state explosions (a 5 wu hop cost 30-90 ms hot). Fixes, each measured:
1. `GameState.set_coop_exempt(id)` — chase packs route by plain A* and neither write nor consult
   reservations (a mob is not a stealth puzzle). Mean 110 -> 18.8 ms/step.
2. Capped pursuit/search hops (`pursuit_direct` + `pursuit_hop`) — no full-length contested plans.
3. Enemy cosmetic-tween hygiene: kill-and-replace on the flash/recover/fade sites + cosmetics
   skip entirely on a headless tree (each FSM beat leaked a live frame-driven tween there).
Residual: rare ~0.6-1.1 s single spikes late-chase remain UNDER INVESTIGATION (instrumentation
is in place; suspects narrowed to the decline-wave moment + shelter-refusal churn).

**The breaker pass (SpiffinBrit):** strolling the course WITHOUT presenting tags used to roll
credits — the wall rest now refuses pre-lockout ("Endo looks up, nods at the checkpoint...")
and the refusal re-arms the one-shot pad. Red/green in `--test-lockout-chase` (26).

**Terrain (director: "the ground is too flat"):** APPROVED DIRECTION, next build — two breaks in
the flat run: (a) a service TRENCH across S2/S3 (unwalkable band), crossed by TOPPLING a conduit
rack (INSPECTION lever; the fallen rack is the bridge — and the pursuers' funnel: they clamber
it one at a time on a delay); (b) the S5 collapse shelf becomes literal: a debris barricade with
a slow exposed CLAMBER crawl over it (CrawlTunnel), pursuers funneled the same way. Both reuse
built machinery (grid gaps, CrawlTunnel authored paths, the topple = push-lab grammar).

## Round 3 (2026-07-13): the flow field + the trench beat

- **Crowd memoization** (director's call): pursuit hops now read ONE shared BFS distance field
  per director tick (seeded from every engageable quarry, spread over grid.is_walkable) instead
  of N per-unit path queries per rescan. Enemy grows `pursuit_hop_resolver` (a scene-provided
  Callable); the chunk owns `_refresh_flow_field` / `_flow_hop`. Because the field reads
  is_walkable LIVE, **movable objects reshape pursuit automatically** — guarded: a re-blocked
  trench cuts the field, the fallen gantry reopens it within a tick.
- **The trench beat** (director's design): the stretch's throat has an UNCROSSABLE service
  trench (dynamic blockers from build) — the breaker's tagless stroll now dies architecturally,
  not just at the wall gate. On the tag rejection, the ground-shake of enforcement tearing out
  of the walls drops the conduit gantry across it: the way OUT opens exactly as the way home
  closes. The wipe-restart re-seals it (gantry back up, blockers back on).
- Tuning: NAT_SPEED 5.4 with the smarter field pursuit. The probe matrix now lands on canon's
  accepted-loss branch: sprint-only completes but LOSES the trailing member (3 strikes over the
  runway); one-lever play the same; Tyreg or fuller lever play keeps everyone alive. FLEX —
  director adjusts.
- Perf CLOSED (2026-07-13, the hunt): the residual late spikes were the DECLINE WAVE shipping
  without the pack wiring — no coop_exempt, so its two members ran full cooperative space-time
  planning and wrote reservations the party's own 90-cell plan then fought. Pinned by the new
  NATIVE per-callback scheduler profiler (EventScheduler.set_profiling/get_profile, chrono-based,
  + a cancelled-pop counter), after GDScript-side counters proved callback volume was tiny.
  Every wave now goes through one _wire_wave_nat. Worst step across the whole chase:
  1900 ms -> 8.1 ms; mean 1.76 ms/step. Lesson: when a spec dict is duplicated per spawn site,
  the wiring WILL diverge — one wiring function per pack, always.

## Round 4 (2026-07-13): the LONG course — segment identities built

150 -> 215 wu; the structure-v2 quotes are geometry now:
- **S1 the record hall** (stacks): two staggered TERMINAL BANKS as real grid obstacles — the
  whole chase S-bends through the weave lanes (the pursuit flow field routes around them live).
- **S4 the wash undercut** (channels): a REAL Channel crosses the corridor, flow-strip tell and
  all. The wash sweeps ANY body in the flooding strip — party knocked back + hp (fail-forward,
  one sweep per encounter via a per-body refractory), pursuers tumbled + stunned. Time it like
  the channels taught you; the pack reads no tells.
- **S5 the collapse shelf** (sprint_gap + the terrain break): a debris barricade seals the
  corridor; the CLAMBER (fast scramble crawl, group-queued) is the only way over — and pursuit
  funnels after you on a 4 s per-member stagger. NOTE: a click PAST the barricade refuses
  outright (disconnected grid) — the player walks to the debris and clambers, but a
  walk-up-to-partial fallback for refused long moves is a wanted QoL follow-up.
- Wave 1 now activates 4.5 s after the rejection (the shake beat covers it — canon's ~18 wu
  initial distance; spawning on the party's heels killed the trailing member in the hall).

TUNING STATE (FLEX, probe-measured): NAT_SPEED 4.4 — the pack falls behind on open runway and
catches at chokepoints (the framework's "barely ahead"). Tyreg's accept route (canon's expected
first-play path) completes, losing the trailing member. The NO-Tyreg routes currently wipe for
the probe's semi-smart player — canon EXPECTS decline first-plays to fail, but the competent
one-lever route should scrape through; the next balance pass needs per-death position traces
(where exactly the pack lands kills). The probe harness is ready for it.

## Round 5 (2026-07-13): PINCH POINTS — the crowd governor (director's design)

Narrow FLOW CONTROL gaps (one body wide) at x=58 and x=112: the party threads them clean; a
pursuer barreling in at pack speed TRIPS prone (a real obstacle — the body tips over) and every
pursuer behind CLIMBS the pile at a per-body toll. The governor is self-balancing: a bigger pack
piles higher and waits longer. Pinch 2 deliberately guards the WASH WAIT — the pack piles up at
the squeeze while you wait out the flood. Measured: Tyreg-route strikes fell 5 -> 2. Rules ride
the shared hazard poll (trip refractory per body; prone = stunned + tipped; climbers pay
CLIMB_SECS x pile, capped). Test isolation lesson: freeze FSM TAGS for statue-enemies in
multi-section tests — stun timers get overwritten by mechanics (the wash sweep) and expire
mid-test; three cascade red herrings before the freeze.

Balance state: Tyreg route healthy (2 strikes). No-Tyreg routes still wipe for the semi-smart
probe — next pass needs per-death position traces; the pinch placement tool is now available
for it (a third pinch before the barricade approach is the obvious candidate).

## Round 6 (2026-07-13): THE PAIR LAW + CHECKPOINT RUNBACKS + ROGUELITE DEALS (director's design)

**The pair law.** Solo play carries you a long way, but not to the end: the S5 debris shelf is a
boost-and-pull TWO-PERSON move (`CrawlTunnel.requirement` — a generic activation gate, reusable),
so the clamber refuses unless both Aster and Peris are up and at (or already over) the shelf; and
Endo's wall rest counts heads — both members up and inside the maintained section, or the gesture
sends you back (Endo never speaks). Red-verified: without the gate a solo runner sails over.

**Runbacks are checkpoints.** The corridor remembers the furthest section boundary the PAIR
cleared together (50 / 92 / 128 / 163 — the marker only advances when both cross alive, so the
checkpoint and the pair law are one rule). A wipe or manual restart resumes THERE: pair revived at
the marker, pack despawned and re-raised a fair 18 wu behind (canon head-start distance — the
first resume spawned at 9 wu and produced a death loop), world state KEPT (gantry down, door
spent, seals spent — levers never regenerate). The full from-the-top reset only happens before the
first marker.

**Pinch 3 = the rubble apron (x=152.5, gap z=0).** The probe's death traces showed the trailing
member dying while QUEUED at the clamber mouth (the one-at-a-time file-through is exactly what the
crowd governor exists for) — the third pinch sits right before the mouth so the pack piles up on
the apron while the party files over. The pinch list is ONE const now (`PINCHES` — the grid
builder read an inline copy; deduped, the decline-wave lesson).

**Roguelite deals.** Each Retrieval Descent run deals ONE chase at a seeded mid-descent depth
(`RunSession.LEVEL_CHASE`, never the opener, never the finale), only while the pair is whole (a
run that lost Aster or Peris gets a generated level instead). The chase's failure economy inside a
run is the checkpoint runback, NOT permadeath (`_roguelike_on_downed` exempts it); its wall rest
IS its shelter rest, so the branch modal follows completion naturally.

**Probe matrix (140 s window):** competent_runner COMPLETES (1 runback, 3 strikes, both 100 hp) —
the no-Tyreg route is beatable at last; tyreg_accepter survives indefinitely on checkpoint cycles
(184 wu, both 100 hp — slow grind, never a lost run); panic/curious/camper/stumbler fail with
cheap retries at their markers. Balance state: healthy. Open tuning: tyreg_accepter's grind pace
(its naive wash play keeps feeding Peris to the pack) — a real player reads the wash after one
sweep.
