@tool
extends EditorScenePostImport

const OUTLINE_SHADER := preload("res://resources/black_outline.gdshader")
const OUTLINE_TARGET_SCRIPT := preload("res://scripts/game/objects/outline_surface_target.gd")
const SURFACE_TARGETS_SUFFIX := "SurfaceTargets"

const SIDECAR_WIRING := preload("res://tools/sidecar_material_import.gd")

func _post_import(scene: Node) -> Object:
	var root := scene as Node3D
	if root == null:
		return scene

	# Sidecar emissive/normal wiring FIRST (a DCC re-export drops the references; the importer
	# re-applies them from the <albedo>_emissive/_normals files every time).
	SIDECAR_WIRING.new()._post_import(scene)
	_split_multi_surface_meshes(root)
	var quad := MeshInstance3D.new()
	quad.name = "AsterSimRoomOutlinePreview"
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2.0, 2.0)
	quad.extra_cull_margin = 10000.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var material := ShaderMaterial.new()
	material.shader = OUTLINE_SHADER
	material.render_priority = 127
	material.set_shader_parameter("texture_outline_mix", 1.0)
	material.set_shader_parameter("texture_outline_darkness", 0.82)
	material.set_shader_parameter("texture_outline_saturation", 2.0)
	material.set_shader_parameter("texture_outline_floor", 0.02)
	material.set_shader_parameter("scene_average_lod", 8.0)
	material.set_shader_parameter("scene_average_influence", 1.0)
	material.set_shader_parameter("scene_average_saturation", 1.6)
	material.set_shader_parameter("local_min_mix", 0.9)
	material.set_shader_parameter("outline_width", 1.0)
	material.set_shader_parameter("close_outline_width", 4.4)
	material.set_shader_parameter("far_outline_width", 1.35)
	material.set_shader_parameter("close_distance", 2.0)
	material.set_shader_parameter("far_distance", 14.0)
	material.set_shader_parameter("outline_strength", 1.0)
	material.set_shader_parameter("bright_region_threshold", 0.72)
	material.set_shader_parameter("bright_region_feather", 0.18)
	material.set_shader_parameter("bright_color_edge_suppression", 1.0)
	quad.material_override = material

	root.add_child(quad)
	quad.owner = root
	return scene

func _split_multi_surface_meshes(root: Node3D) -> void:
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, mesh_instances)
	for mesh_instance in mesh_instances:
		if mesh_instance.name == "AsterSimRoomOutlinePreview":
			continue
		var source_mesh := mesh_instance.mesh
		if source_mesh == null or source_mesh.get_surface_count() <= 1:
			continue
		_split_mesh_instance(root, mesh_instance, source_mesh)

func _collect_mesh_instances(node: Node, mesh_instances: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, mesh_instances)

func _split_mesh_instance(import_root: Node3D, mesh_instance: MeshInstance3D, source_mesh: Mesh) -> void:
	var split_root := Node3D.new()
	split_root.name = "%s%s" % [mesh_instance.name, SURFACE_TARGETS_SUFFIX]
	split_root.transform = Transform3D.IDENTITY if mesh_instance == import_root else mesh_instance.transform

	if mesh_instance == import_root:
		mesh_instance.add_child(split_root)
	else:
		var parent := mesh_instance.get_parent()
		if parent == null:
			return
		parent.add_child(split_root)
	split_root.owner = import_root

	for surface_index in range(source_mesh.get_surface_count()):
		var surface_mesh := ArrayMesh.new()
		var arrays := source_mesh.surface_get_arrays(surface_index)
		surface_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
		var material := _surface_material(mesh_instance, source_mesh, surface_index)
		if material != null:
			surface_mesh.surface_set_material(0, material)

		var body := StaticBody3D.new()
		body.name = _surface_target_name(mesh_instance.name, material, surface_index)
		body.set_script(OUTLINE_TARGET_SCRIPT)
		body.set("hover_enabled", false)
		body.collision_layer = 0
		body.collision_mask = 0
		body.input_ray_pickable = false
		body.set_meta("source_mesh", mesh_instance.name)
		body.set_meta("source_surface", surface_index)
		body.set_meta("source_material", material.resource_name if material != null else "")
		split_root.add_child(body)
		body.owner = import_root

		var visual := MeshInstance3D.new()
		visual.name = "Visual"
		visual.mesh = surface_mesh
		visual.layers = mesh_instance.layers
		visual.cast_shadow = mesh_instance.cast_shadow
		visual.gi_mode = mesh_instance.gi_mode
		body.add_child(visual)
		visual.owner = import_root

		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_shape.shape = _collision_shape_for_surface(surface_mesh, source_mesh)
		body.add_child(collision_shape)
		collision_shape.owner = import_root

	if mesh_instance == import_root:
		mesh_instance.mesh = null
	else:
		mesh_instance.get_parent().remove_child(mesh_instance)
		mesh_instance.free()

func _surface_material(mesh_instance: MeshInstance3D, source_mesh: Mesh, surface_index: int) -> Material:
	if mesh_instance.material_override != null:
		return mesh_instance.material_override
	var override_material := mesh_instance.get_surface_override_material(surface_index)
	if override_material != null:
		return override_material
	return source_mesh.surface_get_material(surface_index)

func _collision_shape_for_surface(surface_mesh: ArrayMesh, source_mesh: Mesh) -> Shape3D:
	var shape := surface_mesh.create_trimesh_shape()
	if shape != null:
		return shape
	var box := BoxShape3D.new()
	var aabb := source_mesh.get_aabb()
	box.size = aabb.size.max(Vector3(0.1, 0.1, 0.1))
	return box

func _surface_target_name(source_name: String, material: Material, surface_index: int) -> String:
	var material_name := material.resource_name if material != null else ""
	var raw_name := material_name if material_name != "" else "%s_surface_%02d" % [source_name, surface_index + 1]
	return "OutlineTarget_%s" % _safe_node_name(raw_name)

func _safe_node_name(raw_name: String) -> String:
	var safe := raw_name.strip_edges()
	for token in [" ", ".", "/", "\\", ":", ";", ",", "(", ")", "[", "]", "{", "}", "#", "%"]:
		safe = safe.replace(token, "_")
	while safe.contains("__"):
		safe = safe.replace("__", "_")
	if safe == "":
		safe = "Surface"
	return safe
