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

## Being caught is currently terminal, not a toll

The intended beat is: run, run out, get caught, pay 20–30 HP, reach cover. What the shipped systems do
is: the connection **cancels the runner's movement command**, and nothing re-issues it. A runner who
is not re-commanded stands where the charge left them and is struck again every cycle until they are
down — in the fragment's first passes the runner paid 100 HP and died in the open.

A real player re-commands toward cover immediately, and then the lane behaves exactly as designed: one
hit, then away. The fragment's drive does the same, and that is legitimate play rather than a
workaround. But it means the fee is only bounded for a player who reacts. **Open question for the
director:** should a landed charge preserve the target's destination and resume the walk (making the
toll self-limiting), or is "if you freeze after a hit you die" the intended teeth?

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
