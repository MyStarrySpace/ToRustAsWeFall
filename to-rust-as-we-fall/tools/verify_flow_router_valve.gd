extends SceneTree

## Focused P-KIT contract for FlowRouterValve. This proves causal capture, reversible routing,
## scheduler timing, reset/cancel invalidation, and portable state restoration without involving a
## bespoke chunk consequence or renderer.

const ValveScript := preload("res://scripts/game/objects/flow_router_valve.gd")

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scheduler := EventScheduler.new()
	var valve = ValveScript.new()
	root.add_child(valve)

	var route_events: Array = []
	var launched: Array = []
	var arrived: Array = []
	var cancelled: Array = []
	valve.route_changed.connect(func(previous, current, state):
		route_events.append({"previous": previous, "current": current, "state": state}))
	valve.flow_launched.connect(func(flow): launched.append(flow))
	valve.flow_arrived.connect(func(flow): arrived.append(flow))
	valve.flow_cancelled.connect(func(flow, reason):
		cancelled.append({"flow": flow, "reason": reason}))

	check(valve.configure(scheduler, &"main", &"spillway", &"main", 2.0, &"test_router"),
		"configures exactly two named routes")
	var initial: Dictionary = valve.get_state()
	check(str(initial.get("contract", "")) == "flow_router_valve/v1",
		"state exposes a versioned integration contract")
	check(initial.get("routes", []) == [&"main", &"spillway"]
			and initial.get("current_route") == &"main",
		"state truthfully reports route names and initial selection")
	check(not valve.set_route(&"unknown") and route_events.is_empty(),
		"invalid route neither mutates nor emits")
	check(not valve.set_route(&"main") and route_events.is_empty(),
		"selecting the current route is a truthful no-op")

	var main_flow := valve.launch_flow(&"bridge_cargo", {"kind": "debris"})
	check(main_flow == 1 and launched.size() == 1
			and launched[0].get("route") == &"main",
		"launch captures the selected main route")
	scheduler.advance_ticks(0.5)
	check(valve.set_route(&"spillway"), "route reverses while a flow is in transit")
	check(route_events.size() == 1
			and route_events[0].get("previous") == &"main"
			and route_events[0].get("current") == &"spillway"
			and (route_events[0].get("state") as Dictionary).get("current_route") == &"spillway",
		"route_changed carries the real before/after state")
	var spillway_flow := valve.launch_flow(&"wash", {"volume": 3})
	check(spillway_flow == 2 and launched[1].get("route") == &"spillway",
		"a later launch captures the newly selected spillway")
	check(valve.toggle_route() == &"main" and valve.toggle_route() == &"spillway",
		"both routes remain reversibly selectable at any time")

	# Coarse advancement still dispatches at exact scheduler ticks. The first flow must not be
	# redirected by later valve movement.
	scheduler.advance_ticks(1.5)
	check(arrived.size() == 1 and arrived[0].get("payload_id") == &"bridge_cargo"
			and arrived[0].get("route") == &"main"
			and is_equal_approx(float(arrived[0].get("arrival_tick")), 2.0),
		"arrival uses the captured route and scheduler-driven delay")
	scheduler.advance_ticks(0.5)
	check(arrived.size() == 2 and arrived[1].get("route") == &"spillway"
			and is_equal_approx(float(arrived[1].get("arrival_tick")), 2.5),
		"overlapping flows retain independent captured routes")

	var cancelled_flow := valve.launch_flow(&"cancel_me")
	check(valve.cancel_flow(cancelled_flow), "one pending flow can be cancelled")
	var arrivals_before_cancel_advance := arrived.size()
	scheduler.advance_ticks(3.0)
	check(arrived.size() == arrivals_before_cancel_advance
			and cancelled.back().get("reason") == &"cancelled",
		"cancel invalidates its delayed callback deterministically")

	valve.set_route(&"spillway")
	var reset_a := valve.launch_flow(&"reset_a")
	var reset_b := valve.launch_flow(&"reset_b")
	var cancel_start := cancelled.size()
	check(valve.reset() == 2 and valve.get_route() == &"main"
			and valve.get_pending_flows().is_empty(),
		"reset cancels all work and restores the configured initial route")
	check(int(cancelled[cancel_start].get("flow", {}).get("flow_id", 0)) == reset_a
			and int(cancelled[cancel_start + 1].get("flow", {}).get("flow_id", 0)) == reset_b,
		"reset cancellation is emitted in deterministic launch order")
	var arrivals_before_reset_advance := arrived.size()
	scheduler.advance_ticks(5.0)
	check(arrived.size() == arrivals_before_reset_advance,
		"reset-invalidated callbacks never arrive later")

	# Snapshot/restore retains the causal fact that this payload is already committed to spillway.
	valve.set_route(&"spillway")
	valve.launch_flow(&"saved_payload", {"mass": 7}, 3.0)
	scheduler.advance_ticks(1.0)
	var snapshot: Dictionary = valve.serialize_state()
	var pending_snapshot: Array = snapshot.get("pending_flows", [])
	check(pending_snapshot.size() == 1
			and pending_snapshot[0].get("route") == &"spillway"
			and is_equal_approx(float(pending_snapshot[0].get("remaining_delay")), 2.0),
		"serialized readback exposes captured route and remaining delay")

	var restored_scheduler := EventScheduler.new()
	var restored = ValveScript.new()
	root.add_child(restored)
	var restored_arrivals: Array = []
	restored.flow_arrived.connect(func(flow): restored_arrivals.append(flow))
	check(restored.restore_state(snapshot, restored_scheduler),
		"serialized state restores onto a gameplay scheduler")
	check(restored.get_route() == &"spillway" and restored.get_pending_flows().size() == 1,
		"restore exposes the selected route and pending flow immediately")
	restored_scheduler.advance_ticks(1.99)
	check(restored_arrivals.is_empty(), "restored flow does not arrive before its remaining delay")
	restored_scheduler.advance_ticks(0.01)
	check(restored_arrivals.size() == 1
			and restored_arrivals[0].get("payload_id") == &"saved_payload"
			and restored_arrivals[0].get("route") == &"spillway",
		"restored flow arrives once on its originally captured route")

	var before_invalid := restored.serialize_state()
	check(not restored.configure(restored_scheduler, &"same", &"same", &"same", 1.0),
		"duplicate route names are rejected")
	check(restored.serialize_state() == before_invalid,
		"invalid reconfiguration leaves live state unchanged")

	valve.free()
	restored.free()
	finish()


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)


func finish() -> void:
	print("FLOW ROUTER VALVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
