extends SceneTree

## Capture a view of any PREVIEW_ENTRIES fragment (the whole chunk framed by its mesh AABB).
##   FRAG=boss_showcase [YAW=0.4] [ELEV=0.30] [DIST=1.6] [SEED=0] [OUT_DIR=<scratchpad>] \
##     ../Godot_v4.7-stable_win64.exe --path "." --position 20000,20000 --script res://tools/capture_fragment.gd
## Writes <frag>_view.png to OUT_DIR (scratchpad) — NEVER the project tree.

func _init() -> void:
	var frag_id := OS.get_environment("FRAG")
	if frag_id == "":
		frag_id = "boss_showcase"
	var yaw := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 0.4
	var elev := float(OS.get_environment("ELEV")) if OS.get_environment("ELEV") != "" else 0.30
	var dist_k := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 1.6
	var scene: Node = load("res://scenes/fragments/fragment_preview.tscn").instantiate()
	scene.set("preview_menu", false)
	var entry: Dictionary = scene.get_script().get_preview_entry(frag_id)
	scene.set("preview_chunk", str(entry.get("chunk", frag_id)))
	var cfg: Dictionary = (entry.get("config", {}) as Dictionary).duplicate(true)
	if OS.get_environment("SEED") != "":
		cfg["seed"] = int(OS.get_environment("SEED"))
	scene.set("preview_chunk_config", cfg)
	get_root().add_child(scene)
	for _i in range(120):
		await process_frame
	var chunk = scene.get("_active_chunk")
	if chunk != null:
		(chunk as Node).set_process(false)
	_defade(scene)
	_hide_canvas(scene)
	var st = scene.get("_overlay_states")
	if st is Dictionary:
		for k in (st as Dictionary).keys():
			st[k] = false
		if scene.has_method("_refresh_active_overlay"):
			scene.call("_refresh_active_overlay")
	for _k in range(4):
		await process_frame
	# frame the chunk's meshes
	var meshes: Array = []
	_collect_meshes(chunk if chunk != null else scene, meshes)
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb := mi.global_transform * mi.mesh.get_aabb()
		for corner in range(8):
			var c := aabb.position + Vector3(aabb.size.x * (corner & 1), aabb.size.y * ((corner >> 1) & 1), aabb.size.z * ((corner >> 2) & 1))
			mn = mn.min(c)
			mx = mx.max(c)
	var center := (mn + mx) * 0.5
	var span := maxf(mx.x - mn.x, maxf(mx.y - mn.y, mx.z - mn.z))
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.global_position = center + Vector3(sin(yaw), elev, cos(yaw)).normalized() * span * dist_k
	cam.look_at(center, Vector3.UP)
	cam.far = span * 6.0
	cam.current = true
	for _j in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var path := out_dir.path_join("%s_view.png" % frag_id)
	img.save_png(path)
	print("[FRAGCAP] %s — span %.1f, %d meshes" % [path, span, meshes.size()])
	quit()

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

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
