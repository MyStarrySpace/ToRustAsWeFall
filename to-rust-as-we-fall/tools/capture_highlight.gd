extends SceneTree

## Dev capture: build an object + OutlineSurfaceTarget, highlight it, and screenshot so the
## outline shader + surface particles can be eyeballed. Run WITH a display (not --headless):
##   ../Godot_v4.6.1-stable_win64_console.exe --path "." --script res://tools/capture_highlight.gd

const OutlineTarget := preload("res://scripts/game/objects/outline_surface_target.gd")

func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	current_scene = root

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_color = Color(0.4, 0.4, 0.45)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -40, 0)
	root.add_child(light)

	var cam := Camera3D.new()
	cam.position = Vector3(2.2, 1.8, 2.6)
	cam.look_at_from_position(cam.position, Vector3(0, 0.4, 0), Vector3.UP)
	root.add_child(cam)

	# The object: a couple of meshes (like the logbook console + screen).
	var obj := Node3D.new()
	root.add_child(obj)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.0, 0.5)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.3)
	box.material_override = mat
	box.position = Vector3(0, 0.5, 0)
	obj.add_child(box)

	# The in-game path: a meshless Interactable zone + its OutlineSurfaceTarget over the mesh,
	# linked exactly like _set_room_target_interaction_delegate does. HOVER the interactable
	# (it intercepts the ray in-game) and confirm it lights up the OBJECT's outline + particles.
	var Interactable := preload("res://scripts/game/objects/interactable.gd")
	var it = Interactable.new()
	obj.add_child(it)
	it.interaction_enabled = true
	var target = OutlineTarget.new()
	target.name = "Outline"
	obj.add_child(target)
	target.register_highlight_mesh(box)
	target.set_interaction_delegate(it)
	it.set_outline_target(target)
	it.set_hover_feedback(true)  # simulate hover on the zone

	await process_frame
	await process_frame
	await process_frame
	# Let particles build up to a steady state (lifetime ~3s ≈ 180 frames).
	for i in range(150):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("res://highlight_capture.png")
	print("[CAPTURE] outline+particles -> res://highlight_capture.png  shells=%d" % target.get_outline_shell_count())
	print("[CAPTURE] mesh_outline_active=%s particles_active=%s" % [str(target.has_active_mesh_outline()), str(target.has_active_outline_particles())])
	quit()
