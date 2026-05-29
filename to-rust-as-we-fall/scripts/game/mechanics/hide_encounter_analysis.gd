class_name HideEncounterAnalysis
extends RefCounted

const SimRef = preload("res://scripts/game/mechanics/hide_encounter_sim.gd")
const SWARM_OFFSETS := [-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4]

var base_config: Dictionary = {}

func _init(overrides: Dictionary = {}) -> void:
	base_config = overrides.duplicate(true)

func build_bundle(overrides: Dictionary = {}) -> Dictionary:
	var solver = SimRef.new(base_config)
	var search_overrides: Dictionary = overrides.get("search", {}).duplicate(true)
	var search_config: Dictionary = base_config.duplicate(true)
	search_config.merge(search_overrides.get("config", {}), true)
	search_overrides["config"] = search_config
	var solved: Dictionary = solver.search_solution(search_overrides)
	if solved.is_empty():
		return {}
	var tuned_config: Dictionary = solved["config"].duplicate(true)
	var bifurcation := build_stamina_bifurcation(tuned_config, overrides.get("bifurcation", {}))
	return {
		"methodology_version": "hide-encounter-v5",
		"tuned_config": tuned_config,
		"search": {
			"score": solved.get("score", 0.0),
			"first_success_stamina": solved.get("first_success_stamina", bifurcation.get("first_success_stamina", -1.0)),
			"objective": solved.get("search_objective", {}),
			"parameter_space": solved.get("search_space", {}),
			"success": solved["success"],
			"slow_retreat": solved["slow_retreat"],
			"slow_lure2_activation": solved["slow_lure2_activation"],
			"no_lure2": solved["no_lure2"],
			"slow_exit": solved["slow_exit"],
		},
		"phase_plane": build_phase_plane(tuned_config, bifurcation, overrides.get("phase_plane", {})),
		"stamina_bifurcation": bifurcation,
		"monte_carlo": run_monte_carlo(tuned_config, bifurcation, overrides.get("monte_carlo", {})),
	}

func build_phase_plane(tuned_config: Dictionary, bifurcation: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var phase_sim = SimRef.new(tuned_config)
	var threshold: float = bifurcation.get("first_success_stamina", tuned_config.get("stamina_max", 100.0))
	var samples: Array = overrides.get("stamina_samples", [
		maxf(0.0, threshold - 15.0),
		maxf(0.0, threshold - 5.0),
		threshold,
		minf(tuned_config["stamina_max"], threshold + 10.0),
		tuned_config["stamina_max"],
	])
	var traces: Array[Dictionary] = []
	for stamina in samples:
		var sim = SimRef.new(tuned_config)
		var result: Dictionary = sim.run_scenario("success", {
			"peris_stamina": float(stamina),
			"record_trace": true,
		})
		traces.append(_trace_payload("success", float(stamina), result))
	for scenario in ["slow_retreat", "slow_lure2_activation", "slow_exit"]:
		var sim = SimRef.new(tuned_config)
		var result: Dictionary = sim.run_scenario(scenario, {
			"peris_stamina": tuned_config["stamina_max"],
			"record_trace": true,
		})
		traces.append(_trace_payload(scenario, tuned_config["stamina_max"], result))

	var boundary: Array[Dictionary] = []
	var max_stamina: float = tuned_config["stamina_max"]
	var slope: float = tuned_config["run_speed"] / tuned_config["run_drain"]
	for i in range(0, 41):
		var stamina := max_stamina * float(i) / 40.0
		boundary.append({
			"stamina": stamina,
			"distance": slope * stamina,
		})

	return {
		"axes": {
			"x": "distance_remaining",
			"y": "stamina",
		},
		"switch_manifold": {
			"name": "run_finish_boundary",
			"description": "Below this line a full run can finish the remaining leg before stamina hits zero.",
			"points": boundary,
		},
		"vector_field": [
			{
				"mode": "run",
				"d_stamina_dt": -tuned_config["run_drain"],
				"d_distance_dt": -tuned_config["run_speed"],
			},
			{
				"mode": "walk",
				"d_stamina_dt": tuned_config["walk_regen"],
				"d_distance_dt": -tuned_config["walk_speed"],
			},
			{
				"mode": "hold",
				"d_stamina_dt": phase_sim.hold_regen_rate(),
				"d_distance_dt": 0.0,
			},
			{
				"mode": "hide",
				"d_stamina_dt": phase_sim.hide_regen_rate(),
				"d_distance_dt": 0.0,
			},
			{
				"mode": "stand",
				"d_stamina_dt": tuned_config["stand_regen"],
				"d_distance_dt": 0.0,
			},
		],
		"discrete_events": [
			{
				"name": "consume_plant",
				"applies_per_hold": true,
				"delta_stamina": -phase_sim.consume_stamina_cost(),
			},
		],
		"traces": traces,
	}

func build_stamina_bifurcation(tuned_config: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var min_stamina: float = overrides.get("min_stamina", 0.0)
	var max_stamina: float = overrides.get("max_stamina", tuned_config["stamina_max"])
	var step: float = overrides.get("step", 2.5)
	var samples: Array[Dictionary] = []
	var first_success := -1.0
	var stamina := min_stamina
	while stamina <= max_stamina + 0.001:
		var sim = SimRef.new(tuned_config)
		var actual: Dictionary = sim.run_scenario("success", {"peris_stamina": stamina})
		var closed_form := _closed_form_prediction(tuned_config, stamina)
		var sample := {
			"initial_stamina": stamina,
			"actual_success": actual["success"],
			"actual_failure_reason": actual["failure_reason"],
			"actual_exit_margin": actual.get("exit_margin", null),
			"actual_lure1_margin": actual.get("lure1_margin", null),
			"closed_form_success": closed_form["predicted_success"],
			"closed_form_exit_margin": closed_form["predicted_exit_margin"],
			"closed_form_lure1_margin": closed_form["predicted_lure1_margin"],
			"closed_form_exit_start_tick": closed_form["predicted_exit_start_tick"],
		}
		samples.append(sample)
		if first_success < 0.0 and actual["success"]:
			first_success = stamina
		stamina += step
	return {
		"parameter": "initial_stamina",
		"step": step,
		"first_success_stamina": first_success,
		"samples": samples,
	}

func run_monte_carlo(tuned_config: Dictionary, bifurcation: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	var trials: int = overrides.get("trials", 256)
	var seed: int = overrides.get("seed", 1337)
	var sample_limit: int = overrides.get("sample_limit", 32)
	var threshold: float = bifurcation.get("first_success_stamina", tuned_config["stamina_max"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var counts := {
		"success": 0,
	}
	var failure_counts := {}
	var confusion := {
		"true_positive": 0,
		"false_positive": 0,
		"true_negative": 0,
		"false_negative": 0,
	}
	var samples: Array[Dictionary] = []
	for i in range(trials):
		var trial := {
			"peris_stamina": clampf(rng.randf_range(maxf(0.0, threshold - 20.0), tuned_config["stamina_max"]), 0.0, tuned_config["stamina_max"]),
			"retreat_hesitation": rng.randf_range(0.0, 2.0),
			"lure2_activation_delay": rng.randf_range(0.0, 1.0),
			"exit_release_delay": rng.randf_range(0.0, 1.0),
			"exit_stamina_cap": rng.randf_range(maxf(20.0, threshold - 10.0), tuned_config["stamina_max"]),
			"siderophore_speed": tuned_config["siderophore_speed"] * rng.randf_range(0.97, 1.03),
		}
		var sim_config := tuned_config.duplicate(true)
		sim_config["siderophore_speed"] = trial["siderophore_speed"]
		var sim = SimRef.new(sim_config)
		var actual: Dictionary = sim.run_scenario("success", trial)
		var closed_form := _closed_form_prediction(sim_config, trial["peris_stamina"], trial)
		if actual["success"]:
			counts["success"] += 1
		else:
			var reason: String = actual["failure_reason"]
			failure_counts[reason] = int(failure_counts.get(reason, 0)) + 1
		if closed_form["predicted_success"] and actual["success"]:
			confusion["true_positive"] += 1
		elif closed_form["predicted_success"] and not actual["success"]:
			confusion["false_positive"] += 1
		elif not closed_form["predicted_success"] and actual["success"]:
			confusion["false_negative"] += 1
		else:
			confusion["true_negative"] += 1
		if samples.size() < sample_limit:
			samples.append({
				"trial": i,
				"inputs": trial,
				"actual_success": actual["success"],
				"actual_failure_reason": actual["failure_reason"],
				"closed_form_success": closed_form["predicted_success"],
				"closed_form_exit_margin": closed_form["predicted_exit_margin"],
				"closed_form_lure1_margin": closed_form["predicted_lure1_margin"],
			})
	return {
		"seed": seed,
		"trials": trials,
		"success_rate": float(counts["success"]) / maxf(1.0, float(trials)),
		"failure_counts": failure_counts,
		"confusion_matrix": confusion,
		"sample_trials": samples,
	}

func _trace_payload(scenario: String, initial_stamina: float, result: Dictionary) -> Dictionary:
	var retreat_trace: Array[Dictionary] = []
	var exit_trace: Array[Dictionary] = []
	for point in result.get("trace", []):
		retreat_trace.append({
			"tick": point["tick"],
			"distance_remaining": point["retreat_distance_remaining"],
			"stamina": point["stamina"],
			"mode": point["phase_mode"],
			"active_lure": point["active_lure"],
		})
		exit_trace.append({
			"tick": point["tick"],
			"distance_remaining": point["exit_distance_remaining"],
			"stamina": point["stamina"],
			"mode": point["phase_mode"],
			"active_lure": point["active_lure"],
		})
	return {
		"scenario": scenario,
		"initial_stamina": initial_stamina,
		"success": result["success"],
		"failure_reason": result["failure_reason"],
		"retreat_trace": retreat_trace,
		"exit_trace": exit_trace,
	}

func _closed_form_prediction(tuned_config: Dictionary, initial_stamina: float, policy_overrides: Dictionary = {}) -> Dictionary:
	var sim = SimRef.new(tuned_config)
	var policy: Dictionary = sim.build_policy_overrides("success", policy_overrides)
	policy["initial_stamina"] = initial_stamina
	var max_stamina: float = tuned_config["stamina_max"]
	var hide_regen: float = sim.hide_regen_rate()
	var stand_regen: float = tuned_config["stand_regen"]
	var post_lure1_hold: float = sim.stamina_after_hold(initial_stamina)
	var retreat: Dictionary = sim.travel_profile(tuned_config["lure_distance"], post_lure1_hold)
	var lure2_activation_tick: float = tuned_config["hold_duration"] + policy["retreat_hesitation"] + retreat["time"] + policy["lure2_activation_delay"] + tuned_config["hold_duration"]
	var lure1_expire_tick: float = tuned_config["hold_duration"] + tuned_config["lure1_duration"]
	var post_lure2_hold: float = sim.stamina_after_hold(retreat["end_stamina"])
	var hide_walk: Dictionary = sim.travel_profile(tuned_config["hide_distance"], post_lure2_hold)
	var hide_arrive_tick: float = lure2_activation_tick + hide_walk["time"]
	var clearance_distance: float = tuned_config["lure_distance"] + SWARM_OFFSETS[SWARM_OFFSETS.size() - 1] - (tuned_config["hide_distance"] - tuned_config["fixated_radius"])
	var clearance_tick: float = lure1_expire_tick + maxf(0.0, clearance_distance) / tuned_config["siderophore_speed"]
	var exit_window_tick: float = maxf(hide_arrive_tick, clearance_tick)
	var hidden_wait: float = maxf(0.0, exit_window_tick - hide_arrive_tick)
	var exit_ready_stamina: float = minf(max_stamina, hide_walk["end_stamina"] + hidden_wait * hide_regen)
	if float(policy["exit_stamina_cap"]) < max_stamina:
		exit_ready_stamina = minf(exit_ready_stamina, float(policy["exit_stamina_cap"]))
	var exit_start_tick: float = exit_window_tick + policy["exit_release_delay"]
	var exit_start_stamina: float = minf(max_stamina, exit_ready_stamina + policy["exit_release_delay"] * stand_regen)
	var exit_leg: Dictionary = sim.travel_profile(tuned_config["cluster_gap"] + tuned_config["exit_gap"], exit_start_stamina)
	var lure2_expire_tick: float = lure2_activation_tick + tuned_config["lure2_duration"]
	var lure1_margin: float = lure1_expire_tick - lure2_activation_tick
	var exit_margin: float = lure2_expire_tick - (exit_start_tick + exit_leg["time"])
	return {
		"predicted_success": not policy["skip_lure2"] and lure1_margin > 0.0 and exit_margin > 0.0,
		"predicted_lure1_margin": lure1_margin,
		"predicted_exit_margin": exit_margin,
		"predicted_exit_start_tick": exit_start_tick,
		"predicted_exit_start_stamina": exit_start_stamina,
		"predicted_post_lure1_hold_stamina": post_lure1_hold,
		"predicted_post_lure2_hold_stamina": post_lure2_hold,
		"predicted_lure2_activation_tick": lure2_activation_tick,
	}
