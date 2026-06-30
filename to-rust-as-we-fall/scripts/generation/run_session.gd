class_name RunSession
extends RefCounted

## The modular, HEADLESS roguelike run loop: generate a level → at the shelter, offer a branch → choose → apply
## the reward → generate the next. Pure data (no UI, no scene) so it's the single authority for run logic and is
## drivable end-to-end in a test; the fragment loader is a thin presenter over it. Deterministic: every level's
## seed + every branch pattern is hashed from (run seed, depth), so a run is reproducible from its seed + choices.

const GeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const BranchScript := preload("res://scripts/generation/run_branch_decisions.gd")

var seed: int
var depth: int = 0
var roster: Array = ["aster", "peris"]
var spec: Dictionary = {}        # the current level
var history: Array = []          # one entry per descent: {depth, choice, pattern, reward, roster, spec_id}

func _init(run_seed: int = 1) -> void:
	seed = run_seed

## Generate the opening level (depth 0). Returns the spec (spec.success is false on failure).
func start() -> Dictionary:
	depth = 0
	roster = ["aster", "peris"]
	var settings := BranchScript._settings(seed, 0, "entry", "teaching", roster)
	spec = GeneratorScript.generate(settings)
	history = [{"depth": 0, "choice": "start", "pattern": "start", "reward": {}, "roster": roster.duplicate(), "spec_id": str(spec.get("id", ""))}]
	return spec

## The branch decision offered at the current shelter (two tradeoff options).
func branch() -> Dictionary:
	return BranchScript.decide({"depth": depth, "seed": seed, "roster": roster})

## Descend by taking one option: apply its reward (recruit grows the roster, depth_skip deepens), then generate
## the next level WITH the (possibly grown) roster so it stays solvable by the current party. Returns the new spec.
func choose(option: Dictionary) -> Dictionary:
	var reward: Dictionary = option.get("reward", {})
	if reward.has("recruit"):
		var who := str(reward["recruit"])
		if who != "" and not roster.has(who):
			roster.append(who)
	depth += 1 + int(reward.get("depth_skip", 0))
	var settings: Dictionary = (option.get("settings", {}) as Dictionary).duplicate(true)
	settings["roster"] = roster.duplicate()
	spec = GeneratorScript.generate(settings)
	history.append({
		"depth": depth, "choice": str(option.get("id", "")), "pattern": str(option.get("id", "")),
		"reward": reward, "roster": roster.duplicate(), "spec_id": str(spec.get("id", "")),
	})
	return spec

## Convenience for headless runs/tests: descend by a simple POLICY — "risky" takes the costly option, "safe" the
## other. Returns the next spec.
func descend(policy: String = "risky") -> Dictionary:
	var b := branch()
	var opts: Array = b.get("options", [])
	if opts.is_empty():
		return spec
	var idx := 0 if policy == "risky" else mini(1, opts.size() - 1)
	return choose(opts[idx])

## True when the current level generated successfully, connects entry→exit, and the bare Aster+Peris pair can
## clear it (the solver guarantee) — i.e. it's actually completable. A run never hands the player a dead level.
func current_is_playable() -> bool:
	if not bool(spec.get("success", false)):
		return false
	var summary: Dictionary = spec.get("headless", {}).get("solution_summary", {})
	return bool(summary.get("bare_pair_solvable", false))
