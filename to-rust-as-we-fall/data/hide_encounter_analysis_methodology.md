# Hide Encounter Analysis Methodology

This encounter is a hybrid system:

- Continuous dynamics: stamina, character movement, swarm travel
- Discrete events: lure activation/expiry, hide timing, exit-window release
- Discrete stamina impulses: plant consumption can subtract a fixed stamina cost at hold completion

The analysis pipeline treats those separately on purpose:

1. Closed-form estimates tell us where the puzzle should succeed in the idealized model.
2. Phase-plane traces show how stamina and remaining distance evolve during retreat and exit.
3. Bifurcation sweeps show where changing starting stamina flips the outcome.
4. Monte Carlo trials measure how often player-like delays or small model perturbations break the closed-form prediction.

## State Variables

- `S(t)`: Peris stamina
- `D_retreat(t)`: remaining distance from lure 1 to lure 2 during the retreat leg
- `D_exit(t)`: remaining distance from the hide to the exit during the final run
- `x_swarm_i(t)`: siderophore positions
- Discrete mode:
  - lure state: none / `lure1` / `lure2`
  - party state: holding / retreating / hiding / exiting

## Phase Plane

The phase plane uses:

- `x = distance_remaining`
- `y = stamina`

It should be read with five vector-field regions:

- `run`: `dS/dt = -run_drain`, `dD/dt = -run_speed`
- `walk`: `dS/dt = +walk_regen`, `dD/dt = -walk_speed`
- `hold`: `dS/dt = +hold_regen`, `dD/dt = 0`
- `hide`: `dS/dt = +hide_regen`, `dD/dt = 0`
- `stand`: `dS/dt = +stand_regen`, `dD/dt = 0`

If plant use has an instantaneous stamina hit, the phase-plane bundle also reports a discrete event:

- `consume_plant`: `ΔS = -consume_stamina_cost` once per completed hold

The main switching manifold is the run-finish boundary:

`distance_remaining = (run_speed / run_drain) * stamina`

Points below that line can finish the current leg by running continuously.

## Bifurcation Sweep

The primary one-parameter bifurcation is starting stamina:

- Sweep initial stamina across a dense range
- Run the intended policy at each stamina value
- Record:
  - actual success/failure
  - actual lure-1 margin
  - actual lure-2 exit margin
  - closed-form predicted success/failure

The key result is the first stamina value where the intended route becomes viable.

## Monte Carlo

The Monte Carlo sweep is not for in-game randomness. It is for robustness against:

- small pre-retreat hesitation
- small lure-2 activation delay
- small exit release delay
- reduced effective exit stamina
- small uncertainty in siderophore travel speed

For each sampled trial we record:

- inputs
- actual outcome
- closed-form predicted outcome

This gives a confusion matrix:

- true positive: closed-form predicted success and sim succeeds
- false positive: closed-form predicted success but sim fails
- true negative: closed-form predicted failure and sim fails
- false negative: closed-form predicted failure but sim succeeds

False positives are the cases the closed-form missed.

## Deliverables

The export bundle should include:

- tuned config
- search summary for the current best distances
- search parameter space for every free variable in the solver
- `phase_plane`
- `stamina_bifurcation`
- `monte_carlo`

The current solver treats these as free parameters:

- `lure_distance`
- `hide_distance`
- `siderophore_speed`
- `run_drain`
- `walk_regen`
- `stand_regen`
- `consume_stamina_cost` for a fixed stamina hit each time a lure plant is consumed
- `hold_regen` when lure interaction recovery should differ from standing recovery
- `hide_regen` when hidden waiting should differ from standing recovery
- `hold_duration`
- `cluster_gap`
- `exit_gap`
- `lure_duration` applied to both lures together
- `lure1_duration` / `lure2_duration` separately when asymmetric timing is needed

When a shared lure duration is part of the search, the default objective is:

1. maximize the actual `first_success_stamina`
2. break ties by keeping more timing margin in the intended route

That makes the solver look for the tightest valid encounter first, instead of always drifting toward the most forgiving lure timers.

## Commands

Export the analysis bundle:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-analysis "hide_encounter_analysis.json"
```

Render PNGs from that bundle:

```powershell
python tools/plot_hide_encounter_analysis.py hide_encounter_analysis.json
```

Probe whether a shared lure duration is feasible in the current bounds:

```powershell
..\godot.bat --headless --path "." -- --test-hide-encounter-shared-duration
```

Export an exit-gap-focused analysis bundle using the current tuned hallway, lure timings, and siderophore speed:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-exit-gap-analysis "hide_encounter_exit_gap_analysis.json"
```

Export a cluster-gap-focused analysis bundle using the current tuned hallway, lure timings, siderophore speed, and exit gap:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-cluster-gap-analysis "hide_encounter_cluster_gap_analysis.json"
```

Export a run-drain-focused analysis bundle using the current tuned hallway, lure timings, siderophore speed, cluster gap, and exit gap:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-run-drain-analysis "hide_encounter_run_drain_analysis.json"
```

Export a stand-regen-focused analysis bundle using the current tuned hallway, lure timings, siderophore speed, run drain, cluster gap, and exit gap:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-stand-regen-analysis "hide_encounter_stand_regen_analysis.json"
```

Export a hold-duration-focused analysis bundle using the current tuned hallway, lure timings, siderophore speed, run drain, stand regen, cluster gap, and exit gap:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-hold-duration-analysis "hide_encounter_hold_duration_analysis.json"
```

Export a walk-regen-focused analysis bundle using the current tuned hallway, lure timings, siderophore speed, run drain, stand regen, hold duration, cluster gap, and exit gap:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-walk-regen-analysis "hide_encounter_walk_regen_analysis.json"
```

Export a coupled `stand_regen + hold_duration` analysis bundle:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-coupled-stand-hold-analysis "hide_encounter_coupled_stand_hold_analysis.json"
```

Export a coupled `stand_regen + walk_regen` analysis bundle:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-coupled-stand-walk-analysis "hide_encounter_coupled_stand_walk_analysis.json"
```

Export any custom combination search from a JSON preset:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-custom-analysis "res://data/analysis_presets/hide_encounter_recovery_triplet.json" "hide_encounter_recovery_triplet_analysis.json"
```

Export the split `hold_regen + hide_regen` structural sweep:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-custom-analysis "res://data/analysis_presets/hide_encounter_split_recovery.json" "hide_encounter_split_recovery_analysis.json"
```

Export the per-plant consume-cost sweep:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-custom-analysis "res://data/analysis_presets/hide_encounter_consume_cost.json" "hide_encounter_consume_cost_analysis.json"
```

Export the `consume_stamina_cost + hide_regen` coupled search aimed at a `10` stamina threshold:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-custom-analysis "res://data/analysis_presets/hide_encounter_coupled_consume_hide_target10.json" "hide_encounter_coupled_consume_hide_target10_analysis.json"
```

Export the `consume_stamina_cost + exit_gap` coupled search aimed at a `10` stamina threshold:

```powershell
..\godot.bat --headless --path "." -- --export-hide-encounter-custom-analysis "res://data/analysis_presets/hide_encounter_coupled_consume_exit_target10.json" "hide_encounter_coupled_consume_exit_target10_analysis.json"
```

## Recommended Workflow

1. Re-run the tuned search after changing movement, stamina, lure duration, or swarm speed.
2. Inspect the stamina bifurcation threshold first.
3. Check phase-plane traces around the threshold:
   - one just below
   - one at threshold
   - one comfortably above
4. Run Monte Carlo and inspect false positives.
5. If false positives cluster near one mistake mode, widen the relevant margin rather than globally loosening the puzzle.
