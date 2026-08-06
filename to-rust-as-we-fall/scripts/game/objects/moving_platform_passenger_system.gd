class_name MovingPlatformPassengerSystem
extends RefCounted

## Reusable authority layer for any moving surface that carries parked occupants.
##
## The owning mechanism decides which cells form the surface and supplies paired data/render
## waypoint paths. A piston can provide two vertical points; a rotating arm can provide sampled
## arc points. This class owns occupant eligibility, traversal identity, and exact commit cleanup.

const TRAVERSAL_PREFIX := "moving_platform/"

var _gs = null
var _platform_id := "platform"
var _captured_route_destinations: Dictionary = {}
var _motion_window: Dictionary = {}


func configure(game_state, platform_id: String) -> void:
	_gs = game_state
	_platform_id = platform_id.strip_edges().replace("/", "_")
	if _platform_id.is_empty():
		_platform_id = "platform"


func parked_occupants(surface_cells: Dictionary, accepted_levels: Array[int]) -> Array[String]:
	return surface_occupants(surface_cells, accepted_levels, false)


func surface_occupants(
		surface_cells: Dictionary,
		accepted_levels: Array[int],
		include_active_routes := true
	) -> Array[String]:
	var result: Array[String] = []
	if _gs == null or _gs.grid == null:
		return result
	for id_v in _gs.characters.keys():
		var id := str(id_v)
		if _gs.is_external_traversal_active(id):
			continue
		if not include_active_routes and ((_gs.has_method("is_navigation_route_active") \
				and _gs.is_navigation_route_active(id)) \
				or (_gs.has_method("is_moving") and _gs.is_moving(id))):
			continue
		var cell: Vector2i = _gs.grid.world_to_grid(_gs.get_position(id))
		var level := int(_gs.get_character_level(id)) \
			if _gs.has_method("get_character_level") else 0
		if surface_cells.has(cell) and accepted_levels.has(level):
			result.append(id)
	result.sort()
	return result


## Snapshot every active route whose remaining cells depend on this surface. Current occupants may
## be converted to platform carries; approaching routes continue until commit, then replan against
## the new topology. Calling this again (including from manual controls) replaces stale forecasts.
func capture_affected_routes(surface_cells: Dictionary, levels: Array[int]) -> void:
	_captured_route_destinations.clear()
	if _gs == null or not _gs.has_method("navigation_route_intersects_cells"):
		return
	for id_v in _gs.characters.keys():
		var id := str(id_v)
		if not _gs.is_navigation_route_active(id) \
				or not _gs.navigation_route_intersects_cells(id, surface_cells, levels):
			continue
		var destination: Vector3 = _gs.get_navigation_route_destination(id)
		if destination.is_finite():
			_captured_route_destinations[id] = destination


func begin_motion_window(
		start_tick: float,
		commit_tick: float,
		surface_cells: Dictionary,
		levels: Array[int]
	) -> void:
	var portable_cells: Array = []
	for cell_v in surface_cells.keys():
		var cell := cell_v as Vector2i
		portable_cells.append([cell.x, cell.y])
	portable_cells.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) if int(a[1]) == int(b[1]) else int(a[1]) < int(b[1]))
	_motion_window = {
		"contract": "moving_platform_motion_window/v1",
		"platform_id": _platform_id,
		"start_tick": start_tick,
		"commit_tick": commit_tick,
		"surface_cells": portable_cells,
		"levels": levels.duplicate(),
		"active": true,
	}
	capture_affected_routes(surface_cells, levels)


func get_motion_window() -> Dictionary:
	return _motion_window.duplicate(true)


func replan_captured_routes(reason := "platform_topology_changed") -> Array[String]:
	var replanned: Array[String] = []
	if _gs == null:
		_captured_route_destinations.clear()
		return replanned
	for id_v in _captured_route_destinations.keys():
		var id := str(id_v)
		if not _gs.characters.has(id) or _gs.is_external_traversal_active(id):
			continue
		var destination: Vector3 = _captured_route_destinations[id_v]
		if _gs.command_move_to_pos(id, destination):
			replanned.append(id)
			if _gs.has_signal("navigation_route_replanned"):
				_gs.emit_signal("navigation_route_replanned", id, {
					"contract": "navigation_route_replan/v1",
					"reason": reason,
					"platform_id": _platform_id,
				})
	_captured_route_destinations.clear()
	return replanned


## Begin one authoritative carry. The paths may be linear, vertical, curved, or rotating, but they
## must have matching waypoint counts. `receipt` may set show_label=false for self-evident motion.
func begin_carry(
		id: String,
		data_path: Array,
		render_path: Array,
		duration: float,
		receipt: Dictionary = {}
	) -> bool:
	if _gs == null or not _gs.has_method("command_external_path_traversal") \
			or data_path.size() < 2 or render_path.size() != data_path.size():
		return false
	return bool(_gs.command_external_path_traversal(
		id, traversal_id(id), data_path, render_path, duration, &"locked", receipt))


## Pin all active passengers to the path position at the current authoritative tick. At a normal
## mechanism commit this is the exact endpoint, even if callback ordering dispatches commit before
## the traversal's own completion callback. Returns the finalized occupant ids.
func finalize_carries(reason: StringName = &"platform_state_commit") -> Array[String]:
	var finalized: Array[String] = []
	if _gs == null or not _gs.has_method("get_external_traversal_state"):
		return finalized
	for id_v in _gs.characters.keys():
		var id := str(id_v)
		if not _gs.is_external_traversal_active(id):
			continue
		var state: Dictionary = _gs.get_external_traversal_state(id)
		if not owns_traversal(str(state.get("traversal_id", ""))):
			continue
		if _gs.cancel_external_traversal(id, reason):
			finalized.append(id)
	if not _motion_window.is_empty():
		_motion_window["active"] = false
	return finalized


func traversal_id(id: String) -> StringName:
	return StringName("%s%s/%s" % [TRAVERSAL_PREFIX, _platform_id, id])


func owns_traversal(candidate: String) -> bool:
	return candidate.begins_with("%s%s/" % [TRAVERSAL_PREFIX, _platform_id])

