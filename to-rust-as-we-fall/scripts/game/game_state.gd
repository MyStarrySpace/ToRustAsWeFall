class_name GameState
extends RefCounted

## Central data authority for all character movement and state.
## Both 3D scenes and headless CLI/sim converge here.
## Pure data — no Node dependency.

signal character_arrived(id: String)
signal character_moved(id: String, pos: Vector3, cell: Vector2i)

var grid: GridWorld  ## Nullable — when null, straight-line movement only
var explored: Dictionary = {}  ## String → Dictionary[Vector2i → bool]
var characters: Dictionary = {}  ## String → Dictionary (CharDict)

## CharDict schema:
## {
##   position: Vector3,
##   grid_cell: Vector2i,
##   path: Array[Vector3],
##   path_index: int,
##   is_moving: bool,
##   move_speed: float,
##   stats: Dictionary,
## }

func register_character(id: String, pos: Vector3, speed: float = 3.0, stats: Dictionary = {}) -> void:
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	characters[id] = {
		"position": pos,
		"grid_cell": cell,
		"path": [] as Array[Vector3],
		"path_index": 0,
		"is_moving": false,
		"move_speed": speed,
		"stats": stats,
	}
	explored[id] = {}

func unregister_character(id: String) -> void:
	characters.erase(id)
	explored.erase(id)

## A* pathfind to a grid cell. Returns true if a path was found.
func command_move_to_cell(id: String, cell: Vector2i) -> bool:
	if not characters.has(id) or not grid:
		return false
	var ch: Dictionary = characters[id]
	var current_cell := grid.world_to_grid(ch.position)
	var path := grid.find_path(current_cell, cell)
	if path.is_empty():
		return false
	ch.path = path
	ch.path_index = 0
	ch.is_moving = true
	return true

## Straight-line move to a world position. Returns true.
func command_move_to_pos(id: String, pos: Vector3) -> bool:
	if not characters.has(id):
		return false
	var ch: Dictionary = characters[id]
	var target := Vector3(pos.x, ch.position.y, pos.z)
	ch.path = [target] as Array[Vector3]
	ch.path_index = 0
	ch.is_moving = true
	return true

## Set an explicit path (scripted waypoints).
func command_walk_path(id: String, path: Array[Vector3]) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	ch.path = path
	ch.path_index = 0
	ch.is_moving = true

## Halt movement.
func command_stop(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	ch.is_moving = false
	ch.path.clear()
	ch.path_index = 0

## Advance all characters along their paths. Call each frame.
## For CharacterBody3D characters (player), the node reads the path
## and drives move_and_slide() itself, then calls update_position().
## For Node3D characters (NPCs), tick() moves them directly.
func tick(delta: float) -> void:
	for id in characters:
		var ch: Dictionary = characters[id]
		if not ch.is_moving or ch.path.is_empty():
			continue
		if ch.path_index >= ch.path.size():
			_finish_path(id)
			continue
		var waypoint: Vector3 = ch.path[ch.path_index]
		var pos: Vector3 = ch.position
		var dir: Vector3 = waypoint - pos
		dir.y = 0
		if dir.length() < 0.2:
			ch.position = Vector3(waypoint.x, pos.y, waypoint.z)
			ch.path_index += 1
			if ch.path_index >= ch.path.size():
				_finish_path(id)
			continue
		var step: Vector3 = dir.normalized() * ch.move_speed * delta
		if step.length() > dir.length():
			step = dir
		ch.position += step
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
		character_moved.emit(id, ch.position, ch.grid_cell)

## Called by Player node after move_and_slide() to sync position back.
func update_position(id: String, pos: Vector3) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	ch.position = pos
	if grid:
		ch.grid_cell = grid.world_to_grid(pos)
	# Check if close enough to current waypoint to advance
	if ch.is_moving and not ch.path.is_empty() and ch.path_index < ch.path.size():
		var waypoint: Vector3 = ch.path[ch.path_index]
		var dist := Vector2(pos.x - waypoint.x, pos.z - waypoint.z).length()
		if dist < 0.2:
			ch.path_index += 1
			if ch.path_index >= ch.path.size():
				_finish_path(id)
	character_moved.emit(id, pos, ch.grid_cell)

func _finish_path(id: String) -> void:
	var ch: Dictionary = characters[id]
	ch.is_moving = false
	ch.path.clear()
	ch.path_index = 0
	character_arrived.emit(id)

## Get the next waypoint for a character (used by Player node for velocity).
func get_next_waypoint(id: String) -> Vector3:
	if not characters.has(id):
		return Vector3.INF
	var ch: Dictionary = characters[id]
	if not ch.is_moving or ch.path.is_empty() or ch.path_index >= ch.path.size():
		return Vector3.INF
	return ch.path[ch.path_index]

func is_moving(id: String) -> bool:
	if not characters.has(id):
		return false
	return characters[id].is_moving

## Full snapshot for save/load.
func serialize() -> Dictionary:
	var char_data := {}
	for id in characters:
		var ch: Dictionary = characters[id]
		char_data[id] = {
			"position": [ch.position.x, ch.position.y, ch.position.z],
			"grid_cell": [ch.grid_cell.x, ch.grid_cell.y],
			"is_moving": ch.is_moving,
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
