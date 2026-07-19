extends Node

## Lightweight, renderer-independent quality gate for the shared production decoration kit.
## It exercises the exact measured spans used by the major Act 1 rooms without booting campaign
## state, enemies, dialogue, or navigation. Geometry is still emitted, so this verifies the real
## MultiMesh hierarchy and independently rejects any physics or standing-height lane intrusion.

const LevelDecoratorScript := preload("res://scripts/generation/level_decorator.gd")

const CASES := [
	{"name": "tag_checkpoint_west", "profile": "tag_checkpoint", "program": "boundary",
		"overrides": {"x0": -4.0, "x1": 12.4, "signs": ["CHECKPOINT 7-B"]}},
	{"name": "tag_checkpoint_east", "profile": "tag_checkpoint", "program": "boundary",
		"overrides": {"x0": 15.6, "x1": 28.0, "signs": ["PSY-KNAPSE ARRAY"]}},
	{"name": "elevator_below", "profile": "elevator_below_routes", "program": "hydraulic"},
	{"name": "elevator_junction_annex", "profile": "elevator_junction_field_annex", "program": "hydraulic"},
	{"name": "elevator_gauntlet", "profile": "elevator_flure_relay", "program": "boundary"},
	{"name": "leaving_facility", "profile": "leaving_facility", "program": "hydraulic",
		"overrides": {"x0": -4.0, "x1": 218.0, "width": 30.0, "spacing": 11.5,
			"floor_tint": Color(0.19, 0.20, 0.22), "wall_tint": Color(0.25, 0.21, 0.19),
			"landmark_lights": true}},
	{"name": "endo_stretch", "profile": "endo_stretch", "program": "hydraulic",
		"overrides": {"x1": 282.0, "width": 44.0, "spacing": 13.0,
			"signs": ["ENDO'S JUNCTION", "CONDUIT SURVEY", "SHELTER SIGNAL", "REFUGE ENTRY", "SHELTER 1  >"]}},
	{"name": "channels", "profile": "channels", "program": "hydraulic"},
	{"name": "stacks", "profile": "stacks", "program": "archive"},
	{"name": "rings", "profile": "rings", "program": "habitat"},
	{"name": "lockout", "profile": "lockout", "program": "boundary",
		"overrides": {"x0": 0.0, "x1": 220.0, "width": 10.0, "wall_height": 3.2,
			"ground_y": 0.0, "spacing": 8.4, "seed": 0x10C0A7,
			"signs": ["CIVIC LIMIT", "PAIR RELAY", "MAINTAINED SECTION  >"]}},
]

var _failures: Array[String] = []


func _ready() -> void:
	_run()


func _run() -> void:
	print("\n=== Production level decoration quality ===")
	var case_filter := OS.get_environment("DECOR_CASE")
	var verified_count := 0
	for case_value in CASES:
		if case_filter != "" and str((case_value as Dictionary)["name"]) != case_filter:
			continue
		_verify_case(case_value as Dictionary)
		verified_count += 1
	if _failures.is_empty():
		print("\nProduction level decoration verification: ALL PASSED (%d measured profiles)" % verified_count)
		get_tree().quit(0)
	else:
		print("\nProduction level decoration verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)


func _verify_case(case_data: Dictionary) -> void:
	var case_name := str(case_data["name"])
	var profile_id := str(case_data["profile"])
	var overrides: Dictionary = (case_data.get("overrides", {}) as Dictionary).duplicate(true)
	var spec := _resolved_spec(profile_id, overrides)
	var parent := _make_shell(spec)
	var audit: Dictionary = LevelDecoratorScript.decorate_profile(parent, profile_id, overrides)
	var decoration := parent.get_node_or_null("LevelDecoration") as Node3D
	_check(not audit.is_empty() and decoration != null, case_name, "emits the measured decoration root and audit")
	if audit.is_empty() or decoration == null:
		parent.free()
		return

	var stations := int(audit.get("stations", 0))
	var macro_landmarks := int(audit.get("macro_landmarks", 0))
	var length_m := float(audit.get("length_m", 0.0))
	var expected_landmarks := maxi(2,
		ceili(length_m / LevelDecoratorScript.MAX_WAYFINDING_GAP_M) - 1)
	var expected_lights := 0
	if bool(spec.get("landmark_lights", true)):
		expected_lights = mini(6, maxi(3,
			ceili(length_m / LevelDecoratorScript.MAX_LIGHT_GAP_M) - 1))
	var expected_labels := mini(3, (spec.get("signs", []) as Array).size())
	var batches: Dictionary = audit.get("batch_instances", {}) as Dictionary

	_check(str(audit.get("contract_id", "")) == "authored_level_decoration_v1"
		and str(audit.get("quality_contract_id", "")) == LevelDecoratorScript.QUALITY_CONTRACT_ID,
		case_name, "publishes the v2 building-quality contract")
	_check(bool(audit.get("quality_passed", false))
		and (audit.get("quality_issues", []) as Array).is_empty(), case_name,
		"passes its self-audit (%s)" % str(audit.get("quality_issues", [])))
	_check(str(audit.get("program", "")) == str(case_data["program"]), case_name,
		"retains its canonical %s program identity" % str(case_data["program"]))
	_check(stations >= 2 and int(audit.get("primary_datums", 0)) >= stations * 6,
		case_name, "has a measured plinth/eave structural datum ladder")
	_check(int(audit.get("facade_fields", 0)) == stations * 2,
		case_name, "carries one recessed facade field per bay face")
	_check(int(audit.get("upper_mass_instances", 0)) >= 2
		and int(audit.get("hierarchy_layers", 0)) == 5,
		case_name, "reads from upper mass through facade, program, landmark, and decay")
	_check(int(audit.get("program_signature_instances", 0)) >= stations * 2,
		case_name, "has a substantive program-specific facade signature")
	_check(int(audit.get("surface_datums", 0)) >= macro_landmarks * 3,
		case_name, "uses paper-thin floor composition to expose route scale")
	_check(int(audit.get("batches", 0)) >= 7 and batches.size() >= 7,
		case_name, "uses at least seven coherent material roles")
	_check(int(audit.get("instances", 0)) >= stations * 15,
		case_name, "has dense authored detail rather than sparse prop scatter")
	_check(int(audit.get("decay_marks", 0)) > 0
		and int(audit.get("emissive_instances", 0)) > 0,
		case_name, "balances seam-bound decay with restrained emissive punctuation")
	_check(macro_landmarks == expected_landmarks
		and float(audit.get("max_wayfinding_gap_m", 999.0)) <= LevelDecoratorScript.MAX_WAYFINDING_GAP_M + 0.01,
		case_name, "keeps macro wayfinding thresholds within %.0f m" % LevelDecoratorScript.MAX_WAYFINDING_GAP_M)
	_check(int(audit.get("labels", -1)) == expected_labels
		and int(audit.get("lights", -1)) == expected_lights,
		case_name, "uses the measured landmark label/light budget")
	_check(int(audit.get("shell_surfaces", 0)) == 3,
		case_name, "differentiates the floor and both shell walls with grime materials")
	_check(int(audit.get("collision_shapes", -1)) == 0
		and int(audit.get("route_clearance_intrusions", -1)) == 0
		and str(audit.get("clearance", "")) == "surface_only_no_obstacles",
		case_name, "reports zero collision and zero standing-height lane intrusion")
	_check(_physics_descendant_count(decoration) == 0,
		case_name, "contains no physics, area, or navigation descendants")
	_check(_emitted_instance_count(decoration) == int(audit.get("instances", -1)),
		case_name, "emitted MultiMesh instance budget matches the audited geometry")
	_check(_program_batch_identity(str(case_data["program"]), batches, stations),
		case_name, "material batches visibly differentiate its program")

	var idempotent_audit: Dictionary = LevelDecoratorScript.decorate_profile(parent, profile_id, overrides)
	_check(idempotent_audit == audit
		and parent.find_children("LevelDecoration", "Node3D", false, false).size() == 1,
		case_name, "decoration is idempotent")
	var twin := _make_shell(spec)
	var twin_audit: Dictionary = LevelDecoratorScript.decorate_profile(twin, profile_id, overrides)
	_check(twin_audit == audit, case_name, "seeded geometry audit is deterministic")

	print("[DECOR_AUDIT] %s %s" % [case_name, JSON.stringify(audit)])
	parent.free()
	twin.free()


func _resolved_spec(profile_id: String, overrides: Dictionary) -> Dictionary:
	var spec: Dictionary = (LevelDecoratorScript.ACT1_PROFILES[profile_id] as Dictionary).duplicate(true)
	for key in overrides:
		spec[key] = overrides[key]
	spec["id"] = profile_id
	return spec


func _make_shell(spec: Dictionary) -> Node3D:
	var parent := Node3D.new()
	var x0 := float(spec["x0"])
	var x1 := float(spec["x1"])
	var length_m := x1 - x0
	var width := float(spec["width"])
	var wall_h := float(spec["wall_height"])
	var ground_y := float(spec.get("ground_y", 0.0))
	_add_shell_box(parent, "AuditFloor", Vector3((x0 + x1) * 0.5, ground_y - 0.05, 0.0),
		Vector3(length_m, 0.10, width))
	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		_add_shell_box(parent, "AuditWall%s" % ("N" if side < 0.0 else "S"),
			Vector3((x0 + x1) * 0.5, ground_y + wall_h * 0.5, side * width * 0.5),
			Vector3(length_m, wall_h, 0.20))
	return parent


func _add_shell_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	parent.add_child(mesh_instance)


func _physics_descendant_count(node: Node) -> int:
	var count := 0
	for descendant in node.find_children("*", "", true, false):
		if descendant is CollisionObject3D or descendant is CollisionShape3D \
				or descendant is NavigationRegion3D or descendant is NavigationObstacle3D:
			count += 1
	return count


func _emitted_instance_count(decoration: Node3D) -> int:
	var instance_count := 0
	for child in decoration.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var multimesh := (child as MultiMeshInstance3D).multimesh
		if multimesh != null:
			instance_count += multimesh.instance_count
	return instance_count


func _program_batch_identity(program: String, batches: Dictionary, stations: int) -> bool:
	match program:
		"hydraulic":
			return int(batches.get("service", 0)) >= stations * 6
		"boundary":
			return int(batches.get("glow", 0)) >= stations * 2 \
				and int(batches.get("dark", 0)) >= stations
		"archive":
			return int(batches.get("service", 0)) >= stations * 8
		"habitat":
			return int(batches.get("leaf", 0)) >= stations * 3 \
				and int(batches.get("glow", 0)) >= stations
	return false


func _check(condition: bool, case_name: String, message: String) -> void:
	if condition:
		print("  PASS [%s]: %s" % [case_name, message])
	else:
		var failure := "[%s] %s" % [case_name, message]
		_failures.append(failure)
		push_error("  FAIL %s" % failure)
