extends SceneTree

## Focused contract proof for GridWorld's retained node+edge multi-level plans.

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := GridWorld.new()
	grid.create_room(8, 8)
	grid.set_level_count(2)
	grid.add_inter_level_edge(
		Vector2i(2, 2), 0, Vector2i(4, 3), 1,
		"ladder", 3.25, true,
		{"duration": 1.5, "action_id": "climb_basin", "prompt": "Climb"})

	var plan := grid.find_multi_level_plan(Vector2i(1, 2), 0, Vector2i(5, 3), 1)
	_check(not plan.is_empty(), "offset connector produces a cross-level plan")
	var nodes: Array = plan.get("nodes", [])
	var edges: Array = plan.get("edges", [])
	_check(edges.size() == nodes.size() - 1, "every adjacent node pair retains one edge")
	_check(str(plan.get("contract_id", "")) == "multi_level_plan_v1", "plan identifies its contract")
	var connector := _first_connector(edges)
	_check(not connector.is_empty(), "plan retains the connector edge")
	_check(connector.get("from_cell") == Vector2i(2, 2) \
		and connector.get("to_cell") == Vector2i(4, 3), "connector keeps distinct XZ endpoints")
	_check(int(connector.get("from_level", -1)) == 0 \
		and int(connector.get("to_level", -1)) == 1, "connector keeps endpoint levels")
	_check(str(connector.get("kind", "")) == "ladder" \
		and str(connector.get("type", "")) == "ladder", "connector keeps its traversal type")
	_check(is_equal_approx(float(connector.get("cost", 0.0)), 3.25) \
		and is_equal_approx(float(connector.get("duration", 0.0)), 1.5), "connector keeps cost and duration")
	_check(str(connector.get("action_id", "")) == "climb_basin" \
		and str((connector.get("metadata", {}) as Dictionary).get("prompt", "")) == "Climb",
		"connector keeps execution annotations")
	_check(grid.is_navigation_edge_available(connector), "planned connector is currently executable")

	var legacy_nodes := grid.find_multi_level_path(Vector2i(1, 2), 0, Vector2i(5, 3), 1)
	_check(legacy_nodes == nodes, "legacy waypoint API projects the retained plan nodes")
	grid.remove_inter_level_edge(Vector2i(2, 2), 0, Vector2i(4, 3), 1)
	_check(not grid.is_navigation_edge_available(connector), "removed connector invalidates a retained edge")
	_check(grid.find_multi_level_plan(Vector2i(1, 2), 0, Vector2i(5, 3), 1).is_empty(),
		"removed connector makes the cross-level destination unreachable")

	var dangling := GridWorld.new()
	dangling.create_room(8, 8)
	dangling.set_level_count(2)
	dangling.allow_cell_on_level(Vector2i(7, 7), 1)
	dangling.add_inter_level_edge(Vector2i(2, 2), 0, Vector2i(4, 3), 1, "ladder")
	_check(dangling.find_multi_level_plan(Vector2i(1, 2), 0, Vector2i(7, 7), 1).is_empty(),
		"planner never relaxes a connector whose destination vertex is not walkable")

	# Runtime consumers need both the current segment and the final command endpoint.
	# A Rally result must bind to the latter, and a planar/edge handoff remains an
	# active route even if ordinary `is_moving()` is briefly false.
	var runtime_grid := GridWorld.new()
	runtime_grid.create_room(8, 8)
	runtime_grid.set_level_count(2)
	runtime_grid.add_inter_level_edge(
		Vector2i(2, 2), 0, Vector2i(4, 3), 1, "ladder", 3.25, true,
		{"duration": 1.5, "action_id": "climb_basin"})
	var state := GameState.new()
	state.scheduler = EventScheduler.new()
	state.grid = runtime_grid
	state.register_character("climber", runtime_grid.grid_to_world(Vector2i(1, 2), 0))
	var final_cell := Vector2i(6, 3)
	var final_destination := runtime_grid.grid_to_world(final_cell, 1)
	_check(state.command_move_cross_level("climber", final_cell, 1),
		"runtime accepts the annotated cross-level command")
	_check(state.is_navigation_route_active("climber"),
		"retained graph plan exposes one public active-route contract")
	_check(state.get_navigation_route_destination("climber").distance_to(
			final_destination) < 0.001,
		"public route destination retains the complete command endpoint")
	_check(state.get_destination("climber").distance_to(final_destination) > 0.001,
		"ordinary movement destination remains only the current cross-level segment")

	var selection := SelectionController.new()
	selection._game_state = state
	var movement_receipts: Array[Dictionary] = []
	selection.movement_result_requested.connect(
		func(payload: Dictionary) -> void: movement_receipts.append(payload))
	selection._emit_rally_movement_result(Vector2.ZERO, ["climber"], 1)
	var receipt_destinations := (movement_receipts[0].get(
		"subject_destinations", {}) as Dictionary) if movement_receipts.size() == 1 else {}
	_check(movement_receipts.size() == 1
		and bool(movement_receipts[0].get("accepted", false))
		and receipt_destinations.has("climber")
		and (receipt_destinations.get("climber", Vector3.INF) as Vector3).distance_to(
			final_destination) < 0.001,
		"Rally presentation receipt binds the committed final endpoint, not its current leg")
	selection.free()

	state._cross_level_plan["climber"] = [{"level": 1, "cells": []}]
	_check(not state.get_navigation_route_destination("climber").is_finite(),
		"malformed retained graph plans fail closed instead of exposing an intermediate endpoint")

	print("TYPED MULTI-LEVEL PLAN: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _first_connector(edges: Array) -> Dictionary:
	for edge_v in edges:
		var edge := edge_v as Dictionary
		if str(edge.get("category", "")) == "connector":
			return edge
	return {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % label)
		return
	_failures += 1
	push_error("  FAIL: %s" % label)
