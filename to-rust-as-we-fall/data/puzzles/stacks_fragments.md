# The Open Files Initiative - Authoritative Level Brief

`The Open Files Initiative` is the canonical district name. `Stacks` is retained only as an
internal scene, file, and dialogue-key prefix.

This brief reconciles, in precedence order:

1. Explicit direction for this build: use already-written dialogue, spotlight more of Aster's
   established kit, use a different level layout, and include hostiles in the abandoned facility
2. `data/dialogue/en/act1.xlsx`, sheet `stacks`, for already-written scene text
3. `reference-docs/act1_timeline.md`, the explicit source of truth that resolves the stale district
   ordering and names in GDD section 4.4
4. `reference-docs/to_rust_gdd_v02.md` for broader world, character, and mechanic canon
5. `docs/SET_PIECES.md`, specifically the ratified `Drawer-stairs v2` gameplay ruling where it does
   not contradict the sources above

Implementation convenience does not override those sources.

## Canonical Boundaries

- Sequence: Plumbing Power Project / Channels -> Open Files -> Greenfields / Rings -> lockout.
- Party: Aster, Peris, and Endo. Myke has not joined and must not appear physically or by name.
- Aster's tag is still valid. Its rejection happens later at the simulation-boundary lockout.
- Aster's active early-game ability is `EMP`.
- `SCAN` and `HACK` are target-owned contextual interactions, not additional ability slots.
- Aster's data overlay uses cyan geometry and data to surface map structure, terminal locations,
  hackable systems, environmental readings, and infrastructural data flows.
- Movement arrows, patrol zones, and scan-grid timing belong to Tyreg's later patrol overlay. The
  Open Files must not give that register to Aster.
- Aster's location spoof falsifies his own tracked location so he can access facility areas his
  issued credentials do not permit. It does not rewrite a biological enemy's destination.
- Naturalizers scan tags and remove incoherent presences. A pre-lockout Naturalizer must not behave
  like an ordinary party-hostile while the party's tags are valid.
- The Open Files are canonical Tangler habitat. Tanglers remain environmental foreshadowing until
  their stealth, grapple, drain, tau status, tells, and counters have a real runtime; a generic
  `Enemy` must never be labeled a Tangler.
- Sapscraps are currently implemented and can plausibly infest abandoned iron-rich archive
  infrastructure. They are the initial playable pressure layer, not a substitute renamed Tangler.
- The retired policy-bank comparison is non-canonical and must not gate the level or shelter.

## District Identity

The Open Files is a cold, loud, abandoned cognitive-function zone: drawer-stack canyons, catalog
desks, server cores, scan arches, catwalks, oxide dust, terminal-green remnants, and one
unofficially maintained lane. The layout is vertical and cross-connected rather than another long
corridor. The player repeatedly sees information at the stacks while the controls that act on it
sit across an exposed hall.

The environmental exception is anonymous care:

- cable routing becomes elegant and individually shaped;
- an instrumented lane remains warmer, cooler-running, and better labeled;
- a small workspace contains restarted diagrams and ghost-ID exemptions.

These are retroactive traces of Myke's work. At this point neither the characters nor the player
is told that name.

## Intended Causal Model

The primary set piece teaches one model:

> An index activates every drawer in its category at one fixed depth. A safe staircase exists only
> where the active categories ascend by depth in height order and the physical drawers are sound.

The two required perception registers are complementary:

- Aster answers `WHAT`: category, height, fixed extension depth, terminal relationship, and
  infrastructure flow.
- Peris answers `WHERE`: which candidate columns are damp, rotted, or Scarpet-marked and therefore
  cannot bear weight.
- Endo contributes refuge and hazard-route information, but does not replace either deduction.

The player cycle is:

```text
inspect stacks -> combine Aster and Peris reads -> predict a category set
-> cross to catalog controls -> activate indices -> inspect the physical reshape
-> revise or climb
```

The set is approximately three choices from six. Selection is the reasoning; execution has no
timing sequence.

## Drawer-Stairs v2

The ratified set piece is not a terminal that makes a staircase appear.

- Six category index levers sit at the catalog desk.
- Each category has a fixed stamped extension depth: deep, mid, or shallow.
- Activating one category extends every drawer belonging to it throughout the bay.
- A candidate column becomes a staircase only when its active drawers form ascending depths from
  bottom to top.
- A rotten drawer cannot bear weight. Stepping on it slips the character down one section and
  downs them; it is fail-forward, not a wipe.
- Wrong activations remain useful. Extended drawers reshape aisles into walls and cover, so a
  wrong hypothesis can still help manage hostile pressure.
- The low-level mechanism owns its phase, collision, blockers, and inter-level links. State becomes
  authoritative when activation commits and survives save, load, replay, and fast-forward.
- Visible geometry is real graded drawer motion. Flat blue rectangles, fake portals, or collision
  that appears without the drawer are forbidden.

## Level Beat Chain

### 1. Arrival and causal framing - safe read

The party leaves the Channels and enters the cold processing cores. The first live terminal shows
that data was deliberately cleaned and normalized. Use the already-written opening material
(`stacks.narration.enter` through `stacks.aster.means`) without inventing a policy-comparison game.

This beat establishes the district's question and gives the player a pressure-free view of one
drawer bay, the catalog desk across the hall, and the upper route it can create.

### 2. Index lesson - multi-register deduction

Aster contextually scans tag plates. Peris contextually reads damp and rot. The player selects the
three indices that produce a safe ascending column. One nearby wrong index is deliberately useful:
it blocks a lateral aisle and demonstrates that a mistaken selection changed topology rather than
merely producing an error toast.

Representative misconception:

- Prediction: category names describe individual drawers.
- Evidence: one lever visibly extends that category everywhere in the room.
- Revision: indices are global controls whose local effect depends on each column's arrangement.

### 3. Transfer under Sapscrap pressure

The second bay keeps the same category-to-depth law but changes the viable column and adds a
Sapscrap swarm in the iron-rich lower aisle. The player is not asked to repeat the first answer.
They must use the known global-index relationship in a new spatial arrangement.

An Aster-operated iron purge exposes a sacrificial iron fixture on one side of the room. Its
infrastructural connection is visible in Aster's data register, and the Sapscraps physically move
toward the stronger iron source. This creates a temporary safe side and a tradeoff: the lure clears
one route while concentrating the swarm near another.

Wrong drawer activations can wall off a lane or expose additional iron. The hostile pressure
sharpens category selection but never hides the tag plates or Peris's viability read.

### 4. Aster kit variations

Each contextual system has one distinct, visible consequence:

- `SCAN DATA`: reveals category metadata, terminal ownership, and infrastructural links. It does
  not show patrol arrows.
- `HACK INDEX`: toggles one global drawer category.
- `HACK PURGE`: exposes or retracts a physical sacrificial iron fixture that redirects Sapscraps.
- `SPOOF LOCATION`: opens an optional tracked-access maintenance lane by falsifying Aster's own
  reported position. It does not reroute an enemy.
- `EMP`: trips one clearly electronic, faulted archive circuit as an infrastructure cut-off. It
  opens a short regroup route and cannot be confused with harming a biological enemy.

These are separate beats so the player reads the consequence of each terminal instead of facing a
wall of interchangeable buttons.

### 5. Records and anonymous care

The mandatory support intake uses the existing Pendys/support-team and drink-machine thread:

- network address and support Engram: `stacks.narration.network_address` through
  `stacks.peris.priorities`;
- cleaned terminal and expectation: `stacks.narration.cleaned_terminal` through
  `stacks.aster.expectation`.

The optional spoofed lane uses the existing instrumented-lane and ghost-workspace material:

- `stacks.narration.instrumented_lane` through `stacks.aster.standardization`;
- `stacks.narration.workspace` through `stacks.aster.right`.

Mule's early trail may identify sick-leave filings and escalating incident reports, but the GDD
explicitly leaves the prose pending. Do not invent a Mule monologue or reveal more of the arc.

Optional records reward risk and attention. They are not a checklist and do not independently
unlock the shelter.

### 6. Shelter rest

The shelter follows the terminal-data infrastructure and the cleaned-data discovery. It uses the
ordinary authored party-rest interaction with all three conscious party members gathered.

The exact already-written sequence is:

1. `stacks.rest.narration.open`
2. `stacks.rest.narration.peris_quiet`
3. `stacks.rest.peris.breath`
4. `stacks.rest.peris.cant`
5. `stacks.rest.peris.silence`
6. `stacks.rest.peris.try_again`
7. `stacks.rest.peris.scared`
8. `stacks.rest.peris.ask`
9. `stacks.rest.peris.wait_for_answer`
10. `stacks.rest.aster.start`
11. `stacks.rest.aster.models`
12. `stacks.rest.aster.focus`
13. `stacks.rest.aster.application`
14. `stacks.rest.aster.peris`
15. `stacks.rest.peris.listening`
16. `stacks.rest.peris.huh`
17. `stacks.rest.peris.focus`
18. `stacks.rest.peris.breath_settles`
19. `stacks.rest.aster.notice`
20. `stacks.rest.peris.yeah`
21. `stacks.rest.narration.close`

The six-line `stacks.anxiety.*` rewrite is not the written scene and must not be used. Peris gets a
small handhold, not a cure; the beat's later lockout callbacks depend on that exact emotional work.

## Failure Pedagogy

- Activate one index and expect one drawer: the whole category extends in view.
- Build a staircase in the wrong column: Peris's persistent rot mark explains why the step failed,
  and the character falls one section rather than resetting the puzzle.
- Choose the wrong categories: the resulting walls remain useful cover while the player revises.
- Trigger the iron purge without reading its destination: Sapscraps visibly leave one lane and
  crowd the fixture, exposing the tradeoff.
- Treat Aster's data overlay as threat omniscience: it shows machinery and flow but not the missing
  Tyreg patrol register.
- EMP a biological Sapscrap: it receives no electronic shutdown response; the nearby faulted
  circuit remains the visually matched target.
- Enter the optional lane without spoofing: the access tracker rejects the reported location,
  names that mismatch, and leaves the main route unaffected.

Every failure must expose a wrong prediction through persistent world evidence. Control, camera,
visibility, and repeated traversal errors are defects, not puzzle difficulty.

## Pacing and Acceptance

- First attentive play target: 12-16 minutes including the shelter and optional lane.
- Solved replay target: 6-9 minutes.
- The first bay teaches; the second transfers under ecological pressure; the optional lane rewards
  mastery; the shelter releases tension.
- Hostiles move faster than walking and slower than running where that global tuning applies, but
  the intended solve is routing and system manipulation rather than a sprint check.
- Once the second category set is understood, the climb to the shelter is short. No repeated
  lever-and-crossing chores are added merely to inflate playtime.
- Critical state, causal links, drawer motion, rot, iron attraction, and access rejection remain
  truthful under deterministic replay and save/load.
