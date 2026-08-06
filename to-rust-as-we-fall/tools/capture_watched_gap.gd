extends SceneTree

## Dev capture: boot the REAL fragment preview on The Watched Gap and screenshot it top-down-ish, so the room
## reads: west room + flure pocket, the one-lane gap in the dividing wall, the sentry at its post, east room.
## Isolated-display launch only (not --headless); see tools/README.md:
##   godot --path "." --script res://tools/capture_watched_gap.gd

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var scene: PackedScene = load("res://scenes/fragments/fragment_preview.tscn")
	var inst: Node = scene.instantiate()
	inst.set("preview_menu", false)
	inst.set("preview_chunk", "distract_gate")
	get_root().add_child(inst)
	current_scene = inst
	for i in range(60):
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 55.0
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(11.5, 22.0, 12.0), Vector3(11.5, 0.0, 0.0), Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-65, -30, 0)
	key.light_energy = 1.5
	get_root().add_child(key)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://watched_gap_capture.png")
	print("[CAPTURE] The Watched Gap -> res://watched_gap_capture.png")
	quit()
