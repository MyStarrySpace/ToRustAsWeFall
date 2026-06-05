class_name GridWorld
extends RefCounted

## Authoritative 2D grid for world layout and pathfinding.
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
var dynamic_blockers: Dictionary = {}  # Vector2i → obj_id

# --- Multi-level support (stacked floors). The grid stays a single 2D plane of cells; a LEVEL is
# the same (x,z) plane lifted by level_height in world Y. A character's level is tracked in
# GameState; grid_to_world(cell, level) places the cell at that floor's height. Ladders/ramps are
# inter-level LINKS at a cell, registered here. Backward-compatible: level defaults to 0 → Y=0. ---
var level_count := 1
var level_height := 4.0               # world Y between stacked floors
var inter_level_links: Dictionary = {}  # "x,z,from,to" -> {type, cost}

func set_level_count(count: int) -> void:
	level_count = maxi(1, count)

## Which stacked floor a world Y sits on (0 for a single-floor grid). Inverse of grid_to_world's Y.
func level_for_y(y: float) -> int:
	if level_count <= 1 or level_height <= 0.0:
		return 0
	return clampi(int(round((y - origin.y) / level_height)), 0, level_count - 1)

func _link_key(cell: Vector2i, from_level: int, to_level: int) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, from_level, to_level]

## Register a ladder/ramp at a cell that lets a character move between two adjacent levels. Bidirectional
## by default — adds both directions. link_type: "ladder" (climb, costlier) or "ramp" (walk).
func add_inter_level_link(cell: Vector2i, from_level: int, to_level: int, link_type := "ladder", bidirectional := true) -> void:
	var cost := 2.0 if link_type == "ladder" else 1.3
	inter_level_links[_link_key(cell, from_level, to_level)] = {"type": link_type, "cost": cost}
	if bidirectional:
		inter_level_links[_link_key(cell, to_level, from_level)] = {"type": link_type, "cost": cost}

func can_traverse_link(cell: Vector2i, from_level: int, to_level: int) -> bool:
	return inter_level_links.has(_link_key(cell, from_level, to_level))

func get_link_cost(cell: Vector2i, from_level: int, to_level: int) -> float:
	return float(inter_level_links.get(_link_key(cell, from_level, to_level), {}).get("cost", 1.0))

## The levels a character at this cell+level can step to (via a ladder/ramp here).
func links_from(cell: Vector2i, from_level: int) -> Array:
	var out: Array = []
	for to_level in range(level_count):
		if to_level != from_level and can_traverse_link(cell, from_level, to_level):
			out.append(to_level)
	return out

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
	if dynamic_blockers.has(Vector2i(x, z)):
		return false
	return true

func add_dynamic_blocker(cell: Vector2i, obj_id: String) -> void:
	dynamic_blockers[cell] = obj_id

func remove_dynamic_blocker(cell: Vector2i) -> void:
	dynamic_blockers.erase(cell)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var local := world_pos - origin
	var gx := int(floor(local.x / cell_size))
	var gz := int(floor(local.z / cell_size))
	return Vector2i(gx, gz)

func grid_to_world(cell: Vector2i, level: int = 0) -> Vector3:
	return origin + Vector3(
		cell.x * cell_size + cell_size * 0.5,
		float(level) * level_height,
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
	locked_doors: Dictionary = {},
	level: int = 0
) -> Array[Vector3]:
	if start == end:
		return [grid_to_world(end, level)]
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
			return _reconstruct_path(came_from, current, level)

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

## A* ACROSS floors: route from (start_cell, start_level) to (end_cell, end_level) using same-level
## 8-dir moves PLUS ladder/ramp transitions at link cells. Returns an ordered list of
## {cell: Vector2i, level: int} waypoints — a level change happens between two consecutive
## waypoints that share a cell (the link). [] if unreachable. State space is (cell, level); grids
## are small so this stays cheap. Used for player-directed cross-level moves.
func find_multi_level_path(
	start_cell: Vector2i, start_level: int, end_cell: Vector2i, end_level: int,
	explored: Dictionary = {}, locked_doors: Dictionary = {}
) -> Array:
	if start_cell == end_cell and start_level == end_level:
		return [{"cell": end_cell, "level": end_level}]
	if not is_in_bounds(end_cell.x, end_cell.y) or not is_walkable(end_cell.x, end_cell.y, explored, locked_doors):
		return []
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var start_key := _ml_key(start_cell, start_level)
	var open: Array = [start_key]
	var came_from: Dictionary = {}
	var g: Dictionary = {start_key: 0.0}
	var f: Dictionary = {start_key: _ml_h(start_cell, start_level, end_cell, end_level)}
	var iters := 0
	var max_iters := width * height * maxi(1, level_count) * 6
	while not open.is_empty() and iters < max_iters:
		iters += 1
		var cur_key: String = open[0]
		var best_f: float = f.get(cur_key, INF)
		for i in range(1, open.size()):
			var ff: float = f.get(open[i], INF)
			if ff < best_f:
				best_f = ff
				cur_key = open[i]
		var cur_cell: Vector2i = _ml_cell(cur_key)
		var cur_level: int = _ml_level(cur_key)
		if cur_cell == end_cell and cur_level == end_level:
			return _ml_reconstruct(came_from, cur_key)
		open.erase(cur_key)
		var cur_g: float = g.get(cur_key, INF)
		# Same-level 8-dir moves.
		for dir in dirs:
			var nb := cur_cell + dir
			if not is_in_bounds(nb.x, nb.y) or not is_walkable(nb.x, nb.y, explored, locked_doors):
				continue
			var is_diag := dir.x != 0 and dir.y != 0
			if is_diag:
				if not is_walkable(cur_cell.x + dir.x, cur_cell.y, explored, locked_doors):
					continue
				if not is_walkable(cur_cell.x, cur_cell.y + dir.y, explored, locked_doors):
					continue
			_ml_relax(_ml_key(nb, cur_level), cur_key, cur_g + (1.414 if is_diag else 1.0),
				nb, cur_level, end_cell, end_level, came_from, g, f, open)
		# Ladder/ramp transitions at the current cell.
		for to_level in links_from(cur_cell, cur_level):
			_ml_relax(_ml_key(cur_cell, to_level), cur_key, cur_g + get_link_cost(cur_cell, cur_level, to_level),
				cur_cell, to_level, end_cell, end_level, came_from, g, f, open)
	return []

func _ml_key(cell: Vector2i, level: int) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, level]

func _ml_cell(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))

func _ml_level(key: String) -> int:
	return int(key.split(",")[2])

func _ml_h(cell: Vector2i, level: int, end_cell: Vector2i, end_level: int) -> float:
	return _heuristic(cell, end_cell) + absf(level - end_level) * 1.5

func _ml_relax(nkey: String, from_key: String, tentative_g: float, cell: Vector2i, level: int,
		end_cell: Vector2i, end_level: int, came_from: Dictionary, g: Dictionary, f: Dictionary, open: Array) -> void:
	if tentative_g < float(g.get(nkey, INF)):
		came_from[nkey] = from_key
		g[nkey] = tentative_g
		f[nkey] = tentative_g + _ml_h(cell, level, end_cell, end_level)
		if not open.has(nkey):
			open.append(nkey)

func _ml_reconstruct(came_from: Dictionary, current: String) -> Array:
	var keys: Array = [current]
	while came_from.has(current):
		current = came_from[current]
		keys.append(current)
	keys.reverse()
	var out: Array = []
	for k in keys:
		out.append({"cell": _ml_cell(k), "level": _ml_level(k)})
	return out

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Octile distance
	var dx := absf(a.x - b.x)
	var dz := absf(a.y - b.y)
	return maxf(dx, dz) + (1.414 - 1.0) * minf(dx, dz)

func _reconstruct_path(came_from: Dictionary, current: Vector2i, level: int = 0) -> Array[Vector3]:
	var cells: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		cells.append(current)
	cells.reverse()
	# Convert to world positions, skipping the occupied start cell.
	var path: Array[Vector3] = []
	for i in range(1, cells.size()):
		path.append(grid_to_world(cells[i], level))
	return path

## Find all tiles of a given type. Returns array of Vector2i grid positions.
func find_tiles(tile_type: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(height):
		for x in range(width):
			if grid[z][x] == tile_type:
				result.append(Vector2i(x, z))
	return result
