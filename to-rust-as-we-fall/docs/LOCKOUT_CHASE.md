# The Lockout Chase — scene design (GDD §12.1) + the portal-offshoot beat

**Status: PROPOSED (director approval required).** Canon spine: GDD §12.1 (position, phases,
Tyreg accept/decline, aftermath at Endo's section), L751 (the lockout checkpoint at the vessel
wall's 6 o'clock), L763 (the failed re-entry as antecedent), L2557 (the party's tags fail here —
why later gates are credit-gated). **The GDD's satellite files `chase_scene_framework.md` (full
mechanics + the expert solution) and `lockout_chase_aftermath.md` (dialogue) are NOT in the
reference-docs mirror** — everything below marked [FRAMEWORK?] is designed to be overridden by
them once refreshed. The portal-offshoot beat is DESIGN_PRINCIPLES tension seed 3 ("sacrificial
activation"), promoted into the chase — including the shadow-solution cheese the director
flagged, closed below.

## Shape

One chunk (`lockout_chase`), three spaces, all reused geometry vocabulary:

1. **The checkpoint plaza** (the simulation boundary — gap A's facility checkpoint build, used
   twice: once quiet for the failed re-entry, once hostile here). Scan gates, tag reader, cool
   blue-white enforcement light — the one place Act 1 uses that register at full brightness.
2. **The return corridors** — the mid-Act-1 stretch the party just walked, now hostile: same
   rooms REVERSED, doors they opened now working against them (the GDD's "corridors they just
   came through, now hostile under chase conditions"). Familiarity is the design material:
   every lever they learned (doors, flora, terrain) plays mirrored.
3. **Endo's maintained section** — the boundary wall, the quiet aftermath room.

The chase is a PAIR context by construction (Aster + Peris attempted re-entry; Endo stayed out —
GDD L763/§12.1 names only the two). So "the shadow solution" here isn't a harder alternate — it
is the DEFAULT cast, with Tyreg as the optional third. That's why the offshoot cheese matters:
the chase must be tense for exactly the pair.

## The clock, not a leash

The chase runs on a WAVE TIMELINE, not per-enemy leashes: Naturalizer wave N enters corridor
segment S at scheduled tick T (scheduler-driven, fast-forward invariant, replayable). Nothing
resets when you break line of sight — the waves keep advancing on their timetable, so TIME spent
anywhere is spent from the escape budget. This is the architectural anti-cheese: there is no
aggro state to launder, only a timetable to be ahead of. [FRAMEWORK? — if the framework doc
specifies leashes instead, the timetable still drives spawns.]

- Phase 1 (pure environmental): waves 1–2, readable spacing; every corridor segment offers one
  lever (a door to close = +one segment of delay, a Chelator cluster [FRAMEWORK? not yet a
  class] to trip, a flora beat).
- Phase shift: Tyreg arrives at the mid-corridor junction with the accept/decline choice.
- Accept: three-hander loop — Aster hacks a terminal (portal to an ammo cache), Peris runs the
  ammo, Tyreg's Suppress deletes a wave's lead rank. The loop IS the chase.
- Decline: wave density scales; the expert out is Hushbloom portal-stunning [needs the Hushbloom
  class; full spec in the framework doc when refreshed]. First-play decline is expected to fail
  (canon says so — the game does not telegraph it).

## The portal-offshoot beat (seed 3, promoted)

Mid-corridor, one side gallery sits behind a PortalPad pair: the OFFSHOOT HIDE — a dead-end
maintenance bay parallel to the main run, rejoining two segments later. The pad's activation
console sits INSIDE a watch fan covering the junction.

**The presented play (with Tyreg):** she Suppresses the fan's watcher; activation is free; the
party ports, the wave sweeps past the empty junction, they exit BEHIND it — buying the plaza's
second gate the time it needs. Textbook seed 3 with the toll paid in ammo instead of blood.

**The pair play (no Tyreg):** sacrificial activation, as the seed wrote it — one of the two
stands the fan and takes the survivable strike (or times the whiff against the windup — whiff
rules exist), the portal opens, both slip into the offshoot, the sweep passes. It SHOULD work.

**The cheese (director's flag) and the four laws that close it:**

1. **One charge per arming.** The activation burns the pad's charge; it re-arms only from the
   NEXT terminal down the corridor (the same terminals the ammo loop uses). The offshoot is a
   card you play once per stretch of corridor, not a revolving door. (The register's own idiom:
   one bait = one window, P12 — no latch.)
2. **The hide is MEDIUM, not FULL.** The offshoot sheds a wave sweeping at OUTER range — but a
   Naturalizer that saw the entry inside its inner band posts at the mouth and camps (two-tier
   detection, already built, does this for free). Cheesing the portal point-blank in front of a
   watcher converts "hidden" into "cornered."
3. **The clock keeps running.** Hiding spends the timetable: wave N+1 enters the segment on
   schedule, and the exit corridor's own gate begins CLOSING on its own timer the moment the
   checkpoint alarm fired. The offshoot buys one sweep's worth of seconds — it can never buy a
   reset, because there is nothing to reset.
4. **The toll is real for the pair.** No Tyreg means the fan is live: the activation costs the
   strike (hp the aftermath scene will read) or the whiff-timing skill check. A pair that plays
   the offshoot perfectly has spent EXACTLY the resources the beat prices — that's a solve, not
   a cheese; laws 1–3 only remove the repeatable/free versions.

**Why keep it at all:** the offshoot is the chase's one BREATH — the pair play teaches
sacrificial activation under real pressure two acts before the Hushbloom expert path asks for
its cousin, and the accept path shows Tyreg's value by making the same beat cost nothing. Cutting
it would flatten the chase into a pure run; pricing it is better than removing it.

## Aftermath

At Endo's section the waves stand down at the boundary (enforcement doesn't cross into
maintained territory — [FRAMEWORK?], and it reads right: the wall Endo keeps is the line the
institution respects). The scene is quiet and character-forward per canon; hp/strike state from
the offshoot toll is allowed to show (limping into Endo's light is the correct image).

## Buildability

- ✅ EXISTS: wave scheduling (scheduler), pursuit/search/return FSM, two-tier detection +
  distraction, PortalPad group queueing, CrawlTunnel offshoots, whiff/dodge timing, shelters as
  sanctuary (Endo's section registers a region — the new law), corridors from the fragment
  vocabulary, real-input test machinery for a chase leg.
- ❌ NEEDS-BUILD: **Naturalizer** enemy class (fixed-route scan + lethal contact strike +
  granule-pack tell, fauna_roster L34 — tag_day fakes them scripted today); **Tyreg** temp party
  member + Suppress (ammo-fed ranged suppress verb); the **ammo-cache portal loop** (terminal →
  portal → carry, composes existing pieces); **Hushbloom** class (stun burst — also unlocks the
  decline expert path and two register elements); the **wave director** (a timetable runner on
  the scheduler); the checkpoint plaza geometry (shared with gap A's facility build).
- Tests, when built: `--test-lockout-chase-playthrough` (pair beats phase 1 + the offshoot beat
  via the data layer), the anti-cheese laws (charge burns, mouth-camp on inner-band entry, the
  timetable advances while hidden), and the accept-path three-hander loop.
