extends SceneTree
## Review captures of the WASH ASCENT rebuild — boots the real preview, strips UI
## and debug layers, writes three story shots (overview / bay / portal ledge) to
## OUT_DIR (scratchpad — NEVER the project tree). The audit eye reviews these for
## what SHOULDN'T be there, not for whether additions appeared.
##
##   OUT_DIR=<scratchpad> ../Godot_v4.7-stable_win64.exe --path "." \
##       --position 20000,20000 --resolution 1600x900 --script tools/capture_wash_ascent.gd

func _init() -> void:
	pass

func _initialize() -> void:
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		push_error("OUT_DIR not set — captures go to the scratchpad, never the project")
		quit(1)
		return
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	var scene: Node = packed.instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", "wash_ascent")
	get_root().add_child(scene)
	for _i in range(30):
		await process_frame
	# Fog of war is a gameplay layer (default ON, dev-console-only override) — a
	# REVIEW capture is a dev surface, so it may lift it the same way `fog off` does.
	scene.set("fog_of_war_enabled", false)
	# Perception overlays ghost the world in x-ray edges — debug/tactical layers,
	# not the level; a beauty still shows the AUTHORED render only.
	var st = scene.get("_overlay_states")
	if st is Dictionary:
		for k in (st as Dictionary).keys():
			st[k] = false
		if scene.has_method("_refresh_active_overlay"):
			scene.call("_refresh_active_overlay")
	_defade(scene)
	for _i in range(4):
		await process_frame
	_hide_canvas(scene)
	_hide_labels(scene)
	_hide_characters(scene)
	RenderingServer.global_shader_parameter_set("player_world_pos", Vector3(0.0, -100000.0, 0.0))
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.make_current()
	# Cameras live in ARC space {s, lane, h} and resolve through ChannelsArc, so the
	# shots follow the coil: the overview reads the climb from outside the rim, the
	# closeups stand on (or just off) the deck like a player's eye would.
	var shots := [
		{"name": "ascent_overview", "cam": [13.0, 17.0, 7.5], "at": [13.0, 0.0, 0.0], "fov": 60.0},
		{"name": "ascent_bay", "cam": [12.0, 5.5, 2.6], "at": [11.5, -3.0, 1.1], "fov": 55.0},
		{"name": "ascent_portal", "cam": [18.6, 1.0, 1.8], "at": [24.3, 1.0, 1.6], "fov": 50.0},
		{"name": "ascent_approach", "cam": [-2.5, 2.0, 2.1], "at": [4.0, 0.0, 0.7], "fov": 58.0},
		{"name": "ascent_surge", "cam": [10.5, 8.0, 3.4], "at": [14.5, 2.0, 0.6],
			"fov": 56.0, "wash": [1, "flood"]},
		# THE PUZZLE VOCABULARY — one portrait per element (director's ask):
		{"name": "puzzle_valve", "cam": [6.9, 6.2, 1.7], "at": [9.2, 2.9, 0.7],
			"fov": 50.0},
		{"name": "puzzle_terminal", "cam": [14.4, -0.2, 1.5], "at": [16.4, -3.4, 1.0],
			"fov": 48.0},
		{"name": "puzzle_telegraph", "cam": [3.6, 7.2, 2.3], "at": [6.6, 4.2, 0.2],
			"fov": 52.0, "wash": [0, "telegraph"]},
		{"name": "puzzle_rail_gap", "cam": [0.6, 6.4, 1.7], "at": [3.2, 3.0, 0.3],
			"fov": 52.0},
	]
	var chunk: Node = scene.find_child("Chunk_wash_ascent", true, false)
	if chunk != null:
		# stills own the wash DISPLAY: a non-"active" phase makes the live
		# cadence's repaint handlers no-op, so the staged state can't be
		# overwritten by a real flood mid-shot
		chunk.set("_phase", "capture")
	for shot in shots:
		if chunk != null:
			# stage the declared wash state for the still (state setter only — no
			# scheduler), then wait out the rise/sink tweens before framing
			for i in range(3):
				chunk.call("_set_wash_state", i, "idle")
			if shot.has("wash"):
				chunk.call("_set_wash_state", int(shot["wash"][0]), str(shot["wash"][1]))
			for _t in range(26):
				await process_frame
		cam.fov = float(shot["fov"])
		var c: Array = shot["cam"]
		var a: Array = shot["at"]
		var cam_pos: Vector3 = ChannelsArc.arc_pos(float(c[0]), float(c[1])) + Vector3(0, float(c[2]), 0)
		var at_pos: Vector3 = ChannelsArc.arc_pos(float(a[0]), float(a[1])) + Vector3(0, float(a[2]), 0)
		cam.look_at_from_position(cam_pos, at_pos, Vector3.UP)
		for _j in range(8):
			await process_frame
		_hide_labels(scene)
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png(out_dir.path_join(str(shot["name"]) + ".png"))
		img.save_jpg(out_dir.path_join(str(shot["name"]) + ".jpg"), 0.88)
		print("[ASCENT] %s" % shot["name"])
	print("[ASCENT] done -> %s" % out_dir)
	quit()

func _hide_labels(n: Node) -> void:
	if n is Label3D:
		(n as Label3D).visible = false
	for c in n.get_children():
		_hide_labels(c)

func _defade(n: Node) -> void:
	if n is ColorRect and (n as ColorRect).color.a > 0.5 and (n as ColorRect).size.x > 100.0:
		(n as ColorRect).visible = false
	for c in n.get_children():
		_defade(c)

func _hide_canvas(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_canvas(c)

func _hide_characters(n: Node) -> void:
	var scr: Variant = n.get_script()
	if scr != null:
		var path := str(scr.resource_path)
		if path.ends_with("characters/player.gd") or path.ends_with("ai/npc.gd") \
				or path.ends_with("ai/enemy.gd") or path.ends_with("ai/chain_enemy.gd") \
				or path.ends_with("causal_feedback_link.gd"):
			if n is Node3D:
				(n as Node3D).visible = false
			return
	for c in n.get_children():
		_hide_characters(c)
