@tool
extends Node3D

## Editor-first floor-plan guide for authored rooms. The origin is the room's
## north-west corner; +X runs along the long wall and +Z runs toward the open
## camera side. Runtime builds hide the guide unless PERIS_LAYOUT_GUIDES=1 (or
## show_in_game is enabled explicitly), so these construction lines never become
## part of the finished room by accident.

@export var room_size := Vector2(14.0, 6.0):
	set(value):
		room_size = value
		_request_rebuild()
@export_range(0.1, 2.0, 0.05, "suffix:m") var minor_step := 0.5:
	set(value):
		minor_step = maxf(value, 0.01)
		_request_rebuild()
@export_range(0.25, 4.0, 0.25, "suffix:m") var major_step := 1.0:
	set(value):
		major_step = maxf(value, 0.01)
		_request_rebuild()
@export var show_in_game := false
@export var minor_color := Color(0.18, 0.72, 0.78, 0.22):
	set(value):
		minor_color = value
		_request_rebuild()
@export var major_color := Color(0.24, 0.86, 0.92, 0.48):
	set(value):
		major_color = value
		_request_rebuild()
@export var dimension_color := Color(1.0, 0.66, 0.24, 0.9):
	set(value):
		dimension_color = value
		_request_rebuild()

const GUIDE_Y := 0.018
const DIMENSION_OFFSET := 0.45
const EPSILON := 0.001


func _request_rebuild() -> void:
	if is_inside_tree():
		call_deferred("_rebuild")


func _ready() -> void:
	var runtime_visible := show_in_game or OS.get_environment("PERIS_LAYOUT_GUIDES") == "1"
	if not Engine.is_editor_hint() and not runtime_visible:
		visible = false
		return
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta("measurement_grid_generated"):
			child.free()
	if room_size.x <= 0.0 or room_size.y <= 0.0 or minor_step <= 0.0 or major_step <= 0.0:
		return

	var minor_segments: Array[PackedVector3Array] = []
	var major_segments: Array[PackedVector3Array] = []
	var dimension_segments: Array[PackedVector3Array] = []

	_append_grid_axis(minor_segments, major_segments, true)
	_append_grid_axis(minor_segments, major_segments, false)

	# Dimension strings live just outside the modeled walls, with end ticks and
	# one-metre witness ticks. They make the room's 14 m x 6 m contract visible
	# in the editor instead of leaving it buried in gameplay constants.
	_add_segment(dimension_segments,
		Vector3(0.0, GUIDE_Y, -DIMENSION_OFFSET),
		Vector3(room_size.x, GUIDE_Y, -DIMENSION_OFFSET))
	_add_segment(dimension_segments,
		Vector3(-DIMENSION_OFFSET, GUIDE_Y, 0.0),
		Vector3(-DIMENSION_OFFSET, GUIDE_Y, room_size.y))
	var x_tick := 0.0
	while x_tick < room_size.x - EPSILON:
		_add_segment(dimension_segments,
			Vector3(x_tick, GUIDE_Y, -DIMENSION_OFFSET - 0.10),
			Vector3(x_tick, GUIDE_Y, -DIMENSION_OFFSET + 0.10))
		x_tick += major_step
	_add_segment(dimension_segments,
		Vector3(room_size.x, GUIDE_Y, -DIMENSION_OFFSET - 0.10),
		Vector3(room_size.x, GUIDE_Y, -DIMENSION_OFFSET + 0.10))
	var z_tick := 0.0
	while z_tick < room_size.y - EPSILON:
		_add_segment(dimension_segments,
			Vector3(-DIMENSION_OFFSET - 0.10, GUIDE_Y, z_tick),
			Vector3(-DIMENSION_OFFSET + 0.10, GUIDE_Y, z_tick))
		z_tick += major_step
	_add_segment(dimension_segments,
		Vector3(-DIMENSION_OFFSET - 0.10, GUIDE_Y, room_size.y),
		Vector3(-DIMENSION_OFFSET + 0.10, GUIDE_Y, room_size.y))

	_add_line_layer("MinorGrid", minor_segments, minor_color)
	_add_line_layer("MajorGrid", major_segments, major_color)
	_add_line_layer("Dimensions", dimension_segments, dimension_color)
	_add_dimension_label("Width", "%.0f m" % room_size.x,
		Vector3(room_size.x * 0.5, GUIDE_Y + 0.02, -DIMENSION_OFFSET - 0.20))
	_add_dimension_label("Depth", "%.0f m" % room_size.y,
		Vector3(-DIMENSION_OFFSET - 0.20, GUIDE_Y + 0.02, room_size.y * 0.5))


func _append_grid_axis(
		minor_segments: Array[PackedVector3Array],
		major_segments: Array[PackedVector3Array],
		along_x: bool
) -> void:
	var span := room_size.x if along_x else room_size.y
	var value := 0.0
	# Minor and major sequences are authored independently: a 0.3 m minor grid
	# still gets an exact 1 m major grid instead of only their coincident lines.
	while value < span - EPSILON:
		if not _is_major(value):
			_append_axis_segment(minor_segments, value, along_x)
		value += minor_step
	value = 0.0
	while value < span - EPSILON:
		_append_axis_segment(major_segments, value, along_x)
		value += major_step
	# The physical room edge is always explicit, even for a non-divisible span.
	_append_axis_segment(major_segments, span, along_x)


func _append_axis_segment(segments: Array[PackedVector3Array], value: float, along_x: bool) -> void:
	if along_x:
		_add_segment(segments, Vector3(value, GUIDE_Y, 0.0), Vector3(value, GUIDE_Y, room_size.y))
	else:
		_add_segment(segments, Vector3(0.0, GUIDE_Y, value), Vector3(room_size.x, GUIDE_Y, value))


func _is_major(value: float) -> bool:
	if major_step <= 0.0:
		return false
	return absf(value - round(value / major_step) * major_step) <= EPSILON


func _add_segment(segments: Array[PackedVector3Array], a: Vector3, b: Vector3) -> void:
	segments.append(PackedVector3Array([a, b]))


func _add_line_layer(layer_name: String, segments: Array[PackedVector3Array], color: Color) -> void:
	if segments.is_empty():
		return
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment in segments:
		immediate.surface_add_vertex(segment[0])
		immediate.surface_add_vertex(segment[1])
	immediate.surface_end()

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = layer_name
	mesh_instance.mesh = immediate
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.set_meta("measurement_grid_generated", true)
	add_child(mesh_instance)


func _add_dimension_label(label_name: String, value: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = label_name
	label.text = value
	label.position = at
	label.font_size = 20
	label.pixel_size = 0.012
	label.fixed_size = false
	# Labels use normal depth testing; disabling it makes Label3D's transparent
	# atlas quads occlude large pieces of the room on some Forward+ drivers.
	label.no_depth_test = false
	label.modulate = dimension_color
	label.outline_modulate = Color(0.02, 0.03, 0.04, 0.9)
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.set_meta("measurement_grid_generated", true)
	add_child(label)
