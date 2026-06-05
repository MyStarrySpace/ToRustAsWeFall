class_name GameState
extends RefCounted

const NavigationGraphScript := preload("res://scripts/system/core/navigation_graph.gd")

## Scheduler-driven state for movement, stats, items, hazards, and replay.
## Positions are derived from ticks. Detection is predicted when movement changes.

signal character_arrived(id: String)
signal detection_predicted(detector_id: String, target_id: String)
signal physics_collision(obj_id: String, collider_id: String, impulse: Vector3)
signal pendulum_hit(pendulum_id: String, target_id: String, bob_velocity: Vector3)
signal item_picked_up(char_id: String, item_id: String)
signal item_dropped(char_id: String, item_id: String)
signal item_endocytosed(char_id: String, item_id: String, effect: String)
signal item_transferred(from_id: String, to_id: String, item_id: String)
signal item_exocytosed(char_id: String, item_id: String)
signal ability_fired(char_id: String, ability: String, target_pos: Vector3)
signal dodge_started(char_id: String, direction: Vector3)
signal dodge_finished(char_id: String)
signal stat_changed(char_id: String, stat: String, value: float)
signal running_changed(char_id: String, running: bool)
signal interactable_registered(id: String)
signal interactable_triggered(id: String, character: String)
signal interactable_enabled_changed(id: String, enabled: bool)

var grid: GridWorld
var navigation_graph
var scheduler: EventScheduler
var explored: Dictionary = {}
var characters: Dictionary = {}
var physics_objects: Dictionary = {}
var pendulums: Dictionary = {}
var items: Dictionary = {}        # item_id → item dict
var collection: Array[String] = [] # Permanently collected item IDs (cure components, etc.)
## Scene-scoped mechanisms, not serialized.
var mechanisms: Dictionary = {}   # id (StringName) → Mechanism
## Scene-scoped interactables as data (the source of truth; the scene node is a
## view bound to an id). Like mechanisms: rebuilt by replaying the log, not
## snapshot-serialized. id (String) → spec Dictionary.
var interactables: Dictionary = {}
var _next_item_id := 1
var _endocytosing: Dictionary = {} # char_id → {item_id, handle} for in-progress endocytosis
var _dodging: Dictionary = {}     # char_id → {end_tick, handle}
## Per-character running tick state. Missing key = walking.
var _running: Dictionary = {}
## Cooperative-pathfinding space-time reservations: Vector2i cell →
## Array of {t0, t1, id}. A character claims each cell it transits for a
## padded time window so others can plan paths that never overlap it in
## space and time. Derived from movement, never serialized.
var _reservations: Dictionary = {}

## In-flight cross-level (multi-floor) moves: char_id → ordered Array of
## per-level segments {level: int, cells: Array[Vector2i]}. The character walks
## segment[0] to its last cell (a ladder/ramp), transitions floors there, then
## walks the next segment. Derived from one KIND_MOVE_CROSS_LEVEL command, never
## serialized — replay re-runs the command and reproduces every transition.
var _cross_level_plan: Dictionary = {}

const HP_MAX := 100.0
const STAMINA_MAX := 100.0
const ATP_MAX_PIPS := 8.0
const WALK_SPEED := 3.0
const RUN_SPEED := 6.0
const RUN_STAMINA_DRAIN_PER_SEC := 30.0
const RUN_TICK_INTERVAL := 0.1

static func normalize_atp(value: float) -> float:
	if value > ATP_MAX_PIPS + 0.001:
		return clampf(roundf((value / 100.0) * ATP_MAX_PIPS), 0.0, ATP_MAX_PIPS)
	return clampf(roundf(value), 0.0, ATP_MAX_PIPS)

static func clamp_atp(value: float) -> float:
	return clampf(roundf(value), 0.0, ATP_MAX_PIPS)

static func atp_text(value: float) -> String:
	return "%d/%d" % [int(normalize_atp(value)), int(ATP_MAX_PIPS)]

## Optional log for external commands.
var event_log: EventLog
var _recording: bool = true

## Consumed by the next GameState so CLI recording starts at setup.
static var _pending_event_log: EventLog = null

## Run seed used by every deterministic RNG.
var base_seed: int = 0

## Per-system deterministic RNG registry.
var rng_registry: RngRegistry

func _init() -> void:
	if _pending_event_log != null:
		event_log = _pending_event_log
		_pending_event_log = null
	rng_registry = RngRegistry.new(base_seed)

## Set before systems fetch RNGs.
func set_base_seed(seed_value: int) -> void:
	base_seed = seed_value
	rng_registry = RngRegistry.new(seed_value)
	if event_log != null:
		event_log.base_seed = seed_value

func _record_tick() -> float:
	if scheduler:
		return scheduler.get_current_tick()
	return 0.0

func _emit(kind: StringName, payload: Dictionary) -> void:
	if event_log == null or not _recording:
		return
	event_log.append(GameEvent.make(_record_tick(), kind, payload))

## Extend the log to the current scheduler tick before serializing.
func flush_tick() -> void:
	if event_log != null and _recording and scheduler:
		event_log.note_tick(scheduler.get_current_tick())

## Pendulum schema:
## {
##   anchor: Vector3,         # Pivot point (top of swing)
##   length: float,           # Rope/chain length
##   amplitude: float,        # Max swing angle in radians
##   phase: float,            # Phase offset in radians
##   swing_axis: Vector3,     # Normalized swing-plane axis.
##   bob_radius: float,       # Collision radius of the bob
##   damping: float,          # Amplitude decay per second (0 = no decay)
##   start_tick: float,       # When oscillation began
## }

## PhysicsObject schema:
## {
##   position: Vector3,
##   radius: float,           # Collision radius
##   mass: float,             # 1.0 = character-weight
##   friction: float,         # 0.3 = icy, 0.8 = rough
##   movement: Dictionary|null,  # Same schema as character movement
##   grid_cell: Vector2i,
##   pushable: bool,
## }

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
	_emit(GameEvent.KIND_REGISTER_CHARACTER, {
		"id": id,
		"pos": GameEvent.v3_to_arr(pos),
		"speed": speed,
		"stats": stats.duplicate(true),
	})
	var normalized_stats := stats.duplicate(true)
	if normalized_stats.has("atp"):
		normalized_stats["atp"] = normalize_atp(float(normalized_stats["atp"]))
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	characters[id] = {
		"position": pos,
		"grid_cell": cell,
		"level": _level_for_y(pos.y),  # which stacked floor (derived from spawn Y)
		"move_speed": speed,
		"stats": normalized_stats,
		"movement": null,
		"hands": [null, null],
		"internal": [],
	}
	explored[id] = {}
	_reserve_parked(id, cell)

## Which stacked floor a world Y sits on (round to the nearest grid level). 0 without a grid.
func _level_for_y(y: float) -> int:
	if grid != null and grid.level_height > 0.0:
		return int(round((y - grid.origin.y) / grid.level_height))
	return 0

func get_character_level(id: String) -> int:
	return int((characters.get(id, {}) as Dictionary).get("level", 0))

## Set a character's floor (a level transition — a ladder/ramp arrival). Stops any current move and
## snaps the data-layer Y to that floor, so positions/paths read at the right height.
func set_character_level(id: String, level: int) -> void:
	if not characters.has(id):
		return
	_emit(GameEvent.KIND_SET_LEVEL, {"id": id, "level": level})
	_apply_set_level(id, level)

## Floor change without its own log entry — used by the cross-level executor so a
## whole multi-floor traversal is one logged command (the transitions are derived,
## not separately recorded). Snaps the data-layer Y to the target floor.
func _apply_set_level(id: String, level: int) -> void:
	if not characters.has(id):
		return
	var p := get_position(id)  # capture the current interpolated position before cancelling
	_cancel_movement(id)
	characters[id]["level"] = level
	if grid != null:
		p.y = grid.origin.y + float(level) * grid.level_height
	characters[id]["position"] = p
	if grid != null:
		characters[id]["grid_cell"] = grid.world_to_grid(p)
		_reserve_parked(id, characters[id]["grid_cell"])

func unregister_character(id: String) -> void:
	_emit(GameEvent.KIND_UNREGISTER_CHARACTER, {"id": id})
	_cross_level_plan.erase(id)
	if characters.has(id):
		# Cleanup only; no log entry.
		if _running.has(id):
			var handle: int = int(_running[id].get("tick_handle", 0))
			if handle != 0 and scheduler:
				scheduler.cancel(handle)
			_running.erase(id)
		_cancel_movement(id)
	characters.erase(id)
	explored.erase(id)

# --- Movement Commands ---

func set_navigation_graph(graph) -> void:
	navigation_graph = graph

func set_navigation_data(data: Dictionary) -> void:
	if data.is_empty():
		navigation_graph = null
		return
	navigation_graph = NavigationGraphScript.new()
	navigation_graph.configure(data)

func clear_navigation_graph() -> void:
	navigation_graph = null

func get_navigation_state() -> Dictionary:
	if navigation_graph == null:
		return {}
	if navigation_graph.has_method("get_state"):
		return navigation_graph.call("get_state")
	return {}

## A* pathfind to a grid cell on the character's current floor. Returns true if a path was found.
func command_move_to_cell(id: String, cell: Vector2i) -> bool:
	_cross_level_plan.erase(id)  # a fresh explicit move supersedes any in-flight cross-level traversal
	_emit(GameEvent.KIND_MOVE_TO_CELL, {"id": id, "cell": GameEvent.v2i_to_arr(cell)})
	return _do_move_to_cell(id, cell)

## Straight-line move to a world position.
func command_move_to_pos(id: String, pos: Vector3) -> bool:
	_cross_level_plan.erase(id)
	_emit(GameEvent.KIND_MOVE_TO_POS, {"id": id, "pos": GameEvent.v3_to_arr(pos)})
	return _do_move_to_pos(id, pos)

## Pathfind to a cell on a (possibly different) floor, routing over ladders/ramps.
## On the same floor this is just command_move_to_cell. Across floors it walks to the
## ladder cell on the current floor, transitions there, then continues — one logged
## command (KIND_MOVE_CROSS_LEVEL) that replay reproduces transition-for-transition.
## Returns true if a (multi-floor) route exists.
func command_move_cross_level(id: String, end_cell: Vector2i, end_level: int) -> bool:
	_emit(GameEvent.KIND_MOVE_CROSS_LEVEL, {
		"id": id,
		"cell": GameEvent.v2i_to_arr(end_cell),
		"level": end_level,
	})
	return _do_move_cross_level(id, end_cell, end_level)

func _do_move_cross_level(id: String, end_cell: Vector2i, end_level: int) -> bool:
	_cross_level_plan.erase(id)
	if not characters.has(id) or not grid or not scheduler:
		return false
	if is_endocytosing(id):
		return false
	var cur_pos := get_position(id)
	var cur_cell := grid.world_to_grid(cur_pos)
	var cur_level := get_character_level(id)
	if cur_level == end_level:
		return _do_move_to_cell(id, end_cell)  # same floor — ordinary cooperative move
	var path: Array = grid.find_multi_level_path(cur_cell, cur_level, end_cell, end_level)
	if path.is_empty():
		return false  # no ladder/ramp route between these floors
	# Split the route into per-floor segments. A floor change sits between two consecutive
	# waypoints that share the link cell, so the link cell ends one segment and begins the next.
	var segments: Array = []
	var seg := {"level": int(path[0]["level"]), "cells": ([] as Array)}
	for wp in path:
		if int(wp["level"]) != int(seg["level"]):
			segments.append(seg)
			seg = {"level": int(wp["level"]), "cells": ([] as Array)}
		(seg["cells"] as Array).append(wp["cell"])
	segments.append(seg)
	_cross_level_plan[id] = segments
	# The executor advances on each arrival; connect once (survives replay's fresh GameState).
	if not character_arrived.is_connected(_on_cross_level_arrival):
		character_arrived.connect(_on_cross_level_arrival)
	# Walk the first segment to its last cell (the ladder, or the destination if single-floor-after-all).
	var seg0_cells: Array = segments[0]["cells"]
	return _do_move_to_cell(id, seg0_cells[seg0_cells.size() - 1])

## On arrival, advance the cross-level plan: drop the finished segment, and if more remain,
## transition to the next floor (no separate log entry) and walk that segment. The final
## arrival leaves the plan empty and propagates as the genuine destination arrival.
func _on_cross_level_arrival(id: String) -> void:
	if not _cross_level_plan.has(id):
		return
	var segments: Array = _cross_level_plan[id]
	segments.pop_front()  # the segment we just finished
	if segments.is_empty():
		_cross_level_plan.erase(id)
		return
	var next_seg: Dictionary = segments[0]
	_apply_set_level(id, int(next_seg["level"]))  # floor change at the shared ladder cell
	var cells: Array = next_seg["cells"]
	_do_move_to_cell(id, cells[cells.size() - 1])

# Internal move without its own log entry.
func _do_move_to_pos(id: String, pos: Vector3) -> bool:
	if not characters.has(id) or not scheduler:
		return false
	if is_endocytosing(id):
		return false
	var current_pos := get_position(id)
	var target := Vector3(pos.x, pos.y, pos.z)
	_cancel_movement(id)
	characters[id].position = current_pos
	_start_movement(id, _resolve_world_path(current_pos, target))
	return true

## Set an explicit path (scripted waypoints).
func command_walk_path(id: String, path: Array[Vector3]) -> void:
	_cross_level_plan.erase(id)
	_emit(GameEvent.KIND_WALK_PATH, {"id": id, "path": GameEvent.path_to_arr(path)})
	if not characters.has(id) or not scheduler or path.is_empty():
		return
	if is_endocytosing(id):
		return
	var current_pos := get_position(id)
	_cancel_movement(id)
	characters[id].position = current_pos
	var full_path: Array[Vector3] = [current_pos]
	full_path.append_array(path)
	_start_movement(id, full_path)

## Halt movement at current interpolated position.
func command_stop(id: String) -> void:
	_cross_level_plan.erase(id)
	_emit(GameEvent.KIND_STOP, {"id": id})
	_do_stop(id)

func _do_stop(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement != null:
		ch.position = get_position(id)
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
	_cancel_movement(id)
	_reserve_parked(id, ch.grid_cell)

## Change movement speed. If currently moving, recalculates arrival time.
func change_move_speed(id: String, new_speed: float) -> void:
	_emit(GameEvent.KIND_CHANGE_SPEED, {"id": id, "speed": new_speed})
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
		# Replan cooperatively at the new speed so a mid-move speed change (e.g.
		# toggling run) keeps respecting other characters' reservations rather
		# than reverting to a plain, overlap-prone straight path.
		var dest_cell := grid.world_to_grid(dest)
		var current_cell := grid.world_to_grid(current_pos)
		if _begin_cooperative_move(id, current_pos, current_cell, dest_cell, new_speed):
			return
	_start_movement(id, _resolve_world_path(current_pos, dest))

func _resolve_world_path(current_pos: Vector3, target: Vector3) -> Array[Vector3]:
	if navigation_graph != null and navigation_graph.has_method("find_path"):
		var raw_path: Variant = navigation_graph.call("find_path", current_pos, target)
		var resolved: Array[Vector3] = []
		if raw_path is Array:
			for point in raw_path:
				if point is Vector3:
					resolved.append(point)
		if resolved.size() >= 2:
			if resolved[0].distance_to(current_pos) > 0.01:
				resolved.push_front(current_pos)
			if resolved[resolved.size() - 1].distance_to(target) > 0.01:
				resolved.append(target)
			return resolved
	return [current_pos, target]

# --- Queries ---

## Current position, interpolated while moving.
func get_position(id: String) -> Vector3:
	if not characters.has(id):
		return Vector3.ZERO
	var ch: Dictionary = characters[id]
	if ch.movement == null or not scheduler:
		return ch.position
	var mv: Dictionary = ch.movement
	if mv.has("arrival_ticks"):
		return _interpolate_path_timed(mv.path, mv.arrival_ticks, scheduler.get_current_tick())
	if mv.duration <= 0.0:
		return mv.path[mv.path.size() - 1]
	var t := clampf((scheduler.get_current_tick() - mv.start_tick) / mv.duration, 0.0, 1.0)
	return _interpolate_path(mv.path, mv.cum_dist, t)

func is_moving(id: String) -> bool:
	if not characters.has(id):
		return false
	return characters[id].movement != null

# --- Stats ---

## Read a stat (hp/stamina/atp/...). Returns 0.0 if unknown character or stat.
func get_stat(id: String, stat: String) -> float:
	if not characters.has(id):
		return 0.0
	return float(characters[id].stats.get(stat, 0.0))

## Per-character cap for hp/stamina/atp.
func get_stat_cap(id: String, stat: String) -> float:
	if not characters.has(id):
		return 0.0
	var stats: Dictionary = characters[id].stats
	var cap_key := stat + "_max"
	if stats.has(cap_key):
		return float(stats[cap_key])
	match stat:
		"hp": return HP_MAX
		"stamina": return STAMINA_MAX
		"atp": return ATP_MAX_PIPS
	return 0.0

## Set a stat and clamp hp/stamina/atp to their caps.
func set_stat(id: String, stat: String, value: float) -> void:
	_emit(GameEvent.KIND_SET_STAT, {"id": id, "stat": stat, "value": value})
	if not characters.has(id):
		return
	var clamped: float = value
	match stat:
		"stamina":
			clamped = clampf(value, 0.0, get_stat_cap(id, "stamina"))
		"hp":
			clamped = clampf(value, 0.0, get_stat_cap(id, "hp"))
		"atp":
			clamped = clampf(roundf(value), 0.0, get_stat_cap(id, "atp"))
	characters[id].stats[stat] = clamped
	stat_changed.emit(id, stat, clamped)

## Shorthand for relative stat changes (damage, drain, healing).
func adjust_stat(id: String, stat: String, delta: float) -> void:
	set_stat(id, stat, get_stat(id, stat) + delta)

## Apply a stat_upgrade payload. Capacity upgrades also refill the stat.
func _apply_stat_upgrade(char_id: String, payload: Dictionary) -> void:
	if not characters.has(char_id):
		return
	var stat: String = str(payload.get("stat", ""))
	var amount: float = float(payload.get("amount", 0.0))
	if stat == "" or amount == 0.0:
		return
	var stats: Dictionary = characters[char_id].stats
	if stat in ["hp_max", "stamina_max", "atp_max"]:
		# Upgrade from the current cap, including defaults.
		var current_stat := stat.substr(0, stat.find("_max"))
		var new_cap: float = get_stat_cap(char_id, current_stat) + amount
		stats[stat] = new_cap
		stat_changed.emit(char_id, stat, new_cap)
		set_stat(char_id, current_stat, new_cap)
	else:
		var new_value: float = float(stats.get(stat, 0.0)) + amount
		stats[stat] = new_value
		stat_changed.emit(char_id, stat, new_value)

# --- Running ---

func is_running(id: String) -> bool:
	return _running.has(id)

## Enter or leave running state.
func set_running(id: String, running: bool) -> void:
	_emit(GameEvent.KIND_SET_RUNNING, {"id": id, "running": running})
	if not characters.has(id):
		return
	if running == is_running(id):
		return
	if running:
		if get_stat(id, "stamina") <= 0.0:
			return
		_running[id] = {"tick_handle": 0}
		change_move_speed(id, RUN_SPEED)
		_schedule_running_tick(id)
	else:
		var entry: Dictionary = _running.get(id, {})
		var handle: int = int(entry.get("tick_handle", 0))
		if handle != 0 and scheduler:
			scheduler.cancel(handle)
		_running.erase(id)
		change_move_speed(id, WALK_SPEED)
	running_changed.emit(id, running)

func toggle_running(id: String) -> void:
	set_running(id, not is_running(id))

func _schedule_running_tick(id: String) -> void:
	if not is_running(id) or not scheduler:
		return
	var handle := scheduler.schedule_after(
		RUN_TICK_INTERVAL,
		func(): _on_running_tick(id),
		"running_" + id
	)
	_running[id]["tick_handle"] = handle

func _on_running_tick(id: String) -> void:
	if not is_running(id) or not characters.has(id):
		return
	if not is_moving(id):
		# Pause stamina ticks while idle.
		if _running.has(id):
			_running[id]["tick_handle"] = 0
		return
	var new_val: float = maxf(0.0, get_stat(id, "stamina") - RUN_STAMINA_DRAIN_PER_SEC * RUN_TICK_INTERVAL)
	set_stat(id, "stamina", new_val)
	if new_val <= 0.0:
		set_running(id, false)
		return
	_schedule_running_tick(id)

## Restore all registered characters to full stats and clear running flags.
func reset_characters_to_full() -> void:
	for id in characters.keys():
		if is_running(id):
			set_running(id, false)
		set_stat(id, "hp", get_stat_cap(id, "hp"))
		set_stat(id, "stamina", get_stat_cap(id, "stamina"))
		set_stat(id, "atp", get_stat_cap(id, "atp"))

func get_grid_cell(id: String) -> Vector2i:
	if not grid:
		return Vector2i.ZERO
	return grid.world_to_grid(get_position(id))

# --- Serialization ---

## Same-process hash for tests. Use serialize() for cross-process checks.
func state_hash() -> int:
	return serialize().hash()

## Snapshot for save/load. Movement is re-established by sequences.
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

## Begin interpolated movement along full_path. If arrival_ticks is supplied
## (one absolute tick per waypoint, monotonic, arrival_ticks[0] == now), the
## character follows that exact timing — letting cooperative paths embed waits.
## Otherwise timing is uniform constant-speed, identical to the prior behavior.
func _start_movement(id: String, full_path: Array[Vector3], arrival_ticks: Array[float] = []) -> void:
	var ch: Dictionary = characters[id]
	var cum_dist := _compute_cum_dist(full_path)
	var total_dist: float = cum_dist[cum_dist.size() - 1]
	if total_dist < 0.01:
		ch.position = full_path[full_path.size() - 1]
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
		_clear_reservations(id)
		_reserve_parked(id, ch.grid_cell)
		character_arrived.emit(id)
		_recompute_all_detection_predictions()
		_recompute_physics_predictions()
		return
	var speed: float = ch.move_speed
	var start_tick := scheduler.get_current_tick()
	var ticks: Array[float] = arrival_ticks
	if ticks.size() != full_path.size():
		ticks = []
		for d in cum_dist:
			ticks.append(start_tick + d / speed)
	var final_tick: float = ticks[ticks.size() - 1]
	var duration := final_tick - start_tick
	var handle := scheduler.schedule_at(
		final_tick,
		func(): _on_arrival(id),
		"movement_" + id
	)
	ch.movement = {
		"path": full_path,
		"cum_dist": cum_dist,
		"arrival_ticks": ticks,
		"total_distance": total_dist,
		"start_tick": start_tick,
		"duration": duration,
		"handle": handle,
	}
	_reserve_path(id, full_path, ticks)
	# Resume stamina drain on movement.
	# that the character is in motion again.
	if is_running(id) and int(_running[id].get("tick_handle", 0)) == 0:
		_schedule_running_tick(id)
	_recompute_all_detection_predictions()
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func _cancel_movement(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement != null:
		if scheduler:
			scheduler.cancel(ch.movement.handle)
		ch.movement = null
	_clear_reservations(id)
	_recompute_all_detection_predictions()
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

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
	_reserve_parked(id, ch.grid_cell)
	character_arrived.emit(id)

static func _compute_cum_dist(path: Array[Vector3]) -> Array[float]:
	var result: Array[float] = [0.0]
	for i in range(1, path.size()):
		result.append(result[result.size() - 1] + path[i - 1].distance_to(path[i]))
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

## Interpolate along a path with explicit per-waypoint arrival ticks. Unlike the
## constant-speed variant, this honors uneven segment timing — including a
## "wait" segment where two consecutive waypoints share a position but span time,
## which holds the character in place. Cooperative paths use this to pause and let
## another character pass.
static func _interpolate_path_timed(path: Array[Vector3], arrival_ticks: Array, tick: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var n := path.size()
	if n == 1 or tick <= arrival_ticks[0]:
		return path[0]
	if tick >= arrival_ticks[n - 1]:
		return path[n - 1]
	for i in range(1, n):
		if arrival_ticks[i] >= tick:
			var span: float = arrival_ticks[i] - arrival_ticks[i - 1]
			if span <= 0.0001:
				return path[i]
			var seg_t: float = (tick - arrival_ticks[i - 1]) / span
			return path[i - 1].lerp(path[i], seg_t)
	return path[n - 1]

# --- Cooperative pathfinding (space-time reservations) ---
#
# Each character claims every cell it transits for a padded time window. The
# window for cell k spans from when the character leaves cell k-1 until it
# reaches cell k+1 — a 3-cell sliding claim, so a head-on swap (A: X→Y while
# B: Y→X at the same time) shows up as overlapping claims on BOTH shared cells
# and is rejected by a single vertex check. The space-time A* plans paths that
# avoid every reserved (cell, time) window, inserting waits when needed.
# Reservations are derived from movement and scheduler ticks, so they replay
# identically and behave the same under fast-forward.

## Slack ticks padded around each reserved window so characters keep a little
## space and never graze at a shared boundary.
const _RESERVE_BUFFER := 0.18
## A parked character holds its cell effectively forever; others route around it.
const _PARK_HORIZON := 1.0e12
## Search bounds for the cooperative planner. Generous so legitimate solutions
## that need a long wait (e.g. letting a slow character clear a corridor) are
## found, keeping the overlap-prone plain-A* fallback a true last resort.
const _COOP_MAX_NODES := 12000
## Extra wait/detour slack (in cell-times) the planner may spend beyond the
## straight-line estimate before giving up.
const _COOP_WAIT_SLACK_CELLS := 48.0

func _clear_reservations(id: String) -> void:
	if _reservations.is_empty():
		return
	var empty_cells: Array = []
	for cell in _reservations:
		var slots: Array = _reservations[cell]
		var kept: Array = []
		for s in slots:
			if s.id != id:
				kept.append(s)
		if kept.is_empty():
			empty_cells.append(cell)
		else:
			_reservations[cell] = kept
	for cell in empty_cells:
		_reservations.erase(cell)

func _add_reservation(cell: Vector2i, t0: float, t1: float, id: String) -> void:
	if not _reservations.has(cell):
		_reservations[cell] = []
	_reservations[cell].append({"t0": t0, "t1": t1, "id": id})

## Reserve a stationary character's cell from now to the horizon.
func _reserve_parked(id: String, cell: Vector2i) -> void:
	if not scheduler:
		return
	_clear_reservations(id)
	_add_reservation(cell, scheduler.get_current_tick() - _RESERVE_BUFFER, _PARK_HORIZON, id)

## Reserve every cell a path transits with its 3-cell sliding time window. The
## final (destination) cell is held to the horizon since the character parks there.
func _reserve_path(id: String, world_path: Array[Vector3], arrival_ticks: Array) -> void:
	if not grid:
		return
	_clear_reservations(id)
	var n := world_path.size()
	for k in range(n):
		var cell := grid.world_to_grid(world_path[k])
		var lo := maxi(0, k - 1)
		var hi := mini(n - 1, k + 1)
		var t0: float = float(arrival_ticks[lo]) - _RESERVE_BUFFER
		var t1: float
		if k == n - 1:
			t1 = _PARK_HORIZON
		else:
			t1 = float(arrival_ticks[hi]) + _RESERVE_BUFFER
		_add_reservation(cell, t0, t1, id)

## True if any character other than exclude_id has cell reserved during [t0, t1].
func _cell_reserved(cell: Vector2i, t0: float, t1: float, exclude_id: String) -> bool:
	if not _reservations.has(cell):
		return false
	for s in _reservations[cell]:
		if s.id == exclude_id:
			continue
		if t0 <= s.t1 and s.t0 <= t1:
			return true
	return false

func _coop_h(cell: Vector2i, end: Vector2i, card: float) -> float:
	var dx := absf(cell.x - end.x)
	var dz := absf(cell.y - end.y)
	return (maxf(dx, dz) + 0.4142136 * minf(dx, dz)) * card

func _coop_key(cell: Vector2i, t: float, t_start: float, tq: float) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, int(round((t - t_start) / tq))]

## Space-time A*: a grid-cell path from start to end whose timed transit avoids
## every reserved (cell, time) window owned by another character, inserting
## waits where needed. Returns {cells: Array[Vector2i], ticks: Array[float]}
## (absolute arrival tick per cell) or {} if no conflict-free path is found.
func _plan_cooperative(start: Vector2i, end: Vector2i, speed: float, t_start: float, exclude_id: String) -> Dictionary:
	if not grid:
		return {}
	if start == end:
		return {"cells": [start] as Array[Vector2i], "ticks": [t_start] as Array[float]}
	if not grid.is_in_bounds(end.x, end.y) or not grid.is_walkable(end.x, end.y):
		return {}
	var card: float = (grid.cell_size / speed) if speed > 0.0 else 1.0
	var diag: float = card * 1.4142136
	var tq: float = maxf(card * 0.5, 0.0001)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	# A budget on total time so the planner can't wait/wander forever.
	var time_budget: float = _coop_h(start, end, card) * 3.0 + card * _COOP_WAIT_SLACK_CELLS
	var open: Array = [{"cell": start, "t": t_start, "g": 0.0, "f": _coop_h(start, end, card)}]
	var start_key := _coop_key(start, t_start, t_start, tq)
	var best_g: Dictionary = {start_key: 0.0}
	var came: Dictionary = {start_key: {"cell": start, "t": t_start, "pkey": ""}}
	var nodes := 0
	while not open.is_empty() and nodes < _COOP_MAX_NODES:
		nodes += 1
		var bi := 0
		for i in range(1, open.size()):
			if open[i].f < open[bi].f:
				bi = i
		var cur: Dictionary = open[bi]
		open.remove_at(bi)
		var ccell: Vector2i = cur.cell
		var ct: float = cur.t
		var cur_key := _coop_key(ccell, ct, t_start, tq)
		# A stale entry (we already reached this state cheaper) — skip.
		if cur.g > float(best_g.get(cur_key, INF)) + 0.0001:
			continue
		if ccell == end:
			return _coop_reconstruct(came, cur_key)
		# Eight moves plus a wait-in-place.
		for di in range(dirs.size() + 1):
			var is_wait := di == dirs.size()
			var ncell: Vector2i = ccell if is_wait else ccell + dirs[di]
			var dt: float = card
			if not is_wait:
				var dir := dirs[di]
				var is_diag := dir.x != 0 and dir.y != 0
				dt = diag if is_diag else card
				if not grid.is_in_bounds(ncell.x, ncell.y) or not grid.is_walkable(ncell.x, ncell.y):
					continue
				if is_diag:
					if not grid.is_walkable(ccell.x + dir.x, ccell.y) or not grid.is_walkable(ccell.x, ccell.y + dir.y):
						continue
			var nt: float = ct + dt
			if _cell_reserved(ncell, ct - _RESERVE_BUFFER, nt + _RESERVE_BUFFER, exclude_id):
				continue
			var ng: float = cur.g + dt
			if ng > time_budget:
				continue
			var nkey := _coop_key(ncell, nt, t_start, tq)
			if ng < float(best_g.get(nkey, INF)) - 0.0001:
				best_g[nkey] = ng
				came[nkey] = {"cell": ncell, "t": nt, "pkey": cur_key}
				open.append({"cell": ncell, "t": nt, "g": ng, "f": ng + _coop_h(ncell, end, card)})
	return {}

func _coop_reconstruct(came: Dictionary, key: String) -> Dictionary:
	var cells: Array[Vector2i] = []
	var ticks: Array[float] = []
	var k := key
	while k != "" and came.has(k):
		var node: Dictionary = came[k]
		cells.push_front(node.cell)
		ticks.push_front(float(node.t))
		k = String(node.pkey)
	return {"cells": cells, "ticks": ticks}

## Convert a planned cell sequence (cell centers + absolute arrival ticks) into a
## world path that begins at the character's actual current position. A short
## glide from current_pos to the first cell center is timed by distance/speed,
## then the planner's per-cell ticks follow (shifted by that glide).
func _build_timed_world_path(current_pos: Vector3, cells: Array, plan_ticks: Array, speed: float, level: int = 0) -> Dictionary:
	var path: Array[Vector3] = [current_pos]
	var ticks: Array[float] = [float(plan_ticks[0])]
	var first_center := grid.grid_to_world(cells[0], level)
	var glide: float = (current_pos.distance_to(first_center) / speed) if speed > 0.0 else 0.0
	for i in range(cells.size()):
		path.append(grid.grid_to_world(cells[i], level))
		ticks.append(float(plan_ticks[i]) + glide)
	# Drop a redundant first center identical to current_pos (zero-length lead-in).
	if path.size() >= 2 and path[0].distance_to(path[1]) < 0.001 and absf(ticks[1] - ticks[0]) < 0.0001:
		path.remove_at(0)
		ticks.remove_at(0)
	return {"path": path, "ticks": ticks}

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

# --- Predictive Detection ---

func _recompute_all_detection_predictions() -> void:
	if not scheduler:
		return
	scheduler.cancel_tag("detection_predict")
	var now := scheduler.get_current_tick()
	var ids := characters.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var id_a: String = ids[i]
			var id_b: String = ids[j]
			var range_a: float = characters[id_a].stats.get("detection_range", 0.0)
			var range_b: float = characters[id_b].stats.get("detection_range", 0.0)
			if range_a > 0.0:
				var t := _predict_detection_time(id_a, id_b, range_a, now)
				if t >= 0.0:
					var det_id := id_a
					var tgt_id := id_b
					scheduler.schedule_at(t, func(): _on_detection_event(det_id, tgt_id), "detection_predict")
			if range_b > 0.0:
				var t := _predict_detection_time(id_b, id_a, range_b, now)
				if t >= 0.0:
					var det_id := id_b
					var tgt_id := id_a
					scheduler.schedule_at(t, func(): _on_detection_event(det_id, tgt_id), "detection_predict")

func _on_detection_event(detector_id: String, target_id: String) -> void:
	if not characters.has(detector_id) or not characters.has(target_id):
		return
	if is_dodging(target_id):
		return
	# Auto-dodge: if target has dodge queued, automatically evade
	var target_ch: Dictionary = characters[target_id]
	if target_ch.stats.get("auto_dodge", false) and target_ch.stats.get("dodge_unlocked", false):
		var attacker_pos := get_position(detector_id)
		var target_pos := get_position(target_id)
		var approach := Vector3(attacker_pos.x - target_pos.x, 0, attacker_pos.z - target_pos.z)
		if approach.length_squared() > 0.001:
			# Dodge perpendicular to the attack direction
			var perp := Vector3(-approach.z, 0, approach.x).normalized()
			if dodge_roll(target_id, perp):
				return
	detection_predicted.emit(detector_id, target_id)

func _predict_detection_time(detector_id: String, target_id: String, det_range: float, now: float) -> float:
	var segs_a := _get_movement_segments(detector_id)
	var segs_b := _get_movement_segments(target_id)
	var earliest := -1.0
	for seg_a in segs_a:
		for seg_b in segs_b:
			var t0: float = maxf(seg_a.start_tick, seg_b.start_tick)
			var t1: float = minf(seg_a.end_tick, seg_b.end_tick)
			if t0 >= t1:
				continue
			if t0 < now:
				t0 = now
			if t0 >= t1:
				continue
			var pos_a: Vector3 = seg_a.start_pos + (t0 - seg_a.start_tick) * seg_a.velocity
			var pos_b: Vector3 = seg_b.start_pos + (t0 - seg_b.start_tick) * seg_b.velocity
			var tau := _solve_quadratic_detection(pos_a, seg_a.velocity, pos_b, seg_b.velocity, det_range, t1 - t0)
			if tau >= 0.0:
				var abs_t := t0 + tau
				if earliest < 0.0 or abs_t < earliest:
					earliest = abs_t
	return earliest

func _get_movement_segments(id: String) -> Array[Dictionary]:
	var ch: Dictionary = characters[id]
	if ch.movement == null:
		var pos: Vector3 = ch.position
		return [{"start_tick": 0.0, "end_tick": 1e12, "start_pos": Vector3(pos.x, 0, pos.z), "velocity": Vector3.ZERO}]
	var mv: Dictionary = ch.movement
	var segments: Array[Dictionary] = []
	var has_ticks: bool = mv.has("arrival_ticks")
	for i in range(1, mv.path.size()):
		var seg_start_tick: float
		var seg_end_tick: float
		if has_ticks:
			seg_start_tick = mv.arrival_ticks[i - 1]
			seg_end_tick = mv.arrival_ticks[i]
		else:
			seg_start_tick = mv.start_tick + (mv.cum_dist[i - 1] / mv.total_distance) * mv.duration
			seg_end_tick = mv.start_tick + (mv.cum_dist[i] / mv.total_distance) * mv.duration
		var dir := Vector3(mv.path[i].x - mv.path[i - 1].x, 0, mv.path[i].z - mv.path[i - 1].z)
		var span: float = seg_end_tick - seg_start_tick
		var vel := dir / span if (dir.length() > 0.001 and span > 0.0001) else Vector3.ZERO
		segments.append({
			"start_tick": seg_start_tick,
			"end_tick": seg_end_tick,
			"start_pos": Vector3(mv.path[i - 1].x, 0, mv.path[i - 1].z),
			"velocity": vel,
		})
	return segments

# --- Dodge Roll ---

const DODGE_DISTANCE := 3.0
const DODGE_DURATION := 0.35
const DODGE_STAMINA_COST := 15.0
const DODGE_COOLDOWN := 1.0

func dodge_roll(char_id: String, direction: Vector3) -> bool:
	_emit(GameEvent.KIND_DODGE_ROLL, {
		"char_id": char_id,
		"direction": GameEvent.v3_to_arr(direction),
	})
	if not characters.has(char_id) or not scheduler:
		return false
	if is_endocytosing(char_id):
		return false
	var ch: Dictionary = characters[char_id]
	if not ch.stats.get("dodge_unlocked", false):
		return false
	if is_dodging(char_id):
		return false
	# Cooldown check
	var now := scheduler.get_current_tick()
	var last_dodge: float = ch.stats.get("_last_dodge_tick", -10.0)
	if now - last_dodge < DODGE_COOLDOWN:
		return false
	# Stamina check
	var stamina: float = ch.stats.get("stamina", 0.0)
	if stamina < DODGE_STAMINA_COST:
		return false

	# Consume stamina
	ch.stats["stamina"] = stamina - DODGE_STAMINA_COST
	ch.stats["_last_dodge_tick"] = now

	# Compute dodge destination
	var dir := Vector3(direction.x, 0, direction.z)
	if dir.length_squared() < 0.001:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var from := get_position(char_id)
	var to := from + dir * DODGE_DISTANCE

	# Wall trace
	if grid:
		to = _trace_slide_against_walls(from, to)
	var dodge_dist := Vector3(to.x - from.x, 0, to.z - from.z).length()
	if dodge_dist < 0.1:
		ch.stats["stamina"] = stamina  # Refund
		return false

	# Cancel current movement and start dodge movement
	_cancel_movement(char_id)
	ch.position = from

	var speed := dodge_dist / DODGE_DURATION
	var path: Array[Vector3] = [from, to]
	var cum_dist := _compute_cum_dist(path)
	var cid := char_id
	var handle := scheduler.schedule_at(
		now + DODGE_DURATION,
		func(): _on_dodge_end(cid),
		"dodge_" + char_id
	)
	var dodge_ticks: Array[float] = [now, now + DODGE_DURATION]
	ch.movement = {
		"path": path,
		"cum_dist": cum_dist,
		"arrival_ticks": dodge_ticks,
		"total_distance": dodge_dist,
		"start_tick": now,
		"duration": DODGE_DURATION,
		"handle": handle,
	}
	# Reserve the dodge's cells so a cooperative mover routes around the dodging
	# character (the manual movement dict above bypasses _start_movement).
	_reserve_path(char_id, path, dodge_ticks)
	_dodging[char_id] = {"end_tick": now + DODGE_DURATION, "handle": handle}

	dodge_started.emit(char_id, dir)
	_recompute_all_detection_predictions()
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()
	return true

func is_dodging(char_id: String) -> bool:
	return _dodging.has(char_id)

func _on_dodge_end(char_id: String) -> void:
	_dodging.erase(char_id)
	if not characters.has(char_id):
		return
	var ch: Dictionary = characters[char_id]
	if ch.movement != null:
		var dest: Vector3 = ch.movement.path[ch.movement.path.size() - 1]
		ch.position = dest
		if grid:
			ch.grid_cell = grid.world_to_grid(dest)
		ch.movement = null
	_reserve_parked(char_id, ch.grid_cell)
	dodge_finished.emit(char_id)

# --- Queued Abilities (auto-move-into-range) ---

var _queued_abilities: Dictionary = {} # char_id → {ability, target_pos, range, callback}

## Replay-safe ability handlers by ability id.
var _ability_handlers: Dictionary = {}

func register_ability_handler(ability_id: StringName, handler: Callable) -> void:
	_ability_handlers[ability_id] = handler

func queue_ability(char_id: String, ability: String, target_pos: Vector3, ability_range: float, callback: Callable) -> void:
	_emit(GameEvent.KIND_QUEUE_ABILITY, {
		"char_id": char_id,
		"ability": ability,
		"target_pos": GameEvent.v3_to_arr(target_pos),
		"range": ability_range,
	})
	if not characters.has(char_id):
		return
	var char_pos := get_position(char_id)
	var dist := Vector2(char_pos.x - target_pos.x, char_pos.z - target_pos.z).length()
	if dist <= ability_range:
		callback.call()
		ability_fired.emit(char_id, ability, target_pos)
		return
	_queued_abilities[char_id] = {
		"ability": ability,
		"target_pos": target_pos,
		"range": ability_range,
		"callback": callback,
	}
	var dir := Vector3(target_pos.x - char_pos.x, 0, target_pos.z - char_pos.z).normalized()
	var move_target := target_pos
	_do_move_to_pos(char_id, move_target)
	_schedule_ability_in_range(char_id)

func cancel_queued_ability(char_id: String) -> void:
	_emit(GameEvent.KIND_CANCEL_QUEUED_ABILITY, {"char_id": char_id})
	_queued_abilities.erase(char_id)
	if scheduler:
		scheduler.cancel_tag("ability_range")

func has_queued_ability(char_id: String) -> bool:
	return _queued_abilities.has(char_id)

func get_queued_ability(char_id: String) -> String:
	if _queued_abilities.has(char_id):
		return _queued_abilities[char_id].ability
	return ""

func _schedule_ability_in_range(char_id: String) -> void:
	if not _queued_abilities.has(char_id) or not scheduler:
		return
	scheduler.cancel_tag("ability_range_" + char_id)
	var qa: Dictionary = _queued_abilities[char_id]
	var now := scheduler.get_current_tick()
	var char_segs := _get_movement_segments(char_id)
	var target_seg: Array[Dictionary] = [{
		"start_tick": 0.0,
		"end_tick": 1e12,
		"start_pos": Vector3(qa.target_pos.x, 0, qa.target_pos.z),
		"velocity": Vector3.ZERO,
	}]
	var t := _predict_collision_time(char_segs, target_seg, qa.range, now)
	if t >= 0.0:
		var cid := char_id
		scheduler.schedule_at(t, func(): _on_ability_in_range(cid), "ability_range_" + char_id)

func _on_ability_in_range(char_id: String) -> void:
	if not _queued_abilities.has(char_id):
		return
	var qa: Dictionary = _queued_abilities[char_id]
	_queued_abilities.erase(char_id)
	_do_stop(char_id)
	qa.callback.call()
	ability_fired.emit(char_id, qa.ability, qa.target_pos)

# --- Items / Hands / Endocytosis ---

const TRANSFER_RANGE := 1.5
const ENDOCYTOSE_DEFAULT_DURATION := 2.0

func spawn_item(type: String, pos: Vector3, properties: Dictionary = {}) -> String:
	_emit(GameEvent.KIND_SPAWN_ITEM, {
		"type": type,
		"pos": GameEvent.v3_to_arr(pos),
		"properties": properties.duplicate(true),
	})
	var id := "item_%d" % _next_item_id
	_next_item_id += 1
	var type_data := ItemData.get_type_data(type)
	type_data.merge(properties, true)
	if not type_data.has("hand_slots"):
		type_data["hand_slots"] = ItemData.get_hand_slots(type)
	if not type_data.has("endocytosis_allowed"):
		type_data["endocytosis_allowed"] = ItemData.can_endocytose(type)
	items[id] = {
		"type": type,
		"holder": "",
		"location": "ground",
		"position": pos,
		"properties": type_data,
	}
	return id

func remove_item(item_id: String) -> void:
	_emit(GameEvent.KIND_REMOVE_ITEM, {"item_id": item_id})
	if not items.has(item_id):
		return
	var item: Dictionary = items[item_id]
	if item.holder != "" and characters.has(item.holder):
		var ch: Dictionary = characters[item.holder]
		if item.location == "hand":
			for i in range(ch.hands.size()):
				if ch.hands[i] == item_id:
					ch.hands[i] = null
		elif item.location == "internal":
			ch.internal.erase(item_id)
	items.erase(item_id)

func pick_up_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_PICK_UP_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id):
		return false
	if is_endocytosing(char_id):
		return false
	var item: Dictionary = items[item_id]
	if item.location != "ground":
		return false
	var ch: Dictionary = characters[char_id]
	var required_slots := _required_hand_slots(item)
	var slots := _find_free_hand_slots(char_id, required_slots)
	if slots.is_empty():
		return false
	var char_pos := get_position(char_id)
	var dist := Vector3(char_pos.x - item.position.x, 0, char_pos.z - item.position.z).length()
	if dist > 2.0:
		return false
	for slot in slots:
		ch.hands[int(slot)] = item_id
	item.holder = char_id
	item.location = "hand"
	item_picked_up.emit(char_id, item_id)
	return true

func drop_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_DROP_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id):
		return false
	if is_endocytosing(char_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "hand":
		return false
	var ch: Dictionary = characters[char_id]
	_clear_item_from_hands(ch, item_id)
	item.holder = ""
	item.location = "ground"
	item.position = get_position(char_id)
	item_dropped.emit(char_id, item_id)
	return true

func transfer_item(from_id: String, to_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_TRANSFER_ITEM, {"from_id": from_id, "to_id": to_id, "item_id": item_id})
	if not characters.has(from_id) or not characters.has(to_id) or not items.has(item_id):
		return false
	if is_endocytosing(from_id) or is_endocytosing(to_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != from_id or item.location != "hand":
		return false
	var to_slots := _find_free_hand_slots(to_id, _required_hand_slots(item))
	if to_slots.is_empty():
		return false
	var dist := get_position(from_id).distance_to(get_position(to_id))
	if dist > TRANSFER_RANGE:
		return false
	var from_ch: Dictionary = characters[from_id]
	_clear_item_from_hands(from_ch, item_id)
	var to_ch: Dictionary = characters[to_id]
	for slot in to_slots:
		to_ch.hands[int(slot)] = item_id
	item.holder = to_id
	item_transferred.emit(from_id, to_id, item_id)
	return true

func endocytose_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_ENDOCYTOSE_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id) or not scheduler:
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "hand":
		return false
	if not bool(item.properties.get("endocytosis_allowed", ItemData.can_endocytose(item.type))):
		return false
	if _endocytosing.has(char_id):
		return false
	_do_stop(char_id)
	var duration: float = item.properties.get("endocytosis_duration", ENDOCYTOSE_DEFAULT_DURATION)
	var cid := char_id
	var iid := item_id
	var handle := scheduler.schedule_after(duration, func(): _complete_endocytosis(cid, iid), "endocytose_" + char_id)
	_endocytosing[char_id] = {"item_id": item_id, "handle": handle}
	return true

func cancel_endocytosis(char_id: String) -> void:
	_emit(GameEvent.KIND_CANCEL_ENDOCYTOSIS, {"char_id": char_id})
	if not _endocytosing.has(char_id):
		return
	var info: Dictionary = _endocytosing[char_id]
	if scheduler:
		scheduler.cancel(info.handle)
	_endocytosing.erase(char_id)

func is_endocytosing(char_id: String) -> bool:
	return _endocytosing.has(char_id)

func _complete_endocytosis(char_id: String, item_id: String) -> void:
	_endocytosing.erase(char_id)
	if not characters.has(char_id) or not items.has(item_id):
		return
	var item: Dictionary = items[item_id]
	var ch: Dictionary = characters[char_id]
	var effect := ItemData.get_endocytosis_effect(item.type)

	# Remove from hand
	_clear_item_from_hands(ch, item_id)

	match effect:
		"digest":
			var restore: float = normalize_atp(float(item.properties.get("atp_restore", 0.0)))
			var current_atp: float = normalize_atp(float(ch.stats.get("atp", 0.0)))
			ch.stats["atp"] = clamp_atp(current_atp + restore)
			items.erase(item_id)
		"store":
			item.location = "internal"
			ch.internal.append(item_id)
			if item.properties.get("adds_to_collection", false) and item_id not in collection:
				collection.append(item_id)
		"stun_self":
			item.location = "internal"
			ch.internal.append(item_id)
		"scent_broadcast":
			item.location = "internal"
			ch.internal.append(item_id)
		"self_damage":
			var dmg: float = item.properties.get("damage", 0.0)
			var hp: float = ch.stats.get("hp", 100.0)
			ch.stats["hp"] = maxf(0.0, hp - dmg)
			items.erase(item_id)
		"stat_upgrade":
			var payload := ItemData.get_upgrade_payload(item.type)
			var locked_to: String = str(payload.get("locked_to", ""))
			if locked_to != "" and locked_to != char_id:
				# Wrong character; keep the item internally so it can be
				# transferred to whoever it's locked to. No upgrade applied.
				item.location = "internal"
				ch.internal.append(item_id)
			else:
				_apply_stat_upgrade(char_id, payload)
				items.erase(item_id)
		_:
			item.location = "internal"
			ch.internal.append(item_id)

	item_endocytosed.emit(char_id, item_id, effect)

func exocytose_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_EXOCYTOSE_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id):
		return false
	if is_endocytosing(char_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "internal":
		return false
	var ch: Dictionary = characters[char_id]
	ch.internal.erase(item_id)
	var slots := _find_free_hand_slots(char_id, _required_hand_slots(item))
	if not slots.is_empty():
		for slot in slots:
			ch.hands[int(slot)] = item_id
		item.location = "hand"
	else:
		item.holder = ""
		item.location = "ground"
		item.position = get_position(char_id)
	item_exocytosed.emit(char_id, item_id)
	return true

func get_hand_items(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	var result := []
	for slot in characters[char_id].hands:
		if slot != null and not result.has(slot):
			result.append(slot)
	return result

func get_hand_slots(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	return characters[char_id].hands.duplicate()

func get_internal_items(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	return characters[char_id].internal.duplicate()

func has_free_hand(char_id: String) -> bool:
	return _find_free_hand(char_id) >= 0

func has_free_hands(char_id: String, required_slots := 1) -> bool:
	return not _find_free_hand_slots(char_id, required_slots).is_empty()

func _find_free_hand(char_id: String) -> int:
	if not characters.has(char_id):
		return -1
	var hands: Array = characters[char_id].hands
	for i in range(hands.size()):
		if hands[i] == null:
			return i
	return -1

func _find_free_hand_slots(char_id: String, required_slots: int) -> Array[int]:
	var slots: Array[int] = []
	if not characters.has(char_id):
		return slots
	for i in range(characters[char_id].hands.size()):
		if characters[char_id].hands[i] == null:
			slots.append(i)
			if slots.size() >= maxi(required_slots, 1):
				return slots
	return []

func _clear_item_from_hands(ch: Dictionary, item_id: String) -> void:
	for i in range(ch.hands.size()):
		if ch.hands[i] == item_id:
			ch.hands[i] = null

func _required_hand_slots(item: Dictionary) -> int:
	return maxi(int(item.get("properties", {}).get("hand_slots", ItemData.get_hand_slots(str(item.get("type", ""))))), 1)

func get_scent_radius(char_id: String) -> float:
	if not characters.has(char_id):
		return 0.0
	var radius := 0.0
	for item_id in get_hand_items(char_id):
		if items.has(item_id) and ItemData.has_scent(items[item_id].type):
			var sr: float = items[item_id].properties.get("scent_radius", 0.0)
			radius = maxf(radius, sr)
	for item_id in get_internal_items(char_id):
		if items.has(item_id) and ItemData.has_scent(items[item_id].type):
			var sr: float = items[item_id].properties.get("scent_radius", 0.0)
			radius = maxf(radius, sr)
	return radius

# --- Physics Objects ---

const PHYSICS_COLLISION_RADIUS := 0.4
const PHYSICS_DECELERATION := 3.0  # Units/sec² deceleration during slide (game-tuned)
const PHYSICS_RESTITUTION := 0.85

func register_physics_object(id: String, pos: Vector3, radius: float = 0.5, mass: float = 2.0, friction: float = 0.6, pushable: bool = true) -> void:
	_emit(GameEvent.KIND_REGISTER_PHYSICS_OBJECT, {
		"id": id,
		"pos": GameEvent.v3_to_arr(pos),
		"radius": radius,
		"mass": mass,
		"friction": friction,
		"pushable": pushable,
	})
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	physics_objects[id] = {
		"position": pos,
		"radius": radius,
		"mass": mass,
		"friction": friction,
		"movement": null,
		"grid_cell": cell,
		"pushable": pushable,
	}
	if grid and pushable:
		grid.add_dynamic_blocker(cell, id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func unregister_physics_object(id: String) -> void:
	_emit(GameEvent.KIND_UNREGISTER_PHYSICS_OBJECT, {"id": id})
	if physics_objects.has(id):
		var obj: Dictionary = physics_objects[id]
		if obj.movement != null and scheduler:
			scheduler.cancel(obj.movement.handle)
		if grid:
			grid.remove_dynamic_blocker(obj.grid_cell)
	physics_objects.erase(id)
	_recompute_physics_predictions()

func get_physics_position(id: String) -> Vector3:
	if not physics_objects.has(id):
		return Vector3.ZERO
	var obj: Dictionary = physics_objects[id]
	if obj.movement == null or not scheduler:
		return obj.position
	var mv: Dictionary = obj.movement
	if mv.duration <= 0.0:
		return mv.path[mv.path.size() - 1]
	var t := clampf((scheduler.get_current_tick() - mv.start_tick) / mv.duration, 0.0, 1.0)
	var pos := _interpolate_path(mv.path, mv.cum_dist, t)
	if obj.has("throw") and obj.throw != null:
		var tw: Dictionary = obj.throw
		var dt: float = scheduler.get_current_tick() - tw.start_tick
		pos.y = tw.start_y + tw.vy * dt - 0.5 * PENDULUM_GRAVITY * dt * dt
		if pos.y < tw.ground_y:
			pos.y = tw.ground_y
	return pos

func is_physics_moving(id: String) -> bool:
	if not physics_objects.has(id):
		return false
	return physics_objects[id].movement != null

func is_physics_airborne(id: String) -> bool:
	if not physics_objects.has(id):
		return false
	var obj: Dictionary = physics_objects[id]
	return obj.has("throw") and obj.throw != null

func _get_physics_segments(id: String) -> Array[Dictionary]:
	var obj: Dictionary = physics_objects[id]
	if obj.movement == null:
		var pos: Vector3 = obj.position
		return [{"start_tick": 0.0, "end_tick": 1e12, "start_pos": Vector3(pos.x, 0, pos.z), "velocity": Vector3.ZERO}]
	var mv: Dictionary = obj.movement
	var segments: Array[Dictionary] = []
	for i in range(1, mv.path.size()):
		var seg_start_tick: float = mv.start_tick + (mv.cum_dist[i - 1] / mv.total_distance) * mv.duration
		var seg_end_tick: float = mv.start_tick + (mv.cum_dist[i] / mv.total_distance) * mv.duration
		var dir := Vector3(mv.path[i].x - mv.path[i - 1].x, 0, mv.path[i].z - mv.path[i - 1].z)
		var seg_len := dir.length()
		var speed: float = mv.total_distance / mv.duration if mv.duration > 0 else 0.0
		var vel: Vector3 = dir.normalized() * speed if seg_len > 0.001 else Vector3.ZERO
		segments.append({
			"start_tick": seg_start_tick,
			"end_tick": seg_end_tick,
			"start_pos": Vector3(mv.path[i - 1].x, 0, mv.path[i - 1].z),
			"velocity": vel,
		})
	return segments

func _get_velocity_at_tick(id: String, tick: float) -> Vector3:
	var segs: Array[Dictionary]
	if characters.has(id):
		segs = _get_movement_segments(id)
	elif physics_objects.has(id):
		segs = _get_physics_segments(id)
	else:
		return Vector3.ZERO
	for seg in segs:
		if tick >= seg.start_tick and tick < seg.end_tick:
			return seg.velocity
	return Vector3.ZERO

# --- Physics Collision Prediction ---

func _recompute_physics_predictions() -> void:
	if not scheduler:
		return
	scheduler.cancel_tag("physics_predict")
	var now := scheduler.get_current_tick()

	# Character vs PhysicsObject
	for char_id in characters:
		for obj_id in physics_objects:
			var obj: Dictionary = physics_objects[obj_id]
			var collision_range: float = PHYSICS_COLLISION_RADIUS + obj.radius
			var segs_c := _get_movement_segments(char_id)
			var segs_o := _get_physics_segments(obj_id)
			var t := _predict_collision_time(segs_c, segs_o, collision_range, now)
			# Skip collisions at current tick (already being resolved)
			if t >= 0.0 and t > now + 0.01:
				var cid: String = char_id
				var oid: String = obj_id
				scheduler.schedule_at(t, func(): _on_physics_collision_event(oid, cid), "physics_predict")

	# PhysicsObject vs PhysicsObject
	var obj_ids := physics_objects.keys()
	for i in range(obj_ids.size()):
		for j in range(i + 1, obj_ids.size()):
			var id_a: String = obj_ids[i]
			var id_b: String = obj_ids[j]
			var collision_range: float = physics_objects[id_a].radius + physics_objects[id_b].radius
			var segs_a := _get_physics_segments(id_a)
			var segs_b := _get_physics_segments(id_b)
			var t := _predict_collision_time(segs_a, segs_b, collision_range, now)
			if t >= 0.0 and t > now + 0.01:
				var a := id_a
				var b := id_b
				scheduler.schedule_at(t, func(): _on_physics_obj_collision(a, b), "physics_predict")

func _predict_collision_time(segs_a: Array[Dictionary], segs_b: Array[Dictionary], collision_range: float, now: float) -> float:
	var earliest := -1.0
	for seg_a in segs_a:
		for seg_b in segs_b:
			var t0: float = maxf(seg_a.start_tick, seg_b.start_tick)
			var t1: float = minf(seg_a.end_tick, seg_b.end_tick)
			if t0 >= t1:
				continue
			if t0 < now:
				t0 = now
			if t0 >= t1:
				continue
			var pos_a: Vector3 = seg_a.start_pos + (t0 - seg_a.start_tick) * seg_a.velocity
			var pos_b: Vector3 = seg_b.start_pos + (t0 - seg_b.start_tick) * seg_b.velocity
			var tau := _solve_quadratic_detection(pos_a, seg_a.velocity, pos_b, seg_b.velocity, collision_range, t1 - t0)
			if tau >= 0.0:
				var abs_t := t0 + tau
				if earliest < 0.0 or abs_t < earliest:
					earliest = abs_t
	return earliest

# --- Physics Collision Resolution ---

func _on_physics_collision_event(obj_id: String, collider_id: String) -> void:
	if not physics_objects.has(obj_id) or not characters.has(collider_id):
		return
	var obj: Dictionary = physics_objects[obj_id]

	# Airborne object hitting a character: emit signal and land, don't self-push
	if obj.has("throw") and obj.throw != null:
		var obj_vel := _get_velocity_at_tick(obj_id, scheduler.get_current_tick())
		physics_collision.emit(obj_id, collider_id, obj_vel)
		_on_throw_landing(obj_id)
		return

	if not obj.pushable:
		return

	var collider_pos := get_position(collider_id)
	var collider_vel := _get_velocity_at_tick(collider_id, scheduler.get_current_tick())

	var obj_pos := get_physics_position(obj_id)
	var obj_vel := _get_velocity_at_tick(obj_id, scheduler.get_current_tick())

	_resolve_physics_impulse(obj_id, obj_pos, obj_vel, collider_pos, collider_vel, obj)
	physics_collision.emit(obj_id, collider_id, Vector3.ZERO)

func _on_physics_obj_collision(id_a: String, id_b: String) -> void:
	if not physics_objects.has(id_a) or not physics_objects.has(id_b):
		return
	var obj_a: Dictionary = physics_objects[id_a]
	var obj_b: Dictionary = physics_objects[id_b]
	var pos_a := get_physics_position(id_a)
	var pos_b := get_physics_position(id_b)
	var vel_a := _get_velocity_at_tick(id_a, scheduler.get_current_tick())
	var vel_b := _get_velocity_at_tick(id_b, scheduler.get_current_tick())

	if obj_b.pushable:
		_resolve_physics_impulse(id_b, pos_b, vel_b, pos_a, vel_a, obj_b)
	if obj_a.pushable:
		_resolve_physics_impulse(id_a, pos_a, vel_a, pos_b, vel_b, obj_a)

func _resolve_physics_impulse(obj_id: String, obj_pos: Vector3, obj_vel: Vector3, collider_pos: Vector3, collider_vel: Vector3, obj: Dictionary) -> void:
	var push_dir := Vector3(obj_pos.x - collider_pos.x, 0, obj_pos.z - collider_pos.z)
	if push_dir.length_squared() < 0.001:
		push_dir = Vector3(1, 0, 0)
	push_dir = push_dir.normalized()

	var rel_vel := collider_vel - obj_vel
	var impact_speed := maxf(0.0, rel_vel.dot(push_dir))
	if impact_speed < 0.01:
		return

	var mass_ratio: float = 1.0 / obj.mass
	var impulse_speed: float = impact_speed * mass_ratio * PHYSICS_RESTITUTION

	var slide_distance: float = (impulse_speed * impulse_speed) / (2.0 * obj.friction * PHYSICS_DECELERATION)
	if slide_distance < 0.05:
		return

	var slide_target: Vector3 = obj_pos + push_dir * slide_distance

	# Temporarily remove own blocker so trace doesn't collide with self
	var own_cell: Vector2i = obj.grid_cell
	if grid:
		grid.remove_dynamic_blocker(own_cell)
	slide_target = _trace_slide_against_walls(obj_pos, slide_target)
	if grid:
		grid.add_dynamic_blocker(own_cell, obj_id)

	slide_distance = Vector3(slide_target.x - obj_pos.x, 0, slide_target.z - obj_pos.z).length()
	if slide_distance < 0.05:
		return

	_apply_physics_movement(obj_id, obj_pos, slide_target, impulse_speed)

func _trace_slide_against_walls(from: Vector3, to: Vector3) -> Vector3:
	if not grid:
		return to
	var dir := Vector3(to.x - from.x, 0, to.z - from.z)
	var dist := dir.length()
	if dist < 0.01:
		return from
	var step := dir.normalized() * grid.cell_size * 0.5
	var steps := int(dist / (grid.cell_size * 0.5)) + 1
	var pos := from
	for i in range(steps):
		var next := pos + step
		var cell := grid.world_to_grid(next)
		if not grid.is_walkable(cell.x, cell.y):
			return pos
		pos = next
	return to

func _apply_physics_movement(obj_id: String, from: Vector3, to: Vector3, initial_speed: float) -> void:
	var obj: Dictionary = physics_objects[obj_id]

	# Cancel existing movement
	if obj.movement != null and scheduler:
		scheduler.cancel(obj.movement.handle)
		if grid:
			grid.remove_dynamic_blocker(obj.grid_cell)

	var slide_dist := Vector3(to.x - from.x, 0, to.z - from.z).length()
	if slide_dist < 0.01:
		obj.position = from
		obj.movement = null
		if grid:
			obj.grid_cell = grid.world_to_grid(from)
			grid.add_dynamic_blocker(obj.grid_cell, obj_id)
		return

	# Average speed during deceleration = initial_speed / 2
	var avg_speed := initial_speed * 0.5
	var duration := slide_dist / maxf(avg_speed, 0.1)
	var start_tick := scheduler.get_current_tick()
	var path: Array[Vector3] = [from, to]
	var cum_dist := _compute_cum_dist(path)

	var oid := obj_id
	var handle := scheduler.schedule_at(
		start_tick + duration,
		func(): _on_physics_arrival(oid),
		"physics_move_" + obj_id
	)

	obj.movement = {
		"path": path,
		"cum_dist": cum_dist,
		"total_distance": slide_dist,
		"start_tick": start_tick,
		"duration": duration,
		"handle": handle,
	}

	# Remove grid blocker while moving
	if grid:
		grid.remove_dynamic_blocker(obj.grid_cell)

	_recompute_physics_predictions()

func _on_physics_arrival(obj_id: String) -> void:
	if not physics_objects.has(obj_id):
		return
	var obj: Dictionary = physics_objects[obj_id]
	if obj.movement == null:
		return
	var dest: Vector3 = obj.movement.path[obj.movement.path.size() - 1]
	obj.position = dest
	obj.movement = null
	if grid:
		obj.grid_cell = grid.world_to_grid(dest)
		grid.add_dynamic_blocker(obj.grid_cell, obj_id)
	_recompute_physics_predictions()

# --- Area Impulse ---

func apply_area_impulse(center: Vector3, radius: float, force: float) -> void:
	_emit(GameEvent.KIND_APPLY_AREA_IMPULSE, {
		"center": GameEvent.v3_to_arr(center),
		"radius": radius,
		"force": force,
	})
	for obj_id in physics_objects:
		var obj: Dictionary = physics_objects[obj_id]
		if not obj.pushable:
			continue
		var pos := get_physics_position(obj_id)
		var dx := pos.x - center.x
		var dz := pos.z - center.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist < radius and dist > 0.01:
			var dir := Vector3(dx, 0, dz).normalized()
			var falloff := 1.0 - (dist / radius)
			var impulse_speed: float = force * falloff / obj.mass
			var slide_distance: float = (impulse_speed * impulse_speed) / (2.0 * obj.friction * PHYSICS_DECELERATION)
			if slide_distance < 0.05:
				continue
			var slide_target: Vector3 = pos + dir * slide_distance
			if grid:
				grid.remove_dynamic_blocker(obj.grid_cell)
			slide_target = _trace_slide_against_walls(pos, slide_target)
			if grid:
				grid.add_dynamic_blocker(obj.grid_cell, obj_id)
			slide_distance = Vector3(slide_target.x - pos.x, 0, slide_target.z - pos.z).length()
			if slide_distance >= 0.05:
				_apply_physics_movement(obj_id, pos, slide_target, impulse_speed)
				physics_collision.emit(obj_id, "", dir * impulse_speed)

# --- Throw Physics ---

func throw_physics_object(obj_id: String, velocity: Vector3, start_pos: Vector3 = Vector3.INF) -> void:
	_emit(GameEvent.KIND_THROW_PHYSICS_OBJECT, {
		"obj_id": obj_id,
		"velocity": GameEvent.v3_to_arr(velocity),
		"start_pos": GameEvent.v3_to_arr(start_pos),
	})
	if not physics_objects.has(obj_id) or not scheduler:
		return
	var obj: Dictionary = physics_objects[obj_id]
	var from: Vector3 = start_pos if start_pos != Vector3.INF else get_physics_position(obj_id)
	var ground_y := 0.0

	# Cancel existing movement
	if obj.movement != null:
		scheduler.cancel(obj.movement.handle)
		obj.movement = null
	if grid:
		grid.remove_dynamic_blocker(obj.grid_cell)

	# Compute flight time from vertical parabola: y = y0 + vy*t - 0.5*g*t²
	# Solve for y = ground_y: 0.5*g*t² - vy*t - (y0 - ground_y) = 0
	var y0: float = from.y
	var vy: float = velocity.y
	var flight_time: float
	if y0 <= ground_y and vy <= 0:
		flight_time = 0.0
	else:
		var a_coeff := 0.5 * PENDULUM_GRAVITY
		var b_coeff := -vy
		var c_coeff := -(y0 - ground_y)
		var disc := b_coeff * b_coeff - 4.0 * a_coeff * c_coeff
		if disc < 0:
			flight_time = 0.0
		else:
			var sqrt_disc := sqrt(disc)
			var t1: float = (-b_coeff + sqrt_disc) / (2.0 * a_coeff)
			var t2: float = (-b_coeff - sqrt_disc) / (2.0 * a_coeff)
			flight_time = maxf(t1, t2)
			if flight_time < 0.01:
				flight_time = 0.0

	if flight_time < 0.01:
		obj.position = Vector3(from.x, ground_y, from.z)
		obj.throw = null
		if grid:
			obj.grid_cell = grid.world_to_grid(obj.position)
			grid.add_dynamic_blocker(obj.grid_cell, obj_id)
		return

	# XZ: linear flight path
	var xz_vel := Vector3(velocity.x, 0, velocity.z)
	var landing_pos := Vector3(from.x + xz_vel.x * flight_time, ground_y, from.z + xz_vel.z * flight_time)

	# Trace XZ path against walls
	if grid:
		var traced := _trace_slide_against_walls(Vector3(from.x, 0, from.z), Vector3(landing_pos.x, 0, landing_pos.z))
		var traced_dist := Vector3(traced.x - from.x, 0, traced.z - from.z).length()
		var full_dist := Vector3(landing_pos.x - from.x, 0, landing_pos.z - from.z).length()
		if traced_dist < full_dist and full_dist > 0.01:
			var frac := traced_dist / full_dist
			flight_time *= frac
			landing_pos = Vector3(traced.x, ground_y, traced.z)

	# Set up throw parabola for Y
	var now := scheduler.get_current_tick()
	obj.throw = {
		"start_tick": now,
		"start_y": y0,
		"vy": vy,
		"ground_y": ground_y,
		"landing_tick": now + flight_time,
	}

	# Set up XZ movement (reuses existing path system)
	var xz_speed := xz_vel.length()
	var xz_from := Vector3(from.x, ground_y, from.z)
	var xz_to := Vector3(landing_pos.x, ground_y, landing_pos.z)
	var path: Array[Vector3] = [xz_from, xz_to]
	var cum_dist := _compute_cum_dist(path)
	var xz_dist: float = cum_dist[cum_dist.size() - 1]

	var oid := obj_id
	var handle := scheduler.schedule_at(
		now + flight_time,
		func(): _on_throw_landing(oid),
		"throw_" + obj_id
	)

	obj.movement = {
		"path": path,
		"cum_dist": cum_dist,
		"total_distance": xz_dist if xz_dist > 0.001 else 0.001,
		"start_tick": now,
		"duration": flight_time,
		"handle": handle,
	}

	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

## Throw a physics object to a target XZ location along an arc. Picks a launch
## velocity from a flight time (scaled with distance unless `arc_time` is given),
## then defers to throw_physics_object — which traces walls and drives the
## parabola off the scheduler tick, so it stays replay-deterministic. Returns
## false if the object isn't registered.
func throw_physics_object_to(obj_id: String, target: Vector3, arc_time: float = 0.0) -> bool:
	if not physics_objects.has(obj_id) or not scheduler:
		return false
	var from := get_physics_position(obj_id)
	var dx := target.x - from.x
	var dz := target.z - from.z
	var horizontal := Vector2(dx, dz).length()
	var t := arc_time
	if t <= 0.0:
		t = clampf(horizontal / 6.0, 0.45, 2.5)
	# y(t) = from.y + vy*t - 0.5*g*t² = target.y  → solve for vy.
	var vy := (target.y - from.y + 0.5 * PENDULUM_GRAVITY * t * t) / t
	throw_physics_object(obj_id, Vector3(dx / t, vy, dz / t), from)
	return true

func _on_throw_landing(obj_id: String) -> void:
	if not physics_objects.has(obj_id):
		return
	var obj: Dictionary = physics_objects[obj_id]
	var landing_pos := get_physics_position(obj_id)
	landing_pos.y = 0.0

	# Get XZ velocity at landing for post-bounce slide
	var xz_vel := _get_velocity_at_tick(obj_id, scheduler.get_current_tick())
	var xz_speed := xz_vel.length()

	# Clear throw and movement
	obj.throw = null
	obj.movement = null
	obj.position = landing_pos
	if grid:
		obj.grid_cell = grid.world_to_grid(landing_pos)

	# Convert remaining XZ velocity into a ground slide (reduced by bounce loss)
	var bounce_factor := 0.5
	var slide_speed := xz_speed * bounce_factor
	if slide_speed > 0.1 and obj.pushable:
		var slide_dir := xz_vel.normalized()
		var slide_distance: float = (slide_speed * slide_speed) / (2.0 * obj.friction * PHYSICS_DECELERATION)
		if slide_distance > 0.05:
			var slide_target: Vector3 = landing_pos + slide_dir * slide_distance
			var own_cell: Vector2i = obj.grid_cell
			if grid:
				grid.remove_dynamic_blocker(own_cell)
			slide_target = _trace_slide_against_walls(landing_pos, slide_target)
			if grid:
				grid.add_dynamic_blocker(own_cell, obj_id)
			slide_distance = Vector3(slide_target.x - landing_pos.x, 0, slide_target.z - landing_pos.z).length()
			if slide_distance >= 0.05:
				_apply_physics_movement(obj_id, landing_pos, slide_target, slide_speed)
				physics_collision.emit(obj_id, "", xz_vel * bounce_factor)
				return

	# No slide; settle in place.
	if grid:
		grid.add_dynamic_blocker(obj.grid_cell, obj_id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func get_throw_height(id: String) -> float:
	if not physics_objects.has(id):
		return 0.0
	var obj: Dictionary = physics_objects[id]
	if not obj.has("throw") or obj.throw == null or not scheduler:
		return obj.position.y
	var tw: Dictionary = obj.throw
	var dt: float = scheduler.get_current_tick() - tw.start_tick
	var y: float = tw.start_y + tw.vy * dt - 0.5 * PENDULUM_GRAVITY * dt * dt
	return maxf(y, tw.ground_y)

func get_throw_peak_height(id: String) -> float:
	if not physics_objects.has(id):
		return 0.0
	var obj: Dictionary = physics_objects[id]
	if not obj.has("throw") or obj.throw == null:
		return 0.0
	var tw: Dictionary = obj.throw
	var vy: float = tw.vy
	if vy <= 0:
		return tw.start_y
	var t_peak := vy / PENDULUM_GRAVITY
	return tw.start_y + vy * t_peak - 0.5 * PENDULUM_GRAVITY * t_peak * t_peak

# --- Pendulums ---

const PENDULUM_GRAVITY := 9.8
const PENDULUM_SEGMENTS_PER_PERIOD := 12

func register_pendulum(id: String, anchor: Vector3, length: float, amplitude: float, swing_axis: Vector3 = Vector3.FORWARD, bob_radius: float = 0.4, phase: float = 0.0, damping: float = 0.0) -> void:
	_emit(GameEvent.KIND_REGISTER_PENDULUM, {
		"id": id,
		"anchor": GameEvent.v3_to_arr(anchor),
		"length": length,
		"amplitude": amplitude,
		"swing_axis": GameEvent.v3_to_arr(swing_axis),
		"bob_radius": bob_radius,
		"phase": phase,
		"damping": damping,
	})
	var start_tick := scheduler.get_current_tick() if scheduler else 0.0
	pendulums[id] = {
		"anchor": anchor,
		"length": length,
		"amplitude": amplitude,
		"phase": phase,
		"swing_axis": swing_axis.normalized(),
		"bob_radius": bob_radius,
		"damping": damping,
		"start_tick": start_tick,
	}
	_recompute_pendulum_predictions()

func unregister_pendulum(id: String) -> void:
	_emit(GameEvent.KIND_UNREGISTER_PENDULUM, {"id": id})
	pendulums.erase(id)
	if scheduler:
		scheduler.cancel_tag("pendulum_predict")

func get_pendulum_omega(id: String) -> float:
	if not pendulums.has(id):
		return 0.0
	var p: Dictionary = pendulums[id]
	return sqrt(PENDULUM_GRAVITY / p.length)

func get_pendulum_period(id: String) -> float:
	var omega := get_pendulum_omega(id)
	return TAU / omega if omega > 0.001 else 1.0

func get_pendulum_angle(id: String, tick: float = -1.0) -> float:
	if not pendulums.has(id):
		return 0.0
	var p: Dictionary = pendulums[id]
	if tick < 0.0:
		tick = scheduler.get_current_tick() if scheduler else 0.0
	var dt: float = tick - p.start_tick
	var omega := sqrt(PENDULUM_GRAVITY / p.length)
	var amp: float = p.amplitude
	if p.damping > 0.0 and dt > 0.0:
		amp *= exp(-p.damping * dt)
	return amp * cos(omega * dt + p.phase)

func get_pendulum_position(id: String, tick: float = -1.0) -> Vector3:
	if not pendulums.has(id):
		return Vector3.ZERO
	var p: Dictionary = pendulums[id]
	var theta := get_pendulum_angle(id, tick)
	var swing_dir := Vector3(-p.swing_axis.z, 0, p.swing_axis.x)
	var bob_offset: Vector3 = swing_dir * sin(theta) * p.length + Vector3(0, -cos(theta) * p.length, 0)
	return p.anchor + bob_offset

func get_pendulum_bob_velocity(id: String, tick: float = -1.0) -> Vector3:
	if not pendulums.has(id):
		return Vector3.ZERO
	var p: Dictionary = pendulums[id]
	if tick < 0.0:
		tick = scheduler.get_current_tick() if scheduler else 0.0
	var dt: float = tick - p.start_tick
	var omega := sqrt(PENDULUM_GRAVITY / p.length)
	var amp: float = p.amplitude
	if p.damping > 0.0 and dt > 0.0:
		amp *= exp(-p.damping * dt)
	var theta := amp * cos(omega * dt + p.phase)
	var dtheta := -amp * omega * sin(omega * dt + p.phase)
	var swing_dir := Vector3(-p.swing_axis.z, 0, p.swing_axis.x)
	var vx: Vector3 = swing_dir * cos(theta) * p.length * dtheta
	var vy := Vector3(0, sin(theta) * p.length * dtheta, 0)
	return vx + vy

# Decompose pendulum motion into linear segments for collision prediction
func _get_pendulum_segments(id: String, duration: float = -1.0) -> Array[Dictionary]:
	if not pendulums.has(id) or not scheduler:
		return []
	var p: Dictionary = pendulums[id]
	var omega := sqrt(PENDULUM_GRAVITY / p.length)
	var period := TAU / omega if omega > 0.001 else 1.0

	if duration < 0.0:
		# Look ahead 2 periods (or until fully damped)
		duration = period * 2.0
		if p.damping > 0.0:
			# Time until amplitude drops below 0.01 radians
			var decay_time := -log(0.01 / maxf(p.amplitude, 0.01)) / maxf(p.damping, 0.001)
			duration = minf(duration, decay_time)

	var now := scheduler.get_current_tick()
	var step := period / PENDULUM_SEGMENTS_PER_PERIOD
	var steps := int(duration / step) + 1
	var segments: Array[Dictionary] = []

	for i in range(steps):
		var t0 := now + i * step
		var t1 := now + (i + 1) * step
		var pos0 := get_pendulum_position(id, t0)
		var pos1 := get_pendulum_position(id, t1)
		var dt := t1 - t0
		var vel := Vector3((pos1.x - pos0.x) / dt, 0, (pos1.z - pos0.z) / dt) if dt > 0.001 else Vector3.ZERO
		segments.append({
			"start_tick": t0,
			"end_tick": t1,
			"start_pos": Vector3(pos0.x, 0, pos0.z),
			"velocity": vel,
		})

	return segments

func _recompute_pendulum_predictions() -> void:
	if not scheduler:
		return
	scheduler.cancel_tag("pendulum_predict")
	if pendulums.is_empty():
		return
	var now := scheduler.get_current_tick()

	for pend_id in pendulums:
		var p: Dictionary = pendulums[pend_id]
		var pend_segs := _get_pendulum_segments(pend_id)

		# Pendulum vs Characters
		for char_id in characters:
			var collision_range: float = PHYSICS_COLLISION_RADIUS + p.bob_radius
			var char_segs := _get_movement_segments(char_id)
			var t := _predict_collision_time(pend_segs, char_segs, collision_range, now)
			if t >= 0.0 and t > now + 0.01:
				var pid: String = pend_id
				var cid: String = char_id
				scheduler.schedule_at(t, func(): _on_pendulum_hit_character(pid, cid), "pendulum_predict")

		# Pendulum vs Physics Objects
		for obj_id in physics_objects:
			var obj: Dictionary = physics_objects[obj_id]
			var collision_range: float = obj.radius + p.bob_radius
			var obj_segs := _get_physics_segments(obj_id)
			var t := _predict_collision_time(pend_segs, obj_segs, collision_range, now)
			if t >= 0.0 and t > now + 0.01:
				var pid: String = pend_id
				var oid: String = obj_id
				scheduler.schedule_at(t, func(): _on_pendulum_hit_physics(pid, oid), "pendulum_predict")

func _on_pendulum_hit_character(pendulum_id: String, char_id: String) -> void:
	if not pendulums.has(pendulum_id) or not characters.has(char_id):
		return
	if is_dodging(char_id):
		return
	var bob_vel := get_pendulum_bob_velocity(pendulum_id)
	pendulum_hit.emit(pendulum_id, char_id, bob_vel)

func _on_pendulum_hit_physics(pendulum_id: String, obj_id: String) -> void:
	if not pendulums.has(pendulum_id) or not physics_objects.has(obj_id):
		return
	var obj: Dictionary = physics_objects[obj_id]
	if not obj.pushable:
		return
	var bob_vel := get_pendulum_bob_velocity(pendulum_id)
	var obj_pos := get_physics_position(obj_id)
	var bob_pos := get_pendulum_position(pendulum_id)
	_resolve_physics_impulse(obj_id, obj_pos, Vector3.ZERO, bob_pos, bob_vel, obj)
	pendulum_hit.emit(pendulum_id, obj_id, bob_vel)

# --- Replay ---
#
# Replay re-issues logged inputs at their original ticks.

## Build a fresh GameState by replaying a log.
## ability_handlers restores queued ability behavior. re_record_into checks determinism.
static func replay(log: EventLog, world_grid: GridWorld, ability_handlers: Dictionary = {}, re_record_into: EventLog = null) -> GameState:
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = world_grid
	gs.scheduler = sched
	gs._recording = re_record_into != null
	gs.event_log = re_record_into
	gs.set_base_seed(log.base_seed)
	for id in ability_handlers:
		gs.register_ability_handler(StringName(id), ability_handlers[id])

	var prev_tick := 0.0
	for event in log.events:
		var tick: float = float(event["tick"])
		if tick > prev_tick:
			sched.advance_ticks(tick - prev_tick)
			prev_tick = tick
		gs._dispatch(StringName(event["kind"]), event["payload"])

	# Finish scheduler work that was pending when the log was saved.
	if log.recorded_until > prev_tick:
		sched.advance_ticks(log.recorded_until - prev_tick)

	gs._recording = true
	return gs

func _dispatch(kind: StringName, payload: Dictionary) -> void:
	match kind:
		GameEvent.KIND_REGISTER_CHARACTER:
			register_character(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["pos"]),
				float(payload.get("speed", 3.0)),
				payload.get("stats", {})
			)
		GameEvent.KIND_UNREGISTER_CHARACTER:
			unregister_character(String(payload["id"]))
		GameEvent.KIND_MOVE_TO_CELL:
			command_move_to_cell(String(payload["id"]), GameEvent.arr_to_v2i(payload["cell"]))
		GameEvent.KIND_MOVE_TO_POS:
			command_move_to_pos(String(payload["id"]), GameEvent.arr_to_v3(payload["pos"]))
		GameEvent.KIND_WALK_PATH:
			command_walk_path(String(payload["id"]), GameEvent.arr_to_path(payload["path"]))
		GameEvent.KIND_STOP:
			command_stop(String(payload["id"]))
		GameEvent.KIND_CHANGE_SPEED:
			change_move_speed(String(payload["id"]), float(payload["speed"]))
		GameEvent.KIND_SET_LEVEL:
			set_character_level(String(payload["id"]), int(payload["level"]))
		GameEvent.KIND_MOVE_CROSS_LEVEL:
			command_move_cross_level(
				String(payload["id"]),
				GameEvent.arr_to_v2i(payload["cell"]),
				int(payload["level"])
			)
		GameEvent.KIND_SPAWN_ITEM:
			spawn_item(
				String(payload["type"]),
				GameEvent.arr_to_v3(payload["pos"]),
				payload.get("properties", {})
			)
		GameEvent.KIND_REMOVE_ITEM:
			remove_item(String(payload["item_id"]))
		GameEvent.KIND_PICK_UP_ITEM:
			pick_up_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_DROP_ITEM:
			drop_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_TRANSFER_ITEM:
			transfer_item(
				String(payload["from_id"]),
				String(payload["to_id"]),
				String(payload["item_id"])
			)
		GameEvent.KIND_ENDOCYTOSE_ITEM:
			endocytose_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_CANCEL_ENDOCYTOSIS:
			cancel_endocytosis(String(payload["char_id"]))
		GameEvent.KIND_EXOCYTOSE_ITEM:
			exocytose_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_REGISTER_PHYSICS_OBJECT:
			register_physics_object(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["pos"]),
				float(payload.get("radius", 0.5)),
				float(payload.get("mass", 2.0)),
				float(payload.get("friction", 0.6)),
				bool(payload.get("pushable", true))
			)
		GameEvent.KIND_UNREGISTER_PHYSICS_OBJECT:
			unregister_physics_object(String(payload["id"]))
		GameEvent.KIND_THROW_PHYSICS_OBJECT:
			throw_physics_object(
				String(payload["obj_id"]),
				GameEvent.arr_to_v3(payload["velocity"]),
				GameEvent.arr_to_v3(payload["start_pos"])
			)
		GameEvent.KIND_APPLY_AREA_IMPULSE:
			apply_area_impulse(
				GameEvent.arr_to_v3(payload["center"]),
				float(payload["radius"]),
				float(payload["force"])
			)
		GameEvent.KIND_REGISTER_PENDULUM:
			register_pendulum(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["anchor"]),
				float(payload["length"]),
				float(payload["amplitude"]),
				GameEvent.arr_to_v3(payload.get("swing_axis", [0.0, 0.0, -1.0])),
				float(payload.get("bob_radius", 0.4)),
				float(payload.get("phase", 0.0)),
				float(payload.get("damping", 0.0))
			)
		GameEvent.KIND_UNREGISTER_PENDULUM:
			unregister_pendulum(String(payload["id"]))
		GameEvent.KIND_DODGE_ROLL:
			dodge_roll(String(payload["char_id"]), GameEvent.arr_to_v3(payload["direction"]))
		GameEvent.KIND_QUEUE_ABILITY:
			var ab_id := String(payload["ability"])
			var handler: Callable = _ability_handlers.get(StringName(ab_id), Callable())
			if not handler.is_valid():
				handler = func(): pass
			queue_ability(
				String(payload["char_id"]),
				ab_id,
				GameEvent.arr_to_v3(payload["target_pos"]),
				float(payload["range"]),
				handler
			)
		GameEvent.KIND_CANCEL_QUEUED_ABILITY:
			cancel_queued_ability(String(payload["char_id"]))
		GameEvent.KIND_DOWN_CHARACTER:
			down_character(String(payload["char_id"]))
		GameEvent.KIND_RESTORE_CHARACTER:
			restore_character(String(payload["char_id"]))
		GameEvent.KIND_DIE_SCRIPTED:
			die_scripted(String(payload["char_id"]))
		GameEvent.KIND_SET_PARTY:
			set_party(payload.get("members", []))
		GameEvent.KIND_PARTY_MOVE_TO_CELL:
			party_move_to_cell(GameEvent.arr_to_v2i(payload["cell"]))
		GameEvent.KIND_PARTY_MOVE_TO_POS:
			party_move_to_pos(GameEvent.arr_to_v3(payload["pos"]))
		GameEvent.KIND_START_SPLIT:
			start_split(payload.get("members", []))
		GameEvent.KIND_END_SPLIT:
			end_split()
		GameEvent.KIND_REGISTER_INTERACTABLE:
			register_interactable(payload)
		GameEvent.KIND_UNREGISTER_INTERACTABLE:
			unregister_interactable(String(payload["id"]))
		GameEvent.KIND_TRIGGER_INTERACTABLE:
			trigger_interactable(String(payload["id"]), String(payload.get("character", "")))
		GameEvent.KIND_SET_INTERACTABLE_ENABLED:
			set_interactable_enabled(String(payload["id"]), bool(payload["enabled"]))
		GameEvent.KIND_RESET_INTERACTABLE:
			reset_interactable(String(payload["id"]))
		_:
			push_warning("GameState._dispatch: unknown event kind %s" % kind)

# --- Party cohesion ---
#
# Party move commands address all non-split party members.

## Ordered party roster.
# Lateral spacing between members on a gridless party move (no cell spread available).
const _PARTY_GRIDLESS_SPACING := 1.0

var party: Array[String] = []
## Scripted split members ignored by party_move.
var _split_members: Array[String] = []

func set_party(members: Array) -> void:
	_emit(GameEvent.KIND_SET_PARTY, {"members": members.duplicate()})
	party.clear()
	for m in members:
		party.append(String(m))

func get_party() -> Array[String]:
	return party.duplicate()

func get_split_members() -> Array[String]:
	return _split_members.duplicate()

func is_split_active() -> bool:
	return not _split_members.is_empty()

## Party members currently controlled by party_move.
func _main_group() -> Array[String]:
	if _split_members.is_empty():
		return party.duplicate()
	var result: Array[String] = []
	for m in party:
		if not (m in _split_members):
			result.append(m)
	return result

func party_move_to_cell(cell: Vector2i) -> void:
	_emit(GameEvent.KIND_PARTY_MOVE_TO_CELL, {"cell": GameEvent.v2i_to_arr(cell)})
	var members := _main_group()
	for char_id in members:
		_cross_level_plan.erase(char_id)
	if grid:
		var assigned := _assign_party_cells(members, cell)
		for char_id in members:
			_do_move_to_cell(char_id, assigned[char_id])
	else:
		for char_id in members:
			_do_move_to_cell(char_id, cell)

func party_move_to_pos(pos: Vector3) -> void:
	_emit(GameEvent.KIND_PARTY_MOVE_TO_POS, {"pos": GameEvent.v3_to_arr(pos)})
	var members := _main_group()
	for char_id in members:
		_cross_level_plan.erase(char_id)
	if grid:
		# Snap to the grid so the party spreads onto distinct cells around the
		# clicked point and moves cooperatively (no stacking, no overlap).
		var assigned := _assign_party_cells(members, grid.world_to_grid(pos))
		for char_id in members:
			_do_move_to_cell(char_id, assigned[char_id])
	else:
		# No grid (e.g. the elevator): cooperative cell spread isn't available, so fan
		# members out along Z around the target by party order — a pure function of the
		# index, so it stays deterministic / replay-safe — rather than stacking them.
		var count := members.size()
		for i in range(count):
			var lateral := (float(i) - float(count - 1) / 2.0) * _PARTY_GRIDLESS_SPACING
			_do_move_to_pos(members[i], pos + Vector3(0.0, 0.0, lateral))

## Give each party member a distinct, walkable destination cell around target so
## a single party move never stacks everyone on one cell. The order of members
## is deterministic (party order), so this replays and fast-forwards identically.
func _assign_party_cells(members: Array, target: Vector2i) -> Dictionary:
	var assigned: Dictionary = {}
	var taken: Dictionary = {}
	for id in members:
		var cell := _nearest_free_cell(target, taken)
		assigned[id] = cell
		taken[cell] = true
	return assigned

## Outward ring search from target for the closest walkable cell not already
## taken by another member. Deterministic tie-break by distance then coordinate.
func _nearest_free_cell(target: Vector2i, taken: Dictionary) -> Vector2i:
	if grid.is_in_bounds(target.x, target.y) and grid.is_walkable(target.x, target.y) and not taken.has(target):
		return target
	# Search the whole reachable extent (capped) so a large party on a big map
	# never falsely stacks just because a free cell sits past a fixed radius.
	var max_radius := mini(maxi(grid.width, grid.height), 24)
	for radius in range(1, max_radius + 1):
		var best := Vector2i.ZERO
		var found := false
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var c := target + Vector2i(dx, dz)
				if taken.has(c) or not grid.is_in_bounds(c.x, c.y) or not grid.is_walkable(c.x, c.y):
					continue
				if not found or _ring_closer(c, best, target):
					best = c
					found = true
		if found:
			return best
	# No free cell anywhere in range (fewer walkable cells than members) —
	# stacking on the target is then physically unavoidable.
	return target

func _ring_closer(c: Vector2i, best: Vector2i, target: Vector2i) -> bool:
	var dc := c - target
	var db := best - target
	var dist_c := dc.x * dc.x + dc.y * dc.y
	var dist_b := db.x * db.x + db.y * db.y
	if dist_c != dist_b:
		return dist_c < dist_b
	if c.x != best.x:
		return c.x < best.x
	return c.y < best.y

## Scripted split; not exposed to player input.
func start_split(members: Array) -> void:
	_emit(GameEvent.KIND_START_SPLIT, {"members": members.duplicate()})
	_split_members.clear()
	for m in members:
		var cid := String(m)
		if cid in party:
			_split_members.append(cid)

func end_split() -> void:
	_emit(GameEvent.KIND_END_SPLIT, {})
	_split_members.clear()

# Internal cell move without its own log entry.
func _do_move_to_cell(id: String, cell: Vector2i) -> bool:
	if not characters.has(id) or not grid or not scheduler:
		return false
	if is_endocytosing(id):
		return false
	var current_pos := get_position(id)
	var current_cell := grid.world_to_grid(current_pos)
	var speed: float = characters[id].move_speed
	_cancel_movement(id)
	characters[id].position = current_pos
	return _begin_cooperative_move(id, current_pos, current_cell, cell, speed)

## Plan a cooperative path from current_cell to dest_cell (waiting/detouring to
## avoid other characters' reserved cell-time windows) and start it. Falls back
## to plain A* only when no conflict-free path exists within the search budget,
## so the character still moves (the fallback prioritizes liveness — it may
## briefly overlap another character). Assumes the caller already cancelled any
## prior movement and pinned characters[id].position to current_pos.
func _begin_cooperative_move(id: String, current_pos: Vector3, current_cell: Vector2i, dest_cell: Vector2i, speed: float) -> bool:
	var level := get_character_level(id)  # keep waypoints on the character's current floor
	var plan := _plan_cooperative(current_cell, dest_cell, speed, scheduler.get_current_tick(), id)
	if not plan.is_empty() and not plan.cells.is_empty():
		var built := _build_timed_world_path(current_pos, plan.cells, plan.ticks, speed, level)
		_start_movement(id, built.path, built.ticks)
		return true
	var path := grid.find_path(current_cell, dest_cell, {}, false, {}, {}, level)
	if path.is_empty():
		_reserve_parked(id, current_cell)
		return false
	var full_path: Array[Vector3] = [current_pos]
	full_path.append_array(path)
	_start_movement(id, full_path)
	return true

# --- Narrative state transitions (downed / restored) ---
#
# Downed characters remain present but cannot speak, gate, or actuate.

signal character_downed(char_id: String)
signal character_restored(char_id: String)
## Permanent death signal; currently only scripted.
signal character_died(char_id: String, scripted: bool)

func down_character(char_id: String) -> void:
	_emit(GameEvent.KIND_DOWN_CHARACTER, {"char_id": char_id})
	if not characters.has(char_id):
		return
	var ch: Dictionary = characters[char_id]
	ch.stats["hp"] = 0.0
	ch.stats["stamina"] = 0.0
	ch.stats["narrative_available"] = false
	_do_stop(char_id)
	character_downed.emit(char_id)

func restore_character(char_id: String) -> void:
	_emit(GameEvent.KIND_RESTORE_CHARACTER, {"char_id": char_id})
	if not characters.has(char_id):
		return
	var ch: Dictionary = characters[char_id]
	var stats: Dictionary = ch.stats
	if stats.has("max_hp"):
		stats["hp"] = float(stats["max_hp"])
	if stats.has("max_stamina"):
		stats["stamina"] = float(stats["max_stamina"])
	stats["atp"] = ATP_MAX_PIPS
	stats["narrative_available"] = true
	character_restored.emit(char_id)

func is_narratively_available(char_id: String) -> bool:
	if not characters.has(char_id):
		return false
	return bool(characters[char_id].stats.get("narrative_available", true))

func is_downed(char_id: String) -> bool:
	if not characters.has(char_id):
		return false
	return not bool(characters[char_id].stats.get("narrative_available", true))

## True when every listed party member is downed.
func is_party_downed(members: Array) -> bool:
	if members.is_empty():
		return false
	for char_id in members:
		if not is_downed(String(char_id)):
			return false
	return true

## Permanent, scripted-only removal from the simulation.
func die_scripted(char_id: String) -> void:
	_emit(GameEvent.KIND_DIE_SCRIPTED, {"char_id": char_id})
	if not characters.has(char_id):
		return
	_do_stop(char_id)
	var ch: Dictionary = characters[char_id]
	ch.stats["hp"] = 0.0
	ch.stats["stamina"] = 0.0
	ch.stats["narrative_available"] = false
	ch.stats["dead"] = true
	character_died.emit(char_id, true)

# --- Mechanisms ---
#
# Mechanisms see only Actuator data.

func register_mechanism(m: Mechanism) -> void:
	mechanisms[m.id] = m

func unregister_mechanism(mech_id: StringName) -> void:
	mechanisms.erase(mech_id)

# Build actuator data from current actors, items, and physics objects.
func get_all_actuators() -> Array:
	var result: Array = []
	for char_id in characters:
		var ch: Dictionary = characters[char_id]
		var stats: Dictionary = ch.get("stats", {})
		var w: float = float(stats.get("weight", 1.0))
		var sig: StringName = StringName(str(stats.get("signature", "organic")))
		result.append(Actuator.make(get_position(char_id), w, sig))
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.get("location", "") != "ground":
			continue
		var props: Dictionary = item.get("properties", {})
		var w: float = float(props.get("weight", 0.0))
		var sig: StringName = StringName(str(props.get("signature", item.get("type", ""))))
		result.append(Actuator.make(item.get("position", Vector3.ZERO), w, sig))
	for obj_id in physics_objects:
		var obj: Dictionary = physics_objects[obj_id]
		var w: float = float(obj.get("mass", 0.0))
		var sig: StringName = StringName(str(obj.get("signature", "physics_object")))
		result.append(Actuator.make(get_physics_position(obj_id), w, sig))
	return result

func evaluate_mechanisms() -> void:
	if mechanisms.is_empty():
		return
	var actuators := get_all_actuators()
	for m_id in mechanisms:
		mechanisms[m_id].update(actuators)

# --- Interactables (data layer) ---
#
# The data layer owns interactable state (enabled / triggered / one-shot); the
# scene node is a view bound to an id that handles proximity, click, dwell, and
# visuals. Registration/trigger/enable are event-logged so a replay rebuilds the
# registry and re-fires triggers; dwell timing stays on the scheduler (the log
# records the result at the completion tick), keeping fast-forward invariance.

## Normalize a spec dict into the stored shape (defaults + a Vector3 position).
func _normalize_interactable_spec(spec: Dictionary) -> Dictionary:
	var pos_raw: Variant = spec.get("position", Vector3.ZERO)
	var pos: Vector3 = GameEvent.arr_to_v3(pos_raw) if pos_raw is Array else pos_raw
	return {
		"id": String(spec.get("id", "")),
		"position": pos,
		"requires_hold": bool(spec.get("requires_hold", true)),
		"hold_time": float(spec.get("hold_time", 1.0)),
		"one_shot": bool(spec.get("one_shot", false)),
		"required_character": String(spec.get("required_character", "")),
		"dialogue_key": String(spec.get("dialogue_key", "")),
		"radius": float(spec.get("radius", 2.0)),
		"tutorial_label": String(spec.get("tutorial_label", "")),
		"catalog_id": String(spec.get("catalog_id", "")),
		"enabled": bool(spec.get("enabled", true)),
		"triggered": false,
	}

## Register an interactable spec. id is required and unique within the scene.
func register_interactable(spec: Dictionary) -> void:
	var norm := _normalize_interactable_spec(spec)
	if norm.id == "":
		push_warning("GameState.register_interactable: spec has no id")
		return
	_emit(GameEvent.KIND_REGISTER_INTERACTABLE, {
		"id": norm.id,
		"position": GameEvent.v3_to_arr(norm.position),
		"requires_hold": norm.requires_hold,
		"hold_time": norm.hold_time,
		"one_shot": norm.one_shot,
		"required_character": norm.required_character,
		"dialogue_key": norm.dialogue_key,
		"radius": norm.radius,
		"tutorial_label": norm.tutorial_label,
		"catalog_id": norm.catalog_id,
		"enabled": norm.enabled,
	})
	interactables[norm.id] = norm
	interactable_registered.emit(norm.id)

func unregister_interactable(id: String) -> void:
	if not interactables.has(id):
		return
	_emit(GameEvent.KIND_UNREGISTER_INTERACTABLE, {"id": id})
	interactables.erase(id)

func has_interactable(id: String) -> bool:
	return interactables.has(id)

## Copy-on-read so callers can't mutate the registry behind its back.
func get_interactable(id: String) -> Dictionary:
	if not interactables.has(id):
		return {}
	return (interactables[id] as Dictionary).duplicate(true)

func is_interactable_enabled(id: String) -> bool:
	if not interactables.has(id):
		return false
	var spec: Dictionary = interactables[id]
	if bool(spec.get("one_shot", false)) and bool(spec.get("triggered", false)):
		return false
	return bool(spec.get("enabled", true))

func set_interactable_enabled(id: String, enabled: bool) -> void:
	if not interactables.has(id):
		return
	if bool(interactables[id].get("enabled", true)) == enabled:
		return  # no-op: keeps the node free to mirror without log spam
	_emit(GameEvent.KIND_SET_INTERACTABLE_ENABLED, {"id": id, "enabled": enabled})
	interactables[id]["enabled"] = enabled
	interactable_enabled_changed.emit(id, enabled)

## Re-arm an interactable: clear its triggered flag and re-enable it (so a
## one-shot can fire again). Event-logged so replay reproduces the re-arm.
func reset_interactable(id: String) -> void:
	if not interactables.has(id):
		return
	_emit(GameEvent.KIND_RESET_INTERACTABLE, {"id": id})
	interactables[id]["triggered"] = false
	interactables[id]["enabled"] = true

## The trigger authority. Guards existence / enabled / required_character; on
## success records the event, marks triggered, disables one-shots, and emits.
## Returns true if the trigger was accepted.
func trigger_interactable(id: String, character := "") -> bool:
	if not interactables.has(id):
		return false
	if not is_interactable_enabled(id):
		return false
	var spec: Dictionary = interactables[id]
	var req := String(spec.get("required_character", ""))
	if req != "" and character != "" and character != req:
		return false
	_emit(GameEvent.KIND_TRIGGER_INTERACTABLE, {"id": id, "character": character})
	spec["triggered"] = true
	if bool(spec.get("one_shot", false)):
		spec["enabled"] = false
	interactable_triggered.emit(id, character)
	return true

## Default radius for "what can the party see/reach" queries.
const INTERACTABLE_VISIBLE_RANGE := 12.0

## Interactable ids within `radius` of ANY of the given characters. Used to ask
## "what can the party act on right now" (the combined visible range). With
## enabled_only, spent one-shots / disabled interactables are excluded.
func interactables_in_range(char_ids: Array, radius: float = INTERACTABLE_VISIBLE_RANGE, enabled_only := true) -> Array:
	var result: Array = []
	var positions: Array[Vector3] = []
	for cid in char_ids:
		if characters.has(String(cid)):
			positions.append(get_position(String(cid)))
	for id in interactables:
		if enabled_only and not is_interactable_enabled(id):
			continue
		var ipos: Vector3 = interactables[id].get("position", Vector3.ZERO)
		for p in positions:
			if Vector3(p.x - ipos.x, 0.0, p.z - ipos.z).length() <= radius:
				result.append(id)
				break
	result.sort()
	return result

## Move a character to a registered interactable (cooperative cell move to its
## cell). Delegates to command_move_to_cell, which is the logged command.
func move_to_interactable(char_id: String, id: String) -> bool:
	if not has_interactable(id) or not grid:
		return false
	var ipos: Vector3 = interactables[id].get("position", Vector3.ZERO)
	return command_move_to_cell(char_id, grid.world_to_grid(ipos))

static func _solve_quadratic_detection(pos_a: Vector3, vel_a: Vector3, pos_b: Vector3, vel_b: Vector3, R: float, max_tau: float) -> float:
	var dp_x := pos_a.x - pos_b.x
	var dp_z := pos_a.z - pos_b.z
	var dv_x := vel_a.x - vel_b.x
	var dv_z := vel_a.z - vel_b.z
	var a := dv_x * dv_x + dv_z * dv_z
	var b := 2.0 * (dp_x * dv_x + dp_z * dv_z)
	var c := dp_x * dp_x + dp_z * dp_z - R * R
	if c <= 1e-6:
		return 0.0  # Already in range
	if absf(a) < 1e-8:
		if absf(b) < 1e-8:
			return -1.0  # Parallel, never converge
		var t := -c / b
		if t >= 0.0 and t <= max_tau:
			return t
		return -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var sqrt_disc := sqrt(disc)
	var t1 := (-b - sqrt_disc) / (2.0 * a)
	var t2 := (-b + sqrt_disc) / (2.0 * a)
	if t1 >= 0.0 and t1 <= max_tau:
		return t1
	if t2 >= 0.0 and t2 <= max_tau:
		return t2
	return -1.0
