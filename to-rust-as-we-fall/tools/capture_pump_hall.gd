extends SceneTree

## Dev capture: boot Pump Hall in the real preview and screenshot it top-down so the whole level reads:
## yard + crates + scarpet, the aisle walk, the gallery door, the pump room + orbit + shelter.
## Isolated-display launch only; see tools/README.md:
##   godot --path "." --script res://tools/capture_pump_hall.gd

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var scene: PackedScene = load("res://scenes/fragments/fragment_preview.tscn")
	var inst: Node = scene.instantiate()
	inst.set("preview_menu", false)
	inst.set("preview_chunk", "data_fragment")
	inst.set("preview_chunk_config", {"fragment_path": "res://data/fragments/pump_hall.tres"})
	get_root().add_child(inst)
	current_scene = inst
	for i in range(60):
		await process_frame
	# Overlays OFF for the architecture shot: the perception fog is information-as-content in play
	# (the world lights as you advance); here we want the LEVEL itself readable.
	inst.set("_overlay_states", {"aster": false, "peris": false, "endo": false})
	for i in range(4):
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 50.0
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(25.5, 26.0, 17.0), Vector3(24.0, 0.0, -1.0), Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-70, -25, 0)
	key.light_energy = 1.4
	get_root().add_child(key)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://pump_hall_capture.png")
	print("[CAPTURE] Pump Hall -> res://pump_hall_capture.png")
	quit()
