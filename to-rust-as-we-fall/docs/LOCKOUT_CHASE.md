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
  apron (safe for them) and the pursuit line breaks around it. LEVER 3 (Peris): a **Flure** on
  a fertile lip — one decoy redirection, pulling the lead rank up the dead gallery stair.
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
- **S4 — the flooded undercut** (~30 wu). LEVER 4: a **Scarpet run** down the dry side
  (friction + signal — the party crosses clean; pursuit slips wide). LEVER 5 (accept path):
  **ammo cache A** behind portal terminal 2 (the Tyreg loop: Aster hacks, Peris runs, Tyreg
  Suppresses the lead rank).
- **S5 — the collapse shelf** (~30 wu). LEVER 6: a **weak wall** over the shelf (the built
  weak-wall object): pried as the party passes, it drops rubble across the lane — the late big
  delay, priced by the pry dwell. LEVER 7 (decline path pressure): the second wave enters HERE
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
  Capbage grammar); PortalPad + group queueing; weak walls; Scarpet; Flure decoy; scheduler-
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
