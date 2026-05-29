class_name HideEncounterSim
extends RefCounted

const ODESolverRef = preload("res://scripts/game/mechanics/ode_solver.gd")

const DEFAULTS := {
	"stamina_max": 100.0,
	"run_speed": 6.0,
	"walk_speed": 3.0,
	"run_drain": 30.0,
	"walk_regen": 3.0,
	"stand_regen": 15.0,
	"consume_stamina_cost": 0.0,
	"hold_duration": 2.0,
	"lure1_duration": 12.0,
	"lure2_duration": 18.0,
	"siderophore_speed": 1.5,
	"unaware_radius": 5.0,
	"fixated_radius": 5.0 * (14.0 / 32.0),
	"lure_distance": 16.0,
	"hide_distance": 6.0,
	"cluster_gap": 8.0,
	"exit_gap": 2.5,
	"max_tick": 60.0,
	"continuous_step": 0.05,
}

const SWARM_OFFSETS := [-2.4, -1.6, -0.8, 0.0, 0.8, 1.6, 2.4]

var config: Dictionary = {}
var scheduler: EventScheduler

var _last_sync_tick := 0.0
var _logs: Array[Dictionary] = []
var _result := {}
var _trace: Array[Dictionary] = []
var _record_trace := false
var _policy: Dictionary = {}

var _lure2_x := 0.0
var _hide_x := 0.0
var _lure1_x := 0.0
var _cluster_x := 0.0
var _exit_x := 0.0

var _peris := {}
var _party := {}
var _siderophores: Array[Dictionary] = []
var _lures := {}

func _init(overrides: Dictionary = {}) -> void:
	config = DEFAULTS.duplicate(true)
	config.merge(overrides, true)
	_setup_geometry()

func run_scenario(name: String, overrides: Dictionary = {}) -> Dictionary:
	_reset_state()
	_result["scenario"] = name
	_record_trace = overrides.get("record_trace", false)
	_policy = _build_policy(name, overrides)
	match name:
		"success":
			_schedule_success(overrides)
		"slow_retreat":
			_schedule_slow_retreat(overrides)
		"slow_lure2_activation":
			_schedule_slow_lure2_activation(overrides)
		"no_lure2":
			_schedule_no_lure2(overrides)
		"slow_exit":
			_schedule_slow_exit(overrides)
		_:
			_fail("unknown_scenario")
			return _finalize(name)
	if _record_trace:
		_record_trace_point(0.0)

	while not _is_finished() and scheduler.pending_count() > 0 and scheduler.get_current_tick() <= config["max_tick"]:
		var event := scheduler.pop_next()
		if event.is_empty():
			break

	if not _is_finished():
		_sync_to(minf(scheduler.get_current_tick(), config["max_tick"]))

	if not _is_finished():
		_fail("timeout")
	return _finalize(name)

func build_policy_overrides(name: String, overrides: Dictionary = {}) -> Dictionary:
	return _build_policy(name, overrides)

func hold_regen_rate(settings: Dictionary = config) -> float:
	return float(settings.get("hold_regen", settings.get("stand_regen", DEFAULTS["stand_regen"])))

func hide_regen_rate(settings: Dictionary = config) -> float:
	return float(settings.get("hide_regen", settings.get("stand_regen", DEFAULTS["stand_regen"])))

func consume_stamina_cost(settings: Dictionary = config) -> float:
	return float(settings.get("consume_stamina_cost", DEFAULTS["consume_stamina_cost"]))

func stamina_after_hold(initial_stamina: float) -> float:
	return clampf(
		initial_stamina + config["hold_duration"] * hold_regen_rate() - consume_stamina_cost(),
		0.0,
		config["stamina_max"]
	)

func travel_profile(distance: float, starting_stamina: float) -> Dictionary:
	var run_speed: float = config["run_speed"]
	var walk_speed: float = config["walk_speed"]
	var run_drain: float = config["run_drain"]
	var max_run_distance: float = run_speed * starting_stamina / run_drain
	var run_distance := minf(distance, max_run_distance)
	var run_time := run_distance / run_speed
	var walk_distance := maxf(0.0, distance - run_distance)
	var walk_time := walk_distance / walk_speed
	return {
		"time": run_time + walk_time,
		"run_time": run_time,
		"walk_time": walk_time,
		"run_distance": run_distance,
		"walk_distance": walk_distance,
		"end_stamina": maxf(0.0, starting_stamina - run_time * run_drain + walk_time * config["walk_regen"]),
		"run_only": walk_distance <= 0.001,
	}

func find_first_success_stamina(overrides: Dictionary = {}) -> float:
	var resolution: float = float(overrides.get("resolution", 2.5))
	var min_stamina: float = float(overrides.get("min_stamina", 0.0))
	var max_stamina: float = float(overrides.get("max_stamina", config["stamina_max"]))
	var scenario_overrides: Dictionary = overrides.get("scenario_overrides", {}).duplicate(true)
	var stamina_values: Array[float] = []
	var stamina := min_stamina
	while stamina < max_stamina - 0.001:
		stamina_values.append(stamina)
		stamina += resolution
	stamina_values.append(max_stamina)

	if stamina_values.is_empty():
		return -1.0

	var first_overrides := scenario_overrides.duplicate(true)
	first_overrides["peris_stamina"] = stamina_values[0]
	if run_scenario("success", first_overrides)["success"]:
		return stamina_values[0]

	var last_overrides := scenario_overrides.duplicate(true)
	last_overrides["peris_stamina"] = stamina_values[stamina_values.size() - 1]
	if not run_scenario("success", last_overrides)["success"]:
		return -1.0

	var low := 0
	var high := stamina_values.size() - 1
	while high - low > 1:
		var mid := int((low + high) / 2)
		var test_overrides := scenario_overrides.duplicate(true)
		test_overrides["peris_stamina"] = stamina_values[mid]
		if run_scenario("success", test_overrides)["success"]:
			high = mid
		else:
			low = mid
	return stamina_values[high]

func search_solution(overrides: Dictionary = {}) -> Dictionary:
	var best := {}
	var best_margin_score := -INF
	var best_threshold := -INF
	var best_target_distance := INF
	var search_config: Dictionary = overrides.get("config", {}).duplicate(true)
	var base_speed: float = float(search_config.get("siderophore_speed", config["siderophore_speed"]))
	var base_run_drain: float = float(search_config.get("run_drain", config["run_drain"]))
	var base_walk_regen: float = float(search_config.get("walk_regen", config["walk_regen"]))
	var base_stand_regen: float = float(search_config.get("stand_regen", config["stand_regen"]))
	var base_consume_stamina_cost: float = float(search_config.get("consume_stamina_cost", config["consume_stamina_cost"]))
	var base_hold_duration: float = float(search_config.get("hold_duration", config["hold_duration"]))
	var base_cluster_gap: float = float(search_config.get("cluster_gap", config["cluster_gap"]))
	var base_exit_gap: float = float(search_config.get("exit_gap", config["exit_gap"]))
	var base_lure1_duration: float = float(search_config.get("lure1_duration", config["lure1_duration"]))
	var base_lure2_duration: float = float(search_config.get("lure2_duration", config["lure2_duration"]))
	var base_duration: float = maxf(base_lure1_duration, base_lure2_duration)
	var share_lure_duration := bool(overrides.get("share_lure_duration", false))
	var lure_values: Array = overrides.get("lure_values", [])
	var hide_values: Array = overrides.get("hide_values", [])
	var siderophore_speed_values: Array = overrides.get("siderophore_speed_values", [])
	var run_drain_values: Array = overrides.get("run_drain_values", [])
	var walk_regen_values: Array = overrides.get("walk_regen_values", [])
	var stand_regen_values: Array = overrides.get("stand_regen_values", [])
	var consume_stamina_cost_values: Array = overrides.get("consume_stamina_cost_values", [])
	var hold_regen_values: Array = overrides.get("hold_regen_values", [])
	var hide_regen_values: Array = overrides.get("hide_regen_values", [])
	var hold_duration_values: Array = overrides.get("hold_duration_values", [])
	var cluster_gap_values: Array = overrides.get("cluster_gap_values", [])
	var exit_gap_values: Array = overrides.get("exit_gap_values", [])
	var lure_duration_values: Array = overrides.get("lure_duration_values", [])
	var lure1_duration_values: Array = overrides.get("lure1_duration_values", [])
	var lure2_duration_values: Array = overrides.get("lure2_duration_values", [])
	var threshold_search: Dictionary = overrides.get("threshold_search", {}).duplicate(true)
	var optimize_for_threshold := bool(overrides.get("optimize_for_threshold", share_lure_duration))
	var threshold_resolution: float = float(threshold_search.get("resolution", 2.5))
	var has_threshold_target := threshold_search.has("target_first_success_stamina")
	var threshold_target: float = float(threshold_search.get("target_first_success_stamina", 0.0))
	if lure_values.is_empty():
		for i in range(24, 41):
			lure_values.append(i * 0.5)
	if hide_values.is_empty():
		for i in range(6, 23):
			hide_values.append(i * 0.5)
	if siderophore_speed_values.is_empty():
		for i in range(-3, 4):
			siderophore_speed_values.append(maxf(0.1, base_speed + float(i) * 0.1))
	if run_drain_values.is_empty():
		run_drain_values.append(base_run_drain)
	if walk_regen_values.is_empty():
		walk_regen_values.append(base_walk_regen)
	if stand_regen_values.is_empty():
		stand_regen_values.append(base_stand_regen)
	if consume_stamina_cost_values.is_empty():
		consume_stamina_cost_values.append(base_consume_stamina_cost)
	if hold_duration_values.is_empty():
		hold_duration_values.append(base_hold_duration)
	if cluster_gap_values.is_empty():
		cluster_gap_values.append(base_cluster_gap)
	if exit_gap_values.is_empty():
		exit_gap_values.append(base_exit_gap)
	if share_lure_duration and lure_duration_values.is_empty():
		for i in range(-4, 3):
			lure_duration_values.append(maxf(6.0, base_duration + float(i)))

	var hold_regen_candidates: Array = []
	if hold_regen_values.is_empty():
		if search_config.has("hold_regen"):
			hold_regen_candidates.append(float(search_config["hold_regen"]))
		else:
			hold_regen_candidates.append(null)
	else:
		hold_regen_candidates = hold_regen_values.duplicate()

	var hide_regen_candidates: Array = []
	if hide_regen_values.is_empty():
		if search_config.has("hide_regen"):
			hide_regen_candidates.append(float(search_config["hide_regen"]))
		else:
			hide_regen_candidates.append(null)
	else:
		hide_regen_candidates = hide_regen_values.duplicate()

	var search_hold_regen_values: Array = hold_regen_values.duplicate()
	if search_hold_regen_values.is_empty() and search_config.has("hold_regen"):
		search_hold_regen_values.append(float(search_config["hold_regen"]))

	var search_hide_regen_values: Array = hide_regen_values.duplicate()
	if search_hide_regen_values.is_empty() and search_config.has("hide_regen"):
		search_hide_regen_values.append(float(search_config["hide_regen"]))

	var duration_pairs: Array[Dictionary] = []
	if share_lure_duration:
		for lure_duration in lure_duration_values:
			duration_pairs.append({
				"lure1_duration": float(lure_duration),
				"lure2_duration": float(lure_duration),
			})
	elif not lure1_duration_values.is_empty() or not lure2_duration_values.is_empty():
		var lure1_candidates: Array = lure1_duration_values.duplicate()
		var lure2_candidates: Array = lure2_duration_values.duplicate()
		if lure1_candidates.is_empty():
			lure1_candidates.append(base_lure1_duration)
		if lure2_candidates.is_empty():
			lure2_candidates.append(base_lure2_duration)
		for lure1_duration in lure1_candidates:
			for lure2_duration in lure2_candidates:
				duration_pairs.append({
					"lure1_duration": float(lure1_duration),
					"lure2_duration": float(lure2_duration),
				})
	else:
		duration_pairs.append({
			"lure1_duration": base_lure1_duration,
			"lure2_duration": base_lure2_duration,
		})

	var candidate_count := 0

	for duration_pair in duration_pairs:
		for run_drain in run_drain_values:
			for walk_regen in walk_regen_values:
				for stand_regen in stand_regen_values:
					for consume_stamina_cost_value in consume_stamina_cost_values:
						for hold_regen in hold_regen_candidates:
							for hide_regen in hide_regen_candidates:
								for hold_duration in hold_duration_values:
									for cluster_gap in cluster_gap_values:
										for exit_gap in exit_gap_values:
											for siderophore_speed in siderophore_speed_values:
												for lure_distance in lure_values:
													for hide_distance in hide_values:
														if hide_distance >= lure_distance - 1.0:
															continue
														candidate_count += 1
														var sim_config: Dictionary = search_config.duplicate(true)
														sim_config.merge({
															"lure_distance": lure_distance,
															"hide_distance": hide_distance,
															"siderophore_speed": float(siderophore_speed),
															"run_drain": float(run_drain),
															"walk_regen": float(walk_regen),
															"stand_regen": float(stand_regen),
															"consume_stamina_cost": float(consume_stamina_cost_value),
															"hold_duration": float(hold_duration),
															"cluster_gap": float(cluster_gap),
															"exit_gap": float(exit_gap),
															"lure1_duration": duration_pair["lure1_duration"],
															"lure2_duration": duration_pair["lure2_duration"],
														}, true)
														if hold_regen == null:
															sim_config.erase("hold_regen")
														else:
															sim_config["hold_regen"] = float(hold_regen)
														if hide_regen == null:
															sim_config.erase("hide_regen")
														else:
															sim_config["hide_regen"] = float(hide_regen)
														var sim = get_script().new(sim_config)
														var success: Dictionary = sim.run_scenario("success")
														if not success["success"]:
															continue
														var slow_retreat: Dictionary = sim.run_scenario("slow_retreat")
														var slow_lure2: Dictionary = sim.run_scenario("slow_lure2_activation")
														var no_lure2: Dictionary = sim.run_scenario("no_lure2")
														var slow_exit: Dictionary = sim.run_scenario("slow_exit")
														if slow_retreat["success"] or slow_lure2["success"] or no_lure2["success"] or slow_exit["success"]:
															continue
														var first_success_stamina := -1.0
														if optimize_for_threshold:
															first_success_stamina = sim.find_first_success_stamina({
																"resolution": threshold_resolution,
																"scenario_overrides": threshold_search.get("scenario_overrides", {}),
															})
															if first_success_stamina < 0.0:
																continue
														var margin_score: float = (
															success.get("exit_margin", -999.0)
															+ success.get("lure1_margin", -999.0)
															- absf((lure_distance * 0.5) - hide_distance)
														)
														var target_distance: float = absf(first_success_stamina - threshold_target) if has_threshold_target else 0.0
														var better := false
														if best.is_empty():
															better = true
														else:
															if optimize_for_threshold and has_threshold_target:
																if target_distance < best_target_distance - 0.001:
																	better = true
																elif absf(target_distance - best_target_distance) <= 0.001:
																	if first_success_stamina > best_threshold + 0.001:
																		better = true
																	elif absf(first_success_stamina - best_threshold) <= 0.001 and margin_score > best_margin_score:
																		better = true
															elif optimize_for_threshold:
																if first_success_stamina > best_threshold + 0.001:
																	better = true
																elif absf(first_success_stamina - best_threshold) <= 0.001 and margin_score > best_margin_score:
																	better = true
															elif margin_score > best_margin_score:
																better = true
														if better:
															best_margin_score = margin_score
															best_threshold = first_success_stamina
															best_target_distance = target_distance
															best = {
																"config": sim.config.duplicate(true),
																"success": success,
																"slow_retreat": slow_retreat,
																"slow_lure2_activation": slow_lure2,
																"no_lure2": no_lure2,
																"slow_exit": slow_exit,
																"score": margin_score,
																"first_success_stamina": first_success_stamina if optimize_for_threshold else null,
																"search_objective": {
																	"mode": (
																		"target_threshold" if optimize_for_threshold and has_threshold_target
																		else "maximize_threshold" if optimize_for_threshold
																		else "maximize_margin"
																	),
																	"target_first_success_stamina": threshold_target if optimize_for_threshold and has_threshold_target else null,
																	"threshold_resolution": threshold_resolution,
																	"shared_lure_duration": share_lure_duration,
																},
																"search_space": {
																	"lure_values": lure_values.duplicate(),
																	"hide_values": hide_values.duplicate(),
																	"siderophore_speed_values": siderophore_speed_values.duplicate(),
																	"run_drain_values": run_drain_values.duplicate(),
																	"walk_regen_values": walk_regen_values.duplicate(),
																	"stand_regen_values": stand_regen_values.duplicate(),
																	"consume_stamina_cost_values": consume_stamina_cost_values.duplicate(),
																	"hold_regen_values": search_hold_regen_values.duplicate(),
																	"hide_regen_values": search_hide_regen_values.duplicate(),
																	"hold_regen_inherits_stand_regen": search_hold_regen_values.is_empty(),
																	"hide_regen_inherits_stand_regen": search_hide_regen_values.is_empty(),
																	"hold_duration_values": hold_duration_values.duplicate(),
																	"cluster_gap_values": cluster_gap_values.duplicate(),
																"exit_gap_values": exit_gap_values.duplicate(),
																"lure_duration_values": lure_duration_values.duplicate(),
																"lure1_duration_values": lure1_duration_values.duplicate(),
																"lure2_duration_values": lure2_duration_values.duplicate(),
																"shared_lure_duration": share_lure_duration,
																"candidate_count": candidate_count,
															},
															}
	if not best.is_empty():
		var finalized_search_space: Dictionary = best.get("search_space", {}).duplicate(true)
		finalized_search_space["candidate_count"] = candidate_count
		best["search_space"] = finalized_search_space
	return best

func _setup_geometry() -> void:
	_lure2_x = 0.0
	_hide_x = config["hide_distance"]
	_lure1_x = config["lure_distance"]
	_cluster_x = _lure1_x + config["cluster_gap"]
	_exit_x = _cluster_x + config["exit_gap"]

func _reset_state() -> void:
	_setup_geometry()
	scheduler = EventScheduler.new()
	_last_sync_tick = 0.0
	_logs.clear()
	_trace.clear()
	_record_trace = false
	_policy = {}
	_result = {
		"success": false,
		"failure_reason": "",
	}

	_peris = {
		"x": _lure1_x,
		"stamina": float(config["stamina_max"]),
		"motion": null,
		"hidden": false,
		"visible": true,
		"hold_label": "",
	}
	_party = {
		"x": _hide_x,
		"motion": null,
		"hidden": true,
		"visible": false,
		"exit_window_open": false,
	}
	_lures = {
		"lure1": {"active": false, "expire_tick": -1.0, "x": _lure1_x},
		"lure2": {"active": false, "expire_tick": -1.0, "x": _lure2_x},
	}
	_siderophores.clear()
	for i in range(SWARM_OFFSETS.size()):
		_siderophores.append({
			"id": i,
			"x": _cluster_x + SWARM_OFFSETS[i],
			"target_x": _cluster_x + SWARM_OFFSETS[i],
			"radius": config["unaware_radius"],
		})

func _schedule_success(overrides: Dictionary) -> void:
	_peris["stamina"] = _policy["initial_stamina"]
	_schedule_at(0.0, "start_lure1_hold", func():
		_start_hold("lure1")
	)

func _schedule_slow_retreat(overrides: Dictionary) -> void:
	_peris["stamina"] = _policy["initial_stamina"]
	_schedule_at(0.0, "start_lure1_hold", func():
		_start_hold("lure1")
	)

func _schedule_slow_lure2_activation(overrides: Dictionary) -> void:
	_peris["stamina"] = _policy["initial_stamina"]
	_schedule_at(0.0, "start_lure1_hold", func():
		_start_hold("lure1")
	)

func _schedule_no_lure2(overrides: Dictionary) -> void:
	_peris["stamina"] = _policy["initial_stamina"]
	_schedule_at(0.0, "start_lure1_hold", func():
		_start_hold("lure1")
	)

func _schedule_slow_exit(overrides: Dictionary) -> void:
	_peris["stamina"] = _policy["initial_stamina"]
	_schedule_at(0.0, "start_lure1_hold", func():
		_start_hold("lure1")
	)

func _start_hold(lure_name: String) -> void:
	if _is_finished():
		return
	_stop_motion(_peris)
	_peris["hold_label"] = lure_name
	_peris["hidden"] = false
	_peris["visible"] = true
	_log("hold_start", {"lure": lure_name})
	_schedule_after(config["hold_duration"], "hold_complete_%s" % lure_name, func():
		_finish_hold(lure_name)
	)

func _finish_hold(lure_name: String) -> void:
	if _is_finished():
		return
	_apply_consume_stamina_cost(lure_name)
	_activate_lure(lure_name)
	_peris["hold_label"] = ""
	match lure_name:
		"lure1":
			var hesitation: float = _policy["retreat_hesitation"]
			if hesitation > 0.0:
				_schedule_after(hesitation, "begin_retreat_after_hesitation", func():
					_begin_retreat_to_lure2()
				)
			else:
				_begin_retreat_to_lure2()
		"lure2":
			if _scenario_name() == "slow_lure2_activation":
				# Delayed hold branch.
				pass

func _begin_retreat_to_lure2() -> void:
	if _is_finished():
		return
	_log("retreat_begin", {"from": _peris["x"], "to": _lure2_x, "stamina": _peris["stamina"]})
	_start_motion(_peris, _lure2_x, true, "_on_arrive_lure2")

func _on_arrive_lure2() -> void:
	if _is_finished():
		return
	if scheduler.get_current_tick() >= _lures["lure1"]["expire_tick"] and not _lures["lure2"]["active"]:
		_fail("lure1_expired_before_lure2")
		return
	if _policy["skip_lure2"]:
		_move_peris_to_hide()
		return
	var lure2_delay: float = _policy["lure2_activation_delay"]
	if lure2_delay > 0.0:
		_schedule_after(lure2_delay, "delayed_lure2_hold", func():
			_start_hold("lure2")
		)
	else:
		_start_hold("lure2")

func _activate_lure(lure_name: String) -> void:
	var lure: Dictionary = _lures[lure_name]
	lure["active"] = true
	lure["expire_tick"] = scheduler.get_current_tick() + config["%s_duration" % lure_name]
	_lures[lure_name] = lure
	if lure_name == "lure2":
		_result["lure2_activation_tick"] = scheduler.get_current_tick()
	_log("lure_active", {"lure": lure_name, "expire_tick": lure["expire_tick"]})
	_schedule_at(lure["expire_tick"], "expire_%s" % lure_name, func():
		_expire_lure(lure_name)
	)
	_refresh_swarm_targets()
	if lure_name == "lure2":
		_move_peris_to_hide()

func _expire_lure(lure_name: String) -> void:
	var lure: Dictionary = _lures[lure_name]
	lure["active"] = false
	_lures[lure_name] = lure
	_log("lure_expired", {"lure": lure_name})
	if lure_name == "lure2" and _party["visible"] and _party["motion"] != null:
		_result["lure2_expired_mid_exit"] = true
	_refresh_swarm_targets()
	if lure_name == "lure2" and not _result["success"] and _party["visible"]:
		_schedule_after(0.1, "post_lure2_expire_guard", func():
			if not _result["success"] and not String(_result["failure_reason"]).is_empty():
				return
			if not _result["success"] and _party["motion"] != null:
				_fail("lure2_expired_mid_exit")
		)

func _refresh_swarm_targets() -> void:
	var target_name := ""
	if _lures["lure1"]["active"]:
		target_name = "lure1"
	elif _lures["lure2"]["active"]:
		target_name = "lure2"
	else:
		target_name = "cluster"
	for i in range(_siderophores.size()):
		var unit := _siderophores[i]
		match target_name:
			"lure1":
				unit["target_x"] = _lure1_x + SWARM_OFFSETS[i]
				unit["radius"] = config["fixated_radius"]
			"lure2":
				unit["target_x"] = _lure2_x + SWARM_OFFSETS[i]
				unit["radius"] = config["fixated_radius"]
			_:
				unit["target_x"] = _cluster_x + SWARM_OFFSETS[i]
				unit["radius"] = config["unaware_radius"]
	_log("swarm_retarget", {"target": target_name})

func _move_peris_to_hide() -> void:
	if _is_finished():
		return
	_start_motion(_peris, _hide_x, false, "_on_peris_hidden")

func _on_peris_hidden() -> void:
	if _is_finished():
		return
	_peris["hidden"] = true
	_peris["visible"] = false
	_party["hidden"] = true
	_party["visible"] = false
	_log("party_hidden", {})
	match _scenario_name():
		"no_lure2":
			_schedule_after(maxf(0.5, _lures["lure1"]["expire_tick"] - scheduler.get_current_tick() + 0.5), "blocked_exit_check", func():
				if not _party["exit_window_open"]:
					_fail("exit_blocked")
			)
		"slow_exit":
			_schedule_after(0.1, "watch_exit_window_slow", func():
				_watch_exit_window(true)
			)
		_:
			_schedule_after(0.1, "watch_exit_window", func():
				_watch_exit_window(false)
			)

func _watch_exit_window(low_stamina_exit: bool) -> void:
	if _is_finished():
		return
	if _party["exit_window_open"]:
		_party["hidden"] = false
		_party["visible"] = true
		var exit_stamina_cap: float = _policy["exit_stamina_cap"]
		if low_stamina_exit:
			exit_stamina_cap = minf(exit_stamina_cap, 18.0)
		if exit_stamina_cap < config["stamina_max"]:
			_peris["stamina"] = minf(_peris["stamina"], exit_stamina_cap)
		var exit_delay: float = _policy["exit_release_delay"]
		if exit_delay > 0.0:
			_schedule_after(exit_delay, "delayed_exit_run", func():
				_start_party_exit()
			)
		else:
			_start_party_exit()
		return
	_schedule_after(0.1, "watch_exit_window_repeat", func():
		_watch_exit_window(low_stamina_exit)
	)

func _start_party_exit() -> void:
	if _is_finished():
		return
	_party["x"] = _hide_x
	_log("exit_run_begin", {"stamina": _peris["stamina"]})
	_start_motion(_party, _exit_x, true, "_on_party_exit")

func _on_party_exit() -> void:
	if _is_finished():
		return
	_result["success"] = true
	_result["completed_tick"] = scheduler.get_current_tick()
	_result["exit_margin"] = _lures["lure2"]["expire_tick"] - scheduler.get_current_tick()
	_result["lure1_margin"] = _lures["lure1"]["expire_tick"] - _result.get("lure2_activation_tick", scheduler.get_current_tick())
	_log("success", _result)

func _start_motion(actor: Dictionary, target_x: float, allow_run: bool, callback_name: String) -> void:
	var distance: float = absf(target_x - actor["x"])
	if distance < 0.01:
		call(callback_name)
		return
	var direction := 1.0 if target_x >= actor["x"] else -1.0
	var is_party := actor == _party
	var will_run := allow_run
	if is_party:
		will_run = _peris["stamina"] > 0.0
	if not will_run:
		var duration: float = distance / config["walk_speed"]
		actor["motion"] = {
			"target_x": target_x,
			"direction": direction,
			"speed": config["walk_speed"],
			"mode": "walk",
		}
		_schedule_after(duration, "arrive_%s" % callback_name, func():
			_stop_motion(actor)
			actor["x"] = target_x
			call(callback_name)
		)
		return
	var speed: float = config["run_speed"]
	var run_seconds: float = _peris["stamina"] / config["run_drain"]
	var run_distance: float = run_seconds * speed
	if is_party:
		run_seconds = _peris["stamina"] / config["run_drain"]
		run_distance = run_seconds * speed
	if run_distance >= distance:
		actor["motion"] = {
			"target_x": target_x,
			"direction": direction,
			"speed": speed,
			"mode": "run",
		}
		_schedule_after(distance / speed, "arrive_%s" % callback_name, func():
			_stop_motion(actor)
			actor["x"] = target_x
			call(callback_name)
		)
		return
	actor["motion"] = {
		"target_x": target_x,
		"direction": direction,
		"speed": speed,
		"mode": "run",
	}
	_schedule_after(run_seconds, "run_depleted_%s" % callback_name, func():
		_start_motion_walk_remainder(actor, target_x, callback_name)
	)

func _start_motion_walk_remainder(actor: Dictionary, target_x: float, callback_name: String) -> void:
	_stop_motion(actor)
	actor["motion"] = {
		"target_x": target_x,
		"direction": 1.0 if target_x >= actor["x"] else -1.0,
		"speed": config["walk_speed"],
		"mode": "walk",
	}
	var remaining := absf(target_x - actor["x"])
	_schedule_after(remaining / config["walk_speed"], "walk_arrive_%s" % callback_name, func():
		_stop_motion(actor)
		actor["x"] = target_x
		call(callback_name)
	)

func _stop_motion(actor: Dictionary) -> void:
	actor["motion"] = null

func _sync_to(target_tick: float) -> void:
	if target_tick <= _last_sync_tick:
		return
	var tick := _last_sync_tick
	while tick < target_tick and not _is_finished():
		var step := minf(config["continuous_step"], target_tick - tick)
		_step_continuous(step)
		tick += step
		if _record_trace:
			_record_trace_point(tick)
	_last_sync_tick = target_tick

func _step_continuous(dt: float) -> void:
	_integrate_actor(_peris, dt)
	_integrate_actor(_party, dt)
	for unit in _siderophores:
		var dx: float = unit["target_x"] - unit["x"]
		var move: float = signf(dx) * minf(absf(dx), config["siderophore_speed"] * dt)
		unit["x"] += move
	_update_exit_window()
	_check_detection()

func _integrate_actor(actor: Dictionary, dt: float) -> void:
	if actor["motion"] != null:
		var motion: Dictionary = actor["motion"]
		var delta_x: float = motion["direction"] * motion["speed"] * dt
		var next_x: float = actor["x"] + delta_x
		if motion["direction"] > 0.0:
			actor["x"] = minf(next_x, motion["target_x"])
		else:
			actor["x"] = maxf(next_x, motion["target_x"])

	var current_stamina: float = _peris["stamina"]
	var hold_regen: float = hold_regen_rate()
	var hide_regen: float = hide_regen_rate()
	var derivative := func(value: float, _local_t: float) -> float:
		if _party["motion"] != null and _party["motion"]["mode"] == "run":
			return -config["run_drain"]
		if _peris["motion"] != null and _peris["motion"]["mode"] == "run":
			return -config["run_drain"]
		if _peris["hold_label"] != "":
			return hold_regen
		if _peris["motion"] != null and _peris["motion"]["mode"] == "walk":
			return config["walk_regen"]
		if _party["motion"] != null and _party["motion"]["mode"] == "walk":
			return config["walk_regen"]
		if _party["hidden"] and not _party["visible"] and _party["motion"] == null:
			return hide_regen
		return config["stand_regen"]
	_peris["stamina"] = clampf(ODESolverRef.rk4_scalar(current_stamina, dt, derivative), 0.0, config["stamina_max"])

func _apply_consume_stamina_cost(lure_name: String) -> void:
	var cost: float = consume_stamina_cost()
	if cost <= 0.0:
		return
	_peris["stamina"] = clampf(_peris["stamina"] - cost, 0.0, config["stamina_max"])
	_log("consume_stamina_cost", {
		"lure": lure_name,
		"cost": cost,
		"stamina": _peris["stamina"],
	})

func _update_exit_window() -> void:
	var count := 0
	for unit in _siderophores:
		if unit["x"] <= _hide_x - unit["radius"]:
			count += 1
	if count >= _siderophores.size():
		_party["exit_window_open"] = true

func _check_detection() -> void:
	if _result["success"] or not String(_result["failure_reason"]).is_empty():
		return
	var visible_positions: Array[float] = []
	if _peris["visible"] and not _peris["hidden"]:
		visible_positions.append(_peris["x"])
	if _party["visible"] and not _party["hidden"]:
		visible_positions.append(_party["x"])
	if visible_positions.is_empty():
		return
	for unit in _siderophores:
		for pos in visible_positions:
			if absf(unit["x"] - pos) <= unit["radius"]:
				_fail("detected")
				return

func _schedule_at(tick: float, label: String, callback: Callable) -> void:
	scheduler.schedule_at(tick, func():
		_sync_to(scheduler.get_current_tick())
		_result["last_event"] = label
		callback.call()
	, label)

func _schedule_after(delay: float, label: String, callback: Callable) -> void:
	_schedule_at(scheduler.get_current_tick() + delay, label, callback)

func _scenario_name() -> String:
	return _result.get("scenario", "")

func _is_finished() -> bool:
	return _result["success"] or not String(_result["failure_reason"]).is_empty()

func _fail(reason: String) -> void:
	if _is_finished():
		return
	_result["failure_reason"] = reason
	_result["failed_tick"] = scheduler.get_current_tick() if scheduler else 0.0
	_log("failure", {"reason": reason})

func _finalize(name: String) -> Dictionary:
	_result["scenario"] = name
	_result["logs"] = _logs.duplicate(true)
	_result["config"] = config.duplicate(true)
	if _record_trace:
		_result["trace"] = _trace.duplicate(true)
	_result["policy"] = _policy.duplicate(true)
	_result["exit_distance"] = _exit_x - _hide_x
	_result["lure1_to_lure2"] = _lure1_x - _lure2_x
	_result["lure2_to_hide"] = _hide_x - _lure2_x
	return _result.duplicate(true)

func _log(kind: String, data: Dictionary) -> void:
	_logs.append({
		"tick": scheduler.get_current_tick() if scheduler else 0.0,
		"kind": kind,
		"data": data.duplicate(true),
	})

func _build_policy(name: String, overrides: Dictionary) -> Dictionary:
	var policy := {
		"initial_stamina": float(overrides.get("peris_stamina", config["stamina_max"])),
		"retreat_hesitation": 0.0,
		"lure2_activation_delay": 0.0,
		"skip_lure2": false,
		"exit_stamina_cap": float(overrides.get("exit_stamina_cap", config["stamina_max"])),
		"exit_release_delay": float(overrides.get("exit_release_delay", 0.0)),
	}
	match name:
		"slow_retreat":
			policy["retreat_hesitation"] = float(overrides.get("retreat_hesitation", 7.5))
		"slow_lure2_activation":
			policy["lure2_activation_delay"] = float(overrides.get("lure2_activation_delay", 6.0))
		"no_lure2":
			policy["skip_lure2"] = bool(overrides.get("skip_lure2", true))
		"slow_exit":
			policy["exit_stamina_cap"] = float(overrides.get("exit_stamina_cap", 18.0))
	return policy

func _record_trace_point(tick: float) -> void:
	var peris_motion: Dictionary = _peris["motion"] if _peris["motion"] != null else {}
	var party_motion: Dictionary = _party["motion"] if _party["motion"] != null else {}
	var retreat_remaining := 0.0
	var exit_remaining := maxf(0.0, _exit_x - _hide_x)
	var phase_actor := "idle"
	var phase_mode := "stand"
	if _peris["hold_label"] == "lure1":
		retreat_remaining = _lure1_x - _lure2_x
		phase_actor = "peris"
		phase_mode = "hold"
	elif _peris["motion"] != null:
		retreat_remaining = absf(peris_motion["target_x"] - _peris["x"])
		phase_actor = "peris"
		phase_mode = peris_motion["mode"]
	if _party["motion"] != null:
		exit_remaining = absf(party_motion["target_x"] - _party["x"])
		phase_actor = "party"
		phase_mode = party_motion["mode"]
	elif not _party["visible"]:
		exit_remaining = maxf(0.0, _exit_x - _hide_x)
		phase_actor = "party"
		phase_mode = "hide"
	if _peris["hold_label"] == "lure2":
		phase_actor = "peris"
		phase_mode = "hold"
	var active_lure := "none"
	if _lures["lure1"]["active"]:
		active_lure = "lure1"
	elif _lures["lure2"]["active"]:
		active_lure = "lure2"
	var swarm_front := 1e9
	var swarm_back := -1e9
	for unit in _siderophores:
		swarm_front = minf(swarm_front, unit["x"])
		swarm_back = maxf(swarm_back, unit["x"])
	_trace.append({
		"tick": tick,
		"stamina": _peris["stamina"],
		"peris_x": _peris["x"],
		"party_x": _party["x"],
		"peris_visible": _peris["visible"],
		"party_visible": _party["visible"],
		"retreat_distance_remaining": retreat_remaining,
		"exit_distance_remaining": exit_remaining,
		"phase_actor": phase_actor,
		"phase_mode": phase_mode,
		"active_lure": active_lure,
		"swarm_front": swarm_front,
		"swarm_back": swarm_back,
		"exit_window_open": _party["exit_window_open"],
	})
