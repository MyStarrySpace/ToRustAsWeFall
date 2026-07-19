extends SceneTree

## Focused integration contract for the browser fragment dressing and streamed Elevator occlusion.
## Run with:
##   godot --headless --path . --script res://tools/verify_preview_decoration_occlusion.gd

const FRAGMENT_CASES := [
	{
		"name": "stacks",
		"scene": "res://scenes/fragments/chunks/stacks_fragment_chunk.tscn",
		"length": 68.0,
		"width": 24.0,
		"wall_height": 4.0,
		"program": "archive",
	},
	{
		"name": "rings",
		"scene": "res://scenes/fragments/chunks/rings_fragment_chunk.tscn",
		"length": 72.0,
		"width": 30.0,
		"wall_height": 4.4,
		"program": "habitat",
	},
	{
		"name": "lockout",
		"scene": "res://scenes/fragments/chunks/lockout_fragment_chunk.tscn",
		"length": 60.0,
		"width": 18.0,
		"wall_height": 4.8,
		"program": "boundary",
	},
]

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	print("\n=== Preview decoration + occlusion integration ===")
	for case_data in FRAGMENT_CASES:
		await _verify_fragment(case_data)
	await _verify_elevator_streamed_chunks()

	if _failures.is_empty():
		print("\nPreview decoration + occlusion verification: ALL PASSED (%d checks)" % _checks)
		quit(0)
	else:
		print("\nPreview decoration + occlusion verification: %d FAILED / %d checks" % [
			_failures.size(), _checks])
		quit(1)


func _verify_fragment(case_data: Dictionary) -> void:
	var case_name := str(case_data["name"])
	var packed := load(str(case_data["scene"])) as PackedScene
	_check(packed != null, "%s standalone fragment scene loads" % case_name)
	if packed == null:
		return
	var chunk := packed.instantiate() as Node3D
	root.add_child(chunk)
	await process_frame

	var audit: Dictionary = chunk.call("get_decoration_audit")
	var decoration := chunk.get_node_or_null("LevelDecoration")
	_check(decoration != null and not audit.is_empty(),
		"%s invokes the shared LevelDecorator in standalone play" % case_name)
	_check(absf(float(audit.get("length_m", -1.0)) - float(case_data["length"])) < 0.01
		and absf(float(audit.get("width_m", -1.0)) - float(case_data["width"])) < 0.01
		and absf(float(audit.get("wall_height_m", -1.0)) - float(case_data["wall_height"])) < 0.01,
		"%s decoration uses the measured local floor and wall extents" % case_name)
	_check(str(audit.get("program", "")) == str(case_data["program"])
		and bool(audit.get("quality_passed", false)),
		"%s retains its canonical program and passes the decoration audit" % case_name)
	_check(int(audit.get("collision_shapes", -1)) == 0
		and int(audit.get("route_clearance_intrusions", -1)) == 0
		and decoration.find_children("*", "CollisionObject3D", true, false).is_empty()
		and decoration.find_children("*", "CollisionShape3D", true, false).is_empty()
		and decoration.find_children("*", "NavigationRegion3D", true, false).is_empty(),
		"%s decoration adds no collision or navigation obstruction" % case_name)

	var batches: Array = decoration.find_children("*", "MultiMeshInstance3D", true, false)
	_check(batches.size() >= 7, "%s emits a dense batched facade hierarchy" % case_name)
	var manager := CameraOcclusionManager.new()
	root.add_child(manager)
	var wrapped := manager.apply_to(decoration)
	var all_batches_wrapped := true
	for raw_batch in batches:
		var batch := raw_batch as MultiMeshInstance3D
		if not (batch.material_override is ShaderMaterial) \
				or (batch.material_override as ShaderMaterial).shader != manager.OCCLUSION_SHADER:
			all_batches_wrapped = false
			break
	_check(wrapped >= batches.size() and all_batches_wrapped,
		"%s facade MultiMeshes participate in camera dissolution" % case_name)

	manager.queue_free()
	chunk.queue_free()
	await process_frame


func _verify_elevator_streamed_chunks() -> void:
	var packed := load("res://scenes/tutorial/elevator.tscn") as PackedScene
	_check(packed != null, "Elevator scene loads for streamed decoration verification")
	if packed == null:
		return
	var sequence := packed.instantiate()
	sequence.set("suppress_scene_change", true)
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	sequence._scheduler.clear()

	for chunk_name in ["below", "junction", "gauntlet"]:
		var chunk: Node3D = sequence._load_chunk(chunk_name)
		await process_frame
		var decoration := chunk.get_node_or_null("LevelDecoration")
		var audit: Dictionary = (decoration.get_meta("decoration_audit", {}) as Dictionary
			if decoration != null else {})
		_check(decoration != null and not audit.is_empty(),
			"Elevator %s stream emits shared decoration" % chunk_name)
		_check(not bool(audit.get("shell_materials_replaced", true))
			and int(audit.get("shell_surfaces", -1)) == 0,
			"Elevator %s keeps its authored StandardMaterial shell until occlusion" % chunk_name)
		var batches: Array = (decoration.find_children("*", "MultiMeshInstance3D", true, false)
			if decoration != null else [])
		var wrapped_batches := not batches.is_empty()
		for raw_batch in batches:
			var material: Material = (raw_batch as MultiMeshInstance3D).material_override
			if not (material is ShaderMaterial) \
					or (material as ShaderMaterial).shader != sequence._occlusion_mgr.OCCLUSION_SHADER:
				wrapped_batches = false
				break
		_check(wrapped_batches,
			"Elevator %s decoration batches are wrapped by the post-build occlusion pass" % chunk_name)

	sequence.queue_free()
	await process_frame
	await process_frame
