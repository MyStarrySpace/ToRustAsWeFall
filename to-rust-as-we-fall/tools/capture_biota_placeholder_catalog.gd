extends SceneTree

## Renders the editor catalog as an art-review lineup. This staging geometry is tooling-only and
## never enters a gameplay scene.
##
##   OUT_DIR=<scratchpad> ..\Godot_v4.6.1-stable_win64_console.exe --path . \
##     --script res://tools/capture_biota_placeholder_catalog.gd

const CATALOG_SCENE := "res://scenes/props/biota/placeholder_biota_catalog.tscn"


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed := load(CATALOG_SCENE) as PackedScene
	if packed == null:
		push_error("[BIOTA CAPTURE] Could not load %s" % CATALOG_SCENE)
		quit(1)
		return
	var catalog := packed.instantiate() as Node3D
	get_root().add_child(catalog)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.025, 0.026)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.42, 0.4)
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	get_root().add_child(environment_node)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(10.0, 4.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.07, 0.09, 0.085)
	floor_material.roughness = 0.92
	floor.material_override = floor_material
	floor.position = Vector3(0, -0.035, 0)
	get_root().add_child(floor)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -34, 0)
	key.light_color = Color(0.72, 0.86, 0.81)
	key.light_energy = 1.35
	key.shadow_enabled = true
	get_root().add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-38, 142, 0)
	rim.light_color = Color(0.72, 0.5, 0.35)
	rim.light_energy = 0.72
	get_root().add_child(rim)

	var labels := {
		"placeholder_seefern_v1": "SEEFERN",
		"placeholder_hushbloom_v1": "HUSHBLOOM",
		"placeholder_scarpet_v1": "SCARPET",
		"placeholder_sapscrap_v1": "SAPSCRAP",
	}
	for node_name_v in labels.keys():
		var specimen := catalog.get_node_or_null(str(node_name_v)) as Node3D
		if specimen == null:
			continue
		var label := Label3D.new()
		label.text = str(labels[node_name_v])
		label.font_size = 32
		label.modulate = Color(0.72, 0.82, 0.77)
		label.outline_size = 8
		label.outline_modulate = Color(0.01, 0.015, 0.015, 0.9)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = specimen.position + Vector3(0, 1.82, 0)
		get_root().add_child(label)

	var camera := Camera3D.new()
	camera.fov = 42.0
	camera.position = Vector3(0.2, 3.45, 7.65)
	camera.look_at_from_position(camera.position, Vector3(0, 0.58, 0), Vector3.UP)
	get_root().add_child(camera)
	camera.current = true

	for _frame in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var output_dir := OS.get_environment("OUT_DIR")
	if output_dir == "":
		output_dir = "user://"
	var output_path := output_dir.path_join("biota_placeholder_catalog.png")
	var error := get_root().get_texture().get_image().save_png(output_path)
	print("[BIOTA CAPTURE] %s (%s)" % [output_path, error_string(error)])
	quit(0 if error == OK else 1)
