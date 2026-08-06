extends SceneTree

## Eyeball the Beacon Hill tracery rib-merge mode. MODE=junction|sdf, OUT_DIR=<scratchpad>.
## Isolated-display launch only; see tools/README.md:
##   MODE=junction godot --path "." --script res://tools/cap_tracery.gd

func _init() -> void:
	var Base = load("res://scripts/generation/base_shape_builder.gd")
	var Lat = load("res://scripts/generation/lattice_builder.gd")
	var mode := OS.get_environment("MODE")
	if mode == "":
		mode = "junction"
	var spec: Dictionary = Base.generate("beacon_hill")
	var r := float(spec["radius"])
	var h := float(spec["height_total"])
	var root := Node3D.new()
	get_root().add_child(root)

	var bmi := MeshInstance3D.new()
	bmi.mesh = Base.base_mesh(spec)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.32, 0.42, 0.40)
	bmat.roughness = 0.9
	bmi.material_override = bmat
	root.add_child(bmi)

	var tr: Dictionary = Lat.tracery(r, h, {"rib_merge": mode})
	var fmi := MeshInstance3D.new()
	fmi.mesh = tr["frame"]
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.82, 0.78, 0.62)
	fmat.roughness = 0.8
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fmi.material_override = fmat
	root.add_child(fmi)

	var gmi := MeshInstance3D.new()
	gmi.mesh = tr["glass"]
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://resources/window_panes.gdshader")
	gmat.set_shader_parameter("energy", 2.4)
	gmi.material_override = gmat
	root.add_child(gmi)

	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.85, 0.5, 0.0)
	light.light_energy = 1.4
	root.add_child(light)
	var wenv := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_color = Color(0.45, 0.45, 0.5)
	env.ambient_light_energy = 0.7
	wenv.environment = env
	root.add_child(wenv)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 1.15
	root.add_child(cam)
	cam.look_at_from_position(Vector3(r * 0.45, h * 0.5, h * 1.9), Vector3(0.0, h * 0.45, 0.0), Vector3.UP)
	cam.current = true

	for _i in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var out := OS.get_environment("OUT_DIR")
	if out == "":
		out = "user://"
	img.save_png(out.path_join("tracery_%s.png" % mode))
	print("[TRCAP] %s frame_verts=%d" % [mode, (tr["frame"] as ArrayMesh).surface_get_array_len(0)])
	quit()
