class_name PushPuzzleModel
extends RefCounted

## The pure data-layer model of a push-puzzle chamber: walkable cells, goal plates, crates, and one
## pusher. Legality mirrors the shipped planner exactly — cardinal pushes, and player connectivity
## as the planner's own CARDINAL flood (`GridWorld._char_can_reach` walks `_PUSH_DIRS`), which is
## deliberately conservative against the game's 8-dir free walking. The mirror is what makes a
## certificate meaningful: every step legal here is a one-cell plan the shipped verb will accept,
## and the S3 replay guard holds the two languages together.
##
## docs/PUSH_PUZZLE_BUILDER.md is the design; the proof suite behind each method is cited inline.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var walkable: Dictionary = {}   # Vector2i -> true
var goals: Dictionary = {}      # Vector2i -> true

func _init(walkable_cells: Array = [], goal_cells: Array = []) -> void:
	for c in walkable_cells:
		walkable[c] = true
	for g in goal_cells:
		goals[g] = true
		walkable[g] = true

func is_open(cell: Vector2i, crates: Dictionary) -> bool:
	return walkable.has(cell) and not crates.has(cell)

## The pusher's connected component over open cells — cardinal, matching the planner's flood. The
## component IS the player's position for state identity: standing anywhere within it is free.
func player_component(crates: Dictionary, player: Vector2i) -> Dictionary:
	var comp := {}
	if not is_open(player, crates):
		return comp
	comp[player] = true
	var frontier: Array[Vector2i] = [player]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in DIRS:
			var n: Vector2i = c + d
			if comp.has(n) or not is_open(n, crates):
				continue
			comp[n] = true
			frontier.append(n)
	return comp

## Canonical state key: sorted crate cells + the component's minimum cell (§8.1 — position within a
## component is free walking, so the minimum is a sound normal form).
func state_key(crates: Dictionary, player: Vector2i) -> String:
	var cells: Array = crates.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var comp := player_component(crates, player)
	var anchor := player
	for c_v in comp.keys():
		var c: Vector2i = c_v
		if c.y < anchor.y or (c.y == anchor.y and c.x < anchor.x):
			anchor = c
	var parts: Array = []
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	return "|".join(parts) + "#%d,%d" % [anchor.x, anchor.y]

## Every legal push from a state: crate `c` moves to `c+d`; requires open destination, an open
## standing cell `c−d`, and the pusher able to REACH that standing cell.
func legal_pushes(crates: Dictionary, player: Vector2i) -> Array:
	var comp := player_component(crates, player)
	var out: Array = []
	for c_v in crates.keys():
		var c: Vector2i = c_v
		for d in DIRS:
			if not is_open(c + d, crates):
				continue
			var stand: Vector2i = c - d
			if not is_open(stand, crates) or not comp.has(stand):
				continue
			out.append({"crate": c, "dir": d})
	return out

## Apply a push; the pusher ends on the crate's former cell (the planner's own rule).
func apply_push(crates: Dictionary, crate: Vector2i, d: Vector2i) -> Dictionary:
	var next := crates.duplicate()
	next.erase(crate)
	next[crate + d] = true
	return {"crates": next, "player": crate}

## Every legal pull (§8.5 convention): pusher at `p` with crate at `p+d` steps back to `p−d`,
## drawing the crate onto `p`. The exact inverse of a push, which is the certificate theorem's core.
func legal_pulls(crates: Dictionary, player: Vector2i) -> Array:
	var comp := player_component(crates, player)
	var out: Array = []
	for c_v in crates.keys():
		var c: Vector2i = c_v
		for d in DIRS:
			var p: Vector2i = c - d          # pusher stands here, crate at p+d
			var back: Vector2i = p - d       # pusher retreats here
			if not is_open(p, crates) or not comp.has(p):
				continue
			if not is_open(back, crates):
				continue
			out.append({"crate": c, "dir": d})
	return out

func apply_pull(crates: Dictionary, crate: Vector2i, d: Vector2i) -> Dictionary:
	var p: Vector2i = crate - d
	var next := crates.duplicate()
	next.erase(crate)
	next[p] = true
	return {"crates": next, "player": p - d}

func is_solved(crates: Dictionary) -> bool:
	for c in crates.keys():
		if not goals.has(c):
			return false
	return true

## §8.3 — LIVE cells: pull-reachable from some goal in the single-crate relaxation. A crate on a
## non-live cell can never reach any goal, whatever else happens. Sound filter, never a proof of
## solvability. Flood: a live cell `x` makes `n = x − d` live when both `n` and the pusher cell
## `n − d` are walkable (a push n→x needs standing room at n−d).
func live_cells() -> Dictionary:
	var live := {}
	var frontier: Array[Vector2i] = []
	for g in goals.keys():
		live[g] = true
		frontier.append(g)
	while not frontier.is_empty():
		var x: Vector2i = frontier.pop_back()
		for d in DIRS:
			var n: Vector2i = x - d
			if live.has(n):
				continue
			if not walkable.has(n) or not walkable.has(n - d):
				continue
			live[n] = true
			frontier.append(n)
	return live

## §8.4 — freeze certificate over walls and the candidate set ONLY (stability under movement of
## non-members is what makes it sound). Greatest fixpoint: start with every crate, discard any
## member not blocked on both axes by walls/members, repeat. Deadlock iff a surviving member is
## off-goal.
func freeze_deadlocked(crates: Dictionary) -> bool:
	var frozen := crates.duplicate()
	var changed := true
	while changed:
		changed = false
		for c_v in frozen.keys():
			var c: Vector2i = c_v
			var blocked_x := _axis_blocked(c, Vector2i(1, 0), frozen)
			var blocked_z := _axis_blocked(c, Vector2i(0, 1), frozen)
			if not (blocked_x and blocked_z):
				frozen.erase(c)
				changed = true
	for c in frozen.keys():
		if not goals.has(c):
			return true
	return false

func _axis_blocked(c: Vector2i, axis: Vector2i, members: Dictionary) -> bool:
	for side in [c + axis, c - axis]:
		if not walkable.has(side) or members.has(side):
			return true
	return false
