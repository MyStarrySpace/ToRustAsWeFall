class_name OcclusionFade
extends Node

## Fades geometry sitting between the camera and a target character so the
## character stays visible behind walls. Uses the dithered occlusion shader
## (res://resources/occlusion_fade.gdshader): bind a target (and optionally a
## camera), register occluder MeshInstance3Ds, and this keeps the shader's
## player_position uniform in sync each frame. Camera position is read from the
## view matrix in-shader, so the camera ref is informational only.

const OCCLUSION_SHADER := preload("res://resources/occlusion_fade.gdshader")

@export var fade_radius := 1.15
@export var fade_softness := 0.6
@export var min_visibility := 0.1
@export var player_depth_bias := 0.5
## Lift the player end of the tube to roughly chest height (feet → body center).
@export var target_height_offset := 0.9

var target: Node3D
var camera: Camera3D

var _materials: Array[ShaderMaterial] = []

func bind(target_node: Node3D, camera_node: Camera3D = null) -> void:
	target = target_node
	camera = camera_node

## Replace a mesh's material with the occlusion-fade shader, preserving the
## surface's albedo/roughness/metallic where it came from a StandardMaterial3D.
## Returns the ShaderMaterial so callers can tweak it.
func register_occluder(mesh: MeshInstance3D) -> ShaderMaterial:
	if mesh == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = OCCLUSION_SHADER
	_copy_surface_look(mesh, mat)
	_apply_params(mat)
	mesh.material_override = mat
	_materials.append(mat)
	return mat

## Register every MeshInstance3D under root (optionally filtered to a group).
## Returns the number of occluders registered.
func register_occluders_in(root: Node, group := "") -> int:
	if root == null:
		return 0
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if group != "" and not mesh.is_in_group(group):
			continue
		register_occluder(mesh)
		count += 1
	return count

func occluder_count() -> int:
	return _materials.size()

func clear_occluders() -> void:
	_materials.clear()

func _copy_surface_look(mesh: MeshInstance3D, mat: ShaderMaterial) -> void:
	var src: Material = mesh.material_override
	if src == null and mesh.get_surface_override_material_count() > 0:
		src = mesh.get_surface_override_material(0)
	if src == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		src = mesh.mesh.surface_get_material(0)
	if src is StandardMaterial3D:
		var std := src as StandardMaterial3D
		mat.set_shader_parameter("albedo_color", std.albedo_color)
		if std.albedo_texture != null:
			mat.set_shader_parameter("albedo_texture", std.albedo_texture)
		mat.set_shader_parameter("roughness_value", std.roughness)
		mat.set_shader_parameter("metallic_value", std.metallic)

func _apply_params(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("fade_radius", fade_radius)
	mat.set_shader_parameter("fade_softness", fade_softness)
	mat.set_shader_parameter("min_visibility", min_visibility)
	mat.set_shader_parameter("player_depth_bias", player_depth_bias)

func _process(_delta: float) -> void:
	if target == null or _materials.is_empty():
		return
	var p: Vector3 = target.global_position + Vector3(0.0, target_height_offset, 0.0)
	for mat in _materials:
		mat.set_shader_parameter("player_position", p)
