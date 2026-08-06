extends SceneTree

## Art-review capture for the presentation-only Shelter 2 cutscene shell.
## The floor and WorldEnvironment are capture-only; runtime supplies the generated shelter.
## Isolated-display launch only; see tools/README.md.

const SCENE_PATH := "res://scenes/tutorial/shelter_2_aster_stim_cutscene.tscn"
const STAGING_CLIP := "shelter_2_staging"
const STIM_CLIP := "aster_stim_loop"
const STIM_LOOP_SECONDS := 2.8
const CAPTURE_TIMES := [0.0, 3.5, 10.0, 16.0]


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[SHELTER 2 CAPTURE] Could not load %s" % SCENE_PATH)
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	get_root().add_child(scene)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.025, 0.028)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.28, 0.32, 0.34)
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	get_root().add_child(environment_node)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12.0, 12.0)
	floor.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.055, 0.065, 0.062)
	floor_material.roughness = 0.94
	floor.material_override = floor_material
	floor.position = Vector3(0, -0.025, 0)
	get_root().add_child(floor)

	var camera := scene.get_node("CinematicCamera") as Camera3D
	var staging := scene.get_node("StagingAnimationPlayer") as AnimationPlayer
	var stim := scene.get_node("StimAnimationPlayer") as AnimationPlayer
	camera.current = true

	var output_dir := OS.get_environment("OUT_DIR")
	if output_dir == "":
		output_dir = ProjectSettings.globalize_path("user://shelter2_stim_qa")
	var make_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if make_error != OK:
		push_error("[SHELTER 2 CAPTURE] Could not create %s: %s" % [
			output_dir, error_string(make_error),
		])
		quit(1)
		return

	for time_seconds in CAPTURE_TIMES:
		staging.play(STAGING_CLIP)
		staging.seek(time_seconds, true)
		staging.pause()
		stim.play(STIM_CLIP)
		stim.seek(fmod(time_seconds, STIM_LOOP_SECONDS), true)
		stim.pause()
		for _frame in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var filename := "shelter2_stim_t%04d.png" % int(round(time_seconds * 10.0))
		var output_path := output_dir.path_join(filename)
		var error := get_root().get_texture().get_image().save_png(output_path)
		if error != OK:
			push_error("[SHELTER 2 CAPTURE] Failed %s: %s" % [
				output_path, error_string(error),
			])
			quit(1)
			return
		print("[SHELTER 2 CAPTURE] %.1fs -> %s" % [time_seconds, output_path])
	quit(0)
