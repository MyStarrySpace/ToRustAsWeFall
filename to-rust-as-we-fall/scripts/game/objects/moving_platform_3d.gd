class_name MovingPlatform3D
extends Node3D

signal state_changed(state: int)

const PassengerSystemScript := preload(
	"res://scripts/game/objects/moving_platform_passenger_system.gd")
const PATH_SAMPLES := 9

var _scheduler = null
var _gs = null
var _platform_id := "platform"
var _state_transforms: Array[Transform3D] = []
var _state_levels: Array = []
var _surface_cells: Dictionary = {}
var _passengers: RefCounted = null
var _state := 0
var _from_state := 0
var _to_state := 0
var _motion_start_tick := -1.0
var _motion_end_tick := -1.0
var _motion_active := false
var _commit_handle := 0
var _receipt_factory := Callable()


func configure(
		scheduler,
		game_state,
		platform_id: String,
		state_transforms: Array,
		initial_state := 0,
		surface_cells: Dictionary = {},
		state_levels: Array = []
	) -> void:
	_scheduler = scheduler
	_gs = game_state
	_platform_id = platform_id
	_state_transforms.clear()
	for transform_v in state_transforms:
		if transform_v is Transform3D:
			_state_transforms.append(transform_v as Transform3D)
	_state_levels = state_levels.duplicate(true)
	_surface_cells = surface_cells.duplicate()
	_state = clampi(initial_state, 0, maxi(0, _state_transforms.size() - 1))
	_from_state = _state
	_to_state = _state
	_passengers = PassengerSystemScript.new()
	_passengers.configure(_gs, _platform_id)
	if not _state_transforms.is_empty():
		transform = _state_transforms[_state]
	set_process(false)


func set_authority(scheduler, game_state) -> void:
	_scheduler = scheduler
	_gs = game_state
	if _passengers == null:
		_passengers = PassengerSystemScript.new()
	_passengers.configure(_gs, _platform_id)


func get_state() -> int:
	return _state


func set_state_immediate(state_index: int) -> void:
	if state_index < 0 or state_index >= _state_transforms.size():
		return
	_state = state_index
	_from_state = state_index
	_to_state = state_index
	_motion_active = false
	transform = _state_transforms[state_index]
	set_process(false)


func get_motion_window() -> Dictionary:
	return _passengers.get_motion_window() if _passengers != null else {}


func is_moving() -> bool:
	return _motion_active


func request_state(target_state: int, duration: float, receipt_factory := Callable()) -> bool:
	if _scheduler == null or target_state < 0 or target_state >= _state_transforms.size() \
			or target_state == _state or _motion_active or duration <= 0.0:
		return false
	var now := _tick()
	if not begin_transition(target_state, now, now + duration, receipt_factory):
		return false
	_commit_handle = int(_scheduler.schedule_at(
		now + duration, commit_transition, "moving_platform_%s" % _platform_id))
	return _commit_handle > 0


func begin_transition(
		target_state: int,
		start_tick: float,
		end_tick: float,
		receipt_factory := Callable()
	) -> bool:
	if target_state < 0 or target_state >= _state_transforms.size() \
			or target_state == _state or end_tick <= start_tick:
		return false
	_from_state = _state
	_to_state = target_state
	_motion_start_tick = start_tick
	_motion_end_tick = end_tick
	_motion_active = true
	_receipt_factory = receipt_factory
	set_process(true)
	_begin_passenger_motion()
	_apply_motion_at(_tick())
	return true


## Standalone platforms replan immediately. Mechanisms that commit related topology first (such
## as rising water) may defer this, update their grid map, then call replan_affected_routes().
func commit_transition(defer_route_replan := false) -> void:
	if not _motion_active:
		return
	_apply_motion_at(_motion_end_tick)
	if _passengers != null:
		_passengers.finalize_carries(&"platform_state_commit")
	_state = _to_state
	_from_state = _state
	_motion_active = false
	_commit_handle = 0
	set_process(false)
	state_changed.emit(_state)
	if not defer_route_replan:
		replan_affected_routes()


func replan_affected_routes(reason := "moving_platform_state_changed") -> Array[String]:
	return _passengers.replan_captured_routes(reason) if _passengers != null else []


func _process(_delta: float) -> void:
	if not _motion_active:
		set_process(false)
		return
	_apply_motion_at(_tick())


func _apply_motion_at(tick: float) -> void:
	var progress := _progress_at(tick)
	transform = _sample_transform(progress)


func _progress_at(tick: float) -> float:
	if _motion_end_tick <= _motion_start_tick:
		return 1.0
	return clampf((tick - _motion_start_tick) /
		(_motion_end_tick - _motion_start_tick), 0.0, 1.0)


func _sample_transform(progress: float) -> Transform3D:
	var eased := progress * progress * (3.0 - 2.0 * progress)
	return _state_transforms[_from_state].interpolate_with(
		_state_transforms[_to_state], eased)


func _levels_for_state(state_index: int) -> Array[int]:
	var levels: Array[int] = []
	if state_index >= 0 and state_index < _state_levels.size():
		var value: Variant = _state_levels[state_index]
		if value is Array:
			for level_v in value as Array:
				var level := int(level_v)
				if not levels.has(level):
					levels.append(level)
	return levels


func _begin_passenger_motion() -> void:
	if _passengers == null or _gs == null or _gs.grid == null or _surface_cells.is_empty():
		return
	var affected_levels: Array[int] = _levels_for_state(_from_state)
	for level in _levels_for_state(_to_state):
		if not affected_levels.has(level):
			affected_levels.append(level)
	_passengers.begin_motion_window(
		_motion_start_tick, _motion_end_tick, _surface_cells, affected_levels)
	var accepted_levels := _levels_for_state(_from_state)
	for id in _passengers.surface_occupants(_surface_cells, accepted_levels, true):
		_begin_passenger_path(id)


func _begin_passenger_path(id: String) -> void:
	var render_origin: Vector3 = _gs.get_render_position(id) \
		if _gs.has_method("get_render_position") else _gs.get_position(id)
	var start_global := global_transform
	var local_offset := start_global.affine_inverse() * render_origin
	var render_path: Array = []
	var data_path: Array = []
	for sample_index in range(PATH_SAMPLES):
		var progress := float(sample_index) / float(PATH_SAMPLES - 1)
		var sampled_global := get_parent_node_3d().global_transform * _sample_transform(progress) \
			if get_parent_node_3d() != null else _sample_transform(progress)
		var render_point: Vector3 = sampled_global * local_offset
		render_path.append(render_point)
		var data_point := render_point
		if _gs.coord_map != null and _gs.coord_map.has_method("to_data"):
			data_point = _gs.coord_map.to_data(render_point)
		data_path.append(data_point)
	data_path[0] = _gs.get_position(id)
	render_path[0] = render_origin
	var receipt: Dictionary = _receipt_factory.call(
		id, render_path[0], render_path.back(), _motion_start_tick, _motion_end_tick) \
		if _receipt_factory.is_valid() else {}
	_passengers.begin_carry(
		id, data_path, render_path,
		maxf(0.05, _motion_end_tick - _motion_start_tick - 0.01), receipt)


func _tick() -> float:
	return float(_scheduler.get_current_tick()) if _scheduler != null else 0.0
