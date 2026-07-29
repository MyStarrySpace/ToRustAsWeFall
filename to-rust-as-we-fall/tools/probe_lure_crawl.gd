extends SceneTree
## Datum probe for a lured sentry's crawl: fires the lonely flure with the
## sentry un-alerted, then samples the sentry's position, state, and motion
## every simulated second so a stall shows up as numbers (position deltas),
## never as a guess. Also dumps the wall cells along the crawl corridor.
##
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##       --script tools/probe_lure_crawl.gd

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
	var flure = chunk.find_child("LonelyFlureObject", true, false)
	if chunk == null or gs == null or flure == null:
		push_error("probe boot failed")
		quit(1)
		return
	scene.call("headless_advance", 0.05)
	var walls: Array = chunk.get("_wall_cells")
	var corridor: Array = []
	for c in walls:
		var cx := float((c as Array)[0]) if c is Array else float((c as Vector2i).x)
		var cz := float((c as Array)[1]) if c is Array else float((c as Vector2i).y)
		if cx >= 16.0 and cx <= 28.0 and cz >= 4.0:
			corridor.append([cx, cz])
	print("[probe] wall cells x16-28 z4+: %s" % [corridor])
	gs.snap_character_to("aster", Vector3(17.6, 0.1, 1.4))
	gs.snap_character_to("peris", Vector3(18.3, 0.1, 2.3))
	gs.snap_character_to("endo", Vector3(18.3, 0.1, 3.0))
	# reproduce the playthrough's context: the sentry has roamed ~40s before
	# the flure fires, so its position is a roam hop, not the boot anchor
	for _r in range(80):
		scene.call("headless_advance", 0.5)
	var pre: Vector3 = gs.get_position("sapscrap_0")
	print("[probe] pre-fire sentry pos=(%.2f, %.2f) state=%s" % [pre.x, pre.z,
		str((chunk.call("_fauna_by_id", "sapscrap_0")).call("get_state"))])
	flure.set("active_character", "aster")
	await process_frame
	var fired: bool = bool(flure.call("_trigger"))
	print("[probe] flure fired=%s" % fired)
	var foe = chunk.call("_fauna_by_id", "sapscrap_0")
	for sec in range(34):
		scene.call("headless_advance", 1.0)
		var pos: Vector3 = gs.get_position("sapscrap_0")
		print("[probe] t=%2ds state=%-8s pos=(%.2f, %.2f) moving=%s hp=%.0f" % [
			sec + 1, str(foe.call("get_state")), pos.x, pos.z,
			str(gs.is_moving("sapscrap_0")), float(foe.get("_hp"))])
		if float(foe.get("_hp")) < float(foe.get("max_hp")):
			print("[probe] WASH BITE at t=%ds" % (sec + 1))
			break
	quit(0)
