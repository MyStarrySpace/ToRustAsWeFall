class_name WorldCalloutStack3D
extends Node3D

## Keeps a small group of world-space callouts in a stable, non-overlapping screen lane.
##
## Label3D's `fixed_size` solves zoom-dependent glyph scaling, but it does not solve labels whose
## world anchors project onto one another. This presenter keeps the labels attached to a truthful
## world anchor while reserving a fixed number of screen pixels between them. It is cosmetic only:
## visibility and gameplay state remain owned by the labels' original systems.

@export var anchor_path := NodePath("")
@export var label_paths: Array[NodePath] = []
@export_range(-1, 1, 2) var preferred_side := 1
@export_range(0.0, 512.0, 1.0) var anchor_clearance_px := 52.0
@export_range(32.0, 1024.0, 1.0) var estimated_label_width_px := 240.0
@export_range(8.0, 256.0, 1.0) var row_spacing_px := 40.0
@export var vertical_offset_px := -8.0
## left, top, right, bottom
@export var viewport_safe_margins := Vector4(24.0, 24.0, 24.0, 24.0)

var _labels: Array[Label3D] = []
var _anchor: Node3D = null
var _last_camera_transform := Transform3D()
var _last_camera_size := -1.0
var _last_viewport_size := Vector2.ZERO


func _ready() -> void:
	_anchor = get_node_or_null(anchor_path) as Node3D
	for path in label_paths:
		register_label(get_node_or_null(path) as Label3D)
	set_process(DisplayServer.get_name() != "headless")
	if is_processing():
		call_deferred("_refresh_layout", true)


func register_label(label: Label3D) -> void:
	if label == null or _labels.has(label):
		return
	# Fixed-size glyphs and screen-space row placement are both required. One without the other either
	# balloons under a close camera or collapses into the neighbouring row when zoomed out.
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.top_level = true
	_labels.append(label)
	_invalidate_layout()


func unregister_label(label: Label3D) -> void:
	_labels.erase(label)
	_invalidate_layout()


func get_registered_label_count() -> int:
	return _labels.size()


func debug_calculate_screen_centers(
		anchor_screen: Vector2,
		viewport_size: Vector2,
		count := -1
	) -> PackedVector2Array:
	var row_count := _labels.size() if count < 0 else maxi(0, count)
	return _calculate_screen_centers(anchor_screen, viewport_size, row_count)


func _process(_delta: float) -> void:
	_refresh_layout(false)


func _invalidate_layout() -> void:
	_last_camera_size = -1.0
	_last_viewport_size = Vector2.ZERO


func _refresh_layout(force := false) -> void:
	if _anchor == null or not is_instance_valid(_anchor) or _labels.is_empty():
		return
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null or camera.is_position_behind(_anchor.global_position):
		return
	var viewport_size := viewport.get_visible_rect().size
	if not force and camera.global_transform.is_equal_approx(_last_camera_transform) \
			and is_equal_approx(camera.size, _last_camera_size) \
			and viewport_size.is_equal_approx(_last_viewport_size):
		return
	_last_camera_transform = camera.global_transform
	_last_camera_size = camera.size
	_last_viewport_size = viewport_size

	var local_anchor := camera.to_local(_anchor.global_position)
	var depth := maxf(camera.near + 0.01, -local_anchor.z)
	var anchor_screen := camera.unproject_position(_anchor.global_position)
	var centers := _calculate_screen_centers(anchor_screen, viewport_size, _labels.size())
	for index in range(_labels.size()):
		var label := _labels[index]
		if label == null or not is_instance_valid(label):
			continue
		label.global_position = camera.project_position(centers[index], depth)


func _calculate_screen_centers(
		anchor_screen: Vector2,
		viewport_size: Vector2,
		row_count: int
	) -> PackedVector2Array:
	var centers := PackedVector2Array()
	if row_count <= 0 or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return centers
	var left := viewport_safe_margins.x
	var top := viewport_safe_margins.y
	var right := viewport_size.x - viewport_safe_margins.z
	var bottom := viewport_size.y - viewport_safe_margins.w
	var anchor_is_on_screen := anchor_screen.x >= 0.0 and anchor_screen.x <= viewport_size.x \
			and anchor_screen.y >= 0.0 and anchor_screen.y <= viewport_size.y
	var side := 1.0 if preferred_side >= 0 else -1.0
	if anchor_is_on_screen:
		var required_width := anchor_clearance_px + estimated_label_width_px
		var preferred_space := right - anchor_screen.x if side > 0.0 else anchor_screen.x - left
		var alternate_space := anchor_screen.x - left if side > 0.0 else right - anchor_screen.x
		if preferred_space < required_width and alternate_space > preferred_space:
			side = -side
	var half_width := estimated_label_width_px * 0.5
	var center_x := anchor_screen.x + side * (anchor_clearance_px + half_width)
	var total_height := row_spacing_px * float(row_count - 1)
	var center_y := anchor_screen.y + vertical_offset_px
	if anchor_is_on_screen:
		center_x = clampf(center_x, left + half_width, right - half_width)
		center_y = clampf(center_y, top + total_height * 0.5, bottom - total_height * 0.5)
	for index in range(row_count):
		var row_offset := (float(index) - float(row_count - 1) * 0.5) * row_spacing_px
		centers.append(Vector2(center_x, center_y + row_offset))
	return centers
