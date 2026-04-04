@tool
extends CharacterBody3D

## Rimworld-style click-to-move. Click ground → destination marker appears →
## character walks there. Indirect control. Visual feedback: destination ring,
## path line from character to destination.
##
## Supports two modes:
## - GameState-driven: position read from interpolation each frame. All commands
##   go through GameState. Scheduler handles arrival timing.
## - Fallback: frame-based velocity movement (for scenes without GameState).

@export var move_speed := 3.0
@export var run_speed := 6.0
@export var color := Color(0.29, 0.62, 1.0)  # Aster blue

## When set, click-to-move uses A* pathfinding. When null, straight-line.
var grid_world: GridWorld

## When set, movement commands go through GameState.
var game_state: GameState
var char_id := ""  ## Character ID in GameState (e.g. "aster")

var _target_pos: Vector3
var _moving := false
var _move_enabled := true
var _running := false
var _auto_path: Array[Vector3] = []
var _auto_path_index := 0

# Ability queue destination marker
var _ability_marker: MeshInstance3D
var _ability_marker_mat: StandardMaterial3D

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label3D

# Destination marker — ring on the ground where you clicked
var _dest_marker: MeshInstance3D
var _dest_marker_mat: StandardMaterial3D

# Path line — dashed line from character to destination
var _path_line: MeshInstance3D

signal arrived()
signal auto_path_complete()

func _ready() -> void:
	_target_pos = global_position

	# Build character visual — capsule
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.0
	_mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.darkened(0.5)
	mat.emission_energy_multiplier = 0.3
	_mesh.material_override = mat

	# Destination marker — small ring on the ground
	_dest_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.3
	torus.rings = 16
	torus.ring_segments = 8
	_dest_marker.mesh = torus
	_dest_marker_mat = StandardMaterial3D.new()
	_dest_marker_mat.albedo_color = Color(color, 0.0)
	_dest_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dest_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dest_marker.material_override = _dest_marker_mat
	_dest_marker.rotation.x = -PI / 2.0
	_dest_marker.top_level = true
	add_child(_dest_marker)

	# Path line (rebuilt each frame when moving)
	_path_line = MeshInstance3D.new()
	_path_line.top_level = true
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(color, 0.3)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_line.material_override = line_mat
	add_child(_path_line)

	# Ability target marker — diamond shape at queued ability destination
	_ability_marker = MeshInstance3D.new()
	var diamond := SphereMesh.new()
	diamond.radius = 0.2
	diamond.height = 0.4
	_ability_marker.mesh = diamond
	_ability_marker_mat = StandardMaterial3D.new()
	_ability_marker_mat.albedo_color = Color(0.9, 0.7, 0.2, 0.0)
	_ability_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ability_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ability_marker_mat.emission_enabled = true
	_ability_marker_mat.emission = Color(0.9, 0.6, 0.1)
	_ability_marker_mat.emission_energy_multiplier = 0.5
	_ability_marker.material_override = _ability_marker_mat
	_ability_marker.top_level = true
	add_child(_ability_marker)

	if Engine.is_editor_hint():
		return

	# Connect arrival signal if GameState is available
	if game_state:
		game_state.character_arrived.connect(_on_gs_arrived)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not _move_enabled:
		return
	if _auto_path.size() > 0 and not (game_state and char_id != ""):
		return  # Don't interrupt fallback auto-path with clicks

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var hit := _raycast_ground(mb.position)
			if hit != Vector3.INF:
				_set_click_target(hit)

func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	query.collision_mask = 1  # Ground only
	var result := space.intersect_ray(query)
	if not result.is_empty():
		return result.position
	return Vector3.INF

func _set_click_target(world_pos: Vector3) -> void:
	if game_state and char_id != "":
		if grid_world:
			var target_cell := grid_world.world_to_grid(world_pos)
			if not game_state.command_move_to_cell(char_id, target_cell):
				return
			var snapped := grid_world.grid_to_world(target_cell)
			_dest_marker.global_position = Vector3(snapped.x, 0.05, snapped.z)
		else:
			if not game_state.command_move_to_pos(char_id, world_pos):
				return
			_dest_marker.global_position = Vector3(world_pos.x, 0.05, world_pos.z)
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
		return

	if grid_world:
		var target_cell := grid_world.world_to_grid(world_pos)
		var current_cell := grid_world.world_to_grid(global_position)
		var snapped := grid_world.grid_to_world(target_cell)
		var path := grid_world.find_path(current_cell, target_cell)
		if path.is_empty():
			return
		walk_path(path)
		_dest_marker.global_position = Vector3(snapped.x, 0.05, snapped.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
	else:
		_target_pos = world_pos
		_target_pos.y = global_position.y
		_moving = true
		_auto_path.clear()
		_auto_path_index = 0
		_dest_marker.global_position = Vector3(world_pos.x, 0.05, world_pos.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)

## Walk to a grid cell using A* pathfinding.
func walk_to_grid(cell: Vector2i) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_cell(char_id, cell)
		_moving = true
		return
	if not grid_world:
		return
	var current_cell := grid_world.world_to_grid(global_position)
	var path := grid_world.find_path(current_cell, cell)
	if not path.is_empty():
		walk_path(path)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# GameState-driven: read interpolated position
	if game_state and char_id != "":
		if game_state.is_moving(char_id):
			var pos := game_state.get_position(char_id)
			global_position = Vector3(pos.x, global_position.y, pos.z)
			_moving = true
		elif _moving:
			# Just arrived — snap to final position
			_moving = false
			var pos := game_state.get_position(char_id)
			global_position = Vector3(pos.x, global_position.y, pos.z)
			velocity = Vector3.ZERO
		_update_dest_marker(delta)
		_update_path_line()
		return

	# Fallback: auto-path movement (scripted, no GameState)
	if _auto_path.size() > 0:
		var waypoint := _auto_path[_auto_path_index]
		var dir := (waypoint - global_position)
		dir.y = 0
		if dir.length() < 0.2:
			_auto_path_index += 1
			if _auto_path_index >= _auto_path.size():
				_auto_path.clear()
				_auto_path_index = 0
				_moving = false
				auto_path_complete.emit()
				_update_dest_marker(delta)
				_update_path_line()
				return
		else:
			velocity = dir.normalized() * move_speed
			move_and_slide()
		_update_path_line()
		_update_dest_marker(delta)
		return

	# Fallback: click-to-move
	if _moving:
		var dir := (_target_pos - global_position)
		dir.y = 0
		var dist := dir.length()
		if dist < 0.15:
			_moving = false
			velocity = Vector3.ZERO
			arrived.emit()
		else:
			velocity = dir.normalized() * move_speed
			move_and_slide()

	_update_dest_marker(delta)
	_update_path_line()

func _on_gs_arrived(id: String) -> void:
	if id == char_id:
		_moving = false
		arrived.emit()
		auto_path_complete.emit()

func _update_dest_marker(delta: float) -> void:
	if _moving:
		var pulse := 0.3 + sin(Time.get_ticks_msec() * 0.004) * 0.15
		_dest_marker_mat.albedo_color.a = pulse
		var dist := Vector2(
			global_position.x - _dest_marker.global_position.x,
			global_position.z - _dest_marker.global_position.z
		).length()
		var s := clampf(dist / 3.0, 0.3, 1.2)
		_dest_marker.scale = Vector3(s, s, s)
	else:
		_dest_marker_mat.albedo_color.a = maxf(0, _dest_marker_mat.albedo_color.a - delta * 2.0)

func _update_path_line() -> void:
	# Update ability marker visibility
	var has_queued_ability := game_state and char_id != "" and game_state.has_queued_ability(char_id)
	if has_queued_ability:
		var qa_data: Dictionary = game_state._queued_abilities[char_id]
		_ability_marker.global_position = Vector3(qa_data.target_pos.x, 0.5, qa_data.target_pos.z)
		var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.3
		_ability_marker_mat.albedo_color.a = pulse
	else:
		_ability_marker_mat.albedo_color.a = 0.0

	# Path line color: walk = character color (subtle), run = bright warm
	var line_mat: StandardMaterial3D = _path_line.material_override
	if _running:
		line_mat.albedo_color = Color(1.0, 0.7, 0.3, 0.5)
	else:
		line_mat.albedo_color = Color(color, 0.3)

	if not _moving and not has_queued_ability:
		_path_line.mesh = null
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var from_pos := Vector3(global_position.x, 0.08, global_position.z)

	if game_state and char_id != "" and game_state.is_moving(char_id):
		var mv = game_state.characters[char_id].movement
		if mv:
			var path: Array[Vector3] = mv.path
			var cum_dist: Array[float] = mv.cum_dist
			var total: float = mv.total_distance
			var current_tick := game_state.scheduler.get_current_tick()
			var t := clampf((current_tick - mv.start_tick) / mv.duration, 0.0, 1.0) if mv.duration > 0 else 1.0
			var current_dist := t * total
			for i in range(1, path.size()):
				if cum_dist[i] > current_dist:
					var to_pos := Vector3(path[i].x, 0.08, path[i].z)
					im.surface_add_vertex(from_pos)
					im.surface_add_vertex(to_pos)
					from_pos = to_pos
	elif _auto_path.size() > 0:
		for i in range(_auto_path_index, _auto_path.size()):
			var wp := _auto_path[i]
			var to_pos := Vector3(wp.x, 0.08, wp.z)
			im.surface_add_vertex(from_pos)
			im.surface_add_vertex(to_pos)
			from_pos = to_pos
	elif _moving:
		var to_pos := Vector3(_target_pos.x, 0.08, _target_pos.z)
		im.surface_add_vertex(from_pos)
		im.surface_add_vertex(to_pos)

	im.surface_end()
	_path_line.mesh = im

## Set an auto-path for scripted movement
func walk_to(pos: Vector3) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_pos(char_id, pos)
		_moving = true
		return
	_auto_path = [pos]
	_auto_path_index = 0
	_moving = true

## Walk along a series of waypoints
func walk_path(path: Array[Vector3]) -> void:
	if game_state and char_id != "":
		game_state.command_walk_path(char_id, path)
		_moving = true
		return
	_auto_path = path
	_auto_path_index = 0
	_moving = true

func set_move_enabled(enabled: bool) -> void:
	_move_enabled = enabled
	if not enabled:
		if game_state and char_id != "":
			game_state.command_stop(char_id)
		_moving = false
		velocity = Vector3.ZERO
		_auto_path.clear()

func is_moving() -> bool:
	if game_state and char_id != "":
		return game_state.is_moving(char_id)
	return _moving

func set_running(running: bool) -> void:
	_running = running
	# Visual: capsule leans forward slightly when running, stretches
	if _mesh:
		if running:
			_mesh.rotation.x = -0.15
			_mesh.scale = Vector3(0.9, 1.1, 0.9)
		else:
			_mesh.rotation.x = 0.0
			_mesh.scale = Vector3.ONE
	# Update dest marker color: orange when running
	if _dest_marker_mat:
		if running:
			_dest_marker_mat.albedo_color = Color(1.0, 0.6, 0.2, _dest_marker_mat.albedo_color.a)
		else:
			_dest_marker_mat.albedo_color = Color(color.r, color.g, color.b, _dest_marker_mat.albedo_color.a)
