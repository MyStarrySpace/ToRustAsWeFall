class_name ClimbvineReturn
extends Node3D

## Gated, one-way recovery traversal (P-KIT).
##
## Peris tends the already-reached UPPER anchor. Scheduler ticks then reveal an externally-authored
## pothos vine downward. Only after deployment does the LOWER interaction accept a selected/active
## group, and every accepted rider enters GameState's logged external-traversal state until it
## physically reaches the upper endpoint. There is deliberately no upper->lower traversal verb.

const PothosScene := preload("res://resources/models/peris-sim/plants/plant_pothos.gltf")
const POTHOS_SOURCE_PATH := "res://resources/models/peris-sim/plants/plant_pothos.gltf"
const STATE_CONTRACT := "climbvine_return/v1"
const TENDER := "peris"
const DEFAULT_DEPLOY_STEPS := 10
const POTHOS_MODEL_HEIGHT := 1.9
const RECEIPT_AUTHORITY_VERSION := 1
const RECEIPT_POSITION_EPSILON := 0.001
const RECEIPT_TICK_EPSILON := 0.000001

signal tend_rejected(character_id: String, required_character: String)
signal deployment_started(return_id: StringName, state: Dictionary)
signal deployment_progressed(return_id: StringName, progress: float)
signal vine_deployed(return_id: StringName, state: Dictionary)
signal climb_committed(return_id: StringName, character_ids: Array)
signal character_climbed(return_id: StringName, character_id: String)
signal climb_cancelled(return_id: StringName, character_id: String, reason: StringName)

var _gs = null
var _scheduler = null
var _return_id: StringName = &"climbvine_return"
var _lower_data := Vector3.ZERO
var _upper_data := Vector3.ZERO
var _lower_render := Vector3.ZERO
var _upper_render := Vector3.ZERO
var _deployment_duration := 2.5
var _climb_duration := 3.0
var _interaction_radius := 2.0
var _deploy_steps := DEFAULT_DEPLOY_STEPS
var _group_provider: Callable = Callable()

# Presentation caches only. The phase/progress source of truth lives in GameState and can be rebuilt
# without this node from a save or event log.
var _presented_phase: StringName = &"__uninitialized"
var _presented_progress := -1.0
var _active_climbs: Dictionary = {} # char_id -> traversal_id
var _receipt_nonce := 0
var _upper_receipt_pending: Dictionary = {}
var _lower_receipt_pending: Dictionary = {}
var _upper_trigger_open := false
var _lower_trigger_open := false

var _upper_interactable: Interactable
var _lower_interactable: Interactable
var _anchor_visual: Node3D
var _vine_visual: Node3D
var _upper_outline = null
var _lower_outline = null
var _runtime_built := false


## Data endpoints belong to GameState; render endpoints belong to the warped visible world. They
## are intentionally independent so a one-loop change in flat spiral data renders as a short,
## vertical climb between stacked decks.
func configure(
		game_state,
		scheduler,
		lower_data: Vector3,
		upper_data: Vector3,
		lower_render: Vector3,
		upper_render: Vector3,
		options: Dictionary = {}
	) -> bool:
	if game_state == null or scheduler == null:
		return false
	if lower_data.distance_to(upper_data) < 0.01 or lower_render.distance_to(upper_render) < 0.01:
		return false
	var deployment_duration := float(options.get("deployment_duration", 2.5))
	var climb_duration := float(options.get("climb_duration", 3.0))
	var interaction_radius := float(options.get("interaction_radius", 2.0))
	var deploy_steps := int(options.get("deployment_steps", DEFAULT_DEPLOY_STEPS))
	if deployment_duration <= 0.0 or climb_duration <= 0.0 or interaction_radius <= 0.0 \
			or deploy_steps < 1:
		return false

	_unwire_game_state_signals()
	_gs = game_state
	_scheduler = scheduler
	_lower_data = lower_data
	_upper_data = upper_data
	_lower_render = lower_render
	_upper_render = upper_render
	_deployment_duration = deployment_duration
	_climb_duration = climb_duration
	_interaction_radius = interaction_radius
	_deploy_steps = deploy_steps
	_return_id = StringName(str(options.get("return_id", "climbvine_return")))
	if String(_return_id).is_empty():
		_return_id = &"climbvine_return"
	_ensure_runtime()
	_bind_interaction_authority()
	_apply_endpoint_layout()
	_wire_game_state_signals()
	_presented_phase = &"__uninitialized"
	_presented_progress = -1.0
	sync_from_game_state()
	return true


func set_group_provider(provider: Callable) -> void:
	_group_provider = provider


func get_upper_interactable() -> Interactable:
	return _upper_interactable


func get_lower_interactable() -> Interactable:
	return _lower_interactable


func get_interactables() -> Array[Node]:
	var result: Array[Node] = []
	if _upper_interactable != null:
		result.append(_upper_interactable)
	if _lower_interactable != null:
		result.append(_lower_interactable)
	return result


func get_data_endpoints() -> Dictionary:
	return {"lower": _lower_data, "upper": _upper_data}


func get_render_endpoints() -> Dictionary:
	return {"lower": _lower_render, "upper": _upper_render}


func get_mechanism_id() -> StringName:
	return StringName("%s:deployment" % String(_return_id))


func is_deployed() -> bool:
	if _gs == null:
		return false
	var state: Dictionary = _gs.get_mechanism_phase_state(get_mechanism_id())
	return state.get("phase", &"") == &"deployed"


func is_deploying() -> bool:
	if _gs == null:
		return false
	var state: Dictionary = _gs.get_mechanism_phase_state(get_mechanism_id())
	return state.get("phase", &"") == &"deploying"


## Deliberately inert. Tending begins only when the exact upper Interactable has accepted an
## action-free Peris body at its authored data endpoint and its receipt is consumed synchronously.
func tend(_character_id: String) -> bool:
	return false


## Deliberately inert. A list of selected portraits is not a physical lower-mouth receipt.
## The lower Interactable commits only the exact all-present group captured by its validator.
func start_climb(_character_ids: Array) -> int:
	return 0


func _upper_interactable_id() -> String:
	return "%s:upper_tend" % String(_return_id)


func _lower_interactable_id() -> String:
	return "%s:lower_climb" % String(_return_id)


func _receipt_authority_key() -> String:
	return "runtime:climbvine_return:%s:interaction_receipts" % String(_return_id)


func _bind_interaction_authority() -> void:
	if _gs == null or _scheduler == null \
			or _upper_interactable == null or _lower_interactable == null:
		return
	_bind_endpoint_interactable(
		_upper_interactable,
		_upper_interactable_id(),
		_upper_data,
		true,
		TENDER,
		"TEND",
		1.35,
		Callable(self, "_validate_upper_source_receipt")
	)
	_bind_endpoint_interactable(
		_lower_interactable,
		_lower_interactable_id(),
		_lower_data,
		false,
		"",
		"CLIMB",
		0.0,
		Callable(self, "_validate_lower_source_receipt")
	)


func _bind_endpoint_interactable(
		interactable: Interactable,
		stable_id: String,
		data_position: Vector3,
		one_shot: bool,
		required: String,
		verb: String,
		hold_time: float,
		validator: Callable
	) -> void:
	if not _gs.has_interactable(stable_id):
		var initially_enabled: bool = not _gs.has_mechanism_phase(get_mechanism_id())
		if stable_id == _lower_interactable_id():
			initially_enabled = is_deployed()
		_gs.register_interactable({
			"id": stable_id,
			"position": data_position,
			"requires_hold": false,
			"hold_time": hold_time,
			"one_shot": one_shot,
			"required_character": required,
			"radius": _interaction_radius,
			"tutorial_label": verb,
			"enabled": initially_enabled,
		})
	interactable.bind_data(_gs, stable_id)
	interactable.one_shot = one_shot
	interactable.required_character = required
	interactable.tutorial_label = verb
	interactable.interaction_radius = _interaction_radius
	interactable.interactable_type = Interactable.InteractableType.TIMED_ACTION \
		if hold_time > 0.0 else Interactable.InteractableType.INSPECTION
	if hold_time > 0.0:
		interactable.dwell_time = hold_time
	interactable.set_scheduler(_scheduler)
	interactable.set_movement_authority(_gs)
	interactable.set_pre_trigger_validator(validator)


func _validate_upper_source_receipt(source: Node, actor_value: String) -> bool:
	var actor := str(actor_value)
	if source != _upper_interactable or _gs == null or _scheduler == null \
			or _upper_trigger_open or not _upper_receipt_pending.is_empty() \
			or _gs.has_mechanism_phase(get_mechanism_id()) \
			or not _gs.has_interactable(_upper_interactable_id()) \
			or not _gs.is_interactable_enabled(_upper_interactable_id()):
		return false
	if actor != TENDER:
		tend_rejected.emit(actor, TENDER)
		return false
	if not _actor_action_free(actor) or not _actor_at_endpoint(actor, _upper_data):
		return false
	_upper_receipt_pending = _new_source_receipt(
		_upper_interactable_id(), actor, [actor], _upper_data)
	_upper_trigger_open = true
	_publish_receipt_authority()
	return true


func _validate_lower_source_receipt(source: Node, actor_value: String) -> bool:
	var actor := str(actor_value)
	if source != _lower_interactable or _gs == null or _scheduler == null \
			or _lower_trigger_open or not _lower_receipt_pending.is_empty() \
			or not is_deployed() or not _gs.has_interactable(_lower_interactable_id()) \
			or not _gs.is_interactable_enabled(_lower_interactable_id()) \
			or not _actor_action_free(actor) or not _actor_at_endpoint(actor, _lower_data):
		return false
	var group := _group_for(actor)
	if group.is_empty() or str(group[0]) != actor:
		return false
	var normalized: Array = []
	var seen := {}
	for raw_id in group:
		var id := str(raw_id)
		if id.is_empty() or seen.has(id) \
				or not _actor_action_free(id) or not _actor_at_endpoint(id, _lower_data):
			return false
		seen[id] = true
		normalized.append(id)
	_lower_receipt_pending = _new_source_receipt(
		_lower_interactable_id(), actor, normalized, _lower_data)
	_lower_trigger_open = true
	_publish_receipt_authority()
	return true


func _new_source_receipt(
		source_id: String,
		actor: String,
		group: Array,
		endpoint: Vector3
	) -> Dictionary:
	_receipt_nonce += 1
	var positions := {}
	for raw_id in group:
		var id := str(raw_id)
		positions[id] = GameEvent.v3_to_arr(_gs.get_position(id))
	return {
		"version": RECEIPT_AUTHORITY_VERSION,
		"source_id": source_id,
		"actor": actor,
		"group": group.duplicate(),
		"body_positions": positions,
		"endpoint": GameEvent.v3_to_arr(endpoint),
		"accepted_tick": float(_scheduler.get_current_tick()),
		"nonce": _receipt_nonce,
		"phase": "source_reserved",
	}


func _actor_action_free(id: String) -> bool:
	if id.is_empty() or _gs == null or not _gs.characters.has(id) or _gs.is_downed(id):
		return false
	if _gs.is_moving(id) or _gs.is_external_traversal_active(id):
		return false
	for method_name in [
		"is_endocytosing", "is_dodging", "is_knocked_down", "is_dragging",
		"is_resting", "is_field_restoring",
	]:
		if _gs.has_method(method_name) and bool(_gs.call(method_name, id)):
			return false
	return true


func _actor_at_endpoint(id: String, endpoint: Vector3) -> bool:
	return _gs != null and _gs.characters.has(id) \
		and _gs.get_position(id).distance_to(endpoint) <= _interaction_radius + 0.25


func _receipt_matches_live_bodies(
		receipt: Dictionary,
		expected_source: String,
		expected_pending: Dictionary
	) -> bool:
	if _gs == null or _scheduler == null or receipt.is_empty() \
			or expected_pending.is_empty() \
			or int(receipt.get("version", 0)) != RECEIPT_AUTHORITY_VERSION \
			or str(receipt.get("source_id", "")) != expected_source \
			or int(receipt.get("nonce", 0)) != int(expected_pending.get("nonce", -1)) \
			or str(receipt.get("phase", "")) != "source_reserved" \
			or absf(
				float(receipt.get("accepted_tick", -INF))
				- float(_scheduler.get_current_tick())
			) > RECEIPT_TICK_EPSILON:
		return false
	var group_v: Variant = receipt.get("group", [])
	var positions_v: Variant = receipt.get("body_positions", {})
	if not (group_v is Array) or not (positions_v is Dictionary):
		return false
	var group := group_v as Array
	var positions := positions_v as Dictionary
	if group.is_empty() or str(group[0]) != str(receipt.get("actor", "")):
		return false
	var endpoint := GameEvent.arr_to_v3(receipt.get("endpoint", [INF, INF, INF]))
	for raw_id in group:
		var id := str(raw_id)
		if not positions.has(id) or not _actor_action_free(id) \
				or not _actor_at_endpoint(id, endpoint):
			return false
		var accepted_position := GameEvent.arr_to_v3(positions[id])
		if _gs.get_position(id).distance_to(accepted_position) > RECEIPT_POSITION_EPSILON:
			return false
	return true


func _commit_tend_from_receipt(source: Node, receipt: Dictionary) -> bool:
	if source != _upper_interactable \
			or not _receipt_matches_live_bodies(
				receipt, _upper_interactable_id(), _upper_receipt_pending) \
			or str(receipt.get("actor", "")) != TENDER \
			or _gs.has_mechanism_phase(get_mechanism_id()):
		return false
	_upper_receipt_pending["phase"] = "committing"
	_publish_receipt_authority()
	var committed := bool(_gs.command_begin_mechanism_phase(
		get_mechanism_id(),
		&"deploying",
		_deployment_duration,
		&"deployed",
		{
			"mechanism_type": "climbvine_return",
			"return_id": String(_return_id),
			"tender": TENDER,
			"source_interactable_id": _upper_interactable_id(),
			"receipt_nonce": int(receipt.get("nonce", 0)),
			"receipt_tick": float(receipt.get("accepted_tick", -1.0)),
			"tender_position": (receipt.get("body_positions", {}) as Dictionary).get(
				TENDER, GameEvent.v3_to_arr(_upper_data)),
			"lower_data": GameEvent.v3_to_arr(_lower_data),
			"upper_data": GameEvent.v3_to_arr(_upper_data),
			"lower_render": GameEvent.v3_to_arr(_lower_render),
			"upper_render": GameEvent.v3_to_arr(_upper_render),
		}
	))
	if committed:
		_upper_receipt_pending.clear()
		_publish_receipt_authority()
	return committed


func _commit_climb_from_receipt(source: Node, receipt: Dictionary) -> int:
	if source != _lower_interactable \
			or not _receipt_matches_live_bodies(
				receipt, _lower_interactable_id(), _lower_receipt_pending):
		return 0
	var group: Array = (receipt.get("group", []) as Array).duplicate()
	_lower_receipt_pending["phase"] = "committing"
	_lower_receipt_pending["traversal_ids"] = _traversal_ids_for_group(group)
	_publish_receipt_authority()
	_disable_lower_source()
	var accepted: Array = []
	for raw_id in group:
		var id := str(raw_id)
		var traversal_id := StringName(str(
			(_lower_receipt_pending["traversal_ids"] as Dictionary).get(id, "")))
		if bool(_gs.command_external_traversal(
			id,
			traversal_id,
			_upper_data,
			_lower_render,
			_upper_render,
			_climb_duration,
			&"locked"
		)):
			_active_climbs[id] = traversal_id
			accepted.append(id)
		else:
			# A signal observer can invalidate a later rider after an earlier
			# BEGIN event has committed. Do not leave that prefix climbing with
			# the repeatable source wedged in `committing`: explicitly cancel
			# every accepted prefix, retire this consumed receipt, and re-arm
			# the physical mouth for a clean all-present retry.
			for accepted_v in accepted:
				var accepted_id := str(accepted_v)
				if _gs.is_external_traversal_active(accepted_id):
					_gs.cancel_external_traversal(
						accepted_id, &"climbvine_group_commit_rejected")
				_active_climbs.erase(accepted_id)
			_lower_receipt_pending.clear()
			_publish_receipt_authority()
			_rearm_lower_source()
			return 0
	_lower_receipt_pending.clear()
	_publish_receipt_authority()
	_rearm_lower_source()
	if not accepted.is_empty():
		climb_committed.emit(_return_id, accepted.duplicate())
	return accepted.size()


func _traversal_ids_for_group(group: Array) -> Dictionary:
	var traversal_ids := {}
	for raw_id in group:
		var id := str(raw_id)
		traversal_ids[id] = "%s:%s" % [String(_return_id), id]
	return traversal_ids


func _publish_receipt_authority() -> void:
	if _gs == null or not _gs.has_method("set_world_state"):
		return
	_gs.set_world_state(_receipt_authority_key(), {
		"version": RECEIPT_AUTHORITY_VERSION,
		"next_nonce": _receipt_nonce,
		"upper_pending": _upper_receipt_pending.duplicate(true),
		"lower_pending": _lower_receipt_pending.duplicate(true),
	})


func _load_receipt_authority() -> void:
	_upper_receipt_pending.clear()
	_lower_receipt_pending.clear()
	if _gs == null or not _gs.has_method("get_world_state"):
		_receipt_nonce = 0
		return
	var raw: Variant = _gs.get_world_state(_receipt_authority_key(), {})
	if not (raw is Dictionary) \
			or int((raw as Dictionary).get("version", 0)) != RECEIPT_AUTHORITY_VERSION:
		_receipt_nonce = 0
		return
	var saved := raw as Dictionary
	_receipt_nonce = maxi(0, int(saved.get("next_nonce", 0)))
	if saved.get("upper_pending", null) is Dictionary:
		_upper_receipt_pending = (
			saved.get("upper_pending") as Dictionary
		).duplicate(true)
	if saved.get("lower_pending", null) is Dictionary:
		_lower_receipt_pending = (
			saved.get("lower_pending") as Dictionary
		).duplicate(true)


func _clear_receipt_authority() -> void:
	_upper_trigger_open = false
	_lower_trigger_open = false
	_upper_receipt_pending.clear()
	_lower_receipt_pending.clear()
	_publish_receipt_authority()


func _reconcile_interaction_authority_after_attach() -> void:
	_load_receipt_authority()
	_upper_trigger_open = false
	_lower_trigger_open = false
	var phase_state: Dictionary = _gs.get_mechanism_phase_state(get_mechanism_id()) \
		if _gs != null else {}
	if phase_state.is_empty():
		# A saved one-shot trigger without a mechanism phase is the synchronous signal seam between
		# GameState accepting the click and this owner consuming its receipt. It is evidence that the
		# action should be retryable, not evidence that the vine deployed.
		if not _upper_receipt_pending.is_empty() or _upper_registry_triggered():
			_upper_receipt_pending.clear()
			_rearm_upper_source()
	else:
		# A mechanism phase is the authoritative consequence. Any still-published source receipt was
		# caught by a save on the mechanism-start signal and can now be retired without replaying it.
		_upper_receipt_pending.clear()
		_spend_upper_source()

	if not _lower_receipt_pending.is_empty():
		if str(_lower_receipt_pending.get("phase", "")) == "committing":
			_resume_lower_commit_after_restore()
		else:
			# Repeatable accepted-trigger seam: no canonical traversal began, so clear the ephemeral
			# reservation and let the physical lower mouth be clicked again.
			_lower_receipt_pending.clear()
			_rearm_lower_source()
	if _upper_receipt_pending.is_empty() and _lower_receipt_pending.is_empty():
		_publish_receipt_authority()


func _resume_lower_commit_after_restore() -> void:
	if _gs == null or _scheduler == null or not is_deployed():
		return
	var receipt := _lower_receipt_pending.duplicate(true)
	var group_v: Variant = receipt.get("group", [])
	var traversal_ids_v: Variant = receipt.get("traversal_ids", {})
	var positions_v: Variant = receipt.get("body_positions", {})
	if not (group_v is Array) or not (traversal_ids_v is Dictionary) \
			or not (positions_v is Dictionary):
		return
	var group := group_v as Array
	var traversal_ids := traversal_ids_v as Dictionary
	var positions := positions_v as Dictionary
	for raw_id in group:
		var id := str(raw_id)
		var expected_id := str(traversal_ids.get(id, ""))
		if expected_id.is_empty() or not positions.has(id):
			return
		if _gs.is_external_traversal_active(id):
			var active: Dictionary = _gs.get_external_traversal_state(id)
			if str(active.get("traversal_id", "")) != expected_id:
				return
			_active_climbs[id] = StringName(expected_id)
			continue
		var accepted_position := GameEvent.arr_to_v3(positions[id])
		if not _actor_action_free(id) or not _actor_at_endpoint(id, _lower_data) \
				or _gs.get_position(id).distance_to(accepted_position) \
					> RECEIPT_POSITION_EPSILON:
			return
		var traversal_id := StringName(expected_id)
		if not bool(_gs.command_external_traversal(
			id,
			traversal_id,
			_upper_data,
			_lower_render,
			_upper_render,
			_climb_duration,
			&"locked"
		)):
			return
		_active_climbs[id] = traversal_id
	_lower_receipt_pending.clear()
	_publish_receipt_authority()
	_rearm_lower_source()


func _upper_registry_triggered() -> bool:
	if _gs == null or not _gs.has_interactable(_upper_interactable_id()):
		return false
	return bool(_gs.get_interactable(_upper_interactable_id()).get("triggered", false))


func _rearm_upper_source() -> void:
	if _gs != null and _gs.has_interactable(_upper_interactable_id()):
		var spec: Dictionary = _gs.get_interactable(_upper_interactable_id())
		if bool(spec.get("triggered", false)) or not bool(spec.get("enabled", true)):
			_gs.reset_interactable(_upper_interactable_id())
	if _upper_interactable != null and (
			not _upper_interactable.is_interaction_enabled()
			or bool(_upper_interactable.get("_used"))
		):
		_upper_interactable.restore_one_shot_presenter(false, true)


func _spend_upper_source() -> void:
	if _gs != null and _gs.has_interactable(_upper_interactable_id()):
		_gs.set_interactable_enabled(_upper_interactable_id(), false)
	if _upper_interactable != null and (
			_upper_interactable.is_interaction_enabled()
			or not bool(_upper_interactable.get("_used"))
		):
		_upper_interactable.restore_one_shot_presenter(true, false)


func _rearm_lower_source() -> void:
	if _gs != null and _gs.has_interactable(_lower_interactable_id()):
		var spec: Dictionary = _gs.get_interactable(_lower_interactable_id())
		if bool(spec.get("triggered", false)) or not bool(spec.get("enabled", true)):
			_gs.reset_interactable(_lower_interactable_id())
	if _lower_interactable != null and not _lower_interactable.is_interaction_enabled():
		_lower_interactable.restore_one_shot_presenter(false, true)


func _disable_lower_source() -> void:
	if _gs != null and _gs.has_interactable(_lower_interactable_id()):
		_gs.set_interactable_enabled(_lower_interactable_id(), false)
	if _lower_interactable != null and _lower_interactable.is_interaction_enabled():
		_lower_interactable.restore_one_shot_presenter(false, false)


## Checkpoint reset retracts the plant and uses GameState's explicit, logged cancellation seam for
## any current riders. It never teleports them; cancellation freezes their authoritative progress.
func reset() -> void:
	if _gs != null:
		sync_from_game_state()
		_clear_receipt_authority()
		var active_ids := _active_climbs.keys()
		active_ids.sort()
		for id_variant in active_ids:
			var id := str(id_variant)
			if _gs.is_external_traversal_active(id):
				_gs.cancel_external_traversal(id, &"climbvine_reset")
		if _gs.has_mechanism_phase(get_mechanism_id()):
			_gs.command_reset_mechanism_phase(get_mechanism_id(), &"climbvine_reset")
	_active_climbs.clear()
	_rearm_upper_source()
	_disable_lower_source()
	_refresh_from_game_state()


func get_state() -> Dictionary:
	_refresh_from_game_state()
	var active: Array[Dictionary] = []
	var ids := _active_climbs.keys()
	ids.sort()
	for id_variant in ids:
		var id := str(id_variant)
		var traversal: Dictionary = _gs.get_external_traversal_state(id) if _gs != null else {}
		active.append({
			"character_id": id,
			"traversal_id": _active_climbs[id_variant],
			"traversal": traversal,
		})
	var phase_state: Dictionary = _gs.get_mechanism_phase_state(get_mechanism_id()) \
		if _gs != null else {}
	var phase := StringName(str(phase_state.get("phase", "dormant")))
	var deploying := phase == &"deploying"
	var deployed := phase == &"deployed"
	return {
		"contract": STATE_CONTRACT,
		"return_id": _return_id,
		"mechanism_id": get_mechanism_id(),
		"tended": not phase_state.is_empty(),
		"deploying": deploying,
		"deployed": deployed,
		"deployment_progress": float(phase_state.get("progress", 0.0)),
		"deployment_start_tick": float(phase_state.get("start_tick", -1.0)),
		"deployment_end_tick": float(phase_state.get("end_tick", -1.0)),
		"deployment_remaining": float(phase_state.get("remaining", 0.0)),
		"authoritative_phase": phase_state,
		"upper_interactable_id": _upper_interactable_id(),
		"lower_interactable_id": _lower_interactable_id(),
		"interaction_receipts": {
			"next_nonce": _receipt_nonce,
			"upper_pending": _upper_receipt_pending.duplicate(true),
			"lower_pending": _lower_receipt_pending.duplicate(true),
		},
		"lower_interaction_enabled": _lower_interactable != null \
			and _lower_interactable.is_interaction_enabled(),
		"data_endpoints": get_data_endpoints(),
		"render_endpoints": get_render_endpoints(),
		"deployment_duration": _deployment_duration,
		"climb_duration": _climb_duration,
		"active_climbs": active,
		"visual_source": POTHOS_SOURCE_PATH,
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


## Compatibility seam for hosts that restore scene presenters after GameState. The supplied scene
## snapshot is diagnostic only: authoritative deployment and riders are always read back from
## GameState, so replay/load works even when no ClimbvineReturn node existed during reconstruction.
func restore_state(snapshot: Dictionary) -> bool:
	if str(snapshot.get("contract", "")) != STATE_CONTRACT or _gs == null:
		return false
	_on_interactables_snapshot_restored()
	sync_from_game_state()
	return true


func on_game_state_snapshot_restored() -> void:
	_on_interactables_snapshot_restored()
	sync_from_game_state()


func _on_interactables_snapshot_restored() -> void:
	_upper_trigger_open = false
	_lower_trigger_open = false
	for interactable in [_upper_interactable, _lower_interactable]:
		if interactable != null:
			interactable.on_game_state_snapshot_restored()


func sync_from_game_state() -> void:
	_active_climbs.clear()
	if _gs == null:
		return
	_reconcile_interaction_authority_after_attach()
	for id_variant in _gs.characters.keys():
		var id := str(id_variant)
		var state: Dictionary = _gs.get_external_traversal_state(id)
		var traversal_id := str(state.get("traversal_id", ""))
		if traversal_id.begins_with(String(_return_id) + ":"):
			_active_climbs[id] = StringName(traversal_id)
	_refresh_from_game_state()


func _ready() -> void:
	_ensure_runtime()
	_bind_interaction_authority()
	_apply_endpoint_layout()
	sync_from_game_state()
	call_deferred("_wire_outlines")


func _process(_delta: float) -> void:
	# Visual growth samples scheduler-derived GameState progress. Frame rate can change how many
	# samples are drawn, never which phase/progress the simulation owns at a given tick.
	_refresh_from_game_state()


func _ensure_runtime() -> void:
	if _runtime_built:
		return
	_runtime_built = true
	_anchor_visual = _build_pothos_subset(
		"UpperAnchorPothos",
		["Pot", "Soil", "Vine_000", "Vine_004", "Vine_010",
		 "PothosLeaf_000", "PothosLeaf_024", "PothosLeaf_072"]
	)
	add_child(_anchor_visual)
	_vine_visual = _build_pothos_subset(
		"DeployedPothosVine",
		["Vine_000", "Vine_004", "Vine_010", "Vine_018", "Vine_026", "Vine_034",
		 "PothosLeaf_000", "PothosLeaf_024", "PothosLeaf_048", "PothosLeaf_072",
		 "PothosLeaf_108", "PothosLeaf_144", "PothosLeaf_180"]
	)
	add_child(_vine_visual)

	_upper_interactable = _make_interactable(
		"UpperTendAnchor", "TEND", "Grow the return vine down to the lower deck", true)
	_upper_interactable.required_character = TENDER
	_upper_interactable.interactable_type = Interactable.InteractableType.TIMED_ACTION
	_upper_interactable.dwell_time = 1.35
	_upper_interactable.one_shot = true
	_upper_interactable.interacted.connect(_on_upper_interacted)
	add_child(_upper_interactable)

	_lower_interactable = _make_interactable(
		"LowerClimbMouth", "CLIMB", "Climb back to the tended upper deck", false)
	_lower_interactable.set_meta(
		"outline_visibility_contract", "dormant_until_enabled")
	_lower_interactable.interactable_type = Interactable.InteractableType.INSPECTION
	_lower_interactable.one_shot = false
	_lower_interactable.interacted.connect(_on_lower_interacted)
	add_child(_lower_interactable)


func _make_interactable(
		label: String,
		verb: String,
		preview: String,
		enabled: bool
	) -> Interactable:
	var interactable := Interactable.new()
	interactable.name = label
	interactable.interaction_radius = _interaction_radius
	interactable.interaction_enabled = enabled
	interactable.description = preview
	interactable.consequence_preview = preview
	interactable.tutorial_label = verb
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = _interaction_radius
	collision.shape = sphere
	interactable.add_child(collision)
	return interactable


func _build_pothos_subset(label: String, part_names: Array) -> Node3D:
	var subset := Node3D.new()
	subset.name = label
	var source = PothosScene.instantiate()
	for part_name in part_names:
		var part := source.find_child(str(part_name), true, false)
		if part is MeshInstance3D:
			var copy := (part as MeshInstance3D).duplicate() as MeshInstance3D
			if copy != null:
				subset.add_child(copy)
				copy.transform = (part as MeshInstance3D).transform
	source.free()
	return subset


func _apply_endpoint_layout() -> void:
	if _upper_interactable != null:
		_upper_interactable.position = _upper_render
		_upper_interactable.set_meta("flat_authored_position", _upper_data)
		_upper_interactable.set_meta("interaction_target_position", _upper_render)
		_upper_interactable.interaction_radius = _interaction_radius
	if _lower_interactable != null:
		_lower_interactable.position = _lower_render
		_lower_interactable.set_meta("flat_authored_position", _lower_data)
		_lower_interactable.set_meta("interaction_target_position", _lower_render)
		_lower_interactable.interaction_radius = _interaction_radius
	if _anchor_visual != null:
		_anchor_visual.position = _upper_render + Vector3.UP * 0.18
		_anchor_visual.scale = Vector3.ONE * 0.62
	_refresh_from_game_state()


func _apply_dormant_presentation(rearm_upper: bool) -> void:
	_apply_vine_progress(0.0)
	if rearm_upper:
		_rearm_upper_source()
	else:
		_set_interactable_presented_enabled(_upper_interactable, true)
	if _lower_interactable != null:
		if _lower_interactable.is_node_ready():
			_lower_interactable.cancel_pending_interaction()
		_disable_lower_source()


func _on_upper_interacted() -> void:
	if _upper_interactable == null:
		return
	var receipt := _upper_receipt_pending.duplicate(true)
	var committed := _commit_tend_from_receipt(_upper_interactable, receipt)
	_upper_trigger_open = false
	if committed:
		return
	_upper_receipt_pending.clear()
	_publish_receipt_authority()
	_rearm_upper_source()


func _on_lower_interacted() -> void:
	if _lower_interactable == null:
		return
	var receipt := _lower_receipt_pending.duplicate(true)
	var expected_count := (receipt.get("group", []) as Array).size()
	var committed_count := _commit_climb_from_receipt(_lower_interactable, receipt)
	_lower_trigger_open = false
	if committed_count == expected_count and expected_count > 0:
		return
	if committed_count == 0:
		_lower_receipt_pending.clear()
		_publish_receipt_authority()
		_rearm_lower_source()


func _group_for(active: String) -> Array:
	var selected: Array = []
	if _group_provider.is_valid():
		var provided: Variant = _group_provider.call()
		if provided is Array:
			for raw_id in provided:
				var id := str(raw_id)
				if not selected.has(id):
					selected.append(id)
	if active != "" and selected.has(active):
		selected.erase(active)
		selected.push_front(active)
		return selected
	if active != "":
		return [active]
	return selected


func _refresh_from_game_state(force_rearm_dormant: bool = false) -> void:
	if _vine_visual == null:
		return
	var state: Dictionary = _gs.get_mechanism_phase_state(get_mechanism_id()) \
		if _gs != null else {}
	var phase := StringName(str(state.get("phase", "dormant")))
	var progress := clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	var previous_phase := _presented_phase
	var phase_changed := phase != previous_phase
	var progress_changed := not is_equal_approx(progress, _presented_progress)

	if phase == &"dormant":
		_apply_dormant_presentation(force_rearm_dormant or phase_changed)
	elif phase == &"deploying":
		_set_gate_interactions(false, false)
		if progress_changed or phase_changed:
			_apply_vine_progress(progress)
			deployment_progressed.emit(_return_id, progress)
	elif phase == &"deployed":
		_set_gate_interactions(false, true)
		if progress_changed or phase_changed:
			_apply_vine_progress(1.0)
		if phase_changed:
			call_deferred("_wire_lower_outline")
	else:
		# Unknown phases fail closed. The GameState readback remains available for diagnostics.
		_set_gate_interactions(false, false)
		_apply_vine_progress(progress)

	_presented_phase = phase
	_presented_progress = progress


func _apply_vine_progress(progress: float) -> void:
	if _vine_visual == null:
		return
	var p := clampf(progress, 0.0, 1.0)
	_vine_visual.visible = p > 0.0
	if p <= 0.0:
		return
	var down := _lower_render - _upper_render
	var full_length := down.length()
	if full_length < 0.01:
		return
	var deployed_end := _upper_render.lerp(_lower_render, p)
	_vine_visual.position = _upper_render.lerp(deployed_end, 0.5)
	_vine_visual.basis = _basis_with_y(down.normalized())
	_vine_visual.scale = Vector3(0.38, maxf(0.01, full_length * p / POTHOS_MODEL_HEIGHT), 0.38)


func _basis_with_y(y_axis: Vector3) -> Basis:
	var reference := Vector3.UP
	if absf(y_axis.dot(reference)) > 0.96:
		reference = Vector3.FORWARD
	var x_axis := reference.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _set_gate_interactions(upper_enabled: bool, lower_enabled: bool) -> void:
	if upper_enabled:
		_rearm_upper_source()
	else:
		_spend_upper_source()
	if lower_enabled and str(_lower_receipt_pending.get("phase", "")) != "committing":
		_rearm_lower_source()
	else:
		_disable_lower_source()


func _set_interactable_presented_enabled(interactable: Interactable, enabled: bool) -> void:
	if interactable == null or interactable.is_interaction_enabled() == enabled:
		return
	if _gs != null and interactable.data_id != "" \
			and _gs.has_interactable(interactable.data_id):
		_gs.set_interactable_enabled(interactable.data_id, enabled)
	if interactable.is_node_ready():
		interactable.set_interaction_enabled(enabled)
	else:
		interactable.interaction_enabled = enabled


func _wire_game_state_signals() -> void:
	if _gs == null:
		return
	if _gs.has_signal("external_traversal_finished") \
			and not _gs.external_traversal_finished.is_connected(_on_external_traversal_finished):
		_gs.external_traversal_finished.connect(_on_external_traversal_finished)
	if _gs.has_signal("external_traversal_cancelled") \
			and not _gs.external_traversal_cancelled.is_connected(_on_external_traversal_cancelled):
		_gs.external_traversal_cancelled.connect(_on_external_traversal_cancelled)
	if _gs.has_signal("mechanism_phase_started") \
			and not _gs.mechanism_phase_started.is_connected(_on_mechanism_phase_started):
		_gs.mechanism_phase_started.connect(_on_mechanism_phase_started)
	if _gs.has_signal("mechanism_phase_completed") \
			and not _gs.mechanism_phase_completed.is_connected(_on_mechanism_phase_completed):
		_gs.mechanism_phase_completed.connect(_on_mechanism_phase_completed)
	if _gs.has_signal("mechanism_phase_reset") \
			and not _gs.mechanism_phase_reset.is_connected(_on_mechanism_phase_reset):
		_gs.mechanism_phase_reset.connect(_on_mechanism_phase_reset)


func _unwire_game_state_signals() -> void:
	if _gs == null:
		return
	if _gs.has_signal("external_traversal_finished") \
			and _gs.external_traversal_finished.is_connected(_on_external_traversal_finished):
		_gs.external_traversal_finished.disconnect(_on_external_traversal_finished)
	if _gs.has_signal("external_traversal_cancelled") \
			and _gs.external_traversal_cancelled.is_connected(_on_external_traversal_cancelled):
		_gs.external_traversal_cancelled.disconnect(_on_external_traversal_cancelled)
	if _gs.has_signal("mechanism_phase_started") \
			and _gs.mechanism_phase_started.is_connected(_on_mechanism_phase_started):
		_gs.mechanism_phase_started.disconnect(_on_mechanism_phase_started)
	if _gs.has_signal("mechanism_phase_completed") \
			and _gs.mechanism_phase_completed.is_connected(_on_mechanism_phase_completed):
		_gs.mechanism_phase_completed.disconnect(_on_mechanism_phase_completed)
	if _gs.has_signal("mechanism_phase_reset") \
			and _gs.mechanism_phase_reset.is_connected(_on_mechanism_phase_reset):
		_gs.mechanism_phase_reset.disconnect(_on_mechanism_phase_reset)


func _on_mechanism_phase_started(mechanism_id: StringName, _state: Dictionary) -> void:
	if mechanism_id != get_mechanism_id():
		return
	_refresh_from_game_state()
	deployment_started.emit(_return_id, get_state())


func _on_mechanism_phase_completed(mechanism_id: StringName, phase: StringName) -> void:
	if mechanism_id != get_mechanism_id() or phase != &"deployed":
		return
	_refresh_from_game_state()
	call_deferred("_wire_lower_outline")
	vine_deployed.emit(_return_id, get_state())


func _on_mechanism_phase_reset(
		mechanism_id: StringName,
		_reason: StringName
	) -> void:
	if mechanism_id != get_mechanism_id():
		return
	_refresh_from_game_state(true)


func _on_external_traversal_finished(id: String, traversal_id: StringName) -> void:
	if not _active_climbs.has(id) or _active_climbs[id] != traversal_id:
		return
	_active_climbs.erase(id)
	character_climbed.emit(_return_id, id)


func _on_external_traversal_cancelled(
		id: String,
		traversal_id: StringName,
		reason: StringName
	) -> void:
	if not _active_climbs.has(id) or _active_climbs[id] != traversal_id:
		return
	_active_climbs.erase(id)
	climb_cancelled.emit(_return_id, id, reason)


func _wire_outlines() -> void:
	if not is_inside_tree() or _upper_interactable == null:
		return
	var manager := OutlineFeedbackManager.ensure(self)
	if manager == null:
		return
	if _upper_outline == null:
		var meshes := _collect_meshes(_anchor_visual, 8)
		if not meshes.is_empty():
			_upper_outline = manager.outline_meshes(
				self, String(_return_id) + "UpperOutline", meshes,
				"climbvine", maxf(1.0, _interaction_radius))
			if _upper_outline != null:
				_upper_interactable.set_outline_target(_upper_outline)
	if is_deployed():
		_wire_lower_outline()


func _wire_lower_outline() -> void:
	if not is_inside_tree() or _lower_interactable == null or _lower_outline != null:
		return
	var manager := OutlineFeedbackManager.ensure(self)
	if manager == null:
		return
	var meshes := _collect_meshes(_vine_visual, 8)
	if meshes.is_empty():
		return
	_lower_outline = manager.outline_meshes(
		self, String(_return_id) + "LowerOutline", meshes,
		"climbvine", maxf(1.0, _interaction_radius))
	if _lower_outline != null:
		_lower_interactable.set_outline_target(_lower_outline)


func _collect_meshes(root_node: Node, limit: int) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root_node == null:
		return meshes
	for child in root_node.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			meshes.append(child as MeshInstance3D)
			if meshes.size() >= limit:
				break
	return meshes


func _exit_tree() -> void:
	_unwire_game_state_signals()
