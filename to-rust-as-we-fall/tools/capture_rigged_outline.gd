extends SceneTree

## Pixel-check the outline mask on a RIGGED body. Flag-level tests can prove the
## copy is skinned; only the mask's own pixels prove the silhouette matches the
## pose on screen. Run WINDOWED (the mask viewport does not render headless):
##   Godot_v4.7-stable_win64_console.exe --path "." --position 20000,20000 \
##     --script res://tools/capture_rigged_outline.gd

const OUT_DIR := "C:/tmp/rig_poses"


func _initialize() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)

	var mask := OutlineMaskManager.new()
	world.add_child(mask)

	var body := FloraRig.new()
	world.add_child(body)
	if not body.setup("flure"):
		print("[OUTLINE] no rigged flure to capture")
		quit()
		return

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(1.6, 1.1, 1.9)
	cam.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	cam.current = true

	var key := DirectionalLight3D.new()
	world.add_child(key)
	key.rotation_degrees = Vector3(-52.0, 35.0, 0.0)

	await process_frame
	body.play("flure_spend")
	# let the collapse finish so the body on screen is the SPENT shape
	for i in 240:
		await process_frame

	mask.register(1, body.meshes(), Color.WHITE, false)
	for i in 6:
		await process_frame

	var entries: Dictionary = mask.get("_entries")
	var copies: Array = (entries.get(1, {}) as Dictionary).get("copies", [])
	var skinned := 0
	for record in copies:
		var copy := record["copy"] as MeshInstance3D
		if copy.skin != null:
			skinned += 1
	print("[OUTLINE] copies=%d skinned=%d" % [copies.size(), skinned])

	# the mask viewport IS the silhouette the composite edges; capture it directly
	_dump_mask(mask, "spent")

	# and the same body at REST, so the two silhouettes can be compared: a mask
	# stuck in bind space would draw the SAME shape for both
	body.rest()
	for i in 6:
		await process_frame
	mask.unregister(1)
	mask.register(1, body.meshes(), Color.WHITE, false)
	for i in 6:
		await process_frame
	_dump_mask(mask, "rest")

	var shot := root.get_viewport().get_texture().get_image()
	shot.save_png("%s/OUTLINE_scene_spent.png" % OUT_DIR)
	print("[OUTLINE] wrote captures")
	quit()


## Save the mask viewport with its ALPHA written into RGB — the mask fills its
## objects with the tint on a transparent background, so viewed as-is over white
## the silhouette is invisible.
func _dump_mask(mask: OutlineMaskManager, tag: String) -> void:
	var sub: SubViewport = mask.get("_sub")
	if sub == null:
		return
	var img := sub.get_texture().get_image()
	var lit := 0
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.15:
				lit += 1
			out.set_pixel(x, y, Color(a, a, a))
	print("[OUTLINE] %s mask lit texels = %d" % [tag, lit])
	out.save_png("%s/OUTLINE_mask_%s.png" % [OUT_DIR, tag])
