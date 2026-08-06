extends SceneTree

## Visual capture harness: boots a sim WINDOWED, forces the ground overlays into their visible
## states (hover grid under the cursor, a committed move's ribbon + dest marker), and saves
## viewport PNGs for eyeballing. Isolated-display launch only; see tools/README.md:
##   godot --path . -s tools/capture_overlays.gd -- <scene> <out_prefix>

func _init():
	var args := OS.get_cmdline_user_args()
	var scene_path := "res://scenes/tutorial/aster_sim.tscn"
	var prefix := "aster"
	if args.size() >= 1 and not args[0].begins_with("--"):
		scene_path = args[0]
	if args.size() >= 2:
		prefix = args[1]
	_run(scene_path, prefix)

func _run(scene_path: String, prefix: String) -> void:
	var inst: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(inst)
	for i in range(30):
		await process_frame
	# Drive a few seconds so fade-ins clear.
	for i in range(40):
		if inst.has_method("headless_advance"):
			inst.headless_advance(0.1, 0.05)
		await process_frame

	var player = inst.get("_player")
	var gs = inst.get("_game_state")
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	print("[CAP] cam=", cam.global_position if cam else null, " player=", player.global_position if player else null)

	# 1) HOVER: park the mouse over the floor two units ahead of the player.
	if player != null and cam != null:
		var hover_world: Vector3 = player.global_position + Vector3(1.5, 0, 1.5)
		var screen := cam.unproject_position(Vector3(hover_world.x, 0.2, hover_world.z))
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		motion.global_position = screen
		Input.parse_input_event(motion)
	for i in range(10):
		await process_frame
	_snap(prefix + "_hover.png")
	if player != null:
		print("[CAP] hover_grid visible=", player.get("_hover_grid").visible if player.get("_hover_grid") != null else "NONE",
			" pos=", player.get("_hover_grid").global_position if player.get("_hover_grid") != null else "-")
		print("[CAP] move_enabled=", player.get("_move_enabled"), " click_mode=", player.get("_click_mode"))
		var probe_screen: Vector2 = cam.unproject_position(player.global_position + Vector3(1.5, 0.05, 1.5))
		print("[CAP] raycast at parked point -> ", player.call("_raycast_ground", probe_screen))

	# 2) COMMITTED MOVE: ribbon + dest marker while walking.
	if gs != null and player != null:
		var char_id := str(player.get("char_id"))
		var dest: Vector3 = player.global_position + Vector3(2.5, 0, 2.5)
		gs.command_move_to_pos(char_id, dest)
		for i in range(6):
			if inst.has_method("headless_advance"):
				inst.headless_advance(0.05, 0.05)
			await process_frame
	_snap(prefix + "_move.png")
	if player != null and player.get("_dest_marker") != null:
		print("[CAP] dest_marker visible=", player.get("_dest_marker").visible, " pos=", player.get("_dest_marker").global_position)

	# 3) HOVER with movement ENABLED (the free-roam state the player reports from).
	if player != null and cam != null:
		player.call("set_move_enabled", true)
		var hover_world2: Vector3 = player.global_position + Vector3(1.5, 0, 1.5)
		var screen2: Vector2 = cam.unproject_position(Vector3(hover_world2.x, 0.2, hover_world2.z))
		var motion2 := InputEventMouseMotion.new()
		motion2.position = screen2
		motion2.global_position = screen2
		Input.parse_input_event(motion2)
		for i in range(10):
			await process_frame
		_snap(prefix + "_hover_enabled.png")
		print("[CAP] hover2 visible=", player.get("_hover_grid").visible, " pos=", player.get("_hover_grid").global_position)

	quit()

func _snap(filename: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://../" + filename)
	print("[CAP] saved ", filename)
