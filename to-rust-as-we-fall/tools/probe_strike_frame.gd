extends SceneTree
## Frame-mixing probe for the strike knockback on a WARPED scene: stand aster
## beside the wash_ascent pad sentry, let it detect -> charge -> strike, and
## watch aster's DATA position every tick. Any excursion outside the 26x8
## authoring frame is the corruption reported by the player-contract flake.
##
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##       --script tools/probe_strike_frame.gd

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
		push_error("boot failed")
		quit(1)
		return
	scene.call("headless_advance", 0.05)
	# park aster inside the pad watcher's detect ring (25.2, 6.9; detect 4.0)
	scene.call("headless_set_character_position", "aster", Vector3(24.6, 0.1, 5.2))
	scene.call("headless_set_character_position", "peris", Vector3(0.8, 0.1, 2.0))
	scene.call("headless_set_character_position", "endo", Vector3(0.8, 0.1, 4.0))
	for _f in range(3):
		await process_frame
	var hp0 := float(gs.get_stat("aster", "hp"))
	var struck := false
	var worst := Vector3.ZERO
	var off_frame := false
	for t in range(240):
		scene.call("headless_advance", 0.1)
		if t % 2 == 0:
			await process_frame
		var p: Vector3 = gs.get_position("aster")
		if p.z > 8.5 or p.x < -0.5 or p.x > 26.5:
			off_frame = true
			worst = p
			print("[STRIKE-PROBE] OFF-FRAME at t=%.1f aster=%s carry=%s" % [
				float(t) * 0.1, p, gs.is_external_traversal_active("aster")])
			break
		if not struck and float(gs.get_stat("aster", "hp")) < hp0:
			struck = true
			print("[STRIKE-PROBE] struck at t=%.1f aster=%s hp=%.0f" % [
				float(t) * 0.1, p, float(gs.get_stat("aster", "hp"))])
	print("[STRIKE-PROBE] RESULT struck=%s off_frame=%s worst=%s final=%s foe=%s" % [
		struck, off_frame, worst, gs.get_position("aster"),
		str((chunk.call("_fauna_by_id", "sapscrap_0")).call("get_state")) if chunk.call("_fauna_by_id", "sapscrap_0") != null else "?"])
	quit()
