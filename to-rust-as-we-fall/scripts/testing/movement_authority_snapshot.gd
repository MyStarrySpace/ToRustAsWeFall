class_name MovementAuthoritySnapshot
extends RefCounted

## Testing-only readback of the already-committed movement authority. It never
## issues commands or changes gameplay. The continuity tracker consumes this
## snapshot without depending on GameState internals.

const CONTRACT_ID := "movement_authority/v1"
const EPSILON := 0.000001


static func capture(
		game_state, character_id: String,
		logical_position: Vector3, render_position: Vector3) -> Dictionary:
	var tick: float = _scheduler_tick(game_state)
	var coord_map = game_state.coord_map if game_state != null else null
	var identity_projection: bool = coord_map == null
	var route_active: bool = game_state != null \
		and game_state.has_method("is_navigation_route_active") \
		and bool(game_state.call("is_navigation_route_active", character_id))
	var hold := {
		"contract_id": CONTRACT_ID,
		"valid": game_state != null and identity_projection \
			and logical_position.is_finite() \
			and render_position.is_finite() and is_finite(tick),
		"phase": "route_hold" if route_active else "settled",
		"plan_key": "",
		"sample_tick": tick,
		"route_active": route_active,
		"start_tick": tick,
		"end_tick": tick,
		"data_anchor": logical_position,
		"render_anchor": render_position,
		"data_path": [],
		"render_path": [],
		"break_ticks": [],
		"path_cumulative": [],
		"progress_start": 0.0,
		"coord_map_id": 0 if identity_projection \
			else int(coord_map.get_instance_id()),
	}
	if game_state == null or not game_state.characters.has(character_id):
		hold["valid"] = false
		return hold
	if game_state.is_external_traversal_active(character_id):
		var traversal := game_state.get_external_traversal_state(
			character_id) as Dictionary
		var data_path := (traversal.get("data_path", []) as Array).duplicate()
		var render_path := (traversal.get("render_path", []) as Array).duplicate()
		var cumulative := (traversal.get(
			"path_cumulative", []) as Array).duplicate()
		var start_tick := float(traversal.get("start_tick", NAN))
		var end_tick := float(traversal.get("end_tick", NAN))
		var progress_start := float(traversal.get("progress_start", NAN))
		var traversal_id := str(traversal.get("traversal_id", ""))
		return {
			"contract_id": CONTRACT_ID,
			"valid": identity_projection and _path_is_finite(data_path) \
				and _path_is_finite(render_path) \
				and data_path.size() >= 2 \
				and render_path.size() == data_path.size() \
				and _cumulative_is_valid(cumulative, data_path.size()) \
				and is_finite(start_tick) and is_finite(end_tick) \
				and end_tick > start_tick + EPSILON \
				and is_finite(progress_start) \
				and progress_start >= 0.0 and progress_start < 1.0 \
				and not traversal_id.is_empty(),
			"phase": "external",
			"plan_key": "external/%s/%.9f" % [
				traversal_id, start_tick],
			"sample_tick": tick,
			"route_active": route_active,
			"start_tick": start_tick,
			"end_tick": end_tick,
			"data_anchor": logical_position,
			"render_anchor": render_position,
			"data_path": data_path,
			"render_path": render_path,
			"break_ticks": [],
			"path_cumulative": cumulative,
			"progress_start": progress_start,
			"coord_map_id": 0 if identity_projection \
				else int(coord_map.get_instance_id()),
		}
	var character_state := game_state.characters.get(
		character_id, {}) as Dictionary
	var movement_v: Variant = character_state.get("movement", null)
	if not (movement_v is Dictionary):
		return hold
	var movement := movement_v as Dictionary
	var data_path := (movement.get("path", []) as Array).duplicate()
	var break_ticks := _ordinary_break_ticks(movement, data_path.size())
	var render_path := data_path.duplicate()
	var start_tick := float(break_ticks[0]) if not break_ticks.is_empty() else NAN
	var end_tick := float(break_ticks.back()) if not break_ticks.is_empty() else NAN
	return {
		"contract_id": CONTRACT_ID,
		# A generic nonlinear coord map has no declared derivative bound. Basin is
		# flat/identity; other maps fail closed until they publish one.
		"valid": identity_projection and _path_is_finite(data_path) \
			and data_path.size() >= 2 \
			and break_ticks.size() == data_path.size() \
			and _ordinary_segments_are_valid(data_path, break_ticks),
		"phase": "ordinary",
		"plan_key": "ordinary/%s/%.9f" % [
			str(movement.get("epoch", "missing")), start_tick],
		"sample_tick": tick,
		"route_active": route_active,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"data_anchor": logical_position,
		"render_anchor": render_position,
		"data_path": data_path,
		"render_path": render_path,
		"break_ticks": break_ticks,
		"path_cumulative": [],
		"progress_start": 0.0,
		"coord_map_id": 0 if identity_projection else int(coord_map.get_instance_id()),
	}


static func declared_speed_bound(authority: Dictionary) -> float:
	if not bool(authority.get("valid", false)):
		return -1.0
	var phase := str(authority.get("phase", ""))
	if phase in ["settled", "route_hold"]:
		return 0.0
	var data_path := authority.get("data_path", []) as Array
	var render_path := authority.get("render_path", []) as Array
	var bound := 0.0
	if phase == "ordinary":
		var ticks := authority.get("break_ticks", []) as Array
		for index in range(1, data_path.size()):
			var span := float(ticks[index]) - float(ticks[index - 1])
			if span <= EPSILON:
				continue
			bound = maxf(bound, (data_path[index] as Vector3).distance_to(
				data_path[index - 1] as Vector3) / span)
			bound = maxf(bound, (render_path[index] as Vector3).distance_to(
				render_path[index - 1] as Vector3) / span)
		return bound if bound > EPSILON else -1.0
	if phase != "external":
		return -1.0
	var cumulative := authority.get("path_cumulative", []) as Array
	var duration := float(authority.get("end_tick", 0.0)) \
		- float(authority.get("start_tick", 0.0))
	var progress_start := float(authority.get("progress_start", NAN))
	if not is_finite(progress_start) or progress_start < 0.0 \
			or progress_start >= 1.0:
		return -1.0
	var remaining_scale := 1.0 - progress_start
	var scalar_total := float(cumulative.back())
	for index in range(1, data_path.size()):
		var scalar_span := float(cumulative[index]) \
			- float(cumulative[index - 1])
		if scalar_span <= EPSILON:
			continue
		var scale := scalar_total * remaining_scale / (duration * scalar_span)
		bound = maxf(bound, (data_path[index] as Vector3).distance_to(
			data_path[index - 1] as Vector3) * scale)
		bound = maxf(bound, (render_path[index] as Vector3).distance_to(
			render_path[index - 1] as Vector3) * scale)
	return bound if bound > EPSILON and is_finite(bound) else -1.0


static func _scheduler_tick(game_state) -> float:
	if game_state == null or game_state.scheduler == null:
		return NAN
	return float(game_state.scheduler.get_current_tick())


static func _ordinary_break_ticks(movement: Dictionary, path_size: int) -> Array:
	var arrival := (movement.get("arrival_ticks", []) as Array).duplicate()
	if arrival.size() == path_size and _ticks_are_finite_nondecreasing(arrival):
		return arrival
	var cumulative := movement.get("cum_dist", []) as Array
	var total := float(movement.get("total_distance", 0.0))
	var start := float(movement.get("start_tick", NAN))
	var duration := float(movement.get("duration", NAN))
	if cumulative.size() != path_size or total <= EPSILON \
			or not is_finite(start) or not is_finite(duration) or duration <= 0.0:
		return []
	var derived: Array = []
	for distance_v in cumulative:
		derived.append(start + duration * float(distance_v) / total)
	return derived if _ticks_are_finite_nondecreasing(derived) else []


static func _path_is_finite(path: Array) -> bool:
	for point_v in path:
		if not (point_v is Vector3) or not (point_v as Vector3).is_finite():
			return false
	return true


static func _ticks_are_finite_nondecreasing(ticks: Array) -> bool:
	for index in range(ticks.size()):
		if not is_finite(float(ticks[index])) \
				or (index > 0 and float(ticks[index]) \
					< float(ticks[index - 1])):
			return false
	return true


static func _ordinary_segments_are_valid(path: Array, ticks: Array) -> bool:
	if not _ticks_are_finite_nondecreasing(ticks):
		return false
	for index in range(1, path.size()):
		var span := float(ticks[index]) - float(ticks[index - 1])
		if span <= EPSILON and (path[index] as Vector3).distance_to(
				path[index - 1] as Vector3) > EPSILON:
			return false
	return true


static func _cumulative_is_valid(cumulative: Array, expected_size: int) -> bool:
	if cumulative.size() != expected_size or expected_size < 2:
		return false
	for index in range(cumulative.size()):
		if not is_finite(float(cumulative[index])) \
				or (index > 0 and float(cumulative[index]) \
					< float(cumulative[index - 1])):
			return false
	return absf(float(cumulative[0])) <= EPSILON \
		and float(cumulative.back()) > EPSILON
