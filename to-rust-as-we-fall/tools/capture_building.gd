extends SceneTree

## Capture a FACADE elevation of one showcase building (freezes the turntable so the front reads).
##   HERO=beacon_hill [YAW=0.5] [OUT_DIR=<scratchpad>] \
##     ../Godot_v4.7-stable_win64.exe --path "." --script res://tools/capture_building.gd
## Writes <hero>_facade.png to OUT_DIR (scratchpad) — NEVER the project tree.

func _init() -> void:
	var hero_id := OS.get_environment("HERO")
	if hero_id == "":
		hero_id = "beacon_hill"
	var yaw_str := OS.get_environment("YAW")
	var yaw := float(yaw_str) if yaw_str != "" else 0.5
	var scene: Node = load("res://scenes/fragments/fragment_preview.tscn").instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", "architecture_showcase")
	scene.set("preview_chunk_config", {"seed": 1})
	get_root().add_child(scene)
	for _i in range(120):
		await process_frame
	# freeze the turntable + face the chosen yaw
	var chunk = scene.get("_active_chunk")
	if chunk != null:
		(chunk as Node).set_process(false)
	var hero := _find_one(scene, "Hero_" + hero_id)
	if hero == null:
		print("[BLDCAP] hero not found: Hero_%s" % hero_id)
		quit()
		return
	(hero as Node3D).rotation = Vector3(0.0, yaw, 0.0)
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

	# world AABB of the hero's meshes
	var meshes: Array = []
	_collect_meshes(hero, meshes)
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
	var hgt := mx.y - mn.y

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = hgt * 1.18
	get_root().add_child(cam)
	cam.global_position = center + Vector3(hgt * 0.28, hgt * 0.10, hgt * 2.2)
	cam.look_at(center, Vector3.UP)
	cam.current = true

	for _j in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var out_dir := OS.get_environment("OUT_DIR")
	if out_dir == "":
		out_dir = "user://"
	var path := out_dir.path_join("%s_facade.png" % hero_id)
	img.save_png(path)
	print("[BLDCAP] %s — height %.1f, %d meshes" % [path, hgt, meshes.size()])
	quit()

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

func _find_one(n: Node, name_str: String) -> Node:
	if str(n.name) == name_str:
		return n
	for c in n.get_children():
		var f := _find_one(c, name_str)
		if f != null:
			return f
	return null

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
