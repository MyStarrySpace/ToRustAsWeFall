extends SceneTree

## Runtime integration guard for the full procedural path: generator data -> portable landmark wrappers ->
## shared chunk materializer -> staged controls -> environmental consequence. This deliberately inspects
## cursor verbs/previews and state order, not only whether geometry exists.

const Generator := preload("res://scripts/generation/stretch_generator.gd")
const ChunkScene := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var spec: Dictionary = Generator.generate({
		"id": "verify_infrastructure_runtime",
		"title": "Verify Infrastructure Runtime",
		"seed": 71926,
		"complexity_tier": "teaching",
		"biome": "channels",
	})
	check(bool(spec.get("success", false)), "procedural Channels stretch generates")
	check(bool(Generator.validate_area_theme(spec).get("valid", false)),
		"generated infrastructure satisfies the area-theme contract")
	var operation_specs: Array = spec.get("infrastructure_operations", [])
	check(operation_specs.size() == 1, "generation emits one bounded service operation")
	if operation_specs.is_empty():
		_finish()
		return
	var operation_spec := operation_specs[0] as Dictionary
	var grid = GridWorld.from_data(spec.get("navigation_grid", {}))
	for endpoint in ["source_control_pos", "receiver_control_pos", "effect_pos"]:
		var position := _vec3(operation_spec.get(endpoint, []))
		var cell: Vector2i = grid.world_to_grid(position)
		check(grid.is_walkable(cell.x, cell.y), "%s occupies reachable generated floor" % endpoint)

	var chunk := ChunkScene.instantiate()
	chunk.configure_chunk({"spec": spec})
	root.add_child(chunk)
	await process_frame
	await process_frame
	var runtimes: Array = chunk.get("_infrastructure_runtime")
	check(runtimes.size() == 1, "generated presenter materializes the shared operation")
	if runtimes.is_empty():
		chunk.free()
		_finish()
		return
	var runtime := runtimes[0] as Dictionary
	var operation = runtime.get("operation")
	var source = runtime.get("source_control")
	var receiver = runtime.get("receiver_control")
	var field = runtime.get("field")
	check(operation != null and source != null and receiver != null and field != null,
		"runtime exposes source, receiver, and environmental field")
	check(str(source.call("get_action_verb")) == str(operation_spec.get("source_action", "")),
		"source cursor uses the generated mechanical verb")
	check(str(source.call("get_action_preview")) == str(operation_spec.get("source_preview", "")),
		"source cursor previews its exact consequence")
	check(not bool(receiver.call("is_interaction_enabled")),
		"receiver cannot be committed before its typed input arrives")
	check(bool(operation.call("route_service")), "source action routes the typed service")
	check(bool(receiver.call("is_interaction_enabled")),
		"routing reveals the distinct receiver verb")
	check(str(receiver.call("get_action_verb")) == str(operation_spec.get("receiver_action", "")),
		"receiver cursor employs its verb instead of generic click-to-interact")
	check(str(receiver.call("get_action_preview")) == str(operation_spec.get("receiver_preview", "")),
		"receiver cursor previews the route change")
	check(bool((field.call("get_state") as Dictionary).get("hazardous", false)),
		"marked environmental cost remains active until receiver work completes")
	check(bool(operation.call("complete_operation")), "receiver action completes after service routing")
	check(bool((field.call("get_state") as Dictionary).get("resolved", false))
			and not bool((field.call("get_state") as Dictionary).get("hazardous", true)),
		"receiver work visibly resolves the environmental cost")
	var service_link = runtime.get("service_link")
	var effect_link = runtime.get("effect_link")
	check(service_link != null and str(service_link.call("get_relationship_label")) != "",
		"source and receiver have a named spatial connection marker")
	check(effect_link != null and str(effect_link.call("get_relationship_label")) != "",
		"receiver and environmental consequence have a named spatial connection marker")
	chunk.free()
	_finish()


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	print("INFRASTRUCTURE INTERACTIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO
