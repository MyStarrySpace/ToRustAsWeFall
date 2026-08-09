class_name RiskLane
extends RefCounted

## A route priced in HP. The open-world run offers several ways to reach the same place; a lane is one
## of them, and its fee is ARITHMETIC rather than luck. The worked shape is the long hall: cover only at
## the far end, length set just past full-stamina sprint range, so the party runs out, drops to walking
## pace, the pursuit closes, and a fixed number of charges land before the hide.
##
## Nothing here is a new mechanic. Stamina drain, the walk/run speeds, pursuit speed, and the enemy
## attack cycle are all shipped; this model only reads them forward to say what a given geometry costs,
## and inverts them to say what geometry buys a given cost. Stamina is the MECHANISM, HP is the PRICE.

const GameStateScript := preload("res://scripts/system/core/game_state.gd")
const EnemyScript := preload("res://scripts/game/ai/enemy.gd")

## The lane profile a generated route offers. Values are seconds, world units, and HP.
const DEFAULT_PROFILE := {
	"stamina": 100.0,
	"stamina_drain_per_sec": 15.0,
	"sprint_speed": 6.0,
	"walk_speed": 3.0,
	# A chaser only a little slower than a sprint. The margin the sprint buys is what the walk has to
	# give back, so a near-matched pursuer makes the collapse arrive right after the legs go rather
	# than a dead half-minute later.
	"pursuit_speed": 5.5,
	"pursuit_lead": 6.0,
	"attack_range": 3.0,
	# The spotting beat. The chaser stands still through it while the runner is already sprinting, so
	# it is pure head start and the widest the gap ever gets depends on it.
	"alert_duration": 0.6,
	"windup_duration": 0.8,
	"charge_speed": 8.0,
	"lunge_gap": 0.6,
	"impact_duration": 0.14,
	"recover_duration": 1.2,
	"charge_damage": 25.0,
	"charge_max_duration": 1.5,
	# Where inside its price band a tuned lane sits, as a fraction of one strike cycle. A connection
	# costs the runner TIME as well as HP -- the charge shoulders through the path and the walk stalls
	# -- so cover has to be close behind the hit that was paid for. Sitting mid-band leaves room for
	# the stall to earn the chaser a second connection the lane never advertised.
	"strike_band_position": 0.25,
}


## The profile a live scene actually runs, read off the shipped GameState constants and an enemy
## instance, so a lane priced on paper and a lane played in the world cannot drift apart.
static func profile_from_world(game_state: Object, enemy: Object,
		party_ids: Array = []) -> Dictionary:
	var profile := DEFAULT_PROFILE.duplicate()
	if game_state != null:
		profile["sprint_speed"] = float(GameStateScript.RUN_SPEED)
		profile["walk_speed"] = float(GameStateScript.WALK_SPEED)
		# A party walks at the pace of whoever is slowest, and the chaser reaches that member first,
		# so the slowest registered pace is the one the fee has to be computed from. Members carry
		# their own speeds, which is why the shipped constant alone is not enough.
		var slowest := INF
		for member_id in party_ids:
			if game_state.characters.has(str(member_id)):
				slowest = minf(slowest, float(
					game_state.characters[str(member_id)].get("move_speed", INF)))
		if slowest < INF and slowest > 0.0:
			profile["walk_speed"] = slowest
		if "run_stamina_drain_per_sec" in game_state:
			profile["stamina_drain_per_sec"] = float(
				game_state.get("run_stamina_drain_per_sec"))
	if enemy != null:
		var pursuit := float(enemy.get("pursuit_speed"))
		profile["pursuit_speed"] = pursuit if pursuit > 0.0 \
			else float(enemy.get("move_speed"))
		for key in ["attack_range", "windup_duration", "charge_speed", "lunge_gap",
				"impact_duration", "recover_duration", "charge_damage"]:
			profile[key] = float(enemy.get(key))
	return profile


## The widest the gap ever gets: the opening lead, plus everything the runner gains while the chaser
## is still spotting it, plus what the rest of the sprint adds. Everything after this point is the
## walk giving it back.
static func peak_gap(profile: Dictionary, sprint_seconds: float) -> float:
	var sprint_speed := maxf(0.001, float(profile.get("sprint_speed", 6.0)))
	var pursuit_speed := maxf(0.0, float(profile.get("pursuit_speed", 5.5)))
	var alert := clampf(float(profile.get("alert_duration", 0.6)), 0.0, sprint_seconds)
	return float(profile.get("pursuit_lead", 6.0)) \
		+ sprint_speed * alert \
		+ (sprint_speed - pursuit_speed) * (sprint_seconds - alert)


## How long one charge takes from entering reach to connecting. The runner does not stand still for
## it: it keeps walking through the telegraph and through the lunge, so the chaser has to cover the
## reach it started at PLUS everything gained in between, and the strike takes materially longer than
## the telegraph and lunge alone suggest.
static func first_strike_seconds(profile: Dictionary) -> float:
	var walk_speed := maxf(0.0, float(profile.get("walk_speed", 3.0)))
	var charge_speed := maxf(0.001, float(profile.get("charge_speed", 8.0)))
	var windup := float(profile.get("windup_duration", 0.8))
	var gap_at_lunge := float(profile.get("attack_range", 3.0)) + walk_speed * windup
	var closing := maxf(0.001, charge_speed - walk_speed)
	var lunge := maxf(0.0, gap_at_lunge - float(profile.get("lunge_gap", 0.6))) / closing
	return windup + minf(lunge, float(profile.get("charge_max_duration", 1.5)))


## The gap between one connection and the next: hitstop, cooldown, then another full telegraph+lunge.
static func strike_cycle_seconds(profile: Dictionary) -> float:
	return float(profile.get("impact_duration", 0.14)) \
		+ float(profile.get("recover_duration", 1.2)) \
		+ first_strike_seconds(profile)


## Price a lane of a given length. Returns the whole derivation, not just the number, so a level can
## show its work and a test can assert on the step that broke rather than on the total alone.
static func price(lane_length: float, profile_override: Dictionary = {}) -> Dictionary:
	var profile := DEFAULT_PROFILE.duplicate()
	for key in profile_override.keys():
		profile[str(key)] = profile_override[key]

	var sprint_speed := maxf(0.001, float(profile.get("sprint_speed", 6.0)))
	var walk_speed := maxf(0.001, float(profile.get("walk_speed", 3.0)))
	var pursuit_speed := maxf(0.0, float(profile.get("pursuit_speed", 5.5)))
	var drain := maxf(0.001, float(profile.get("stamina_drain_per_sec", 15.0)))

	var sprint_seconds := maxf(0.0, float(profile.get("stamina", 100.0))) / drain
	var sprint_distance := sprint_speed * sprint_seconds
	var result := {
		"lane_length": lane_length,
		"sprint_seconds": sprint_seconds,
		"sprint_distance": sprint_distance,
		"walk_distance": 0.0,
		"walk_seconds": 0.0,
		"gap_at_exhaustion": 0.0,
		"seconds_within_reach": 0.0,
		"strikes": 0,
		"hp_cost": 0.0,
		"profile": profile,
		"free_reason": "",
	}

	if sprint_distance >= lane_length:
		result["free_reason"] = "sprint_covers_lane"
		return result
	# A pursuer no faster than a walk can never close the gap once the sprint ends, so the lane has no
	# fee no matter how long it is; that is a lane authored wrong, not a bargain.
	if pursuit_speed <= walk_speed:
		result["free_reason"] = "pursuit_no_faster_than_walk"
		return result

	var walk_distance := lane_length - sprint_distance
	var walk_seconds := walk_distance / walk_speed
	result["walk_distance"] = walk_distance
	result["walk_seconds"] = walk_seconds

	var gap := peak_gap(profile, sprint_seconds)
	result["gap_at_exhaustion"] = gap
	# The sight the chaser needs to still be on the runner when the legs give out. Reported on every
	# priced lane, not only on the one that fails for want of it, because it is what a level has to
	# configure its chaser with.
	result["required_detection_range"] = gap

	# Sight is a property of the chaser a level configures, not something a lane carries by default:
	# the model REPORTS what the lane demands, and only calls a lane free when a caller has supplied a
	# real chaser whose sight falls short of it.
	if profile.has("detection_range") and float(profile["detection_range"]) < gap:
		result["free_reason"] = "chaser_loses_runner_at_max_gap"
		return result

	var attack_range := float(profile.get("attack_range", 3.0))
	if gap <= attack_range:
		# Already inside reach when the legs give out: the whole walk is exposed.
		result["seconds_within_reach"] = walk_seconds
	else:
		var close_seconds := (gap - attack_range) / (pursuit_speed - walk_speed)
		result["seconds_within_reach"] = maxf(0.0, walk_seconds - close_seconds)

	var exposed := float(result["seconds_within_reach"])
	var first := first_strike_seconds(profile)
	if exposed < first:
		result["free_reason"] = "hide_reached_before_first_connection"
		return result
	var strikes := 1 + int(floorf((exposed - first) \
		/ maxf(0.001, strike_cycle_seconds(profile))))
	result["strikes"] = strikes
	result["hp_cost"] = float(strikes) * float(profile.get("charge_damage", 25.0))
	return result


## The inverse: the shortest lane whose fee is exactly `target_strikes` connections. A generated route
## states the price it wants to charge and gets the geometry that charges it, which is what keeps the
## advertised cost and the played cost the same number.
static func length_for_strikes(target_strikes: int,
		profile_override: Dictionary = {}) -> Dictionary:
	var profile := DEFAULT_PROFILE.duplicate()
	for key in profile_override.keys():
		profile[str(key)] = profile_override[key]
	if target_strikes <= 0:
		var sprint_only := maxf(0.001, float(profile.get("sprint_speed", 6.0))) \
			* maxf(0.0, float(profile.get("stamina", 100.0))) \
			/ maxf(0.001, float(profile.get("stamina_drain_per_sec", 15.0)))
		return {"lane_length": sprint_only, "profile": profile, "solved": true}

	var sprint_speed := maxf(0.001, float(profile.get("sprint_speed", 6.0)))
	var walk_speed := maxf(0.001, float(profile.get("walk_speed", 3.0)))
	var pursuit_speed := maxf(0.0, float(profile.get("pursuit_speed", 5.5)))
	if pursuit_speed <= walk_speed:
		return {"lane_length": 0.0, "profile": profile, "solved": false,
			"reason": "pursuit_no_faster_than_walk"}

	var sprint_seconds := maxf(0.0, float(profile.get("stamina", 100.0))) \
		/ maxf(0.001, float(profile.get("stamina_drain_per_sec", 15.0)))
	var sprint_distance := sprint_speed * sprint_seconds
	var attack_range := float(profile.get("attack_range", 3.0))
	var gap := peak_gap(profile, sprint_seconds)
	var close_seconds := maxf(0.0, (gap - attack_range) / (pursuit_speed - walk_speed))

	# Exposure that buys exactly N connections spans a band one strike cycle wide. The lane is authored
	# at the MIDDLE of that band, not its low edge: an edge lane is advertised at one price and charges
	# another the moment live pacing differs from the model by a fraction of a second, and a fee that
	# moves is not a fee the player can decide against.
	var cycle := strike_cycle_seconds(profile)
	var exposed_low := first_strike_seconds(profile) + float(target_strikes - 1) * cycle
	var band_position := clampf(
		float(profile.get("strike_band_position", 0.25)), 0.05, 0.95)
	var exposed := exposed_low + cycle * band_position
	var walk_seconds := exposed + close_seconds
	return {
		"lane_length": sprint_distance + walk_seconds * walk_speed,
		# The sight a chaser needs to still be on the runner when the legs give out. A lane authored
		# with less than this is free no matter how long it is.
		"required_detection_range": gap,
		"band_low_length": sprint_distance + (exposed_low + close_seconds) * walk_speed,
		"band_high_length": sprint_distance + (exposed_low + cycle + close_seconds) * walk_speed,
		"margin_seconds": cycle * minf(band_position, 1.0 - band_position),
		"exposure_seconds": exposed,
		"close_seconds": close_seconds,
		"profile": profile,
		"solved": true,
	}


## Whether a party can pay for a route: every lane on it, in order, against the HP each member carries.
## Reachability is proven elsewhere (the greedy flood-open validator); this asks the separate question
## of whether the route is SURVIVABLE, which is what a run priced in HP actually turns on.
##
## `lanes` is an ordered array of either lane lengths (float) or priced dictionaries.
## `party_hp` maps member id to current HP. `reserve` is the HP a route must leave standing.
static func route_affordability(lanes: Array, party_hp: Dictionary,
		reserve: float = 1.0, profile_override: Dictionary = {}) -> Dictionary:
	var total := 0.0
	var priced: Array = []
	for lane_value in lanes:
		var lane: Dictionary = lane_value if lane_value is Dictionary \
			else price(float(lane_value), profile_override)
		priced.append(lane)
		total += float(lane.get("hp_cost", 0.0))

	var survivors: Array[String] = []
	var casualties: Array[String] = []
	var member_ids: Array[String] = []
	for member_id in party_hp.keys():
		member_ids.append(str(member_id))
	member_ids.sort()
	for member_id in member_ids:
		if float(party_hp[member_id]) - total >= reserve:
			survivors.append(member_id)
		else:
			casualties.append(member_id)
	return {
		"hp_cost": total,
		"lanes": priced,
		"affordable": casualties.is_empty() and not member_ids.is_empty(),
		"survivors": survivors,
		"casualties": casualties,
		"reserve": reserve,
	}


## A fork is only a real decision if the player can actually take one of its arms. Given the priced
## routes out of a place, report which are payable and fail the fork when none of them are: an
## open world that prices every exit above the party's remaining HP has stranded the run.
static func fork_viability(routes: Array, party_hp: Dictionary,
		reserve: float = 1.0, profile_override: Dictionary = {}) -> Dictionary:
	var evaluated: Array = []
	var payable: Array[String] = []
	var cheapest_id := ""
	var cheapest_cost := INF
	for route_value in routes:
		if not (route_value is Dictionary):
			continue
		var route := route_value as Dictionary
		var route_id := str(route.get("id", ""))
		var report := route_affordability(route.get("lanes", []) as Array,
			party_hp, reserve, profile_override)
		report["id"] = route_id
		evaluated.append(report)
		if bool(report.get("affordable", false)):
			payable.append(route_id)
		var route_cost := float(report.get("hp_cost", 0.0))
		# Ties break on the id rather than on the order the fork happened to list its arms, so the
		# cheapest arm a run is told about is the same one on every replay of that seed.
		if route_cost < cheapest_cost \
				or (route_cost == cheapest_cost and route_id < cheapest_id):
			cheapest_cost = route_cost
			cheapest_id = route_id
	return {
		"routes": evaluated,
		"payable": payable,
		"viable": not payable.is_empty(),
		"cheapest_id": cheapest_id,
		"cheapest_cost": 0.0 if cheapest_cost == INF else cheapest_cost,
	}
