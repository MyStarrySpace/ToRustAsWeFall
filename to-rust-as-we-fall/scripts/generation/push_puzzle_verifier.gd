class_name PushPuzzleVerifier
extends RefCounted

## §8.6 — the exact decision procedure at chamber scale: BFS over canonical states, transitions
## enumerated from the model's own legality, pruned by the sound filters (a pruned branch is
## provably unsolvable, so pruning never costs completeness). This is defense in depth against the
## builder — a bug in pull legality would otherwise emit an unsolvable room WITH a certificate —
## and the reference the guard tests trust.

const STATE_BUDGET := 400000

## Returns {solvable, pushes (optimal count when solvable, -1 otherwise), explored, budget_hit}.
static func solve(model: PushPuzzleModel, crates: Dictionary, player: Vector2i) -> Dictionary:
	if model.is_solved(crates):
		return {"solvable": true, "pushes": 0, "explored": 0, "budget_hit": false}
	var live := model.live_cells()
	for c in crates.keys():
		if not live.has(c):
			return {"solvable": false, "pushes": -1, "explored": 0, "budget_hit": false}
	if model.freeze_deadlocked(crates):
		return {"solvable": false, "pushes": -1, "explored": 0, "budget_hit": false}
	var seen := {model.state_key(crates, player): true}
	var frontier: Array = [{"crates": crates, "player": player}]
	var depth := 0
	var explored := 0
	while not frontier.is_empty():
		depth += 1
		var next_frontier: Array = []
		for state_v in frontier:
			var state: Dictionary = state_v
			for push_v in model.legal_pushes(state["crates"], state["player"]):
				var push: Dictionary = push_v
				var after := model.apply_push(state["crates"], push["crate"], push["dir"])
				explored += 1
				if explored > STATE_BUDGET:
					return {"solvable": false, "pushes": -1, "explored": explored, "budget_hit": true}
				if model.is_solved(after["crates"]):
					return {"solvable": true, "pushes": depth, "explored": explored, "budget_hit": false}
				var crate_dead := false
				for c in after["crates"].keys():
					if not live.has(c):
						crate_dead = true
						break
				if crate_dead or model.freeze_deadlocked(after["crates"]):
					continue
				var key: String = model.state_key(after["crates"], after["player"])
				if seen.has(key):
					continue
				seen[key] = true
				next_frontier.append(after)
		frontier = next_frontier
	return {"solvable": false, "pushes": -1, "explored": explored, "budget_hit": false}
