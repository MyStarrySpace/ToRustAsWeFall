class_name RunEconomy
extends RefCounted

## The across-fragment ECONOMY model (Layer B). A branch fork is only a real choice if neither option dominates:
## the costly/risky path must out-value the safe path for CLEAN play (its extra ATP is worth the extra exposure),
## and the safe path must out-value it for SLOPPY play (the extra exposure costs more than the extra ATP). That
## crossover is what we tune toward. The model is intentionally simple + derived from the spec the generator
## already emits (per-node atp_reward = gain, per-node pressure = exposure), so the headless playtest can measure
## the economy of any generated branch without new authored data.

const GeneratorScript := preload("res://scripts/generation/stretch_generator.gd")

## ATP-equivalent a unit of exposure costs when a player BOTCHES it (takes the hit instead of routing around it).
## Tuned against the branch ATP rewards so the risk/reward fork has its crossover in-range.
const LOSS_PER_PRESSURE := 6.0

## A shelter rest at the exit restores a flat ATP chunk (GDD 3.3) — counted as gain so a longer, more-sheltered
## route is genuinely worth more banked ATP.
const SHELTER_RESTORE := 8.0

## Per interior node a player must TRAVERSE: time in the open is itself exposure, so a longer route inherently costs
## more when played sloppily (this is what makes "longer and more exposed" actually cost something in the model).
const TRAVERSAL_EXPOSURE := 1.0

static func atp_gain(spec: Dictionary) -> float:
	var g := 0.0
	for node in spec.get("nodes", []):
		if node is Dictionary:
			g += float((node as Dictionary).get("atp_reward", 0))
	return g + SHELTER_RESTORE

## Total exposure across the stretch: authored pressure_cost (gauntlet/attrition), a unit per node that fields a
## live threat, AND a traversal unit per interior node (length = time exposed). This is what a player PAYS, scaled
## by how sloppily they play (miss_rate).
static func pressure_load(spec: Dictionary) -> float:
	var p := 0.0
	for node in spec.get("nodes", []):
		if not (node is Dictionary):
			continue
		var role := str((node as Dictionary).get("role", ""))
		if role == "boundary" or role == "shelter_arrival":
			continue
		p += float((node as Dictionary).get("pressure_cost", 0)) + float((node as Dictionary).get("pressure", 0)) + TRAVERSAL_EXPOSURE
	return p

## Expected net ATP of a stretch at a given play quality. miss_rate 0 = flawless (pay nothing), 1 = botch every
## encounter (pay full exposure).
static func expected_net(spec: Dictionary, head_start: float, miss_rate: float) -> float:
	return atp_gain(spec) + head_start - pressure_load(spec) * LOSS_PER_PRESSURE * clampf(miss_rate, 0.0, 1.0)

## Evaluate one branch option: generate its level, then score its expected net ATP (including its head-start reward).
static func evaluate_option(option: Dictionary, miss_rate: float) -> Dictionary:
	var spec: Dictionary = GeneratorScript.generate((option.get("settings", {}) as Dictionary).duplicate(true))
	var hs := float((option.get("reward", {}) as Dictionary).get("atp_head_start", 0))
	return {
		"id": str(option.get("id", "")),
		"net": expected_net(spec, hs, miss_rate),
		"gain": atp_gain(spec),
		"load": pressure_load(spec),
		"head_start": hs,
		"success": bool(spec.get("success", false)),
	}

## Evaluate a whole fork at a play quality: { costly, safe, costly_wins }. options[0] is costly, options[1] safe.
static func evaluate_branch(decision: Dictionary, miss_rate: float) -> Dictionary:
	var opts: Array = decision.get("options", [])
	if opts.size() < 2:
		return {}
	var costly := evaluate_option(opts[0], miss_rate)
	var safe := evaluate_option(opts[1], miss_rate)
	return {"costly": costly, "safe": safe, "costly_wins": float(costly.net) > float(safe.net)}
