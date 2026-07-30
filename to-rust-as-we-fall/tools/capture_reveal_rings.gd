extends SceneTree
## One still of the hold-SHIFT reveal: detection rings live over the gap watch.
##   OUT_DIR=<scratchpad> ../Godot_v4.7-stable_win64.exe --path "." \
##       --position 20000,20000 --resolution 1600x900 --script tools/capture_reveal_rings.gd

func _initialize() -> void:
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		push_error("OUT_DIR not set")
		quit(1)
		return
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	var scene: Node = packed.instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", "wash_ascent")
	get_root().add_child(scene)
	for _i in range(30):
		await process_frame
	scene.set("fog_of_war_enabled", false)
	var st = scene.get("_overlay_states")
	if st is Dictionary:
		for k in (st as Dictionary).keys():
			st[k] = false
		if scene.has_method("_refresh_active_overlay"):
			scene.call("_refresh_active_overlay")
	for layer in get_root().find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var chunk: Node = scene.find_child("Chunk_wash_ascent", true, false)
	scene.call("headless_advance", 12.0)   # ride out the overlook intro
	chunk.set("_phase", "capture")
	for i in range(5):
		chunk.call("_set_wash_state", i, "idle")
	var mgr = scene.find_child("DetectionRingManager", true, false)
	mgr.call("set_active", true)
	for _t in range(10):
		await process_frame
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.make_current()
	cam.fov = 55.0
	var cam_pos: Vector3 = ChannelsArc.arc_pos(33.0, 9.0) + Vector3(0, 4.5, 0)
	var at_pos: Vector3 = ChannelsArc.arc_pos(39.5, 1.5) + Vector3(0, 0.5, 0)
	cam.look_at_from_position(cam_pos, at_pos, Vector3.UP)
	for _j in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("reveal_rings.png"))
	quit(0)
