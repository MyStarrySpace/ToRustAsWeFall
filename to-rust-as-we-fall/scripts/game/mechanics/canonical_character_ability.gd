class_name CanonicalCharacterAbility
extends RefCounted

## Reusable mechanics for the currently implemented early-game GDD casts. Contextual verbs such
## as HACK, SCAN, TEND, and READ FLORA remain on their world targets. Later named canon such as
## Inflame, Barrier/Restore, and Suppress is deliberately not fabricated here before its runtime
## contract is authored.

const EMP_ID := "emp"
const WRAP_ID := "wrap"

const OWNER_BY_ABILITY := {
	EMP_ID: "aster",
	WRAP_ID: "peris",
}
const STAMINA_COST_BY_ABILITY := {
	EMP_ID: 25.0,
	WRAP_ID: 15.0,
}

# Provisional playtest tuning is intentionally centralized. The GDD commits the causal effects,
# not these values; moving them into authored balance data is a later tuning pass.
const EMP_CAST_RANGE := 9.0
const EMP_EFFECT_RADIUS := 5.5
const EMP_STUN_SECONDS := 3.0
const WRAP_CAST_RANGE := 9.0
const WRAP_ABSORPTION := 25.0
const WRAP_DURATION_SECONDS := 5.0
const EMP_VERTICAL_HALF_HEIGHT := 2.0

static func is_canonical(ability_id: String) -> bool:
	return OWNER_BY_ABILITY.has(ability_id)

static func owner_for(ability_id: String) -> String:
	return str(OWNER_BY_ABILITY.get(ability_id, ""))

static func stamina_cost(ability_id: String) -> float:
	return float(STAMINA_COST_BY_ABILITY.get(ability_id, 0.0))

static func target_prompt(ability_id: String) -> String:
	match ability_id:
		EMP_ID:
			return "EMP: click a point near Aster. EMP-compatible electronics inside the pulse will be disabled."
		WRAP_ID:
			return "WRAP: click a conscious character to give that target a temporary damage shield."
	return ""

static func cast_range(ability_id: String) -> float:
	match ability_id:
		EMP_ID:
			return EMP_CAST_RANGE
		WRAP_ID:
			return WRAP_CAST_RANGE
	return 0.0

static func nearest_party_target(
		game_state,
		party_ids: Array,
		world_pos: Vector3,
		pick_radius := 2.5,
		exclude_id := ""
	) -> String:
	if game_state == null:
		return ""
	var data_pos := _to_data_position(game_state, world_pos)
	var best_id := ""
	var best_distance := pick_radius
	for id_variant in party_ids:
		var char_id := str(id_variant)
		if char_id == exclude_id or not game_state.characters.has(char_id) \
				or game_state.is_downed(char_id):
			continue
		var distance := Vector2(
			game_state.get_position(char_id).x - data_pos.x,
			game_state.get_position(char_id).z - data_pos.z
		).length()
		if distance <= best_distance:
			best_distance = distance
			best_id = char_id
	return best_id

## The authoritative canonical cast transaction. Validation happens before any mutation. Once an
## effect accepts, its stamina cost is committed in the same call. GameState's canonical queue is
## the command/event boundary; this service deliberately performs only deterministic derived work.
##
## Options:
## - allowed_target_ids: conscious protectable targets authorized by the command context (WRAP)
## - party_ids: compatibility alias for allowed_target_ids
## - target_id: WRAP's selected ally
## - duration: effect-duration override (WRAP shield or EMP receiver disable)
## - world_root: runtime EMP receiver root (not serialized; replay still resolves simulation state)
## - target_is_data: target_pos is already in GameState/data coordinates
static func execute(
		game_state,
		ability_id: String,
		owner_id: String,
		target_pos: Vector3,
		options: Dictionary = {}
	) -> Dictionary:
	var validation := validate_cast(game_state, ability_id, owner_id, target_pos, options)
	if not bool(validation.get("accepted", false)):
		return validation

	var result: Dictionary
	match ability_id:
		EMP_ID:
			var pulse_pos := _to_world_position(game_state, target_pos) \
					if bool(options.get("target_is_data", false)) else target_pos
			var emp_duration := float(options.get("duration", EMP_STUN_SECONDS))
			result = _apply_emp(pulse_pos, options.get("world_root") as Node, emp_duration)
		WRAP_ID:
			var duration := float(options.get("duration", WRAP_DURATION_SECONDS))
			result = _apply_wrap(game_state, str(options.get("target_id", "")), duration)
		_:
			return {"accepted": false, "reason": "unknown_ability"}

	if not bool(result.get("accepted", false)):
		return result
	var cost := stamina_cost(ability_id)
	if not _spend_stamina(game_state, owner_id, cost):
		# This should be unreachable after validation in the single-threaded simulation. Keep WRAP
		# rollback explicit so a future effect cannot survive without its resource transaction.
		if ability_id == WRAP_ID:
			game_state.clear_damage_shield(str(options.get("target_id", "")))
		return {"accepted": false, "reason": "insufficient_stamina"}
	result["ability_id"] = ability_id
	result["owner_id"] = owner_id
	result["stamina_spent"] = cost
	result["stamina_remaining"] = game_state.get_stat(owner_id, "stamina")
	return result

## Pure preflight shared by immediate and auto-move casts. check_range=false is used while a
## valid out-of-range command is waiting for movement; execution always checks range again.
static func validate_cast(
		game_state,
		ability_id: String,
		owner_id: String,
		target_pos: Vector3,
		options: Dictionary = {},
		check_range := true
	) -> Dictionary:
	if not is_canonical(ability_id):
		return {"accepted": false, "reason": "unknown_ability"}
	if owner_id != owner_for(ability_id):
		return {"accepted": false, "reason": "wrong_owner"}
	if game_state == null or not game_state.characters.has(owner_id) \
			or game_state.is_downed(owner_id):
		return {"accepted": false, "reason": "invalid_owner"}
	var cost := stamina_cost(ability_id)
	if game_state.get_stat(owner_id, "stamina") + 0.0001 < cost:
		return {"accepted": false, "reason": "insufficient_stamina", "required": cost}

	if ability_id == WRAP_ID:
		var target_id := str(options.get("target_id", ""))
		var allowed_ids := _allowed_target_ids(options)
		if target_id == "" or not allowed_ids.has(target_id) \
				or not game_state.characters.has(target_id) or game_state.is_downed(target_id):
			return {"accepted": false, "reason": "invalid_target"}
		var duration := float(options.get("duration", WRAP_DURATION_SECONDS))
		if duration <= 0.0 or game_state.scheduler == null:
			return {"accepted": false, "reason": "invalid_duration"}
		if check_range and not _target_is_in_range(
				game_state, owner_id, game_state.get_position(target_id), WRAP_CAST_RANGE):
			return {"accepted": false, "reason": "out_of_range"}
	else:
		if float(options.get("duration", EMP_STUN_SECONDS)) <= 0.0:
			return {"accepted": false, "reason": "invalid_duration"}
		var data_target := target_pos if bool(options.get("target_is_data", false)) \
				else _to_data_position(game_state, target_pos)
		if not data_target.is_finite():
			return {"accepted": false, "reason": "invalid_target"}
		if check_range and not _target_is_in_range(
				game_state, owner_id, data_target, EMP_CAST_RANGE):
			return {"accepted": false, "reason": "out_of_range"}
	return {"accepted": true}

static func cast_emp(
		game_state,
		owner_id: String,
		target_pos: Vector3,
		world_root: Node
	) -> Dictionary:
	# Compatibility effect helper for callers that still own their resource transaction. New code
	# should queue through GameState.queue_canonical_ability(), which calls execute().
	var validation := _validate_legacy(
		game_state, EMP_ID, owner_id, target_pos, {"world_root": world_root})
	if not bool(validation.get("accepted", false)):
		return validation
	return _apply_emp(target_pos, world_root, EMP_STUN_SECONDS)

static func _apply_emp(target_pos: Vector3, world_root: Node, duration: float) -> Dictionary:
	var affected: Array[String] = []
	if world_root != null:
		for node in _descendants(world_root):
			if not (node is Node3D):
				continue
			var spatial := node as Node3D
			if absf(spatial.global_position.y - target_pos.y) > EMP_VERTICAL_HALF_HEIGHT:
				continue
			if Vector2(spatial.global_position.x - target_pos.x,
					spatial.global_position.z - target_pos.z).length() > EMP_EFFECT_RADIUS:
				continue
			var accepted := false
			# Electronic puzzle objects can opt in without this service knowing their class.
			if node.has_method("apply_emp"):
				accepted = bool(node.call("apply_emp", duration))
			if accepted:
				affected.append(str(node.get_path()))
	return {
		"accepted": true,
		"affected_count": affected.size(),
		"affected": affected,
		"target_pos": target_pos,
		"duration": duration,
	}

static func cast_wrap(
		game_state,
		owner_id: String,
		target_id: String,
		party_ids: Array,
		duration: float
	) -> Dictionary:
	# Compatibility effect helper; see cast_emp(). It enforces canonical owner and party-target rules,
	# but intentionally does not double-charge legacy callers that already subtract stamina.
	var validation := _validate_legacy(game_state, WRAP_ID, owner_id,
		Vector3.ZERO, {"target_id": target_id, "party_ids": party_ids, "duration": duration})
	if not bool(validation.get("accepted", false)):
		return validation
	return _apply_wrap(game_state, target_id, duration)

static func _apply_wrap(game_state, target_id: String, duration: float) -> Dictionary:
	var shielded: Array[String] = []
	if game_state.apply_damage_shield(target_id, WRAP_ABSORPTION, duration, WRAP_ID):
		shielded.append(target_id)
	return {
		"accepted": not shielded.is_empty(),
		"reason": "" if not shielded.is_empty() else "invalid_target",
		"target_id": target_id,
		"shielded": shielded,
		"absorption_each": WRAP_ABSORPTION,
	}

static func _target_is_in_range(
		game_state,
		owner_id: String,
		target_pos: Vector3,
		max_range: float
	) -> bool:
	if game_state == null or not game_state.characters.has(owner_id) or game_state.is_downed(owner_id):
		return false
	var owner_pos: Vector3 = game_state.get_position(owner_id)
	return Vector2(owner_pos.x - target_pos.x, owner_pos.z - target_pos.z).length() <= max_range

static func _to_data_position(game_state, world_pos: Vector3) -> Vector3:
	if game_state != null and game_state.coord_map != null \
			and game_state.coord_map.has_method("to_data"):
		return game_state.coord_map.to_data(world_pos)
	return world_pos

static func _to_world_position(game_state, data_pos: Vector3) -> Vector3:
	if game_state != null and game_state.coord_map != null \
			and game_state.coord_map.has_method("to_world"):
		return game_state.coord_map.to_world(data_pos)
	return data_pos

static func _validate_legacy(
		game_state,
		ability_id: String,
		owner_id: String,
		target_pos: Vector3,
		options: Dictionary
	) -> Dictionary:
	# Legacy helpers keep the same effect-only contract, but all structural validation is shared.
	var validation := validate_cast(game_state, ability_id, owner_id, target_pos, options)
	if str(validation.get("reason", "")) == "insufficient_stamina":
		# The legacy caller may already have paid. Re-run the non-resource checks with a temporary
		# affordable value avoided: spell those checks directly by using the canonical cost as a
		# virtual balance, without mutating GameState.
		return _validate_without_stamina(game_state, ability_id, owner_id, target_pos, options)
	return validation

static func _validate_without_stamina(
		game_state,
		ability_id: String,
		owner_id: String,
		target_pos: Vector3,
		options: Dictionary
	) -> Dictionary:
	if not is_canonical(ability_id):
		return {"accepted": false, "reason": "unknown_ability"}
	if owner_id != owner_for(ability_id):
		return {"accepted": false, "reason": "wrong_owner"}
	if game_state == null or not game_state.characters.has(owner_id) \
			or game_state.is_downed(owner_id):
		return {"accepted": false, "reason": "invalid_owner"}
	if ability_id == WRAP_ID:
		var target_id := str(options.get("target_id", ""))
		var allowed_ids := _allowed_target_ids(options)
		if target_id == "" or not allowed_ids.has(target_id) \
				or not game_state.characters.has(target_id) or game_state.is_downed(target_id):
			return {"accepted": false, "reason": "invalid_target"}
		if float(options.get("duration", WRAP_DURATION_SECONDS)) <= 0.0 \
				or game_state.scheduler == null:
			return {"accepted": false, "reason": "invalid_duration"}
		if not _target_is_in_range(
				game_state, owner_id, game_state.get_position(target_id), WRAP_CAST_RANGE):
			return {"accepted": false, "reason": "out_of_range"}
	else:
		if not _target_is_in_range(
				game_state, owner_id, _to_data_position(game_state, target_pos), EMP_CAST_RANGE):
			return {"accepted": false, "reason": "out_of_range"}
	return {"accepted": true}

static func _spend_stamina(game_state, owner_id: String, cost: float) -> bool:
	var current: float = game_state.get_stat(owner_id, "stamina")
	if current + 0.0001 < cost:
		return false
	var remaining := maxf(0.0, current - cost)
	# Like dodge stamina, this is a deterministic consequence of the logged command and must not
	# create a second input event. Replay executes this exact mutation from KIND_QUEUE_ABILITY.
	var stats: Dictionary = game_state.characters[owner_id].stats
	stats["stamina"] = remaining
	game_state.stat_changed.emit(owner_id, "stamina", remaining)
	return true

static func _normalized_ids(ids_variant) -> Array[String]:
	var result: Array[String] = []
	if not (ids_variant is Array):
		return result
	for id_variant in ids_variant:
		var id := str(id_variant)
		if id != "" and not result.has(id):
			result.append(id)
	return result

static func _allowed_target_ids(options: Dictionary) -> Array[String]:
	return _normalized_ids(options.get(
		"allowed_target_ids", options.get("party_ids", [])))

static func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result
