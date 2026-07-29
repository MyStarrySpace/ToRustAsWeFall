extends SceneTree
## Datum probe for the wash_ascent flure CLICK path: drives the REAL interaction
## commitment (the same coordinator a right-click uses) from (a) beside the
## flure — the legitimate player position — and (b) from across a wash span,
## and reports arrival, trigger, refusal, and whether a mid-walk sweep killed
## the committed interaction. Numbers, never eyes.
##
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##       --script tools/probe_flure_click.gd

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
	var near_flure: Array = []
	for c in walls:
		var cs := str(c)
		if cs.contains("(14") or cs.contains("(15") or cs.contains("(16") 				or cs.contains("(17") or cs.contains("(18") or cs.contains("(19"):
			near_flure.append(c)
	print("[FLURE-PROBE] wall cells near: %s" % [near_flure])
	var grid = gs.grid
	for cell in [Vector2i(17,1), Vector2i(17,2), Vector2i(16,1), Vector2i(18,1), Vector2i(17,0)]:
		print("[FLURE-PROBE] walkable %s = %s" % [cell, grid.is_walkable(cell.x, cell.y, {}, {}, 0)])

	# --- case A: the REAL right-click chain from beside the flure ---
	scene.call("headless_set_character_position", "aster", Vector3(16.4, 0.1, 1.6))
	scene.call("headless_set_selected_characters", ["aster"])
	for _f in range(3):
		await process_frame
	# fire the same signal a right-click on the hovered interactable emits
	flure.emit_signal("interaction_requested", flure, flure.global_position)
	var fired_a := false
	for _t in range(28):
		scene.call("headless_advance", 0.25)
		await process_frame
		await process_frame
		var foe = chunk.call("_fauna_by_id", "sapscrap_0")
		var st := str(foe.call("get_state")) if foe != null else "?"
		if _t % 4 == 0:
			print("[FLURE-PROBE] t=%.1f aster=%s moving=%s carry=%s foe=%s report=%s" % [
				float(_t) * 0.25, gs.get_position("aster"), gs.is_moving("aster"),
				gs.is_external_traversal_active("aster"), st,
				str(flure.get("_last_activation_report"))])
		if foe != null and st == "lured":
			fired_a = true
			break
	print("[FLURE-PROBE] near-click RESULT: fired=%s" % fired_a)

	# --- case B: click from across span 2 (the contract-sweep case) ---
	chunk.call("reset_preview_state")
	scene.call("headless_set_character_position", "aster", Vector3(22.0, 0.1, 3.0))
	for _f2 in range(3):
		await process_frame
	gs.command_move_to_pos("aster", Vector3(17.6, 0.1, 1.4))
	var swept_mid := false
	var arrived := false
	for _t2 in range(160):
		scene.call("headless_advance", 0.1)
		await process_frame
		if bool(gs.is_external_traversal_active("aster")):
			swept_mid = true
		if gs.get_position("aster").distance_to(Vector3(17.6, 0.1, 1.4)) < 1.0 \
				and not gs.is_moving("aster"):
			arrived = true
			break
	print("[FLURE-PROBE] far-walk: swept_mid=%s arrived=%s aster=%s" % [
		swept_mid, arrived, gs.get_position("aster")])
	quit()
