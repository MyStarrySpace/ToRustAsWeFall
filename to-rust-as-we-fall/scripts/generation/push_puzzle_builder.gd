class_name PushPuzzleBuilder
extends RefCounted

## §8.5 — constructive generation with a certificate. The builder plays BACKWARD from the solved
## state: crates start ON goals, and a seeded walk applies legal pulls; the recorded pull sequence,
## reversed, is a step-legal push solution of the emitted instance — that reversal IS the
## solvability proof, shipped inside the instance. Every instance is additionally re-checked by the
## exact verifier (§8.6) and its quality knobs, so a builder bug cannot ship on the certificate's
## authority alone.
##
## Deterministic by construction: all randomness flows from the caller's seed; nothing reads the
## wall clock.

## Returns {} on rejection (caller reseeds), else:
##   {crates: Array[Vector2i], player: Vector2i, goals: Array[Vector2i],
##    certificate: Array[{crate: Vector2i, dir: Vector2i}],   # forward pushes, in order
##    optimal_pushes: int, pull_steps: int, seed: int}
static func build(
		model: PushPuzzleModel,
		seed_value: int,
		pull_steps: int,
		min_pushes: int
	) -> Dictionary:
	var rng := SeededRng.new(seed_value)
	var crates := {}
	for g in model.goals.keys():
		crates[g] = true
	# The pusher spawns on any open cell; pulls immediately constrain it to real standing room.
	var open: Array = []
	for c in model.walkable.keys():
		if not crates.has(c):
			open.append(c)
	if open.is_empty():
		return {}
	open.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var player: Vector2i = open[rng.pick_index(open.size())]

	var pulls: Array = []
	for _step in range(pull_steps):
		var options := model.legal_pulls(crates, player)
		if options.is_empty():
			break
		# Prefer pulls that are not the immediate inverse of the previous one, so the walk detours
		# instead of vibrating in place; fall back to any legal pull.
		var filtered: Array = []
		if not pulls.is_empty():
			var last: Dictionary = pulls[pulls.size() - 1]
			for opt_v in options:
				var opt: Dictionary = opt_v
				var undoes: bool = (opt["dir"] == -(last["dir"] as Vector2i)) \
					and (opt["crate"] as Vector2i) == (last["crate"] as Vector2i) - (last["dir"] as Vector2i)
				if not undoes:
					filtered.append(opt)
		if filtered.is_empty():
			filtered = options
		var pick: Dictionary = filtered[rng.pick_index(filtered.size())]
		var after := model.apply_pull(crates, pick["crate"], pick["dir"])
		crates = after["crates"]
		player = after["player"]
		pulls.append(pick)

	if pulls.is_empty() or model.is_solved(crates):
		return {}   # net-zero: the room would open already solved (S7)

	# The certificate: pulls reversed into pushes. A pull drew crate `c` onto `c − d`; the forward
	# push shoves it from `c − d` back to `c` along `d`.
	var certificate: Array = []
	for i in range(pulls.size() - 1, -1, -1):
		var pull: Dictionary = pulls[i]
		certificate.append({
			"crate": (pull["crate"] as Vector2i) - (pull["dir"] as Vector2i),
			"dir": pull["dir"],
		})

	var verdict := PushPuzzleVerifier.solve(model, crates, player)
	if not bool(verdict["solvable"]):
		# §8.5's theorem says this cannot happen; reaching here means the model diverged from
		# itself and MUST be surfaced, not skipped.
		push_error("PushPuzzleBuilder: certificate exists but verifier refuses (seed %d)" % seed_value)
		return {}
	if int(verdict["pushes"]) < min_pushes:
		return {}
	var crate_cells: Array = crates.keys()
	crate_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var goal_cells: Array = model.goals.keys()
	goal_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return {
		"crates": crate_cells,
		"player": player,
		"goals": goal_cells,
		"certificate": certificate,
		"optimal_pushes": int(verdict["pushes"]),
		"pull_steps": pulls.size(),
		"seed": seed_value,
	}
