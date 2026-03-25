class_name GameState
extends RefCounted

## Central data authority for all character state and movement.
## Movement uses path interpolation driven by EventScheduler ticks.
## Position is computed on read — no per-frame tick needed.

signal character_arrived(id: String)

var grid: GridWorld
var scheduler: EventScheduler
var explored: Dictionary = {}
var characters: Dictionary = {}

## CharDict schema:
## {
##   position: Vector3,         # Settled position (updated on arrival/stop)
##   grid_cell: Vector2i,       # Settled grid cell
##   move_speed: float,
##   stats: Dictionary,
##   movement: Dictionary|null  # Non-null when in motion
##     {
##       path: Array[Vector3],
##       cum_dist: Array[float],
##       total_distance: float,
##       start_tick: float,
##       duration: float,
##       handle: int,
##     }
## }

func register_character(id: String, pos: Vector3, speed: float = 3.0, stats: Dictionary = {}) -> void:
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	characters[id] = {
		"position": pos,
		"grid_cell": cell,
		"move_speed": speed,
		"stats": stats,
		"movement": null,
	}
	explored[id] = {}

func unregister_character(id: String) -> void:
	if characters.has(id):
		_cancel_movement(id)
	characters.erase(id)
	explored.erase(id)

# --- Movement Commands ---

## A* pathfind to a grid cell. Returns true if a path was found.
func command_move_to_cell(id: String, cell: Vector2i) -> bool:
	if not characters.has(id) or not grid or not scheduler:
		return false
	var current_pos := get_position(id)
	var current_cell := grid.world_to_grid(current_pos)
	var path := grid.find_path(current_cell, cell)
	if path.is_empty():
		return false
	_cancel_movement(id)
	characters[id].position = current_pos
	var full_path: Array[Vector3] = [current_pos]
	full_path.append_array(path)
	_start_movement(id, full_path)
	return true

## Straight-line move to a world position.
func command_move_to_pos(id: String, pos: Vector3) -> bool:
	if not characters.has(id) or not scheduler:
		return false
	var current_pos := get_position(id)
	var target := Vector3(pos.x, current_pos.y, pos.z)
	_cancel_movement(id)
	characters[id].position = current_pos
	_start_movement(id, [current_pos, target])
	return true

## Set an explicit path (scripted waypoints).
func command_walk_path(id: String, path: Array[Vector3]) -> void:
	if not characters.has(id) or not scheduler or path.is_empty():
		return
	var current_pos := get_position(id)
	_cancel_movement(id)
	characters[id].position = current_pos
	var full_path: Array[Vector3] = [current_pos]
	full_path.append_array(path)
	_start_movement(id, full_path)

## Halt movement at current interpolated position.
func command_stop(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement != null:
		ch.position = get_position(id)
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
	_cancel_movement(id)

## Change movement speed. If currently moving, recalculates arrival time.
func change_move_speed(id: String, new_speed: float) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	ch.move_speed = new_speed
	if ch.movement == null:
		return
	var current_pos := get_position(id)
	var dest: Vector3 = ch.movement.path[ch.movement.path.size() - 1]
	_cancel_movement(id)
	ch.position = current_pos
	if grid:
		var dest_cell := grid.world_to_grid(dest)
		var current_cell := grid.world_to_grid(current_pos)
		var path := grid.find_path(current_cell, dest_cell)
		if not path.is_empty():
			var full_path: Array[Vector3] = [current_pos]
			full_path.append_array(path)
			_start_movement(id, full_path)
			return
	_start_movement(id, [current_pos, dest])

# --- Queries ---

## Current position — interpolated if moving, settled if stationary.
func get_position(id: String) -> Vector3:
	if not characters.has(id):
		return Vector3.ZERO
	var ch: Dictionary = characters[id]
	if ch.movement == null or not scheduler:
		return ch.position
	var mv: Dictionary = ch.movement
	if mv.duration <= 0.0:
		return mv.path[mv.path.size() - 1]
	var t := clampf((scheduler.get_current_tick() - mv.start_tick) / mv.duration, 0.0, 1.0)
	return _interpolate_path(mv.path, mv.cum_dist, t)

func is_moving(id: String) -> bool:
	if not characters.has(id):
		return false
	return characters[id].movement != null

func get_grid_cell(id: String) -> Vector2i:
	if not grid:
		return Vector2i.ZERO
	return grid.world_to_grid(get_position(id))

# --- Serialization ---

## Snapshot for save/load. Movement is not serialized — sequences re-establish it.
func serialize() -> Dictionary:
	var char_data := {}
	for id in characters:
		var pos := get_position(id)
		var ch: Dictionary = characters[id]
		char_data[id] = {
			"position": [pos.x, pos.y, pos.z],
			"grid_cell": [ch.grid_cell.x, ch.grid_cell.y],
			"move_speed": ch.move_speed,
			"stats": ch.stats.duplicate(),
		}
	return {
		"characters": char_data,
		"explored": _serialize_explored(),
	}

func deserialize(data: Dictionary) -> void:
	if data.has("characters"):
		for id in data.characters:
			var cd: Dictionary = data.characters[id]
			var pos := Vector3(cd.position[0], cd.position[1], cd.position[2])
			register_character(id, pos, cd.get("move_speed", 3.0), cd.get("stats", {}))
	if data.has("explored"):
		_deserialize_explored(data.explored)

# --- Internal ---

func _start_movement(id: String, full_path: Array[Vector3]) -> void:
	var ch: Dictionary = characters[id]
	var cum_dist := _compute_cum_dist(full_path)
	var total_dist: float = cum_dist[cum_dist.size() - 1]
	if total_dist < 0.01:
		ch.position = full_path[full_path.size() - 1]
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
		character_arrived.emit(id)
		return
	var speed: float = ch.move_speed
	var duration := total_dist / speed
	var start_tick := scheduler.get_current_tick()
	var handle := scheduler.schedule_at(
		start_tick + duration,
		func(): _on_arrival(id),
		"movement_" + id
	)
	ch.movement = {
		"path": full_path,
		"cum_dist": cum_dist,
		"total_distance": total_dist,
		"start_tick": start_tick,
		"duration": duration,
		"handle": handle,
	}

func _cancel_movement(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement != null:
		if scheduler:
			scheduler.cancel(ch.movement.handle)
		ch.movement = null

func _on_arrival(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement == null:
		return
	var dest: Vector3 = ch.movement.path[ch.movement.path.size() - 1]
	ch.position = dest
	if grid:
		ch.grid_cell = grid.world_to_grid(dest)
	ch.movement = null
	character_arrived.emit(id)

static func _compute_cum_dist(path: Array[Vector3]) -> Array[float]:
	var result: Array[float] = [0.0]
	for i in range(1, path.size()):
		var dx := path[i].x - path[i - 1].x
		var dz := path[i].z - path[i - 1].z
		result.append(result[result.size() - 1] + sqrt(dx * dx + dz * dz))
	return result

static func _interpolate_path(path: Array[Vector3], cum_dist: Array[float], t: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if path.size() == 1 or t <= 0.0:
		return path[0]
	if t >= 1.0:
		return path[path.size() - 1]
	var total := cum_dist[cum_dist.size() - 1]
	var target_dist := t * total
	for i in range(1, cum_dist.size()):
		if cum_dist[i] >= target_dist:
			var seg_start := cum_dist[i - 1]
			var seg_len := cum_dist[i] - seg_start
			if seg_len < 0.001:
				return path[i]
			var seg_t := (target_dist - seg_start) / seg_len
			return path[i - 1].lerp(path[i], seg_t)
	return path[path.size() - 1]

func _serialize_explored() -> Dictionary:
	var result := {}
	for id in explored:
		var cells: Dictionary = explored[id]
		var cell_list := []
		for cell in cells:
			cell_list.append([cell.x, cell.y])
		result[id] = cell_list
	return result

func _deserialize_explored(data: Dictionary) -> void:
	for id in data:
		explored[id] = {}
		for cell_arr in data[id]:
			explored[id][Vector2i(cell_arr[0], cell_arr[1])] = true
