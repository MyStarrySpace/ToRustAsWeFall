extends SceneTree

## Headless contract check for the measured infrastructure family. This complements the portable
## asset verifier: it proves every seeded survey stays valid, every structure builds detail geometry,
## the landmark grammar can place it, and the intended supply-chain adjacencies really compose.

const BaseShape := preload("res://scripts/generation/base_shape_builder.gd")
const Survey := preload("res://scripts/generation/building_survey.gd")
const Builder := preload("res://scripts/generation/infrastructure_structure_builder.gd")
const Filler := preload("res://scripts/generation/building_filler.gd")
const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const SceneChunkScript := preload("res://scripts/scene_chunks/scene_chunk.gd")

const KINDS := ["fabrication_hall", "bonded_warehouse", "reclamation_works",
	"distribution_substation"]
const SEEDS := [0, 1, 17, 113, 997]

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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

	await _expect_link(failures, "fabrication_hall", "bonded_warehouse", "fabricated_goods")
	await _expect_link(failures, "distribution_substation", "fabrication_hall", "electricity")
	await _expect_link(failures, "fabrication_hall", "reclamation_works", "wastewater")

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

	# Exercise the production interaction grammar, not retired controller verbs. The exact source
	# launches a physical scheduler-owned payload; only its arrival enables the exact receiver.
	operation_spec["operation_id"] = "catalog_%s" % commodity
	operation_spec["source_control_pos"] = Vector3.ZERO
	operation_spec["receiver_control_pos"] = Vector3(3.0, 0.0, 0.0)
	operation_spec["effect_pos"] = Vector3(6.0, 0.0, 0.0)
	operation_spec["transit_speed"] = 2.0
	var host = HostScript.new()
	host.setup()
	host.register_party({"aster": Vector3.ZERO})
	root.add_child(host)
	var chunk = SceneChunkScript.new()
	chunk.attach_chunk_host(host, "catalog_%s" % commodity)
	host.add_child(chunk)
	await process_frame
	var built: Dictionary = chunk.call("_add_infrastructure_operation", operation_spec)
	await process_frame
	var operation = built.get("operation")
	var field = built.get("field")
	var source_control = built.get("source_control")
	var receiver_control = built.get("receiver_control")
	if operation == null or source_control == null or receiver_control == null or field == null:
		failures.append("%s operation did not materialize its physical fixtures" % commodity)
		host.queue_free()
		await process_frame
		return
	if bool(operation.call("route_service")) or bool(operation.call("complete_operation")):
		failures.append("%s retired direct verbs still bypass physical controls" % commodity)
	if bool(receiver_control.call("is_interaction_enabled")):
		failures.append("%s receiver starts enabled before commodity transit" % commodity)

	source_control.set("active_character", "aster")
	host.set_preview_character_position("aster", (source_control as Node3D).global_position)
	if not bool(source_control.call("_trigger", false)):
		failures.append("%s exact source control did not accept its physical actor" % commodity)
	var in_transit: Dictionary = operation.call("get_state")
	if str(in_transit.get("phase", "")) != operation.PHASE_IN_TRANSIT \
			or bool(in_transit.get("receiver_enabled", true)) \
			or bool((in_transit.get("field", {}) as Dictionary).get("resolved", true)):
		failures.append("%s source did not create a gated physical transit" % commodity)
	var arrival_tick := float(in_transit.get("arrival_tick", -1.0))
	host.scheduler.advance_ticks(
		maxf(0.0, arrival_tick - float(host.scheduler.get_current_tick()) - 0.001)
	)
	if str((operation.call("get_state") as Dictionary).get("phase", "")) \
			!= operation.PHASE_IN_TRANSIT:
		failures.append("%s commodity arrived before its route deadline" % commodity)
	host.scheduler.advance_ticks(0.001)
	if str((operation.call("get_state") as Dictionary).get("phase", "")) \
			!= operation.PHASE_ARRIVED \
			or not bool(receiver_control.call("is_interaction_enabled")):
		failures.append("%s commodity arrival did not enable the exact receiver" % commodity)
	if bool((field.call("get_state") as Dictionary).get("resolved", false)):
		failures.append("%s arrival resolved the field before receiver commissioning" % commodity)

	receiver_control.set("active_character", "aster")
	host.set_preview_character_position("aster", (receiver_control as Node3D).global_position)
	if not bool(receiver_control.call("_trigger", false)) \
			or str((operation.call("get_state") as Dictionary).get("phase", "")) \
				!= operation.PHASE_COMPLETED \
			or not bool((field.call("get_state") as Dictionary).get("resolved", false)):
		failures.append("%s exact receiver did not resolve its environmental field" % commodity)
	host.queue_free()
	await process_frame

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
