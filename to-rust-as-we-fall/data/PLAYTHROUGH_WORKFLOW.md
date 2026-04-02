# Optimal Playthrough Workflow

## Purpose

Simulate an optimal player run through each game section to measure pacing, APM feel, and difficulty. This is a design validation tool, not a functional test. The test suite verifies code correctness. The playthrough validates game feel.

## What We Measure

| Metric | How | Target |
|--------|-----|--------|
| **Section time** | `status` at start/end of each section, delta the scheduler ticks | 3-5 min per shelter stretch at 1x speed |
| **APM** | Count commands per section, divide by section time | 10-20 actions/minute feels engaged without frantic |
| **Dead time** | Seconds where the player has nothing to do | < 5s continuous dead time |
| **Difficulty** | Does the optimal strategy require thinking, or is it autopilot? | Each section should have 1-2 decision points |
| **Dialogue density** | Lines per section | 4-8 lines per narrative beat; > 10 is monologue |

## How to Run

```bash
cd to-rust-as-we-fall
timeout 120 ../Godot_v4.6.1-stable_win64_console.exe --headless --path "." \
  -- --cli --cli-script "res://data/test_optimal_playthrough.txt"
```

The output shows each command executing and `status` dumps at section boundaries.

## How to Write a Playthrough Script

### File format
Plain text, one command per line. `#` comments describe strategy.

### Section structure
```
# === SECTION NAME ===
# Strategy: [what the optimal player does]
# Expected: [estimated time breakdown]
status                    # Checkpoint: record start state
[commands]                # The actual play
status                    # Checkpoint: record end state
```

### Commands available
- `move <x> <z>` — Move player to position (waits for arrival)
- `wait <seconds>` — Advance game time
- `advance` — Click through one dialogue line
- `run` — Toggle run/walk
- `dwell [secs]` — Wait for proximity interaction
- `status` — Print game state snapshot
- `assert <stat> <op> <value>` — Verify a stat

### Writing the optimal strategy

For each section, answer:
1. **What does the player know?** (first play vs. second play)
2. **What's the fastest path?** (skip optional content)
3. **What must the player do?** (required interactions, forced dialogue)
4. **What can go wrong?** (hazards, enemies, wrong turns)
5. **How does the player avoid what can go wrong?** (the optimal input sequence)

Write the commands that execute the optimal strategy. The `#` comments ARE the design documentation — they explain why each command is the right move.

## When to Run This

- **After adding a new section**: Write the playthrough commands for it, run, check pacing
- **After changing dialogue**: Re-run to verify section times haven't bloated
- **After changing movement speeds/distances**: Re-run to verify travel times
- **After changing enemy behavior**: Re-run to verify the optimal strategy still works
- **Before milestone**: Full playthrough to check the entire experience

## Interpreting Results

### Pacing reference: Subnautica day/night

The GDD targets ~15 min day, ~5 min night. A full day-night cycle is ~20 min.
Players should reach shelter in 3-5 min of game time per shelter stretch.
An Act 1 run (shelters 1-10) should take ~30-50 min of game time.

### Level sizing math

- Walk speed: 3.0 units/sec. Run: 6.0 units/sec.
- 3 min of walking = ~540 units of linear distance.
- But exploration is not linear: side branches, backtracking, dwelling at
  interactables, avoiding hazards. Effective exploration covers ~40% of
  distance walked. So a level with 200 units of main path + 100 units of
  side branches gives ~300 units to explore, which takes ~3-4 min at walk.
- Width should be 30-60 units to allow meaningful route choices.

### Good pacing
- Each shelter-to-shelter stretch is 3-5 min at 1x speed
- Dialogue and movement alternate (never > 45s of pure dialogue or pure walking)
- The player always knows what to do next (prompt, dialogue hint, or environmental cue)
- Transitions between sections feel like progression, not loading
- At least 2-3 side branches worth exploring per section
- At least 1 resource decision per section (food, flora, shelter timing)
- The day/night clock creates gentle urgency, not panic

### Bad signs
- Section < 2 min: hallway, not a level. Add branching, resources, exploration.
- Section > 7 min: too sprawling for one shelter stretch. Split or add a midpoint.
- > 10 consecutive `advance` commands: monologue. Break it up with movement or interaction.
- Dead time > 10s with nothing to do: player is lost. Add a landmark or prompt.
- 0 decision points in a section: autopilot. Add a route choice or hazard.
- Main path is a straight line with no width: player never has to look around.

## Updating the Playthrough

When you add or change a section:
1. Add the section to `test_optimal_playthrough.txt` with strategy comments
2. Run the playthrough
3. Record actual times in the comments (replace "Expected" with "Actual")
4. If pacing is off, adjust the section (dialogue count, walk distance, hold times)
5. Re-run until pacing feels right
6. Commit the updated playthrough script — it IS the pacing design document
