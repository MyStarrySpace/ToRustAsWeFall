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
- `--test-persona-probe` — the SYSTEMS pass (data fragments with real
  economies; enrolled: basin_fill_proof, push_lab). The roster below runs
  here. New fragments with prices enroll by adding a row.

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

**Future candidates (real personalities, not yet built):** Jirard the
Completionist (touches and re-touches EVERYTHING — the re-arm/double-count
hunter), DarkViperAU (the speedrunner — routes around content, spends hp as
currency; asserts the pacing floor holds).

## Invariants checked for EVERY persona, every beat
- Stats sane: hp/stamina/ATP finite and within [0, max].
- Bodies legal: every idle character stands in-bounds on a cell its grid
  level allows (moving/carried bodies exempt until they land).
- Time flows: the gameplay scheduler tick strictly advances.

## Adding a persona / an enrollment
One row in the PROBE_PERSONAS table (reflex callable + assert callable) or
one row in PROBE_FRAGMENTS (fragment id + per-fragment price facts the
exploiter asserts against). Keep each persona to a few reflexes a REAL
player type has — a persona that plays well finds nothing.
