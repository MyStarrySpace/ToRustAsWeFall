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
