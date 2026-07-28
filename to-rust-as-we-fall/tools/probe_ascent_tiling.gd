extends SceneTree
## Datum probe for the wash-ascent tiling laws: per-row deck seam errors and
## water-band vertex geometry (angular span, height span, fitted climb slope).
## Run headless when the seam/band asserts go red — numbers, never eyes.
##
##   ../Godot_v4.7-stable_win64_console.exe --headless --path "." \
##       --script tools/probe_ascent_tiling.gd

func _initialize() -> void:
	var packed = load("res://scenes/fragments/fragment_preview.tscn")
	var scene = packed.instantiate()
	scene.set("preview_menu", false)
	scene.set("preview_chunk", "wash_ascent")
	get_root().add_child(scene)
	for _i in range(30):
		await process_frame
	var chunk = scene.find_child("Chunk_wash_ascent", true, false)
	if chunk == null:
		push_error("chunk not found")
		quit(1)
		return
	var realized = chunk.get("_realized_root")
	var arc = load("res://scripts/game/world/channels_arc.gd")
	# deck tiles: worst seam error per row (flat z), plus one sample breakdown
	var rows: Dictionary = {}
	for piece in (realized as Node3D).get_children():
		if not (piece is Node3D):
			continue
		var p3 := piece as Node3D
		if str(p3.get_meta("cluster", "")) != "structure_deck":
			continue
		for ex in [-1.0, 1.0]:
			var edge: Vector3 = p3.global_transform * Vector3(float(ex), 0.0, 0.0)
			var wa: Dictionary = arc.world_to_arc(edge)
			var expected: float = arc.arc_pos(float(wa["s"]), 0.0).y
			var err: float = edge.y - expected
			var lane_key := snappedf(float(wa["lane"]), 0.1)
			if not rows.has(lane_key) or absf(err) > absf(float(rows[lane_key][0])):
				rows[lane_key] = [err, p3.name, edge, float(wa["s"])]
	var keys: Array = rows.keys()
	keys.sort()
	for k in keys:
		var e: Array = rows[k]
		print("[SEAM] lane=%5.1f  err=%+.4f  %s  s=%.2f" % [float(k), float(e[0]), str(e[1]), float(e[3])])
	# water bands: geometry of the first deck band's water surface
	var sw: Array = chunk.get("_section_water")
	for entry in sw:
		if str(entry["kind"]) != "deck":
			continue
		var node: Node3D = entry["node"]
		var mis: Array = []
		var stack: Array = [node]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				mis.append(n)
			for c in n.get_children():
				stack.append(c)
		print("[BAND] s0=%.1f node=%s mesh_instances=%d" % [float(entry["s0"]), node.name, mis.size()])
		for mi_v in mis:
			var mi := mi_v as MeshInstance3D
			for si in range(mi.mesh.get_surface_count()):
				var arrays: Array = mi.mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var tmin := 1e9
				var tmax := -1e9
				var ymin := 1e9
				var ymax := -1e9
				var rmin := 1e9
				var rmax := -1e9
				var t0 := 0.0
				var first := true
				for v in verts:
					var w: Vector3 = mi.global_transform * v
					var t := atan2(w.z, w.x)
					if first:
						t0 = t
						first = false
					t = wrapf(t - t0, -PI, PI)
					tmin = minf(tmin, t)
					tmax = maxf(tmax, t)
					ymin = minf(ymin, w.y)
					ymax = maxf(ymax, w.y)
					var r := Vector2(w.x, w.z).length()
					rmin = minf(rmin, r)
					rmax = maxf(rmax, r)
				print("[BAND]   surf %d: %d verts  theta[%.4f..%.4f]  y[%.3f..%.3f]  r[%.2f..%.2f]" % [
					si, verts.size(), tmin, tmax, ymin, ymax, rmin, rmax])
		break
	quit()
