# Fragment Composition Model — nested gaps, typed ports, input/output balance

**Owner: the director.** This document records the generation architecture as the director stated it
(2026-08-06), verbatim and unedited, followed by a formalization and an honest map of what the code
does today. The verbatim section is the source of record — where the formalization and the statement
disagree, the statement wins.

Companions: `FRAGMENT_IDEAS.md` (the content register — what to build),
`RISING_WATER_AND_MOVING_PLATFORM_ARCHETYPE.md` (one archetype's causal model),
`BALANCING_BASIN.md` (the worked composition), `SYSTEMS_THINKING_PUZZLE_STANDARD.md` and
`DESIGN_PRINCIPLES.md` (the composition laws every generated level must still satisfy).

---

## 1. The director's statement (verbatim, 2026-08-06)

> So, I want to go over how procedural generation is going to work. What we author is different
> fragments that have certain pieces of the archetype in them and then certain gaps that can be
> resized, and we fill those gaps with fragments that have smaller gaps, and so on. We already are
> starting to think this way with the basin being one fragment containing multiple platform fragments
> rising with it (other fragments could be things like platforms with enemies and you have to drop one
> fragment from above to let the enemy cross off, raise a pedestal to lift the dropped fragment, drop
> another fragment to connect that center fragment with where you're crossing from, and then cross -
> write this idea down exactly as is somewhere)

And, immediately following:

> So we want to note that the output of the fragment is one enemy and two inputs are platforms from
> above. So we then place connecting fragments that fulfill those requirements. And some fragments
> just have inputs, some outputs, we  need to balance the system inputs and outputs when we connect
> various puzzle pieces together

Then, on configuration variability:

> Right. And the cool thing about this fragment is that we can make the center piece a gap for
> another fragment, or we can optionally have an enemy as an input from somewhere else coming in that
> might be needed somewhere further on, so this puzzle also has a configuration with one enemy as
> input, and the pieces connecting to that center piece can come in from different directions, etc.

And, on how the generators are to be used:

> And these generators are for quick brainstorming, but I'll be working collaboratively to improve on
> what gets made and in turn refine the generators

Ruling, when asked whether configurations are authored enumerations *or* free variables a solver
assigns:

> So, the enumeration are free variables

Ruling, on the objection that port balance is a non-local constraint and therefore expensive:

> Actually, the adjacency need not be local in terms of satisfying parameters. We just need to ensure
> that the values be balanced overall, and stay within some bound based on difficulty

> So that's why the wfc

Ruling, on the risk that a port-type vocabulary is either too coarse (everything matches everything —
oatmeal) or too fine (nothing matches anything — a fixed jigsaw):

> So the way we alleviate the risk is that we have slots that are more flexible and that can match tbe
> fine parts

> While fitting into the requirements of other things

And, on spatial orientation as a dimension of variance:

> Also, we should make sure that we also consider spatial positioning with variants. Some mught have
> the same archetype or strategy, but might be vertical (fragments like stairs, pedestals, ladders,
> etc.) And some might be horizontal, and some of the authored puzzle parts might be horizontal or
> vertical so that we can have things like connecting the platforms from above to an upwards piece
> that drops the piece to below and has its own design fragments within it

---

## 1b. Ruling: a configuration is a finite-domain variable over authored values

The either/or was a false choice and the director's ruling dissolves it. Every placement site in a
composition carries a **variable** — which configuration this fragment takes — and the solver assigns
it. The variable's **domain is the authored enumeration**: every value it can take is a
configuration someone named and built.

Both properties are preserved at once, and each one matters for a different reason:

- **The solver gets real latitude.** Assignment is global: the polarity of the enemy port, whether
  the center site is a body or a gap, and which direction a connection arrives from are all decided
  by the composition as a whole, not fixed at authoring time.
- **The output stays legible.** Every assigned value is a configuration the director recognizes,
  so a proposal can be read, judged, and corrected. This is the §1a requirement — a generator whose
  output can't be steered can't be refined.

**This is the same algorithm the project already runs, one level up.** `stretch_wfc_layout.gd`
already solves a variable per node-slot whose domain is an enumerated room-piece set, constrained by
edge-socket compatibility. The configuration model is that, with a richer variable (configuration,
not just piece + rotation) and a richer constraint (port compatibility *and* flow balance, not just
boundary adjacency). It is not a new algorithm class to adopt; it is the existing one to extend.

---

## 1c. Two layers: WFC solves adjacency, a budget solves balance

An earlier draft of this document treated port balance as a constraint that had to be enforced
*inside* the placement solver, and then worried that it could not be, because balance is a property
of the whole assembly while socket adjacency propagates neighbour to neighbour. The director
overruled the premise: satisfaction does not have to be adjacency-local at all. **The values need to
balance overall and stay within a bound set by difficulty** — and that is a different kind of check
entirely, run by a different layer.

The separation, and the reason it works:

| Layer | Solves | Scope | Machinery |
|---|---|---|---|
| **Placement** | what can physically sit next to what | local, neighbour-to-neighbour | WFC — `stretch_wfc_layout.gd`, already shipping |
| **Economy** | do supply and demand balance, and by how much | global, whole-composition | aggregate over typed port quantities, bounded |

**This is what WFC is for.** It is already the right tool for the local problem and it already solves
it. Pushing balance into it was the error — it would have broken the propagation that makes WFC cheap,
in order to answer a question WFC was never the right shape for. The economy layer sits above and
reads the assembled result.

**Adjacency becomes reachability.** A fragment's input does not have to be met by its neighbour. The
enemy that walks off the center platform does not go to the piece next door; it joins the level's
population and is absorbed by any reachable fragment downstream. What the economy layer checks is
that supply of each port type meets demand across the composition, plus that the supplier is
actually reachable from the consumer — not that they touch.

**The check is asymmetric, and the asymmetry is the design.** These are not the same kind of failure:

- A **deficit on a progress-gating input** is a bug. If a fragment needs a platform delivered from
  above and nothing in the composition supplies one, the level cannot be finished. Hard error.
- A **surplus of pressure** is difficulty, not a bug. Enemies produced and never absorbed are simply
  threat left in play, and how much of that is allowed is exactly what the difficulty bound sets.

So the bound is not a safety margin — it is the difficulty knob itself, and it is the same knob the
curriculum ramp already turns. `stretch_systems_curriculum.gd` raises pressure with progression
stage; expressing that as *"how much unabsorbed output may be in flight at once"* gives the ramp a
single measurable quantity instead of a bundle of hand-set numbers. Early stages hold the running
net near zero — produced pressure is absorbed almost immediately. Later stages permit large
excursions, and the level runs hot.

**Cost.** Aggregate arithmetic plus a reachability query, over an assembly WFC has already produced.
No flow solve, no repair pass, no constraint propagation. It is also trivially explainable, which
matters for §1a: the critic can say *"three enemies produced, one sink, net +2 against a stage-2
bound of +1"* — a sentence the director can act on.

---

## 1d. Orientation is a configuration axis, and it already has a home in the grid

A strategy and its spatial realization are different things. The same archetype — *deliver a surface
so a blocker can clear off it* — can be realized horizontally (a bridge slid across) or vertically
(a platform dropped from above onto a pedestal that lifts it). Stairs, pedestals, and ladders are
vertical fragments; some authored pieces are deliberately either. **Orientation is therefore another
axis of the configuration variable**, ranging over the same authored domain as everything else in
§1b: the solver may choose the vertical realization of a fragment the way it chooses any other
configuration.

**The existing catalog split is already correct for this.** `archetype_catalog.json` carries pure
semantics — `requires`, `uses`, `risk`, `approaches`, `min_stage`, `taught_by` — and contains *zero*
dimensional fields (no `size`, `width`, `height`, `footprint`, `span`, `scale`). Orientation-free
strategy at the archetype layer, orientation-bearing realization at the fragment layer, is the split
that already exists; it just has not been named or used.

**Vertical connection is already first-class in the data layer.** This is not new machinery to build:

- The grid is a 2D plane stacked into levels by `grid.level_height`; `grid_to_world(cell, level)`
  and `level_for_y(y)` convert both ways.
- `add_inter_level_link(cell, from, to, "ladder"|"ramp")` registers a cell where a character may
  change floors, with `can_traverse_link`, `get_link_cost`, and `links_from` to query it.
- `find_multi_level_path(start_cell, start_level, end_cell, end_level)` is an A* over `(cell, level)`
  and `command_move_cross_level` actually walks it, splitting the route into per-floor segments and
  transitioning at the link cell.
- `stretch_wfc_layout.solve(...)` already takes a `levels` argument, and `fragment_grammar.gd`'s
  connector record already carries a `level` alongside `KIND_WALK` / `KIND_CLIMB`, with a `_shape_stair`
  among its terminals.

So a "from above" port is not a new concept needing invention — **it is an inter-level link**, and
the game already routes bodies across those. The port layer should be defined in those terms rather
than parallel to them.

Three consequences that do need working out:

1. **Gap extents are per-axis.** A horizontal fragment's resizable dimension lies in the plane; a
   vertical one's lies across levels. A gap declares extent ranges per axis, and orientation selects
   which axis is the one being negotiated.
2. **Vertical flows can be one-way — so reachability is DIRECTED.** Gravity is not symmetric. A
   platform dropped from above reaches what is below it; a body that drops down cannot necessarily
   climb back. The economy layer's reachability query in §1c must therefore run on the directed
   multi-level graph — which is exactly what `can_traverse_link` and `find_multi_level_path` already
   express — and never on undirected adjacency. Getting this wrong would let the check certify a
   supply that the player or the enemy can never actually get to.
3. **The recursion is orientation-blind.** The upward piece that drops a platform "has its own design
   fragments within it": a vertical fragment declares gaps and nests children exactly like a
   horizontal one. Orientation changes the axis, not the model.

---

## 1e. Fine parts, flexible slots — the granularity risk is answered by asymmetry

The open risk was that a port-type vocabulary has to be either coarse or fine and both fail: coarse
types make everything satisfy everything, so every level is the same few verbs rearranged (the
"10,000 bowls of oatmeal" failure, one level up from where it usually happens); fine types make
nothing satisfy anything, so composition collapses into a fixed jigsaw. The director's ruling
dissolves it the same way §1c did — **stop asking the two sides to be the same thing.**

**Supply is fine. Demand is flexible.** A fragment's outputs are as specific as the fragment is: a
Climbvine descent and a slid deck are both `surface`, but they are not interchangeable pieces, and
nothing about them is blurred to make them match. A slot does not name a piece — it names an
**admissible set**: a bound that many fine parts satisfy. Variety comes from the count of fine parts
that clear one bound; character survives because no fine part was coarsened to clear it.

**And the bound is narrowed by context, not authored in isolation.** A slot's flexibility is not
licence to fill it with anything: its effective domain is its own admissible set *intersected with
what everything it must serve requires of it* — the parent's signature above, the neighbours it must
abut, the guarantees downstream fragments assume. A wide slot therefore means *many candidates
filtered by everything else that must hold*, not *an arbitrary fill*. That intersection is
constraint propagation, which is the placement solver's existing job (§1c) — so the flexible slot
narrows through machinery that already ships.

**The mechanism is already in the formalization.** §5.3's site *signature* is exactly this bound —
boundary rungs, availability, hazard ceiling — and a gap's domain is defined there as "every
configuration whose own output signature discharges it." What this ruling adds is the *design
posture* for authoring them: **make signatures wide and fragments specific.** A signature that names
one inhabitant is a mis-authored signature.

**It is measurable, which moves the risk from unsolvable to routine.** Granularity-of-vocabulary is a
design problem nobody can settle in the abstract; slot fanout is a number a validator prints. For
each slot, in context, count the admissible catalog members:

| fanout in context | reading | action |
|---|---|---|
| 0 | unsatisfiable slot | hard error — the composition cannot be filled |
| 1 | a jigsaw notch — the slot names its inhabitant | warn: widen the bound, or admit it is a body not a gap |
| 2–8 | healthy | — |
| many, with no constraint distinguishing them | oatmeal risk — the bound is doing no work | warn: the slot is not asking for anything |

Both warnings are §1a critic lines, not gates. The point is that the vocabulary can now be *tuned by
observation* — author fragments, print the fanout table, adjust the bounds — rather than guessed at
before anything exists.

---

## 1a. The generators are brainstorming tools, not autopilots

The last statement sets the engineering priorities for everything below, so it is stated up front.
The generator's output is a **draft the director edits**, and the director's edits are expected to
flow **back into the generator**. That is a two-way loop, and it changes what "good" means:

- **Legibility over opacity.** A generated composition must be readable and editable as authored
  data — named fragments, named ports, an inspectable assembly — never an opaque blob only the
  generator understands. If the director cannot see why a level came out the way it did, he cannot
  correct it.
- **The balance check is a CRITIC, not a gate.** At brainstorm time an unbalanced or unsolvable
  proposal is useful information, not a failure: the generator should surface *"enemy output at the
  center fragment is unmatched"* and still show the level. Hard rejection belongs at the promotion
  step — when a draft is being adopted as real content — not at the proposal step.
- **Variety and speed beat guaranteed correctness at proposal time.** Correctness gates on the way
  out, not on the way in.
- **Edits must be liftable.** When the director fixes a generated level by hand, there needs to be a
  path for that fix to become a new fragment, a new configuration, a re-weighted rule, or a new port
  type. A refinement that can only ever live in one output is a refinement the generator never
  learns. This is the half of the loop most easily forgotten, and it should shape the data formats
  from the start.

---

## 2. The model

### 2.1 A fragment is an archetype body plus resizable gaps

A **fragment** is an authored piece carrying *some* of an archetype's mechanism — not a whole level
and not a bare mesh. Alongside its authored body it declares **gaps**: interior regions it does not
fill itself, whose extent is a RANGE rather than a fixed footprint. A gap is filled by another
fragment, which may itself declare gaps, and so on down. Recursion terminates at a fragment with no
gaps (an atom).

This is the director's word — **gap**. Note the collision: `building_filler.gd` currently uses "gap"
for non-walkable negative space it packs with architecture (`_grow`, "gap cells"). That usage is
already called *lot packing* in the same file and should be renamed to lot/negative-space, leaving
"gap" to mean the composition region defined here.

### 2.2 Ports: what a fragment demands and what it supplies

Every fragment declares typed **ports**:

- an **input port** is a requirement the fragment cannot satisfy itself — something another fragment
  must supply for this one to be playable;
- an **output port** is something the fragment produces and hands onward.

Ports are typed and counted. The director's worked example, stated exactly: the fragment's output is
**one enemy**; its inputs are **two platforms from above**. A fragment placed above it must therefore
output droppable platforms, and something downstream must be able to receive an enemy.

Ports are not the same thing as the room-piece edge sockets that already exist in
`roompiece_catalog.json` (`wall | open | door`). Those describe *geometric* boundary compatibility —
whether two footprints may abut. Ports describe *gameplay supply and demand*. A composition can be
geometrically legal and still unbalanced.

### 2.3 The balance law

Three fragment shapes fall out of the port declaration:

| Shape | Ports | Role in a composition |
|---|---|---|
| **Source** | outputs only | supplies pressure or affordance (the platform-dropper, the spawn yard) |
| **Transformer** | inputs and outputs | the interesting middle — consumes supply, emits something else |
| **Sink** | inputs only | absorbs what upstream produced (a drown pen, a departure lane, an exit) |

**A composition is balanced when every input port is matched by a reachable, compatible output port,
and every output port is either consumed by a downstream input or explicitly declared as acceptable
surplus.** Unmatched input = an unsolvable level. Unmatched output = leaked pressure (an enemy nobody
accounts for, a platform that does nothing), which is the generative equivalent of dead content.

This is the generator's core constraint, and it is what makes the recursion checkable rather than
merely productive: gap-filling is a matching problem, not a sprinkle.

### 2.4 The worked example, unpacked

Read against the statement, the enemy-crossing fragment decomposes as:

- **Body:** a platform with an enemy standing on it, and a crossing the party wants to make.
- **Input, ×2:** a platform delivered *from above* — the first lets the enemy cross off; the second
  connects the now-vacated center platform back to the side you are crossing from.
- **Input:** a pedestal raise, to lift the first dropped platform once the enemy has left it.
- **Output, ×1:** the enemy, which walks off this fragment and becomes a downstream fragment's
  problem — so some sink must be able to receive it.
- **Result:** the crossing opens.

Each input is a *gap that only a particular kind of fragment can fill*. The platform-from-above
requirement is satisfied by any fragment whose output is a droppable surface; the pedestal by any
fragment that outputs a lift. That substitutability is where variety comes from — the puzzle's shape
is fixed by the port contract, its content is not.

### 2.5 The basin as the existing instance

`BALANCING_BASIN.md` already reads this way: the basin is one fragment whose water level is the
master state, containing multiple platform fragments that rise with it. In port terms the basin is a
source (it outputs *height on a schedule* to everything nested inside it) and its float ring is a set
of children consuming that output. Formalizing this is naming what the basin already does — not
inventing a new mechanism, per the systems-thinking law.

### 2.6 What has to be true for this to work

Three properties the model needs that do not follow automatically:

1. **Size negotiation.** A gap declares an extent range; a candidate child declares a footprint range;
   placement picks a size both accept. Nothing today accepts a target footprint and lays out its
   interior to fit.
2. **Local proofs that compose.** A fragment must declare a *precondition at each input* and a
   *guarantee at each output* ("given a surface delivered here, I guarantee a walkable route from my
   west edge to my east edge"). Then a nested piece is verified once, locally, and the parent composes
   guarantees instead of re-proving the assembled whole. Without this the verification cost is
   combinatorial in depth and the generator cannot be trusted at scale.
3. **The design laws still bind.** Port balance proves a level is *assembled*; it does not prove the
   level is *good*. Every generated composition must still satisfy the bare-pair floor (P10), the
   one-verb-per-section rule (P8), fail-forward recovery (P11), and perception-lock (P2). The port
   system is a substrate for the existing laws, never a replacement for them.

---

## 3. Where the code actually stands (recon 2026-08-06)

Honest map, so nobody plans against machinery that does not exist.

| The model needs | Today |
|---|---|
| A fragment declaring interior gap regions | **Absent.** `roompiece_catalog.json` sockets are edge labels; `content_sockets` on `grated_platform` are fixed 3D points inside one authored `.tscn`, filled with content *nouns* only |
| Gaps with variable extent | **Absent.** Pieces carry a literal `"size": [w,h]`, validated exact; the only transform is `rotate_piece` |
| Depth > 1 (a placed piece that itself has gaps) | **Absent.** `_assign_spatial_features` runs once over `layout.placements` and never re-enters |
| Recursive expansion | **Absent.** `fragment_grammar.gd` is an iterative frontier queue over *exterior* outlets; overlap is a hard reject (`:327`), so growth is sibling-adjacent, never parent-contains-child |
| Typed input/output ports | **Absent.** `archetype_catalog.json` has `requires` / `uses` semantics at the node level, which is the nearest thing, but it is not a port contract and is not matched pairwise |
| Per-fragment solvability contract | **Absent.** `stretch_solution_solver.gd` proves capability satisfaction over the whole node spine; `ChunkGenerator.verify` is per-chunk but is never called by the stretch pipeline |

**Reusable machinery if this gets built:**

1. `FragmentGrammar`'s connector record — `{pos, dir, width, kind, level}` (`fragment_grammar.gd:18`)
   is already the right *shape* for a resizable typed opening. It points outward; ports point inward.
2. `RoomPieceCatalog.sockets_compatible` / `open_sides` / `rotate_piece` — a working, deterministic
   typed-boundary matcher already shared by the WFC layout and the stitcher.
3. `BuildingFiller`'s lot packer and landmark hookup (`building_filler.gd:133-172`) — the only code
   that finds free regions inside a parent and hands them to a second builder that writes **playable**
   cells back (bridges append walkable cells and ladder links). It is depth-1 and hard-coded, but it
   is the existence proof.
4. `ChunkGenerator.verify` / `lock_before_key` / `safe_passage` — the only per-unit solvability
   prover in the codebase. Give it an entry/exit contract and it becomes the local proof of §2.6.2.
5. `content_palette.json`'s `"generator"` field — a declared but currently dead seam for delegating a
   content noun to a sub-builder (it points at `rising_water_crossing_generator.gd`, which
   `StretchGenerator` never calls).

---

## 4. Open questions for the director

1. **Port type vocabulary.** What is the closed list? The example implies at least *surface delivered
   from above*, *lift*, and *enemy*. Height, power, water level, sightline, and time-window are
   plausible neighbours — but the list should be small and canonical, and drawn from
   `ENVIRONMENT_ELEMENTS.md` / `GAMEPLAY_OBJECTS.md` rather than invented here.
2. **Is an unmatched output ever legal?** A surplus enemy could be ambient pressure rather than a
   fault. If so, surplus needs to be declared per port, not tolerated silently.
3. **Depth budget.** How deep does the recursion go before a level stops being readable? The basin is
   depth 2 (basin → floats). Depth 4 may be a puzzle nobody can hold in their head.
4. **Who authors gaps — the fragment or the archetype?** If the archetype owns the gap shape, every
   fragment of that archetype is substitutable by construction, which is the stronger position.
   *(Settled in §5.3: the archetype owns the signature, the fragment owns the geometry.)*

---

## 5. The settled formalization

*Written 2026-08-06 against §1a–§1d. This section supersedes nothing in §1; where it disagrees with
the director's statement, the statement wins. Three independent formalizations were drafted and
adversarially attacked before this synthesis; what survived is marked inline.*

### 5.1 A configuration is a sparse binding vector over the fragment's sites

A fragment declares a **site map** once and a small list of **named configurations**, each a *diff*
against the site map's defaults. That sparseness is the whole answer to "how does the enumeration
stay authorable as fragments gain sites": adding a site adds one default line, not a doubling of rows.

```gdscript
# data/fragments/<id>.tres  →  Fragment (new exports)
sites = {
  "center":   {"kind":"site",  "signature":"sig:surface_span_3x3",  "default":"body",
               "body":"slab_atom_3x3"},
  "occupant": {"kind":"port",  "noun":"fauna_body", "species":"sapscrap",
               "default":"out", "channel":"lateral"},
  "drop_a":   {"kind":"port",  "noun":"surface", "default":"in",
               "channel":"vertical", "level_delta":1, "faces":["above"]},
  "drop_b":   {"kind":"port",  "noun":"surface", "default":"in",
               "channel":"vertical", "level_delta":1, "faces":["above","lateral"]},
  "lift_a":   {"kind":"port",  "noun":"lift",   "default":"in", "channel":"lateral"},
}
configurations = [
  {"id":"ferry_out",   "intent":"Resident enemy walks off the dropped deck and leaves east.",
   "set":{}},
  {"id":"ferry_in",    "intent":"No resident. An enemy arrives from elsewhere and is wanted further on.",
   "set":{"occupant":"in"}},
  {"id":"open_center", "intent":"The center is left OPEN for another fragment to fill.",
   "set":{"center":"gap"}},
  {"id":"teach_drop",  "intent":"No enemy at all — the pure two-drop crossing that teaches the verb.",
   "set":{"occupant":"off", "lift_a":"off"}},
]
```

Three rules keep this human-sized, all enforced by a catalog validator (`--test-fragment-catalog`):

**≤ 8 configurations per fragment, hard red on overflow.** Overflow is a signal to split the
fragment, never to raise the cap. Precedent: `_enforce_spatial_feature_budget`'s tier budgets, which
already refuse to grow silently.

**Every configuration carries a one-sentence `intent`.** A binding vector is machine-legible and
human-hostile; §1a's refinement loop requires the director to recognise a value on sight.

**Nothing that is a free group action is ever a configuration.** Lateral rotation is applied at
domain-build time by `RoomPieceCatalog.rotate_piece`, exactly as today — not stored, not enumerated,
zero rows. This is the single largest anti-explosion lever and it already ships one level up.

*Discarded:* mechanical expansion of an axis product into a flat generated table. It scales, but it
produces rows nobody named, which violates §1b's requirement that every value in the domain be a
configuration someone built — and it makes §1a's edit-lifting loop impossible, because the director
cannot correct a level by pointing at `ferry_span@center=body;fauna=source;decks=above+above`.

### 5.2 The solver's variable, polarity, and determinism

The per-slot variable widens from `{piece_id, rotation}` to `{fragment_id, config_id, rotation}`.
That is a change to two functions in `stretch_wfc_layout.gd` — `_build_domain` and the collapse loop
— not a new solver.

`_build_domain` gains three filters on top of the two it already applies (tag eligibility, required
open sides):

| filter | source |
|---|---|
| lateral port channel opens toward each route-neighbour | folds into the existing `open_sides` check |
| orientation class matches the slot's level delta (§1d) | `horizontal \| vertical \| either` on the configuration |
| site signature satisfiable — every `gap` binding has ≥ 1 inhabitant in the catalog | precomputed bitmask at catalog load |

**Vertical and ambient ports are invisible to WFC.** Only lateral ports touch socket propagation.
This keeps propagation cheap and follows directly from the ruling that satisfaction is reachability,
not adjacency — a "from above" supply is resolved by the economy layer, never by a neighbour check.
It also avoids a trap the recon flagged: `roompiece_catalog.gd` validates exactly `n/s/e/w` with
socket-array lengths bound to `w`/`h`, and `_rotate_cw` is a 4-cycle with no fixed point, so a fifth
socket face cannot be added without voiding rotation.

**Polarity rides the configuration and is never a separate variable.** `ferry_out` and `ferry_in` are
two values of one domain; picking one picks the sign of the `occupant` port. The port's *noun* is
stable across both — what changes is provenance: whether the fragment manufactures the body or owes
it to the composition. This fits the §1b ruling exactly, because the economy layer never chooses a
sign; it only sums what the assignment produced.

**Determinism**, extending the shipping pattern with two corrections:

- One seeded draw per slot over the widened domain, on the isolated stream, unchanged in kind.
- Salt by **structural key, not spine index**. Today `_salt(int(s["index"]))` means inserting a node
  shifts every downstream draw; `_salt(str(s["id"]))` does not. Cheap, strictly better, and it
  belongs in `GENERATOR_SEED_QA.md`.
- Fold the catalog content hash into the effective seed and store `{seed, catalog_hash,
  generator_version}` on the emitted spec, so adding a configuration relabels visibly rather than
  silently re-rolling every existing seed.
- Sort before iterating any Dictionary in `scripts/generation/`. GDScript dicts iterate in insertion
  order, and a determinism bug in a generator is invisible until a replay breaks.

### 5.3 A site is a signature; body and gap are two bindings that discharge it

This is the load-bearing rule, and it is what makes the director's variability (A) cost nothing:

> **A site declares ONE signature. Every binding of that site must discharge the same signature.**

`body` discharges it with a shipped default sub-fragment, itself checked against the signature at
catalog load. `gap` publishes it as a nested placement variable whose domain is every configuration
whose own output signature discharges it. Because the signature is identical either way, **the
parent's local proof never mentions the binding** — opening a site costs zero re-verification.

A signature has exactly three parts, and each answers a specific attack:

**Boundary — invariant, exact.** Which rim cells are open, at which level, at which extent *rungs*.
Not "at least". A filler may not add an opening the parent did not declare, nor close one it did.
This kills the connectivity-covariance unsoundness: "provides at least a walkable surface" is fatal,
because a *larger* filler can silently connect the parent's exit to its entrance and void
`locked_blocks` / `ordering_ok`, which are downward-closed in connectivity. Extents are rungs, never
continuous ranges — the local proof re-runs per rung and the entry splits where the proof changes.
That is an admitted expressiveness loss (cadence periods and telegraph leads are genuinely
continuous), not a feature.

**Availability — `always` or `after_own_gates`.** This answers the gap-demand paradox raised against
every draft: a demand strong enough to preserve the parent's guarantee ("walkable from the start")
appeared to forbid the child from being a puzzle, while a demand weak enough to admit a puzzle
appeared to vacate the parent's guarantee. It is not a paradox — it is a two-valued field the author
sets. A parent that must *reach its own controls* across the site declares `always`, and only atoms
and always-open configurations are eligible. A parent whose guarantee is "the crossing opens at the
end" declares `after_own_gates` and can host a real nested puzzle. This is exactly what
`ChunkGenerator`'s `ordering_ok` already proves locally.

**Hazard ceiling — contravariant, mandatory.** Max enemies, max water level, max concealment tier the
parent's proof tolerates. The validator goes **red** on a signature carrying a hazard-classed
attribute with no ceiling; it must never default to unbounded.

**Depth is capped at 3, asserted.** The basin is depth 2. This is a tractability bound as much as a
legibility one, because an unfilled child port escapes upward into the parent's port row.

**The archetype owns the signature; the fragment owns the geometry that discharges it.** That settles
§4.4 in favour of the stronger position, and the catalog split already supports it —
`archetype_catalog.json` carries pure semantics with zero dimensional fields.

### 5.4 Direction: rotation is free, "from above" is a channel, orientation is a configuration axis

Three port **channels**. The channel decides which layer resolves the port and which matching rule
runs. The *noun* is shared across channels — a droppable deck and a slid bridge are both `surface`,
which preserves the substitutability §2.4 identifies as the source of variety.

| channel | resolved by | matching rule | rotates? |
|---|---|---|---|
| `lateral` | WFC socket adjacency (ships today) | facing sides abut, sockets compatible | yes — labels permute |
| `vertical` | economy layer, directed multi-level reachability | supplier at level > consumer, XZ footprints overlap, gravity-directed | **no** — invariant under the rotation group |
| `ambient` | economy layer, scope containment + value band | consumer inside provider's region, bands intersect | n/a |

"From above" is therefore a distinct **channel**, not a fifth direction value and not a distinct noun.
Gravity is not a symmetry of the plane, so a vertical label is a fixed point of the rotation group;
making it a fifth value of `side` would force `rotate_piece` to special-case one value and void the
symmetry argument the whole domain relies on. Assert this: `rotate(ports)` must permute every lateral
label and fix every vertical one, all four rotations, with a 360° round-trip identity. The pipe-warp
yaw-extraction bug is the same class and it shipped once already.

A **kinding check** runs before any search: a vertical coupling declared at a lateral face is a shape
error, named at catalog load, not a deadlock at generation time.

Orientation (`horizontal | vertical | either`) is a configuration field per §1d, and per §1d(1) a
gap's extent rungs are per-axis, with orientation selecting which axis negotiates.

### 5.5 The economy layer

Aggregate arithmetic plus a reachability query over an assembly WFC has already produced. No flow
solve, no repair pass, no propagation.

**The port record.** Multiplicity and class default from the noun; an override requires a reason
string the validator prints.

```
{ id, noun, species, dir: in|out, channel, mult: exclusive|broadcast,
  class: gating|pressure, count: int, mobility: party|ground_fauna|carried|gravity,
  cell, level, band: [lo,hi] (ambient only), surplus_ok: bool }
```

| noun | mult | class | mobility |
|---|---|---|---|
| `surface` (a deliverable deck) | exclusive | gating | `gravity` (vertical) / `party` (lateral) |
| `lift` | exclusive | gating | `party` |
| `current` / `power` | exclusive | gating | `party` |
| `fauna_body` | exclusive | **pressure** | `ground_fauna` |
| `water_level`, `clock_phase`, `light`, `info` | broadcast | gating | n/a |
| `recovery_anchor` (P11) | broadcast | gating | n/a |

**What is summed.** Only `exclusive` ports enter arithmetic, with multiplicity. Broadcast ports are
never summed — they are a satisfied/unsatisfied predicate. Summing broadcast is how one water level
gets over-counted as satisfying three consumers.

**The asymmetry, in full.** Class × direction gives four cells, and this is the precise settlement of
§1c:

| | deficit (demand > reachable supply) | surplus (supply > demand) |
|---|---|---|
| **gating** | **HARD ERROR** — the level cannot be finished | warning: *dead affordance* |
| **pressure** | warning: *unused sink* (an empty drown pen plays fine) | **BOUNDED by difficulty** — the knob, never an error at proposal |

Pressure-deficit must be a warning and not an error: a level with an absorptive affordance nobody
feeds is under-used, not broken, and erroring on it would make every drown pen in the catalog a
standing red.

**Reachability is directed and mobility-classed.** This is what stops the check certifying a supply
nobody can get to. `enemy.gd` never calls `command_move_cross_level` — enemies are strictly
single-floor movers, and detection is dead beyond `DETECTION_VERTICAL_BAND`. So a `fauna_body` output
on level 1 matched to a drown pen on level 0 across a ladder balances arithmetically and deadlocks in
play. Four predicates over the same assembled graph:

- `party` — full `find_multi_level_path` semantics: 8-dir on a level, plus links.
- `ground_fauna` — same-level flood only, no link traversal.
- `carried` — party reachability (a body a member moves).
- `gravity` — supplier at strictly greater level, XZ footprint overlap with the consumer site, one-way.

One BFS per class per composition, memoised. O(cells) each, ≤ 4 classes.

**What is bounded: peak concurrent unabsorbed pressure, per noun, walked in spine order.** Not the
aggregate total — the total says nothing about how hot the level ever gets, and the player traverses
in order. The spine order already exists and `stretch_solution_solver` already accumulates a
`pressure` float along it, so "measured over a composition the player traverses in order" has a
definite meaning today. Two numbers are bounded: `peak` (the maximum running net) and `final` (net at
the exit — pressure leaked into whatever comes next).

**Curriculum mapping.** `STAGE_PROFILES` 1..6 is today entirely qualitative. The bound is its missing
quantitative column, one table replacing hand-set numbers scattered across the generator:

| stage | profile | peak | final |
|---|---|---|---|
| 1 | isolated_relation | 0 | 0 |
| 2 | prediction_chain | 1 | 0 |
| 3 | stock_and_delay | 2 | 1 |
| 4 | feedback_and_scale | 3 | 1 |
| 5 | leverage_and_topology | 4 | 2 |
| 6 | transfer_under_degraded_perception | 6 | 3 |

Stage 3 is where the number first goes above one, deliberately — "stock and delay" is exactly when
unabsorbed pressure becomes a stock the player is meant to reason about. **These six pairs are a first
calibration, not a derivation; they need playtest tuning and the director's ear.** The bound stays
independent of `complexity_tier`, whose spatial-feature budget explicitly refuses to scale with
campaign stage, so the two knobs do not collide.

**Where the greedy is wrong, stated plainly.** Gating demands are matched most-constrained-first, then
first-fit. That can hand a supply only one consumer can reach to a consumer that had alternatives,
producing a false deficit. Most-constrained-first removes the realistic cases; it is not a maximum
matching and will not be made one, because flow was rejected and a false deficit at proposal time is a
critic line, not a gate. If one is ever observed in practice, the fix is a bounded retry over two
orderings, not a matcher.

**Critic messages, exact wording.** Per §1a these are reported and the level still renders. At
promotion they gate.

```
[economy/gating-deficit] enemy_crossing#3.drop_a needs 1 x surface (vertical, from above);
  0 reachable suppliers in the composition. The level cannot be finished.
  Nearest candidate: platform_yard#1.slab_out (supplies 1 x surface) — not reachable:
  it sits at level 0 and this port needs a supplier above level 1.

[economy/pressure-over-bound] fauna_body(sapscrap): 3 produced, 1 absorbed, net +2,
  peak concurrent 2 against a stage-2 bound of 1. Produced at sites 2, 5, 7; absorbed at site 9.
  The level runs hot.

[economy/leaked-at-exit] fauna_body(ferrule): net +2 at the exit against a stage-2 bound of 0.

[economy/broadcast-band-empty] basin#0.water_level supplies [low..high];
  float_ring#1 needs [mid..mid] and drown_pen#2 needs [high..high] — no single value satisfies both.

[economy/dead-affordance] pedestal#4.lift_out supplies 1 x lift; no reachable consumer.

[economy/unused-sink] drown_pen#6.fauna_in absorbs 1 x fauna_body; nothing upstream produces one.
```

Broadcast checking is scope containment plus **value-band intersection**: for each provider, intersect
the admissible bands of every consumer in its scope and require non-empty. This is one deliberate
addition beyond bare reachability, for a concrete reason — the basin's water level is a map switch,
and a float-ring crossing needing MID composed with a drown pen needing HIGH is reachability-satisfied
and physically impossible.

**Recourse.** The economy layer never reassigns configurations. The only automatic response to a
violation is a capped reseed of the whole generator, with the last attempt shown regardless — exactly
`ChunkGenerator.compose`'s existing posture (4 attempts, failing chunk returned so the report card is
honest). That posture must be preserved.

### 5.6 What a configuration declares so local proofs compose — and the global pass they do not replace

Per configuration:

```
assumes:    per input port — a ground precondition record (noun, species, count, channel,
                             level relation, availability, hazard bound)
guarantees: per output port — a ground guarantee record, same shape
signature_discharge: which site signature each `body`/`gap` binding satisfies
margins:    the leaking-channel declarations (below)
laws:       {bare_pair: bool, teaches: "<verb>", registers_required: [], recovery: "<anchor>"}
cost:       {ticks: [lo,hi], stamina: [lo,hi]}
verified:   {body_hash, signature_hash, prover, status}
```

Composition is one field-wise entailment per matched edge — noun, species, multiplicity family (an
exclusive input may never be fed by a broadcast output), channel, level relation, extent rungs
intersect, availability compatible. Constant time per edge.

**Do not claim the assembled level is never verified.** That claim is false for this game and the
codebase records why: `chunk_generator.gd`'s fairness invariant exists because per-gate local checks
composed into a level where two gates' sentry fans jointly covered the connecting chamber and a
correctly-playing runner got caught on open floor (seed 11). The fix was `safe_passage` — a joint
flood over the assembled whole. Local proofs do not compose on the detection channel, and pretending
otherwise re-ships a bug we already paid for.

The honest architecture is therefore: **the expensive per-fragment solvability proof is local and
cached; a cheap global flood handles a closed list of leaking channels.**

| channel | declared as | checked by |
|---|---|---|
| detection fan | radius in cells | flood over the assembled grid, `safe_passage`'s shape |
| lure / sound | radius | same flood |
| flood / water extent | cells at each level value | same flood |
| sightline | cells | same flood |
| **enemy transit** | derived, not declared | the reachability path the economy layer already computed |

That last row is a genuine win from having computed reachability: when a pressure output is matched to
a sink, the path is already in hand, so every site whose footprint the path crosses is charged against
that site's `hazard_ceiling.enemies`. The interval between an enemy leaving one fragment and arriving
at another was the unowned seam in every draft; it becomes checkable for free.

Two things are honestly **not** covered, and the report must say so rather than assert `ok`:

- **Loadout monotonicity is false.** A bigger party adds detector/target pairs, occupies more distinct
  cells under cooperative reservation, and serialises through crawl mouths one at a time. P10 is a
  floor, not a bottom element that discharges every roster. Proofs stay per-loadout.
- **Shared depletable budgets** — stamina, the day clock, ATP — are not ports. Two locally
  bare-pair-solvable configurations can compose into something the pair cannot finish because both
  spend most of one closed bar. The `cost` interval above is the hook for bounding per-section spend
  the way pressure is bounded; until it is built, a composed bare-pair claim is strictly weaker than a
  local one.

Proof records are keyed on `body_hash + signature_hash` with a **red** in `--test-all` on staleness,
never a warning. A stale green stamp is worse than no stamp, precisely because composition declines to
re-verify.

### 5.7 The smallest proving step

`basin_fill_proof` — one data block, one picker row, one new static, no new geometry. It is the right
fragment because it already carries both multiplicities and a real fauna flow: `dwellers` (roster with
`refuge` + `home`) and `outfall` (a declared world point where an expelled body leaves) inside the
`rising_water_crossing` object, plus two `{"type":"enemy"}` objects that spawn the bodies locally, plus
a broadcast `state_changed` read by four independent consumers through a tag resolver.

Two configurations, each proving one director statement:

- **`dweller_input`** (proves polarity-by-configuration): keep the `dwellers` entry for `dweller_a`,
  remove the `{"type":"enemy","id":"dweller_a"}` object. This *already runs* — `basin_water.gd`'s
  eviction and return loops `continue` on an unresolved id — so the fragment stays playable while now
  *declaring* that it consumes a `fauna_body` it does not supply.
- **`open_center`** (proves body-vs-gap): shrink `float_cells` to the rows nearest each bank, leaving
  the middle undeclared. `_apply_state` toggles walkability on exactly the declared cells, so the
  unfilled middle is a real, legal, uncrossable hole a child must fill. The local proof to
  reparameterise is `rising_water_crossing_spec.gd:195` — extend the "float_cells must contain the
  moving-platform route" assertion to accept a declared gap span plus the assumption "a surface is
  delivered at `float_level` over cells X". ~10 lines, in a validator *already* assumption-parameterised
  by `party_size`.

| file | change |
|---|---|
| `scenes/fragments/fragment.gd` | add `@export var sites: Dictionary`, `configurations: Array[Dictionary]`, `ports: Array[Dictionary]` |
| `scripts/fragments/chunks/data_fragment_chunk.gd:78-86` | `configure_chunk` reads `config["configuration"]`; `_build_chunk` does `load(path).duplicate(true)` **before** applying the patch — the `duplicate(true)` is load-bearing, `load()` returns the cached Resource and mutation would leak across preview reloads and tests |
| `data/fragments/basin_fill_proof.tres` | the `sites` + `configurations` + `ports` blocks; `floors`/`walls`/`grid`/`spawns` untouched |
| `scripts/generation/fragment_economy.gd` | **new** — `check()` over one fragment's own port row |
| `scripts/fragments/fragment_preview_sequence.gd` | one `PREVIEW_ENTRIES` row, appended at the END per the picker-order policy |
| `scripts/test_runner_cli.gd` | extend `_test_basin_fill_proof`; add `--test-fragment-economy` |

The test asserts: rota and float road byte-identical across configurations (geometry invariant); one
fewer local enemy spawned; the dweller roster still names `dweller_a`; the economy check reports a
**pressure-deficit warning**, not an error, with `ok` still true; and the run still reaches the exit
shelter.

That is the whole architecture in miniature: configuration variable → changed port row → economy
critic → level still renders. It does **not** prove cross-fragment reachability, the difficulty bound,
depth > 1 nesting, or "from above" as a solver-visible channel.

### 5.8 Cost

Domain size goes from ≤ 9 pieces × 4 rotations = 36 to ≤ (fragments × configs ≤ 8) × 4, filtered as
today by tag eligibility, required open sides, and now orientation class — realistically 2–8× the
current per-slot domain, on a pass that is one sweep with no backtracking. The economy layer adds ≤ 4
BFS floods over the assembled grid plus a linear walk of the port list: the same order as the existing
`_enforce_spatial_feature_budget` pass, which already runs globally after collapse.

The cost that actually needs budgeting is **proof maintenance**: one cached local proof per
configuration per size rung, invalidated by a body or signature edit. At 9 fragments × ≤ 8
configurations × ~3 rungs that is a couple of hundred `ChunkGenerator.verify` + `safe_passage` runs at
promotion — a minutes-scale job, incremental by content hash, and it must never run inside the
generation loop.

### 5.9 Open questions that need the director

1. **The closed port-noun list.** §4.1 stands. The table in §5.5 is a working proposal; the canonical
   list should be drawn from `ENVIRONMENT_ELEMENTS.md` / `GAMEPLAY_OBJECTS.md`. Past roughly a dozen
   nouns the compatibility matrix goes sparse enough that gaps stop having multiple inhabitants and
   variety collapses into a fixed jigsaw.
2. **Is a delivered enemy ever *gating*?** A body you need for its weight on a plate is a `fauna_body`
   whose absence makes the level unfinishable. If yes, the same noun is both classes and `class` must
   be authored per port with no noun default — a real authoring cost, so his call.
3. **Does killing an enemy count as absorption?** No fragment will ever declare a `fauna_body` input
   meaning "the player fought it". If kills absorb, every level has an implicit unbounded sink and the
   bound is about *concurrency* only, never net. If they do not, the ledger will systematically report
   levels hot that play fine.
4. **The six stage bounds in §5.5.** The shape (peak + final, per noun) is defensible; the numbers are
   a guess at the feel.
5. **Does pressure leak across stretches?** Whether `final` net carries into the next descent segment
   or resets at the shelter changes what the `final` bound means, and touches the roguelite loop.
6. **Depth budget.** §4.3 stands; 3 is recommended (the basin is 2), and it is now doing double duty as
   a tractability bound, so raising it costs more than readability.
