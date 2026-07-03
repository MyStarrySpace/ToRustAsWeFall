extends SceneTree

## Path-ribbon visibility check on a DATA fragment: boot Sprint Gap, put peris on a long move,
## capture mid-flight, and dump the PathRenderManager's renderer states alongside.
## Run WITH a display: ../Godot_v4.7-stable_win64.exe --path "." --script res://tools/capture_path_check.gd

func _init() -> void:
	var packed: PackedScene = load("res://scenes/fragments/fragment_preview.tscn")
	var inst = packed.instantiate()
	inst.set("preview_menu", false)
	inst.set("preview_chunk", "data_fragment")
	inst.set("preview_chunk_config", {"fragment_path": "res://data/fragments/sprint_gap.tres"})
	# All three ON — the default play state. NOTE: the capture harness must PIN THE CAMERA — the
	# windowed run inherits the real OS cursor, and a cursor parked on a window edge RTS-edge-scrolls
	# the camera into the void mid-capture (the false "blackout" that mimicked an overlay bug TWICE).
	root.add_child(inst)
	await process_frame
	Input.warp_mouse(Vector2(576, 324))   # park the cursor mid-window: no edge-scroll drift
	var cam = inst.get("_camera")
	if cam != null and cam.has_method("set_pan_enabled"):
		cam.set_pan_enabled(false)
	for i in range(30):
		await process_frame
	var gs = inst.get("_game_state")
	gs.command_move_to_pos("peris", Vector3(38.0, 0.5, 0.0))
	gs.command_move_to_pos("aster", Vector3(10.0, 0.5, 3.0))
	for i in range(150):
		await process_frame
	var mgr = inst.get("_path_render_manager")
	print("[pathchk] manager=%s" % [mgr != null])
	if mgr != null:
		var renderers = mgr.get_children()
		print("[pathchk] manager children=%d" % renderers.size())
		for r in renderers:
			var line = r.get("_line") if "_line" in r or r.has_method("get") else null
			var drawable = line != null and line.mesh != null
			print("[pathchk]   %s char=%s drawable=%s vis=%s gpos=%s" % [r.name,
				str(r.get("char_id")), drawable, r.visible if r is Node3D else "?",
				str((r as Node3D).global_position) if r is Node3D else "?"])
	print("[pathchk] peris moving=%s pos=%s" % [gs.is_moving("peris"), str(gs.get_position("peris"))])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://vr_data_a.png")
	print("[pathchk] A: data-only default params")
	var mat = inst.get("_overlay_stack_material")
	mat.set_shader_parameter("data_clear_radius", 100.0)
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://vr_data_b.png")
	print("[pathchk] B: data_clear_radius=100")
	mat.set_shader_parameter("data_clear_radius", 14.0)
	mat.set_shader_parameter("los_enabled", false)
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://vr_data_c.png")
	print("[pathchk] C: los_enabled=false")
	quit()
