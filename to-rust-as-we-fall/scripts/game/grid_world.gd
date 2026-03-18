class_name GridWorld
extends RefCounted

## Authoritative 2D grid — source of truth for world layout and pathfinding.
## grid[z][x] of tile type ints. 3D rendering is a separate layer on top.

enum Tile {
	FLOOR = 0,
	WALL = 1,
	FLORA = 2,
	IRON_BLOOM = 3,
	SHELTER = 4,
	TERMINAL = 5,
	FOOD = 6,
	KEY = 7,
	LOCKED_DOOR = 8,
	HIDE_DOOR = 9,
}

var width := 0
var height := 0
var grid: Array = []  # Array of Array[int] — grid[z][x]
var cell_size := 1.0
var origin := Vector3.ZERO

# --- Loading ---

## Load from an array of strings (prototype MAP_DATA format).
## Each character maps to a tile type (0-9).
func load_from_strings(data: PackedStringArray) -> void:
	height = data.size()
	width = 0
	grid.clear()
	for z in range(height):
		var row: Array[int] = []
		var line := data[z]
		if line.length() > width:
			width = line.length()
		for x in range(line.length()):
			var ch := line[x]
			if ch == " " or ch == ".":
				row.append(Tile.FLOOR)
			else:
				var val := ch.to_int()
				row.append(clampi(val, 0, 9))
		grid.append(row)
	# Pad shorter rows to uniform width
	for z in range(height):
		while grid[z].size() < width:
			grid[z].append(Tile.FLOOR)

## Load map from a JSON file that has a "map" key with string array.
func load_from_json(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("GridWorld: Could not open %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("GridWorld: JSON parse error in %s" % path)
		return
	var data: Dictionary = json.data
	if data.has("map"):
		var map_lines: PackedStringArray = PackedStringArray()
		for line in data["map"]:
			map_lines.append(line)
		load_from_strings(map_lines)

## Create a simple rectangular room with wall borders.
func create_room(w: int, h: int, wall_border := true) -> void:
	width = w
	height = h
	grid.clear()
	for z in range(h):
		var row: Array[int] = []
		for x in range(w):
			if wall_border and (z == 0 or z == h - 1 or x == 0 or x == w - 1):
				row.append(Tile.WALL)
			else:
				row.append(Tile.FLOOR)
		grid.append(row)

## Set a specific tile. Bounds-checked.
func set_tile(x: int, z: int, tile: int) -> void:
	if x >= 0 and x < width and z >= 0 and z < height:
		grid[z][x] = tile

# --- Queries ---

func get_tile(x: int, z: int) -> int:
	if x < 0 or x >= width or z < 0 or z >= height:
		return Tile.WALL  # Out of bounds = wall
	return grid[z][x]

func is_walkable(x: int, z: int, explored: Dictionary = {}, locked_doors: Dictionary = {}) -> bool:
	var tile := get_tile(x, z)
	if tile == Tile.WALL:
		return false
	if tile == Tile.LOCKED_DOOR:
		var key := Vector2i(x, z)
		if locked_doors.has(key) and locked_doors[key]:
			return false
	# If we have explored data and this cell is known to be a wall, block it
	# Unknown tiles are passable (fog of war — optimistic pathfinding)
	return true

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var local := world_pos - origin
	var gx := int(floor(local.x / cell_size))
	var gz := int(floor(local.z / cell_size))
	return Vector2i(gx, gz)

func grid_to_world(cell: Vector2i) -> Vector3:
	return origin + Vector3(
		cell.x * cell_size + cell_size * 0.5,
		0.0,
		cell.y * cell_size + cell_size * 0.5
	)

func is_in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < width and z >= 0 and z < height

# --- Pathfinding (A*, 8-directional) ---

## Find a path from start cell to end cell.
## Returns array of world positions (Vector3) for the path waypoints.
func find_path(
	start: Vector2i,
	end: Vector2i,
	explored: Dictionary = {},
	cautious: bool = false,
	roads: Dictionary = {},
	locked_doors: Dictionary = {}
) -> Array[Vector3]:
	if start == end:
		return [grid_to_world(end)]
	if not is_in_bounds(end.x, end.y):
		return []
	if not is_walkable(end.x, end.y, explored, locked_doors):
		return []

	# A* with octile heuristic
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}  # Vector2i -> Vector2i
	var g_score: Dictionary = {}    # Vector2i -> float
	var f_score: Dictionary = {}    # Vector2i -> float

	g_score[start] = 0.0
	f_score[start] = _heuristic(start, end)

	# 8 directions: cardinal + diagonal
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]

	var iterations := 0
	var max_iterations := width * height * 4

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1

		# Find node with lowest f_score
		var current := open_set[0]
		var best_f: float = f_score.get(current, INF)
		for i in range(1, open_set.size()):
			var f: float = f_score.get(open_set[i], INF)
			if f < best_f:
				best_f = f
				current = open_set[i]

		if current == end:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		for dir in dirs:
			var neighbor := current + dir
			if not is_in_bounds(neighbor.x, neighbor.y):
				continue
			if not is_walkable(neighbor.x, neighbor.y, explored, locked_doors):
				continue

			# Diagonal corner-cutting prevention
			var is_diagonal := dir.x != 0 and dir.y != 0
			if is_diagonal:
				var adj_a := Vector2i(current.x + dir.x, current.y)
				var adj_b := Vector2i(current.x, current.y + dir.y)
				if not is_walkable(adj_a.x, adj_a.y, explored, locked_doors):
					continue
				if not is_walkable(adj_b.x, adj_b.y, explored, locked_doors):
					continue

			# Movement cost
			var base_cost := 1.414 if is_diagonal else 1.0

			# Cautious mode: penalize IRON_BLOOM tiles
			if cautious and get_tile(neighbor.x, neighbor.y) == Tile.IRON_BLOOM:
				base_cost += 20.0

			# Road bonus
			if roads.has(neighbor):
				base_cost -= 0.4

			var tentative_g: float = g_score.get(current, INF) + base_cost
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end)
				if neighbor not in open_set:
					open_set.append(neighbor)

	# No path found
	return []

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Octile distance
	var dx := absf(a.x - b.x)
	var dz := absf(a.y - b.y)
	return maxf(dx, dz) + (1.414 - 1.0) * minf(dx, dz)

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector3]:
	var cells: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		cells.append(current)
	cells.reverse()
	# Convert to world positions (skip start cell — player is already there)
	var path: Array[Vector3] = []
	for i in range(1, cells.size()):
		path.append(grid_to_world(cells[i]))
	return path

## Find all tiles of a given type. Returns array of Vector2i grid positions.
func find_tiles(tile_type: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(height):
		for x in range(width):
			if grid[z][x] == tile_type:
				result.append(Vector2i(x, z))
	return result
