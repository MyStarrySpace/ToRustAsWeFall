# Generated Stretch Seed QA

The maintained seed corpus is
[`data/generation/stretch_seed_corpus.json`](../data/generation/stretch_seed_corpus.json).
A seed case records the integer seed **and** the generator profile that gives the
seed meaning: tier, progression stage, palette limits, composition, and world slot.

## Statuses

- `candidate`: regenerates successfully but has not completed a rendered human playthrough.
- `tuning`: playable end to end; quality or balance changes are still being compared.
- `blocked`: a reproducible issue prevents the case from meeting its acceptance focus.
- `approved`: passes generation/solver checks, deterministic in-engine replay, and a rendered
  real-input playthrough with no open blocking issue.

Never promote a case from solver output alone. The solver establishes a mechanical floor; the
rendered playthrough evaluates first read, causal feedback, failure pedagogy, pressure, control and
camera cost, and how much repetitive execution remains after the model is solved.

## Playing A Seed

Open **Fragments** from the main menu. The **Generated Seed** row can launch a maintained case or
any integer seed. Selecting a maintained case preserves its full generator profile; editing its
number creates a variation of that profile. **N** advances to the next integer seed in-game.

The seed number, case status, and generated title remain visible in the preview header. Restarting
the scene preserves a dynamically launched seed case.

## Machine Verification

From the Godot project directory:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . `
  --script res://tools/verify_stretch_seed_corpus.gd
```

Verify and deterministically play one maintained case:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . `
  --script res://tools/verify_stretch_seed_corpus.gd -- `
  --case=random_walk_3117 --play
```

Exercise an arbitrary custom seed:

```powershell
..\Godot_v4.7-stable_win64_console.exe --headless --path . `
  --script res://tools/verify_stretch_seed_corpus.gd -- `
  --seed=8128 --tier=standard --play
```

## Rendered Playthrough Record

After each run, update the case rather than relying on memory:

1. Increment `playthrough_count` and set `last_played`.
2. Record the first moment the goal and causal boundary became clear.
3. Record any wrong prediction and the evidence that corrected it.
4. Separate model errors from movement, selection, camera, visibility, or timing errors.
5. Record the moment the model was solved and whether later execution added a new decision.
6. Add concrete `blocking_issues`, or remove resolved ones and promote the status honestly.

An approved seed is a regression fixture. Generator changes must keep its causal model and
playability intact; they do not need to preserve identical serialized geometry when the generation
contract intentionally evolves.
