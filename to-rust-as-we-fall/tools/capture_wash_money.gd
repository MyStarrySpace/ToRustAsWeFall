extends SceneTree

## Money-shot captures of the wash relay: boots the REAL preview, strips UI/labels/fog,
## and shoots an authored list of beauty framings (the story beats, the broken coil, the
## falls at full flood — forced via WashRelayDressing.drive_falls, which live play only
## shows mid-surge). Writes <name>.png + <name>.jpg to OUT_DIR (scratchpad — NEVER the
## project tree). Run WITH a display, parked off-screen:
##   OUT_DIR=<scratchpad> ../Godot_v4.7-stable_win64.exe --path "." --position 20000,20000 \
##     --script res://tools/capture_wash_money.gd
func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var scene: Node = load("res://scenes/fragments/fragment_preview.tscn").instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", "wash_relay")
	get_root().add_child(scene)
	for _i in range(140):
		await process_frame
	var chunk = scene.get("_active_chunk")
	if chunk != null:
		(chunk as Node).set_process(false)
	scene.set("fog_of_war_enabled", false)
	var mgr = scene.get("_occlusion_mgr")
	if mgr != null:
		(mgr as Node).set_process(false)
	RenderingServer.global_shader_parameter_set("player_world_pos", Vector3(0.0, -100000.0, 0.0))
	_defade(scene)
	_hide_canvas(scene)
	# LABELS=keep leaves every Label3D visible — the scene annotates itself, which is the
	# ground-truth mode for audits (what IS that thing in frame?). Default strips them.
	if OS.get_environment("LABELS") != "keep":
		# The HOST re-syncs item nameplates every frame — freeze its process so a
		# swept label can't come back before the capture (the RICH LYSATE leak).
		scene.set_process(false)
		_hide_labels(scene)
	var st = scene.get("_overlay_states")
	if st is Dictionary:
		for k in (st as Dictionary).keys():
			st[k] = false
		if scene.has_method("_refresh_active_overlay"):
			scene.call("_refresh_active_overlay")
	# RIG=off drops the injected studio key/fill — the honest capture of the
	# level's AUTHORED lighting (the rig flatters; the game never has it).
	if OS.get_environment("RIG") != "off":
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-58, -30, 0)
		key.light_energy = 1.25
		get_root().add_child(key)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-18, 145, 0)
		fill.light_energy = 0.45
		get_root().add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 300.0
	get_root().add_child(cam)
	cam.current = true

	# The authored shot list: name, camera, target, fall intensity (0 = dry).
	var shots := [
		{"name": "curecumin_portal", "cam": Vector3(8.7, 3.0, 3.9), "at": Vector3(4.7, 2.0, 0.7),
			"falls": 0.0, "fov": 50.0},
		{"name": "branch_spur", "cam": Vector3(-19.9, 8.6, 14.0), "at": Vector3(-15.6, 5.2, 9.9),
			"falls": 0.0, "fov": 52.0},
		{"name": "lonely_flure", "cam": Vector3(7.6, 11.6, -3.6), "at": Vector3(3.76, 10.0, -2.6),
			"falls": 0.0, "fov": 48.0},
		{"name": "drum_face", "cam": Vector3(5.8, 2.6, 4.4), "at": Vector3(2.86, 1.8, 1.96),
			"falls": 0.0, "fov": 46.0},
		{"name": "full_flood", "cam": Vector3(4.4, 2.9, 8.6), "at": Vector3(9.5, 1.6, 6.4),
			"falls": 1.0, "fov": 58.0},
		{"name": "the_ascent", "cam": Vector3(-9.1, 7.1, 6.3), "at": Vector3(-11.0, 6.6, -0.9),
			"falls": 0.45, "fov": 60.0},
		{"name": "summit_crown", "cam": Vector3(5.5, 18.5, 7.5), "at": Vector3(0.0, 15.5, 0.0),
			"falls": 0.0, "fov": 50.0},
		# neck_garden retired: the carved pocket's true frame is unprobed — every
		# eyeballed camera clips the neck shell. Re-add after a datum probe of it.
	]
	var dressing = chunk.get("_dressing") if chunk != null else null
	for shot in shots:
		var lvl := float(shot["falls"])
		if dressing is Dictionary:
			for i in range(int((dressing["mats"] as Array).size())):
				WashRelayDressing.drive_falls(dressing, i, lvl)
		# The flood shot also shows the chunk's own section water (normally cadence-gated).
		if chunk != null and chunk.get("_section_water") is Array:
			for segs in (chunk.get("_section_water") as Array):
				for seg in segs:
					if is_instance_valid(seg):
						(seg as Node3D).visible = lvl > 0.5
		cam.fov = float(shot.get("fov", 55.0))
		cam.look_at_from_position(shot["cam"], shot["at"], Vector3.UP)
		for _j in range(10):
			await process_frame
		# Late item nameplates (branch/drain lysate) spawn after the first sweep;
		# re-hide right before the frame so LABELS=off holds every shot.
		if OS.get_environment("LABELS") != "keep":
			_hide_labels(scene)
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png(out_dir.path_join(str(shot["name"]) + ".png"))
		img.save_jpg(out_dir.path_join(str(shot["name"]) + ".jpg"), 0.88)
		print("[MONEY] %s" % shot["name"])
	print("[MONEY] done -> %s" % out_dir)
	quit()

func _hide_labels(n: Node) -> void:
	if n is Label3D:
		(n as Label3D).visible = false
	for c in n.get_children():
		_hide_labels(c)

func _hide_canvas(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_canvas(c)

func _defade(n: Node) -> void:
	if n is ColorRect and (n as ColorRect).color.a > 0.5 and (n as ColorRect).size.x > 100.0:
		(n as ColorRect).visible = false
	for c in n.get_children():
		_defade(c)
