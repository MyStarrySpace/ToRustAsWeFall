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
	inst.set("_overlay_states", {"aster": false, "peris": true, "endo": false})   # A/B: fog ONLY
	root.add_child(inst)
	await process_frame
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
	root.get_texture().get_image().save_png("res://vr_path_check.png")
	print("[pathchk] wrote vr_path_check.png (overlays OFF)")
	quit()
