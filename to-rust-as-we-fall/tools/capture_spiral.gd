extends SceneTree

## Dev capture: build ONLY the generated_stretch chunk (which now warps its own tiled floor + node dressing onto
## a helix) and screenshot it from above + at a 3/4 angle so the spiral reads. Loading the chunk directly (not the
## whole fragment_preview scene) avoids preloading every other chunk script. Run WITH a display (not --headless):
##   ../Godot_v4.7-stable_win64.exe --path "." --script res://tools/capture_spiral.gd -- --seed=7

func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1360, 900))
	var seed_val := 7
	var shape_name := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--seed="):
			seed_val = int(str(a).split("=")[1])
		elif str(a).begins_with("--shape="):
			shape_name = str(a).split("=")[1]

	var StretchGen = load("res://scripts/generation/stretch_generator.gd")
	# A long (setpiece) stretch so it wraps 2+ turns and the meta-template's drop/climbvine return points appear.
	var spec: Dictionary = StretchGen.generate({"seed": seed_val, "complexity_tier": "setpiece", "id": "spiral_capture", "budget": {"node_count": 12}})
	var config := {"spec": spec}
	# Plug the hub SHAPE in as a parameter: --shape=rect / hexagon / triangle / circle (default circle == spiral).
	if shape_name != "":
		config["hub_shape"] = {"type": "rect", "aspect": 1.7} if shape_name == "rect" else {"type": shape_name}

	var chunk: Node3D = load("res://scripts/fragments/chunks/generated_stretch_chunk.gd").new()
	chunk.call("configure_chunk", config)   # loads the spec before _ready builds it
	get_root().add_child(chunk)                       # _ready -> _build_chunk (warps floor + dressing)
	for i in range(30):
		await process_frame

	var cm = chunk.call("get_coord_map")
	var center := Vector3(0.0, 3.0, 0.0)
	if cm != null and "center" in cm:
		center = Vector3(cm.center.x, 3.0, cm.center.z)

	var cam := Camera3D.new()
	cam.fov = 60.0
	get_root().add_child(cam)
	cam.look_at_from_position(center + Vector3(0.0, 46.0, 34.0), center, Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62, -34, 0)
	key.light_energy = 1.7
	get_root().add_child(key)
	var amb := DirectionalLight3D.new()
	amb.rotation_degrees = Vector3(-20, 140, 0)
	amb.light_energy = 0.6
	get_root().add_child(amb)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var tag := shape_name if shape_name != "" else "circle"
	var out := "res://spiral_capture_%s_seed%d.png" % [tag, seed_val]
	get_root().get_texture().get_image().save_png(out)
	print("[CAPTURE] generated hub (shape=%s seed %d) -> %s | coord_map=%s" % [tag, seed_val, out, str(cm != null)])
	quit()
