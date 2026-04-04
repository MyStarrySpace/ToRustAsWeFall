class_name GameState
extends RefCounted

## Central data authority for all character state and movement.
## Movement uses path interpolation driven by EventScheduler ticks.
## Position is computed on read — no per-frame tick needed.
##
## Predictive detection: when movement starts/stops, computes when paths
## will bring characters within detection range and schedules events.
## Characters with stats.detection_range > 0 are detectors.

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

var grid: GridWorld
var scheduler: EventScheduler
var explored: Dictionary = {}
var characters: Dictionary = {}
var physics_objects: Dictionary = {}
var pendulums: Dictionary = {}
var items: Dictionary = {}        # item_id → item dict
var collection: Array[String] = [] # Permanently collected item IDs (cure components, etc.)
var _next_item_id := 1
var _endocytosing: Dictionary = {} # char_id → {item_id, handle} for in-progress endocytosis

## Pendulum schema:
## {
##   anchor: Vector3,         # Pivot point (top of swing)
##   length: float,           # Rope/chain length
##   amplitude: float,        # Max swing angle in radians
##   phase: float,            # Phase offset in radians
##   swing_axis: Vector3,     # Normalized axis perpendicular to swing plane (e.g. Z for XY swing)
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
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	characters[id] = {
		"position": pos,
		"grid_cell": cell,
		"move_speed": speed,
		"stats": stats,
		"movement": null,
		"hands": [null, null],
		"internal": [],
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
		_recompute_all_detection_predictions()
		_recompute_physics_predictions()
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
	character_arrived.emit(id)
	if _queued_abilities.has(id):
		check_queued_abilities()

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
			# Positions at t0
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
	var speed: float = ch.move_speed
	for i in range(1, mv.path.size()):
		var seg_start_tick: float = mv.start_tick + (mv.cum_dist[i - 1] / mv.total_distance) * mv.duration
		var seg_end_tick: float = mv.start_tick + (mv.cum_dist[i] / mv.total_distance) * mv.duration
		var dir := Vector3(mv.path[i].x - mv.path[i - 1].x, 0, mv.path[i].z - mv.path[i - 1].z)
		var seg_len := dir.length()
		var vel := dir.normalized() * speed if seg_len > 0.001 else Vector3.ZERO
		segments.append({
			"start_tick": seg_start_tick,
			"end_tick": seg_end_tick,
			"start_pos": Vector3(mv.path[i - 1].x, 0, mv.path[i - 1].z),
			"velocity": vel,
		})
	return segments

# --- Queued Abilities (auto-move-into-range) ---

var _queued_abilities: Dictionary = {} # char_id → {ability, target_pos, range, callback}

func queue_ability(char_id: String, ability: String, target_pos: Vector3, ability_range: float, callback: Callable) -> void:
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
	# Move toward target, stopping at ability range
	var dir := Vector3(target_pos.x - char_pos.x, 0, target_pos.z - char_pos.z).normalized()
	var move_target := target_pos - dir * (ability_range * 0.8)
	command_move_to_pos(char_id, move_target)

func cancel_queued_ability(char_id: String) -> void:
	_queued_abilities.erase(char_id)

func has_queued_ability(char_id: String) -> bool:
	return _queued_abilities.has(char_id)

func get_queued_ability(char_id: String) -> String:
	if _queued_abilities.has(char_id):
		return _queued_abilities[char_id].ability
	return ""

func check_queued_abilities() -> void:
	var to_fire: Array[String] = []
	for char_id in _queued_abilities:
		if not characters.has(char_id):
			to_fire.append(char_id)
			continue
		var qa: Dictionary = _queued_abilities[char_id]
		var char_pos := get_position(char_id)
		var dist := Vector2(char_pos.x - qa.target_pos.x, char_pos.z - qa.target_pos.z).length()
		if dist <= qa.range:
			to_fire.append(char_id)
			command_stop(char_id)
			qa.callback.call()
			ability_fired.emit(char_id, qa.ability, qa.target_pos)
	for char_id in to_fire:
		_queued_abilities.erase(char_id)

# --- Items / Hands / Endocytosis ---

const TRANSFER_RANGE := 1.5
const ENDOCYTOSE_DEFAULT_DURATION := 2.0

func spawn_item(type: String, pos: Vector3, properties: Dictionary = {}) -> String:
	var id := "item_%d" % _next_item_id
	_next_item_id += 1
	var type_data := ItemData.get_type_data(type)
	type_data.merge(properties, true)
	items[id] = {
		"type": type,
		"holder": "",
		"location": "ground",
		"position": pos,
		"properties": type_data,
	}
	return id

func remove_item(item_id: String) -> void:
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
	if not characters.has(char_id) or not items.has(item_id):
		return false
	var item: Dictionary = items[item_id]
	if item.location != "ground":
		return false
	var ch: Dictionary = characters[char_id]
	var slot := _find_free_hand(char_id)
	if slot < 0:
		return false
	var char_pos := get_position(char_id)
	var dist := Vector3(char_pos.x - item.position.x, 0, char_pos.z - item.position.z).length()
	if dist > 2.0:
		return false
	ch.hands[slot] = item_id
	item.holder = char_id
	item.location = "hand"
	item_picked_up.emit(char_id, item_id)
	return true

func drop_item(char_id: String, item_id: String) -> bool:
	if not characters.has(char_id) or not items.has(item_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "hand":
		return false
	var ch: Dictionary = characters[char_id]
	for i in range(ch.hands.size()):
		if ch.hands[i] == item_id:
			ch.hands[i] = null
	item.holder = ""
	item.location = "ground"
	item.position = get_position(char_id)
	item_dropped.emit(char_id, item_id)
	return true

func transfer_item(from_id: String, to_id: String, item_id: String) -> bool:
	if not characters.has(from_id) or not characters.has(to_id) or not items.has(item_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != from_id or item.location != "hand":
		return false
	var to_slot := _find_free_hand(to_id)
	if to_slot < 0:
		return false
	var dist := get_position(from_id).distance_to(get_position(to_id))
	if dist > TRANSFER_RANGE:
		return false
	var from_ch: Dictionary = characters[from_id]
	for i in range(from_ch.hands.size()):
		if from_ch.hands[i] == item_id:
			from_ch.hands[i] = null
	var to_ch: Dictionary = characters[to_id]
	to_ch.hands[to_slot] = item_id
	item.holder = to_id
	item_transferred.emit(from_id, to_id, item_id)
	return true

func endocytose_item(char_id: String, item_id: String) -> bool:
	if not characters.has(char_id) or not items.has(item_id) or not scheduler:
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "hand":
		return false
	if _endocytosing.has(char_id):
		return false
	command_stop(char_id)
	var duration: float = item.properties.get("endocytosis_duration", ENDOCYTOSE_DEFAULT_DURATION)
	var cid := char_id
	var iid := item_id
	var handle := scheduler.schedule_after(duration, func(): _complete_endocytosis(cid, iid), "endocytose_" + char_id)
	_endocytosing[char_id] = {"item_id": item_id, "handle": handle}
	return true

func cancel_endocytosis(char_id: String) -> void:
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
	for i in range(ch.hands.size()):
		if ch.hands[i] == item_id:
			ch.hands[i] = null

	match effect:
		"digest":
			var restore: float = item.properties.get("atp_restore", 0.0)
			ch.stats["atp"] = ch.stats.get("atp", 0.0) + restore
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
		_:
			item.location = "internal"
			ch.internal.append(item_id)

	item_endocytosed.emit(char_id, item_id, effect)

func exocytose_item(char_id: String, item_id: String) -> bool:
	if not characters.has(char_id) or not items.has(item_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "internal":
		return false
	var ch: Dictionary = characters[char_id]
	ch.internal.erase(item_id)
	var slot := _find_free_hand(char_id)
	if slot >= 0:
		ch.hands[slot] = item_id
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
		if slot != null:
			result.append(slot)
	return result

func get_internal_items(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	return characters[char_id].internal.duplicate()

func has_free_hand(char_id: String) -> bool:
	return _find_free_hand(char_id) >= 0

func _find_free_hand(char_id: String) -> int:
	if not characters.has(char_id):
		return -1
	var hands: Array = characters[char_id].hands
	for i in range(hands.size()):
		if hands[i] == null:
			return i
	return -1

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

	# No slide — settle in place
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
