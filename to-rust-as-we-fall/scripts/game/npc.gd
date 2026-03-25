@tool
extends Node3D

## Simple NPC with scripted movement and visual representation.
## Supports GameState-driven interpolation or local fallback movement.

@export var display_name := "Citizen"
@export var color := Color(0.5, 0.5, 0.55)
@export var move_speed := 2.0

## When set, movement commands go through GameState (interpolation-based).
var game_state: GameState
var char_id := ""

## When set, walk_to_grid() uses A* pathfinding (fallback mode only).
var grid_world: GridWorld

var _path: Array[Vector3] = []
var _path_index := 0
var _moving := false
var _visible_mesh := true

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
		global_position += dir.normalized() * move_speed * delta

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
	var tween := create_tween()
	tween.tween_property(_mesh, "transparency", 1.0, duration)
	tween.parallel().tween_property(_label, "modulate:a", 0.0, duration)
