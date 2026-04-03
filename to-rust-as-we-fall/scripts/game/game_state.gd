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

var grid: GridWorld
var scheduler: EventScheduler
var explored: Dictionary = {}
var characters: Dictionary = {}
var physics_objects: Dictionary = {}

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
	return _interpolate_path(mv.path, mv.cum_dist, t)

func is_physics_moving(id: String) -> bool:
	if not physics_objects.has(id):
		return false
	return physics_objects[id].movement != null

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
