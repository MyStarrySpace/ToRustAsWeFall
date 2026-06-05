extends SceneTree

## Dev capture: draw a PathRenderer's line over a floor and screenshot it, to see whether the
## movement path is visible at all. Run WITH a display:
##   ../Godot_v4.6.1-stable_win64_console.exe --path "." --script res://tools/capture_path.gd

const PathRendererScript := preload("res://scripts/game/world/path_renderer.gd")

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	current_scene = root

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -30, 0)
	root.add_child(light)

	# A floor so the line has context.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.18, 0.2, 0.24)
	floor_mi.material_override = fmat
	root.add_child(floor_mi)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 7.0, 7.0)
	cam.look_at_from_position(cam.position, Vector3(0.5, 0, 0.5), Vector3.UP)
	root.add_child(cam)

	# A PathRenderer driven by a REAL GameState move (the gameplay source #1).
	var GameStateScript := load("res://scripts/system/core/game_state.gd")
	var SchedulerClass := load("res://bin/event_scheduler.gdextension") if false else null
	var gs = GameStateScript.new()
	gs.scheduler = ClassDB.instantiate("EventScheduler")
	gs.register_character("runner", Vector3(-3, 0, -3), 3.0)
	gs.command_move_to_pos("runner", Vector3(3, 0, 2))
	gs.scheduler.advance_ticks(0.4)
	var pr = PathRendererScript.new()
	root.add_child(pr)
	pr.color = Color(1.0, 0.7, 0.3)
	pr.set_running(true)
	pr.setup(gs, "runner", Color(1.0, 0.7, 0.3))
	await process_frame
	print("[CAPTURE] game_state moving=%s remaining_points=%d" % [str(gs.is_moving("runner")), pr._remaining_points().size()])

	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://path_capture.png")
	print("[CAPTURE] path -> res://path_capture.png")
	quit()
