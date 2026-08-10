class_name RunBranchDecisions
extends RefCounted

## The across-fragment RUN-META layer (companion to the per-fragment element composition): at a shelter, a run
## FORKS, and the player chooses between two next fragments with a tradeoff. This is a registry of decision
## PATTERNS, each authoring a coherent choice over the EXISTING generation knobs (tier, roster, depth, route risk)
## — no new machinery, per run_meta_decisions.md. Every pattern offers a COSTLY path that grants a unique reward
## vs a SAFE path without it; the constraint is economic/topological (the differential must keep both worth taking),
## not solvability (that's the element layer + the solver inside the fragment).
##
## Deterministic: the pattern + both children's seeds are hashed from (run seed, depth), so a run is reproducible.

const BiomesScript := preload("res://scripts/generation/biomes.gd")
const BranchPointScript := preload("res://scripts/generation/branch_point.gd")

const TIERS := ["teaching", "standard", "hard", "setpiece"]
const CORE_PAIR := ["aster", "peris"]          # the shadow pair — always in the party, never recruited
# Canonical roguelike-playable roster beyond the core pair (GDD 14.3): the base-game main cast first, then the
# DLC-exclusive cells. Recruit offers the next un-joined one. (Ron is an NPC, not playable; "Monos" is the
# institution's tag for Marco the Macrophage, who goes by "Makrov Mage" in roguelike mode.)
const RECRUIT_ORDER := ["endo", "myke", "oli", "tyreg", "marco", "brobla", "vasca", "senchy", "swan", "ninj", "pendy"]
# Roguelike personas / display names where they differ from the bare id.
const DISPLAY_NAMES := {
	"marco": "Makrov Mage", "endo": "Endo", "myke": "Myke", "oli": "Oli", "tyreg": "Tyreg",
	"brobla": "Brobla", "vasca": "Vasca", "senchy": "Senchy", "swan": "Swan", "ninj": "Ninj", "pendy": "Pendy",
}
const GEAR_POOL := ["hushbloom", "seefern"]   # only live tool flora may enter the salvage reward pool

static func display_name(id: String) -> String:
	return str(DISPLAY_NAMES.get(id, id.capitalize()))

## decide({depth, seed, roster}) -> { pattern, prompt, options:[{id,label,desc,risk,settings,reward}, ...] }
## `options[0]` is the COSTLY/risky path, `options[1]` the safe path.
static func decide(context: Dictionary) -> Dictionary:
	var depth := int(context.get("depth", 0))
	var seed := int(context.get("seed", 1))
	var roster: Array = context.get("roster", CORE_PAIR.duplicate())
	var available := _available_patterns(roster)
	var pattern: String = available[_hash_index("pattern:%d:%d" % [seed, depth], available.size())]
	var decision := _build(pattern, depth, seed, roster)
	_apply_gain_cap(decision)
	decision["branch_point"] = _as_branch_point(decision, depth)
	return decision


## The fork, expressed as the BRANCH POINT it is: a safe arm and a priced one, each with the single
## socket the next level fills. The run has always offered this shape; saying so in the generator's
## own vocabulary is what lets `BranchPoint.validate()` speak about a real run rather than about a
## structure built beside it.
static func _as_branch_point(decision: Dictionary, depth: int) -> Dictionary:
	var tier: String = TIERS[mini(depth, TIERS.size() - 1)]
	var point := BranchPointScript.build({
		"tier": tier, "sockets_per_arm": 1, "damaging_arms": 1})
	for arm_v in (point["arms"] as Array):
		var arm: Dictionary = arm_v
		var want_safe := str(arm.get("class", "")) == BranchPointScript.SAFE
		for option_v in (decision.get("options", []) as Array):
			var option: Dictionary = option_v
			var option_is_safe := str(option.get("risk", "")) == "low"
			if option_is_safe != want_safe:
				continue
			arm["id"] = str(option.get("id", arm.get("id", "")))
			for socket_v in (arm["sockets"] as Array):
				var socket: Dictionary = socket_v
				socket["fragment"] = str(option.get("id", ""))
				# The level behind a socket is generated, so its class is what its own probe will
				# say. The safe arm is held to that by RunSession at the moment of descent; here the
				# arm simply records the intent the fork advertises.
				socket["route_class"] = "clean" if option_is_safe else "damaging"
				socket["hp_cost"] = 0.0
			break
	point["pattern"] = str(decision.get("pattern", ""))
	point["validation"] = BranchPointScript.validate(point)
	return point


## HARD CAPS THE GAINS, NEVER THE BLOOD. A costly arm generating at a tier that caps gains authors
## FEWER physical caches — fewer forage beats, fewer flora slots, fewer optional rooms. It is applied
## to the generation budget rather than to a number on the menu because the run's law is that a
## branch's value comes from what the level physically places, never from an invisible grant attached
## to picking an option.
static func _apply_gain_cap(decision: Dictionary) -> void:
	for option_v in (decision.get("options", []) as Array):
		var option: Dictionary = option_v
		if str(option.get("risk", "")) != "high":
			continue
		var settings: Dictionary = option.get("settings", {}) as Dictionary
		var scale := BranchPointScript.gain_cap_for(
			str(settings.get("complexity_tier", "standard")))
		if scale >= 1.0:
			continue
		var budget: Dictionary = settings.get("budget", {}) as Dictionary
		if budget.is_empty():
			continue
		for key in ["resource_beats", "optional_node_count"]:
			if budget.has(key):
				budget[key] = maxi(0, int(floorf(float(budget[key]) * scale)))
		if budget.has("flora_slots") and budget["flora_slots"] is Array:
			var slots: Array = budget["flora_slots"]
			for i in range(slots.size()):
				slots[i] = maxi(0, int(floorf(float(slots[i]) * scale)))
		option["gain_cap_applied"] = scale

## Which patterns can fire here. Recruit only when a specialist is still un-joined.
static func _available_patterns(roster: Array) -> Array:
	var pats := ["risk_reward", "shortcut", "gear", "respite"]
	if next_recruit(roster) != "":
		pats.append("recruit")
	pats.sort()   # stable order so the seeded index is reproducible regardless of dict iteration
	return pats

static func next_recruit(roster: Array) -> String:
	for c in RECRUIT_ORDER:
		if not roster.has(c):
			return c
	return ""

static func _build(pattern: String, depth: int, seed: int, roster: Array) -> Dictionary:
	var base_i := mini(depth, TIERS.size() - 1)
	var base_tier: String = TIERS[base_i]
	var hard_tier: String = TIERS[mini(depth + 1, TIERS.size() - 1)]
	match pattern:
		"recruit":
			var who := next_recruit(roster)
			return {
				"pattern": "recruit", "prompt": "A distress pulse threads up from the deep channel.",
				"options": [
					_opt("trace", "Trace the signal", "Brutal water and sentries — but a stranded %s waits at the far shelter." % display_name(who),
						"high", _settings(seed, depth, "trace", hard_tier, roster + [who]), {"recruit": who}),
					_opt("slip", "Slip past", "A shallow, quiet run. No one to find.",
						"low", _settings(seed, depth, "slip", base_tier, roster), {}),
				]}
		"shortcut":
			return {
				"pattern": "shortcut", "prompt": "A collapsing maintenance shaft cuts straight down.",
				"options": [
					_opt("collapse", "Take the collapse", "One savage stretch that drops you TWO shelters deep.",
						"high", _settings(seed, depth, "collapse", hard_tier, roster), {"depth_skip": 1}),
					_opt("channel", "Follow the channel", "The normal route — one shelter at a time.",
						"low", _settings(seed, depth, "channel", base_tier, roster), {}),
				]}
		"gear":
			var gear: String = GEAR_POOL[_hash_index("gear:%d:%d" % [seed, depth], GEAR_POOL.size())]
			return {
				"pattern": "gear", "prompt": "A sealed salvage cache glints past a flooded gauntlet.",
				"options": [
					_opt("salvage", "Run the gauntlet", "Dangerous — the cache holds a %s you keep for the run." % gear.capitalize(),
						"high", _settings(seed, depth, "salvage", hard_tier, roster), {"gear": gear}),
					_opt("clean", "Stay clean", "A safe path. No salvage.",
						"low", _settings(seed, depth, "clean", base_tier, roster), {}),
				]}
		"respite":
			# The inverse fork: the SAFE path costs TIME (longer, more exposure) but authors more physical
			# lysate-cache opportunities; the risky path is a short brutal sprint. No branch choice itself
			# changes ATP: the party must find, carry, and endocytose any food the generated stretch places.
			return {
				"pattern": "respite", "prompt": "The route splits: a long sheltered haul, or a short brutal sprint.",
				"options": [
					_opt("sprint", "Sprint it", "Short and savage — no mid-rest.",
						"high", _settings(seed, depth, "sprint", hard_tier, roster,
							{"node_count": [4, 5], "optional_node_count": 0, "resource_beats": 0}), {}),
					_opt("haul", "Take the long haul", "Longer and more exposed, with more lysate caches to work for.",
						"low", _settings(seed, depth, "haul", base_tier, roster,
							{"node_count": [9, 11], "optional_node_count": 4, "resource_beats": 2}), {}),
				]}
		_:  # risk_reward (the decided default)
			# The costly vein is LONGER + richer (more forage), not just higher-tier: its extra length is extra
			# exposure. Its value must come from physical caches in the generated level, never an invisible
			# resource grant attached to choosing the menu option.
			return {
				"pattern": "risk_reward", "prompt": "The vein forks — deep and rich, or shallow and lean.",
				"options": [
					_opt("deep", "Work the deep vein", "Harder fighting and water, far more to forage.",
						"high", _settings(seed, depth, "deep", hard_tier, roster,
							{"node_count": [8, 10], "optional_node_count": 4,
							"flora_slots": [4, 6], "resource_beats": 2}), {}),
					_opt("shallow", "Take the shallow cut", "Easier going, leaner pickings.",
						"low", _settings(seed, depth, "shallow", base_tier, roster, {"node_count": [5, 6]}), {}),
				]}

static func _opt(id: String, label: String, desc: String, risk: String, settings: Dictionary, reward: Dictionary) -> Dictionary:
	return {"id": id, "label": label, "desc": desc, "risk": risk, "settings": settings, "reward": reward}

## Generation settings for one branch child — a child seed hashed from the branch so it's reproducible + distinct.
static func _settings(seed: int, depth: int, branch_id: String, tier: String, roster: Array, budget: Dictionary = {}) -> Dictionary:
	var biome := BiomesScript.for_key("%d:%d:%s" % [seed, depth, branch_id])
	var s := {
		"seed": int(hash("level:%d:%d:%s" % [seed, depth, branch_id])),
		"complexity_tier": tier,
		"roster": roster.duplicate(),
		"biome": biome,
		"id": "roguelike_d%d_%s" % [depth, branch_id],
		"title": "%s — Depth %d" % [BiomesScript.display_name(biome), depth + 1],
	}
	if not budget.is_empty():
		s["budget"] = budget
	return s

static func _hash_index(key: String, n: int) -> int:
	if n <= 0:
		return 0
	return abs(int(hash(key))) % n
