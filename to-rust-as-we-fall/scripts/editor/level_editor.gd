extends Node3D

## Level editor with auto-connecting pipes, multiple block types, and rotation.

@onready var grid_map: GridMap = $GridMap
@onready var camera: Camera3D = $EditorCamera
@onready var cursor: MeshInstance3D = $Cursor
@onready var floor_plane: StaticBody3D = $FloorPlane

const PLAN_BROWSER_CONTRACT_ID := "level_editor_plan_graybox_v1"
const PLAN_PREVIEW_ROOT_NAME := "PlanPreviewRoot"
const StretchGeneratorScript := preload("res://scripts/generation/stretch_generator.gd")
const StretchArchetypeCatalogScript := preload("res://scripts/generation/stretch_archetype_catalog.gd")
const StretchGenerationPlaytestLoopScript := preload("res://scripts/generation/stretch_generation_playtest_loop.gd")
const GENERATED_STRETCH_SPEC_PATH := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
const GENERATED_CHAIN_NESTED_POC_SPEC_PATH := "res://data/generated_stretches/generated_chain_nested_poc_shelter_2_to_3.json"
const GENERATED_RANDOM_WALK_POC_SPEC_PATH := "res://data/generated_stretches/generated_random_walk_poc_shelter_3_to_4.json"
const GENERATED_STRETCH_CHUNK_SCENE_PATH := "res://scenes/fragments/chunks/generated_stretch_chunk.tscn"
const GENERATED_STRETCH_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const GENERATED_CHAIN_NESTED_POC_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const GENERATED_RANDOM_WALK_POC_PREVIEW_SCENE_PATH := "res://scenes/fragments/fragment_preview.tscn"
const PLAN_SCENES := [
	{
		"id": "endo_junction_stretch",
		"title": "Endo's Junction -> Shelter 1",
		"chunk_scene": "res://scenes/fragments/chunks/endo_junction_stretch_chunk.tscn",
		"preview_scene": "res://scenes/fragments/fragment_preview.tscn",
	},
	{
		"id": "stacks",
		"title": "Processing Stacks",
		"chunk_scene": "res://scenes/fragments/chunks/stacks_fragment_chunk.tscn",
		"preview_scene": "res://scenes/fragments/fragment_preview.tscn",
	},
	{
		"id": "mother_flure",
		"title": "Mother Flure",
		"chunk_scene": "res://scenes/fragments/chunks/mother_flure_chunk.tscn",
		"preview_scene": "res://scenes/fragments/fragment_preview.tscn",
	},
	{
		"id": "rings",
		"title": "Residential Rings",
		"chunk_scene": "res://scenes/fragments/chunks/rings_fragment_chunk.tscn",
		"preview_scene": "res://scenes/fragments/fragment_preview.tscn",
	},
	{
		"id": "lockout",
		"title": "Lockout",
		"chunk_scene": "res://scenes/fragments/chunks/lockout_fragment_chunk.tscn",
		"preview_scene": "res://scenes/fragments/fragment_preview.tscn",
	},
	{
		"id": "survival_range",
		"title": "Shelter-To-Shelter Range",
		"chunk_scene": "res://scenes/fragments/chunks/survival_range_chunk.tscn",
		"preview_scene": "res://scenes/fragments/fragment_preview.tscn",
	},
	{
		"id": "generated_teaching_channels_shelter_1_to_2",
		"title": "Generated: Teaching Channels Shelter 1 -> 2",
		"chunk_scene": GENERATED_STRETCH_CHUNK_SCENE_PATH,
		"preview_scene": GENERATED_STRETCH_PREVIEW_SCENE_PATH,
		"generated": true,
		"spec_path": GENERATED_STRETCH_SPEC_PATH,
	},
	{
		"id": "generated_chain_nested_poc_shelter_2_to_3",
		"title": "Generated: Chain/Nested POC Shelter 2 -> 3",
		"chunk_scene": GENERATED_STRETCH_CHUNK_SCENE_PATH,
		"preview_scene": GENERATED_CHAIN_NESTED_POC_PREVIEW_SCENE_PATH,
		"generated": true,
		"spec_path": GENERATED_CHAIN_NESTED_POC_SPEC_PATH,
	},
	{
		"id": "generated_random_walk_poc_shelter_3_to_4",
		"title": "Generated: Random Walk POC Shelter 3 -> 4",
		"chunk_scene": GENERATED_STRETCH_CHUNK_SCENE_PATH,
		"preview_scene": GENERATED_RANDOM_WALK_POC_PREVIEW_SCENE_PATH,
		"generated": true,
		"spec_path": GENERATED_RANDOM_WALK_POC_SPEC_PATH,
	},
]

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

@export var load_plan_on_start := true

var current_item: int = 0
var current_orientation: int = 0

const Y_ROTATIONS: Array[int] = [0, 22, 10, 16]
var _rotation_index: int = 0

var _cursor_meshes: Array[Mesh] = []
var _cursor_mat: StandardMaterial3D
var _last_cursor_cell: Vector3i = Vector3i(-9999, -9999, -9999)

var _right_pressed: bool = false
var _right_press_pos: Vector2 = Vector2.ZERO

var _plan_preview_root: Node3D
var _active_plan_instance: Node3D
var _active_plan_index := -1
var _active_plan_state: Dictionary = {}
var _generation_state: Dictionary = {}

signal block_changed(index: int)
signal orientation_changed(rot: int)
signal plan_changed(state: Dictionary)
signal plan_visibility_changed(visible: bool)

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
	_ensure_plan_preview_root()
	if load_plan_on_start:
		show_plan_scene(0)

func _build_cursor_meshes() -> void:
	var lib := grid_map.mesh_library
	if not lib:
		return
	_cursor_meshes.clear()
	var item_ids := {}
	for item_id in lib.get_item_list():
		item_ids[int(item_id)] = true
	for i in range(lib.get_last_unused_item_id()):
		var src_mesh: Mesh = lib.get_item_mesh(i) if item_ids.has(i) else null
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
		elif kc == KEY_P:
			toggle_plan_visibility()
		elif kc == KEY_BRACKETLEFT:
			cycle_plan_scene(-1)
		elif kc == KEY_BRACKETRIGHT:
			cycle_plan_scene(1)
		elif kc == KEY_F:
			focus_active_plan()

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

	# Dynamic pipe preview with neighbors.
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

# --- Scene plan / graybox browser ---

func get_editor_plan_entries() -> Array:
	var entries := []
	for i in range(PLAN_SCENES.size()):
		var entry: Dictionary = PLAN_SCENES[i].duplicate(true)
		entry["index"] = i
		entries.append(entry)
	return entries

func show_plan_scene(plan: Variant) -> void:
	var index := _resolve_plan_index(plan)
	if index < 0 or index >= PLAN_SCENES.size():
		return

	_ensure_plan_preview_root()
	_clear_active_plan_instance()

	var entry: Dictionary = PLAN_SCENES[index]
	var chunk_path := str(entry.get("chunk_scene", ""))
	var packed_scene: PackedScene = load(chunk_path)
	if packed_scene == null:
		_active_plan_index = -1
		_active_plan_state = {
			"contract_id": PLAN_BROWSER_CONTRACT_ID,
			"loaded": false,
			"error": "Unable to load %s" % chunk_path,
		}
		plan_changed.emit(get_editor_plan_state())
		return

	var instance := packed_scene.instantiate() as Node3D
	if instance == null:
		_active_plan_index = -1
		_active_plan_state = {
			"contract_id": PLAN_BROWSER_CONTRACT_ID,
			"loaded": false,
			"error": "Unable to instantiate %s" % chunk_path,
		}
		plan_changed.emit(get_editor_plan_state())
		return

	instance.name = "PlanGraybox_%s" % str(entry.get("id", index))
	_configure_generated_plan_instance(instance, entry)
	_plan_preview_root.add_child(instance, true)
	_active_plan_instance = instance
	_active_plan_index = index

	var anchors := _active_plan_anchors()
	_build_plan_anchor_markers(instance, anchors)
	_make_plan_read_only(instance)
	_active_plan_state = _build_plan_state(entry, anchors)
	focus_active_plan()
	plan_changed.emit(get_editor_plan_state())

func get_generation_palette() -> Dictionary:
	var catalog := StretchArchetypeCatalogScript.new()
	return {
		"valid": bool(catalog.validate().get("valid", false)),
		"archetypes": catalog.get_archetype_ids(),
		"flora": catalog.get_content_keys("flora"),
		"enemies": catalog.get_content_keys("enemies"),
		"structures": catalog.get_content_keys("structures"),
	}

func generate_stretch_plan(settings: Dictionary) -> Dictionary:
	var spec := StretchGeneratorScript.generate(settings)
	_generation_state = {
		"last_action": "generate",
		"success": bool(spec.get("success", false)),
		"spec_id": str(spec.get("id", "")),
		"last_spec": spec.duplicate(true),
		"errors": spec.get("validation", {}).get("errors", []),
		"warnings": spec.get("validation", {}).get("warnings", []),
	}
	return spec

func generate_and_playtest_stretch(settings: Dictionary) -> Dictionary:
	var loop = StretchGenerationPlaytestLoopScript.new()
	var result: Dictionary = await loop.generate_and_playtest(settings, get_tree())
	_generation_state = {
		"last_action": "generate_and_playtest",
		"success": bool(result.get("success", false)),
		"spec_id": str(result.get("spec_id", "")),
		"last_spec": result.get("spec", {}).duplicate(true),
		"last_playtest": result.duplicate(true),
		"errors": result.get("errors", []),
		"warnings": result.get("warnings", []),
	}
	return result

func save_generated_stretch(spec: Dictionary, path := "") -> String:
	if spec.is_empty():
		_generation_state = {
			"last_action": "save",
			"success": false,
			"error": "empty_spec",
		}
		return ""
	var target_path := path
	if target_path == "":
		target_path = "res://data/generated_stretches/%s.json" % _sanitize_generated_id(str(spec.get("id", "generated_stretch")))
	var saved := StretchGeneratorScript.save_spec(spec, target_path)
	_generation_state = {
		"last_action": "save",
		"success": saved,
		"spec_id": str(spec.get("id", "")),
		"path": target_path,
	}
	return target_path if saved else ""

func show_generated_stretch(spec_or_path: Variant) -> void:
	_ensure_plan_preview_root()
	_clear_active_plan_instance()
	var packed_scene: PackedScene = load(GENERATED_STRETCH_CHUNK_SCENE_PATH)
	if packed_scene == null:
		_active_plan_index = -1
		_active_plan_state = {
			"contract_id": PLAN_BROWSER_CONTRACT_ID,
			"loaded": false,
			"error": "Unable to load %s" % GENERATED_STRETCH_CHUNK_SCENE_PATH,
		}
		plan_changed.emit(get_editor_plan_state())
		return
	var instance := packed_scene.instantiate() as Node3D
	if instance == null:
		_active_plan_index = -1
		_active_plan_state = {
			"contract_id": PLAN_BROWSER_CONTRACT_ID,
			"loaded": false,
			"error": "Unable to instantiate generated stretch chunk",
		}
		plan_changed.emit(get_editor_plan_state())
		return
	var entry := {
		"id": "generated_runtime",
		"title": "Generated Runtime Stretch",
		"chunk_scene": GENERATED_STRETCH_CHUNK_SCENE_PATH,
		"preview_scene": GENERATED_STRETCH_PREVIEW_SCENE_PATH,
		"generated": true,
	}
	if spec_or_path is String:
		entry["spec_path"] = str(spec_or_path)
	elif spec_or_path is Dictionary:
		entry["spec"] = (spec_or_path as Dictionary).duplicate(true)
	instance.name = "PlanGraybox_generated_runtime"
	_configure_generated_plan_instance(instance, entry)
	_plan_preview_root.add_child(instance, true)
	_active_plan_instance = instance
	_active_plan_index = -1
	var anchors := _active_plan_anchors()
	_build_plan_anchor_markers(instance, anchors)
	_make_plan_read_only(instance)
	_active_plan_state = _build_plan_state(entry, anchors)
	focus_active_plan()
	plan_changed.emit(get_editor_plan_state())

func get_generation_state() -> Dictionary:
	var state := _generation_state.duplicate(true)
	if _active_plan_instance != null and _active_plan_instance.has_method("get_preview_state"):
		var preview: Variant = _active_plan_instance.call("get_preview_state")
		if preview is Dictionary:
			state["active_preview"] = preview
	return state

func clear_plan_scene() -> void:
	_clear_active_plan_instance()
	_active_plan_index = -1
	_active_plan_state = {}
	plan_changed.emit(get_editor_plan_state())

func cycle_plan_scene(direction: int) -> void:
	if PLAN_SCENES.is_empty():
		return
	var next_index := 0
	if _active_plan_index >= 0:
		next_index = (_active_plan_index + direction + PLAN_SCENES.size()) % PLAN_SCENES.size()
	show_plan_scene(next_index)

func toggle_plan_visibility() -> void:
	_ensure_plan_preview_root()
	_plan_preview_root.visible = not _plan_preview_root.visible
	plan_visibility_changed.emit(_plan_preview_root.visible)
	plan_changed.emit(get_editor_plan_state())

func set_plan_visibility(visible: bool) -> void:
	_ensure_plan_preview_root()
	_plan_preview_root.visible = visible
	plan_visibility_changed.emit(_plan_preview_root.visible)
	plan_changed.emit(get_editor_plan_state())

func focus_active_plan() -> void:
	if _active_plan_instance == null:
		return
	var bounds := _calculate_plan_bounds()
	var focus := bounds.get_center()
	var size := bounds.size
	var focus_distance := maxf(18.0, maxf(size.x, size.z) * 0.72)
	if camera != null and camera.has_method("focus_on"):
		camera.call("focus_on", focus, focus_distance)

func get_editor_plan_state() -> Dictionary:
	_ensure_plan_preview_root()
	var state := _active_plan_state.duplicate(true)
	state["contract_id"] = PLAN_BROWSER_CONTRACT_ID
	state["plan_count"] = PLAN_SCENES.size()
	state["visible"] = _plan_preview_root.visible
	state["loaded"] = _active_plan_instance != null
	state["active_plan_index"] = _active_plan_index
	state["collisions_disabled"] = _active_plan_collisions_disabled()
	return state

func _ensure_plan_preview_root() -> void:
	if _plan_preview_root != null:
		return
	_plan_preview_root = get_node_or_null(PLAN_PREVIEW_ROOT_NAME) as Node3D
	if _plan_preview_root == null:
		_plan_preview_root = Node3D.new()
		_plan_preview_root.name = PLAN_PREVIEW_ROOT_NAME
		add_child(_plan_preview_root, true)

func _resolve_plan_index(plan: Variant) -> int:
	if plan is int:
		return int(plan)
	if plan is String:
		var plan_id := str(plan)
		for i in range(PLAN_SCENES.size()):
			if str(PLAN_SCENES[i].get("id", "")) == plan_id:
				return i
	return -1

func _clear_active_plan_instance() -> void:
	if _active_plan_instance != null:
		_active_plan_instance.free()
	_active_plan_instance = null

func _configure_generated_plan_instance(instance: Node, entry: Dictionary) -> void:
	if not bool(entry.get("generated", false)):
		return
	if instance == null or not instance.has_method("configure_chunk"):
		return
	var config := {}
	if entry.has("spec"):
		config["spec"] = (entry.get("spec", {}) as Dictionary).duplicate(true)
	elif entry.has("spec_path"):
		config["spec_path"] = str(entry.get("spec_path", GENERATED_STRETCH_SPEC_PATH))
	else:
		config["spec_path"] = GENERATED_STRETCH_SPEC_PATH
	instance.call("configure_chunk", config)

func _active_plan_anchors() -> Dictionary:
	if _active_plan_instance != null and _active_plan_instance.has_method("get_preview_anchors"):
		var anchors: Variant = _active_plan_instance.call("get_preview_anchors")
		if anchors is Dictionary:
			return (anchors as Dictionary).duplicate(true)
	return {}

func _active_plan_world_slot() -> Dictionary:
	if _active_plan_instance != null and _active_plan_instance.has_method("get_world_slot"):
		var slot: Variant = _active_plan_instance.call("get_world_slot")
		if slot is Dictionary:
			return (slot as Dictionary).duplicate(true)
	return {}

func _active_plan_title(entry: Dictionary) -> String:
	if _active_plan_instance != null and _active_plan_instance.has_method("get_scene_title"):
		return str(_active_plan_instance.call("get_scene_title"))
	return str(entry.get("title", entry.get("id", "Plan")))

func _active_plan_help() -> String:
	if _active_plan_instance != null and _active_plan_instance.has_method("get_scene_help"):
		return str(_active_plan_instance.call("get_scene_help"))
	return ""

func _active_plan_generation_state() -> Dictionary:
	if _active_plan_instance != null and _active_plan_instance.has_method("get_preview_state"):
		var state: Variant = _active_plan_instance.call("get_preview_state")
		if state is Dictionary and (state as Dictionary).has("generation"):
			return ((state as Dictionary).get("generation", {}) as Dictionary).duplicate(true)
	return {}

func _active_plan_graybox_state() -> Dictionary:
	if _active_plan_instance != null and _active_plan_instance.has_method("get_graybox_state"):
		var state: Variant = _active_plan_instance.call("get_graybox_state")
		if state is Dictionary:
			return (state as Dictionary).duplicate(true)
	if _active_plan_instance != null and _active_plan_instance.has_method("get_preview_state"):
		var preview: Variant = _active_plan_instance.call("get_preview_state")
		if preview is Dictionary and (preview as Dictionary).has("graybox"):
			return ((preview as Dictionary).get("graybox", {}) as Dictionary).duplicate(true)
	return {}

func _build_plan_state(entry: Dictionary, anchors: Dictionary) -> Dictionary:
	var bounds := _calculate_plan_bounds()
	var graybox_state := _active_plan_graybox_state()
	return {
		"contract_id": PLAN_BROWSER_CONTRACT_ID,
		"active_plan_id": str(entry.get("id", "")),
		"active_plan_title": _active_plan_title(entry),
		"chunk_scene": str(entry.get("chunk_scene", "")),
		"preview_scene": str(entry.get("preview_scene", "")),
		"generated": bool(entry.get("generated", false)),
		"spec_path": str(entry.get("spec_path", "")),
		"generation": _active_plan_generation_state(),
		"graybox": graybox_state,
		"graybox_contract_id": str(graybox_state.get("contract_id", "")),
		"help": _active_plan_help(),
		"world_slot": _active_plan_world_slot(),
		"anchors": anchors.duplicate(true),
		"anchor_count": anchors.size(),
		"bounds_center": bounds.get_center(),
		"bounds_size": bounds.size,
	}

func _sanitize_generated_id(raw: String) -> String:
	var text := raw.strip_edges().to_lower()
	var result := ""
	for i in range(text.length()):
		var c := text[i]
		var code := c.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 97 and code <= 122):
			result += c
		elif c in ["-", "_"]:
			result += c
		elif result.length() > 0 and not result.ends_with("_"):
			result += "_"
	while result.begins_with("_"):
		result = result.substr(1)
	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)
	return result if result != "" else "generated_stretch"

func _build_plan_anchor_markers(parent: Node3D, anchors: Dictionary) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "PlanAnchorMarkers"
	parent.add_child(marker_root, true)

	for anchor_name in anchors.keys():
		var raw_position: Variant = anchors[anchor_name]
		if not (raw_position is Vector3):
			continue
		_add_plan_anchor_marker(marker_root, str(anchor_name), raw_position as Vector3)

func _add_plan_anchor_marker(parent: Node3D, anchor_name: String, position: Vector3) -> void:
	var color := _plan_anchor_color(anchor_name)
	var marker := MeshInstance3D.new()
	marker.name = "PlanAnchor_%s" % anchor_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	marker.mesh = sphere
	marker.position = position + Vector3(0.0, 0.55, 0.0)
	marker.material_override = _make_plan_material(color)
	parent.add_child(marker)

	var label := Label3D.new()
	label.name = "PlanAnchorLabel_%s" % anchor_name
	label.text = anchor_name.to_upper()
	label.position = position + Vector3(0.0, 1.35, 0.0)
	label.pixel_size = 0.012
	label.font_size = 42
	label.modulate = color.lightened(0.25)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.72)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)

func _plan_anchor_color(anchor_name: String) -> Color:
	match anchor_name:
		"aster":
			return Color(0.36, 0.64, 1.0, 0.82)
		"peris":
			return Color(0.64, 0.82, 0.48, 0.82)
		"endo":
			return Color(0.92, 0.66, 0.32, 0.82)
		_:
			return Color(0.74, 0.9, 1.0, 0.74)

func _make_plan_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.28
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _make_plan_read_only(root: Node) -> void:
	root.process_mode = Node.PROCESS_MODE_DISABLED
	for node in root.find_children("*", "", true, false):
		if node is CollisionObject3D:
			var collision := node as CollisionObject3D
			collision.collision_layer = 0
			collision.collision_mask = 0
			collision.input_ray_pickable = false
		if node is Area3D:
			var area := node as Area3D
			area.monitoring = false
			area.monitorable = false

func _active_plan_collisions_disabled() -> bool:
	if _active_plan_instance == null:
		return true
	for node in _active_plan_instance.find_children("*", "", true, false):
		if node is CollisionObject3D:
			var collision := node as CollisionObject3D
			if collision.collision_layer != 0 or collision.collision_mask != 0 or collision.input_ray_pickable:
				return false
	return true

func _calculate_plan_bounds() -> AABB:
	var anchors := _active_plan_anchors()
	var has_point := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	for raw_position in anchors.values():
		if not (raw_position is Vector3):
			continue
		var position := raw_position as Vector3
		if not has_point:
			min_point = position
			max_point = position
			has_point = true
		else:
			min_point = min_point.min(position)
			max_point = max_point.max(position)
	if has_point:
		var size := max_point - min_point
		return AABB(min_point, Vector3(maxf(size.x, 1.0), maxf(size.y, 1.0), maxf(size.z, 1.0)))
	return AABB(Vector3.ZERO, Vector3(20.0, 1.0, 20.0))
