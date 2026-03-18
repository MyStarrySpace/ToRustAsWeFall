extends MeshInstance3D

## Draws a visible grid on the floor plane so you can see cell boundaries.

@export var grid_size: int = 40
@export var grid_color: Color = Color(0.3, 0.3, 0.35, 0.4)

func _ready() -> void:
	var im := ImmediateMesh.new()
	mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = grid_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	material_override = mat

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := grid_size / 2
	for i in range(-half, half + 1):
		# Lines along X
		im.surface_add_vertex(Vector3(i, 0.01, -half))
		im.surface_add_vertex(Vector3(i, 0.01, half))
		# Lines along Z
		im.surface_add_vertex(Vector3(-half, 0.01, i))
		im.surface_add_vertex(Vector3(half, 0.01, i))
	im.surface_end()
