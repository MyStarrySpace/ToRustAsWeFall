class_name BranchPoint
extends RefCounted

## A fork in the run, built as GENERATOR structure: a branch point carries ARMS, an arm carries ordered
## SOCKETS, and fragments are filled into those sockets afterwards. Branching is not something a
## fragment does to itself — a room is one playable unit, and the choice between rooms belongs here.
##
## THE LAW THIS OWNS (director, 2026-08-10; .claude/rules/design-laws.md):
##   - A fragment is `clean` (beatable with no damage by perfect play) or `damaging` (a priced toll).
##   - A DAMAGING fragment may only be socketed onto a DAMAGING arm. It is legal content; it is not
##     legal on the safe way through.
##   - EVERY branch point offers at least one SAFE arm, and every socket on it takes clean fragments
##     only. A fork with no safe arm has stranded the run.
##   - A damaging arm's TOTAL damage is capped by difficulty, and on the hardest tier the GAINS are
##     capped rather than the losses raised.
##
## `fill()` fails CLOSED: if the roster cannot satisfy the invariants it returns the reason rather
## than a branch point that quietly breaks one, because a generator that ships a stranded fork has
## produced a run nobody can finish.

const SAFE := "safe"
const DAMAGING := "damaging"

## HP a single damaging arm may charge in total, per difficulty tier. The cap is the whole point of
## the tier: a harder run does not get to charge more blood, it gets to hand back less.
const ARM_HP_CAP := {
	"teaching": 25.0,
	"standard": 50.0,
	"hard": 75.0,
	"setpiece": 75.0,
}

## What a tier keeps of a damaging arm's advertised reward. Hard caps the GAINS instead of raising
## the losses, which is what keeps a difficulty tier from becoming a damage slider.
const ARM_GAIN_CAP := {
	"teaching": 1.0,
	"standard": 1.0,
	"hard": 0.6,
	"setpiece": 0.6,
}


static func hp_cap_for(tier: String) -> float:
	return float(ARM_HP_CAP.get(tier, ARM_HP_CAP["standard"]))


static func gain_cap_for(tier: String) -> float:
	return float(ARM_GAIN_CAP.get(tier, ARM_GAIN_CAP["standard"]))


## Lay out a fork: one safe arm plus `damaging_arms` priced arms, each with `sockets_per_arm` empty
## sockets. The sockets are what fragments are filled into; nothing about which fragments exist is
## decided here, so a layout can be built before a roster is known.
static func build(params: Dictionary = {}) -> Dictionary:
	var tier := str(params.get("tier", "standard"))
	var sockets_per_arm := maxi(1, int(params.get("sockets_per_arm", 2)))
	var damaging_arms := maxi(1, int(params.get("damaging_arms", 1)))
	var arms: Array = []
	# The safe arm is built FIRST and always: the invariant is structural, not something a later
	# step is trusted to remember.
	arms.append(_arm("safe_0", SAFE, sockets_per_arm + 1, 0.0))
	for i in range(damaging_arms):
		arms.append(_arm("damaging_%d" % i, DAMAGING, sockets_per_arm, hp_cap_for(tier)))
	return {
		"contract": "branch_point/v1",
		"tier": tier,
		"arms": arms,
		"hp_cap": hp_cap_for(tier),
		"gain_cap": gain_cap_for(tier),
	}


## The safe arm carries one MORE socket than a priced one: taking the clean way is longer, and that
## length is the whole of what it costs.
static func _arm(arm_id: String, arm_class: String, socket_count: int,
		hp_cap: float) -> Dictionary:
	var sockets: Array = []
	for i in range(socket_count):
		sockets.append({
			"index": i,
			"accepts": ["clean"] if arm_class == SAFE else ["clean", "damaging"],
			"fragment": "",
		})
	return {
		"id": arm_id,
		"class": arm_class,
		"sockets": sockets,
		"hp_cap": hp_cap,
		"hp_cost": 0.0,
	}


## Fill every socket from a roster of `{id, route_class, hp_cost, reward}` entries. Deterministic:
## the same roster and seed fill the same way, so a branch point is replay-safe like everything else
## the generator emits.
##
## Returns `{ok, reason, branch_point}`. A refusal names the invariant it could not meet.
static func fill(branch_point: Dictionary, roster: Array, seed_value := 1) -> Dictionary:
	var filled := branch_point.duplicate(true)
	var clean_pool: Array = []
	var damaging_pool: Array = []
	for entry_value in roster:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		match str(entry.get("route_class", "")):
			"clean": clean_pool.append(entry)
			"damaging": damaging_pool.append(entry)
	clean_pool.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	damaging_pool.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	if clean_pool.is_empty():
		return _refuse(filled, "no_clean_fragment_for_the_safe_arm")

	var rng := SeededRng.new(seed_value)
	for arm_value in (filled["arms"] as Array):
		var arm: Dictionary = arm_value
		var is_safe := str(arm.get("class", "")) == SAFE
		var spent := 0.0
		for socket_value in (arm["sockets"] as Array):
			var socket: Dictionary = socket_value
			var pick := {}
			if is_safe:
				pick = clean_pool[rng.pick_index(clean_pool.size())]
			else:
				# A priced socket takes a toll only while the arm can still afford one under its cap;
				# past that it takes a clean fragment, so an arm never charges more than its tier
				# allows however many sockets it happens to carry.
				var affordable: Array = []
				for candidate_value in damaging_pool:
					var candidate: Dictionary = candidate_value
					if spent + float(candidate.get("hp_cost", 0.0)) \
							<= float(arm.get("hp_cap", 0.0)):
						affordable.append(candidate)
				if affordable.is_empty():
					pick = clean_pool[rng.pick_index(clean_pool.size())]
				else:
					pick = affordable[rng.pick_index(affordable.size())]
			socket["fragment"] = str(pick.get("id", ""))
			socket["route_class"] = str(pick.get("route_class", "clean"))
			socket["hp_cost"] = float(pick.get("hp_cost", 0.0))
			spent += float(pick.get("hp_cost", 0.0))
		arm["hp_cost"] = spent
		# The tier caps what a priced arm hands BACK, never what it takes.
		arm["reward_scale"] = float(filled.get("gain_cap", 1.0)) if not is_safe else 1.0
	var verdict := validate(filled)
	if not bool(verdict.get("ok", false)):
		return _refuse(filled, str(verdict.get("reason", "invalid")))
	return {"ok": true, "reason": "", "branch_point": filled}


static func _refuse(branch_point: Dictionary, reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "branch_point": branch_point}


## Every invariant the law states, checked against a filled branch point. The generator calls this
## before it ships one; a test calls it to prove the generator cannot ship a broken fork.
static func validate(branch_point: Dictionary) -> Dictionary:
	var arms: Array = branch_point.get("arms", []) as Array
	if arms.is_empty():
		return {"ok": false, "reason": "branch_point_has_no_arms"}
	var safe_arms := 0
	for arm_value in arms:
		var arm: Dictionary = arm_value
		var is_safe := str(arm.get("class", "")) == SAFE
		var total := 0.0
		for socket_value in (arm.get("sockets", []) as Array):
			var socket: Dictionary = socket_value
			var socket_class := str(socket.get("route_class", ""))
			if str(socket.get("fragment", "")) == "":
				return {"ok": false, "reason": "socket_left_empty:%s" % str(arm.get("id", ""))}
			if is_safe and socket_class != "clean":
				return {"ok": false,
					"reason": "damaging_fragment_on_safe_arm:%s" % str(socket.get("fragment", ""))}
			total += float(socket.get("hp_cost", 0.0))
		if is_safe:
			safe_arms += 1
			if total > 0.0:
				return {"ok": false,
					"reason": "safe_arm_charges_hp:%s" % str(arm.get("id", ""))}
		elif total > float(arm.get("hp_cap", 0.0)) + 0.001:
			return {"ok": false, "reason": "damaging_arm_over_cap:%s (%.1f > %.1f)" % [
				str(arm.get("id", "")), total, float(arm.get("hp_cap", 0.0))]}
	if safe_arms < 1:
		return {"ok": false, "reason": "no_safe_arm"}
	return {"ok": true, "reason": ""}


## What the player is told at the mouth of each arm, so the choice is made on the same arithmetic the
## world will charge. Reward is already scaled by the tier's gain cap.
static func advertise(branch_point: Dictionary) -> Array:
	var quoted: Array = []
	for arm_value in (branch_point.get("arms", []) as Array):
		var arm: Dictionary = arm_value
		quoted.append({
			"id": str(arm.get("id", "")),
			"class": str(arm.get("class", "")),
			"hp_cost": float(arm.get("hp_cost", 0.0)),
			"reward_scale": float(arm.get("reward_scale", 1.0)),
			"sockets": (arm.get("sockets", []) as Array).size(),
		})
	return quoted
