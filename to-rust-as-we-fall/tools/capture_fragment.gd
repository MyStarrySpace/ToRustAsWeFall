extends SceneTree

## Capture a view of any PREVIEW_ENTRIES fragment (the whole chunk framed by its mesh AABB).
##   FRAG=boss_showcase [YAW=0.4] [ELEV=0.30] [DIST=1.6] [SEED=0] [OUT_DIR=<scratchpad>] \
##     [FOG=off] [CLIP=<max dist from median mesh center — drops stray outliers from framing>] \
##     [OCCL=off — freeze the see-through dissolve (top-down shots)] [LABELS=off — hide Label3D verbs] \
##     [LIGHT=1 — add a key+fill directional rig for dark scenes] \
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
	if OS.get_environment("FOG") == "off":
		scene.set("fog_of_war_enabled", false)
	for _i in range(120):
		await process_frame
	var chunk = scene.get("_active_chunk")
	if chunk != null:
		(chunk as Node).set_process(false)
	_defade(scene)
	_hide_canvas(scene)
	if OS.get_environment("OCCL") == "off":
		var mgr = scene.get("_occlusion_mgr")
		if mgr != null:
			(mgr as Node).set_process(false)
		RenderingServer.global_shader_parameter_set("player_world_pos", Vector3(0.0, -100000.0, 0.0))
	if OS.get_environment("LABELS") == "off":
		_hide_labels(chunk if chunk != null else scene)
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
	var clip := float(OS.get_environment("CLIP")) if OS.get_environment("CLIP") != "" else 0.0
	if clip > 0.0 and meshes.size() > 2:
		var med := _median_center(meshes)
		var kept: Array = []
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi.mesh != null and (mi.global_transform * mi.mesh.get_aabb()).get_center().distance_to(med) <= clip:
				kept.append(m)
		if kept.size() > 0:
			meshes = kept
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
	if OS.get_environment("LIGHT") != "":
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-62, -34, 0)
		key.light_energy = 1.7
		get_root().add_child(key)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-20, 140, 0)
		fill.light_energy = 0.6
		get_root().add_child(fill)
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.global_position = center + Vector3(sin(yaw), elev, cos(yaw)).normalized() * span * dist_k
	cam.look_at(center, Vector3.UP)
	cam.far = span * 6.0
	cam.current = true
	for _j in range(16):
		await process_frame
	# Re-hide right before the frame is taken: some tags (branch reward items,
	# world-item nameplates) spawn only after the chunk's runtime state
	# initializes, well past the first hide pass — sweep the WHOLE tree, and all
	# text mechanisms (Label3D, Sprite3D plates, late CanvasLayers), so
	# LABELS=off means what it says.
	if OS.get_environment("LABELS") == "off":
		# The preview's per-frame item sync re-shows nameplates every frame —
		# freeze the host's process before sweeping or the sweep loses the race.
		scene.set_process(false)
		_hide_labels(get_root())
		_hide_plates(get_root())
		_hide_canvas(get_root())
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

func _median_center(meshes: Array) -> Vector3:
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var c := (mi.global_transform * mi.mesh.get_aabb()).get_center()
		xs.append(c.x)
		ys.append(c.y)
		zs.append(c.z)
	xs.sort()
	ys.sort()
	zs.sort()
	var mid := xs.size() / 2
	return Vector3(xs[mid], ys[mid], zs[mid]) if xs.size() > 0 else Vector3.ZERO

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

func _hide_labels(n: Node) -> void:
	if n is Label3D:
		(n as Label3D).visible = false
	for c in n.get_children():
		_hide_labels(c)

func _hide_plates(n: Node) -> void:
	if n is Sprite3D:
		(n as Sprite3D).visible = false
	for c in n.get_children():
		_hide_plates(c)

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
