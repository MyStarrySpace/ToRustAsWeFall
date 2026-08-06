extends SceneTree

## Verify the screen-space outline + glow inside a CHUNK preview (other than the tutorial rooms). Loads
## fragment_preview.tscn directly onto a chunk, runs past intro, force-highlights every OutlineSurfaceTarget
## (one queued for the glow), and screenshots the game camera. Pick the chunk with the CHUNK env var:
## Isolated-display launch only; see tools/README.md:
##   CHUNK=flora_garden godot --path "." --script res://tools/capture_chunk_outline.gd
## Writes chunk_outline_<id>.png.

func _init() -> void:
	var chunk_id := OS.get_environment("CHUNK")
	if chunk_id == "":
		chunk_id = "flora_garden"
	var scene: Node = load("res://scenes/fragments/fragment_preview.tscn").instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", chunk_id)
	get_root().add_child(scene)
	for _i in range(180):
		await process_frame
	_defade(scene)
	var targets: Array = []
	_collect(scene, targets)
	# Frame the targets with a DEDICATED current camera (the player-follow cam looks at empty ground in chunks
	# whose content sits around the edges). The mask manager syncs to whatever camera is current, so this works.
	if targets.size() > 0:
		var center := Vector3.ZERO
		for t in targets:
			center += (t as Node3D).global_position
		center /= float(targets.size())
		var spread := 2.0
		for t in targets:
			spread = maxf(spread, (t as Node3D).global_position.distance_to(center))
		var dist := maxf(4.0, spread * 1.8 + 3.0)
		var cam := Camera3D.new()
		get_root().add_child(cam)
		cam.global_position = center + Vector3(0, dist * 0.7, dist)
		cam.look_at(center, Vector3.UP)
		cam.current = true
	# Hover-highlight all but one; queue the first so the capture shows both the outline and the energy glow.
	for idx in range(targets.size()):
		if idx == 0:
			targets[idx].call("begin_queued_feedback", Vector3.ZERO, Color(0.36, 0.91, 0.5, 1.0))
		else:
			targets[idx].call("set_highlight", true)
	for _j in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "res://chunk_outline_%s.png" % chunk_id
	img.save_png(path)
	print("[CHUNKCAP] %s — %d outline targets" % [path, targets.size()])
	quit()

func _collect(n: Node, out: Array) -> void:
	if n is OutlineSurfaceTarget:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _defade(n: Node) -> void:
	if n is ColorRect and (n as ColorRect).color.a > 0.5 and (n as ColorRect).size.x > 100.0:
		(n as ColorRect).visible = false
	for c in n.get_children():
		_defade(c)
