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
var _path_walkability_revision := 0
var _path_walkability_cache: Dictionary = {}
var _path_risk_revision := 0
var _path_risk_cache: Dictionary = {}
var _goal_risk_potential_cache: Dictionary = {}
var _last_path_iterations := 0
var dynamic_blockers: Dictionary = {}  # Vector2i → obj_id

# --- Per-cell risk (the safe/direct routing vocabulary). A risky cell stays WALKABLE — risk only
# shapes route choice. In CAUTIOUS (safe) routing a recoverable risky cell costs extra (the planner
# detours around it when a detour exists) and a NON-recoverable one is never entered (no safe route
# may exist at all — the player must go direct). Direct routing ignores risk entirely; any harm from
# crossing is gameplay applied by the scene/chunk, not the pathfinder. ---
var risk_cells: Dictionary = {}  # Vector2i -> {"penalty": float, "recoverable": bool}

# Player-facing graph annotation for a vertex whose consequence is authored by a
# mechanism rather than by path shape alone. It is keyed by (level, cell), so an
# unsafe bowl floor never labels the safe deck stacked above it. This is presentation
# data only: it does not alter walkability, cost, or command acceptance.
var navigation_consequences: Dictionary = {}  # "level:x:z" -> String

# --- Multi-level support (stacked floors). The grid stays a single 2D plane of cells; a LEVEL is
# the same (x,z) plane lifted by level_height in world Y. A character's level is tracked in
# GameState; grid_to_world(cell, level) places the cell at that floor's height. Ladders/ramps are
# inter-level LINKS at a cell, registered here. Backward-compatible: level defaults to 0 → Y=0. ---
var level_count := 1
var level_height := 4.0               # world Y between stacked floors
## Directional traversal-edge records. Legacy co-located links retain their historical
## "x,z,from,to" key so direct readers remain compatible; edges whose two endpoints have
## different XZ cells use the extended key produced by _edge_key().
var inter_level_links: Dictionary = {}
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


func set_navigation_consequence(cell: Vector2i, level: int, text: String) -> void:
	var key := _navigation_consequence_key(cell, level)
	var normalized := text.strip_edges()
	if normalized.is_empty():
		navigation_consequences.erase(key)
	else:
		navigation_consequences[key] = normalized


func navigation_consequence(cell: Vector2i, level: int) -> String:
	return str(navigation_consequences.get(
		_navigation_consequence_key(cell, level), ""))


func _navigation_consequence_key(cell: Vector2i, level: int) -> String:
	return "%d:%d:%d" % [level, cell.x, cell.y]

func _link_key(cell: Vector2i, from_level: int, to_level: int) -> String:
	return "%d,%d,%d,%d" % [cell.x, cell.y, from_level, to_level]

func _edge_key(
		from_cell: Vector2i,
		from_level: int,
		to_cell: Vector2i,
		to_level: int
	) -> String:
	# Keep the key used by existing same-cell ladder owners and direct readers.
	if from_cell == to_cell:
		return _link_key(from_cell, from_level, to_level)
	return "%d,%d,%d>%d,%d,%d" % [
		from_cell.x, from_cell.y, from_level,
		to_cell.x, to_cell.y, to_level,
	]

func _default_link_cost(link_type: String) -> float:
	return 2.0 if link_type == "ladder" else 1.3

func _nav_node(cell: Vector2i, level: int) -> Dictionary:
	return {"cell": cell, "level": level}

func _store_inter_level_edge(
		from_cell: Vector2i,
		from_level: int,
		to_cell: Vector2i,
		to_level: int,
		link_type: String,
		cost: float,
		metadata: Dictionary
	) -> void:
	var entry := metadata.duplicate(true)
	entry.merge({
		"kind": "inter_level",
		"type": link_type,
		"cost": cost,
		"from_cell": from_cell,
		"from_level": from_level,
		"to_cell": to_cell,
		"to_level": to_level,
	}, true)
	inter_level_links[_edge_key(from_cell, from_level, to_cell, to_level)] = entry

## Register a general annotated traversal edge between two navigation vertices. Unlike the
## legacy add_inter_level_link(), the endpoints need not share an XZ cell, so stairs, ramps,
## offset ladders, and other authored connectors can retain their actual graph topology.
func add_inter_level_edge(
		from_cell: Vector2i,
		from_level: int,
		to_cell: Vector2i,
		to_level: int,
		link_type := "ladder",
		link_cost := -1.0,
		bidirectional := true,
		metadata: Dictionary = {}
	) -> void:
	var resolved_type := str(link_type)
	var resolved_cost := float(link_cost) if float(link_cost) >= 0.0 \
		else _default_link_cost(resolved_type)
	_store_inter_level_edge(
		from_cell, from_level, to_cell, to_level,
		resolved_type, resolved_cost, metadata)
	if bidirectional:
		_store_inter_level_edge(
			to_cell, to_level, from_cell, from_level,
			resolved_type, resolved_cost, metadata)
	_invalidate_path_walkability()

## Register a ladder/ramp at a cell that lets a character move between two adjacent levels. Bidirectional
## by default — adds both directions. link_type: "ladder" (climb, costlier) or "ramp" (walk).
func add_inter_level_link(cell: Vector2i, from_level: int, to_level: int, link_type := "ladder", bidirectional := true) -> void:
	add_inter_level_edge(
		cell, from_level, cell, to_level,
		str(link_type), -1.0, bidirectional)

func can_traverse_link(cell: Vector2i, from_level: int, to_level: int) -> bool:
	return inter_level_links.has(_link_key(cell, from_level, to_level))

## Remove a link (both directions) — for reversible set pieces (the sump's ledge falls when it
## drains). Absent keys are a no-op.
func remove_inter_level_link(cell: Vector2i, from_level: int, to_level: int) -> void:
	remove_inter_level_edge(cell, from_level, cell, to_level)

## Remove both directions of a general traversal edge. Absent records are a no-op.
func remove_inter_level_edge(
		from_cell: Vector2i,
		from_level: int,
		to_cell: Vector2i,
		to_level: int
	) -> void:
	var changed := inter_level_links.erase(
		_edge_key(from_cell, from_level, to_cell, to_level))
	changed = inter_level_links.erase(
		_edge_key(to_cell, to_level, from_cell, from_level)) or changed
	if changed:
		_invalidate_path_walkability()

func get_link_cost(cell: Vector2i, from_level: int, to_level: int) -> float:
	return float(inter_level_links.get(_link_key(cell, from_level, to_level), {}).get("cost", 1.0))

## The levels a character at this cell+level can step to (via a ladder/ramp here).
func links_from(cell: Vector2i, from_level: int) -> Array:
	var out: Array = []
	for edge_v in link_edges_from(cell, from_level):
		var to_level := int((edge_v as Dictionary).get("to_level", from_level))
		if to_level != from_level and not out.has(to_level):
			out.append(to_level)
	out.sort()
	return out

## Full directional edge records leaving a navigation vertex. This is the endpoint-preserving
## counterpart to legacy links_from(), which can report only destination levels.
func link_edges_from(cell: Vector2i, from_level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_v in inter_level_links.values():
		if not (entry_v is Dictionary):
			continue
		var entry := entry_v as Dictionary
		if not entry.has("from_cell") or entry.get("from_cell") != cell \
				or int(entry.get("from_level", -1)) != from_level:
			continue
		out.append(entry)
	return out

## Revalidate a retained plan edge against the current navigation graph. Connector edges
## must still exist with the exact endpoints/type/action, and all edge kinds require currently
## walkable endpoints. This lets an executor reject a route made stale by a topology mutation.
func is_navigation_edge_available(
	edge: Dictionary,
	explored: Dictionary = {},
	locked_doors: Dictionary = {}
) -> bool:
	if not edge.has("from_cell") or not edge.has("to_cell") \
			or not (edge.get("from_cell") is Vector2i) \
			or not (edge.get("to_cell") is Vector2i):
		return false
	var from_cell: Vector2i = edge["from_cell"]
	var to_cell: Vector2i = edge["to_cell"]
	var from_level := int(edge.get("from_level", -1))
	var to_level := int(edge.get("to_level", -1))
	if not _ml_vertex_walkable(from_cell, from_level, explored, locked_doors) \
			or not _ml_vertex_walkable(to_cell, to_level, explored, locked_doors):
		return false

	var category := str(edge.get("category", "")).to_lower()
	# A retained connector must still name the exact stored edge. Explicit category keeps an
	# ordinary adjacent walk independent when the same vertex pair also has an authored edge.
	var stored_v: Variant = inter_level_links.get(
		_edge_key(from_cell, from_level, to_cell, to_level), null)
	if category != "grid" and stored_v is Dictionary:
		var stored := stored_v as Dictionary
		if stored.get("from_cell") != from_cell \
				or int(stored.get("from_level", -1)) != from_level \
				or stored.get("to_cell") != to_cell \
				or int(stored.get("to_level", -1)) != to_level:
			return false
		return str(edge.get("type", edge.get("kind", ""))).to_lower() \
				== str(stored.get("type", "")).to_lower() \
			and str(edge.get("action_id", "")) == str(stored.get("action_id", ""))
	if category == "connector":
		return false

	# No authored connector record: only a legal one-cell planar edge remains available.
	if str(edge.get("kind", "")).to_lower() != "walk" or from_level != to_level:
		return false
	var delta := to_cell - from_cell
	var abs_x := absi(delta.x)
	var abs_z := absi(delta.y)
	if (abs_x == 0 and abs_z == 0) or abs_x > 1 or abs_z > 1:
		return false
	var is_diagonal := abs_x == 1 and abs_z == 1
	var edge_type := str(edge.get("type", "diagonal" if is_diagonal else "cardinal")).to_lower()
	if edge_type != ("diagonal" if is_diagonal else "cardinal"):
		return false
	if is_diagonal:
		return _ml_vertex_walkable(
			Vector2i(from_cell.x + delta.x, from_cell.y), from_level,
			explored, locked_doors) \
			and _ml_vertex_walkable(
				Vector2i(from_cell.x, from_cell.y + delta.y), from_level,
				explored, locked_doors)
	return true

# --- Per-level walkable footprints (stacked floors with different shapes) ---

## Mark a single cell walkable on a level (this RESTRICTS the level to its allow-set).
func allow_cell_on_level(cell: Vector2i, level: int) -> void:
	if not level_allowed.has(level):
		level_allowed[level] = {}
	if level_allowed[level].has(cell):
		return
	level_allowed[level][cell] = true
	_invalidate_path_walkability()

## Mark an inclusive rectangle of cells walkable on a level.
func allow_cell_region_on_level(min_cell: Vector2i, max_cell: Vector2i, level: int) -> void:
	if not level_allowed.has(level):
		level_allowed[level] = {}
	var allowed: Dictionary = level_allowed[level]
	var changed := false
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			var cell := Vector2i(x, z)
			if not allowed.has(cell):
				allowed[cell] = true
				changed = true
	if changed:
		_invalidate_path_walkability()

## Remove one cell from a restricted level's footprint. Keeping footprint
## mutation behind GridWorld guarantees derived path masks invalidate with it.
func disallow_cell_on_level(cell: Vector2i, level: int) -> void:
	if level_allowed.has(level) and (level_allowed[level] as Dictionary).erase(cell):
		_invalidate_path_walkability()

## Remove an inclusive cell rectangle from one restricted level's footprint.
func disallow_cell_region_on_level(min_cell: Vector2i, max_cell: Vector2i, level: int) -> void:
	if not level_allowed.has(level):
		return
	var allowed: Dictionary = level_allowed[level]
	var changed := false
	for z in range(mini(min_cell.y, max_cell.y), maxi(min_cell.y, max_cell.y) + 1):
		for x in range(mini(min_cell.x, max_cell.x), maxi(min_cell.x, max_cell.x) + 1):
			changed = allowed.erase(Vector2i(x, z)) or changed
	if changed:
		_invalidate_path_walkability()

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
		var legacy_cell := _arr_to_vec2i(l.get("cell", [0, 0]))
		var from_cell := _arr_to_vec2i(l.get("from_cell", legacy_cell))
		var to_cell := _arr_to_vec2i(l.get("to_cell", legacy_cell))
		var from_level := int(l.get("from_level", l.get("from", 0)))
		var to_level := int(l.get("to_level", l.get("to", 1)))
		# Preserve connector-specific execution annotations without making GridWorld
		# interpret them. The returned plan promotes duration/action_id for consumers.
		var metadata := l.duplicate(true)
		for schema_key in [
			"cell", "from_cell", "to_cell", "from", "to", "from_level", "to_level",
			"type", "cost", "bidirectional", "metadata",
		]:
			metadata.erase(schema_key)
		var nested_metadata: Variant = l.get("metadata", {})
		if nested_metadata is Dictionary:
			metadata.merge((nested_metadata as Dictionary).duplicate(true), true)
		g.add_inter_level_edge(
			from_cell, from_level, to_cell, to_level,
			str(l.get("type", "ladder")), float(l.get("cost", -1.0)),
			bool(l.get("bidirectional", true)), metadata)
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
	_invalidate_path_walkability()
	_invalidate_path_risk()
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
	_invalidate_path_walkability()
	_invalidate_path_risk()
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
		_invalidate_path_walkability()
		_invalidate_path_risk()

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

## In-bounds planner hot-path equivalent of is_walkable(). Avoids a second
## get_tile() call and only constructs a Vector2i when one of the keyed blocker
## sets can actually affect this query. `explored` is intentionally absent: the
## public predicate does not use it either.
func _path_cell_walkable(x: int, z: int, locked_doors: Dictionary, level: int) -> bool:
	var tile: int = grid[z][x]
	if tile == Tile.WALL:
		return false
	var needs_key := tile == Tile.LOCKED_DOOR and not locked_doors.is_empty()
	needs_key = needs_key or not dynamic_blockers.is_empty() or level_allowed.has(level)
	if not needs_key:
		return true
	var cell := Vector2i(x, z)
	if tile == Tile.LOCKED_DOOR and bool(locked_doors.get(cell, false)):
		return false
	if dynamic_blockers.has(cell):
		return false
	if level_allowed.has(level) and not level_allowed[level].has(cell):
		return false
	return true

func _invalidate_path_walkability() -> void:
	_path_walkability_revision += 1
	_path_walkability_cache.clear()

## Monotonic derived-topology token for systems that cache their own spatial
## query (for example, a crowd flow field). Callers must still rebuild their
## cache when their own origins/goals change; this token covers tiles, dynamic
## blockers, and per-level footprint mutations made through GridWorld's API.
func get_path_walkability_revision() -> int:
	return _path_walkability_revision

func _invalidate_path_risk() -> void:
	_path_risk_revision += 1
	_path_risk_cache.clear()
	_goal_risk_potential_cache.clear()

## Read-only dense walkability view for planners that already bounds-check cells.
## Locked-door dictionaries remain query-specific and must be layered by callers.
func get_path_walkability_mask(level: int) -> PackedByteArray:
	var allowed_count := -1
	if level_allowed.has(level):
		allowed_count = (level_allowed[level] as Dictionary).size()
	var cached: Dictionary = _path_walkability_cache.get(level, {})
	if int(cached.get("revision", -1)) == _path_walkability_revision \
			and int(cached.get("dynamic_count", -1)) == dynamic_blockers.size() \
			and int(cached.get("allowed_count", -2)) == allowed_count:
		return cached.get("mask", PackedByteArray()) as PackedByteArray
	var mask := PackedByteArray()
	mask.resize(width * height)
	mask.fill(0)
	var restricted := level_allowed.has(level)
	var allowed: Dictionary = level_allowed.get(level, {})
	var has_dynamic := not dynamic_blockers.is_empty()
	for z in range(height):
		for x in range(width):
			var tile: int = grid[z][x]
			if tile == Tile.WALL:
				continue
			if not has_dynamic and not restricted:
				mask[z * width + x] = 1
				continue
			var cell := Vector2i(x, z)
			if has_dynamic and dynamic_blockers.has(cell):
				continue
			if restricted and not allowed.has(cell):
				continue
			mask[z * width + x] = 1
	_path_walkability_cache[level] = {
		"revision": _path_walkability_revision,
		"dynamic_count": dynamic_blockers.size(),
		"allowed_count": allowed_count,
		"mask": mask,
	}
	return mask

## Read-only dense cautious-routing penalties and hard-risk blocks.
func get_path_risk_masks() -> Dictionary:
	if int(_path_risk_cache.get("revision", -1)) == _path_risk_revision \
			and int(_path_risk_cache.get("risk_count", -1)) == risk_cells.size():
		return _path_risk_cache
	var penalties := PackedFloat64Array()
	penalties.resize(width * height)
	penalties.fill(0.0)
	var blocked := PackedByteArray()
	blocked.resize(width * height)
	blocked.fill(0)
	for z in range(height):
		for x in range(width):
			if int(grid[z][x]) == Tile.IRON_BLOOM:
				penalties[z * width + x] = 20.0
	for cell_variant in risk_cells.keys():
		var cell: Vector2i = cell_variant
		if not is_in_bounds(cell.x, cell.y):
			continue
		var info: Dictionary = risk_cells[cell]
		var index := cell.y * width + cell.x
		penalties[index] += float(info.get("penalty", 0.0))
		if not bool(info.get("recoverable", true)):
			blocked[index] = 1
	_path_risk_cache = {
		"revision": _path_risk_revision,
		"risk_count": risk_cells.size(),
		"penalties": penalties,
		"blocked": blocked,
	}
	return _path_risk_cache

## Cached admissible lower bound for the cautious risk still required to reach
## `end`. Octile distance alone cannot see that a destination sits several cells
## inside a costly region; a short click could therefore expand the entire safe
## floor before accepting unavoidable goal risk.
##
## This relaxed graph keeps only the goal's connected positive-risk component
## and collapses all zero-risk space into one OUTSIDE node. Reverse Dijkstra
## gives the exact remaining risk in that relaxation. Walls and movement
## distance are omitted, so adding this potential to the geometric heuristic
## never overestimates a real route. Results are cached per goal/risk revision
## and shared by spatial and cooperative planning.
func get_cautious_goal_risk_potential(end: Vector2i) -> PackedFloat64Array:
	var perf_started := PerformanceTrace.begin()
	if not is_in_bounds(end.x, end.y):
		PerformanceTrace.end(&"nav", &"grid.risk_potential", perf_started, "out_of_bounds", 0)
		return PackedFloat64Array()
	var end_index := end.y * width + end.x
	if _goal_risk_potential_cache.has(end_index):
		var cached: PackedFloat64Array = _goal_risk_potential_cache[end_index]
		PerformanceTrace.end(&"nav", &"grid.risk_potential", perf_started, "cached", cached.size())
		return cached
	var masks := get_path_risk_masks()
	var penalties: PackedFloat64Array = masks.get("penalties", PackedFloat64Array())
	var blocked: PackedByteArray = masks.get("blocked", PackedByteArray())
	if penalties.is_empty() or penalties[end_index] <= 0.0 or blocked[end_index] != 0:
		var empty := PackedFloat64Array()
		_goal_risk_potential_cache[end_index] = empty
		PerformanceTrace.end(&"nav", &"grid.risk_potential", perf_started, "zero", 0)
		return empty

	var cell_count := width * height
	var in_component := PackedByteArray()
	in_component.resize(cell_count)
	in_component.fill(0)
	var component_cells := PackedInt32Array([end_index])
	in_component[end_index] = 1
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var scan_i := 0
	while scan_i < component_cells.size():
		var scanned_index := component_cells[scan_i]
		scan_i += 1
		var scanned_x := scanned_index % width
		var scanned_z := int(scanned_index / width)
		for dir in dirs:
			var nx := scanned_x + dir.x
			var nz := scanned_z + dir.y
			if not is_in_bounds(nx, nz):
				continue
			var neighbor_index := nz * width + nx
			if in_component[neighbor_index] != 0 or blocked[neighbor_index] != 0 \
					or penalties[neighbor_index] <= 0.0:
				continue
			in_component[neighbor_index] = 1
			component_cells.append(neighbor_index)

	var boundary_cells := PackedInt32Array()
	var boundary_mask := PackedByteArray()
	boundary_mask.resize(cell_count)
	boundary_mask.fill(0)
	for component_index in component_cells:
		var component_x := component_index % width
		var component_z := int(component_index / width)
		for dir in dirs:
			var nx := component_x + dir.x
			var nz := component_z + dir.y
			if not is_in_bounds(nx, nz):
				continue
			var neighbor_index := nz * width + nx
			if in_component[neighbor_index] == 0 and blocked[neighbor_index] == 0 \
					and penalties[neighbor_index] <= 0.0:
				boundary_cells.append(component_index)
				boundary_mask[component_index] = 1
				break

	var outside_index := cell_count
	var distance := PackedFloat64Array()
	distance.resize(cell_count + 1)
	distance.fill(INF)
	distance[end_index] = 0.0
	var settled := PackedByteArray()
	settled.resize(cell_count + 1)
	settled.fill(0)
	var heap_nodes := PackedInt32Array()
	var heap_costs := PackedFloat64Array()
	var heap_sequence := PackedInt32Array()
	var sequence := 0
	_gw_dense_heap_push(heap_nodes, heap_costs, heap_sequence, end_index, 0.0, sequence)
	sequence += 1
	while not heap_nodes.is_empty():
		var dijkstra_node := _gw_dense_heap_pop(heap_nodes, heap_costs, heap_sequence)
		if settled[dijkstra_node] != 0:
			continue
		settled[dijkstra_node] = 1
		var current_distance := distance[dijkstra_node]
		if dijkstra_node == outside_index:
			# Forward boundary -> OUTSIDE costs zero: leaving danger adds no risk.
			for boundary_index in boundary_cells:
				if current_distance < distance[boundary_index]:
					distance[boundary_index] = current_distance
					_gw_dense_heap_push(heap_nodes, heap_costs, heap_sequence,
						boundary_index, current_distance, sequence)
					sequence += 1
			continue
		var current_x := dijkstra_node % width
		var current_z := int(dijkstra_node / width)
		# Reverse an in-component edge. Forward predecessor -> current pays
		# the current cell's penalty on entry.
		var predecessor_cost := current_distance + penalties[dijkstra_node]
		for dir in dirs:
			var px := current_x + dir.x
			var pz := current_z + dir.y
			if not is_in_bounds(px, pz):
				continue
			var predecessor_index := pz * width + px
			if in_component[predecessor_index] == 0 \
					or predecessor_cost >= distance[predecessor_index]:
				continue
			distance[predecessor_index] = predecessor_cost
			_gw_dense_heap_push(heap_nodes, heap_costs, heap_sequence,
				predecessor_index, predecessor_cost, sequence)
			sequence += 1
		if boundary_mask[dijkstra_node] != 0 and predecessor_cost < distance[outside_index]:
			distance[outside_index] = predecessor_cost
			_gw_dense_heap_push(heap_nodes, heap_costs, heap_sequence,
				outside_index, predecessor_cost, sequence)
			sequence += 1

	var outside_cost := distance[outside_index]
	if not is_finite(outside_cost):
		# No zero-risk entry exists in the relaxed in-bounds graph. Zero is the
		# conservative fallback; the ordinary planner still proves reachability.
		outside_cost = 0.0
	var potential := PackedFloat64Array()
	potential.resize(cell_count)
	potential.fill(outside_cost)
	for component_index in component_cells:
		potential[component_index] = distance[component_index] \
			if is_finite(distance[component_index]) else 0.0
	_goal_risk_potential_cache[end_index] = potential
	PerformanceTrace.end(&"nav", &"grid.risk_potential", perf_started, "built", component_cells.size())
	return potential

## Deterministic diagnostic used by performance regressions and the trace's
## `units` field. It never affects path ordering or serialized state.
func get_last_path_iterations() -> int:
	return _last_path_iterations

func add_dynamic_blocker(cell: Vector2i, obj_id: String) -> void:
	if dynamic_blockers.has(cell) and str(dynamic_blockers[cell]) == obj_id:
		return
	dynamic_blockers[cell] = obj_id
	_invalidate_path_walkability()

func remove_dynamic_blocker(cell: Vector2i) -> void:
	if dynamic_blockers.erase(cell):
		_invalidate_path_walkability()

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
	_invalidate_path_risk()

func clear_cell_risk(cell: Vector2i) -> void:
	if risk_cells.erase(cell):
		_invalidate_path_risk()

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

## One authoritative cautious-routing cost shared by the spatial and
## cooperative planners. Keeping the terrain tile and authored risk penalty in
## one function prevents previews and committed conflict detours from drifting.
func cautious_cost_penalty(cell: Vector2i) -> float:
	var penalty := risk_penalty(cell)
	if get_tile(cell.x, cell.y) == Tile.IRON_BLOOM:
		penalty += 20.0
	return penalty

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
	var perf_started := PerformanceTrace.begin()
	if _pf_debug:
		_pf_trace("[A*] reachable BFS %v -> %v" % [start, end])
	if start == end:
		PerformanceTrace.end(&"nav", &"grid.reachable", perf_started, "same_cell", 1)
		return true
	if not _reach_walkable(start.x, start.y, level, cautious) or not _reach_walkable(end.x, end.y, level, cautious):
		PerformanceTrace.end(&"nav", &"grid.reachable", perf_started, "blocked", 0)
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
				PerformanceTrace.end(&"nav", &"grid.reachable", perf_started, "reached", seen.size())
				return true
			seen[n] = true
			queue.append(n)
	PerformanceTrace.end(&"nav", &"grid.reachable", perf_started, "unreachable", seen.size())
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

# Dense A* heap. Each open entry used to be a Dictionary containing a
# Vector2i, f-score and sequence number. On Web, allocating and probing those
# Dictionaries costs more than the path math itself (a 227-cell straight route
# measured about 9 ms). Parallel packed arrays keep the exact same f/sequence
# ordering without allocating an object per discovered cell.
static func _gw_dense_heap_less(
		heap_f: PackedFloat64Array,
		heap_seq: PackedInt32Array,
		a: int,
		b: int
	) -> bool:
	if heap_f[a] != heap_f[b]:
		return heap_f[a] < heap_f[b]
	return heap_seq[a] < heap_seq[b]

static func _gw_dense_heap_push(
		heap_cells: PackedInt32Array,
		heap_f: PackedFloat64Array,
		heap_seq: PackedInt32Array,
		cell_index: int,
		f_score: float,
		sequence: int
	) -> void:
	heap_cells.append(cell_index)
	heap_f.append(f_score)
	heap_seq.append(sequence)
	var i := heap_cells.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _gw_dense_heap_less(heap_f, heap_seq, i, parent):
			break
		var tmp_cell := heap_cells[parent]
		heap_cells[parent] = heap_cells[i]
		heap_cells[i] = tmp_cell
		var tmp_f := heap_f[parent]
		heap_f[parent] = heap_f[i]
		heap_f[i] = tmp_f
		var tmp_seq := heap_seq[parent]
		heap_seq[parent] = heap_seq[i]
		heap_seq[i] = tmp_seq
		i = parent

static func _gw_dense_heap_pop(
		heap_cells: PackedInt32Array,
		heap_f: PackedFloat64Array,
		heap_seq: PackedInt32Array
	) -> int:
	var top := heap_cells[0]
	var last_index := heap_cells.size() - 1
	if last_index == 0:
		heap_cells.resize(0)
		heap_f.resize(0)
		heap_seq.resize(0)
		return top
	heap_cells[0] = heap_cells[last_index]
	heap_f[0] = heap_f[last_index]
	heap_seq[0] = heap_seq[last_index]
	heap_cells.resize(last_index)
	heap_f.resize(last_index)
	heap_seq.resize(last_index)
	var i := 0
	var n := heap_cells.size()
	while true:
		var smallest := i
		var left := 2 * i + 1
		var right := left + 1
		if left < n and _gw_dense_heap_less(heap_f, heap_seq, left, smallest):
			smallest = left
		if right < n and _gw_dense_heap_less(heap_f, heap_seq, right, smallest):
			smallest = right
		if smallest == i:
			break
		var tmp_cell := heap_cells[smallest]
		heap_cells[smallest] = heap_cells[i]
		heap_cells[i] = tmp_cell
		var tmp_f := heap_f[smallest]
		heap_f[smallest] = heap_f[i]
		heap_f[i] = tmp_f
		var tmp_seq := heap_seq[smallest]
		heap_seq[smallest] = heap_seq[i]
		heap_seq[i] = tmp_seq
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
	level: int = 0,
	allowed_cells: Dictionary = {}
) -> Array[Vector3]:
	var perf_started := PerformanceTrace.begin()
	_last_path_iterations = 0
	# An optional allow-list is used by mechanism-owned movement that must stay on a
	# particular permanent topology. It is intentionally stricter than ordinary
	# walkability: the occupied start, destination, every entered cell, and both
	# orthogonal support cells of a diagonal edge must all belong to the mask.
	if not allowed_cells.is_empty():
		# A constrained path may never use the legacy sparse-start bridge: cells
		# outside this grid cannot belong to the topology the mask describes.
		if not is_in_bounds(start.x, start.y) or not is_in_bounds(end.x, end.y):
			PerformanceTrace.end(&"nav", &"grid.find_path", perf_started,
				"outside_allowed_grid", 0)
			return []
		if not allowed_cells.has(start) or not allowed_cells.has(end):
			PerformanceTrace.end(&"nav", &"grid.find_path", perf_started,
				"outside_allowed_cells", 0)
			return []
	if start == end:
		PerformanceTrace.end(&"nav", &"grid.find_path", perf_started, "same_cell", 1)
		return [grid_to_world(end, level)]
	if not is_in_bounds(end.x, end.y):
		PerformanceTrace.end(&"nav", &"grid.find_path", perf_started, "out_of_bounds", 0)
		return []
	if not is_walkable(end.x, end.y, explored, locked_doors, level):
		PerformanceTrace.end(&"nav", &"grid.find_path", perf_started, "blocked", 0)
		return []
	if cautious and cautious_cell_blocked(end):
		PerformanceTrace.end(&"nav", &"grid.find_path", perf_started, "risk_blocked", 0)
		return []
	# Normal movement snaps starts onto the footprint first, but preserve the
	# historical ability to step in from a start immediately outside the grid.
	if not is_in_bounds(start.x, start.y):
		var sparse := _find_path_sparse_start(
			start, end, explored, cautious, roads, locked_doors, level)
		PerformanceTrace.end(&"nav", &"grid.find_path", perf_started,
			"sparse_start" if not sparse.is_empty() else "no_path", sparse.size())
		return sparse
	# (No reachability pre-check here: the heap A* below already explores an unreachable target's whole
	# component in O(n log n) — adding a BFS pre-check would just DOUBLE the cost for the common reachable
	# case. The cull lives in _plan_cooperative, where it saves the far more expensive space-time search.)

	# A* with octile heuristic, binary-heap open set
	if _pf_debug:
		_pf_trace("[A*] find_path start %v -> %v (grid %dx%d, cautious=%s)" % [start, end, width, height, cautious])
	var cell_count := width * height
	var came_from := PackedInt32Array()
	came_from.resize(cell_count)
	came_from.fill(-1)
	var g_score := PackedFloat64Array()
	g_score.resize(cell_count)
	g_score.fill(INF)
	var closed := PackedByteArray()
	closed.resize(cell_count)
	closed.fill(0)
	var start_index := start.y * width + start.x
	var end_index := end.y * width + end.x
	g_score[start_index] = 0.0
	var walkability_mask := get_path_walkability_mask(level)
	var risk_penalties := PackedFloat64Array()
	var risk_blocked := PackedByteArray()
	var risk_potential := PackedFloat64Array()
	if cautious:
		var risk_masks := get_path_risk_masks()
		risk_penalties = risk_masks.get("penalties", PackedFloat64Array())
		risk_blocked = risk_masks.get("blocked", PackedByteArray())
		risk_potential = get_cautious_goal_risk_potential(end)
	var seq := 0
	var open_cells := PackedInt32Array()
	var open_f := PackedFloat64Array()
	var open_seq := PackedInt32Array()
	var start_risk_potential := risk_potential[start_index] if not risk_potential.is_empty() else 0.0
	_gw_dense_heap_push(open_cells, open_f, open_seq,
		start_index, _heuristic(start, end) + start_risk_potential, seq)
	seq += 1

	# 8 directions: cardinal + diagonal
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]

	var iterations := 0
	var max_iterations := width * height * 4

	while not open_cells.is_empty() and iterations < max_iterations:
		iterations += 1

		# Pop the packed heap inline. Passing three reference-counted packed arrays
		# through a helper for every expansion is measurably expensive in Web builds.
		var current_index := open_cells[0]
		var heap_last_index := open_cells.size() - 1
		if heap_last_index == 0:
			open_cells.resize(0)
			open_f.resize(0)
			open_seq.resize(0)
		else:
			open_cells[0] = open_cells[heap_last_index]
			open_f[0] = open_f[heap_last_index]
			open_seq[0] = open_seq[heap_last_index]
			open_cells.resize(heap_last_index)
			open_f.resize(heap_last_index)
			open_seq.resize(heap_last_index)
			var heap_i := 0
			var heap_size := open_cells.size()
			while true:
				var heap_smallest := heap_i
				var heap_left := 2 * heap_i + 1
				var heap_right := heap_left + 1
				if heap_left < heap_size and (open_f[heap_left] < open_f[heap_smallest] \
						or (open_f[heap_left] == open_f[heap_smallest] \
						and open_seq[heap_left] < open_seq[heap_smallest])):
					heap_smallest = heap_left
				if heap_right < heap_size and (open_f[heap_right] < open_f[heap_smallest] \
						or (open_f[heap_right] == open_f[heap_smallest] \
						and open_seq[heap_right] < open_seq[heap_smallest])):
					heap_smallest = heap_right
				if heap_smallest == heap_i:
					break
				var heap_tmp_cell := open_cells[heap_smallest]
				open_cells[heap_smallest] = open_cells[heap_i]
				open_cells[heap_i] = heap_tmp_cell
				var heap_tmp_f := open_f[heap_smallest]
				open_f[heap_smallest] = open_f[heap_i]
				open_f[heap_i] = heap_tmp_f
				var heap_tmp_seq := open_seq[heap_smallest]
				open_seq[heap_smallest] = open_seq[heap_i]
				open_seq[heap_i] = heap_tmp_seq
				heap_i = heap_smallest
		# A stale duplicate (already finalized cheaper) — skip. Consistent (octile) heuristic, so a cell
		# popped once is at its best g and never needs reopening.
		if closed[current_index] != 0:
			continue
		closed[current_index] = 1

		if current_index == end_index:
			if _pf_debug:
				_pf_trace("[A*] find_path done: reached in %d iters" % iterations)
			var result := _reconstruct_dense_path(came_from, current_index, start_index, level)
			_last_path_iterations = iterations
			PerformanceTrace.end(&"nav", &"grid.find_path", perf_started, "reached", iterations)
			return result

		var current_x := current_index % width
		var current_z := int(current_index / width)
		for dir in dirs:
			var neighbor_x := current_x + dir.x
			var neighbor_z := current_z + dir.y
			if not is_in_bounds(neighbor_x, neighbor_z):
				continue
			var neighbor_index := neighbor_z * width + neighbor_x
			if walkability_mask[neighbor_index] == 0:
				continue
			var neighbor_cell := Vector2i(neighbor_x, neighbor_z)
			if not allowed_cells.is_empty() and not allowed_cells.has(neighbor_cell):
				continue
			if not locked_doors.is_empty() and int(grid[neighbor_z][neighbor_x]) == Tile.LOCKED_DOOR \
					and bool(locked_doors.get(Vector2i(neighbor_x, neighbor_z), false)):
				continue

			# Diagonal corner-cutting prevention
			var is_diagonal := dir.x != 0 and dir.y != 0
			if is_diagonal:
				var adjacent_a := Vector2i(current_x + dir.x, current_z)
				var adjacent_b := Vector2i(current_x, current_z + dir.y)
				var adjacent_a_index := current_z * width + current_x + dir.x
				var adjacent_b_index := (current_z + dir.y) * width + current_x
				if walkability_mask[adjacent_a_index] == 0:
					continue
				if walkability_mask[adjacent_b_index] == 0:
					continue
				if not allowed_cells.is_empty() \
						and (not allowed_cells.has(adjacent_a) \
							or not allowed_cells.has(adjacent_b)):
					continue
				if not locked_doors.is_empty() and (
						(int(grid[current_z][current_x + dir.x]) == Tile.LOCKED_DOOR \
						and bool(locked_doors.get(Vector2i(current_x + dir.x, current_z), false))) \
						or (int(grid[current_z + dir.y][current_x]) == Tile.LOCKED_DOOR \
						and bool(locked_doors.get(Vector2i(current_x, current_z + dir.y), false)))):
					continue
			# Cautious (safe) routing never enters a non-recoverable risky cell.
			if cautious and risk_blocked[neighbor_index] != 0:
				continue

			# Movement cost
			var base_cost := 1.414 if is_diagonal else 1.0

			# Cautious mode: use the same cost vocabulary as cooperative A*.
			if cautious:
				base_cost += risk_penalties[neighbor_index]

			# Road bonus
			if not roads.is_empty() and roads.has(Vector2i(neighbor_x, neighbor_z)):
				base_cost -= 0.4

			var tentative_g: float = g_score[current_index] + base_cost
			if tentative_g < g_score[neighbor_index]:
				came_from[neighbor_index] = current_index
				g_score[neighbor_index] = tentative_g
				var heuristic_dx := absi(neighbor_x - end.x)
				var heuristic_dz := absi(neighbor_z - end.y)
				var heuristic := float(maxi(heuristic_dx, heuristic_dz)) \
					+ (1.414 - 1.0) * float(mini(heuristic_dx, heuristic_dz))
				open_cells.append(neighbor_index)
				var remaining_risk := risk_potential[neighbor_index] \
					if not risk_potential.is_empty() else 0.0
				open_f.append(tentative_g + heuristic + remaining_risk)
				open_seq.append(seq)
				var push_i := open_cells.size() - 1
				while push_i > 0:
					var push_parent := (push_i - 1) >> 1
					if open_f[push_i] > open_f[push_parent] or (open_f[push_i] == open_f[push_parent] \
							and open_seq[push_i] >= open_seq[push_parent]):
						break
					var push_tmp_cell := open_cells[push_parent]
					open_cells[push_parent] = open_cells[push_i]
					open_cells[push_i] = push_tmp_cell
					var push_tmp_f := open_f[push_parent]
					open_f[push_parent] = open_f[push_i]
					open_f[push_i] = push_tmp_f
					var push_tmp_seq := open_seq[push_parent]
					open_seq[push_parent] = open_seq[push_i]
					open_seq[push_i] = push_tmp_seq
					push_i = push_parent
				seq += 1

	# No path found
	if _pf_debug:
		_pf_trace("[A*] find_path done: NO PATH after %d iters (max %d)" % [iterations, max_iterations])
	_last_path_iterations = iterations
	PerformanceTrace.end(&"nav", &"grid.find_path", perf_started, "no_path", iterations)
	return []

## Rare compatibility path for a start just outside the grid. Dense storage
## cannot index that start, while the historical sparse A* could step in from
## it. Kept separate so normal in-bounds queries never pay these allocations.
func _find_path_sparse_start(
		start: Vector2i,
		end: Vector2i,
		explored: Dictionary,
		cautious: bool,
		roads: Dictionary,
		locked_doors: Dictionary,
		level: int
	) -> Array[Vector3]:
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var closed: Dictionary = {}
	var seq := 0
	var open: Array = [{"cell": start, "f": _heuristic(start, end), "seq": seq}]
	seq += 1
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var iterations := 0
	var max_iterations := width * height * 4
	while not open.is_empty() and iterations < max_iterations:
		iterations += 1
		var current: Vector2i = _gw_heap_pop(open).cell
		if closed.has(current):
			continue
		closed[current] = true
		if current == end:
			return _reconstruct_path(came_from, current, level)
		for dir in dirs:
			var neighbor := current + dir
			if not is_in_bounds(neighbor.x, neighbor.y):
				continue
			if not is_walkable(neighbor.x, neighbor.y, explored, locked_doors, level):
				continue
			var is_diagonal := dir.x != 0 and dir.y != 0
			if is_diagonal:
				if not is_walkable(current.x + dir.x, current.y, explored, locked_doors, level):
					continue
				if not is_walkable(current.x, current.y + dir.y, explored, locked_doors, level):
					continue
			if cautious and cautious_cell_blocked(neighbor):
				continue
			var base_cost := 1.414 if is_diagonal else 1.0
			if cautious:
				base_cost += cautious_cost_penalty(neighbor)
			if roads.has(neighbor):
				base_cost -= 0.4
			var tentative_g: float = float(g_score.get(current, INF)) + base_cost
			if tentative_g < float(g_score.get(neighbor, INF)):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				_gw_heap_push(open, {"cell": neighbor,
					"f": tentative_g + _heuristic(neighbor, end), "seq": seq})
				seq += 1
	return []

## Stable multi-level route contract. The richer planner below is authoritative; the legacy
## waypoint-only API remains as a projection for generation and validation callers.
const MULTI_LEVEL_PLAN_CONTRACT_ID := "multi_level_plan_v1"

## Compatibility projection for older callers that consume only ordered graph vertices.
func find_multi_level_path(
	start_cell: Vector2i, start_level: int, end_cell: Vector2i, end_level: int,
	explored: Dictionary = {}, locked_doors: Dictionary = {}
) -> Array:
	var plan := find_multi_level_plan(
		start_cell, start_level, end_cell, end_level, explored, locked_doors)
	return (plan.get("nodes", []) as Array).duplicate(true) if not plan.is_empty() else []

## Route through the graph of (cell, level) vertices while retaining every traversed edge.
## `nodes[i] -> nodes[i + 1]` is described by `edges[i]`; connector edges may have
## different XZ endpoints. Dijkstra ordering is intentional: arbitrary authored connectors
## can be cheaper than their geometric distance, so an octile heuristic is not admissible.
func find_multi_level_plan(
	start_cell: Vector2i, start_level: int, end_cell: Vector2i, end_level: int,
	explored: Dictionary = {}, locked_doors: Dictionary = {}
) -> Dictionary:
	var perf_started := PerformanceTrace.begin()
	if not _ml_vertex_walkable(start_cell, start_level, explored, locked_doors) \
			or not _ml_vertex_walkable(end_cell, end_level, explored, locked_doors):
		PerformanceTrace.end(&"nav", &"grid.find_multi_level_plan", perf_started, "blocked", 0)
		return {}
	if start_cell == end_cell and start_level == end_level:
		PerformanceTrace.end(&"nav", &"grid.find_multi_level_plan", perf_started, "same_vertex", 1)
		return {
			"contract_id": MULTI_LEVEL_PLAN_CONTRACT_ID,
			"nodes": [_nav_node(start_cell, start_level)],
			"edges": [],
			"total_cost": 0.0,
		}

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var start_key := _ml_key(start_cell, start_level)
	var open: Array[String] = [start_key]
	var closed: Dictionary = {}
	var came_from: Dictionary = {}
	var came_edge: Dictionary = {}
	var g: Dictionary = {start_key: 0.0}
	var iters := 0
	var max_iters := width * height * maxi(1, level_count) + 1
	while not open.is_empty() and iters < max_iters:
		iters += 1
		var cur_key: String = open[0]
		var best_g: float = float(g.get(cur_key, INF))
		for i in range(1, open.size()):
			var candidate_key: String = open[i]
			var candidate_g: float = float(g.get(candidate_key, INF))
			if candidate_g < best_g:
				best_g = candidate_g
				cur_key = candidate_key
		open.erase(cur_key)
		if closed.has(cur_key):
			continue
		closed[cur_key] = true
		var cur_cell := _ml_cell(cur_key)
		var cur_level := _ml_level(cur_key)
		if cur_cell == end_cell and cur_level == end_level:
			var result := _ml_reconstruct_plan(came_from, came_edge, cur_key, best_g)
			PerformanceTrace.end(&"nav", &"grid.find_multi_level_plan", perf_started, "reached", iters)
			return result

		# Ordinary same-level 8-direction movement.
		for dir in dirs:
			var neighbor := cur_cell + dir
			if not _ml_vertex_walkable(neighbor, cur_level, explored, locked_doors):
				continue
			var is_diagonal := dir.x != 0 and dir.y != 0
			if is_diagonal and (
				not _ml_vertex_walkable(
					Vector2i(cur_cell.x + dir.x, cur_cell.y), cur_level,
					explored, locked_doors)
				or not _ml_vertex_walkable(
					Vector2i(cur_cell.x, cur_cell.y + dir.y), cur_level,
					explored, locked_doors)
			):
				continue
			var walk_cost := 1.414 if is_diagonal else 1.0
			var walk_edge := _ml_plan_edge(
				cur_cell, cur_level, neighbor, cur_level,
				"walk", "diagonal" if is_diagonal else "cardinal",
				walk_cost, 0.0, "", {})
			_ml_relax(
				_ml_key(neighbor, cur_level), cur_key, best_g + walk_cost,
				walk_edge, came_from, came_edge, g, open, closed)

		# Authored connector edges retain their real endpoints and execution annotations.
		for link in link_edges_from(cur_cell, cur_level):
			var from_link_cell: Vector2i = link.get("from_cell", cur_cell)
			var from_link_level := int(link.get("from_level", cur_level))
			var to_link_cell: Vector2i = link.get("to_cell", cur_cell)
			var to_link_level := int(link.get("to_level", cur_level))
			if not _ml_vertex_walkable(
					from_link_cell, from_link_level, explored, locked_doors) \
					or not _ml_vertex_walkable(
						to_link_cell, to_link_level, explored, locked_doors):
				continue
			var link_edge := _ml_plan_edge_from_link(link)
			var link_cost := float(link_edge.get("cost", 0.0))
			_ml_relax(
				_ml_key(to_link_cell, to_link_level), cur_key, best_g + link_cost,
				link_edge, came_from, came_edge, g, open, closed)

	PerformanceTrace.end(&"nav", &"grid.find_multi_level_plan", perf_started, "no_path", iters)
	return {}

func _ml_key(cell: Vector2i, level: int) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, level]

func _ml_cell(key: String) -> Vector2i:
	var p := key.split(",")
	return Vector2i(int(p[0]), int(p[1]))

func _ml_level(key: String) -> int:
	return int(key.split(",")[2])

func _ml_vertex_walkable(
	cell: Vector2i,
	level: int,
	explored: Dictionary,
	locked_doors: Dictionary
) -> bool:
	return level >= 0 and level < level_count \
		and is_in_bounds(cell.x, cell.y) \
		and is_walkable(cell.x, cell.y, explored, locked_doors, level)

func _ml_plan_edge(
	from_cell: Vector2i,
	from_level: int,
	to_cell: Vector2i,
	to_level: int,
	kind: String,
	type: String,
	cost: float,
	duration: float,
	action_id: String,
	metadata: Dictionary
) -> Dictionary:
	return {
		"from_cell": from_cell,
		"from_level": from_level,
		"to_cell": to_cell,
		"to_level": to_level,
		"category": "grid" if kind == "walk" else "connector",
		"kind": kind,
		"type": type,
		"cost": maxf(0.0, cost),
		"duration": maxf(0.0, duration),
		"action_id": action_id,
		"metadata": metadata.duplicate(true),
	}

func _ml_plan_edge_from_link(link: Dictionary) -> Dictionary:
	var metadata := link.duplicate(true)
	for schema_key in [
		"from_cell", "from_level", "to_cell", "to_level", "kind", "type",
		"cost", "duration", "action_id", "metadata",
	]:
		metadata.erase(schema_key)
	var nested_metadata: Variant = link.get("metadata", {})
	if nested_metadata is Dictionary:
		metadata.merge((nested_metadata as Dictionary).duplicate(true), true)
	var link_type := str(link.get("type", "link")).to_lower()
	var edge := _ml_plan_edge(
		link.get("from_cell", Vector2i.ZERO), int(link.get("from_level", 0)),
		link.get("to_cell", Vector2i.ZERO), int(link.get("to_level", 0)),
		"link" if link_type == "walk" else link_type,
		link_type, float(link.get("cost", 1.0)),
		float(link.get("duration", 0.0)), str(link.get("action_id", "")), metadata)
	edge["category"] = "connector"
	return edge

func _ml_relax(
	nkey: String,
	from_key: String,
	tentative_g: float,
	edge: Dictionary,
	came_from: Dictionary,
	came_edge: Dictionary,
	g: Dictionary,
	open: Array[String],
	closed: Dictionary
) -> void:
	if closed.has(nkey) or tentative_g >= float(g.get(nkey, INF)):
		return
	came_from[nkey] = from_key
	came_edge[nkey] = edge
	g[nkey] = tentative_g
	if not open.has(nkey):
		open.append(nkey)

func _ml_reconstruct_plan(
	came_from: Dictionary,
	came_edge: Dictionary,
	current: String,
	total_cost: float
) -> Dictionary:
	var keys: Array[String] = [current]
	var reversed_edges: Array[Dictionary] = []
	while came_from.has(current):
		reversed_edges.append((came_edge.get(current, {}) as Dictionary).duplicate(true))
		current = came_from[current]
		keys.append(current)
	keys.reverse()
	reversed_edges.reverse()
	var nodes: Array[Dictionary] = []
	for key in keys:
		nodes.append(_nav_node(_ml_cell(key), _ml_level(key)))
	return {
		"contract_id": MULTI_LEVEL_PLAN_CONTRACT_ID,
		"nodes": nodes,
		"edges": reversed_edges,
		"total_cost": total_cost,
	}

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

func _reconstruct_dense_path(
		came_from: PackedInt32Array,
		current_index: int,
		start_index: int,
		level: int = 0
	) -> Array[Vector3]:
	# Collect backwards, then emit forwards. This avoids push_front's repeated
	# array shifts while retaining one waypoint per cell and excluding the start.
	var reversed_indices := PackedInt32Array()
	while current_index != start_index and current_index >= 0:
		reversed_indices.append(current_index)
		current_index = came_from[current_index]
	var path: Array[Vector3] = []
	for i in range(reversed_indices.size() - 1, -1, -1):
		var cell_index := reversed_indices[i]
		path.append(grid_to_world(
			Vector2i(cell_index % width, int(cell_index / width)), level))
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
## `blocked` is an extra Vector2i->bool obstacle set (other pushable objects' cells — a crate is an
## obstacle to a crate): the object may not enter those cells and the character may not stand there.
func plan_push(obj_cell: Vector2i, char_cell: Vector2i, target_cell: Vector2i, level := 0,
		blocked: Dictionary = {}) -> Dictionary:
	if not is_walkable(target_cell.x, target_cell.y, {}, {}, level) or blocked.has(target_cell):
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
			if not is_walkable(obj_to.x, obj_to.y, {}, {}, level) or blocked.has(obj_to):
				continue
			if not is_walkable(push_cell.x, push_cell.y, {}, {}, level) or blocked.has(push_cell):
				continue
			if not _char_can_reach(chr, push_cell, obj, level, blocked):
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
## `blocked` extends the walls (other pushable objects — you cannot walk through a crate).
func _char_can_reach(from: Vector2i, to: Vector2i, obj_cell: Vector2i, level: int,
		blocked: Dictionary = {}) -> bool:
	if from == to:
		return true
	if to == obj_cell or blocked.has(to):
		return false
	var frontier: Array[Vector2i] = [from]
	var seen := {from: true}
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in _PUSH_DIRS:
			var n: Vector2i = c + d
			if n == to:
				return true
			if seen.has(n) or n == obj_cell or blocked.has(n):
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
