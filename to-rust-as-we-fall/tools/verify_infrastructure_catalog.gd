extends SceneTree

## Headless contract check for the measured infrastructure family. This complements the portable
## asset verifier: it proves every seeded survey stays valid, every structure builds detail geometry,
## the landmark grammar can place it, and the intended supply-chain adjacencies really compose.

const BaseShape := preload("res://scripts/generation/base_shape_builder.gd")
const Survey := preload("res://scripts/generation/building_survey.gd")
const Builder := preload("res://scripts/generation/infrastructure_structure_builder.gd")
const Filler := preload("res://scripts/generation/building_filler.gd")
const Operation := preload("res://scripts/game/objects/infrastructure_operation.gd")
const ServiceField := preload("res://scripts/game/objects/infrastructure_service_field.gd")

const KINDS := ["fabrication_hall", "bonded_warehouse", "reclamation_works",
	"distribution_substation"]
const SEEDS := [0, 1, 17, 113, 997]

func _init() -> void:
	var failures: Array[String] = []
	for kind_v in KINDS:
		var kind := str(kind_v)
		if not BaseShape.BUILDINGS.has(kind) or not Filler.LANDMARK_KINDS.has(kind):
			failures.append("%s is missing from a generation catalog" % kind)
			continue
		for seed_v in SEEDS:
			var spec: Dictionary = BaseShape.generate(kind, int(seed_v))
			var survey: BuildingSurvey = Survey.from_spec(spec)
			var problems := survey.validate()
			if not problems.is_empty():
				failures.append("%s seed %d survey: %s" % [kind, int(seed_v), "; ".join(problems)])
			var ports: Array = survey.anchors().get("service_ports", [])
			if ports.is_empty():
				failures.append("%s seed %d has no measured service ports" % [kind, int(seed_v)])
			var has_in := false
			var has_out := false
			for port_v in ports:
				var port := port_v as Dictionary
				has_in = has_in or str(port.get("flow", "")) == "in"
				has_out = has_out or str(port.get("flow", "")) == "out"
			if not has_in or not has_out:
				failures.append("%s seed %d must expose both an input and an output" % [kind, int(seed_v)])
			var built: Dictionary = Builder.build(spec, survey)
			var vertices := 0
			for mesh_v in built.values():
				var mesh := mesh_v as ArrayMesh
				for surface in range(mesh.get_surface_count()):
					vertices += mesh.surface_get_array_len(surface)
			if vertices < 72:
				failures.append("%s seed %d has too little construction geometry (%d vertices)" % [kind, int(seed_v), vertices])

	_expect_link(failures, "fabrication_hall", "bonded_warehouse", "fabricated_goods")
	_expect_link(failures, "distribution_substation", "fabrication_hall", "electricity")
	_expect_link(failures, "fabrication_hall", "reclamation_works", "wastewater")

	if failures.is_empty():
		print("[INFRASTRUCTURE CATALOG] PASS: 4 measured editable structures, %d seed surveys, 3 causal links" % (KINDS.size() * SEEDS.size()))
		quit(0)
		return
	for failure in failures:
		push_error("[INFRASTRUCTURE CATALOG] %s" % failure)
	quit(1)

func _expect_link(failures: Array[String], a_kind: String, b_kind: String, commodity: String) -> void:
	var plan := Filler.plan_service_link(_landmark(a_kind), _landmark(b_kind))
	if str(plan.get("commodity", "")) != commodity:
		failures.append("%s + %s should compose through %s, got %s" % [a_kind, b_kind,
			commodity, str(plan.get("commodity", "none"))])
		return
	var operation_spec: Dictionary = Filler.service_operation_from_link(plan)
	for field_name in ["source_action", "source_preview", "receiver_action", "receiver_preview",
			"service_relationship", "effect_relationship", "hazard_label", "safe_label"]:
		if str(operation_spec.get(field_name, "")).strip_edges() == "":
			failures.append("%s operation is missing %s" % [commodity, field_name])
	if str(operation_spec.get("source_action", "")) in ["INTERACT", "CLICK", "USE"] \
			or str(operation_spec.get("receiver_action", "")) in ["INTERACT", "CLICK", "USE"]:
		failures.append("%s operation falls back to a generic click verb" % commodity)

	# The reusable controller must preserve the staged model: the environmental consequence cannot
	# resolve until a typed service has first been routed to the receiver.
	var field := ServiceField.new()
	field.configure({
		"commodity": commodity,
		"damage_per_second": float(operation_spec.get("damage_per_second", 0.0)),
		"safe_concealment": bool(operation_spec.get("safe_concealment", false)),
	})
	var operation := Operation.new()
	operation.configure(operation_spec)
	operation.add_child(field)
	operation.bind_runtime(null, null, field)
	if operation.complete_operation():
		failures.append("%s consequence resolves before the source service is routed" % commodity)
	if not operation.route_service() or not bool(operation.get_state().get("routed", false)):
		failures.append("%s source action did not route its service" % commodity)
	if not operation.complete_operation() or not bool(field.get_state().get("resolved", false)):
		failures.append("%s receiver action did not change the environmental field" % commodity)
	operation.free()

func _landmark(kind: String) -> Dictionary:
	var spec: Dictionary = BaseShape.generate(kind, 0)
	var ports: Array = []
	for port_v in (Survey.from_spec(spec).anchors().get("service_ports", []) as Array):
		var port := (port_v as Dictionary).duplicate(true)
		var p := port["pos"] as Vector3
		var d := port["dir"] as Vector3
		port["pos"] = [p.x, p.y, p.z]
		port["dir"] = [d.x, d.y, d.z]
		ports.append(port)
	return {"kind": kind, "service_ports": ports, "door_pos": [0.0, 0.0, 2.0], "street": [0, 1]}
