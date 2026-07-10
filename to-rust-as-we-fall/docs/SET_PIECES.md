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

## CURE-ECHO set pieces — easier foreshadows of the nine landmark puzzles (PROPOSED, 2026-07-09)

The GDD's nine cure-component puzzles (§10.4.1–10.4.9) each own a distinct mechanic class. The
pedagogy: every landmark gets an EASIER ECHO placed earlier — a set piece (CONTROL + EFFECT) that
teaches the landmark's *grammar* in a low-stakes, recoverable form, so mastery is layered before the
cure version demands it. Per the director: echoes are **activation/selection-based wherever
possible, not execution-timing**. Flora/fauna verbs are canon (`fauna_roster.md`,
`flora_taxonomy.md`); GDD cites from the §10.4 sweep.

| Cure landmark (GDD) | Echo set piece | Location / Act | Easier because | Flora / fauna |
| --- | --- | --- | --- | --- |
| **Inflammashunt** §10.4.2 (3-route contradictory info; patience wins) | **Tending triage rows** — three planter rows carry POSTED claims about which irrigation line is safe; two of three agree only when cross-read; watering wrong swells a Gasafoetida hedge (repel burst, recoverable); waiting one beat lets Seefern brighten over the true line | Greenfields, Act 1 (pre-shelter-10) | 2 contradictions not 3; no hold timers; the patient option always legible | Seefern (light = truth tell), Gasafoetida (fire-reactive hedge); Aember at the chokepoint |
| **Pattern Wrap** §10.4.3 (temporal overlays, cascading edits) | **Records replay bay** — a carrel replays 2–3 archived SNAPSHOTS of the hall's shelving; activating one ghosts that era's drawer layout (one at a time); the route exists only by sequencing two activations | Open Files, Act 1/2 seam | overlays are walk-only (no cascading edits); 2–3 eras not 4 timelines | the drawer-canyon Naturalizer patrols the PRESENT only — overlays never hide you (teaches overlay ≠ safety) |
| **Flow Aligner** §10.4.4 (fragment assembly, degrading Peris read, heavy carry) | **Flow-plate mosaic** — three mosaic plates re-slot at a junction kiosk; the assembled diagram names the ONE valve to open; only one plate is heavy; Peris's read is STABLE | Plumbing Power Project, Act 1 | no read-decay; 3 fragments; one heavy plate not all | the plates are IRON — carrying one draws the Sapscrap swarm (drop it to shed aggro; Flure pulls them off the carry line). Teaches iron-carry aggro before Act 2's Chelators |
| **Outflow Expander** §10.4.5 (memorize the maze, run it blind, rising water) | **Lights-out stairwell** — walk one lit floor, then the breaker kills the lights and you walk it from memory; a Meeb flows slowly up the stair (sidestep-able, no wipe) | Honeycomb, Act 2 | ONE character, one short route; pursuit is slow, not a flood; **Peris can pre-plant Seefern = memory anchors you can buy back** (the difficulty dial is preparation, not reflex) | Seefern (pre-planted waypoints), Meeb (slow pursuer, canonical sidestep) |
| **Acid Core** §10.4.6 (valve-turn sequence routing) | ALREADY SEEDED — the register's PPP valve-rotation terminal + Hypelines coupled diverters are the designated re-themed echoes (per their CANON notes); the showcase WATER BASIN (built) is the infant form: one valve, three states | PPP / Hypelines, Act 1 | one-valve state cycling → two coupled valves → full sequence logic | Climbvine couples valve pairs (canonical tie-rotating-surfaces verb) |
| **Resonator** §10.4.7 (two-body distance = frequency; phase staffing) | **Crossing-signal duet** — two members stand on paired plates; their DISTANCE dials the crossing signal's blink rate; matching the posted rate (readable dial) arms the tram gate WHILE both hold position (P12 held, never latched) | Cleanstreets, Act 2 | one pair, visible target readout, no phase/collision constraint, nothing executes on a beat — pure positioning | the armed gate shutters a Spiker's firing lane (its brightened branch shows what you're gating) |
| **Membrane Sealant** §10.4.8 (plan, commit, lose control; observe⊕act) | **Pore-lock dry-run** — ONE pair, two lanes, six tiles: peek the observation port (you cannot touch switches while observing), set two switches from memory, pull COMMIT — the pair autopilots through; the Override handle exists and is COSTLESS here (teaches that it exists before it tempts) | Bulwark Wharf, Act 2 | one pair not three; no cable forks/inversions; override free | Crusts vent acid across one lane on dilate-tell (the hazard the switches gate) — membrane biology in miniature |
| **Rest Cycle Module** §10.4.9 (persistence among many identical activatables) | **Junction-box row** — one locked door, nine identical boxes, one correct; each wrong box is a priced beat (the patrol cycles back); ASTER's read NARROWS candidates (a hum rises on the half-connected circuit) — the cure version gives no info at all | Sunset Acres fringe, Act 2/3 | feedback exists (candidate set shrinks); one door; pack repellable | Gnawer pack cycling the row (Gasafoetida repel, Hushbloom stun-break — both canonical counters) |

(The Chaperone Lattice, §10.4.1, has no mechanic to echo — it is a pickup with forget-me-nots, which
canon forbids weaponizing.)

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

- **Bay A — crawl pipes:** a pipe with two ENTRANCE mouths; click a mouth, the character ducks in
  and traverses inside the pipe (slowed, concealed while inside) and exits at the other mouth.
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
