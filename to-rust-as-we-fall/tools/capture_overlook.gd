extends SceneTree
## Two stills of the entry beat: the OVERLOOK from the bridge (the whole climb
## below, pre-collapse) and Peris's flora-memory marks lighting the coil after
## the drop.
##   OUT_DIR=<scratchpad> ../Godot_v4.7-stable_win64.exe --path "." \
##       --position 20000,20000 --resolution 1600x900 --script tools/capture_overlook.gd

func _initialize() -> void:
	get_root().unfocusable = true
	OffscreenWindow.park(get_root())
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
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.make_current()
	# SHOT 1: the overlook — from just behind the bridge spawns, looking down
	# the whole coil (the read Peris keeps)
	cam.fov = 66.0
	# the entry span crosses the drum's CENTER: frame the party over the core
	# with the coil dropping away around them
	var cam_pos: Vector3 = ChannelsArc.arc_pos(158.0, 8.0) + Vector3(0, 8.5, 0)
	var at_pos: Vector3 = Vector3(0, 23.2, 0)
	cam.look_at_from_position(cam_pos, at_pos, Vector3.UP)
	scene.call("headless_advance", 2.2)   # mid-overlook: channels alive below
	_hide_labels(get_root())
	for _j in range(10):
		await process_frame
	_hide_labels(get_root())
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("overlook.png"))
	# SHOT 2: after the drop — PERIS'S OVERLAY on (her register look), the
	# memory marks lighting the flora she read from above
	scene.call("headless_advance", 19.0)
	if st is Dictionary:
		st["peris"] = true
		if scene.has_method("_refresh_active_overlay"):
			scene.call("_refresh_active_overlay")
	for _t in range(14):
		await process_frame
	_hide_labels(get_root())
	cam.fov = 58.0
	cam_pos = ChannelsArc.arc_pos(6.0, 15.0) + Vector3(0, 6.5, 0)
	at_pos = ChannelsArc.arc_pos(16.0, 1.0) + Vector3(0, 1.0, 0)
	cam.look_at_from_position(cam_pos, at_pos, Vector3.UP)
	for _j2 in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir.path_join("peris_memory.png"))
	quit(0)

func _hide_labels(n: Node) -> void:
	if n is Label3D:
		(n as Label3D).visible = false
	for c in n.get_children():
		_hide_labels(c)
