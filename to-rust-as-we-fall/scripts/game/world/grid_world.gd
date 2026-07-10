class_name GridWorld
extends RefCounted

## Authoritative 2D grid for world layout and pathfinding.
## grid[z][x] of tile type ints. 3D rendering is a separate layer on top.

## Pathfinding tracing — run with PATHFIND_DEBUG=1. Prints every A* search (start/end + iters) AND appends
## to a FLUSHED file (user://pathfind.log) that survives a hard crash/segfault — the LAST line is the search
## that died. Env-gated so normal runs (and the test suite) aren't slowed by per-search file I/O.
static var _pf_debug: bool = OS.has_environment("PATHFIND_DEBUG")
static var _pf_file: FileAccess = null

## FX/render tracing — run with FX_DEBUG=1. A SEPARATE channel from the A* path tracing above, for the path
## PREVIEW ribbon + the interactable OUTLINE hit chain (so a hover-debug session isn't buried under per-search
## A* spam). Routes through the same _pf_trace printer. Env-gated; off in normal runs and the test suite.
static var _fx_debug: bool = OS.has_environment("FX_DEBUG")

static func _pf_trace(msg: String) -> void:
	print(msg)
	if _pf_file == null:
		_pf_file = FileAccess.open("user://pathfind.log", FileAccess.WRITE)
	if _pf_file != null:
		_pf_file.store_line(msg)
		_pf_file.flush()

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

# --- Per-cell risk (the safe/direct routing vocabulary). A risky cell stays WALKABLE — risk only
# shapes route choice. In CAUTIOUS (safe) routing a recoverable risky cell costs extra (the planner
# detours around it when a detour exists) and a NON-recoverable one is never entered (no safe route
# may exist at all — the player must go direct). Direct routing ignores risk entirely; any harm from
# crossing is gameplay applied by the scene/chunk, not the pathfinder. ---
var risk_cells: Dictionary = {}  # Vector2i -> {"penalty": float, "recoverable": bool}

# --- Multi-level support (stacked floors). The grid stays a single 2D plane of cells; a LEVEL is
# the same (x,z) plane lifted by level_height in world Y. A character's level is tracked in
# GameState; grid_to_world(cell, level) places the cell at that floor's height. Ladders/ramps are
# inter-level LINKS at a cell, registered here. Backward-compatible: level defaults to 0 → Y=0. ---
var level_count := 1
var level_height := 4.0               # world Y between stacked floors
var inter_level_links: Dictionary = {}  # "x,z,from,to" -> {type, cost}
## Per-level walkable footprints. Stacked floors rarely share a footprint (the elevator's upper
## deck and lower deck overlap in X but live on different levels), so walkability is per (cell,
## level). A level ABSENT here is fully walkable — single-floor scenes never touch it, so they are
## unchanged. Once a level has ANY allowed cell it is RESTRICTED: only its allow-set is walkable.
var level_allowed: Dictionary = {}   # level(int) -> Dictionary of Vector2i -> true

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

# --- Per-level walkable footprints (stacked floors with different shapes) ---

## Mark a single cell walkable on a level (this RESTRICTS the level to its allow-set).
func allow_cell_on_level(cell: Vector2i, level: int) -> void:
	if not level_allowed.has(level):
		level_allowed[level] = {}
	level_allowed[level][cell] = true

## Mark an inclusive rectangle of cells walkable on a level.
func allow_cell_region_on_level(min_cell: Vector2i, max_cell: Vector2i, level: int) -> void:
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			allow_cell_on_level(Vector2i(x, z), level)

## Mark a world-space XZ rectangle walkable on a level — convenient when authoring from world
## coordinates (a chunk's footprint). Converts the AABB corners to cells.
func allow_world_region_on_level(min_xz: Vector2, max_xz: Vector2, level: int) -> void:
	var a := world_to_grid(Vector3(min_xz.x, 0.0, min_xz.y))
	var b := world_to_grid(Vector3(max_xz.x, 0.0, max_xz.y))
	allow_cell_region_on_level(a, b, level)

## True once a level has been given a footprint (only its allow-set is walkable on that level).
func is_level_restricted(level: int) -> bool:
	return level_allowed.has(level)

## Whether a cell is inside a level's footprint. Unrestricted levels allow every cell.
func is_cell_allowed_on_level(cell: Vector2i, level: int) -> bool:
	if not level_allowed.has(level):
		return true
	return level_allowed[level].has(cell)

# --- Loading ---

const GRID_DATA_CONTRACT_ID := "unified_grid_v1"

## Build a grid from a plain-data dictionary — the contract a scene chunk's get_grid_data() returns.
## Everything is authored in WORLD XZ rectangles (chunks think in world space): the footprint starts
## as solid WALL and walkable_regions carve FLOOR; risk_regions lay per-cell risk on top; optional
## stacked levels with per-level footprints and ladder/ramp links. Pure data → deterministic build,
## so the preview, tests, and CLI all construct the identical grid.
static func from_data(data: Dictionary) -> GridWorld:
	var g := GridWorld.new()
	g.origin = _arr_to_vec3(data.get("origin", [0.0, 0.0, 0.0]))
	g.cell_size = float(data.get("cell_size", 1.0))
	var w := int(data.get("width", 0))
	var h := int(data.get("height", 0))
	g.create_room(w, h, false)
	if not bool(data.get("default_walkable", false)):
		for z in range(h):
			for x in range(w):
				g.grid[z][x] = Tile.WALL
	for region in data.get("walkable_regions", []):
		var r := region as Dictionary
		var a := g.world_to_grid(_xz_to_vec3(r.get("min", [0, 0])))
		var b := g.world_to_grid(_xz_to_vec3(r.get("max", [0, 0])))
		for z in range(maxi(0, mini(a.y, b.y)), mini(h - 1, maxi(a.y, b.y)) + 1):
			for x in range(maxi(0, mini(a.x, b.x)), mini(w - 1, maxi(a.x, b.x)) + 1):
				g.grid[z][x] = Tile.FLOOR
	for cell in data.get("wall_cells", []):
		var c := _arr_to_vec2i(cell)
		g.set_tile(c.x, c.y, Tile.WALL)
	# Explicit CELL lists — for carved shapes world-rects can't express (rasterized diagonal
	# corridors from the generator). Cell coordinates, not world.
	for cell in data.get("walkable_cells", []):
		var wc := _arr_to_vec2i(cell)
		g.set_tile(wc.x, wc.y, Tile.FLOOR)
	for region in data.get("risk_regions", []):
		var r := region as Dictionary
		g.set_world_region_risk(
			_xz_to_vec2(r.get("min", [0, 0])), _xz_to_vec2(r.get("max", [0, 0])),
			float(r.get("penalty", 20.0)), bool(r.get("recoverable", true)))
	for entry in data.get("risk_cell_list", []):
		var rc := entry as Dictionary
		g.set_cell_risk(_arr_to_vec2i(rc.get("cell", [0, 0])),
			float(rc.get("penalty", 20.0)), bool(rc.get("recoverable", true)))
	g.set_level_count(int(data.get("level_count", 1)))
	g.level_height = float(data.get("level_height", g.level_height))
	for region in data.get("level_regions", []):
		var r := region as Dictionary
		g.allow_world_region_on_level(
			_xz_to_vec2(r.get("min", [0, 0])), _xz_to_vec2(r.get("max", [0, 0])), int(r.get("level", 0)))
	for entry in data.get("level_cells", []):
		var lc := entry as Dictionary
		for cell in lc.get("cells", []):
			g.allow_cell_on_level(_arr_to_vec2i(cell), int(lc.get("level", 0)))
	for link in data.get("links", []):
		var l := link as Dictionary
		g.add_inter_level_link(_arr_to_vec2i(l.get("cell", [0, 0])),
			int(l.get("from", 0)), int(l.get("to", 1)), str(l.get("type", "ladder")))
	return g

static func _arr_to_vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO

static func _xz_to_vec3(raw: Variant) -> Vector3:
	var v := _xz_to_vec2(raw)
	return Vector3(v.x, 0.0, v.y)

static func _xz_to_vec2(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO

static func _arr_to_vec2i(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO

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

func is_walkable(x: int, z: int, explored: Dictionary = {}, locked_doors: Dictionary = {}, level: int = 0) -> bool:
	var tile := get_tile(x, z)
	if tile == Tile.WALL:
		return false
	if tile == Tile.LOCKED_DOOR:
		var key := Vector2i(x, z)
		if locked_doors.has(key) and locked_doors[key]:
			return false
	if dynamic_blockers.has(Vector2i(x, z)):
		return false
	# Per-level footprint: a restricted level only allows cells in its allow-set.
	if level_allowed.has(level) and not level_allowed[level].has(Vector2i(x, z)):
		return false
	return true

func add_dynamic_blocker(cell: Vector2i, obj_id: String) -> void:
	dynamic_blockers[cell] = obj_id

func remove_dynamic_blocker(cell: Vector2i) -> void:
	dynamic_blockers.erase(cell)

# --- Sight blocking (line of sight). A cell blocks sight if it's a WALL / locked door, or an explicitly
# registered sight blocker (for scenes whose walls aren't WALL tiles). Declared at build like occupancy —
# derived, never logged, rebuilt on replay. Used by detection so enemies can't see through walls. ---
var sight_blockers: Dictionary = {}   # Vector2i -> true

func add_sight_blocker(cell: Vector2i) -> void:
	sight_blockers[cell] = true

func clear_sight_blocker(cell: Vector2i) -> void:
	sight_blockers.erase(cell)

# SEE-OVER terrain: a WALL-tiled cell that blocks movement but NOT sight (water basins, canals,
# pits, low kerbs). Registered at build like sight blockers — derived, never logged. An explicit
# sight_blocker on the same cell wins (checked first).
var sight_transparent: Dictionary = {}   # Vector2i -> true

func add_sight_transparent(cell: Vector2i) -> void:
	sight_transparent[cell] = true

func clear_sight_transparent(cell: Vector2i) -> void:
	sight_transparent.erase(cell)

func is_opaque_cell(cell: Vector2i) -> bool:
	if sight_blockers.has(cell):
		return true
	if sight_transparent.has(cell):
		return false
	var tile := get_tile(cell.x, cell.y)
	return tile == Tile.WALL or tile == Tile.LOCKED_DOOR

## True if nothing blocks the straight line between two world points (XZ only). The endpoints' own cells are
## ignored, so a detector/target standing in a doorway never self-blocks. Pure grid query — deterministic, so
## detection that gates on it stays replay-safe (a physics raycast would not).
func has_line_of_sight(from_world: Vector3, to_world: Vector3) -> bool:
	var a := world_to_grid(from_world)
	var b := world_to_grid(to_world)
	if a == b:
		return true
	var dist := Vector2(to_world.x - from_world.x, to_world.z - from_world.z).length()
	var steps := maxi(2, int(ceil(dist / (cell_size * 0.5))))   # sample at least twice per cell so no wall slips through
	for i in range(1, steps):
		var f := float(i) / float(steps)
		var cell := world_to_grid(Vector3(lerpf(from_world.x, to_world.x, f), 0.0, lerpf(from_world.z, to_world.z, f)))
		if cell == a or cell == b:
			continue
		if is_opaque_cell(cell):
			return false
	return true

# --- Per-cell risk authoring + queries ---

func set_cell_risk(cell: Vector2i, penalty := 20.0, recoverable := true) -> void:
	risk_cells[cell] = {"penalty": maxf(0.0, penalty), "recoverable": recoverable}

func clear_cell_risk(cell: Vector2i) -> void:
	risk_cells.erase(cell)

## Mark a world-space XZ rectangle risky — authoring convenience for a hazard band/corridor.
func set_world_region_risk(min_xz: Vector2, max_xz: Vector2, penalty := 20.0, recoverable := true) -> void:
	var a := world_to_grid(Vector3(min_xz.x, 0.0, min_xz.y))
	var b := world_to_grid(Vector3(max_xz.x, 0.0, max_xz.y))
	for z in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			set_cell_risk(Vector2i(x, z), penalty, recoverable)

func is_cell_risky(cell: Vector2i) -> bool:
	return risk_cells.has(cell)

func risk_penalty(cell: Vector2i) -> float:
	return float((risk_cells.get(cell, {}) as Dictionary).get("penalty", 0.0))

## A non-recoverable risky cell is never entered by cautious (safe) routing.
func cautious_cell_blocked(cell: Vector2i) -> bool:
	var info: Dictionary = risk_cells.get(cell, {})
	return not info.is_empty() and not bool(info.get("recoverable", true))

# Geometric reachability over the EXACT same per-cell predicate the planners step with: is_walkable (with
# empty explored/locked_doors, like _plan_cooperative + find_path), the 8-dir + diagonal corner-cut rule,
# and cautious blocking when route-cautious. A plain 2D BFS that IGNORES time + reservations — because
# waiting and reservations never change WHICH cells are reachable, only the timing. So a `false` return
# means "geometrically unreachable in this mode": the space-time cooperative search and find_path both
# provably return empty, and the caller can bail INSTANTLY instead of exhausting a 12k-node wait-state
# search. Early-exits the moment `end` is dequeued; derived + deterministic (fixed visit order), never logged.
func _reach_walkable(x: int, z: int, level: int, cautious: bool) -> bool:
	if not is_walkable(x, z, {}, {}, level):
		return false
	return not (cautious and cautious_cell_blocked(Vector2i(x, z)))

func reachable(start: Vector2i, end: Vector2i, level: int = 0, cautious: bool = false) -> bool:
	if _pf_debug:
		_pf_trace("[A*] reachable BFS %v -> %v" % [start, end])
	if start == end:
		return true
	if not _reach_walkable(start.x, start.y, level, cautious) or not _reach_walkable(end.x, end.y, level, cautious):
		return false
	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for dir in dirs:
			var n: Vector2i = c + dir
			if seen.has(n) or not _reach_walkable(n.x, n.y, level, cautious):
				continue
			if dir.x != 0 and dir.y != 0:
				# Diagonal corner-cut — both orthogonal neighbors must be walkable (mirrors the planners).
				if not _reach_walkable(c.x + dir.x, c.y, level, cautious) or not _reach_walkable(c.x, c.y + dir.y, level, cautious):
					continue
			if n == end:
				return true
			seen[n] = true
			queue.append(n)
	return false

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

## The nearest walkable cell to `cell` on a level (deterministic outward ring scan), or `cell` itself
## when it's already walkable / nothing is found within max_radius. The grid equivalent of the old
## navigation graph's snap-to-nearest-node: a character parked off the carved footprint (teleports,
## chunk spawns, knockbacks) must still be able to route from/to the mesh.
func nearest_walkable_cell(cell: Vector2i, level := 0, max_radius := 6, explored: Dictionary = {}, locked_doors: Dictionary = {}) -> Vector2i:
	if is_walkable(cell.x, cell.y, explored, locked_doors, level):
		return cell
	for r in range(1, max_radius + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue  # ring only — inner radii already scanned
				var c := Vector2i(cell.x + dx, cell.y + dz)
				if is_in_bounds(c.x, c.y) and is_walkable(c.x, c.y, explored, locked_doors, level):
					return c
	return cell

## Resolve a desired world position to a valid character SPAWN point: grounded on the floor (the
## level's Y), and — when the desired spot lands on a NON-walkable cell (a wall border, off the floor,
## a blocker) — moved to the centre of the CLOSEST walkable cell so the character can stand and path
## out. A spot already on a walkable cell keeps its exact XZ (only its Y is grounded). This is the one
## place any scene should route a spawn through, so an authored marker that grazes a wall never strands
## a character on an un-walkable cell. `radius` is the search window in cells.
func nearest_walkable_world(world_pos: Vector3, radius := 3, level := 0) -> Vector3:
	var ground_y := origin.y + level_height * float(level)
	var cell := world_to_grid(world_pos)
	if is_walkable(cell.x, cell.y, {}, {}, level):
		return Vector3(world_pos.x, ground_y, world_pos.z)
	var best := cell
	var best_d := INF
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := Vector2i(cell.x + dx, cell.y + dz)
			if is_in_bounds(c.x, c.y) and is_walkable(c.x, c.y, {}, {}, level):
				var cw := grid_to_world(c, level)
				var d := Vector2(cw.x - world_pos.x, cw.z - world_pos.z).length()
				if d < best_d:
					best_d = d
					best = c
	return grid_to_world(best, level)

# --- Pathfinding (A*, 8-directional) ---

# Binary min-heap for the A* open set (f, then insertion seq for deterministic FIFO ties). Replaces a
# linear min-scan + O(n) `erase` + O(n) `in open_set` membership test — which made find_path O(n²) and,
# for a far target on a big grid, the per-hover preview's bottleneck.
static func _gw_heap_less(a: Dictionary, b: Dictionary) -> bool:
	if a.f != b.f:
		return a.f < b.f
	return int(a.seq) < int(b.seq)

static func _gw_heap_push(heap: Array, node: Dictionary) -> void:
	heap.append(node)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _gw_heap_less(heap[i], heap[parent]):
			break
		var tmp = heap[parent]; heap[parent] = heap[i]; heap[i] = tmp
		i = parent

static func _gw_heap_pop(heap: Array) -> Dictionary:
	var top: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var smallest := i
			var l := 2 * i + 1
			var r := 2 * i + 2
			if l < n and _gw_heap_less(heap[l], heap[smallest]):
				smallest = l
			if r < n and _gw_heap_less(heap[r], heap[smallest]):
				smallest = r
			if smallest == i:
				break
			var tmp = heap[smallest]; heap[smallest] = heap[i]; heap[i] = tmp
			i = smallest
	return top

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
	if not is_walkable(end.x, end.y, explored, locked_doors, level):
		return []
	# (No reachability pre-check here: the heap A* below already explores an unreachable target's whole
	# component in O(n log n) — adding a BFS pre-check would just DOUBLE the cost for the common reachable
	# case. The cull lives in _plan_cooperative, where it saves the far more expensive space-time search.)

	# A* with octile heuristic, binary-heap open set
	if _pf_debug:
		_pf_trace("[A*] find_path start %v -> %v (grid %dx%d, cautious=%s)" % [start, end, width, height, cautious])
	var came_from: Dictionary = {}  # Vector2i -> Vector2i
	var g_score: Dictionary = {start: 0.0}    # Vector2i -> float (best known cost-to-reach)
	var closed: Dictionary = {}     # cells finalized at their best g (lazy-deletion skip)
	var seq := 0
	var open: Array = [{"cell": start, "f": _heuristic(start, end), "seq": seq}]
	seq += 1

	# 8 directions: cardinal + diagonal
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]

	var iterations := 0
	var max_iterations := width * height * 4

	while not open.is_empty() and iterations < max_iterations:
		iterations += 1

		var current: Vector2i = _gw_heap_pop(open).cell
		# A stale duplicate (already finalized cheaper) — skip. Consistent (octile) heuristic, so a cell
		# popped once is at its best g and never needs reopening.
		if closed.has(current):
			continue
		closed[current] = true

		if current == end:
			if _pf_debug:
				_pf_trace("[A*] find_path done: reached in %d iters" % iterations)
			return _reconstruct_path(came_from, current, level)

		for dir in dirs:
			var neighbor := current + dir
			if not is_in_bounds(neighbor.x, neighbor.y):
				continue
			if not is_walkable(neighbor.x, neighbor.y, explored, locked_doors, level):
				continue

			# Diagonal corner-cutting prevention
			var is_diagonal := dir.x != 0 and dir.y != 0
			if is_diagonal:
				var adj_a := Vector2i(current.x + dir.x, current.y)
				var adj_b := Vector2i(current.x, current.y + dir.y)
				if not is_walkable(adj_a.x, adj_a.y, explored, locked_doors, level):
					continue
				if not is_walkable(adj_b.x, adj_b.y, explored, locked_doors, level):
					continue

			# Cautious (safe) routing never enters a non-recoverable risky cell.
			if cautious and cautious_cell_blocked(neighbor):
				continue

			# Movement cost
			var base_cost := 1.414 if is_diagonal else 1.0

			# Cautious mode: penalize IRON_BLOOM tiles and risky cells
			if cautious:
				if get_tile(neighbor.x, neighbor.y) == Tile.IRON_BLOOM:
					base_cost += 20.0
				base_cost += risk_penalty(neighbor)

			# Road bonus
			if roads.has(neighbor):
				base_cost -= 0.4

			var tentative_g: float = g_score.get(current, INF) + base_cost
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				_gw_heap_push(open, {"cell": neighbor, "f": tentative_g + _heuristic(neighbor, end), "seq": seq})
				seq += 1

	# No path found
	if _pf_debug:
		_pf_trace("[A*] find_path done: NO PATH after %d iters (max %d)" % [iterations, max_iterations])
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
	if not is_in_bounds(end_cell.x, end_cell.y) or not is_walkable(end_cell.x, end_cell.y, explored, locked_doors, end_level):
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
			if not is_in_bounds(nb.x, nb.y) or not is_walkable(nb.x, nb.y, explored, locked_doors, cur_level):
				continue
			var is_diag := dir.x != 0 and dir.y != 0
			if is_diag:
				if not is_walkable(cur_cell.x + dir.x, cur_cell.y, explored, locked_doors, cur_level):
					continue
				if not is_walkable(cur_cell.x, cur_cell.y + dir.y, explored, locked_doors, cur_level):
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

# --- Sokoban push planning -------------------------------------------------
# A character pushes an object one CARDINAL cell at a time, standing on the cell behind it; between
# pushes it may walk around the object (which blocks its own cell while being repositioned around).
# Classic consequence: a 1-wide hallway bend is unpushable — there's no room to get behind the new
# direction. Pure grid logic, deterministic (ordered direction sets, BFS) — safe for replay.

const _PUSH_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Plan pushing the object from obj_cell to target_cell with the character starting at char_cell.
## Returns {"steps": [{"dir", "obj_from", "obj_to", "char_push_cell"}...]} — steps in order, where
## char_push_cell is where the character stands to make that push — or {} when impossible.
func plan_push(obj_cell: Vector2i, char_cell: Vector2i, target_cell: Vector2i, level := 0) -> Dictionary:
	if not is_walkable(target_cell.x, target_cell.y, {}, {}, level):
		return {}
	if obj_cell == target_cell:
		return {"steps": []}
	# BFS over (object cell, push direction used to get here). The character constraint folds in via
	# reachability: to push along d the character must REACH obj-d from where the previous push left
	# it (obj_from of that push), with the object's cell blocked.
	var start_key := "%d,%d|s" % [obj_cell.x, obj_cell.y]
	var queue: Array = [{"obj": obj_cell, "char": char_cell, "key": start_key}]
	var came := {start_key: {}}
	var iterations := 0
	while not queue.is_empty() and iterations < width * height * 8:
		iterations += 1
		var cur: Dictionary = queue.pop_front()
		var obj: Vector2i = cur["obj"]
		var chr: Vector2i = cur["char"]
		for d in _PUSH_DIRS:
			var obj_to: Vector2i = obj + d
			var push_cell: Vector2i = obj - d
			if not is_walkable(obj_to.x, obj_to.y, {}, {}, level):
				continue
			if not is_walkable(push_cell.x, push_cell.y, {}, {}, level):
				continue
			if not _char_can_reach(chr, push_cell, obj, level):
				continue
			var nkey := "%d,%d|%d,%d" % [obj_to.x, obj_to.y, d.x, d.y]
			if came.has(nkey):
				continue
			came[nkey] = {"prev": cur["key"], "dir": d, "obj_from": obj, "obj_to": obj_to, "char_push_cell": push_cell}
			if obj_to == target_cell:
				return {"steps": _reconstruct_push(came, nkey)}
			# After the push the character stands where the object WAS.
			queue.append({"obj": obj_to, "char": obj, "key": nkey})
	return {}

## Can the character walk from `from` to `to` with the object's cell treated as a wall?
func _char_can_reach(from: Vector2i, to: Vector2i, obj_cell: Vector2i, level: int) -> bool:
	if from == to:
		return true
	if to == obj_cell:
		return false
	var frontier: Array[Vector2i] = [from]
	var seen := {from: true}
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in _PUSH_DIRS:
			var n: Vector2i = c + d
			if n == to:
				return true
			if seen.has(n) or n == obj_cell:
				continue
			if not is_walkable(n.x, n.y, {}, {}, level):
				continue
			seen[n] = true
			frontier.append(n)
	return false

func _reconstruct_push(came: Dictionary, key: String) -> Array:
	var steps: Array = []
	var k := key
	while came.has(k) and not (came[k] as Dictionary).is_empty():
		var entry: Dictionary = came[k]
		steps.push_front({
			"dir": entry["dir"], "obj_from": entry["obj_from"],
			"obj_to": entry["obj_to"], "char_push_cell": entry["char_push_cell"],
		})
		k = str(entry["prev"])
	return steps

## Find all tiles of a given type. Returns array of Vector2i grid positions.
func find_tiles(tile_type: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in range(height):
		for x in range(width):
			if grid[z][x] == tile_type:
				result.append(Vector2i(x, z))
	return result
