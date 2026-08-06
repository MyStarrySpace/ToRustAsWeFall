extends SceneTree

## Verify the screen-space outline in the REAL Aster scene (real room model, real walls, real game camera, real
## OutlineMaskManager wired by the sequence). Loads aster_sim, runs past the intro fade, force-highlights every
## OutlineSurfaceTarget, and screenshots the game camera. Isolated-display launch only; see tools/README.md:
##   godot --path "." --script res://tools/capture_aster_outline.gd

func _init() -> void:
	var scene: Node = load("res://scenes/tutorial/aster_sim.tscn").instantiate()
	get_root().add_child(scene)
	for _i in range(150):
		await process_frame
	# Clear any lingering intro fade so the room is visible for the shot.
	_defade(scene)
	var targets: Array = []
	_collect(scene, targets)
	# Hover-highlight one (white), and queue-feedback another (char tint) so the capture shows both states.
	var named := {}
	for t in targets:
		named[str(t.name)] = t
	# Realistic case: ONE object hovered (white), the drink machine queued (servicing-char green) — the two states
	# the player actually sees, not every target at once.
	if named.has("RoomTargetDesk"):
		named["RoomTargetDesk"].call("set_highlight", true)
	if named.has("RoomTargetDrinkMachine"):
		named["RoomTargetDrinkMachine"].call("begin_queued_feedback", Vector3.ZERO, Color(0.36, 0.91, 0.5, 1.0))
	for _j in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("res://aster_outline_cap.png")
	print("[ASTERCAP] saved aster_outline_cap.png — %d outline targets: %s" % [targets.size(), str(named.keys())])
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
