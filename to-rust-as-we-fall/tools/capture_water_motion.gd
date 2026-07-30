extends SceneTree
## Motion proof for the wash water: stages a flood, parks the camera on the
## keyed span, and writes TWO frames ~0.7 s of wall time apart. A shader that
## actually moves produces a non-trivial pixel diff in the water region; a
## static one produces ~zero. Also a low overview frame for the translucency
## read (the sluice bed showing through the surge).
##
##   OUT_DIR=<scratchpad> ../Godot_v4.7-stable_win64.exe --path "." \
##       --position 20000,20000 --resolution 1600x900 --script tools/capture_water_motion.gd

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
	for layer in get_root().find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var chunk: Node = scene.find_child("Chunk_wash_ascent", true, false)
	scene.call("headless_advance", 12.0)   # ride out the overlook intro
	chunk.set("_phase", "capture")
	for i in range(5):
		chunk.call("_set_wash_state", i, "idle")
	chunk.call("_set_wash_state", 3, "flood")
	for _t in range(30):
		await process_frame
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.make_current()
	cam.fov = 56.0
	var cam_pos: Vector3 = ChannelsArc.arc_pos(25.0, 8.5) + Vector3(0, 3.6, 0)
	var at_pos: Vector3 = ChannelsArc.arc_pos(31.0, 2.0) + Vector3(0, 0.8, 0)
	cam.look_at_from_position(cam_pos, at_pos, Vector3.UP)
	for _j in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("water_t0.png"))
	var waited := 0.0
	while waited < 0.7:
		waited += float(get_root().get_process_delta_time())
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("water_t1.png"))
	# the translucency read: low over the bed, looking along the flooded span
	cam.fov = 50.0
	cam_pos = ChannelsArc.arc_pos(27.0, 5.0) + Vector3(0, 1.4, 0)
	at_pos = ChannelsArc.arc_pos(32.0, 3.0) + Vector3(0, 0.2, 0)
	cam.look_at_from_position(cam_pos, at_pos, Vector3.UP)
	for _j2 in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("water_low.png"))
	quit(0)
