# Elevator Lower Route: Systemic Puzzle Contract

## Boundary and goal

The puzzle begins at the post-fall fork and ends at the wreckage brace marks. The
player must deliver both conscious characters. No overlay, interaction count, or
lead-character X threshold grants completion; the authored `PartyGate3D` is the
physical authority.

## Causal model

- A Flure temporarily pulls only its visibly linked pack.
- A lured pack retains a small inner detection reach and returns when the visible
  window closes.
- Iron deals 8 HP per second only inside Peris's exact visible footprints.
- Running converts finite stamina into traversal time.
- Two crossovers let the player change which cost they pay between beats.
- Route damage persists into the later gauntlet instead of being erased at Endo's shelter.

The expected loop is: observe links or footprints, predict one beat, stage both
characters, commit, inspect the result, then revise or transfer that policy.

## Reasoning and emergence

The likely novice model is that lighting any Flure makes its whole lane safe.
The representative failures must disprove that model in separate, inspectable
ways: only the linked pack responds, an already-committed pack cannot be pulled,
the pull retains an inner reach, and its window can expire before both characters
cross. The leverage point is party staging plus activation timing, not activation
count. HP and stamina are the stocks; lure duration and rearming are the delays;
inner reach, exact iron footprints, and two-body gates are the thresholds.

The route is emergent because those shared rules couple enemy state, party
position, stamina, hazard exposure, crossovers, and the party's later mistake budget.
After the first beat, each remaining beat must change a meaningful spatial or
resource decision. If it only repeats an already-proven activation-and-run input,
it belongs to solved-state execution and should be compressed.

## Viable strategies and mastery

- **Fast relay:** stage both characters, prime each linked Flure immediately before crossing, and run
  through its window. Fastest, but timing- and stamina-sensitive.
- **Cautious iron:** use exact footprint boundaries and SAFE movement previews to
  skirt the fields. Slowest, with no Flure actions and near-zero health cost.
- **Hybrid:** use one or two Flures and the crossovers to avoid the remaining
  pressure. Its time and resource cost should lie between the two extremes.

Random activation is recoverable but dominated. A signal that pulls no available
linked pack—or only part of a committed pack—creates no live window or
successful-prime credit and then rearms. A
valid but unused window expires, its pack visibly returns, and the Flure can be
primed again. Skill is expressed by fewer wasted windows, lower damage, and
deliberate stamina use—not by hidden scores or a junction reward menu.

## Truthful feedback

- `NO TARGET`: the activation produced no live window. Feedback must distinguish
  an absent/out-of-range linked pack (model error) from a correctly linked pack
  that was already committed to an attack (timing error).
- `NO SIGNAL`: the damaging pack was never successfully pulled (model error).
- `WINDOW CLOSED`: the player crossed after a used window expired (timing error).
- `INNER REACH`: the player crowded a correctly lured pack (control error).
- `IRON FIELD n`: identifies the exact footprint that caused damage.

Each failure must preserve the correction opportunity. Aster shows causal links;
Peris shows hazard boundaries. Neither overlay may draw an entry-to-exit solution
path or silently change SAFE/DIRECT routing.

## Acceptance

- Fast, cautious, and hybrid plans can each put both characters at the gate.
- One trailing or downed character cannot advance route transfer, gauntlet
  midpoint, or gauntlet exit.
- Activation without movement makes no spatial progress.
- Early activation followed by waiting does not protect a later crossing.
- A corrected staged activation succeeds after that failure.
- Fast, cautious, and hybrid acceptance runs use the live enemy FSM, navigation,
  stamina, and iron hazards from the same start state; teleporting across route
  thresholds is diagnostic coverage, not proof of a viable strategy.
- Ablating Aster's links or Peris's footprint-risk read must block or strictly
  increase the cost of the strategy that uses that register, without making an
  overlay toggle itself into progression currency.
- A 9-second lower-route window is longer than both cooperative paths in a staged walk but shorter than an
  unstaged full-beat catch-up. The gauntlet always uses the same 14-second Flure
  window, which rewards staging or RUN. Pre-activation approach time is never
  counted in this crossover, and no shelter action silently changes it.
- Endo inspections are optional world-building. Peris tending the dormant plant
  is the sole story transition, and solved execution has no annex checklist or
  invented preparation branch.
