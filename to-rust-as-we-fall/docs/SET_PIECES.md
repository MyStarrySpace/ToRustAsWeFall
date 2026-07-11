# Set Pieces — interactive gameplay geometry (director, 2026-07-09)

## Director's words (VERBATIM — the design authority for this doc)

> 1) I want to add a showcase for set pieces we might want to create. For example: a) pipes we can
> crawl through (and their entrances), b) pipes that we can rotate by pushing things that rotate,
> some parts where you control the water height and can't go into water, but you need to move some
> parts that float to the right height to cross from one part to another part, or some parts are
> lower and you can climb up and drown enemies. 2) This could be an overall grammar where finding
> the places to adjust the height in the water puzzle or rotating the pipes vs. Crossing them is
> separated by parts of other pieces. That's the beauty of my archetypes system and how Ideally I
> want it to work and generate so write this down verbatim. We can think of puzzle ideas like these
> to make for each setting

## What this means (working decomposition)

A SET PIECE is a reusable interactive geometry unit with a CONTROL side and an EFFECT side:

| Set piece | CONTROL (the verb you find) | EFFECT (the traversal/combat it gates) |
| --- | --- | --- |
| **Crawl pipe** | an entrance you can reach | traverse INSIDE the pipe to wherever it exits |
| **Rotating pipe** | a push-wheel / rotator you push | the pipe's exits realign — a crawl route connects or breaks |
| **Water basin** | a height control (valve/console) | floats rise/fall: at the RIGHT height they bridge a crossing; water itself is impassable |
| **Drowning pool** | the same height control | a LOWER part floods: climb up first, then raise the water to drown enemies standing in it |

**The grammar (the archetypes point):** the CONTROL and the EFFECT of one set piece are SEPARATED by
parts of OTHER pieces — you crawl a pipe to reach the water valve; the rotation wheel sits across the
basin the floats bridge. Generation composes set pieces by interleaving their control/effect halves,
which is exactly how the archetypes system is meant to work and generate (see the verbatim quote).
This nests into the existing law: P8 gated composition (you can't walk past an unsolved piece), P2
perception registers (WHO can find/operate a control), P10 shadow solves (a second, harder chaining
of the same controls).

**Per-setting generative direction:** invent puzzle ideas of this class for EACH setting/district
(the channels get water-height + pipes natively; other districts get their own set-piece families in
their idiom — e.g. Open Files rack-shutters, Greenfields planter-terrace weirs). Keep a growing list
here as pieces are designed.

## PROPOSED set pieces per setting (Claude, 2026-07-09 — director approval required)

Each is CONTROL + EFFECT with a traversal use AND a combat/stealth use, separable per the grammar.
Fauna/flora verbs checked against `reference-docs/fauna_roster.md` / `flora_taxonomy.md`; none
duplicates an ENVIRONMENT_ELEMENTS entry (no new valve-rotations, no new riding).

1. **Drawer-stair columns — The Open Files Initiative.** Floor-to-ceiling record cabinets; a pull
   lever extends one COLUMN of drawers at graded depths = a climbable staircase to the stack-tops.
   CONTROL: the lever at the aisle end. EFFECT: an inter-level link appears mid-aisle. Traversal:
   the only way onto the overwatch shelf-tops. Combat: retract while a Gnawer pack is climbing —
   they drop back to the floor; extended drawers also BLOCK that aisle (a re-shapeable wall).
   Grammar: the lever sits in the next aisle over, inside a patrol's sweep. Build: runtime
   add/remove of grid inter-level links + dynamic blockers (both exist).

2. **Iron-load magnet hoist — The Hypelines.** *(BUILT — set-piece showcase bay E.)* The Iron Heart
   moves payloads on an overhead electromagnet trolley; a charge lever energizes/drops the magnet.
   CONTROL: charge lever + a track switch. EFFECT: whatever iron sits under the magnet. Traversal:
   lift an iron PLATE, run the trolley out, drop it as a bridge over a conduit gap. Combat: charge
   it over a Sapscrap swarm — the iron-laden strippers are yanked up and pinned until discharge
   (dump them into the backwash). TWIST (canon: Sapscraps "strip iron from fixtures"): an unattended
   plate-bridge gets EATEN — the traversal decays unless the swarm is lured off (Flure) or pinned
   first. Grammar: the charge lever is across the gap the plate must bridge.

3. **Irrigation ration sluice — Greenfields Collective.** The residential terraces share ONE daily
   water ration; a sluice paddle routes it to a single terrace. CONTROL: the paddle at the header.
   EFFECT: the watered terrace's flora swells — Scarpet spreads into medium-hide carpet, a Capbage
   fattens into a tight hide, Seefern brightens — while the de-watered terrace's cover WILTS behind
   you (cover is a spent ration, not a latch). Combat: route the ration onto the chokepoint where
   an Aember cluster camps — dousing the cluster is its canonical counter; or swell a Gasafoetida
   bed into a repellent hedge across a patrol lane. Grammar: the header paddle is two terraces
   upstream of the crossing it grows.

4. **Return-chute routing flaps — Beacon Hill.** The reading room's book-return chutes: one-way
   gravity slides crisscrossing the tower, big enough to ride (crawl pipes' fast, committed
   cousin). CONTROL: a routing flap at each junction. EFFECT: which room the chute mouths into.
   Traversal: a concealed one-way descent past the checkpoint floors. Combat: flip the flap so the
   Gnawer pack riding in after you dumps into the sealed holding cage; or send a PAYLOAD instead
   of a body — a Flure down the east chute relocates every iron-seeker in the wing (lure
   LOGISTICS: the routing network moves your tools, not just you). Grammar: flaps are set in the
   stacks, mouths open elsewhere; you commit before you see the landing.

5. **Counterweight cargo baskets — Bulwark Wharf.** Paired gantry baskets over the membrane wall on
   a shared pulley — vesicle transport made mechanical (cargo crossing the barrier in a carrier).
   CONTROL: ballast — load/unload iron chunks on either basket, from anywhere on the line. EFFECT:
   the paired basket rises as yours sinks. Traversal: weigh one down to lift a character to the
   wall-top. Combat: drop a Flure in the lowered basket, let a Sapscrap swarm pile in chasing it,
   then load ballast — the swarm is hoisted and left swinging out of play (no kill, a REMOVAL —
   and dumping it back out is a choice). Grammar: the ballast pile and the basket you need lifted
   are on opposite sides of the wall.

6. **Cell-shutter cranks — The Honeycomb Cooperative.** The honeyframe facade's cells hold rotating
   shutter plates; one crank turns a whole COLUMN between OPEN / SLIT / SEALED. CONTROL: the crank
   at the column base. EFFECT: open = a crawlable cell-to-cell route THROUGH the facade lattice;
   slit = light bars that re-cut every sightline on the floor inside (stealth geometry changes
   without anyone moving); sealed = the Aember breach-cells close (the ambusher camps the
   chokepoint — seal its chokepoint away). Canon hook: Climbvine "tied between rotating surfaces"
   can couple two cranks so one turn sets two columns. Grammar: the crank column you need open is
   reachable only through the column a DIFFERENT crank opens. (Geometry note: the S_A/S_B
   honeyframe lattice we ship is literally this facade — the set piece reuses it.)

7. **Hydrant scour lanes — The Cleanstreets Initiative.** Sanitation hydrants with aimable nozzles;
   opening one blasts a directional scour wash down a plaza lane. CONTROL: the hydrant valve +
   nozzle aim. EFFECT: everything in the lane is PUSHED N cells (the queued-push grammar), the
   lane's Scarpet is scrubbed off (your own medium cover is spendable — double-edged), and light
   debris rafts down the gutter to pile at the drain grate into a climbable heap (traversal you
   ACCUMULATE by repeated flushes). Combat: shove a Spiker off its ledge perch, or push a pursuer
   across a Candid zone — the ecosystem finishes it (canonical counter). Grammar: the hydrant
   points down the lane you'll cross two pieces later, and the debris heap builds at the far drain.

## PROPOSED set pieces — the Aghora + the boss zones (Claude, 2026-07-11 — director approval required)

The three zones NO register or proposal covered yet (checked against ENVIRONMENT_ELEMENTS.md and
the list above — PPP and Ancourage are exhaustively owned by the register, the other seven
districts by proposals 1–7). Same grammar: CONTROL + EFFECT, a traversal use AND a combat/stealth
use, control separated from effect by other pieces. The Aghora pieces derive from its BIOLOGY
(GDD §4.12 L807-811: receptor tolerance, synchronized excitotoxic firing, hoarded stolen
resources, the counterfeit market); the boss pieces decompose gameplay canon the GDD already
states (§11.1 heavy queueing + the door-trap shadow; §11.2 alignment paths + the Climbvine spend).

### The Aghora (the counterfeit agora — bazaar canyon, coop-district cracks, Act 2/3)

8. **Dose-lantern pull-cords — TOLERANCE as a mechanic.** Stim dispensers hang along the stall
   rows; a pull-cord fires a sensory BURST that entrances everything in its radius for a beat.
   CONTROL: the cord. EFFECT: the freeze window — but the addiction curve is the rule: each
   firing of the SAME lantern is weaker (the window halves — receptor tolerance, GDD L809), and
   it never recovers. A decaying stun economy: order and spacing matter more than trigger-pulling.
   Traversal: freeze the crowd blocking a lane and slip through. Combat: two bursts back-to-back
   OVERDRIVE an iron-seeker (Sapscrap swarmlet / Aember) into excitotoxic burnout — the canon
   kill, fired past what it can survive (L809) — but only if you spent a virgin lantern on it.
   Grammar: the cords hang in the stall rows; the lanes they freeze are two stalls further on.
   Build: Flure-class lure object + a per-lantern decay counter (scheduler state, replay-safe).

9. **Exchange dumbwaiter — the market prices movement.** The counterfeit exchange runs a
   counterweight cargo cage between canyon levels, and it moves ONLY when fed: loading trade
   goods (iron chunks, flora pods — the hoarded stolen resources of L805-807) on the counter side
   hoists the cage. CONTROL: what you feed the counter. EFFECT: the cage rises to the terrace
   level bought. Traversal: vertical movement with a PRICE — the Aghora's whole cosmology as a
   lift. Combat: bait the cage floor with an iron chunk, let a Sapscrap swarm pile in chasing it,
   feed the counter — the swarm is hoisted out of play, hanging over the bazaar (removal, not a
   kill; sending it back down is a choice). Grammar: the goods pile sits at the stalls you have
   passed; the cage lands where you are going. Build: the bulwark counterweight-basket controller
   re-skinned + the object-carry class (pending, shared with the flow-plate mosaic).

10. **Synchronization floor — detection samples on the beat.** The assembly floor is the cult's
    synchronized-excitation rite made geometry: light strips pulse on a scheduler cadence, and on
    the floor DETECTION ONLY SAMPLES ON THE FLASH — the dark half-beat is blind. CONTROL: the
    tempo lever on the DJ balcony. EFFECT: the flash cadence. SLOW tempo = long blind windows,
    easy crossings, but each flash is a full-floor scan (be hidden ON the beat, P2 register:
    Aster's TRACE reads the next flash tick); FAST tempo = entrained fauna stutter-lock to the
    beat (pursuit crawls) but you are sampled constantly and must hug cover. Two viable settings,
    a real choice, no execution timing — you pick the regime, then move on readable windows.
    Combat: crank MAX with a pack mid-floor and hold it there — synchronized excitation burns the
    entrained out (L809), the district's own practice as the weapon. Grammar: the tempo lever is
    on the balcony only the dumbwaiter (piece 9) reaches. Build: detection recompute already
    rides the scheduler; this quantizes its sampling ticks — no per-frame polling.

11. **The SENSATION SELECTED gate (the market-gate arch, boss-arena mouth).** The plate's neon
    arch scans for AROUSAL, not tags: it admits only the freshly dosed. CONTROL: the dose-lantern
    chain (piece 8) — a member who took a burst within the decay window carries a "lit" state the
    arch reads. EFFECT: the arch opens per lit member, one at a time (the portal rule). The bind:
    dosing to pass SPENDS lantern freshness the crossing beyond may need, and the tolerance you
    build here weakens every later lantern — entry to the deep bazaar is priced in your own
    escalation, the addiction curve as a door. Naturalizers ignore the arch (they scan tags, not
    arousal — fauna_roster L34); the gate is the cult's own filter. Grammar: piece 8's CONTROL is
    this gate's KEY; the gate is a CrawlTunnel-class one-at-a-time mouth. Build: CrawlTunnel
    group-queue + a per-character timed status flag.

### Loca's Watchtower approach + interior (Act 1/2 boundary, GDD §11.1)

12. **Switchback scree winches — buy sections from the tide.** The mountain trail's flights pass
    under rockfall chutes; a winch at each landing opens the gate above the flight BELOW you.
    CONTROL: the winch. EFFECT: scree sweeps that lower flight — locusts on it are carried down
    the mountain (swept, not killed — the wash-sweep grammar), and the flight becomes a scramble
    slope: still climbable, slower, for them AND for you. The ascent is a fighting retreat from a
    tide that keeps coming (Myke's futility, L2421, as terrain): you queue winch turns and moves
    ahead of the swarm — the canonical heavy-queueing context (L301) in its native home.
    Grammar: every winch controls the flight below, never the one you stand on — spending one
    always costs your own line of retreat. Build: wash-sweep controller on a slope + the queued
    command system.

13. **Ward-door breaker bus — the shadow solution as geometry.** The tower's sector doors share
    one power BUS with a breaker budget: only N doors can HOLD at once; sealing one somewhere
    frees nothing until another is dropped. CONTROL: per-door hack points (Aster) + the breaker
    panel. EFFECT: which sectors are sealed. Traversal: your ascent route is whatever the budget
    leaves open. Combat: seal a locust group in with itself — isolated and at rest, the locusts
    cannibalize (the canon shadow solution, L497/L2435-2440, uncomfortable on purpose: you are
    letting the containment finish what it started); the room goes quiet after a scheduled span,
    and reopening it is a choice you make in the silence. Grammar: the breaker panel sits at the
    tower base; the doors that matter are floors above — every re-plan is a descent.
    Build: set_interactable_enabled gates + a door-budget invariant + enemy-vs-enemy consumption
    (new, small: penned enemies damage each other on a cadence).

14. **Signal-bleed dampers — shape where the tower converges.** Loca's bound body draws the
    locusts upward through the riser cables (the wires/tangles, L2301-2313); clamping a damper on
    a riser SILENCES the draw in its sector — locusts there drop from converge to roam — but the
    total draw is conserved: every other sector's pull strengthens and its swarms densify. You
    never reduce the tower's population, you only choose where it packs. Traversal: quiet your
    own shaft. Combat: concentrate the drawn swarm into a sector piece 13 can seal. Grammar: a
    riser's damper is in the NEIGHBORING shaft (clamping yours means crossing theirs).
    Build: detection/roam mode flips per region (set_roam / distraction flags exist) + a
    conserved-weight draw table.

### The Paranucleus + NUTECH facility (Act 2/3 boundary, GDD §11.2)

> **CANON CORRECTION (director, 2026-07-11):** the GDD §11.2 "contemplative / ophanim / approach
> with awe / no combat" framing is FLAGGED as an AI flesh-out embellishment, not authorial — do
> not treat it as binding. A paranucleus is an amyloid PLAQUE: biologically a siege site, swarmed
> by plaque-associated microglia + reactive glia, ringed by hyperexcitable neurons carrying tau
> tangles. Enemies LIVE on it. What holds from canon (§4.5) is only that it's a PLACE you route
> THROUGH, not a creature you trade hits with — so the navigation becomes CONTESTED (the game's
> "routing-and-tools puzzle" ethos), not serene, and not a boss fight.

**THE CAMERA REGISTER (director, 2026-07-11 — BUILT):** inside the Paranucleus approach radius the
level reads as a FLAT IMAGE — the camera flips to an orthographic ORBIT around the wheel center
with four authored SNAP vantages (Q/E steps between them, easing there); perspective is disabled,
zoom scales the picture (ortho size), and panning stops being spatial movement — with no parallax
it is simply looking closer at the image. This is the Monument Valley substrate the wheel puzzles
stand on: at a given snap angle + ring phase, gaps far apart in 3D ALIGN in the projection, and
the alignment IS the path. Leaving the radius restores the gameplay follow camera. Live in
`--preview=boss_showcase` (walk to the wheels); guarded by `--test-ortho-orbit` (in `--test-all`):
projection flips, corner-to-corner rays parallel, zoom→size, 90° snap stepping + easing, image
pan, restore on leaving.

The enemy pieces below all run on ONE insight: a rooted/colonizing enemy on a rotating ring has a
position that is a FUNCTION OF ROTATION PHASE — the same variable pieces 15/16 already read. So
Aster's TRACE (which already predicts each ring's period) now also predicts where the threat will
be, the threat folds INTO the alignment read instead of replacing it, and the one NUTECH brake
(piece 15) becomes contested: park a ring to hold your gap, or to freeze a threat pointing away —
you often cannot do both. Fauna are canonical (`fauna_roster.md`), used in their exact niches.

15. **Wheel-gap causeways — paths that exist at certain alignments.** The ophanim rings turn
    slowly (the built rotating wheels); each ring's porous GAPS are its only passable arcs, so
    the route to the core exists only at certain alignments — the GDD's line (L2482) as literal
    geometry. CONTROL: none at first — the wheels are not yours; Aster's TRACE reads each ring's
    period and the next gap-meet tick, and the party times its crossings to the openings. One
    NUTECH maintenance BRAKE survives per approach: it parks ONE ring —
    a permanent gap on that ring only, bought by choosing which. Being on an arc when it rotates
    out is a SWEEP (carried around and set down outside — fail-forward, never a death).
    Build: the wheels already turn; gap arcs = walkable windows keyed to rotation phase
    (scheduler-derived, the fast-forward-invariant pattern the wash cadences use).

16. **Climbvine ratline hoists — tied between rotating surfaces.** Anchor bosses stud the ring
    rims and the facility gantries; a harvested Climbvine SPENT between two anchors becomes a
    permanent ratline (an inter-level link bought from inventory — the encounter's canonical
    Climbvine economy, L2506). The twist is the canonical verb itself (flora_taxonomy: Climbvine
    ties between ROTATING surfaces): a vine tied gantry-to-RIM winds up as the ring turns and
    HOISTS the climber to the hub — the wheel as elevator. N vines, M anchor pairs, N < M:
    route-planning by expenditure. Grammar: the anchor you need is on the ring whose gap
    (piece 15) you must first cross. Build: add_inter_level_link at runtime (exists) + a vine
    inventory count; the hoist is a timed authored path (the crawl-tunnel movement pattern).

17. **Reservoir siphon manifold — the last of the Lavender Lake.** The facility's central
    reservoirs (L2490, where the bottle waits) still hold DREGS; the bottling manifold's siphon
    valves route what pressure remains to scent heads around the engulfed yard. CONTROL: the
    valves in the intact NUTECH office (the legible building). EFFECT: a fired head raises a
    lavender scent CURTAIN across its lane for one crossing — the spray line's canonical power
    is disabling security (L2530), so the curtain pacifies the lane: Gnawers denned in the
    engulfed wing will not cross it while it hangs. Pressure is finite and falling — each curtain
    is one crossing, and what you spend here foreshadows the bottle's own two-application economy
    before the player ever holds it. Grammar: valves in the office, heads in the yard, and the
    yard is how you reach the reservoirs the valves drain. Build: a timed concealment/repel lane
    (the distraction/conceal flags) + a shared depleting counter.

#### Enemies living ON the Paranucleus (director, 2026-07-11 — the plaque is a siege site)

The plaque-associated swarm: colonizers rooted to the turning rings, so THEIR position is a
function of rotation phase and joins the same read as the gaps (pieces 15/16). None is a "defeat
the boss" fight — each is a hazard you route past, and each nests into the alignment mechanic.

18. **Sweeping Spiker sightline.** A Spiker (rooted LOS turret — fauna_roster: locks onto movement
    in its sightline, fires from a bright branch) bolted to a ring band; as the ring turns its
    firing LANE sweeps the interior. CONTROL: the ring's rotation (piece 15's read/brake). EFFECT:
    the wheel-gap crossing now has TWO phases to satisfy AT ONCE — the gap open AND the bright
    branch swept off your arc; Aster's TRACE predicts both. The brake is contested: park the ring
    to hold your gap, or to freeze the branch pointing away. Cover verb stays canon (Capbage /
    Scarpet break its LOS) — but cover placed on a spinning ring rotates with it, so WHERE on the
    arc you set it decides how long it shields. Grammar: the Spiker fires ACROSS the gap you cross,
    control (brake) at the hub. Build: a rooted enemy parented to a ring pivot (the wheels already
    turn) + LOS from its live world transform; Spiker aiming already exists.

19. **Crust bands — fire that rotates away.** A Crust colony (fauna_roster: wall hazard, vents acid
    from dilating pores, ONLY fire clears a stretch and it grows back, a siderophore) rings one
    band. EFFECT: the acid arc is impassable on its pore-dilate tell. Burn a stretch (Myke / a
    thermal source) and the cleared gap ROTATES AWAY while un-burnt crust comes around — a timed,
    MOVING window, not a permanent clearing (fire-on-a-turntable). Iron hook: Crusts are
    siderophores, so an iron plate from the NUTECH hoist/yard draws the colony to one side of the
    band, thinning the arc you cross opposite it. Grammar: the fire source / iron bait sits on the
    facility side; the band you thin is out on the ring. Build: a Crust terrain colony as ring-band
    cells (fire-clear + regrow cadence exist) parented to the pivot; iron-draw = the siderophore
    lure bias.

20. **Tangler–Spiker ecology, aimed by timing.** Canon ecology (fauna_roster: a Spiker's firing
    "draws the Tanglers that hunt it"; Tanglers "prefer hyperexcitable neurons" and unravel their
    prey — and biologically the tau tangles ring the plaque's hyperexcitable neurons). So the
    counter is to NOT break the Spiker's LOS: let it fire, a Tangler creeps toward it, and when
    their two rings ALIGN the Tangler reaches and unravels it — clearing BOTH hazards at an
    alignment YOU chose by withholding your intervention. Pure "aim the ecosystem" (roster L40)
    expressed through rotation timing: the verb is a decision about WHEN to do nothing. Grammar:
    the Spiker and its hunting Tangler ride DIFFERENT rings; you read/brake to bring them together.
    Build: the existing Spiker-draws-Tangler behavior + contact resolved on ring-alignment tick.

(Variant kept for later: a **Candid arc** — fauna_roster's costly-but-safe colony floor that blinds
Naturalizer scans and drives other enemies off — ringing one band makes a MOVING safe corridor that
only shelters you while its arc sweeps past your position. Folds in the same way; not written up as
its own piece yet.)

## CURE-ECHO set pieces — easier foreshadows of the nine landmark puzzles (PROPOSED, 2026-07-09)

The GDD's nine cure-component puzzles (§10.4.1–10.4.9) each own a distinct mechanic class. The
pedagogy: every landmark gets an EASIER ECHO placed earlier — a set piece (CONTROL + EFFECT) that
teaches the landmark's *grammar* in a low-stakes, recoverable form, so mastery is layered before the
cure version demands it. Per the director: echoes are **activation/selection-based wherever
possible, not execution-timing**. Flora/fauna verbs are canon (`fauna_roster.md`,
`flora_taxonomy.md`); GDD cites from the §10.4 sweep.

**THE ECHO-SIGNATURE RULE (ratified 2026-07-10):** an echo borrows the landmark's GRAMMAR but must
never contain its SIGNATURE TWIST — no cascade depth (Wrap), no read-decay (Aligner), no phase math
(Resonator), no info-blackout (Rest Cycle), no costly Override (Sealant). That is the line between
foreshadowing and spoiling. Two companion rules from the same pass: **wrong activations should have
USES, not penalties** (drawer-stairs: a wrong index extends cover), and **nothing ever echoes
Peris's degrading read** — her decline landing fresh in Act 2 is a narrative beat, not a mechanic to
rehearse.

| Cure landmark (GDD) | Echo set piece | Location / Act | Easier because | Flora / fauna |
| --- | --- | --- | --- | --- |
| **Inflammashunt** §10.4.2 (3-route contradictory info; patience wins) | **Tending triage rows** — three planter rows carry POSTED claims about which irrigation line is safe; two of three agree only when cross-read; watering wrong swells a Gasafoetida hedge (repel burst, recoverable); waiting one beat lets Seefern brighten over the true line | Greenfields, Act 1 (pre-shelter-10) | 2 contradictions not 3; no hold timers; the patient option always legible | Seefern (light = truth tell), Gasafoetida (fire-reactive hedge); Aember at the chokepoint |
| **Pattern Wrap** §10.4.3 (temporal overlays, cascading edits) | **Records replay bay** — a carrel replays 2–3 archived SNAPSHOTS of the hall's shelving; activating one ghosts that era's drawer layout (one at a time); the route needs two activations sequenced AND exactly ONE cascading pair: an edit made in era-1 visibly carries into era-2's layout (one edit, one propagation — teaching that overlays have consequences without the Wrap's four-timeline retroactive build) | Open Files, Act 1/2 seam | ONE propagation, not a cascade; 2–3 eras not 4 timelines; walking, not path-building | the drawer-canyon Naturalizer patrols the PRESENT only — overlays never hide you (teaches overlay ≠ safety) |
| **Flow Aligner** §10.4.4 (fragment assembly, degrading Peris read, heavy carry) | **Flow-plate mosaic** — three mosaic plates re-slot at a junction kiosk; the assembled diagram names the ONE valve to open; only one plate is heavy; Peris's read is STABLE | Plumbing Power Project, Act 1 | no read-decay; 3 fragments; one heavy plate not all | the plates are IRON — carrying one draws the Sapscrap swarm (drop it to shed aggro; Flure pulls them off the carry line). Teaches iron-carry aggro before Act 2's Chelators |
| **Outflow Expander** §10.4.5 (memorize the maze, run it blind, rising water) | **Lights-out stairwell** — walk one lit floor, then the breaker kills the lights and you walk it from memory; a Meeb flows slowly up the stair (sidestep-able, no wipe) | Honeycomb, Act 2 | ONE character, one short route; pursuit is slow, not a flood; **Peris can pre-plant Seefern = memory anchors you can buy back** (the difficulty dial is preparation, not reflex) | Seefern (pre-planted waypoints), Meeb (slow pursuer, canonical sidestep) |
| **Acid Core** §10.4.6 (valve-turn sequence routing) | ALREADY SEEDED — the register's PPP valve-rotation terminal + Hypelines coupled diverters are the designated re-themed echoes (per their CANON notes); the showcase WATER BASIN (built) is the infant form: one valve, three states | PPP / Hypelines, Act 1 | one-valve state cycling → two coupled valves → full sequence logic | Climbvine couples valve pairs (canonical tie-rotating-surfaces verb) |
| **Resonator** §10.4.7 (two-body distance = frequency; phase staffing) | **Crossing-signal TRIO** — TWO signals share THREE plates: each signal's blink rate is dialed by the distance between ITS pair of plates, and the middle plate serves both — so one member's position is a shared resource and who-stands-where is a real staffing plan (the Resonator's actual seed), with visible target readouts and zero phase math; both gates arm WHILE positions are held (P12) | Cleanstreets, Act 2 | visible readouts; no phase/collision; nothing executes on a beat — but the STAFFING decision is present in miniature | the armed gates shutter a Spiker's firing lane (its brightened branch shows what you're gating) |
| **Membrane Sealant** §10.4.8 (plan, commit, lose control; observe⊕act) | **Pore-lock dry-run** — ONE pair, two lanes, six tiles: peek the observation port (you cannot touch switches while observing), set two switches from memory, pull COMMIT — the pair autopilots through; the Override handle exists and is COSTLESS here (teaches that it exists before it tempts) | Bulwark Wharf, Act 2 | one pair not three; no cable forks/inversions; override free | Crusts vent acid across one lane on dilate-tell (the hazard the switches gate) — membrane biology in miniature |
| **Rest Cycle Module** §10.4.9 (persistence among many identical activatables) | **Junction-box row** — one locked door, nine identical boxes, one correct; each wrong box is a priced beat (the patrol cycles back); Aster's hum-read narrows candidates — but **the hum LIES sometimes** (half-connected circuits on off-path doors hum too), so the instrument helps without being an oracle. Sunset Acres is canonically the district whose ground no institutional instrument could read — an unreliable read HERE teaches instrument-distrust one act before the finale removes the instrument entirely | Sunset Acres fringe, Act 2/3 | partial (unreliable) feedback vs the finale's none; one door; pack repellable | Gnawer pack cycling the row (Gasafoetida repel, Hushbloom stun-break — both canonical counters) |

(The Chaperone Lattice, §10.4.1, has no mechanic to echo — it is a pickup with forget-me-nots, which
canon forbids weaponizing.)

**Build order by value-per-cost (assessment, 2026-07-10):** crossing-signal trio → junction-box row
→ drawer-stairs v2 → flow-plate mosaic (needs a small object-carry class) → pore-lock dry-run
(commit-autopilot controller) → tending triage rows → lights-out stairwell and records replay bay
LAST (each carries a real new system: player-side DARKNESS/visibility does not exist yet — all
current systems are enemy-side concealment — and ghost-layout overlays are the most expensive echo).

## Drawer-stairs v2 — ACTIVATION logic, not timing (director's ruling, replaces proposal 1's execution)

The Open Files stack wall's pull-handles are **INDEX LEVERS** at the catalog desk — one per record
category. Activating an index extends EVERY drawer of that category at a category-fixed depth
(deep / mid / shallow, stamped on the tag plates). A staircase forms on a column only when the
ACTIVATED SET produces ascending depths in height order there — so the solve is **selecting the
right ~3 of 6 indices**, deduced from readable information, and executing has no clock:

- **Aster (WHEN→what):** reads the tag-plate metadata — which categories live at which heights in
  which column (the deduction data).
- **Peris (WHERE):** damp, rotted drawers grow Scarpet — a rotted step CANNOT bear weight (stepping
  on one is a slip → downed, fail-forward one section, never a wipe). Her read marks which columns
  are viable.
- **Wrong activations are never fail states** — they extend drawer WALLS across aisles, which block
  your path but ALSO break the overwatch Naturalizer's scan-line: the same activation system doubles
  as deployable cover. (Selection has side-uses, not penalties.)
- **The combat verb stays activation-based:** retract the index a climbing Gnawer pack is ON and
  they drop — you choose *which category* to retract, you never race a timer.
- **Grammar:** the index levers sit at the catalog desk across the hall from the stacks; the tag
  plates are read AT the stacks (control and information separated by the room).
- **Cure-echo position:** the selection-not-sequence rung under BOTH the Acid Core (reconfiguring
  reachability by activation) and the Rest Cycle Module (many similar activatables — but here fully
  information-rich). It is deliberately the easiest rung of both ladders.

## Planned-location survey (register + GDD, for slotting future pieces)

Act 1: PPP, Open Files, Greenfields, Hypelines, Ancourage (Inflammashunt DZ at shelter 10). Act 2:
Honeycomb (Pattern Wrap, shelters 11-12), the Zone 2 water junction (Flow Aligner), map-edge
drainage (Outflow Expander), Cleanstreets, Beacon Hill, Bulwark Wharf. Act 3 (register PROPOSAL
regions): Welcombe Springs (drainage terraces / steam halls / funicular), Harmonia (Resonator,
shelters 21-22 + entrainment ferry / civic-pulse approach), Sunset Acres (iron-burst rows /
sinkhole field; Zone 3 waste facility = Acid Core), Root Archive (reading hall / circadian crossing
/ artifact carry; the Hidden shelter above = Rest Cycle Module). Every echo above slots into a
location the registers already own, one act (or more) before its landmark. magnet hoist's charge lever behind a drawer-stair
climb; sluice header past an Aember chokepoint that the sluice itself can douse — but only after a
chute ride commits you to the wrong wing; shutter-crank columns interleaved so each opened column
exposes the next crank plus one slit-state sightline change. Every pair alternates one piece's
CONTROL with another piece's EFFECT, per the verbatim rule above.

## Showcase

`set_piece_showcase` (fragment picker: "Set Pieces — crawl / rotate / water") — one bay per set
piece, mechanics live on the data layer (scheduler-driven, replay-safe, fast-forward invariant):

- **Bay A — crawl pipes:** a pipe with two ENTRANCE mouths (`CrawlTunnel`, the reusable object);
  click a mouth, the character ducks in and traverses inside the pipe (slowed, concealed while
  inside) and exits at the other mouth. **The PORTAL RULE (director):** a queued PARTY lines up at
  the mouth and enters ONE AT A TIME — staggered by the in-tube spacing so the tube stays
  single-file — and each member walks off to its own far-side slot so the exit never stacks.
- **Bay B — rotating pipe:** a cross-shaped pipe hub with a PUSH WHEEL; each push rotates the hub
  90°; only when its bend connects the two fixed stubs does the crawl route through it open.
- **Bay C — water basin:** a valve console cycles the basin water level LOW/MID/HIGH; water cells
  are never walkable; two FLOATS ride the surface and only bridge the crossing at MID; a sunken
  side pen holds a roaming enemy — climb the ledge and raise the water to HIGH to drown it.
- The GRAMMAR demo: bay C's valve sits across bay A's crawl pipe (control separated from effect by
  another piece), per the verbatim rule.

- **Bay D — structural weakness (the BUILDING→PUZZLE hook):** a generated S_A/S_B honeyframe slab
  with a cracked WEAK POINT (dark-red tell, first sight); pry the loose strut on its FAR side → the
  facade crumbles on a scheduled beat — the debris kills the lurker roaming beneath AND the rubble
  fills the trench into a shortcut (combat + traversal from one strike; control behind the slab,
  effect in front: the grammar again).
- **Bay E — the iron-load magnet hoist (proposal 2, BUILT):** a trolley rides an overhead rail
  across a canal (stations: plate store / the gap / the scrap pen). CHARGE lifts whatever iron sits
  beneath; DISCHARGE at the gap drops it. Drop the PLATE → the canal cells open — but two iron-laden
  scraps roam the far bank, and living scraps STRIP an unattended plate (scheduled commit, ~7 s):
  the traversal DECAYS. Pin the swarm under the magnet, carry it over the canal, drop it in — then
  the plate bridge is permanent. The ecology contests the traversal; both orders are playable and
  tested.

Tests: `--test-set-piece-showcase` — data-layer playthrough of all five mechanics (crawl connects,
rotation gates, water level rewalks the grid + aligns floats + drowns the penned enemy, the crumble
kills + opens the shortcut, the hoist's decaying vs. permanent bridge), replay-safe.

## Buildings hook into the puzzle infrastructure (director, 2026-07-09)

Generated buildings are not scenery — every generator emits **gameplay anchors**
(`BaseShapeBuilder.gameplay_anchors(spec, entrances)`), the sockets the level/puzzle layer consumes:

- **`weak_points`** — structural weaknesses (deterministic, on the structure): a consumer may make
  one crumble when struck — a scheduled collapse that kills/blocks what's beneath and leaves rubble
  (bay D is the live reference implementation).
- **`connectors`** — road sockets at every entrance threshold (main flagged) and bridge sockets at
  tier-ledge rims / flat-roof parapets: where the level's roads and bridges ATTACH to a building, so
  generation can route circulation through architecture instead of around it.
- **`balcony_slots`** — content points around tier ledges: the level assigns flora, lures, rest
  spots, set-piece controls — a balcony is a shelf the puzzle layer stocks.

The architecture showcase renders every socket as a small emissive gem (red = weak, green = road,
cyan = bridge, amber = balcony) so anchors are inspectable while iterating.

**Weak points are consumed too:** the first landmark in a generated district spends one hash-picked
structural weak point as a `weak_wall` OBJECT (a new data-fragment object type): the loader spawns a
crack tell + a pry point at the wall foot; prying it crumbles the face on a scheduled beat — enemies
in the kill zone on the street in front die, rubble remains. Proven end-to-end in a loaded generated
level (`--test-shape-grammar` snaps a gnawer into the zone and pries).

**The generators CONSUME the sockets (2026-07-09):** the district filler places up to two LANDMARK
heroes (BaseShapeBuilder specs) on big street-adjacent lots — each rotated so its MAIN-door road
connector faces its street (`_street_dir`), with the approach carved walkable + an apron when the
threshold sits short of the network. Facing BRIDGE sockets between the pair span a REAL walkable
deck: `BuildingFiller.plan_bridge` (pure, unit-tested) picks the first level-snappable aligned pair
over a clear street lane; the deck's cells join the grid at its level with LADDER links at both ends
(`--test-shape-grammar` proves deck walkability + link traversal + door-street connectivity +
determinism). The loader (`_spawn_landmark_building`) assembles the heroes from plan data — the same
pattern as the lathe towers. Preview: `--preview=shape_grammar` (seed 1 places a bulwark + terrace
pair with a bridge).
