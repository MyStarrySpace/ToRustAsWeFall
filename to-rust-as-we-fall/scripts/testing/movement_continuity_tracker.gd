class_name MovementContinuityTracker
extends RefCounted

## Read-only release-evidence contract for movement presentation. Callers sample
## once per presented frame; this object never commands or mutates gameplay.
##
## A non-trivial non-portal displacement is valid only when all four full-XYZ
## authorities (logical, projected render, global_position, and
## global_transform.origin) retain an origin, at least two strict interior points,
## and an endpoint across multiple scheduler ticks and presented frames. This is
## deliberately stronger than endpoint parity: moving every authority directly
## to the endpoint in one synchronized write is still a failed episode.

const CONTRACT_ID := "movement_continuity/v1"
const MOTION_AUTHORITY_CONTRACT := "movement_authority/v1"

const DEFAULT_TRANSFORM_TOLERANCE := 0.08
const DEFAULT_PROJECTION_TOLERANCE := 0.08
const MIN_TRACKED_DISPLACEMENT := 0.12
const INTERIOR_DISTANCE_EPSILON := 0.015
const MAX_STEP_FRACTION := 0.50
const MAX_TICK_GAP_FRACTION := 0.90
const MOTION_BUDGET_EPSILON := 0.01
const MOTION_SAMPLE_POSITION_TOLERANCE := 0.01
const MOTION_SEAM_TOLERANCE := 0.08
const TICK_EPSILON := 0.000001

var _states: Dictionary = {}


func reset(character_ids: Array = []) -> void:
	_states.clear()
	for id_v in character_ids:
		_ensure_state(str(id_v))


## Sample schema (Vector3 values may also be portable {x,y,z} dictionaries):
## {
##   character_id, scheduler_tick, presented_frame, in_flight,
##   logical_position, render_position, presented_position,
##   presented_transform_origin,
##   logical_to_render_projection_valid, logical_to_render_projection_error,
##   declared_local_speed_bound,
##   movement_provenance?, portal_discontinuity?
## }
func sample(value: Dictionary) -> void:
	var character_id := str(value.get("character_id", ""))
	if character_id.is_empty():
		return
	var state := _ensure_state(character_id)
	var canonical := _canonical_sample(value)
	if canonical.is_empty():
		_append_state_violation(state, "malformed_or_non_finite_sample")
		return
	_validate_sample_authority_parity(state, canonical)
	var previous := state.get("last_sample", {}) as Dictionary
	if previous.is_empty():
		state["last_sample"] = canonical
		if bool(canonical.get("in_flight", false)):
			_append_state_violation(state, "movement_started_before_observed_origin")
		else:
			state["settled_anchor"] = canonical.duplicate(true)
		return

	var current_frame := int(canonical.get("presented_frame", -1))
	var previous_frame := int(previous.get("presented_frame", -1))
	var current_tick := float(canonical.get("scheduler_tick", -INF))
	var previous_tick := float(previous.get("scheduler_tick", -INF))
	if current_frame <= previous_frame:
		_append_state_violation(state, "presented_frame_not_strictly_increasing")
	if current_tick < previous_tick - TICK_EPSILON:
		_append_state_violation(state, "scheduler_tick_regressed")
	_record_motion_pair(state, previous, canonical)

	var was_in_flight := bool(previous.get("in_flight", false))
	var is_in_flight := bool(canonical.get("in_flight", false))
	var active := state.get("active_episode", {}) as Dictionary
	if is_in_flight and active.is_empty():
		if was_in_flight:
			_append_state_violation(state, "movement_started_before_observed_origin")
		else:
			active = _new_episode(previous, canonical)
			state["active_episode"] = active
	elif is_in_flight:
		_append_episode_sample(active, canonical)

	# Settled jitter never advances the legal anchor. This prevents a sequence of
	# individually sub-threshold direct mutations from laundering an arbitrarily
	# large displacement. Only a certified continuous episode or one fresh, exact
	# production-authorized discontinuity may establish a new settled anchor. No
	# such issuer/lineage exists in this testing-only contract yet, so even a fully
	# shaped portal-looking dictionary remains unissued and fails closed.
	if not was_in_flight and not is_in_flight:
		var settled_anchor := state.get("settled_anchor", {}) as Dictionary
		if settled_anchor.is_empty():
			settled_anchor = previous
			state["settled_anchor"] = settled_anchor.duplicate(true)
		var settled_displacement := _sample_displacement(
			settled_anchor, canonical)
		if settled_displacement >= MIN_TRACKED_DISPLACEMENT:
			var portal_value := canonical.get(
				"portal_discontinuity", {}) as Dictionary
			if not portal_value.is_empty():
				_append_state_violation(
					state, "unissued_portal_discontinuity_not_authorized")
			if not bool(state.get("settled_jump_latched", false)):
				state["settled_jump_violation_count"] = int(
					state.get("settled_jump_violation_count", 0)) + 1
			state["settled_jump_latched"] = true
			_append_state_violation(
				state, "settled_endpoint_jump_without_continuous_episode")
		else:
			state["settled_jump_latched"] = false

	if was_in_flight and not is_in_flight:
		if active.is_empty():
			# The tracker was attached after launch. That can remain diagnostic, but it
			# cannot certify an origin-to-endpoint movement episode.
			_append_state_violation(state, "movement_endpoint_without_observed_origin")
		else:
			_append_episode_sample(active, canonical)
			if _finalize_episode(state, active):
				state["settled_anchor"] = canonical.duplicate(true)
				state["settled_jump_latched"] = false
			state["active_episode"] = {}

	state["last_sample"] = canonical


func receipt(character_id: String) -> Dictionary:
	var state := _ensure_state(character_id)
	var active := state.get("active_episode", {}) as Dictionary
	return {
		"contract_id": CONTRACT_ID,
		"valid": (state.get("violations", []) as Array).is_empty(),
		"completed_episode_count": int(state.get("completed_episode_count", 0)),
		"completed_continuous_episode_count": int(
			state.get("completed_continuous_episode_count", 0)),
		"invalid_episode_count": int(state.get("invalid_episode_count", 0)),
		"settled_jump_violation_count": int(
			state.get("settled_jump_violation_count", 0)),
		"typed_portal_exception_count": int(
			state.get("typed_portal_exception_count", 0)),
		"bounded_step_count": int(state.get("bounded_step_count", 0)),
		"invalid_motion_authority_count": int(
			state.get("invalid_motion_authority_count", 0)),
		"max_logical_speed_excess": float(
			state.get("max_logical_speed_excess", 0.0)),
		"max_render_speed_excess": float(
			state.get("max_render_speed_excess", 0.0)),
		"last_motion_pair": (state.get(
			"last_motion_pair", {}) as Dictionary).duplicate(true),
		"active_episode": not active.is_empty(),
		"active_sample_count": (active.get("samples", []) as Array).size(),
		"violations": (state.get("violations", []) as Array).duplicate(),
		"last_completed_episode": (state.get(
			"last_completed_episode", {}) as Dictionary).duplicate(true),
		"last_typed_portal_discontinuity": (state.get(
			"last_typed_portal_discontinuity", {}) as Dictionary).duplicate(true),
	}


func receipts() -> Dictionary:
	var out: Dictionary = {}
	var ids := _states.keys()
	ids.sort()
	for id_v in ids:
		var character_id := str(id_v)
		out[character_id] = receipt(character_id)
	return out


func _ensure_state(character_id: String) -> Dictionary:
	if not _states.has(character_id):
		_states[character_id] = {
			"last_sample": {},
			"settled_anchor": {},
			"active_episode": {},
			"completed_episode_count": 0,
			"completed_continuous_episode_count": 0,
			"invalid_episode_count": 0,
			"settled_jump_violation_count": 0,
			"typed_portal_exception_count": 0,
			"bounded_step_count": 0,
			"invalid_motion_authority_count": 0,
			"max_logical_speed_excess": 0.0,
			"max_render_speed_excess": 0.0,
			"last_motion_pair": {},
			"settled_jump_latched": false,
			"violations": [],
			"last_completed_episode": {},
			"last_typed_portal_discontinuity": {},
		}
	return _states[character_id] as Dictionary


func _canonical_sample(value: Dictionary) -> Dictionary:
	var logical := _vector3_from(value.get("logical_position", null))
	var render := _vector3_from(value.get("render_position", null))
	var presented := _vector3_from(value.get("presented_position", null))
	var transform_origin := _vector3_from(
		value.get("presented_transform_origin", null))
	var tick := float(value.get("scheduler_tick", NAN))
	var frame := int(value.get("presented_frame", -1))
	var projection_error := float(value.get(
		"logical_to_render_projection_error", NAN))
	var declared_speed_bound := float(value.get(
		"declared_local_speed_bound", NAN))
	if not logical.is_finite() or not render.is_finite() \
			or not presented.is_finite() or not transform_origin.is_finite() \
			or not is_finite(tick) or frame < 0 or not is_finite(projection_error):
		return {}
	return {
		"scheduler_tick": tick,
		"presented_frame": frame,
		"in_flight": bool(value.get("in_flight", false)),
		"logical_position": logical,
		"render_position": render,
		"presented_position": presented,
		"presented_transform_origin": transform_origin,
		"logical_to_render_projection_valid": bool(value.get(
			"logical_to_render_projection_valid", false)),
		"logical_to_render_projection_error": projection_error,
		"declared_local_speed_bound": declared_speed_bound \
			if is_finite(declared_speed_bound) else -1.0,
		"motion_authority": (value.get(
			"motion_authority", {}) as Dictionary).duplicate(true),
		"movement_provenance": (value.get(
			"movement_provenance", {}) as Dictionary).duplicate(true),
		"portal_discontinuity": (value.get(
			"portal_discontinuity", {}) as Dictionary).duplicate(true),
	}


func _new_episode(origin: Dictionary, first_active: Dictionary) -> Dictionary:
	var episode := {
		"samples": [origin.duplicate(true)],
		"movement_provenance": [],
	}
	_append_episode_sample(episode, first_active)
	return episode


func _append_episode_sample(episode: Dictionary, sample_value: Dictionary) -> void:
	(episode.get("samples", []) as Array).append(sample_value.duplicate(true))
	var provenance := sample_value.get("movement_provenance", {}) as Dictionary
	if provenance.is_empty():
		return
	var canonical := {
		"category": str(provenance.get("category", "")),
		"kind": str(provenance.get("kind", "")),
		"type": str(provenance.get("type", "")),
	}
	var provenances := episode.get("movement_provenance", []) as Array
	if not provenances.has(canonical):
		provenances.append(canonical)


func _finalize_episode(state: Dictionary, episode: Dictionary) -> bool:
	var samples := episode.get("samples", []) as Array
	state["completed_episode_count"] = int(
		state.get("completed_episode_count", 0)) + 1
	var result := _evaluate_episode(samples)
	result["movement_provenance"] = (episode.get(
		"movement_provenance", []) as Array).duplicate(true)
	state["last_completed_episode"] = result
	if bool(result.get("valid", false)):
		state["completed_continuous_episode_count"] = int(
			state.get("completed_continuous_episode_count", 0)) + 1
		return true
	else:
		state["invalid_episode_count"] = int(
			state.get("invalid_episode_count", 0)) + 1
		for reason_v in result.get("violations", []):
			_append_state_violation(state, str(reason_v))
	return false


func _evaluate_episode(samples: Array) -> Dictionary:
	var violations: Array[String] = []
	# Defense in depth: even if a future caller constructs an episode directly,
	# an already-moving sample can never impersonate the required settled origin.
	if not samples.is_empty() \
			and bool((samples[0] as Dictionary).get("in_flight", false)):
		violations.append("movement_origin_already_in_flight")
	if samples.size() < 4:
		violations.append("missing_origin_multiple_interiors_endpoint_samples")
		return _episode_result(samples, violations, 0, 0, 1.0, 1.0, 0.0)
	var origin := samples[0] as Dictionary
	var endpoint := samples[samples.size() - 1] as Dictionary
	var start_tick := float(origin.get("scheduler_tick", 0.0))
	var end_tick := float(endpoint.get("scheduler_tick", start_tick))
	var start_frame := int(origin.get("presented_frame", 0))
	var end_frame := int(endpoint.get("presented_frame", start_frame))
	var scheduler_span := end_tick - start_tick
	var presented_frame_span := end_frame - start_frame
	for sample_v in samples:
		var sample_value := sample_v as Dictionary
		var declared_bound := float(sample_value.get(
			"declared_local_speed_bound", -1.0))
		var sample_motion := sample_value.get("motion_authority", {}) as Dictionary
		var sample_phase := str(sample_motion.get("phase", ""))
		if declared_bound < 0.0 \
				or (sample_phase in ["ordinary", "external"] \
					and declared_bound <= 0.0):
			violations.append("missing_or_nonpositive_local_speed_bound")
		for reason in _sample_motion_authority_violations(sample_value):
			if not violations.has(reason):
				violations.append(reason)
	for sample_index in range(1, samples.size()):
		var pair := _motion_pair_budget(
			samples[sample_index - 1] as Dictionary,
			samples[sample_index] as Dictionary)
		if not bool(pair.get("valid", false)):
			if not violations.has("invalid_motion_authority_interval"):
				violations.append("invalid_motion_authority_interval")
			continue
		if float(pair.get("logical_step", INF)) \
				> float(pair.get("logical_bound", -INF)) + MOTION_BUDGET_EPSILON \
				and not violations.has("logical_position_local_speed_bound_exceeded"):
			violations.append("logical_position_local_speed_bound_exceeded")
		if float(pair.get("render_step", INF)) \
				> float(pair.get("render_bound", -INF)) + MOTION_BUDGET_EPSILON \
				and not violations.has("render_position_local_speed_bound_exceeded"):
			violations.append("render_position_local_speed_bound_exceeded")
	if scheduler_span <= TICK_EPSILON:
		violations.append("scheduler_time_did_not_advance")
	if presented_frame_span < 2:
		violations.append("movement_did_not_span_multiple_presented_frames")

	var authority_keys := [
		"logical_position",
		"render_position",
		"presented_position",
		"presented_transform_origin",
	]
	var tracked_displacement := 0.0
	var max_step_fraction := 0.0
	for authority_key in authority_keys:
		var direct := (endpoint[authority_key] as Vector3).distance_to(
			origin[authority_key] as Vector3)
		tracked_displacement = maxf(tracked_displacement, direct)
		var cumulative := 0.0
		var largest_step := 0.0
		for sample_index in range(1, samples.size()):
			var prior := samples[sample_index - 1] as Dictionary
			var current := samples[sample_index] as Dictionary
			var step := (current[authority_key] as Vector3).distance_to(
				prior[authority_key] as Vector3)
			cumulative += step
			largest_step = maxf(largest_step, step)
		if cumulative >= MIN_TRACKED_DISPLACEMENT:
			var fraction := largest_step / cumulative
			max_step_fraction = maxf(max_step_fraction, fraction)
			if fraction >= MAX_STEP_FRACTION:
				violations.append("%s_endpoint_step_unbounded" % authority_key)

	var strict_interior_frames: Dictionary = {}
	var strict_interior_ticks: Dictionary = {}
	for sample_index in range(1, samples.size() - 1):
		var sample_value := samples[sample_index] as Dictionary
		var sample_tick := float(sample_value.get("scheduler_tick", start_tick))
		var sample_frame := int(sample_value.get("presented_frame", start_frame))
		if sample_tick <= start_tick + TICK_EPSILON \
				or sample_tick >= end_tick - TICK_EPSILON \
				or sample_frame <= start_frame or sample_frame >= end_frame:
			continue
		var strict_full_xyz := true
		for authority_key in authority_keys:
			var point := sample_value[authority_key] as Vector3
			strict_full_xyz = strict_full_xyz \
				and point.distance_to(origin[authority_key] as Vector3) \
					> INTERIOR_DISTANCE_EPSILON \
				and point.distance_to(endpoint[authority_key] as Vector3) \
					> INTERIOR_DISTANCE_EPSILON
		if strict_full_xyz:
			strict_interior_frames[sample_frame] = true
			strict_interior_ticks["%.9f" % sample_tick] = true
	if strict_interior_frames.size() < 2 or strict_interior_ticks.size() < 2:
		violations.append("insufficient_strict_intermediate_full_xyz_progress")

	var max_tick_gap_fraction := 0.0
	if scheduler_span > TICK_EPSILON:
		for sample_index in range(1, samples.size()):
			var prior_tick := float((samples[sample_index - 1] as Dictionary).get(
				"scheduler_tick", start_tick))
			var current_tick := float((samples[sample_index] as Dictionary).get(
				"scheduler_tick", prior_tick))
			max_tick_gap_fraction = maxf(
				max_tick_gap_fraction, maxf(0.0, current_tick - prior_tick) / scheduler_span)
		if max_tick_gap_fraction >= MAX_TICK_GAP_FRACTION:
			violations.append("scheduler_progress_step_unbounded")

	var max_position_error := 0.0
	var max_transform_error := 0.0
	var max_projection_error := 0.0
	var projection_valid := true
	for sample_v in samples:
		var sample_value := sample_v as Dictionary
		max_position_error = maxf(max_position_error,
			(sample_value["presented_position"] as Vector3).distance_to(
				sample_value["render_position"] as Vector3))
		max_transform_error = maxf(max_transform_error,
			(sample_value["presented_transform_origin"] as Vector3).distance_to(
				sample_value["render_position"] as Vector3))
		max_projection_error = maxf(max_projection_error, float(sample_value.get(
			"logical_to_render_projection_error", INF)))
		projection_valid = projection_valid and bool(sample_value.get(
			"logical_to_render_projection_valid", false))
	if not projection_valid or max_projection_error > DEFAULT_PROJECTION_TOLERANCE:
		violations.append("logical_render_projection_diverged")
	if max_position_error > DEFAULT_TRANSFORM_TOLERANCE:
		violations.append("global_position_diverged_from_render")
	if max_transform_error > DEFAULT_TRANSFORM_TOLERANCE:
		violations.append("global_transform_origin_diverged_from_render")

	if tracked_displacement < MIN_TRACKED_DISPLACEMENT:
		# A stationary/no-op accepted member is not movement continuity evidence,
		# but it is also not a teleport violation.
		violations.append("episode_displacement_below_continuity_threshold")
	return _episode_result(
		samples, violations, strict_interior_frames.size(),
		strict_interior_ticks.size(), max_step_fraction,
		max_tick_gap_fraction, tracked_displacement,
		max_position_error, max_transform_error, max_projection_error)


func _episode_result(
		samples: Array,
		violations: Array[String],
		strict_frame_count: int,
		strict_tick_count: int,
		max_step_fraction: float,
		max_tick_gap_fraction: float,
		displacement: float,
		max_position_error := 0.0,
		max_transform_error := 0.0,
		max_projection_error := 0.0
	) -> Dictionary:
	var origin: Dictionary = samples[0] if not samples.is_empty() else {}
	var endpoint: Dictionary = samples[samples.size() - 1] \
		if not samples.is_empty() else {}
	return {
		"valid": violations.is_empty(),
		"violations": violations.duplicate(),
		"sample_count": samples.size(),
		"strict_interior_presented_frame_count": strict_frame_count,
		"strict_interior_scheduler_tick_count": strict_tick_count,
		"start_presented_frame": int(origin.get("presented_frame", -1)),
		"end_presented_frame": int(endpoint.get("presented_frame", -1)),
		"start_scheduler_tick": float(origin.get("scheduler_tick", -1.0)),
		"end_scheduler_tick": float(endpoint.get("scheduler_tick", -1.0)),
		"max_step_fraction": max_step_fraction,
		"max_scheduler_tick_gap_fraction": max_tick_gap_fraction,
		"full_xyz_displacement": displacement,
		"max_presented_position_error": max_position_error,
		"max_presented_transform_error": max_transform_error,
		"max_logical_render_projection_error": max_projection_error,
	}


func _sample_displacement(previous: Dictionary, current: Dictionary) -> float:
	var displacement := 0.0
	for authority_key in [
		"logical_position",
		"render_position",
		"presented_position",
		"presented_transform_origin",
	]:
		displacement = maxf(displacement,
			(previous[authority_key] as Vector3).distance_to(
				current[authority_key] as Vector3))
	return displacement


func _record_motion_pair(
		state: Dictionary, previous: Dictionary, current: Dictionary) -> void:
	var pair := _motion_pair_budget(previous, current)
	state["last_motion_pair"] = pair.duplicate(true)
	if not bool(pair.get("valid", false)):
		state["invalid_motion_authority_count"] = int(
			state.get("invalid_motion_authority_count", 0)) + 1
		_append_state_violation(state, "invalid_motion_authority_interval")
		return
	# Idle hold-to-hold frames are checked at a zero budget, but they do not prove
	# that a committed timed path was exercised. This counter is release evidence
	# only for a plan interval or an exact plan handoff.
	if str(pair.get("kind", "")) != "zero_speed_hold":
		state["bounded_step_count"] = int(
			state.get("bounded_step_count", 0)) + 1
	var logical_excess := maxf(0.0, float(pair.get("logical_step", INF)) \
		- float(pair.get("logical_bound", -INF)))
	var render_excess := maxf(0.0, float(pair.get("render_step", INF)) \
		- float(pair.get("render_bound", -INF)))
	state["max_logical_speed_excess"] = maxf(float(
		state.get("max_logical_speed_excess", 0.0)), logical_excess)
	state["max_render_speed_excess"] = maxf(float(
		state.get("max_render_speed_excess", 0.0)), render_excess)
	if logical_excess > MOTION_BUDGET_EPSILON:
		_append_state_violation(
			state, "logical_position_local_speed_bound_exceeded")
	if render_excess > MOTION_BUDGET_EPSILON:
		_append_state_violation(
			state, "render_position_local_speed_bound_exceeded")


func _motion_pair_budget(previous: Dictionary, current: Dictionary) -> Dictionary:
	var t0 := float(previous.get("scheduler_tick", NAN))
	var t1 := float(current.get("scheduler_tick", NAN))
	var result := {
		"valid": false,
		"kind": "invalid",
		"dt": t1 - t0,
		"logical_step": (current.get(
			"logical_position", Vector3.INF) as Vector3).distance_to(
				previous.get("logical_position", Vector3.INF) as Vector3),
		"logical_bound": 0.0,
		"render_step": (current.get(
			"render_position", Vector3.INF) as Vector3).distance_to(
				previous.get("render_position", Vector3.INF) as Vector3),
		"render_bound": 0.0,
		"seam_count": 0,
	}
	if not is_finite(t0) or not is_finite(t1) or t1 < t0 - TICK_EPSILON:
		return result
	var old_authority := previous.get("motion_authority", {}) as Dictionary
	var new_authority := current.get("motion_authority", {}) as Dictionary
	if not _motion_authority_valid(old_authority) \
			or not _motion_authority_valid(new_authority):
		return result
	var old_phase := str(old_authority.get("phase", ""))
	var new_phase := str(new_authority.get("phase", ""))
	var old_plan := old_phase in ["ordinary", "external"]
	var new_plan := new_phase in ["ordinary", "external"]
	var old_key := str(old_authority.get("plan_key", ""))
	var new_key := str(new_authority.get("plan_key", ""))
	var logical_bound := 0.0
	var render_bound := 0.0
	var kind := "hold"
	var seam_count := 0
	if old_plan and new_plan and old_key == new_key \
			and (old_phase != new_phase \
				or not _motion_authorities_same_plan(
					old_authority, new_authority)):
		# A plan id is immutable. Reusing it for different geometry/timing is
		# neither continuation nor an authorized handoff.
		return result
	if old_plan and new_plan and old_phase == new_phase \
			and old_key == new_key \
			and _motion_authorities_same_plan(old_authority, new_authority):
		var budget := _motion_authority_budget(old_authority, t0, t1)
		if not bool(budget.get("valid", false)):
			return result
		logical_bound = float(budget.get("logical", 0.0))
		render_bound = float(budget.get("render", 0.0))
		kind = "%s_continuation" % old_phase
	elif not old_plan and not new_plan:
		kind = "zero_speed_hold"
	elif not old_plan and new_plan:
		var seam := float(new_authority.get("start_tick", NAN))
		if not _tick_in_interval(seam, t0, t1) \
				or not _sample_matches_motion_seam(previous, new_authority, seam):
			return result
		var budget := _motion_authority_budget(new_authority, seam, t1)
		if not bool(budget.get("valid", false)):
			return result
		logical_bound = float(budget.get("logical", 0.0))
		render_bound = float(budget.get("render", 0.0))
		kind = "hold_to_%s" % new_phase
		seam_count = 1
	elif old_plan and not new_plan:
		# A cancellation pins the old analytic plan at the new hold's sample tick;
		# a normal completion pins at the old end and may then remain stationary.
		var seam := minf(float(old_authority.get("end_tick", NAN)),
			float(new_authority.get("sample_tick", NAN)))
		if not _tick_in_interval(seam, t0, t1) \
				or not _tick_in_interval(seam,
					float(old_authority.get("start_tick", NAN)),
					float(old_authority.get("end_tick", NAN))) \
				or not _sample_matches_motion_seam(current, old_authority, seam):
			return result
		var budget := _motion_authority_budget(old_authority, t0, seam)
		if not bool(budget.get("valid", false)):
			return result
		logical_bound = float(budget.get("logical", 0.0))
		render_bound = float(budget.get("render", 0.0))
		kind = "%s_to_hold" % old_phase
		seam_count = 1
	else:
		var seam := float(new_authority.get("start_tick", NAN))
		if not _tick_in_interval(seam, t0, t1) \
				or not _tick_in_interval(seam,
					float(old_authority.get("start_tick", NAN)),
					float(old_authority.get("end_tick", NAN))) \
				or not _motion_authorities_share_seam(
					old_authority, new_authority, seam):
			return result
		var tail := _motion_authority_budget(old_authority, t0, seam)
		var head := _motion_authority_budget(new_authority, seam, t1)
		if not bool(tail.get("valid", false)) \
				or not bool(head.get("valid", false)):
			return result
		logical_bound = float(tail.get("logical", 0.0)) \
			+ float(head.get("logical", 0.0))
		render_bound = float(tail.get("render", 0.0)) \
			+ float(head.get("render", 0.0))
		kind = "%s_to_%s" % [old_phase, new_phase]
		seam_count = 1
	result["valid"] = true
	result["kind"] = kind
	result["logical_bound"] = logical_bound
	result["render_bound"] = render_bound
	result["seam_count"] = seam_count
	return result


func _motion_authority_valid(authority: Dictionary) -> bool:
	if str(authority.get("contract_id", "")) != MOTION_AUTHORITY_CONTRACT \
			or not bool(authority.get("valid", false)):
		return false
	var sample_tick := float(authority.get("sample_tick", NAN))
	var start_tick := float(authority.get("start_tick", NAN))
	var end_tick := float(authority.get("end_tick", NAN))
	if not is_finite(sample_tick) or not is_finite(start_tick) \
			or not is_finite(end_tick):
		return false
	var phase := str(authority.get("phase", ""))
	if int(authority.get("coord_map_id", -1)) != 0:
		return false
	if phase in ["settled", "route_hold"]:
		return absf(start_tick - sample_tick) <= TICK_EPSILON \
			and absf(end_tick - sample_tick) <= TICK_EPSILON \
			and (authority.get(
				"data_anchor", Vector3.INF) as Vector3).is_finite() \
			and (authority.get(
				"render_anchor", Vector3.INF) as Vector3).is_finite()
	if phase not in ["ordinary", "external"] \
			or str(authority.get("plan_key", "")).is_empty():
		return false
	if end_tick <= start_tick + TICK_EPSILON \
			or sample_tick < start_tick - TICK_EPSILON \
			or sample_tick > end_tick + TICK_EPSILON:
		return false
	var data_path := authority.get("data_path", []) as Array
	var render_path := authority.get("render_path", []) as Array
	if data_path.size() < 2 or render_path.size() != data_path.size():
		return false
	for point_v in data_path + render_path:
		if not (point_v is Vector3) or not (point_v as Vector3).is_finite():
			return false
	if phase == "ordinary":
		var break_ticks := authority.get("break_ticks", []) as Array
		if break_ticks.size() != data_path.size():
			return false
		for tick_v in break_ticks:
			if not is_finite(float(tick_v)):
				return false
		if absf(float(break_ticks[0]) - start_tick) > TICK_EPSILON \
				or absf(float(break_ticks.back()) - end_tick) > TICK_EPSILON:
			return false
		for index in range(1, break_ticks.size()):
			var span := float(break_ticks[index]) - float(break_ticks[index - 1])
			if span < 0.0 \
					or (span <= TICK_EPSILON \
						and ((data_path[index] as Vector3).distance_to(
							data_path[index - 1] as Vector3) > TICK_EPSILON \
						or (render_path[index] as Vector3).distance_to(
							render_path[index - 1] as Vector3) > TICK_EPSILON)):
				return false
		return true
	var cumulative := authority.get("path_cumulative", []) as Array
	var progress_start := float(authority.get("progress_start", NAN))
	if cumulative.size() != data_path.size() or not is_finite(progress_start) \
			or progress_start < 0.0 or progress_start >= 1.0:
		return false
	for scalar_v in cumulative:
		if not is_finite(float(scalar_v)):
			return false
	if absf(float(cumulative[0])) > TICK_EPSILON \
			or float(cumulative.back()) <= TICK_EPSILON:
		return false
	for index in range(1, cumulative.size()):
		var scalar_span := float(cumulative[index]) \
			- float(cumulative[index - 1])
		if scalar_span < 0.0 \
				or (scalar_span <= TICK_EPSILON \
					and ((data_path[index] as Vector3).distance_to(
						data_path[index - 1] as Vector3) > TICK_EPSILON \
					or (render_path[index] as Vector3).distance_to(
						render_path[index - 1] as Vector3) > TICK_EPSILON)):
			return false
	return true


func _motion_authority_budget(
		authority: Dictionary, from_tick: float, to_tick: float) -> Dictionary:
	if not _motion_authority_valid(authority) or to_tick < from_tick - TICK_EPSILON:
		return {"valid": false}
	var phase := str(authority.get("phase", ""))
	if phase == "ordinary":
		return {
			"valid": true,
			"logical": _ordinary_motion_budget(
				authority, from_tick, to_tick, false),
			"render": _ordinary_motion_budget(
				authority, from_tick, to_tick, true),
		}
	if phase == "external":
		return {
			"valid": true,
			"logical": _external_motion_budget(
				authority, from_tick, to_tick, false),
			"render": _external_motion_budget(
				authority, from_tick, to_tick, true),
		}
	return {"valid": true, "logical": 0.0, "render": 0.0}


func _ordinary_motion_budget(
		authority: Dictionary, from_tick: float, to_tick: float,
		render: bool) -> float:
	var path := authority.get(
		"render_path" if render else "data_path", []) as Array
	var ticks := authority.get("break_ticks", []) as Array
	var budget := 0.0
	for index in range(1, path.size()):
		var start := float(ticks[index - 1])
		var finish := float(ticks[index])
		var span := finish - start
		if span <= TICK_EPSILON:
			continue
		var overlap := maxf(0.0,
			minf(to_tick, finish) - maxf(from_tick, start))
		budget += (path[index] as Vector3).distance_to(
			path[index - 1] as Vector3) * overlap / span
	return budget


func _external_motion_budget(
		authority: Dictionary, from_tick: float, to_tick: float,
		render: bool) -> float:
	var path := authority.get(
		"render_path" if render else "data_path", []) as Array
	var cumulative := authority.get("path_cumulative", []) as Array
	var scalar_start := _external_motion_scalar(authority, from_tick)
	var scalar_end := _external_motion_scalar(authority, to_tick)
	var budget := 0.0
	for index in range(1, path.size()):
		var segment_start := float(cumulative[index - 1])
		var segment_end := float(cumulative[index])
		var span := segment_end - segment_start
		if span <= TICK_EPSILON:
			continue
		var overlap := maxf(0.0,
			minf(scalar_end, segment_end) - maxf(scalar_start, segment_start))
		budget += (path[index] as Vector3).distance_to(
			path[index - 1] as Vector3) * overlap / span
	return budget


func _external_motion_scalar(authority: Dictionary, tick: float) -> float:
	var start := float(authority.get("start_tick", tick))
	var finish := float(authority.get("end_tick", start))
	var progress_start := float(authority.get("progress_start", 0.0))
	var local := clampf((tick - start) / maxf(TICK_EPSILON, finish - start), 0.0, 1.0)
	var q := lerpf(progress_start, 1.0, local)
	var cumulative := authority.get("path_cumulative", []) as Array
	return q * float(cumulative.back())


func _motion_authority_position(
		authority: Dictionary, tick: float, render: bool) -> Vector3:
	var phase := str(authority.get("phase", ""))
	if phase in ["settled", "route_hold"]:
		return authority.get(
			"render_anchor" if render else "data_anchor", Vector3.INF) as Vector3
	var path := authority.get(
		"render_path" if render else "data_path", []) as Array
	if phase == "ordinary":
		var ticks := authority.get("break_ticks", []) as Array
		if tick <= float(ticks[0]):
			return path[0] as Vector3
		for index in range(1, path.size()):
			if tick <= float(ticks[index]) + TICK_EPSILON:
				var start := float(ticks[index - 1])
				var span := float(ticks[index]) - start
				var t := 1.0 if span <= TICK_EPSILON else clampf(
					(tick - start) / span, 0.0, 1.0)
				return (path[index - 1] as Vector3).lerp(
					path[index] as Vector3, t)
		return path.back() as Vector3
	var cumulative := authority.get("path_cumulative", []) as Array
	var scalar := _external_motion_scalar(authority, tick)
	for index in range(1, path.size()):
		if scalar <= float(cumulative[index]) + TICK_EPSILON:
			var start := float(cumulative[index - 1])
			var span := float(cumulative[index]) - start
			var t := 1.0 if span <= TICK_EPSILON else clampf(
				(scalar - start) / span, 0.0, 1.0)
			return (path[index - 1] as Vector3).lerp(path[index] as Vector3, t)
	return path.back() as Vector3


func _sample_matches_motion_seam(
		sample_value: Dictionary, authority: Dictionary, tick: float) -> bool:
	return (sample_value.get("logical_position", Vector3.INF) as Vector3).distance_to(
		_motion_authority_position(authority, tick, false)) \
		<= MOTION_SEAM_TOLERANCE \
		and (sample_value.get("render_position", Vector3.INF) as Vector3).distance_to(
			_motion_authority_position(authority, tick, true)) \
		<= MOTION_SEAM_TOLERANCE


func _motion_authorities_share_seam(
		old_authority: Dictionary, new_authority: Dictionary, tick: float) -> bool:
	return _motion_authority_position(old_authority, tick, false).distance_to(
		_motion_authority_position(new_authority, tick, false)) \
		<= MOTION_SEAM_TOLERANCE \
		and _motion_authority_position(old_authority, tick, true).distance_to(
			_motion_authority_position(new_authority, tick, true)) \
		<= MOTION_SEAM_TOLERANCE


func _motion_authorities_same_plan(
		old_authority: Dictionary, new_authority: Dictionary) -> bool:
	if str(old_authority.get("phase", "")) \
			!= str(new_authority.get("phase", "")) \
			or str(old_authority.get("plan_key", "")) \
				!= str(new_authority.get("plan_key", "")) \
			or absf(float(old_authority.get("start_tick", NAN)) \
				- float(new_authority.get("start_tick", NAN))) > TICK_EPSILON \
			or absf(float(old_authority.get("end_tick", NAN)) \
				- float(new_authority.get("end_tick", NAN))) > TICK_EPSILON \
			or int(old_authority.get("coord_map_id", -1)) \
				!= int(new_authority.get("coord_map_id", -1)):
		return false
	if not _motion_vector_arrays_match(
			old_authority.get("data_path", []) as Array,
			new_authority.get("data_path", []) as Array) \
			or not _motion_vector_arrays_match(
				old_authority.get("render_path", []) as Array,
				new_authority.get("render_path", []) as Array):
		return false
	if str(old_authority.get("phase", "")) == "ordinary":
		return _motion_number_arrays_match(
			old_authority.get("break_ticks", []) as Array,
			new_authority.get("break_ticks", []) as Array)
	return absf(float(old_authority.get("progress_start", NAN)) \
			- float(new_authority.get("progress_start", NAN))) <= TICK_EPSILON \
		and _motion_number_arrays_match(
			old_authority.get("path_cumulative", []) as Array,
			new_authority.get("path_cumulative", []) as Array)


func _motion_vector_arrays_match(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not (left[index] is Vector3) or not (right[index] is Vector3) \
				or (left[index] as Vector3).distance_to(
					right[index] as Vector3) > TICK_EPSILON:
			return false
	return true


func _motion_number_arrays_match(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not is_finite(float(left[index])) or not is_finite(float(right[index])) \
				or absf(float(left[index]) - float(right[index])) > TICK_EPSILON:
			return false
	return true


func _tick_in_interval(tick: float, start: float, finish: float) -> bool:
	return is_finite(tick) and tick >= start - TICK_EPSILON \
		and tick <= finish + TICK_EPSILON


func _validate_sample_authority_parity(
		state: Dictionary, sample_value: Dictionary) -> void:
	var declared_bound := float(sample_value.get(
		"declared_local_speed_bound", -1.0))
	var motion_authority := sample_value.get("motion_authority", {}) as Dictionary
	var motion_phase := str(motion_authority.get("phase", ""))
	if declared_bound < 0.0 \
			or (motion_phase in ["ordinary", "external"] \
				and declared_bound <= 0.0):
		_append_state_violation(state, "missing_or_nonpositive_local_speed_bound")
	for reason in _sample_motion_authority_violations(sample_value):
		_append_state_violation(state, reason)
	if not bool(sample_value.get(
			"logical_to_render_projection_valid", false)) \
			or float(sample_value.get(
				"logical_to_render_projection_error", INF)) \
				> DEFAULT_PROJECTION_TOLERANCE:
		_append_state_violation(state, "logical_render_projection_diverged")
	var render := sample_value.get("render_position", Vector3.INF) as Vector3
	if (sample_value.get("presented_position", Vector3.INF) as Vector3).distance_to(
			render) > DEFAULT_TRANSFORM_TOLERANCE:
		_append_state_violation(state, "global_position_diverged_from_render")
	if (sample_value.get(
			"presented_transform_origin", Vector3.INF) as Vector3).distance_to(
			render) > DEFAULT_TRANSFORM_TOLERANCE:
		_append_state_violation(state, "global_transform_origin_diverged_from_render")


func _sample_motion_authority_violations(sample_value: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	var authority := sample_value.get("motion_authority", {}) as Dictionary
	if not _motion_authority_valid(authority):
		violations.append("invalid_motion_authority_sample")
		return violations
	var scheduler_tick := float(sample_value.get("scheduler_tick", NAN))
	var authority_tick := float(authority.get("sample_tick", NAN))
	if not is_finite(scheduler_tick) or not is_finite(authority_tick) \
			or absf(authority_tick - scheduler_tick) > TICK_EPSILON:
		violations.append("motion_authority_sample_tick_mismatch")
	var phase := str(authority.get("phase", ""))
	var in_flight := bool(sample_value.get("in_flight", false))
	if in_flight != (phase != "settled"):
		violations.append("invalid_motion_authority_sample")
	var expected_logical := Vector3.INF
	var expected_render := Vector3.INF
	if phase in ["ordinary", "external"]:
		expected_logical = _motion_authority_position(
			authority, authority_tick, false)
		expected_render = _motion_authority_position(
			authority, authority_tick, true)
	else:
		expected_logical = authority.get("data_anchor", Vector3.INF) as Vector3
		expected_render = authority.get("render_anchor", Vector3.INF) as Vector3
	if not expected_logical.is_finite() \
			or (sample_value.get(
				"logical_position", Vector3.INF) as Vector3).distance_to(
				expected_logical) > MOTION_SAMPLE_POSITION_TOLERANCE:
		violations.append("logical_position_not_on_committed_motion_plan")
	if not expected_render.is_finite() \
			or (sample_value.get(
				"render_position", Vector3.INF) as Vector3).distance_to(
				expected_render) > MOTION_SAMPLE_POSITION_TOLERANCE:
		violations.append("render_position_not_on_committed_motion_plan")
	return violations


func _append_state_violation(state: Dictionary, reason: String) -> void:
	var violations := state.get("violations", []) as Array
	if not violations.has(reason):
		violations.append(reason)


static func _vector3_from(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Dictionary:
		var dictionary := value as Dictionary
		if dictionary.has("x") and dictionary.has("y") and dictionary.has("z"):
			var vector := Vector3(
				float(dictionary.get("x", NAN)),
				float(dictionary.get("y", NAN)),
				float(dictionary.get("z", NAN)))
			return vector if vector.is_finite() else Vector3.INF
	if value is Array and (value as Array).size() == 3:
		var array := value as Array
		var vector := Vector3(float(array[0]), float(array[1]), float(array[2]))
		return vector if vector.is_finite() else Vector3.INF
	return Vector3.INF
