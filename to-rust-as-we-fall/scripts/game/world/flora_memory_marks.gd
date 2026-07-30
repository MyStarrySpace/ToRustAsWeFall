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
	if points.size() == _built_for:
		return
	_clear()
	_built_for = points.size()
	for p in points:
		_marks.append(_spawn_mark(p as Vector3))

func _clear() -> void:
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
