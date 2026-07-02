class_name RunSession
extends RefCounted

## The modular, HEADLESS roguelike run loop: generate a level → at the shelter, offer a branch → choose → apply
## the reward → generate the next. Pure data (no UI, no scene) so it's the single authority for run logic and is
## drivable end-to-end in a test; the fragment loader is a thin presenter over it. Deterministic: every level's
## seed + every branch pattern is hashed from (run seed, depth), so a run is reproducible from its seed + choices.

const GeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const BranchScript := preload("res://scripts/generation/run_branch_decisions.gd")
const ChunkGenScript := preload("res://scripts/generation/chunk_generator.gd")

## Level kinds a run can serve. "stretch" = the WFC room-piece levels. "atom" = GATED ATOM CHAINS from the
## chunk-atom pipeline: provably gated + lock-before-key + safe-passage (the report card is the playability
## gate), built by puzzle_atom_chunk with REAL mechanics and laid on a seeded hub SHAPE with the base floor.
const LEVELS_STRETCH := "stretch"
const LEVELS_ATOM := "atom"

## Hub shapes an atom run rotates through (seeded per depth) — the macro-shape variety of the descent.
const ATOM_SHAPES: Array = [
	{"type": "circle"},
	{"type": "rect", "aspect": 1.6},
	{"type": "hexagon"},
	{"type": "triangle"},
]

var seed: int
var depth: int = 0
var levels: String = LEVELS_STRETCH
var roster: Array = ["aster", "peris"]
var spec: Dictionary = {}        # the current level
var history: Array = []          # one entry per descent: {depth, choice, pattern, reward, roster, spec_id}

func _init(run_seed: int = 1, levels_mode: String = LEVELS_STRETCH) -> void:
	seed = run_seed
	levels = levels_mode

## Generate the opening level (depth 0). Returns the spec (spec.success is false on failure).
func start() -> Dictionary:
	depth = 0
	roster = ["aster", "peris"]
	if levels == LEVELS_ATOM:
		spec = _generate_atom_level(0)
	else:
		var settings := BranchScript._settings(seed, 0, "entry", "teaching", roster)
		spec = GeneratorScript.generate(settings)
	history = [{"depth": 0, "choice": "start", "pattern": "start", "reward": {}, "roster": roster.duplicate(), "spec_id": str(spec.get("id", ""))}]
	return spec

## The branch decision offered at the current shelter (two tradeoff options). In atom mode the FIRST
## (costly) option also lengthens the next chain by one gate — the honest difficulty axis (more puzzle,
## never tighter windows), marked on the option so choose() can read it without caring about risk labels.
func branch() -> Dictionary:
	var decision: Dictionary = BranchScript.decide({"depth": depth, "seed": seed, "roster": roster})
	if levels == LEVELS_ATOM:
		var opts: Array = decision.get("options", [])
		for i in range(opts.size()):
			(opts[i] as Dictionary)["atom_stage_bonus"] = 1 if i == 0 else 0
	return decision

## Descend by taking one option: apply its reward (recruit grows the roster, depth_skip deepens), then generate
## the next level WITH the (possibly grown) roster so it stays solvable by the current party. Returns the new spec.
func choose(option: Dictionary) -> Dictionary:
	var reward: Dictionary = option.get("reward", {})
	if reward.has("recruit"):
		var who := str(reward["recruit"])
		if who != "" and not roster.has(who):
			roster.append(who)
	depth += 1 + int(reward.get("depth_skip", 0))
	if levels == LEVELS_ATOM:
		spec = _generate_atom_level(int(option.get("atom_stage_bonus", 0)))
	else:
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
	if levels == LEVELS_ATOM:
		# The report card IS the playability gate: gated (P8) + lock-before-key + SAFE-PASSAGE + every
		# archetype backed by a real mechanic. Stronger than connectivity — the level is a provably fair,
		# provably gated puzzle, not just a connected space.
		return bool((spec.get("card", {}) as Dictionary).get("ok", false))
	var summary: Dictionary = spec.get("headless", {}).get("solution_summary", {})
	return bool(summary.get("bare_pair_solvable", false))

## An atom-chain level descriptor: stages scale with DEPTH (2 -> 4 gates; the costly branch adds one), the
## variant pool widens with depth (teaching runs are lure-only and legible; deeper runs mix patrol/twin —
## information and register demands rise, windows never tighten), and the hub SHAPE rotates by seed+depth.
## The skeleton is composed + graded HERE so the run can refuse an unfair level before it ever loads.
func _generate_atom_level(stage_bonus: int) -> Dictionary:
	var atom_seed := int(hash("atomrun:%d:%d" % [seed, depth]))
	var rng := SeededRng.new(atom_seed)
	var count := clampi(2 + depth / 2 + stage_bonus, 2, 5)
	var pool: Array = ["lure"]
	if depth >= 1:
		pool.append("patrol")
	if depth >= 2:
		pool.append("twin")
	var stages: Array = []
	for i in range(count):
		stages.append("distract:%s" % str(pool[int(rng.call("randi_range", 0, pool.size() - 1))]))
	# FLAT, by direction: the hub warp shipped broken in play (stale coord_map across descents; the base
	# contract violated by the shifted-origin grid — both confirmed by review) and the director has parked
	# the shape system. Runs serve flat, readable levels until the warp is rebuilt and PLAYTESTED.
	var shape: Dictionary = {}
	var _unused_shape_pool := ATOM_SHAPES.size() + int(rng.call("randi_range", 0, 1))  # keep the rng cadence stable
	var skeleton: Dictionary = ChunkGenScript.compose(stages, atom_seed)
	var card: Dictionary = ChunkGenScript.report_card(skeleton)
	return {
		"kind": "atom",
		"id": "atom_d%d_%d" % [depth, atom_seed],
		"success": bool(card.get("ok", false)),
		"stages": stages,
		"seed": atom_seed,
		"hub_shape": shape,
		"depth": depth,
		"card": card,
	}
