extends CharacterBody3D

## Rimworld-style click-to-move. Click ground → destination marker appears →
## character walks there. Indirect control. Visual feedback: destination ring,
## path line from character to destination.

@export var move_speed := 3.0
@export var color := Color(0.29, 0.62, 1.0)  # Aster blue

## When set, click-to-move uses A* pathfinding. When null, straight-line.
var grid_world: GridWorld

## When set, movement commands go through GameState. Player reads path from
## GameState, drives move_and_slide(), writes position back.
var game_state: GameState
var char_id := ""  ## Character ID in GameState (e.g. "aster")

var _target_pos: Vector3
var _moving := false
var _move_enabled := true
var _auto_path: Array[Vector3] = []
var _auto_path_index := 0

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
	# Add to scene root so it stays at the click position, not on the player
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

func _unhandled_input(event: InputEvent) -> void:
	if not _move_enabled:
		return
	if _auto_path.size() > 0:
		return  # Don't interrupt auto-path with clicks

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
	query.collision_mask = 1  # Ground only — skip characters (layer 2) and interactables (layer 4)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		return result.position
	return Vector3.INF

func _set_click_target(world_pos: Vector3) -> void:
	if game_state and char_id != "":
		# Unified path: route through GameState
		if grid_world:
			var target_cell := grid_world.world_to_grid(world_pos)
			if not game_state.command_move_to_cell(char_id, target_cell):
				return
			var snapped := grid_world.grid_to_world(target_cell)
			_dest_marker.global_position = Vector3(snapped.x, 0.05, snapped.z)
		else:
			game_state.command_move_to_pos(char_id, world_pos)
			_dest_marker.global_position = Vector3(world_pos.x, 0.05, world_pos.z)
		# Sync local state from GameState
		var ch: Dictionary = game_state.characters[char_id]
		_auto_path = ch.path.duplicate()
		_auto_path_index = ch.path_index
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
	elif grid_world:
		# Grid-based: snap to cell center, A* pathfind
		var target_cell := grid_world.world_to_grid(world_pos)
		var current_cell := grid_world.world_to_grid(global_position)
		var snapped := grid_world.grid_to_world(target_cell)
		var path := grid_world.find_path(current_cell, target_cell)
		if path.is_empty():
			return  # No valid path
		walk_path(path)
		# Show destination marker at grid cell center
		_dest_marker.global_position = Vector3(snapped.x, 0.05, snapped.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
	else:
		# Straight-line fallback (no grid)
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
		if game_state.command_move_to_cell(char_id, cell):
			var ch: Dictionary = game_state.characters[char_id]
			_auto_path = ch.path.duplicate()
			_auto_path_index = ch.path_index
			_moving = true
		return
	if not grid_world:
		return
	var current_cell := grid_world.world_to_grid(global_position)
	var path := grid_world.find_path(current_cell, cell)
	if not path.is_empty():
		walk_path(path)

func _physics_process(delta: float) -> void:
	# GameState-driven movement: read path from GameState, use move_and_slide, write back
	if game_state and char_id != "" and game_state.characters.has(char_id):
		var ch: Dictionary = game_state.characters[char_id]
		if ch.is_moving and not ch.path.is_empty() and ch.path_index < ch.path.size():
			var waypoint: Vector3 = ch.path[ch.path_index]
			var dir := (waypoint - global_position)
			dir.y = 0
			if dir.length() < 0.2:
				# Let GameState advance the path index
				game_state.update_position(char_id, global_position)
				if not game_state.is_moving(char_id):
					_moving = false
					velocity = Vector3.ZERO
					auto_path_complete.emit()
			else:
				velocity = dir.normalized() * move_speed
				move_and_slide()
				game_state.update_position(char_id, global_position)
			# Keep local path in sync for line drawing
			_auto_path = ch.path.duplicate()
			_auto_path_index = ch.path_index
			_update_path_line()
			_update_dest_marker(delta)
			return
		elif not ch.is_moving and _moving:
			_moving = false
			velocity = Vector3.ZERO
			auto_path_complete.emit()
		_update_dest_marker(delta)
		_update_path_line()
		return

	# Auto-path movement (scripted, no GameState)
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
				return
		else:
			velocity = dir.normalized() * move_speed
			move_and_slide()
		_update_path_line()
		return

	# Click-to-move
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

func _update_dest_marker(delta: float) -> void:
	if _moving:
		# Pulse gently
		var pulse := 0.3 + sin(Time.get_ticks_msec() * 0.004) * 0.15
		_dest_marker_mat.albedo_color.a = pulse
		# Shrink as character approaches
		var dist := Vector2(
			global_position.x - _dest_marker.global_position.x,
			global_position.z - _dest_marker.global_position.z
		).length()
		var s := clampf(dist / 3.0, 0.3, 1.2)
		_dest_marker.scale = Vector3(s, s, s)
	else:
		# Fade out
		_dest_marker_mat.albedo_color.a = maxf(0, _dest_marker_mat.albedo_color.a - delta * 2.0)

func _update_path_line() -> void:
	if not _moving and _auto_path.is_empty():
		_path_line.mesh = null
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var from_pos := global_position
	from_pos.y = 0.08  # Slightly above ground

	if _auto_path.size() > 0:
		# Draw line through auto-path waypoints
		for i in range(_auto_path_index, _auto_path.size()):
			var wp := _auto_path[i]
			var to_pos := Vector3(wp.x, 0.08, wp.z)
			im.surface_add_vertex(from_pos)
			im.surface_add_vertex(to_pos)
			from_pos = to_pos
	else:
		# Draw line to click target
		var to_pos := Vector3(_target_pos.x, 0.08, _target_pos.z)
		im.surface_add_vertex(from_pos)
		im.surface_add_vertex(to_pos)

	im.surface_end()
	_path_line.mesh = im

## Set an auto-path for scripted movement
func walk_to(pos: Vector3) -> void:
	_auto_path = [pos]
	_auto_path_index = 0
	_moving = true

## Walk along a series of waypoints
func walk_path(path: Array[Vector3]) -> void:
	_auto_path = path
	_auto_path_index = 0
	_moving = true

func set_move_enabled(enabled: bool) -> void:
	_move_enabled = enabled
	if not enabled:
		_moving = false
		velocity = Vector3.ZERO
		_auto_path.clear()

func is_moving() -> bool:
	return _moving
