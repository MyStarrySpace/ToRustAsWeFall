@tool
extends Node3D

## Simple NPC with scripted movement and visual representation.
## Supports GameState-driven interpolation or local fallback movement.

@export var display_name := "Citizen"
@export var color := Color(0.5, 0.5, 0.55)
@export var move_speed := 2.0
var speed_multiplier := 1.0

## When set, movement commands go through GameState (interpolation-based).
var game_state: GameState
var char_id := ""
## Scripted ambience walks don't advertise like player commands: the PathRenderManager skips NPCs by
## default. A scene that WANTS an NPC's route visible (an escort the player follows) flips this on.
var show_movement_path := false
var _scheduler

## When set, walk_to_grid() uses A* pathfinding (fallback mode only).
var grid_world: GridWorld

var _path: Array[Vector3] = []
var _path_index := 0
var _moving := false
var _visible_mesh := true
var _fade_active := false
var _fade_start_tick := 0.0
var _fade_duration := 0.0

@onready var _mesh: MeshInstance3D
@onready var _label: Label3D

signal path_complete()
signal waypoint_reached(index: int)

func _ready() -> void:
	# Build visual
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 0.9
	_mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_mesh.material_override = mat
	_mesh.position.y = 0.45
	add_child(_mesh)

	# Data label (Aster sees people as data points)
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 48
	_label.pixel_size = 0.01
	_label.modulate = Color(color, 0.7)
	_label.position.y = 1.2
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

	if Engine.is_editor_hint():
		return

	if game_state and char_id != "":
		game_state.character_arrived.connect(_on_gs_arrived)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_scheduler_fade()
	# GameState-driven: read interpolated position
	if game_state and char_id != "":
		if game_state.is_moving(char_id):
			var pos := game_state.get_position(char_id)
			global_position = Vector3(pos.x, global_position.y, pos.z)
		return

	# Fallback: local path-following
	if not _moving or _path.is_empty():
		return

	var target := _path[_path_index]
	var dir := (target - global_position)
	dir.y = 0
	if dir.length() < 0.15:
		global_position.x = target.x
		global_position.z = target.z
		waypoint_reached.emit(_path_index)
		_path_index += 1
		if _path_index >= _path.size():
			_moving = false
			_path.clear()
			_path_index = 0
			path_complete.emit()
	else:
		global_position += dir.normalized() * move_speed * speed_multiplier * delta

func set_scheduler(scheduler_ref) -> void:
	_scheduler = scheduler_ref

func sync_scheduler_visuals() -> void:
	_update_scheduler_fade()

func _on_gs_arrived(id: String) -> void:
	if id == char_id:
		path_complete.emit()

func walk_path(path: Array[Vector3]) -> void:
	if game_state and char_id != "":
		game_state.command_walk_path(char_id, path)
		return
	_path = path
	_path_index = 0
	_moving = true

func walk_to(pos: Vector3) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_pos(char_id, pos)
		return
	walk_path([pos])

func stop() -> void:
	if game_state and char_id != "":
		game_state.command_stop(char_id)
		return
	_moving = false
	_path.clear()
	_path_index = 0

## Walk to a grid cell using A* pathfinding.
func walk_to_grid(cell: Vector2i) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_cell(char_id, cell)
		return
	if not grid_world:
		return
	var current_cell := grid_world.world_to_grid(global_position)
	var path := grid_world.find_path(current_cell, cell)
	if not path.is_empty():
		walk_path(path)

func is_moving() -> bool:
	if game_state and char_id != "":
		return game_state.is_moving(char_id)
	return _moving

func set_color(c: Color) -> void:
	color = c
	if _mesh and _mesh.material_override:
		(_mesh.material_override as StandardMaterial3D).albedo_color = c
	if _label:
		_label.modulate = Color(c, 0.7)

func fade_out(duration: float) -> void:
	if _scheduler != null:
		_fade_start_tick = _scheduler.get_current_tick()
		_fade_duration = maxf(duration, 0.001)
		_fade_active = true
		_update_scheduler_fade()
		return
	var tween := create_tween()
	tween.tween_property(_mesh, "transparency", 1.0, duration)
	tween.parallel().tween_property(_label, "modulate:a", 0.0, duration)

func _update_scheduler_fade() -> void:
	if not _fade_active or _scheduler == null:
		return
	var elapsed: float = _scheduler.get_current_tick() - _fade_start_tick
	var t := clampf(elapsed / _fade_duration, 0.0, 1.0)
	_apply_fade_alpha(1.0 - t)
	if t >= 1.0:
		_fade_active = false

func _apply_fade_alpha(alpha: float) -> void:
	if _mesh:
		_mesh.transparency = 1.0 - alpha
	if _label:
		_label.modulate.a = 0.7 * alpha
