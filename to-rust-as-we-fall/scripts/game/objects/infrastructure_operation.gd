class_name InfrastructureOperation
extends Node3D

## Reusable physical source -> transit -> receiver -> field operation.
##
## The causal model is deliberately inspectable:
##   1. an exact source control accepts a nearby actor;
##   2. a visible commodity token follows the saved route on scheduler time;
##   3. only its physical arrival enables the exact receiver control;
##   4. an exact receiver receipt resolves the environmental field.
##
## Render frames only project the saved route and scheduler clock. They cannot advance a phase.

signal service_routed(operation: InfrastructureOperation)
signal service_arrived(operation: InfrastructureOperation)
signal operation_completed(operation: InfrastructureOperation)

const AUTHORITY_VERSION := 2
const PHASE_READY := "ready"
const PHASE_IN_TRANSIT := "in_transit"
const PHASE_ARRIVED := "arrived"
const PHASE_COMPLETED := "completed"
const VALID_PHASES := [
	PHASE_READY,
	PHASE_IN_TRANSIT,
	PHASE_ARRIVED,
	PHASE_COMPLETED,
]
const DEFAULT_TRANSIT_SPEED := 3.0
const MIN_TRANSIT_DURATION := 0.25
const RESTORE_REARM_EPSILON := 0.000001
const INTERACTION_POSITION_TOLERANCE := 0.45

var operation_id := "infrastructure_operation"
var commodity := "service"
var source_action := "ROUTE SERVICE"
var receiver_action := "COMMISSION RECEIVER"
var transit_speed := DEFAULT_TRANSIT_SPEED
var source_control: Node
var receiver_control: Node
var service_field: Node3D
var source_status: Label3D
var receiver_status: Label3D
var source_link: Node3D
var consequence_link: Node3D

var _game_state
var _scheduler
var _authority_publisher := Callable()
var _phase := PHASE_READY
var _source_actor_id := ""
var _receiver_actor_id := ""
var _source_id := ""
var _receiver_id := ""
var _route_world: Array[Vector3] = []
var _authored_route_local: Array[Vector3] = []
var _origin := Vector3.ZERO
var _receiver := Vector3.ZERO
var _started_at := -1.0
var _arrival_tick := -1.0
var _completed_at := -1.0
var _field_resolved := false
var _restoring := false
var _transit_token: MeshInstance3D
var _transit_token_material: StandardMaterial3D


func configure(spec: Dictionary) -> void:
	operation_id = str(spec.get("operation_id", operation_id))
	commodity = str(spec.get("commodity", commodity))
	source_action = str(spec.get("source_action", source_action))
	receiver_action = str(spec.get("receiver_action", receiver_action))
	transit_speed = maxf(0.05, float(spec.get("transit_speed", DEFAULT_TRANSIT_SPEED)))
	_authored_route_local.clear()
	for point_v in spec.get("route_points", []) as Array:
		var point := _decode_vec3(point_v, Vector3.INF)
		if point != Vector3.INF:
			_authored_route_local.append(point)


func bind_runtime(
		source: Node,
		receiver: Node,
		field: Node3D,
		source_label: Label3D = null,
		receiver_label: Label3D = null,
		service_link: Node3D = null,
		effect_link: Node3D = null
	) -> void:
	source_control = source
	receiver_control = receiver
	service_field = field
	source_status = source_label
	receiver_status = receiver_label
	source_link = service_link
	consequence_link = effect_link
	_source_id = str(source_control.get("data_id")) if is_instance_valid(source_control) else ""
	_receiver_id = str(receiver_control.get("data_id")) if is_instance_valid(receiver_control) else ""
	if is_instance_valid(source_control) and source_control.has_method("set_pre_trigger_validator"):
		source_control.call("set_pre_trigger_validator", _validate_source_trigger)
	if is_instance_valid(receiver_control) and receiver_control.has_method("set_pre_trigger_validator"):
		receiver_control.call("set_pre_trigger_validator", _validate_receiver_trigger)
	_ensure_transit_presenter()
	_apply_state()


## Bind the one simulation clock and the canonical interaction registry. The optional publisher is
## installed by the enclosing host after it has added this operation to its stable-ID collection.
func bind_authority(game_state, scheduler, publisher := Callable()) -> void:
	if _game_state != null and _game_state.has_signal("interactable_triggered") \
			and _game_state.interactable_triggered.is_connected(
				_on_authority_interactable_triggered
			):
		_game_state.interactable_triggered.disconnect(_on_authority_interactable_triggered)
	_game_state = game_state
	_scheduler = scheduler
	_authority_publisher = publisher
	if _game_state != null and _game_state.has_signal("interactable_triggered") \
			and not _game_state.interactable_triggered.is_connected(
				_on_authority_interactable_triggered
			):
		_game_state.interactable_triggered.connect(_on_authority_interactable_triggered)
	_apply_state()


func set_authority_publisher(publisher: Callable) -> void:
	_authority_publisher = publisher


## These entry points always refuse: a caller cannot manufacture either end of the operation by invoking
## a convenient public helper: only the exact source/receiver Interactable's accepted GameState receipt
## can cross these boundaries.
func route_service() -> bool:
	return false


func complete_operation() -> bool:
	return false


func _validate_source_trigger(source: Node, actor: String) -> bool:
	return source == source_control \
		and _phase == PHASE_READY \
		and _actor_ready_at(source, actor)


func _validate_receiver_trigger(source: Node, actor: String) -> bool:
	return source == receiver_control \
		and _phase == PHASE_ARRIVED \
		and _actor_ready_at(source, actor)


## GameState emits this after writing the exact interactable trigger but before the Interactable applies
## local one-shot feedback. The operation can therefore save its complete causal context before any of
## its own links, token, labels, field effects, or external signals change.
func _on_authority_interactable_triggered(data_id: String, actor: String) -> void:
	if data_id == _source_id:
		_accept_source_receipt(source_control, actor)
	elif data_id == _receiver_id:
		_accept_receiver_receipt(receiver_control, actor)


func _accept_source_receipt(source: Node, actor: String) -> bool:
	if not _validate_source_trigger(source, actor) \
			or not _consumed_interactable_receipt(source, _source_id, actor):
		return false
	var now := _scheduler_tick()
	var route := _build_world_route()
	if route.size() < 2:
		return false
	var duration := maxf(MIN_TRANSIT_DURATION, _route_length(route) / transit_speed)

	# Commitment first: portable identity, phase, actor, endpoints, exact route, start, and deadline
	# are all true before any operation presentation or notification can observe the launch.
	_phase = PHASE_IN_TRANSIT
	_source_actor_id = actor
	_receiver_actor_id = ""
	_source_id = str(source.get("data_id"))
	_receiver_id = str(receiver_control.get("data_id"))
	_route_world.assign(route)
	_origin = _route_world[0]
	_receiver = _route_world[_route_world.size() - 1]
	_started_at = now
	_arrival_tick = now + duration
	_completed_at = -1.0
	_field_resolved = false
	_publish_authority()
	_arm_transit_arrival()

	_apply_state()
	_set_link_state(source_link, "ready", true)
	service_routed.emit(self)
	return true


func _accept_receiver_receipt(source: Node, actor: String) -> bool:
	if not _validate_receiver_trigger(source, actor) \
			or not _consumed_interactable_receipt(source, _receiver_id, actor):
		return false

	# Completion is one atomic world fact. Publish it before resolving the field presenter/signal so
	# a save taken from any consequence callback already contains the paid receiver receipt.
	_phase = PHASE_COMPLETED
	_receiver_actor_id = actor
	_completed_at = _scheduler_tick()
	_field_resolved = true
	_publish_authority()
	if is_instance_valid(service_field) and service_field.has_method("resolve_field"):
		service_field.call("resolve_field")
	_apply_state()
	_set_link_state(consequence_link, "complete", true)
	operation_completed.emit(self)
	return true


func _actor_ready_at(source: Node, actor: String) -> bool:
	if _game_state == null or _scheduler == null or not is_instance_valid(source) \
			or not (source is Node3D) or actor == "" \
			or not _game_state.characters.has(actor):
		return false
	if _game_state.has_method("is_narratively_available") \
			and not bool(_game_state.is_narratively_available(actor)):
		return false
	if (_game_state.has_method("is_downed") and bool(_game_state.is_downed(actor))) \
			or (_game_state.has_method("is_knocked_down")
				and bool(_game_state.is_knocked_down(actor))) \
			or _actor_busy(actor):
		return false
	var required_actor := str(source.get("required_character"))
	if required_actor != "" and actor != required_actor:
		return false
	var source_position := (source as Node3D).global_position
	if _game_state.coord_map != null and _game_state.coord_map.has_method("to_data"):
		source_position = _game_state.coord_map.to_data(source_position)
	var actor_position: Vector3 = _game_state.get_position(actor)
	var planar_distance := Vector2(actor_position.x, actor_position.z).distance_to(
		Vector2(source_position.x, source_position.z)
	)
	return planar_distance <= float(source.get("interaction_radius")) \
		+ INTERACTION_POSITION_TOLERANCE


func _actor_busy(actor: String) -> bool:
	return (_game_state.has_method("is_moving") and bool(_game_state.is_moving(actor))) \
		or (_game_state.has_method("is_resting") and bool(_game_state.is_resting(actor))) \
		or (_game_state.has_method("is_dodging") and bool(_game_state.is_dodging(actor))) \
		or (_game_state.has_method("is_endocytosing")
			and bool(_game_state.is_endocytosing(actor))) \
		or (_game_state.has_method("is_external_traversal_active")
			and bool(_game_state.is_external_traversal_active(actor))) \
		or (_game_state.has_method("is_dragging") and bool(_game_state.is_dragging(actor))) \
		or (_game_state.has_method("is_field_restoring")
			and bool(_game_state.is_field_restoring(actor)))


func _consumed_interactable_receipt(source: Node, expected_id: String, actor: String) -> bool:
	if not is_instance_valid(source) or str(source.get("data_id")) != expected_id \
			or str(source.get("active_character")) != actor \
			or not bool(source.get("one_shot")) \
			or _game_state == null or expected_id == "" \
			or not _game_state.has_interactable(expected_id):
		return false
	var receipt: Dictionary = _game_state.get_interactable(expected_id)
	return bool(receipt.get("one_shot", false)) \
		and bool(receipt.get("triggered", false)) \
		and not bool(receipt.get("enabled", true))


func _build_world_route() -> Array[Vector3]:
	var route: Array[Vector3] = []
	if not is_instance_valid(source_control) or not is_instance_valid(receiver_control):
		return route
	route.append((source_control as Node3D).global_position)
	for local_point in _authored_route_local:
		route.append(to_global(local_point))
	route.append((receiver_control as Node3D).global_position)
	var compact: Array[Vector3] = []
	for point in route:
		if compact.is_empty() or compact[compact.size() - 1].distance_to(point) > 0.001:
			compact.append(point)
	return compact


func _arm_transit_arrival() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(_transit_tag())
	if _phase != PHASE_IN_TRANSIT or _arrival_tick < 0.0:
		return
	var deadline := _arrival_tick
	var now := _scheduler_tick()
	if deadline <= now:
		# A snapshot taken after the deadline but before its callback resolves on the next scheduler turn.
		# The callback remains scheduler-owned and strictly future; no render/headless presenter is needed.
		deadline = now + RESTORE_REARM_EPSILON
	_scheduler.schedule_at(
		deadline,
		_on_service_arrived.bind(_arrival_tick),
		_transit_tag()
	)


func _on_service_arrived(expected_arrival_tick: float) -> void:
	if _phase != PHASE_IN_TRANSIT \
			or not is_equal_approx(expected_arrival_tick, _arrival_tick):
		return
	_phase = PHASE_ARRIVED
	_publish_authority()
	_apply_state()
	_set_link_state(source_link, "complete", true)
	_set_link_state(consequence_link, "ready", true)
	service_arrived.emit(self)


func reset_operation() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(_transit_tag())
	_phase = PHASE_READY
	_source_actor_id = ""
	_receiver_actor_id = ""
	_route_world.clear()
	_origin = Vector3.ZERO
	_receiver = Vector3.ZERO
	_started_at = -1.0
	_arrival_tick = -1.0
	_completed_at = -1.0
	_field_resolved = false
	if is_instance_valid(source_control) and source_control.has_method("reset"):
		source_control.call("reset")
	if is_instance_valid(receiver_control) and receiver_control.has_method("reset"):
		receiver_control.call("reset")
	if is_instance_valid(service_field) and service_field.has_method("reset_field"):
		service_field.call("reset_field")
	_set_link_state(source_link, "predicted", false)
	_set_link_state(consequence_link, "predicted", false)
	_apply_state()


## JSON-safe, stable-ID authority persisted by the enclosing chunk. Compatibility booleans are derived
## from the phase; they are never writable authority.
func serialize_state() -> Dictionary:
	var encoded_route: Array = []
	for point in _route_world:
		encoded_route.append(_encode_vec3(point))
	return {
		"version": AUTHORITY_VERSION,
		"operation_id": operation_id,
		"commodity": commodity,
		"phase": _phase,
		"source_actor_id": _source_actor_id,
		"receiver_actor_id": _receiver_actor_id,
		"source_id": _source_id,
		"receiver_id": _receiver_id,
		"origin": _encode_vec3(_origin),
		"receiver": _encode_vec3(_receiver),
		"route": encoded_route,
		"started_at": _started_at,
		"arrival_tick": _arrival_tick,
		"completed_at": _completed_at,
		"transit_speed": transit_speed,
		"progress_rule": "piecewise_linear_route_by_scheduler_tick",
		"interruption_policy": "none_once_launched",
		"source_receipt_consumed": _phase != PHASE_READY,
		"receiver_receipt_consumed": _phase == PHASE_COMPLETED,
		"routed": _phase != PHASE_READY,
		"completed": _phase == PHASE_COMPLETED,
		"field_resolved": _field_resolved,
	}


## Mirror saved truth silently. Missing, mismatched, or causally impossible records retract the
## presenter and callback to the pre-route baseline.
func restore_state(snapshot: Variant) -> bool:
	if _scheduler != null:
		_scheduler.cancel_tag(_transit_tag())
	var expected_source_id := _source_id
	var expected_receiver_id := _receiver_id
	var valid := snapshot is Dictionary
	var saved: Dictionary = snapshot as Dictionary if valid else {}
	if valid:
		valid = int(saved.get("version", 0)) == AUTHORITY_VERSION \
			and str(saved.get("operation_id", "")) == operation_id \
			and str(saved.get("commodity", "")) == commodity \
			and str(saved.get("source_id", "")) == expected_source_id \
			and str(saved.get("receiver_id", "")) == expected_receiver_id \
			and is_equal_approx(
				float(saved.get("transit_speed", -1.0)),
				transit_speed
			)
	var next_phase := str(saved.get("phase", PHASE_READY)) if valid else PHASE_READY
	var next_route: Array[Vector3] = []
	if valid:
		next_route = _decode_route(saved.get("route", []))
	var next_started := float(saved.get("started_at", -1.0)) if valid else -1.0
	var next_arrival := float(saved.get("arrival_tick", -1.0)) if valid else -1.0
	var next_completed := float(saved.get("completed_at", -1.0)) if valid else -1.0
	var next_field_resolved := bool(saved.get("field_resolved", false)) if valid else false
	var saved_source_actor := str(saved.get("source_actor_id", "")) if valid else ""
	var saved_receiver_actor := str(saved.get("receiver_actor_id", "")) if valid else ""
	var source_receipt_consumed := bool(
		saved.get("source_receipt_consumed", false)
	) if valid else false
	var receiver_receipt_consumed := bool(
		saved.get("receiver_receipt_consumed", false)
	) if valid else false
	if next_phase not in VALID_PHASES:
		valid = false
	elif next_phase == PHASE_READY:
		valid = next_route.is_empty() and next_started < 0.0 and next_arrival < 0.0 \
			and next_completed < 0.0 and not next_field_resolved \
			and saved_source_actor == "" and saved_receiver_actor == "" \
			and not source_receipt_consumed and not receiver_receipt_consumed
	elif next_route.size() < 2 or next_started < 0.0 or next_arrival <= next_started:
		valid = false
	elif saved_source_actor == "" or not source_receipt_consumed:
		valid = false
	elif not _saved_route_context_matches(saved, next_route, next_started, next_arrival):
		valid = false
	elif next_phase == PHASE_COMPLETED:
		valid = next_completed >= next_arrival and next_field_resolved \
			and saved_receiver_actor != "" and receiver_receipt_consumed
	elif next_completed >= 0.0 or next_field_resolved \
			or saved_receiver_actor != "" or receiver_receipt_consumed:
		valid = false
	if not valid:
		next_phase = PHASE_READY
		next_route.clear()
		next_started = -1.0
		next_arrival = -1.0
		next_completed = -1.0
		next_field_resolved = false

	_restoring = true
	_phase = next_phase
	_source_actor_id = saved_source_actor if valid else ""
	_receiver_actor_id = saved_receiver_actor if valid else ""
	_source_id = str(saved.get("source_id", _source_id)) if valid else _source_id
	_receiver_id = str(saved.get("receiver_id", _receiver_id)) if valid else _receiver_id
	_route_world.assign(next_route)
	_origin = _route_world[0] if not _route_world.is_empty() else Vector3.ZERO
	_receiver = _route_world[_route_world.size() - 1] \
		if not _route_world.is_empty() else Vector3.ZERO
	_started_at = next_started
	_arrival_tick = next_arrival
	_completed_at = next_completed
	_field_resolved = next_field_resolved
	_restore_control_presenter(
		source_control,
		_phase != PHASE_READY,
		_phase == PHASE_READY
	)
	_restore_control_presenter(
		receiver_control,
		_phase == PHASE_COMPLETED,
		_phase == PHASE_ARRIVED
	)
	if is_instance_valid(service_field):
		if service_field.has_method("restore_resolved_state"):
			service_field.call("restore_resolved_state", _field_resolved)
		elif _field_resolved and service_field.has_method("resolve_field"):
			service_field.call("resolve_field")
		elif not _field_resolved and service_field.has_method("reset_field"):
			service_field.call("reset_field")
	_apply_state(false)
	_restore_link_feedback()
	_restoring = false
	_arm_transit_arrival()
	return valid


func _saved_route_context_matches(
		saved: Dictionary,
		route: Array[Vector3],
		started_at: float,
		arrival_tick: float
	) -> bool:
	var saved_origin := _decode_vec3(saved.get("origin", []), Vector3.INF)
	var saved_receiver := _decode_vec3(saved.get("receiver", []), Vector3.INF)
	if saved_origin == Vector3.INF or saved_receiver == Vector3.INF \
			or saved_origin.distance_to(route[0]) > 0.001 \
			or saved_receiver.distance_to(route[route.size() - 1]) > 0.001:
		return false
	var expected_duration := maxf(MIN_TRANSIT_DURATION, _route_length(route) / transit_speed)
	return is_equal_approx(arrival_tick - started_at, expected_duration)


func get_state() -> Dictionary:
	var state := serialize_state()
	var progress := transit_progress()
	var token_position := transit_position()
	state["transit_progress"] = progress
	state["transit_position"] = token_position
	state["transit_visible"] = _phase in [PHASE_IN_TRANSIT, PHASE_ARRIVED]
	state["receiver_enabled"] = is_instance_valid(receiver_control) \
		and receiver_control.has_method("is_interaction_enabled") \
		and bool(receiver_control.call("is_interaction_enabled"))
	state["field"] = service_field.call("get_state") if is_instance_valid(service_field) \
		and service_field.has_method("get_state") else {}
	return state


func transit_progress() -> float:
	if _phase == PHASE_READY:
		return 0.0
	if _phase in [PHASE_ARRIVED, PHASE_COMPLETED]:
		return 1.0
	if _started_at < 0.0 or _arrival_tick <= _started_at:
		return 0.0
	return clampf(
		(_scheduler_tick() - _started_at) / (_arrival_tick - _started_at),
		0.0,
		1.0
	)


func transit_position() -> Vector3:
	if _route_world.is_empty():
		return Vector3.ZERO
	return _sample_route(_route_world, transit_progress())


func _process(_delta: float) -> void:
	# @rendering_only: the token and labels analytically project scheduler-owned authority.
	if _phase != PHASE_IN_TRANSIT:
		set_process(false)
		return
	_update_transit_presenter()
	_apply_status_labels()


func _publish_authority() -> void:
	if _restoring or not _authority_publisher.is_valid():
		return
	_authority_publisher.call()


func _scheduler_tick() -> float:
	return float(_scheduler.get_current_tick()) if _scheduler != null else 0.0


func _transit_tag() -> StringName:
	return StringName("infrastructure:%s:transit_arrival" % operation_id)


func _restore_control_presenter(control: Node, used: bool, enabled: bool) -> void:
	if not is_instance_valid(control):
		return
	if control.has_method("restore_one_shot_presenter"):
		control.call("restore_one_shot_presenter", used, enabled)
		return
	if "_used" in control:
		control.set("_used", used)
	if control.has_method("set_interaction_enabled"):
		control.call("set_interaction_enabled", enabled)


func _restore_link_feedback() -> void:
	match _phase:
		PHASE_IN_TRANSIT:
			_set_link_state(source_link, "ready", false)
			_set_link_state(consequence_link, "predicted", false)
		PHASE_ARRIVED:
			_set_link_state(source_link, "complete", false)
			_set_link_state(consequence_link, "ready", false)
		PHASE_COMPLETED:
			_set_link_state(source_link, "complete", false)
			_set_link_state(consequence_link, "complete", false)
		_:
			_set_link_state(source_link, "predicted", false)
			_set_link_state(consequence_link, "predicted", false)


func _apply_state(update_control_presenters := true) -> void:
	if update_control_presenters:
		_restore_control_presenter(
			source_control,
			_phase != PHASE_READY,
			_phase == PHASE_READY
		)
		_restore_control_presenter(
			receiver_control,
			_phase == PHASE_COMPLETED,
			_phase == PHASE_ARRIVED
		)
	_apply_status_labels()
	_set_link_latched(source_link, _phase == PHASE_IN_TRANSIT)
	_set_link_latched(consequence_link, _phase == PHASE_ARRIVED)
	_update_transit_presenter()
	set_process(_phase == PHASE_IN_TRANSIT)


func _apply_status_labels() -> void:
	if is_instance_valid(source_status):
		source_status.text = "1  %s%s" % [
			source_action,
			"  SENT" if _phase != PHASE_READY else "",
		]
		source_status.modulate = Color(0.36, 0.91, 0.50) \
			if _phase != PHASE_READY else _commodity_color()
	if not is_instance_valid(receiver_status):
		return
	match _phase:
		PHASE_COMPLETED:
			receiver_status.text = "2  %s  DONE" % receiver_action
			receiver_status.modulate = Color(0.36, 0.91, 0.50)
		PHASE_ARRIVED:
			receiver_status.text = "2  %s" % receiver_action
			receiver_status.modulate = Color(0.95, 0.64, 0.32)
		PHASE_IN_TRANSIT:
			receiver_status.text = "INBOUND %s  %d%%" % [
				commodity.replace("_", " ").to_upper(),
				roundi(transit_progress() * 100.0),
			]
			receiver_status.modulate = _commodity_color()
		_:
			receiver_status.text = "2  WAITING: %s" % commodity.replace("_", " ").to_upper()
			receiver_status.modulate = Color(0.62, 0.65, 0.70)


func _ensure_transit_presenter() -> void:
	if is_instance_valid(_transit_token):
		return
	_transit_token = MeshInstance3D.new()
	_transit_token.name = "InfrastructureCommodityToken"
	var token_mesh := SphereMesh.new()
	token_mesh.radius = 0.18
	token_mesh.height = 0.36
	_transit_token.mesh = token_mesh
	_transit_token_material = StandardMaterial3D.new()
	_transit_token_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_transit_token_material.albedo_color = _commodity_color()
	_transit_token_material.emission_enabled = true
	_transit_token_material.emission = _commodity_color()
	_transit_token_material.emission_energy_multiplier = 2.4
	_transit_token.material_override = _transit_token_material
	_transit_token.visible = false
	_transit_token.set_meta("camera_occlusion_exempt", true)
	add_child(_transit_token)


func _update_transit_presenter() -> void:
	if not is_instance_valid(_transit_token):
		return
	_transit_token.visible = _phase in [PHASE_IN_TRANSIT, PHASE_ARRIVED]
	if _transit_token.visible and not _route_world.is_empty():
		_transit_token.global_position = transit_position() + Vector3(0.0, 0.38, 0.0)


func _commodity_color() -> Color:
	match commodity:
		"electricity": return Color(0.42, 0.72, 0.95)
		"data": return Color(0.58, 0.50, 0.96)
		"fabricated_goods": return Color(0.95, 0.64, 0.32)
		"wastewater": return Color(0.72, 0.54, 0.24)
		"process_water": return Color(0.24, 0.78, 0.72)
		_: return Color(0.36, 0.91, 0.50)


func _route_length(route: Array[Vector3]) -> float:
	var total := 0.0
	for idx in range(1, route.size()):
		total += route[idx - 1].distance_to(route[idx])
	return total


func _sample_route(route: Array[Vector3], progress: float) -> Vector3:
	if route.is_empty():
		return Vector3.ZERO
	if route.size() == 1 or progress <= 0.0:
		return route[0]
	if progress >= 1.0:
		return route[route.size() - 1]
	var total := _route_length(route)
	if total <= 0.000001:
		return route[route.size() - 1]
	var remaining := progress * total
	for idx in range(1, route.size()):
		var segment := route[idx - 1].distance_to(route[idx])
		if remaining <= segment:
			return route[idx - 1].lerp(
				route[idx],
				remaining / maxf(segment, 0.000001)
			)
		remaining -= segment
	return route[route.size() - 1]


func _decode_route(raw: Variant) -> Array[Vector3]:
	var route: Array[Vector3] = []
	if not (raw is Array):
		return route
	for point_v in raw as Array:
		var point := _decode_vec3(point_v, Vector3.INF)
		if point == Vector3.INF:
			route.clear()
			return route
		route.append(point)
	return route


func _decode_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback


func _encode_vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _set_link_latched(link: Node3D, active: bool) -> void:
	if is_instance_valid(link) and link.has_method("set_latched"):
		link.call("set_latched", active)


func _set_link_state(link: Node3D, mode: String, flash_link: bool) -> void:
	if not is_instance_valid(link):
		return
	if link.has_method("set_feedback_mode"):
		link.call("set_feedback_mode", mode)
	if flash_link and link.has_method("flash"):
		link.call("flash", 1.35, 1.2)
