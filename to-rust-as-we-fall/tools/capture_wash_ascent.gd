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
	var shots := [
		{"name": "ascent_overview", "cam": Vector3(13.0, 10.0, -9.5), "at": Vector3(13.0, 0.6, 4.5), "fov": 55.0},
		{"name": "ascent_bay", "cam": Vector3(5.6, 3.0, -0.6), "at": Vector3(11.5, 1.1, 6.2), "fov": 55.0},
		{"name": "ascent_portal", "cam": Vector3(18.6, 1.9, 3.0), "at": Vector3(24.3, 1.9, 3.0), "fov": 50.0},
		{"name": "ascent_approach", "cam": Vector3(-1.8, 2.2, 0.2), "at": Vector3(4.0, 0.8, 4.6), "fov": 58.0},
	]
	for shot in shots:
		cam.fov = float(shot["fov"])
		cam.look_at_from_position(shot["cam"], shot["at"], Vector3.UP)
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
