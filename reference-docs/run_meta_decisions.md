# TRAWF run meta-decisions

This document records the larger-scale generation decisions, the ones about how fragments are arranged into a run rather than what happens inside one fragment. A fragment here is a run unit, a stretch in story mode or a generated unit in roguelike. This register is the companion to the per-archetype work in `archetype_element_distillation.md`: that doc handles composition inside a fragment, this one handles the topology and economy across fragments. The two compose, since a run's difficulty is produced jointly by how densely fragments merge elements and by the meta knobs recorded here.

## What this register decides, and where the knobs already live

The run shape is, in the current formats, a tree of stretches. `act1_order.json` is a root of nested children, each a stretch with entry and exit shelters, a tier, a stage, a region, and a branch label. Act 1 is authored as a single main branch with empty children, so the branching structure exists but is unpopulated. The economy knobs already exist as well. Tier sets a fragment's difficulty budget, atp_reward rides on the forage and rest archetypes, pressure_cost on the gauntlet and attrition archetypes, routes carry risk kinds, and REST at a shelter restores ATP. So most decisions in this register are about authoring a coherent choice over knobs that are already present, rather than adding new machinery.

## How a meta-decision is recorded

Mirroring the distillation log, each decision below records four things. What it is. The structural and economic knobs it uses. The constraint it has to satisfy. And the tuning target the headless playtest loop measures. The constraints in this register are usually economic or topological rather than solvability, since solvability is handled inside the fragment by the element layer and the solver.

## Decisions

### Risk/reward branch, where a fragment forks into a harder, richer path and an easier, leaner one

What it is. At a branch point in the run, one fragment leads to two child fragments. One is harder and pays more, the other easier and pays less, so the player chooses between pushing for resources and playing safe. The grain is the run unit, a branch between stretches or generated units, populating the campaign tree's branch and children fields that currently sit empty.

Knobs it uses. The harder child is a higher tier (more node budget, more enemies, more pressure) carrying more atp_reward, optionally with higher pressure_cost or fewer shelters along it. The easier child is a lower tier with less atp_reward. The branch itself is two child entries under one parent in the run tree, each with its own tier, stage, and region.

Constraint. The constraint is economic, not solvability. The ATP differential has to make the harder branch worth its expected extra loss while leaving the easier branch still worth taking. If the harder branch pays too little it is never chosen; if it pays too much, the easier branch is never chosen. Either way the choice collapses to a single dominant option and stops being a decision.

Tuning target. The headless playtest loop measures expected ATP gain against expected loss per branch, the same tooling as the within-fragment cost curve. The ATP differential is tuned until neither branch dominates across the range of play quality, light for clean runs and heavy for sloppy ones.

## Candidates, not yet shaped

These belong to this register but are not decided yet. Whether two branches reconverge at a shelter or lead to different regions. Whether a fork commits or is an optional detour that rejoins, where optional nodes and shortcuts already cover the rejoining case. The shelter and ATP cadence across a run, since shelters are where ATP returns. Portal and shortcut placement, which collapse the map. How difficulty and ATP scale with depth. And meta-progression across runs, which the GDD and the roguelike doc explicitly leave open.
