extends SceneTree

## Dev capture: load the reframed Peris sim and screenshot the modeled room in place.
## Run WITH a display:
##   ../Godot_v4.6.1-stable_win64_console.exe --path "." --script res://tools/capture_peris.gd

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 820))
	var scene: Node = (load("res://scenes/tutorial/peris_sim.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	current_scene = scene
	for i in range(150):
		await process_frame

	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.fov = 50.0
	cam.position = Vector3(16.0, 9.0, 13.0)
	cam.look_at_from_position(cam.position, Vector3(6.5, 1.0, 3.0), Vector3.UP)
	cam.current = true

	# a neutral fill so the room reads (the scene boots dim/faded)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -30, 0)
	key.light_energy = 1.5
	get_root().add_child(key)
	for child in scene.get_children():
		if child is WorldEnvironment and child.environment:
			child.environment.ambient_light_color = Color(0.6, 0.58, 0.55)
			child.environment.ambient_light_energy = 1.0
			child.environment.background_color = Color(0.14, 0.13, 0.13)
	# clear any fade overlay
	for r in get_root().find_children("*", "ColorRect", true, false):
		(r as ColorRect).color = Color(0, 0, 0, 0)
	cam.current = true
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://peris_reframe_capture.png")
	print("[CAPTURE] peris reframe -> res://peris_reframe_capture.png")
	quit()
