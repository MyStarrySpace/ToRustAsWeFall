extends SceneTree

## Focused regression for the Cleanstreets roguelite district contract. It keeps the expensive all-biome seed
## sweep separate while proving one complete generated stretch, authored scene loading, risk-cell seating, and
## the flat-space damage coverage used after the visible world is wrapped onto a helix.

const Biomes := preload("res://scripts/generation/biomes.gd")
const Generator := preload("res://scripts/generation/stretch_generator.gd")
const GeneratedChunkScene := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")

var checks := 0
var failures := 0


func _init() -> void:
	var registry: Dictionary = Biomes.validate()
	check(bool(registry.get("valid", false)), "biome registry validates: %s" % str(registry.get("errors", [])))
	check(Biomes.biome_ids().has("cleanstreets"), "Cleanstreets participates in run-depth rotation")
	check(GeneratedChunkScene != null, "generated stretch presenter with theme-hazard runtime loads")
	var clean_theme: Dictionary = Biomes.theme_contract_for("cleanstreets", 71926)
	var landmark_def := (clean_theme.get("landmarks", []) as Array)[0] as Dictionary
	check(str(landmark_def.get("asset_contract", "")) == "editable_3d_v1",
		"toll pavilion declares the portable editable-asset contract")
	for model_v in landmark_def.get("editable_assets", []):
		check_editable_model(str(model_v))
	var route_def := (clean_theme.get("route_setpieces", []) as Array)[0] as Dictionary
	check(str(route_def.get("asset_contract", "")) == "editable_3d_v1",
		"stud lane declares the portable editable-asset contract")
	for model_v in route_def.get("editable_assets", []):
		check_editable_model(str(model_v))

	var spec: Dictionary = Generator.generate({
		"id": "verify_cleanstreets",
		"title": "Verify Cleanstreets",
		"seed": 71926,
		"complexity_tier": "teaching",
		"biome": "cleanstreets",
	})
	check(bool(spec.get("success", false)), "Cleanstreets stretch generates: %s" % str(spec.get("validation", spec.get("error", ""))))
	if bool(spec.get("success", false)):
		var validation: Dictionary = Generator.validate_area_theme(spec)
		check(bool(validation.get("valid", false)), "Cleanstreets area theme validates: %s" % str(validation.get("errors", [])))
		var emitted_landmarks: Array = spec.get("themed_landmarks", [])
		check(emitted_landmarks.size() == 3,
			"one dominant toll pavilion plus a typed two-building infrastructure pair are emitted")
		var operations: Array = spec.get("infrastructure_operations", [])
		check(operations.size() == 1, "one bounded infrastructure operation is emitted")
		if not operations.is_empty():
			var operation := operations[0] as Dictionary
			check(str(operation.get("commodity", "")) == "fabricated_goods",
				"Cleanstreets supply-chain pair routes fabricated goods")
			check(str(operation.get("source_action", "")) == "DISPATCH PARTS"
					and str(operation.get("receiver_action", "")) == "CLEAR RECEIVING",
				"service endpoints expose mechanical verbs rather than generic click copy")
			check(str(operation.get("source_preview", "")) != ""
					and str(operation.get("receiver_preview", "")) != "",
				"both commits preview their exact consequence")
		for landmark_v in emitted_landmarks:
			var emitted := landmark_v as Dictionary
			if str(emitted.get("contract_id", "")) != "generated_infrastructure_landmark_v1":
				continue
			var wrapper := load(str(emitted.get("scene", ""))) as PackedScene
			check(wrapper != null, "%s authored wrapper loads" % str(emitted.get("kind", "infrastructure")))
			if wrapper != null:
				var instance := wrapper.instantiate() as Node3D
				check(not _has_scene_local_primitive(instance),
					"%s visible geometry comes from its portable OBJ" % str(emitted.get("kind", "infrastructure")))
				instance.free()
		var setpieces: Array = spec.get("themed_setpieces", [])
		check(setpieces.size() >= 3, "several hostile-architecture cells create a repeated street system")
		var risk_cells := {}
		for risk_v in spec.get("navigation_grid", {}).get("risk_cell_list", []):
			if risk_v is Dictionary:
				var raw: Array = (risk_v as Dictionary).get("cell", [])
				if raw.size() >= 2:
					risk_cells["%d:%d" % [int(raw[0]), int(raw[1])]] = true
		for setpiece_v in setpieces:
			var setpiece := setpiece_v as Dictionary
			var cell: Array = setpiece.get("risk_cell", [])
			check(cell.size() >= 2 and risk_cells.has("%d:%d" % [int(cell[0]), int(cell[1])]),
				"%s sits on a route-preview risk cell" % str(setpiece.get("id", "setpiece")))
		if not setpieces.is_empty():
			var first := setpieces[0] as Dictionary
			var packed := load(str(first.get("scene", ""))) as PackedScene
			check(packed != null, "authored stud-lane scene loads")
			if packed != null:
				var lane := packed.instantiate() as Node3D
				check(lane != null and lane.find_child("HostileArchitecture", true, false) != null,
					"stud lane keeps its visible fixtures as scene nodes")
				if lane != null:
					check(not _has_scene_local_primitive(lane),
						"stud lane visible geometry comes from portable assets, not scene-local primitives")
					lane.call("configure", first)
					var p := _vec3(first.get("position", []))
					check(bool(lane.call("covers_flat", p)), "stud lane covers its emitted risk-cell center")
					check(not bool(lane.call("covers_flat", p + Vector3(3.0, 0.0, 3.0))),
						"stud damage remains local to the visible fixture")
					lane.free()
	var pavilion_packed := load(str(landmark_def.get("scene", ""))) as PackedScene
	check(pavilion_packed != null, "authored toll-pavilion wrapper loads external model sources")
	if pavilion_packed != null:
		var pavilion := pavilion_packed.instantiate() as Node3D
		check(not _has_scene_local_primitive(pavilion),
			"toll pavilion visible geometry comes from portable assets, not scene-local primitives")
		pavilion.free()
	print("CLEANSTREETS GENERATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)


func check_editable_model(path: String) -> void:
	var mesh := load(path) as Mesh
	check(mesh != null, "%s imports as an editable mesh" % path.get_file())
	check(FileAccess.file_exists(path.trim_suffix(".obj") + ".mtl") \
		and FileAccess.file_exists(path.trim_suffix(".obj") + ".png"),
		"%s keeps its material and paintable texture beside the model" % path.get_file())
	if mesh == null:
		return
	var has_complete_uvs := mesh.get_surface_count() > 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if vertices.is_empty() or uvs.size() != vertices.size():
			has_complete_uvs = false
	check(has_complete_uvs, "%s has UVs for every imported vertex" % path.get_file())


func _has_scene_local_primitive(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is PrimitiveMesh:
		return true
	for child in node.get_children():
		if _has_scene_local_primitive(child):
			return true
	return false


func _vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO
