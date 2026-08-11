class_name FloraMemoryMarks
extends Node3D
## PERIS'S MEMORY OF THE OVERLOOK — the WHERE register's first canon slice
## (CHANNELS_DESIGN: she read the flora from the entry bridge, so the marks
## stay in her overlay even where the party can't currently see them). A
## scene-level render layer (the managers pattern): while the Peris overlay
## is ACTIVE, every position the scene's chunk remembers (its
## `get_peris_flora_marks()` data getter — empty until the overlook happened)
## shows a small floating diamond in her register's green, warped through the
## coord map. Purely cosmetic: reads the chunk + GameState, writes nothing.
## Marks are memory, not solve-data: they say WHERE green lives, never when
## anything floods (the canon-mechanics ruling).

const MARK_COLOR := Color(0.36, 0.91, 0.5)
const MARK_SIZE := 0.16
const LIFT := 1.15

var _gs
var _chunk_provider: Callable = Callable()
var _active := false
var _marks: Array = []
var _built_for := -1
var _ghosts: Array = []
var _ghosts_built_for := -1

## The workings she saw from the overlook, handed back as FADED shapes rather than marks: a wheel
## reads as a wheel. Same register, same rule -- it says WHERE she saw a thing, never what it does or
## when the water comes. Dim and unlit so it never competes with an object actually in front of you.
const GHOST_COLOR := Color(0.36, 0.91, 0.5, 0.22)

func setup(game_state, chunk_provider: Callable) -> void:
	_gs = game_state
	_chunk_provider = chunk_provider

func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if not active:
		_clear()

func mark_count() -> int:
	return _marks.size()

func _process(_delta: float) -> void:
	if not _active:
		return
	var chunk = _chunk_provider.call() if _chunk_provider.is_valid() else null
	if chunk == null or not chunk.has_method("get_peris_flora_marks"):
		_clear()
		return
	var points: Array = chunk.call("get_peris_flora_marks")
	if points.size() != _built_for:
		_clear()
		_built_for = points.size()
		for p in points:
			_marks.append(_spawn_mark(p as Vector3))
	_refresh_ghosts(chunk)

## Faded copies of the remembered workings. Rebuilt only when the remembered SET changes, and the
## copies track their sources every frame so a warped scene (or a piece that moves) keeps its ghost
## on the object rather than beside it.
func _refresh_ghosts(chunk) -> void:
	if not chunk.has_method("get_peris_memory_ghosts"):
		_clear_ghosts()
		return
	var remembered: Array = chunk.call("get_peris_memory_ghosts")
	if remembered.size() != _ghosts_built_for:
		_clear_ghosts()
		_ghosts_built_for = remembered.size()
		for entry_v in remembered:
			var entry: Dictionary = entry_v
			for mesh_v in (entry.get("meshes", []) as Array):
				if not (mesh_v is MeshInstance3D) or (mesh_v as MeshInstance3D).mesh == null:
					continue
				_ghosts.append(_spawn_ghost(mesh_v as MeshInstance3D))
	for ghost_v in _ghosts:
		var ghost: Dictionary = ghost_v
		if is_instance_valid(ghost["copy"]) and is_instance_valid(ghost["src"]):
			(ghost["copy"] as MeshInstance3D).global_transform = 				(ghost["src"] as MeshInstance3D).global_transform

func _clear_ghosts() -> void:
	for ghost_v in _ghosts:
		var ghost: Dictionary = ghost_v
		if is_instance_valid(ghost["copy"]):
			(ghost["copy"] as Node).queue_free()
	_ghosts.clear()
	_ghosts_built_for = -1

func _spawn_ghost(src: MeshInstance3D) -> Dictionary:
	var copy := MeshInstance3D.new()
	copy.mesh = src.mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GHOST_COLOR
	mat.emission_enabled = true
	mat.emission = Color(GHOST_COLOR.r, GHOST_COLOR.g, GHOST_COLOR.b)
	mat.emission_energy_multiplier = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Above the perception quad, or a memory drawn under the veil is a memory nobody sees.
	mat.render_priority = 127
	copy.material_override = mat
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(copy)
	copy.global_transform = src.global_transform
	return {"copy": copy, "src": src}

func _clear() -> void:
	_clear_ghosts()
	for m in _marks:
		if is_instance_valid(m):
			(m as Node).queue_free()
	_marks.clear()
	_built_for = -1

func _to_world(data_point: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_world(data_point)
	return data_point

## A small vertical diamond (two crossed quads) — the perception-layer mark
## grammar, like the alert "!" and the reveal rings: overlay UI, not level
## dressing, so it is built procedurally and stays out of the piece library.
func _spawn_mark(data_point: Vector3) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector3 = _to_world(data_point) + Vector3.UP * LIFT
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var a: Vector3 = c + Vector3.UP * MARK_SIZE
		var b: Vector3 = c + axis * MARK_SIZE
		var d: Vector3 = c - Vector3.UP * MARK_SIZE
		var e: Vector3 = c - axis * MARK_SIZE
		for tri in [[a, b, e], [b, d, e]]:
			for v in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = MARK_COLOR
	mat.emission_enabled = true
	mat.emission = MARK_COLOR
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
