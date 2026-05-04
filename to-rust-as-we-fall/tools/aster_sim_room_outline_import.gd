@tool
extends EditorScenePostImport

const OUTLINE_SHADER := preload("res://resources/black_outline.gdshader")

func _post_import(scene: Node) -> Object:
	var root := scene as Node3D
	if root == null:
		return scene

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
	material.set_shader_parameter("hover_outline_enabled", false)
	material.set_shader_parameter("hover_outline_color", Vector3(1.0, 1.0, 1.0))
	material.set_shader_parameter("selected_outline_enabled", false)
	material.set_shader_parameter("selected_outline_color", Vector3(1.0, 0.62, 0.12))
	quad.material_override = material

	root.add_child(quad)
	quad.owner = root
	return scene
