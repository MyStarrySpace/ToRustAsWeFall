class_name FlowRouterValve
extends Node

## Deterministic two-route flow router (P-KIT).
##
## A level places and presents the valve, then wires these signals to other kit objects. The valve
## owns only one causal rule: a flow captures the selected route when it launches and arrives on
## that route after scheduler time has elapsed. Switching the valve later affects future launches,
## never a payload already in transit. No character ability or chunk-specific consequence lives
## here.

signal route_changed(previous_route: StringName, current_route: StringName, state: Dictionary)
signal flow_launched(flow: Dictionary)
signal flow_arrived(flow: Dictionary)
signal flow_cancelled(flow: Dictionary, reason: StringName)
signal state_restored(state: Dictionary)

const STATE_CONTRACT := "flow_router_valve/v1"

var _scheduler = null
var _router_id: StringName = &"flow_router"
var _routes: Array[StringName] = [&"main", &"spillway"]
var _initial_route: StringName = &"main"
var _current_route: StringName = &"main"
var _travel_delay := 1.0
var _next_flow_id := 1
var _route_revision := 0
var _generation := 1
var _configured := false
var _pending: Dictionary = {} # flow_id -> private flow record (includes scheduler handle)


## Configure the two truthful route names and the delay used by future launches. Reconfiguration
## deterministically cancels in-flight work. Returns false without changing state for invalid
## routes, an invalid initial route, a negative delay, or a missing scheduler.
func configure(
		scheduler,
		route_a: StringName = &"main",
		route_b: StringName = &"spillway",
		initial_route: StringName = &"main",
		travel_delay: float = 1.0,
		router_id: StringName = &"flow_router"
	) -> bool:
	if scheduler == null or not scheduler.has_method("schedule_after"):
		return false
	if not _valid_route_pair(route_a, route_b):
		return false
	if initial_route != route_a and initial_route != route_b:
		return false
	if travel_delay < 0.0:
		return false

	var previous := _current_route
	var was_configured := _configured
	_cancel_all_internal(&"reconfigured", true)
	_scheduler = scheduler
	_routes.clear()
	_routes.append(route_a)
	_routes.append(route_b)
	_initial_route = initial_route
	_current_route = initial_route
	_travel_delay = travel_delay
	_router_id = router_id if not String(router_id).is_empty() else &"flow_router"
	_next_flow_id = 1
	_configured = true
	if was_configured and previous != _current_route:
		_route_revision += 1
		route_changed.emit(previous, _current_route, get_state())
	return true


func get_routes() -> Array[StringName]:
	return _routes.duplicate()


func has_route(route: StringName) -> bool:
	return route == _routes[0] or route == _routes[1]


func get_route() -> StringName:
	return _current_route


## Select either configured route. A no-op or invalid request emits nothing and returns false;
## every emitted route_changed event therefore describes a real transition.
func set_route(route: StringName) -> bool:
	if not has_route(route) or route == _current_route:
		return false
	var previous := _current_route
	_current_route = route
	_route_revision += 1
	route_changed.emit(previous, _current_route, get_state())
	return true


## Reversible at any time, including while flows are in transit.
func toggle_route() -> StringName:
	var next := _routes[1] if _current_route == _routes[0] else _routes[0]
	set_route(next)
	return _current_route


func set_travel_delay(seconds: float) -> bool:
	if seconds < 0.0:
		return false
	_travel_delay = seconds
	return true


func get_travel_delay() -> float:
	return _travel_delay


## Launch a named flow on the route selected NOW. `payload` is portable descriptive data for
## downstream kit wiring; this object never interprets it. A negative override uses the configured
## delay. Returns a deterministic positive flow id, or 0 when no scheduler is configured.
func launch_flow(
		payload_id: StringName = &"",
		payload: Dictionary = {},
		travel_delay_override: float = -1.0
	) -> int:
	if _scheduler == null:
		return 0
	var delay := _travel_delay if travel_delay_override < 0.0 else travel_delay_override
	if delay < 0.0:
		return 0

	var flow_id := _next_flow_id
	_next_flow_id += 1
	var launch_tick := _scheduler_tick()
	var route_at_launch := _current_route
	var flow_name := payload_id
	if String(flow_name).is_empty():
		flow_name = StringName("flow_%d" % flow_id)
	var record := {
		"flow_id": flow_id,
		"payload_id": flow_name,
		"payload": payload.duplicate(true),
		"route": route_at_launch,
		"launch_tick": launch_tick,
		"arrival_tick": launch_tick + delay,
		"generation": _generation,
		"handle": 0,
	}
	var handle := int(_scheduler.schedule_after(
		delay,
		_complete_flow.bind(flow_id, _generation),
		_event_tag(flow_id)
	))
	if handle <= 0:
		return 0
	record["handle"] = handle
	_pending[flow_id] = record
	flow_launched.emit(_public_flow(record, &"in_transit"))
	return flow_id


## Cancel one in-flight flow. Its delayed callback is removed and additionally guarded by its
## generation/id, so reset remains safe even if a scheduler implementation uses lazy deletion.
func cancel_flow(flow_id: int) -> bool:
	if not _pending.has(flow_id):
		return false
	var record: Dictionary = _pending[flow_id]
	_cancel_handle(int(record.get("handle", 0)))
	_pending.erase(flow_id)
	flow_cancelled.emit(_public_flow(record, &"cancelled"), &"cancelled")
	return true


## Cancel all in-flight flows in launch order. Returns the number invalidated.
func cancel_pending_flows() -> int:
	return _cancel_all_internal(&"cancelled", true)


## Restore the configured initial route and invalidate every pending callback. The route signal is
## emitted only when reset actually changes the selected route.
func reset() -> int:
	var cancelled := _cancel_all_internal(&"reset", true)
	if _current_route != _initial_route:
		var previous := _current_route
		_current_route = _initial_route
		_route_revision += 1
		route_changed.emit(previous, _current_route, get_state())
	return cancelled


func get_pending_flows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := _sorted_pending_ids()
	for flow_id in ids:
		out.append(_public_flow(_pending[flow_id], &"in_transit"))
	return out


## Stable, renderer-independent state for causal overlays, integration checks, saves, and replay
## diagnostics. Pending records are sorted by flow id and contain remaining scheduler time.
func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"configured": _configured,
		"router_id": _router_id,
		"routes": _routes.duplicate(),
		"initial_route": _initial_route,
		"current_route": _current_route,
		"travel_delay": _travel_delay,
		"route_revision": _route_revision,
		"next_flow_id": _next_flow_id,
		"scheduler_tick": _scheduler_tick(),
		"pending_flows": get_pending_flows(),
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


## Load a serialized snapshot. Pending flows retain their captured routes and remaining delays, but
## receive fresh scheduler handles. Loading emits state_restored, not synthetic launch/route events.
func restore_state(snapshot: Dictionary, scheduler_override = null) -> bool:
	if str(snapshot.get("contract", "")) != STATE_CONTRACT:
		return false
	var raw_routes: Array = snapshot.get("routes", [])
	if raw_routes.size() != 2:
		return false
	var route_a := StringName(str(raw_routes[0]))
	var route_b := StringName(str(raw_routes[1]))
	if not _valid_route_pair(route_a, route_b):
		return false
	var initial := StringName(str(snapshot.get("initial_route", "")))
	var current := StringName(str(snapshot.get("current_route", "")))
	if (initial != route_a and initial != route_b) or (current != route_a and current != route_b):
		return false
	var delay := float(snapshot.get("travel_delay", -1.0))
	if delay < 0.0:
		return false
	var scheduler = scheduler_override if scheduler_override != null else _scheduler
	var raw_pending: Array = snapshot.get("pending_flows", [])
	if scheduler == null and not raw_pending.is_empty():
		return false

	# Validate all pending records before mutating live state.
	var validated: Array[Dictionary] = []
	var seen_ids := {}
	for raw in raw_pending:
		if not raw is Dictionary:
			return false
		var flow: Dictionary = raw
		if not flow.get("payload", {}) is Dictionary:
			return false
		var flow_id := int(flow.get("flow_id", 0))
		var captured_route := StringName(str(flow.get("route", "")))
		var saved_arrival_tick := float(flow.get("arrival_tick", -1.0))
		var remaining := (
			maxf(0.0, saved_arrival_tick - float(scheduler.get_current_tick()))
			if saved_arrival_tick >= 0.0 and scheduler.has_method("get_current_tick")
			else float(flow.get("remaining_delay", -1.0))
		)
		if flow_id <= 0 or seen_ids.has(flow_id) or remaining < 0.0:
			return false
		if captured_route != route_a and captured_route != route_b:
			return false
		seen_ids[flow_id] = true
		var validated_flow := flow.duplicate(true)
		validated_flow["remaining_delay"] = remaining
		validated.append(validated_flow)

	_cancel_all_internal(&"restored", false)
	_scheduler = scheduler
	_routes.clear()
	_routes.append(route_a)
	_routes.append(route_b)
	_initial_route = initial
	_current_route = current
	_travel_delay = delay
	_router_id = StringName(str(snapshot.get("router_id", "flow_router")))
	_route_revision = maxi(0, int(snapshot.get("route_revision", 0)))
	_next_flow_id = maxi(1, int(snapshot.get("next_flow_id", 1)))
	_configured = true

	validated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("flow_id", 0)) < int(b.get("flow_id", 0)))
	for flow in validated:
		var flow_id := int(flow["flow_id"])
		var remaining := float(flow["remaining_delay"])
		var record := {
			"flow_id": flow_id,
			"payload_id": StringName(str(flow.get("payload_id", "flow_%d" % flow_id))),
			"payload": (flow.get("payload", {}) as Dictionary).duplicate(true),
			"route": StringName(str(flow["route"])),
			"launch_tick": float(flow.get("launch_tick", _scheduler_tick())),
			"arrival_tick": _scheduler_tick() + remaining,
			"generation": _generation,
			"handle": 0,
		}
		var handle := int(_scheduler.schedule_after(
			remaining,
			_complete_flow.bind(flow_id, _generation),
			_event_tag(flow_id)
		))
		if handle <= 0:
			_cancel_all_internal(&"restore_failed", false)
			return false
		record["handle"] = handle
		_pending[flow_id] = record
		_next_flow_id = maxi(_next_flow_id, flow_id + 1)
	state_restored.emit(get_state())
	return true


func _complete_flow(flow_id: int, generation: int) -> void:
	if generation != _generation or not _pending.has(flow_id):
		return
	var record: Dictionary = _pending[flow_id]
	if int(record.get("generation", -1)) != generation:
		return
	_pending.erase(flow_id)
	flow_arrived.emit(_public_flow(record, &"arrived"))


func _cancel_all_internal(reason: StringName, emit_events: bool) -> int:
	_generation += 1
	var ids := _sorted_pending_ids()
	for flow_id in ids:
		var record: Dictionary = _pending[flow_id]
		_cancel_handle(int(record.get("handle", 0)))
		if emit_events:
			flow_cancelled.emit(_public_flow(record, reason), reason)
	_pending.clear()
	return ids.size()


func _cancel_handle(handle: int) -> void:
	if _scheduler != null and handle > 0 and _scheduler.has_method("cancel"):
		_scheduler.cancel(handle)


func _public_flow(record: Dictionary, status: StringName) -> Dictionary:
	return {
		"flow_id": int(record.get("flow_id", 0)),
		"payload_id": record.get("payload_id", &""),
		"payload": (record.get("payload", {}) as Dictionary).duplicate(true),
		"route": record.get("route", &""),
		"launch_tick": float(record.get("launch_tick", 0.0)),
		"arrival_tick": float(record.get("arrival_tick", 0.0)),
		"remaining_delay": maxf(0.0, float(record.get("arrival_tick", 0.0)) - _scheduler_tick()),
		"status": status,
	}


func _sorted_pending_ids() -> Array[int]:
	var ids: Array[int] = []
	for value in _pending.keys():
		ids.append(int(value))
	ids.sort()
	return ids


func _scheduler_tick() -> float:
	if _scheduler != null and _scheduler.has_method("get_current_tick"):
		return float(_scheduler.get_current_tick())
	return 0.0


func _event_tag(flow_id: int) -> String:
	return "%s_flow_%d" % [String(_router_id), flow_id]


func _valid_route_pair(route_a: StringName, route_b: StringName) -> bool:
	return not String(route_a).is_empty() and not String(route_b).is_empty() and route_a != route_b


func _exit_tree() -> void:
	_cancel_all_internal(&"teardown", false)
