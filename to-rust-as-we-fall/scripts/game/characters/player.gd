@tool
extends CharacterBody3D

const CHARACTER_INTERACTION_CONTROLLER := preload("res://scripts/game/characters/character_interaction_controller.gd")

## Click-to-move character view. Prefer GameState; fallback moves locally.

@export var move_speed := 3.0
@export var run_speed := 6.0
@export var color := Color(0.29, 0.62, 1.0)  # Aster blue

## Optional A* grid.
var grid_world: GridWorld

## Optional authoritative state.
var game_state: GameState
var char_id := ""  ## Character ID in GameState (e.g. "aster")

var _target_pos: Vector3
var _moving := false
var _move_enabled := true
## "move" = a ground click moves the player; "select" = a ground click only
## emits ground_clicked for a sequence to interpret (e.g. "click the target").
var _click_mode := "move"
var _running := false
var _auto_path: Array[Vector3] = []
var _auto_path_index := 0
var _interaction_controller: CharacterInteractionController
var _pending_interaction_roots: Array[Node] = []
var _pending_interaction_targets: Array[Node] = []

var _ability_marker: MeshInstance3D
var _ability_marker_mat: StandardMaterial3D

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label3D

var _dest_marker: MeshInstance3D
var _dest_marker_mat: StandardMaterial3D

var _path_renderer: PathRenderer

signal arrived()
signal auto_path_complete()
## Emitted on every left-click that hits the ground, with the world position.
## Sequences listen to this instead of running their own ground raycast.
signal ground_clicked(world_pos: Vector3)

func _ready() -> void:
	_target_pos = global_position

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

	# The movement-path line is the shared PathRenderer, anchored to this body so the
	# line starts exactly where the mesh is. game_state / char_id are forwarded once
	# they're assigned (see _update_path_line).
	_path_renderer = PathRenderer.new()
	_path_renderer.setup(game_state, char_id, color, self)
	add_child(_path_renderer)

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

	_interaction_controller = CHARACTER_INTERACTION_CONTROLLER.new()
	_interaction_controller.name = "CharacterInteractionController"
	add_child(_interaction_controller)
	_interaction_controller.setup(self)
	for root in _pending_interaction_roots:
		_interaction_controller.bind_interaction_root(root)
	for target in _pending_interaction_targets:
		_interaction_controller.bind_interaction_target(target)
	_pending_interaction_roots.clear()
	_pending_interaction_targets.clear()

	# Connect arrival signal if GameState is available
	if game_state:
		game_state.character_arrived.connect(_on_gs_arrived)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	# Select mode: a click only reports the world position; the sequence decides
	# what it means (e.g. "is that near the target?"). No movement.
	if _click_mode == "select":
		var hit_sel := _raycast_ground(mb.position)
		if hit_sel != Vector3.INF:
			ground_clicked.emit(hit_sel)
		return

	# Move mode (default): click-to-move.
	if not _move_enabled:
		return
	if _auto_path.size() > 0 and not (game_state and char_id != ""):
		return  # Don't interrupt fallback auto-path with clicks
	var hit := _raycast_ground(mb.position)
	if hit != Vector3.INF:
		ground_clicked.emit(hit)
		_set_click_target(hit)

## Switch how a ground click is interpreted: "move" (default) or "select".
func set_click_mode(mode: String) -> void:
	_click_mode = mode if mode in ["move", "select"] else "move"

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

## When true, a ground click moves the whole party (spread onto distinct cells)
## via the data layer rather than just this character — so a multi-select group
## move never stacks members on one cell.
var group_move := false

func _set_click_target(world_pos: Vector3, cancel_interaction := true) -> bool:
	if cancel_interaction and _interaction_controller != null:
		_interaction_controller.cancel_active_target()
	# Group move: one click moves the whole party. On a grid they spread onto
	# distinct cells; gridless (e.g. the elevator) they fan out around the clicked
	# point — either way every selected member gets a move, not just the active one.
	if group_move and game_state:
		if grid_world:
			var group_cell := grid_world.world_to_grid(world_pos)
			game_state.party_move_to_cell(group_cell)
			var group_snap := grid_world.grid_to_world(group_cell)
			_dest_marker.global_position = Vector3(group_snap.x, 0.05, group_snap.z)
		else:
			game_state.party_move_to_pos(world_pos)
			_dest_marker.global_position = Vector3(world_pos.x, world_pos.y + 0.05, world_pos.z)
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
		return true
	if game_state and char_id != "":
		if grid_world:
			var target_cell := grid_world.world_to_grid(world_pos)
			if not game_state.command_move_to_cell(char_id, target_cell):
				return false
			var snapped_pos := grid_world.grid_to_world(target_cell)
			_dest_marker.global_position = Vector3(snapped_pos.x, 0.05, snapped_pos.z)
		else:
			if not game_state.command_move_to_pos(char_id, world_pos):
				return false
			_dest_marker.global_position = Vector3(world_pos.x, world_pos.y + 0.05, world_pos.z)
		_moving = true
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
		return true

	if grid_world:
		var target_cell := grid_world.world_to_grid(world_pos)
		var current_cell := grid_world.world_to_grid(global_position)
		var snapped_pos := grid_world.grid_to_world(target_cell)
		var path := grid_world.find_path(current_cell, target_cell)
		if path.is_empty():
			return false
		walk_path(path)
		_dest_marker.global_position = Vector3(snapped_pos.x, 0.05, snapped_pos.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
	else:
		_target_pos = world_pos
		_moving = true
		_auto_path.clear()
		_auto_path_index = 0
		_dest_marker.global_position = Vector3(world_pos.x, world_pos.y + 0.05, world_pos.z)
		_dest_marker_mat.albedo_color.a = 0.6
		_dest_marker.scale = Vector3(1.2, 1.2, 1.2)
	return true

func move_to_world_position(world_pos: Vector3) -> bool:
	return _set_click_target(world_pos, false)

func bind_interaction_root(root: Node) -> void:
	if _interaction_controller != null:
		_interaction_controller.bind_interaction_root(root)
	elif root != null and not _pending_interaction_roots.has(root):
		_pending_interaction_roots.append(root)

func bind_interaction_target(target: Node) -> void:
	if _interaction_controller != null:
		_interaction_controller.bind_interaction_target(target)
	elif target != null and not _pending_interaction_targets.has(target):
		_pending_interaction_targets.append(target)

func cancel_interaction_target() -> void:
	if _interaction_controller != null:
		_interaction_controller.cancel_active_target()

## Walk to a grid cell.
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
	if game_state and char_id != "":
		if game_state.is_moving(char_id):
			var pos := game_state.get_position(char_id)
			if grid_world:
				global_position = Vector3(pos.x, global_position.y, pos.z)
			else:
				global_position = pos
			_moving = true
		elif _moving:
			_moving = false
			var pos := game_state.get_position(char_id)
			if grid_world:
				global_position = Vector3(pos.x, global_position.y, pos.z)
			else:
				global_position = pos
			velocity = Vector3.ZERO
			arrived.emit()
			auto_path_complete.emit()
		_update_dest_marker(delta)
		_update_path_line()
		return

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
		var pulse := 0.3 + sin(Time.get_ticks_msec() * 0.004) * 0.15  # @rendering_only — destination marker pulse
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
	var has_queued_ability := game_state and char_id != "" and game_state.has_queued_ability(char_id)
	if has_queued_ability:
		var qa_data: Dictionary = game_state._queued_abilities[char_id]
		_ability_marker.global_position = qa_data.target_pos + Vector3(0.0, 0.5, 0.0)
		var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.3  # @rendering_only — ability marker pulse
		_ability_marker_mat.albedo_color.a = pulse
	else:
		_ability_marker_mat.albedo_color.a = 0.0

	# The path line itself is drawn by the shared PathRenderer. Keep its inputs in
	# sync (game_state / char_id are assigned after _ready) and hand it the local
	# fallback path for the rare no-GameState case (editor / standalone previews).
	if _path_renderer == null:
		return
	_path_renderer.game_state = game_state
	_path_renderer.char_id = char_id
	_path_renderer.color = color
	_path_renderer.set_running(_running)
	if game_state and char_id != "":
		_path_renderer.clear_explicit_path()
	elif _auto_path.size() > 0:
		_path_renderer.set_explicit_path(_auto_path, _auto_path_index)
	elif _moving:
		_path_renderer.set_explicit_path([_target_pos], 0)
	else:
		_path_renderer.clear_explicit_path()

## Walk to a world position.
func walk_to(pos: Vector3) -> void:
	if game_state and char_id != "":
		game_state.command_move_to_pos(char_id, pos)
		_moving = true
		return
	_auto_path = [pos]
	_auto_path_index = 0
	_moving = true

## Walk through waypoints.
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

func is_move_enabled() -> bool:
	return _move_enabled

func is_moving() -> bool:
	if game_state and char_id != "":
		return game_state.is_moving(char_id)
	return _moving

func set_running(running: bool) -> void:
	_running = running
	if _mesh:
		if running:
			_mesh.rotation.x = -0.15
			_mesh.scale = Vector3(0.9, 1.1, 0.9)
		else:
			_mesh.rotation.x = 0.0
			_mesh.scale = Vector3.ONE
	if _dest_marker_mat:
		if running:
			_dest_marker_mat.albedo_color = Color(1.0, 0.6, 0.2, _dest_marker_mat.albedo_color.a)
		else:
			_dest_marker_mat.albedo_color = Color(color.r, color.g, color.b, _dest_marker_mat.albedo_color.a)
