extends SceneTree

## Dev capture: load the real elevator scene and screenshot the car in place.
## Run WITH a display (not --headless):
##   ../Godot_v4.6.1-stable_win64_console.exe --path "." --script res://tools/capture_elevator.gd

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 820))
	var scene: Node = (load("res://scenes/tutorial/elevator.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	current_scene = scene

	# let _ready build the chunk + lights + boot a bit
	for i in range(120):
		await process_frame

	# our own interior camera (3/4 from a back corner, framing the door wall + floor + ceiling)
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.fov = 60.0
	cam.position = Vector3(-3.0, 3.2, 3.4)
	cam.look_at_from_position(cam.position, Vector3(1.6, 1.1, -0.6), Vector3.UP)
	cam.current = true

	await _settle()
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://elev_capture_faithful.png")
	print("[CAPTURE] faithful -> res://elev_capture_faithful.png")

	# neutral fill so the form/atlas reads (not the moody red)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -35, 0)
	key.light_energy = 1.4
	get_root().add_child(key)
	for child in scene.get_children():
		if child is WorldEnvironment and child.environment:
			child.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
			child.environment.ambient_light_energy = 0.9
			child.environment.background_color = Color(0.12, 0.13, 0.15)
	cam.current = true
	await _settle()
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://elev_capture_clear.png")
	print("[CAPTURE] clear -> res://elev_capture_clear.png")

	quit()

func _settle() -> void:
	for i in range(6):
		await process_frame
