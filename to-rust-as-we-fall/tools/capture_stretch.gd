extends SceneTree

## Dev capture: force-build the elevator's below-deck stretch chunks and screenshot the tiling.
## Isolated-display launch only; see tools/README.md:
##   godot --path "." --script res://tools/capture_stretch.gd

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1360, 820))
	var s: Node = (load("res://scenes/tutorial/elevator.tscn") as PackedScene).instantiate()
	if "suppress_scene_change" in s:
		s.suppress_scene_change = true
	get_root().add_child(s)
	current_scene = s
	for i in range(60):
		await process_frame
	for cn in ["below", "junction", "gauntlet"]:
		if s.has_method("_load_chunk"):
			s._load_chunk(cn)
	for i in range(12):
		await process_frame
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.fov = 58.0
	cam.position = Vector3(28.0, 13.0, 19.0)
	cam.look_at_from_position(cam.position, Vector3(30.0, -4.0, -1.0), Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -28, 0)
	key.light_energy = 1.7
	get_root().add_child(key)
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://elev_stretch_capture.png")
	print("[CAPTURE] stretch -> res://elev_stretch_capture.png")
	quit()
