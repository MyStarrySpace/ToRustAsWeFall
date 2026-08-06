extends SceneTree

## Capture a render of a generation-preview chunk so the output is eyeball-able.
##   SEED=3 [CHUNK=shape_grammar|creature_grammar] [ANGLE=low] \
##     godot --path "." --script res://tools/capture_shape_grammar.gd
## Isolated-display launch only; see tools/README.md.
## Writes <chunk>_<seed>.png.

func _init() -> void:
	var seed_str := OS.get_environment("SEED")
	var seed_val := int(seed_str) if seed_str != "" else 1
	var chunk_id := OS.get_environment("CHUNK")
	if chunk_id == "":
		chunk_id = "shape_grammar"
	var scene: Node = load("res://scenes/fragments/fragment_preview.tscn").instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", chunk_id)
	var cfg := {"seed": seed_val}
	if OS.get_environment("ALGO") != "":
		cfg["algorithm"] = int(OS.get_environment("ALGO"))
	scene.set("preview_chunk_config", cfg)
	get_root().add_child(scene)
	for _i in range(150):
		await process_frame
	_defade(scene)
	var chunk = scene.get("_active_chunk")
	if chunk != null and chunk.get("fragment") != null:
		var ys := {}
		for fl in chunk.get("fragment").floors:
			var y := snappedf(float((fl["pos"] as Vector3).y), 0.1)
			ys[y] = int(ys.get(y, 0)) + 1
		print("[SGCAP] floor boxes by height: %s ; walls: %d" % [str(ys), chunk.get("fragment").walls.size()])
	# Clean architecture shot: perception overlays OFF + HUD/panels hidden. OVERLAY=peris|aster
	# instead turns exactly that overlay ON (fog/data-view eyeballing).
	var want_overlay := OS.get_environment("OVERLAY")
	var st = scene.get("_overlay_states")
	if st is Dictionary:
		for k in (st as Dictionary).keys():
			st[k] = str(k) == want_overlay
		if scene.has_method("_refresh_active_overlay"):
			scene.call("_refresh_active_overlay")
	_hide_canvas(scene)

	# Bounds from every visual mesh (the floor slab + grid tiles cover the generated footprint).
	# ANGLE=close frames only Creature_* nodes — the morphology close-up.
	var mn := Vector3(1e9, 0, 1e9)
	var mx := Vector3(-1e9, 0, -1e9)
	var meshes: Array = []
	if OS.get_environment("ANGLE") == "close":
		for n in _find_named(scene, "Creature_"):
			_collect_meshes(n, meshes)
		for n in _find_named(scene, "Hero_"):
			_collect_meshes(n, meshes)
	if meshes.is_empty():
		_collect_meshes(scene, meshes)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb := mi.global_transform * mi.mesh.get_aabb()
		mn.x = minf(mn.x, aabb.position.x); mn.z = minf(mn.z, aabb.position.z)
		mx.x = maxf(mx.x, aabb.position.x + aabb.size.x); mx.z = maxf(mx.z, aabb.position.z + aabb.size.z)
	var center := Vector3((mn.x + mx.x) * 0.5, 0, (mn.z + mx.z) * 0.5)
	var extent := maxf(mx.x - mn.x, mx.z - mn.z)

	# Isometric tilt (not straight top-down) so stacked floors and ladders read in the shot.
	# ANGLE=low gives a near-horizon side view — the check that upper decks really sit a level up.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * 1.05 + 6.0
	get_root().add_child(cam)
	if OS.get_environment("ANGLE") == "low":
		cam.size = extent * 0.7 + 6.0
		cam.global_position = center + Vector3(extent * 0.95, extent * 0.22 + 6.0, extent * 0.4)
	elif OS.get_environment("ANGLE") == "close":
		cam.size = extent * 0.6 + 2.0
		center.y += 1.0
		cam.global_position = center + Vector3(extent * 0.12, extent * 0.16 + 2.4, extent * 0.55 + 6.0)
	elif OS.get_environment("ANGLE") == "party":
		# frame ~gameplay distance around the party (the view the player actually judges)
		var chars = scene.get("_characters")
		if chars is Dictionary and not (chars as Dictionary).is_empty():
			for cid in (chars as Dictionary).keys():
				var cn = (chars as Dictionary)[cid]
				if cn is Node3D:
					center = (cn as Node3D).global_position
					break
		cam.size = 24.0
		cam.global_position = center + Vector3(4.0, 20.0, 13.0)
	else:
		cam.global_position = center + Vector3(extent * 0.45, extent * 0.85 + 10.0, extent * 0.6)
	cam.look_at(center, Vector3.UP)
	cam.current = true

	for _j in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	# NEVER write into the project tree (project hygiene). Honour an explicit OUT_DIR (the scratchpad);
	# fall back to user:// — never res://.
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var path := out_dir.path_join("%s_%d.png" % [chunk_id, seed_val])
	img.save_png(path)
	print("[SGCAP] %s — extent %.1f, %d meshes" % [path, extent, meshes.size()])
	quit()

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

func _find_named(n: Node, prefix: String) -> Array:
	var out: Array = []
	if str(n.name).begins_with(prefix):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_named(c, prefix))
	return out

func _hide_canvas(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_canvas(c)

func _defade(n: Node) -> void:
	if n is ColorRect and (n as ColorRect).color.a > 0.5 and (n as ColorRect).size.x > 100.0:
		(n as ColorRect).visible = false
	for c in n.get_children():
		_defade(c)
