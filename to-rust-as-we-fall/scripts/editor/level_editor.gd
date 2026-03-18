extends Node3D

## Level editor with auto-connecting pipes, multiple block types, and rotation.

@onready var grid_map: GridMap = $GridMap
@onready var camera: Camera3D = $EditorCamera
@onready var cursor: MeshInstance3D = $Cursor
@onready var floor_plane: StaticBody3D = $FloorPlane

const BLOCK_NAMES: Array[String] = [
	"Wall", "Floor", "Pipe", "Flora",
	"Iron Bloom", "Terminal", "Shelter", "Membrane"
]
const BLOCK_KEYS: Array[String] = [
	"1", "2", "3", "4", "5", "6", "7", "8"
]
const BLOCK_COLORS: Array[Color] = [
	Color(0.22, 0.16, 0.12),
	Color(0.1, 0.1, 0.12),
	Color(0.15, 0.35, 0.32),
	Color(0.1, 0.4, 0.25),
	Color(0.45, 0.15, 0.05),
	Color(0.08, 0.18, 0.28),
	Color(0.12, 0.18, 0.3),
	Color(0.3, 0.2, 0.25),
]

const PIPE_TOOL_INDEX := 2  # Palette index for the pipe tool

var current_item: int = 0
var current_orientation: int = 0

const Y_ROTATIONS: Array[int] = [0, 22, 10, 16]
var _rotation_index: int = 0

var _cursor_meshes: Array[Mesh] = []
var _cursor_mat: StandardMaterial3D
var _last_cursor_cell: Vector3i = Vector3i(-9999, -9999, -9999)

var _right_pressed: bool = false
var _right_press_pos: Vector2 = Vector2.ZERO

signal block_changed(index: int)
signal orientation_changed(rot: int)

func _ready() -> void:
	# Generate pipe variants into the MeshLibrary
	PipeBuilder.build(grid_map.mesh_library)

	_cursor_mat = StandardMaterial3D.new()
	_cursor_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.35)
	_cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor.material_override = _cursor_mat

	_build_cursor_meshes()
	_apply_cursor_mesh()

func _build_cursor_meshes() -> void:
	var lib := grid_map.mesh_library
	if not lib:
		return
	_cursor_meshes.clear()
	for i in range(lib.get_last_unused_item_id()):
		var src_mesh := lib.get_item_mesh(i)
		if src_mesh:
			_cursor_meshes.append(src_mesh.duplicate())
		else:
			_cursor_meshes.append(null)

func _apply_cursor_mesh() -> void:
	if current_item == PIPE_TOOL_INDEX:
		# Pipe cursor updates dynamically in _update_cursor
		cursor.basis = Basis.IDENTITY
		return
	if current_item < _cursor_meshes.size() and _cursor_meshes[current_item]:
		cursor.mesh = _cursor_meshes[current_item]
	else:
		var box := BoxMesh.new()
		box.size = Vector3(1, 1, 1)
		cursor.mesh = box
	cursor.material_override = _cursor_mat
	cursor.basis = _orientation_to_basis(current_orientation)

func _orientation_to_basis(ort: int) -> Basis:
	match ort:
		22: return Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
		10: return Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
		16: return Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		_: return Basis.IDENTITY

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_place_block()
			get_viewport().set_input_as_handled()

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_pressed = true
				_right_press_pos = mb.position
			else:
				if _right_pressed and mb.position.distance_to(_right_press_pos) < 5.0:
					_erase_block()
				_right_pressed = false

		if mb.pressed and mb.shift_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cycle_block(-1)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_block(1)
				get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc >= KEY_1 and kc <= KEY_8:
			select_block(kc - KEY_1)
		elif kc == KEY_R:
			_rotate()
		elif kc == KEY_Q:
			_cycle_block(-1)
		elif kc == KEY_E:
			_cycle_block(1)

func _process(_delta: float) -> void:
	_update_cursor()

# --- Block selection ---

func select_block(index: int) -> void:
	if index < 0 or index >= BLOCK_NAMES.size():
		return
	current_item = index
	_apply_cursor_mesh()
	block_changed.emit(current_item)

func _cycle_block(dir: int) -> void:
	select_block((current_item + dir + BLOCK_NAMES.size()) % BLOCK_NAMES.size())

func _rotate() -> void:
	_rotation_index = (_rotation_index + 1) % Y_ROTATIONS.size()
	current_orientation = Y_ROTATIONS[_rotation_index]
	_apply_cursor_mesh()
	orientation_changed.emit(current_orientation)

# --- Raycasting ---

func _raycast_mouse() -> Dictionary:
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	return space.intersect_ray(query)

func _update_cursor() -> void:
	var result := _raycast_mouse()
	if result.is_empty():
		cursor.visible = false
		return

	var place_pos := _get_place_position(result)
	cursor.visible = true
	cursor.global_position = Vector3(place_pos.x + 0.5, place_pos.y + 0.5, place_pos.z + 0.5)

	# Dynamic pipe preview — show what the pipe would look like with neighbors
	if current_item == PIPE_TOOL_INDEX and place_pos != _last_cursor_cell:
		_last_cursor_cell = place_pos
		var mask := _get_pipe_mask(place_pos)
		if mask >= 0 and mask < PipeBuilder.pipe_meshes.size():
			cursor.mesh = PipeBuilder.pipe_meshes[mask]
			cursor.material_override = _cursor_mat
		cursor.basis = Basis.IDENTITY

func _get_place_position(result: Dictionary) -> Vector3i:
	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	if result.collider == floor_plane:
		return Vector3i(floori(hit_pos.x), 0, floori(hit_pos.z))
	var adjacent := hit_pos + hit_normal * 0.5
	return Vector3i(floori(adjacent.x), floori(adjacent.y), floori(adjacent.z))

# --- Place / Erase ---

func _place_block() -> void:
	var result := _raycast_mouse()
	if result.is_empty():
		return
	var place_pos := _get_place_position(result)
	if place_pos.y < 0:
		return

	var prev_item := grid_map.get_cell_item(place_pos)
	var was_pipe := PipeBuilder.is_pipe(prev_item)

	if current_item == PIPE_TOOL_INDEX:
		# Auto-connect pipe
		var mask := _get_pipe_mask(place_pos)
		grid_map.set_cell_item(place_pos, PipeBuilder.PIPE_ID_OFFSET + mask)
		_update_pipe_neighbors(place_pos)
	else:
		grid_map.set_cell_item(place_pos, current_item, current_orientation)
		# If we overwrote a pipe, update its former neighbors
		if was_pipe:
			_update_pipe_neighbors(place_pos)

func _erase_block() -> void:
	var result := _raycast_mouse()
	if result.is_empty():
		return
	var hit_pos: Vector3 = result.position
	var hit_normal: Vector3 = result.normal
	var inside := hit_pos - hit_normal * 0.5
	var cell := Vector3i(floori(inside.x), floori(inside.y), floori(inside.z))
	var item := grid_map.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return
	var was_pipe := PipeBuilder.is_pipe(item)
	grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	if was_pipe:
		_update_pipe_neighbors(cell)

# --- Pipe auto-connection ---

func _get_pipe_mask(cell: Vector3i) -> int:
	var mask := 0
	for i in range(PipeBuilder.DIR_OFFSETS.size()):
		var neighbor := cell + PipeBuilder.DIR_OFFSETS[i]
		if PipeBuilder.is_pipe(grid_map.get_cell_item(neighbor)):
			mask |= (1 << i)
	return mask

func _update_pipe_at(cell: Vector3i) -> void:
	if not PipeBuilder.is_pipe(grid_map.get_cell_item(cell)):
		return
	var mask := _get_pipe_mask(cell)
	grid_map.set_cell_item(cell, PipeBuilder.PIPE_ID_OFFSET + mask)

func _update_pipe_neighbors(center: Vector3i) -> void:
	for offset in PipeBuilder.DIR_OFFSETS:
		_update_pipe_at(center + offset)
