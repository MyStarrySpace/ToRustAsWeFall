extends SceneTree
## Datum probe for the keyed-span crossing: holds section 3 via the landing
## valve verb, commands the party across the bed on the back-wall lane, and
## samples every walker each half-second — a stall shows up as a flatlining
## position. Dumps the wall cells across the bed first.
##
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##       --script tools/probe_keyed_crossing.gd

func _initialize() -> void:
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	var scene = packed.instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", "wash_ascent")
	get_root().add_child(scene)
	for _i in range(30):
		await process_frame
	var chunk = scene.find_child("Chunk_wash_ascent", true, false)
	var gs = scene.get("_game_state")
	if chunk == null or gs == null:
		push_error("probe boot failed")
		quit(1)
		return
	scene.call("headless_advance", 0.05)
	scene.call("headless_advance", 20.0)
	var walls: Array = chunk.get("_wall_cells")
	var bed: Array = []
	for c in walls:
		var cx := float((c as Array)[0]) if c is Array else float((c as Vector2i).x)
		var cz := float((c as Array)[1]) if c is Array else float((c as Vector2i).y)
		if cx >= 26.0 and cx <= 40.0:
			bed.append([cx, cz])
	print("[probe] wall cells x26-40: %s" % [bed])
	# replicate the playthrough's preceding beat: the lonely flure has FIRED
	# (aster at its stand) and its lured/washed sentry is in play
	gs.snap_character_to("aster", Vector3(17.6, 0.1, 1.4))
	gs.snap_character_to("peris", Vector3(18.3, 0.1, 2.3))
	gs.snap_character_to("endo", Vector3(18.3, 0.1, 3.0))
	scene.call("headless_advance", 0.5)
	var lflure = chunk.find_child("LonelyFlureObject", true, false)
	lflure.set("active_character", "aster")
	await process_frame
	print("[probe] lonely flure fired=%s" % str(lflure.call("_trigger")))
	for _lw in range(24):
		scene.call("headless_advance", 0.5)
	gs.snap_character_to("aster", Vector3(26.4, 0.1, 4.8))
	gs.snap_character_to("peris", Vector3(26.6, 0.1, 5.6))
	gs.snap_character_to("endo", Vector3(27.2, 0.1, 6.4))
	scene.call("headless_advance", 0.5)
	var channels: Array = chunk.get("_channels")
	(channels[3] as Node).call("hold", 14.0)
	print("[probe] section 3 held")
	gs.command_move_to_pos("aster", Vector3(37.2, 0.1, 6.2))
	gs.command_move_to_pos("peris", Vector3(37.2, 0.1, 6.6))
	gs.command_move_to_pos("endo", Vector3(37.2, 0.1, 7.0))
	for half in range(28):
		scene.call("headless_advance", 0.5)
		var pa: Vector3 = gs.get_position("aster")
		var pp: Vector3 = gs.get_position("peris")
		var pe: Vector3 = gs.get_position("endo")
		print("[probe] t=%4.1fs A=(%.1f,%.1f)m%s P=(%.1f,%.1f)m%s E=(%.1f,%.1f)m%s" % [
			0.5 * float(half + 1),
			pa.x, pa.z, "1" if gs.is_moving("aster") else "0",
			pp.x, pp.z, "1" if gs.is_moving("peris") else "0",
			pe.x, pe.z, "1" if gs.is_moving("endo") else "0"])
		if pa.x > 36.3 and pp.x > 36.3 and pe.x > 36.3:
			print("[probe] ALL ACROSS at t=%.1fs" % (0.5 * float(half + 1)))
			break
	quit(0)
