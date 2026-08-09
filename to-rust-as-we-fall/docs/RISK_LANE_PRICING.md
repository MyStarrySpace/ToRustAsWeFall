# Risk Lane Pricing — what a route costs, and why the number is arithmetic

The open-world run offers several ways to the same place, each advertising a price in HP. This is the
model behind that price (`scripts/generation/risk_lane.gd`), the fragment that composes it
(`--preview=long_hall`), and the facts about the shipped systems that the build surfaced.

Proofs: `--test-risk-lane-price` (the model, 44 assertions) and `--test-long-hall-fee` (the fragment
actually charging what it quoted, at two scheduler step sizes). Both are in `--test-all`.

## The shape

A lane is a corridor with cover only at the far end, cut just past full-stamina sprint range. Running
it drains the bar; the legs give out short of the hide; the chaser closes; a fixed number of charges
land; the runner reaches cover and is lost. **Stamina is the mechanism, HP is the price.**

Nothing in it is new. The run toggle and its drain, walk/run speeds, enemy pursuit and the
alert → pursuit → windup → charge → impact → recover cycle, and Capbage tight-hide concealment are all
shipped. The model only reads them forward (what does this geometry cost?) and inverts them (what
geometry charges this?).

## The generator tunes length from a target cost

`length_for_strikes(n)` is the inverse of `price(length)`, and it is the direction generation uses: a
route states the fee it wants to charge and receives the corridor that charges it. That answers the
open question directly — length is derived from cost, not authored and then measured.

`--test-risk-lane-price` holds the two functions to being inverses across n = 1, 2, 3.

## The fee's quantum is one charge

`charge_damage` is 25 HP, so the director's "20–30 HP" is **exactly one connection**. A lane cannot
charge 18 or 27; it charges 25, 50, 75. The price bands are therefore one strike cycle wide, and a
lane is authored at a chosen position inside its band rather than at an edge — an edge lane is quoted
at one price and collects another the moment live pacing differs from the model by a fraction of a
second.

Lanes sit LOW in the band (`strike_band_position`, 0.25). A connection costs the runner time as well
as HP, so cover has to be close behind the hit that was paid for; mid-band leaves enough room for that
delay to earn the chaser a second connection the lane never advertised.

## Terms the build surfaced

Each of these was found by the fragment's test disagreeing with the model, and each is now carried:

1. **A lane only charges if the chaser can still see the runner at the widest the gap ever gets.** The
   sprint opens more distance than the walk gives back, so a chaser whose sight is shorter than that
   peak simply loses the party mid-lane and collects nothing. `price()` reports
   `required_detection_range` on every lane; the fragment configures its chaser from it.
2. **The spotting beat is pure head start.** The chaser stands still through `alert_duration` while
   the runner is already sprinting, which is worth several units of gap on its own.
3. **The runner keeps escaping through the strike.** It walks through the telegraph and through the
   lunge, so the chaser must cover the reach it started at plus everything gained in between: a
   connection takes about 1.8 s from entering reach, not the 1.1 s that telegraph-plus-lunge suggests.
4. **A landed charge cancels the target's move order.** See below — this is the one with design
   consequences.
5. **A mixed-pace party cannot be charged one price.** Members carry their own speeds; a lane cut for
   the slowest under-charges the fastest and vice versa. A route is a SOLO dash in this build.

## A displacement adjusts the walk; it never cancels it

The intended beat is: run, run out, get caught, pay 20–30 HP, reach cover. The shipped systems used to
do something else — the connection cancelled the runner's movement command and nothing re-issued it,
so a runner who was not re-commanded stood where the charge left them and was struck every cycle until
they were down. The fragment's first passes measured 100 HP and a corpse.

**Director's ruling: a consequence ADJUSTS the movement command, it does not cancel it** — and what
can be precomputed should be. That is now how the world works, for the shove, for a dodge, and for a
knockdown alike:

- The body's walk ORDER is lifted off the plan before the plan is torn down, and held as a command
  shape (destination, floor, route constraint) rather than a bare point.
- It is re-issued from the callback the displacement had **already scheduled** — the shove's end tick
  is known the moment it is committed, so nothing is discovered by polling. That is the precomputed
  half, and it is what makes the resumed walk fast-forward invariant.
- The **route** is deliberately re-solved at the landing tick rather than frozen at commit: a quarter
  of a second of other bodies moving can invalidate a frozen plan, and the body would walk into a
  blocker that appeared while it was in the air.
- A newer order always wins. A held order is dropped by any explicit move, stop, walk-path, push, or
  by the body going down.
- It is **derived**, never logged: the walk was recorded once when the player gave it and the shove
  once when it landed, so a replay of exactly those entries rebuilds the resumed walk.

Opting in is per-displacement. A carry ENDS the rider's errand — it is why the rider got on — so the
~20 other traversal callers keep today's semantics, and a wash sweep still strands the member it
carried backwards. Only the strike shove opts in.

Guards: `--test-strike-preserves-destination` (a struck walker owns a plan ending at its destination
after every shove, and arrives) and `--test-displacement-resume-discipline` (one walk order logged
across two shoves; identical strikes, HP and finishing position at a fine and a coarse clock). The
long hall's own test now issues **one** order for the whole run and still pays exactly 25 HP.

Still open, and separate: a move clicked *during* the shove is refused outright by
`can_accept_move_command`, so it is lost rather than replacing the held order. And `_apply_set_level`
— a scripted floor change — still drops a walk; it has twelve call sites and deserves its own ruling.

## Affordability is not reachability

`route_affordability(lanes, party_hp)` and `fork_viability(routes, party_hp)` answer the question the
greedy flood-open validator cannot: not "can the party walk this" but "can the party survive it". A
fork every arm of which costs more HP than the party has is a stranded run even though every arm is
walkable. `fork_viability` names the payable arms and the cheapest one, with ties broken on the id so
a seed reports the same arm on every replay.

This is the G3 guard the open-world ruling made a prerequisite.

## The fragment

`--preview=long_hall` (picker title **Long Hall**). Two mouths off one plaza, each sealed until it is
chosen so no route can be entered before it is priced: the hall quotes its HP fee on the plate, the
long way quotes none and costs the minutes the hall was buying. A route board reads both out. Greybox;
dressing is a canon consultation, not part of the arithmetic.
