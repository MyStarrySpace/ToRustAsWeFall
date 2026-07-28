class_name StagedRigidCollapse3D
extends Node3D

## Reusable, frame-sliced presentation for turning an authored MeshInstance3D subtree into
## cosmetic rigid debris. The caller owns the authoritative consequence (level transition,
## damage, etc.); this component only presents that consequence without tree-entering a whole
## physics cohort in one rendered frame.

signal settled(generation: int)

const DEFAULT_PIECES_PER_STEP := 4
const DEFAULT_RELEASES_PER_STEP := 4
const DEFAULT_SETTLE_SECONDS := 3.0

var _generation := 0
var _active := false
var _visual_paused := false
var _source_model: Node3D
var _pending_pieces: Array[Dictionary] = []
var _scheduled_releases: Array[Dictionary] = []
var _debris: Array[RigidBody3D] = []
var _paused_debris: Dictionary = {}
var _catch_floor: StaticBody3D
var _source_piece_count := 0
var _visual_elapsed := 0.0
var _settle_started_at := -1.0

var _pieces_per_step := DEFAULT_PIECES_PER_STEP
var _releases_per_step := DEFAULT_RELEASES_PER_STEP
var _settle_seconds := DEFAULT_SETTLE_SECONDS
var _debris_layer := 0
var _floor_layer := 0
var _gravity_scale := 1.0
var _release_delay_per_unit := 0.05
var _max_release_delay := 0.5
var _horizontal_impulse := 1.3
var _downward_impulse := -1.0
var _angular_scale := 2.2


## Begin one collapse generation. The nearest batch is converted immediately so the initiating
## frame visibly answers the cause; remaining batches are converted by advance_visual_time().
## Returns a component-owned lifecycle token suitable for rejecting a stale settled signal.
func begin(source_model: Node3D, break_x: float, options: Dictionary = {}) -> int:
	# A presenter can be reused after settlement or redirected while still active. Retire every
	# previously owned physics node before clearing its tracking arrays; otherwise a settled
	# generation leaves untracked debris and a second catch floor in the tree. When possible,
	# restore an interrupted source's converted meshes so restarting it cannot lose its prefix.
	if _active or not _debris.is_empty() or is_instance_valid(_catch_floor):
		_clear_owned_visuals(_active)
	_generation += 1
	_active = source_model != null and is_instance_valid(source_model)
	_visual_paused = false
	_source_model = source_model
	_pending_pieces.clear()
	_scheduled_releases.clear()
	_debris.clear()
	_paused_debris.clear()
	_source_piece_count = 0
	_visual_elapsed = 0.0
	_settle_started_at = -1.0
	_apply_options(options)
	if not _active:
		return _generation

	var prepare_started := PerformanceTrace.begin()
	_create_catch_floor(break_x, options)
	var source_meshes: Array[Node] = source_model.find_children("*", "MeshInstance3D", true, false)
	for source_order in range(source_meshes.size()):
		var mesh_instance := source_meshes[source_order] as MeshInstance3D
		var world_transform := mesh_instance.global_transform
		_pending_pieces.append({
			"mesh": mesh_instance,
			"world_transform": world_transform,
			"aabb": mesh_instance.get_aabb(),
			"distance": absf(world_transform.origin.x - break_x),
			"source_order": source_order,
		})
	_pending_pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var distance_a := float(a.get("distance", 0.0))
		var distance_b := float(b.get("distance", 0.0))
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		return int(a.get("source_order", 0)) < int(b.get("source_order", 0)))
	_source_piece_count = _pending_pieces.size()
	PerformanceTrace.end(&"draw", &"collapse.prepare", prepare_started,
		str(source_model.name), _source_piece_count)
	_convert_next_batch(break_x)
	_release_ready_debris()
	return _generation


## Advance one rendered presentation step. `delta` should be unscaled wall-clock gameplay time;
## fast-forward must not accelerate the cosmetic cascade, and pause should pass zero or call
## set_visual_paused(true). At most one bounded conversion batch is performed per call.
func advance_visual_time(delta: float) -> void:
	if not _active or _visual_paused or delta <= 0.0:
		return
	if not is_instance_valid(_source_model) and not _pending_pieces.is_empty():
		cancel()
		return
	_visual_elapsed += delta
	if not _pending_pieces.is_empty():
		var break_x := float(get_meta(&"collapse_break_x", global_position.x))
		_convert_next_batch(break_x)
	_release_ready_debris()
	if _pending_pieces.is_empty() and _scheduled_releases.is_empty():
		if _settle_started_at < 0.0:
			_settle_started_at = _visual_elapsed
		elif _visual_elapsed - _settle_started_at >= _settle_seconds:
			if is_instance_valid(_source_model):
				_source_model.queue_free()
			_active = false
			settled.emit(_generation)


## Pause is explicit because gameplay uses a scheduler pause rather than SceneTree.paused. Released
## rigid bodies retain their velocities and resume from the exact same visual state.
func set_visual_paused(paused: bool) -> void:
	if _visual_paused == paused:
		return
	_visual_paused = paused
	if paused:
		for body in _debris:
			if not is_instance_valid(body) or body.freeze:
				continue
			_paused_debris[body.get_instance_id()] = {
				"linear_velocity": body.linear_velocity,
				"angular_velocity": body.angular_velocity,
			}
			body.freeze = true
		return
	for body in _debris:
		if not is_instance_valid(body):
			continue
		var saved: Dictionary = _paused_debris.get(body.get_instance_id(), {})
		if saved.is_empty():
			continue
		body.freeze = false
		body.linear_velocity = saved.get("linear_velocity", Vector3.ZERO)
		body.angular_velocity = saved.get("angular_velocity", Vector3.ZERO)
	_paused_debris.clear()


## Invalidate all pending work. Every callback is component-owned and frame-driven, so clearing
## these references is sufficient to make scene teardown safe; no SceneTree timer survives us.
func cancel(remove_visual_nodes := true) -> void:
	_generation += 1
	_active = false
	_visual_paused = false
	_settle_started_at = -1.0
	if remove_visual_nodes:
		_clear_owned_visuals(false)
	else:
		_pending_pieces.clear()
		_scheduled_releases.clear()
		_paused_debris.clear()
		_debris.clear()
		_catch_floor = null
	_source_model = null


func is_active() -> bool:
	return _active


func is_visual_paused() -> bool:
	return _visual_paused


func is_settling() -> bool:
	return _active and _settle_started_at >= 0.0


func visual_generation() -> int:
	return _generation


func visual_elapsed() -> float:
	return _visual_elapsed


func source_piece_count() -> int:
	return _source_piece_count


func pending_piece_count() -> int:
	return _pending_pieces.size()


func pending_release_count() -> int:
	return _scheduled_releases.size()


func converted_piece_count() -> int:
	return _debris.size()


func debris_bodies() -> Array[RigidBody3D]:
	return _debris


func catch_floor() -> StaticBody3D:
	return _catch_floor


func _apply_options(options: Dictionary) -> void:
	_pieces_per_step = maxi(int(options.get("pieces_per_step", DEFAULT_PIECES_PER_STEP)), 1)
	_releases_per_step = maxi(int(options.get("releases_per_step", _pieces_per_step)), 1)
	_settle_seconds = maxf(float(options.get("settle_seconds", DEFAULT_SETTLE_SECONDS)), 0.0)
	_debris_layer = int(options.get("debris_layer", 0))
	_floor_layer = int(options.get("floor_layer", 0))
	_gravity_scale = float(options.get("gravity_scale", 1.0))
	_release_delay_per_unit = maxf(float(options.get("release_delay_per_unit", 0.05)), 0.0)
	_max_release_delay = maxf(float(options.get("max_release_delay", 0.5)), 0.0)
	_horizontal_impulse = float(options.get("horizontal_impulse", 1.3))
	_downward_impulse = float(options.get("downward_impulse", -1.0))
	_angular_scale = float(options.get("angular_scale", 2.2))
	set_meta(&"collapse_break_x", float(options.get("break_x", 0.0)))


func _create_catch_floor(break_x: float, options: Dictionary) -> void:
	var catch := StaticBody3D.new()
	catch.name = str(options.get("catch_name", "DebrisCatch"))
	catch.collision_layer = _floor_layer
	catch.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = options.get("catch_size", Vector3(60.0, 1.0, 30.0))
	collision.shape = box
	catch.add_child(collision)
	add_child(catch)
	catch.global_position = options.get("catch_global_position", Vector3(break_x, -4.4, 0.0))
	_catch_floor = catch
	set_meta(&"collapse_break_x", break_x)


func _convert_next_batch(break_x: float) -> void:
	if _pending_pieces.is_empty():
		return
	var batch_started := PerformanceTrace.begin()
	var converted := 0
	while converted < _pieces_per_step and not _pending_pieces.is_empty():
		var piece: Dictionary = _pending_pieces.pop_front()
		var mesh_instance := piece.get("mesh") as MeshInstance3D
		if not is_instance_valid(mesh_instance):
			continue
		var world_transform: Transform3D = piece.get("world_transform", Transform3D.IDENTITY)
		var aabb: AABB = piece.get("aabb", AABB())
		var body := RigidBody3D.new()
		body.name = "%s_Debris" % str(mesh_instance.name)
		body.collision_layer = _debris_layer
		body.collision_mask = _floor_layer
		body.gravity_scale = _gravity_scale
		body.freeze = true
		add_child(body)
		body.global_transform = world_transform
		mesh_instance.get_parent().remove_child(mesh_instance)
		body.add_child(mesh_instance)
		mesh_instance.transform = Transform3D.IDENTITY
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size.max(Vector3(0.05, 0.05, 0.05))
		collision.shape = box
		collision.position = aabb.position + aabb.size * 0.5
		body.add_child(collision)
		_debris.append(body)
		var distance := absf(world_transform.origin.x - break_x)
		_scheduled_releases.append({
			"body": body,
			"release_at": minf(distance * _release_delay_per_unit, _max_release_delay),
			"break_x": break_x,
			"spin": _deterministic_spin(world_transform.origin.x),
		})
		converted += 1
	PerformanceTrace.end(&"draw", &"collapse.convert_batch", batch_started,
		str(name), converted)


func _release_ready_debris() -> void:
	if _scheduled_releases.is_empty():
		return
	var release_started := PerformanceTrace.begin()
	var released := 0
	while not _scheduled_releases.is_empty() and released < _releases_per_step:
		var entry: Dictionary = _scheduled_releases[0]
		if float(entry.get("release_at", INF)) > _visual_elapsed:
			break
		_scheduled_releases.pop_front()
		var body := entry.get("body") as RigidBody3D
		if not is_instance_valid(body):
			continue
		var break_x := float(entry.get("break_x", body.global_position.x))
		var away := signf(body.global_position.x - break_x)
		if away == 0.0:
			away = 1.0
		body.freeze = false
		body.apply_central_impulse(Vector3(away * _horizontal_impulse, _downward_impulse, 0.0))
		var spin: Vector3 = entry.get("spin", Vector3.ZERO)
		body.angular_velocity = spin * _angular_scale
		released += 1
	PerformanceTrace.end(&"draw", &"collapse.release_batch", release_started,
		str(name), released)


func _clear_owned_visuals(restore_interrupted_source: bool) -> void:
	var can_restore := restore_interrupted_source and is_instance_valid(_source_model) \
		and not _source_model.is_queued_for_deletion()
	for body in _debris:
		if not is_instance_valid(body):
			continue
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		if can_restore:
			for child in body.get_children():
				var mesh_instance := child as MeshInstance3D
				if mesh_instance != null:
					mesh_instance.reparent(_source_model, true)
		if body.get_parent() != null:
			body.get_parent().remove_child(body)
		body.queue_free()
	if is_instance_valid(_catch_floor):
		_catch_floor.collision_layer = 0
		_catch_floor.collision_mask = 0
		if _catch_floor.get_parent() != null:
			_catch_floor.get_parent().remove_child(_catch_floor)
		_catch_floor.queue_free()
	_pending_pieces.clear()
	_scheduled_releases.clear()
	_paused_debris.clear()
	_debris.clear()
	_catch_floor = null


func _deterministic_spin(x: float) -> Vector3:
	var hash_value := int(absf(x) * 17.0)
	return Vector3(
		0.7 + float(hash_value % 6) * 0.22,
		-0.5 + float(int(hash_value / 6) % 7) * 0.18,
		-0.6 + float(int(hash_value / 42) % 6) * 0.24
	)
