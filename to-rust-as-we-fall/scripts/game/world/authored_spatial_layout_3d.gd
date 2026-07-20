@tool
class_name AuthoredSpatialLayout3D
extends Node3D

## Small reusable contract for authored gameplay layouts. Level controllers own
## story/state; this scene owns spatial placement and visual visibility choices.

@export var anchors_path := NodePath("Anchors")
@export var hidden_visual_paths: Array[NodePath] = []
@export var occlusion_exempt_paths: Array[NodePath] = []


func _ready() -> void:
	_apply_visibility_overrides()
	_apply_occlusion_exemptions()


func anchor(anchor_name: StringName) -> Marker3D:
	var anchors := get_node_or_null(anchors_path)
	if anchors == null:
		return null
	return anchors.get_node_or_null(NodePath(str(anchor_name))) as Marker3D


func anchor_position(anchor_name: StringName) -> Vector3:
	var marker := anchor(anchor_name)
	return marker.global_position if marker != null else global_position


func anchor_names() -> PackedStringArray:
	var result := PackedStringArray()
	var anchors := get_node_or_null(anchors_path)
	if anchors == null:
		return result
	for child in anchors.get_children():
		if child is Marker3D:
			result.append(str(child.name))
	return result


func _apply_visibility_overrides() -> void:
	for path in hidden_visual_paths:
		var visual := get_node_or_null(path) as Node3D
		if visual != null:
			visual.visible = false


func _apply_occlusion_exemptions() -> void:
	for path in occlusion_exempt_paths:
		var subtree := get_node_or_null(path)
		if subtree == null:
			continue
		if subtree is MeshInstance3D:
			subtree.set_meta("camera_occlusion_exempt", true)
		for mesh in subtree.find_children("*", "MeshInstance3D", true, false):
			mesh.set_meta("camera_occlusion_exempt", true)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if get_node_or_null(anchors_path) == null:
		warnings.append("anchors_path must point to a node containing Marker3D anchors.")
	for path in hidden_visual_paths:
		if get_node_or_null(path) == null:
			warnings.append("Hidden visual does not exist: %s" % path)
	for path in occlusion_exempt_paths:
		if get_node_or_null(path) == null:
			warnings.append("Occlusion-exempt subtree does not exist: %s" % path)
	return warnings
