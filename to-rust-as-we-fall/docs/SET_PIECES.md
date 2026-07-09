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

Tests: `--test-set-piece-showcase` — data-layer playthrough of all three mechanics (crawl connects,
rotation gates, water level rewalks the grid + aligns floats + drowns the penned enemy), replay-safe.
