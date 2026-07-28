class_name PatrolRouteBeacon
extends Node

## Save-authoritative receiver for an authored patrol-route intervention.
##
## TypedTerminal owns the physical interaction. This object first commits the consumed terminal
## receipt, alternate route, and per-enemy handoff phase to GameState. It then lets each enemy
## finish its already-committed movement leg before changing it through the public patrol API.

signal route_applied(state: Dictionary)
signal enemy_route_reconciled(enemy_id: String, route_id: String)
signal authority_rejected(reason: String)

const STATE_CONTRACT := "patrol_route_beacon/v1"
const AUTHORITY_VERSION := 1
const AUTHORITY_PREFIX := "gameplay:patrol_route_beacon:"
const TERMINAL_CONTRACT := "typed_terminal/v1"
const TERMINAL_ID_PREFIX := "typed_terminal:"
const TERMINAL_KEY_PREFIX := "gameplay:typed_terminal:"
const ENEMY_KEY_PREFIX := "runtime:enemy:"
const EXPECTED_FAMILY := "terminal"
const EXPECTED_SUBTYPE := "route"
const EXPECTED_EFFECT := "reroute"
const POSITION_EPSILON := 0.05
const TICK_EPSILON := 0.000001

var _game_state: GameState
var _beacon_id := ""
var _routes: Array[Dictionary] = []
var _enemies := {}
var _configured := false
var _restoring := false
var _last_restore_valid := true
var _last_reconciled: Array[String] = []
var _last_pending: Array[String] = []


## Assignment shape: `{enemy_id: String, route_id: String, points: Array[Vector3]}`.
func configure(
		game_state: GameState,
		beacon_id: String,
		authored_assignments: Array
	) -> bool:
	var normalized := _normalize_routes(authored_assignments)
	if game_state == null or beacon_id.strip_edges().is_empty() or normalized.is_empty():
		return false
	_disconnect_arrival()
	_game_state = game_state
	_beacon_id = beacon_id.strip_edges()
	_routes = normalized
	_enemies.clear()
	_configured = true
	_connect_arrival()
	return sync_from_game_state()


## Bind by Enemy.char_id. An applied save immediately reconciles a late-bound presenter.
func bind_enemy(enemy: Enemy) -> bool:
	if not _configured or enemy == null or not is_instance_valid(enemy):
		return false
	var enemy_id := str(enemy.char_id)
	if enemy_id.is_empty() or _authored_route(enemy_id).is_empty():
		return false
	_enemies[enemy_id] = enemy
	var saved := _saved()
	if _valid_saved(saved):
		_reconcile_route(_saved_route(saved, enemy_id), false)
	elif _valid_reset(saved):
		_apply_or_restore_enemy(
			_route_in_list(saved.get("baseline_routes", []), enemy_id),
			false
		)
	return true


func unbind_enemy(enemy_id: String) -> void:
	_enemies.erase(enemy_id)


func authority_state_key() -> String:
	return AUTHORITY_PREFIX + _beacon_id if not _beacon_id.is_empty() else ""


## Pure receiver preflight. It accepts only the exact spent physical TypedTerminal receipt.
func can_accept_terminal_command(command: Dictionary) -> bool:
	if not _configured or not _authority_allows_command() or not _all_targets_ready():
		return false
	var normalized := _normalize_command(command)
	return not normalized.is_empty() and _live_source_matches(normalized)


## Sole consequence entry point. No actor-id or route-id activation helper is exposed.
func accept_terminal_command(command: Dictionary) -> bool:
	if not can_accept_terminal_command(command):
		return false
	var receipt := _normalize_command(command)
	var baseline_routes := _capture_baseline_routes()
	if baseline_routes.is_empty():
		return false
	var applied_routes := _portable_routes()
	for route in applied_routes:
		route["handoff"] = "pending"
	var record := {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"beacon_id": _beacon_id,
		"phase": "route_applied",
		"actor": str(receipt.get("actor", "")),
		"accepted_tick": float(receipt.get("accepted_tick", 0.0)),
		"receipt_provenance": _receipt_provenance(receipt),
		"applied_routes": applied_routes,
		"baseline_routes": baseline_routes,
	}
	# A signal-time save now has the complete consequence, even before any enemy is touched.
	_game_state.set_world_state(authority_state_key(), record)
	_reconcile_record(record, true)
	route_applied.emit(get_state())
	return true


## Checkpoint reset. The reset record is published before Enemy is touched, so a save raised from
## that edge restores the original patrols instead of retaining a half-reset assignment.
func reset_assignment(reason: StringName = &"checkpoint_reset") -> bool:
	var saved := _saved()
	if not _valid_saved(saved):
		return false
	var baseline := (saved.get("baseline_routes", []) as Array).duplicate(true)
	var record := {
		"contract": STATE_CONTRACT,
		"version": AUTHORITY_VERSION,
		"beacon_id": _beacon_id,
		"phase": "reset",
		"reset_reason": str(reason),
		"reset_tick": _scheduler_tick(),
		"baseline_routes": baseline,
	}
	_game_state.set_world_state(authority_state_key(), record)
	return _reconcile_reset(record)


func on_game_state_snapshot_restored() -> bool:
	return sync_from_game_state()


func sync_from_game_state() -> bool:
	_last_reconciled.clear()
	_last_pending.clear()
	_connect_arrival()
	if not _configured:
		_last_restore_valid = false
		return false
	var saved := _saved()
	if saved.is_empty():
		_last_restore_valid = true
		return true
	if _valid_reset(saved):
		_last_restore_valid = true
		_restoring = true
		_reconcile_reset(saved)
		_restoring = false
		# Scene construction may call configure before binding its Enemy presenters. The reset record
		# is still valid; each later bind repairs that one baseline route.
		return true
	if not _valid_saved(saved):
		_last_restore_valid = false
		authority_rejected.emit("invalid_saved_authority")
		return false
	_last_restore_valid = true
	_restoring = true
	_reconcile_record(saved, false)
	_restoring = false
	# A pending handoff is a valid restored phase, not a failed reconciliation. The existing
	# GameState movement and character_arrived edge still own its deterministic completion.
	return true


func is_applied() -> bool:
	return _valid_saved(_saved())


## Stable QA surface: pending means an old movement leg still owns the enemy; authoritative means
## the alternate route is both committed and reflected by Enemy's own GameState record.
func get_state() -> Dictionary:
	var saved := _saved()
	var valid := _valid_saved(saved)
	var reset_valid := _valid_reset(saved)
	var phase := "dormant"
	if not saved.is_empty():
		phase = "route_applied" if valid else ("reset" if reset_valid else "invalid_authority")
	var statuses: Array[Dictionary] = []
	for route in _routes:
		var enemy_id := str(route.get("enemy_id", ""))
		statuses.append({
			"enemy_id": enemy_id,
			"route_id": str(route.get("route_id", "")),
			"status": _route_status(saved, enemy_id, valid),
		})
	return {
		"contract": STATE_CONTRACT,
		"configured": _configured,
		"beacon_id": _beacon_id,
		"authority_key": authority_state_key(),
		"phase": phase,
		"actor": str(saved.get("actor", "")) if valid else "",
		"accepted_tick": float(saved.get("accepted_tick", -1.0)) if valid else -1.0,
		"receipt_provenance": (
			(saved.get("receipt_provenance", {}) as Dictionary).duplicate(true)
			if valid else {}
		),
		"applied_routes": (
			(saved.get("applied_routes", []) as Array).duplicate(true) if valid else []
		),
		"baseline_routes": (
			(saved.get("baseline_routes", []) as Array).duplicate(true)
			if valid or reset_valid else []
		),
		"reset_reason": str(saved.get("reset_reason", "")) if reset_valid else "",
		"authored_routes": _portable_routes(),
		"bound_enemy_ids": _bound_enemy_ids(),
		"route_statuses": statuses,
		"last_restore_valid": _last_restore_valid,
		"last_reconciled_ids": _last_reconciled.duplicate(),
		"last_pending_ids": _last_pending.duplicate(),
	}


func _normalize_routes(assignments: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var seen := {}
	for value in assignments:
		if not value is Dictionary:
			return []
		var spec := value as Dictionary
		var enemy_id := str(spec.get("enemy_id", "")).strip_edges()
		var route_id := str(spec.get("route_id", "")).strip_edges()
		var points := _vectors(spec.get("points", []))
		if enemy_id.is_empty() or route_id.is_empty() or points.size() < 2:
			return []
		if seen.has(enemy_id):
			return []
		seen[enemy_id] = true
		normalized.append({"enemy_id": enemy_id, "route_id": route_id, "points": points})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("enemy_id", "")) < str(b.get("enemy_id", ""))
	)
	return normalized


func _vectors(value: Variant) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not value is Array:
		return points
	for raw_point in value as Array:
		var point := _vector(raw_point)
		if not point.is_finite():
			return []
		points.append(point)
	return points


func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)


func _portable_routes() -> Array[Dictionary]:
	var portable: Array[Dictionary] = []
	for route in _routes:
		var points: Array = []
		for value in route.get("points", []) as Array:
			var point := value as Vector3
			points.append([point.x, point.y, point.z])
		portable.append({
			"enemy_id": str(route.get("enemy_id", "")),
			"route_id": str(route.get("route_id", "")),
			"points": points,
		})
	return portable


func _authored_route(enemy_id: String) -> Dictionary:
	for route in _routes:
		if str(route.get("enemy_id", "")) == enemy_id:
			return route
	return {}


func _saved_route(saved: Dictionary, enemy_id: String) -> Dictionary:
	for value in saved.get("applied_routes", []) as Array:
		if value is Dictionary and str(value.get("enemy_id", "")) == enemy_id:
			return value as Dictionary
	return {}


func _normalize_command(command: Dictionary) -> Dictionary:
	if str(command.get("family", "")) != EXPECTED_FAMILY \
			or str(command.get("subtype", "")) != EXPECTED_SUBTYPE \
			or str(command.get("effect", "")) != EXPECTED_EFFECT:
		return {}
	var source_id := str(command.get("source_id", ""))
	var source_key := str(command.get("source_authority_key", ""))
	var actor := str(command.get("actor", ""))
	var trigger_count := int(command.get("source_trigger_count", 0))
	var source_position := _vector(command.get("source_position", []))
	var accepted_tick := float(command.get("accepted_tick", -1.0))
	if not source_id.begins_with(TERMINAL_ID_PREFIX) \
			or source_id.length() <= TERMINAL_ID_PREFIX.length():
		return {}
	var stable_id := source_id.trim_prefix(TERMINAL_ID_PREFIX)
	if source_key != TERMINAL_KEY_PREFIX + stable_id \
			or actor.is_empty() or trigger_count <= 0 \
			or not source_position.is_finite() \
			or not is_finite(accepted_tick) or accepted_tick < 0.0:
		return {}
	return {
		"family": EXPECTED_FAMILY,
		"subtype": EXPECTED_SUBTYPE,
		"effect": EXPECTED_EFFECT,
		"source_id": source_id,
		"source_authority_key": source_key,
		"source_trigger_count": trigger_count,
		"actor": actor,
		"source_position": [source_position.x, source_position.y, source_position.z],
		"accepted_tick": accepted_tick,
	}


func _receipt_provenance(command: Dictionary) -> Dictionary:
	var receipt := command.duplicate(true)
	receipt["source_contract"] = TERMINAL_CONTRACT
	return receipt


func _live_source_matches(command: Dictionary) -> bool:
	var actor := str(command.get("actor", ""))
	var source_id := str(command.get("source_id", ""))
	if not _game_state.characters.has(actor) or not _game_state.has_interactable(source_id):
		return false
	var source := _game_state.get_interactable(source_id)
	if not _registry_receipt_matches(source, command, actor):
		return false
	var source_pos := _vector(command.get("source_position", []))
	var registered_pos := _vector(source.get("position", Vector3(INF, INF, INF)))
	if source_pos.distance_to(registered_pos) > POSITION_EPSILON:
		return false
	var radius := maxf(0.0, float(source.get("radius", 0.0)))
	if _game_state.get_position(actor).distance_to(registered_pos) > radius + POSITION_EPSILON:
		return false
	if _game_state.scheduler == null:
		return false
	var now := float(_game_state.scheduler.get_current_tick())
	return absf(float(command.get("accepted_tick", -1.0)) - now) <= TICK_EPSILON \
		and _source_authority_matches(command)


func _registry_receipt_matches(
		source: Dictionary,
		command: Dictionary,
		actor: String
	) -> bool:
	return bool(source.get("one_shot", false)) \
		and bool(source.get("triggered", false)) \
		and not bool(source.get("enabled", true)) \
		and int(source.get("trigger_count", 0)) \
			== int(command.get("source_trigger_count", -1)) \
		and str(source.get("last_trigger_character", "")) == actor


func _source_authority_matches(command: Dictionary) -> bool:
	var key := str(command.get("source_authority_key", ""))
	var value: Variant = _game_state.get_world_state(key, {})
	if not value is Dictionary:
		return false
	var source := value as Dictionary
	if str(source.get("contract", "")) != TERMINAL_CONTRACT:
		return false
	var receipt: Variant = source
	for candidate in ["command", "accepted_command", "receipt", "last_command"]:
		if source.get(candidate, null) is Dictionary:
			receipt = source[candidate]
			break
	if not receipt is Dictionary:
		return false
	var normalized := _normalize_command(receipt as Dictionary)
	return not normalized.is_empty() and normalized == command


func _all_targets_ready() -> bool:
	for route in _routes:
		var enemy_id := str(route.get("enemy_id", ""))
		var enemy: Variant = _enemies.get(enemy_id)
		if not enemy is Enemy or not is_instance_valid(enemy):
			return false
		if not _game_state.characters.has(enemy_id) or not _valid_enemy_authority(enemy_id):
			return false
	return true


func _authority_allows_command() -> bool:
	var saved := _saved()
	return saved.is_empty() or _valid_reset(saved)


func _capture_baseline_routes() -> Array[Dictionary]:
	var baseline: Array[Dictionary] = []
	for route in _routes:
		var enemy_id := str(route.get("enemy_id", ""))
		var value: Variant = _game_state.get_world_state(ENEMY_KEY_PREFIX + enemy_id, {})
		if not value is Dictionary:
			return []
		var enemy_saved := value as Dictionary
		if str(enemy_saved.get("home_mode", "")) != "patrol":
			return []
		var points: Variant = enemy_saved.get("patrol_waypoints", [])
		if _vectors(points).size() < 2:
			return []
		baseline.append({
			"enemy_id": enemy_id,
			"route_id": "baseline:%s" % enemy_id,
			"points": (points as Array).duplicate(true),
		})
	return baseline


func _saved() -> Dictionary:
	if not _configured or _game_state == null:
		return {}
	var value: Variant = _game_state.get_world_state(authority_state_key(), {})
	return value as Dictionary if value is Dictionary else {}


func _valid_saved(saved: Dictionary) -> bool:
	if saved.is_empty() or str(saved.get("contract", "")) != STATE_CONTRACT \
			or int(saved.get("version", 0)) != AUTHORITY_VERSION \
			or str(saved.get("beacon_id", "")) != _beacon_id \
			or str(saved.get("phase", "")) != "route_applied":
		return false
	var provenance: Variant = saved.get("receipt_provenance", {})
	if not provenance is Dictionary:
		return false
	var command := _normalize_command(provenance as Dictionary)
	if command.is_empty() \
			or str(provenance.get("source_contract", "")) != TERMINAL_CONTRACT:
		return false
	if str(saved.get("actor", "")) != str(command.get("actor", "")) \
			or not is_equal_approx(
		float(saved.get("accepted_tick", -1.0)),
		float(command.get("accepted_tick", -2.0))
		):
		return false
	return _saved_routes_match(saved.get("applied_routes", [])) \
		and _valid_baseline_routes(saved.get("baseline_routes", []))


func _valid_reset(saved: Dictionary) -> bool:
	if saved.is_empty() or str(saved.get("contract", "")) != STATE_CONTRACT:
		return false
	if int(saved.get("version", 0)) != AUTHORITY_VERSION:
		return false
	if str(saved.get("beacon_id", "")) != _beacon_id:
		return false
	if str(saved.get("phase", "")) != "reset":
		return false
	if not is_finite(float(saved.get("reset_tick", -1.0))):
		return false
	return _valid_baseline_routes(saved.get("baseline_routes", []))


func _valid_baseline_routes(value: Variant) -> bool:
	if not value is Array or value.size() != _routes.size():
		return false
	var seen := {}
	for raw_route in value as Array:
		if not raw_route is Dictionary:
			return false
		var route := raw_route as Dictionary
		var enemy_id := str(route.get("enemy_id", ""))
		if _authored_route(enemy_id).is_empty() or seen.has(enemy_id):
			return false
		if str(route.get("route_id", "")) != "baseline:%s" % enemy_id:
			return false
		if _vectors(route.get("points", [])).size() < 2:
			return false
		seen[enemy_id] = true
	return true


func _saved_routes_match(value: Variant) -> bool:
	if not value is Array:
		return false
	var saved_routes := value as Array
	var authored := _portable_routes()
	if saved_routes.size() != authored.size():
		return false
	for index in range(authored.size()):
		if not _saved_route_matches(saved_routes[index], authored[index]):
			return false
	return true


func _saved_route_matches(saved_value: Variant, expected: Dictionary) -> bool:
	if not saved_value is Dictionary:
		return false
	var saved := saved_value as Dictionary
	return str(saved.get("enemy_id", "")) == str(expected.get("enemy_id", "")) \
		and str(saved.get("route_id", "")) == str(expected.get("route_id", "")) \
		and str(saved.get("handoff", "")) in ["pending", "applied"] \
		and _points_equal(saved.get("points", []), expected.get("points", []))


func _points_equal(left_value: Variant, right_value: Variant) -> bool:
	if not left_value is Array or not right_value is Array:
		return false
	var left := left_value as Array
	var right := right_value as Array
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		var left_point := _vector(left[index])
		var right_point := _vector(right[index])
		if not left_point.is_finite() or not left_point.is_equal_approx(right_point):
			return false
	return true


func _reconcile_record(saved: Dictionary, emit_signal: bool) -> bool:
	var complete := true
	for value in saved.get("applied_routes", []) as Array:
		var route := value as Dictionary
		if not _reconcile_route(route, emit_signal):
			complete = false
			var enemy_id := str(route.get("enemy_id", ""))
			if not _last_pending.has(enemy_id):
				_last_pending.append(enemy_id)
	return complete


func _reconcile_reset(saved: Dictionary) -> bool:
	var complete := true
	for value in saved.get("baseline_routes", []) as Array:
		var route := value as Dictionary
		if not _apply_or_restore_enemy(route, false):
			complete = false
			var enemy_id := str(route.get("enemy_id", ""))
			if not _last_pending.has(enemy_id):
				_last_pending.append(enemy_id)
	return complete


func _reconcile_route(route: Dictionary, emit_signal: bool) -> bool:
	var enemy_id := str(route.get("enemy_id", ""))
	if str(route.get("handoff", "")) == "pending":
		if _game_state.is_moving(enemy_id):
			return false
		return _commit_handoff(enemy_id, emit_signal)
	return _apply_or_restore_enemy(route, emit_signal)


## Commit the handoff before invoking Enemy, closing the arrival-callback save seam.
func _commit_handoff(enemy_id: String, emit_signal: bool) -> bool:
	var saved := _saved().duplicate(true)
	if not _valid_saved(saved):
		return false
	var changed := false
	for route in saved.get("applied_routes", []) as Array:
		if str(route.get("enemy_id", "")) == enemy_id and route.get("handoff") == "pending":
			route["handoff"] = "applied"
			changed = true
			break
	if changed:
		_game_state.set_world_state(authority_state_key(), saved)
	return _apply_or_restore_enemy(_saved_route(saved, enemy_id), emit_signal)


func _apply_or_restore_enemy(route: Dictionary, emit_signal: bool) -> bool:
	var enemy_id := str(route.get("enemy_id", ""))
	var value: Variant = _enemies.get(enemy_id)
	if not value is Enemy or not is_instance_valid(value):
		return false
	if not _game_state.characters.has(enemy_id):
		return false
	var enemy := value as Enemy
	if _enemy_route_matches(enemy_id, route):
		if _restoring:
			enemy.on_game_state_snapshot_restored()
		return true
	return _apply_route_now(route, emit_signal)


func _apply_route_now(route: Dictionary, emit_signal: bool) -> bool:
	var enemy_id := str(route.get("enemy_id", ""))
	var value: Variant = _enemies.get(enemy_id)
	if not value is Enemy or not is_instance_valid(value):
		return false
	if not _game_state.characters.has(enemy_id):
		return false
	var enemy := value as Enemy
	var points := _vectors(route.get("points", []))
	if points.size() < 2:
		return false
	enemy.configure_patrol(points)
	enemy.begin_home_behavior()
	if not _enemy_route_matches(enemy_id, route):
		return false
	if not _last_reconciled.has(enemy_id):
		_last_reconciled.append(enemy_id)
	if emit_signal:
		enemy_route_reconciled.emit(enemy_id, str(route.get("route_id", "")))
	return true


func _scheduler_tick() -> float:
	if _game_state != null and _game_state.scheduler != null:
		return float(_game_state.scheduler.get_current_tick())
	return 0.0


func _valid_enemy_authority(enemy_id: String) -> bool:
	var value: Variant = _game_state.get_world_state(ENEMY_KEY_PREFIX + enemy_id, {})
	if not value is Dictionary:
		return false
	var saved := value as Dictionary
	return int(saved.get("version", 0)) > 0 and str(saved.get("char_id", "")) == enemy_id


func _enemy_route_matches(enemy_id: String, route: Dictionary) -> bool:
	var value: Variant = _game_state.get_world_state(ENEMY_KEY_PREFIX + enemy_id, {})
	if not value is Dictionary:
		return false
	var saved := value as Dictionary
	if str(saved.get("char_id", "")) != enemy_id:
		return false
	if str(saved.get("home_mode", "")) != "patrol":
		return false
	return _points_equal(saved.get("patrol_waypoints", []), route.get("points", []))


func _route_status(saved: Dictionary, enemy_id: String, valid: bool) -> String:
	var value: Variant = _enemies.get(enemy_id)
	if not value is Enemy or not is_instance_valid(value):
		return "unbound"
	if not _game_state.characters.has(enemy_id):
		return "missing_character"
	if _valid_reset(saved):
		var baseline := _route_in_list(saved.get("baseline_routes", []), enemy_id)
		return "baseline" if _enemy_route_matches(enemy_id, baseline) else "needs_reset"
	if not valid:
		return "awaiting_command"
	var route := _saved_route(saved, enemy_id)
	if str(route.get("handoff", "")) == "pending":
		return "finishing_committed_leg"
	return "authoritative" if _enemy_route_matches(enemy_id, route) else "needs_reconcile"


func _route_in_list(routes_value: Variant, enemy_id: String) -> Dictionary:
	if not routes_value is Array:
		return {}
	for value in routes_value as Array:
		if value is Dictionary and str(value.get("enemy_id", "")) == enemy_id:
			return value as Dictionary
	return {}


func _bound_enemy_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id in _enemies.keys():
		var enemy_id := str(raw_id)
		var enemy: Variant = _enemies.get(enemy_id)
		if enemy is Enemy and is_instance_valid(enemy):
			ids.append(enemy_id)
	ids.sort()
	return ids


func _connect_arrival() -> void:
	if _game_state != null and not _game_state.character_arrived.is_connected(_on_character_arrived):
		_game_state.character_arrived.connect(_on_character_arrived)


func _disconnect_arrival() -> void:
	if _game_state != null and _game_state.character_arrived.is_connected(_on_character_arrived):
		_game_state.character_arrived.disconnect(_on_character_arrived)


func _on_character_arrived(enemy_id: String) -> void:
	if not _configured or _restoring:
		return
	var saved := _saved()
	if not _valid_saved(saved):
		return
	var route := _saved_route(saved, enemy_id)
	if not route.is_empty() and str(route.get("handoff", "")) == "pending":
		_commit_handoff(enemy_id, true)


func _exit_tree() -> void:
	_disconnect_arrival()
