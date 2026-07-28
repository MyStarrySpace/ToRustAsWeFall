extends SceneTree

## Physical source -> saved transit -> exact receiver authority regression. The same reusable object is
## exercised through both production hosts. Direct operation verbs are negative coverage only: every
## successful phase change must originate in an accepted world Interactable receipt.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const DataChunkScript := preload("res://scripts/fragments/chunks/data_fragment_chunk.gd")
const GeneratedChunkScene := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const Generator := preload("res://scripts/generation/stretch_generator.gd")

const OPERATION_ID := "authority_test_service"
const ACTOR_ID := "aster"
const DEADLINE_EPSILON := 0.001

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_data_fragment_authority()
	await _verify_generated_authority()
	print("INFRASTRUCTURE OPERATION SAVE AUTHORITY: %d checks, %d failures" % [
		_checks, _failures
	])
	quit(0 if _failures == 0 else 1)


func _verify_data_fragment_authority() -> void:
	var source := await _boot_data_fragment()
	await _exercise_host(
		source,
		"DataFragment",
		str(source.chunk.call("_fragment_authority_key")),
		Callable(self, "_boot_data_fragment")
	)


func _verify_generated_authority() -> void:
	var spec: Dictionary = Generator.generate({
		"id": "verify_infrastructure_save_authority",
		"title": "Verify Infrastructure Save Authority",
		"seed": 71926,
		"complexity_tier": "teaching",
		"biome": "channels",
	})
	check(bool(spec.get("success", false)),
		"generated authority fixture produces a valid stretch")
	var source := await _boot_generated(spec)
	await _exercise_host(
		source,
		"generated stretch",
		str(source.chunk.call("_generated_runtime_authority_key")),
		Callable(self, "_boot_generated").bind(spec)
	)


func _exercise_host(
		source: Dictionary,
		label: String,
		authority_key: String,
		fresh_factory: Callable
	) -> void:
	var host = source.host
	var chunk = source.chunk
	var operation = source.operation
	var source_control = operation.get("source_control")
	var receiver_control = operation.get("receiver_control")
	var field = operation.get("service_field")
	var operation_id := str(operation.get("operation_id"))
	var baseline := _capture(host)
	var counts := {
		"route": 0,
		"arrival": 0,
		"complete": 0,
		"field": 0,
		"launch_published_first": false,
		"arrival_published_first": false,
		"completion_published_first": false,
	}
	operation.service_routed.connect(func(_operation) -> void:
		counts["route"] += 1
		var saved := _saved_operation(host, authority_key, operation_id)
		counts["launch_published_first"] = (
			str(saved.get("phase", "")) == operation.PHASE_IN_TRANSIT
			and not bool(saved.get("field_resolved", true))
		)
	)
	operation.service_arrived.connect(func(_operation) -> void:
		counts["arrival"] += 1
		var saved := _saved_operation(host, authority_key, operation_id)
		counts["arrival_published_first"] = (
			str(saved.get("phase", "")) == operation.PHASE_ARRIVED
			and bool(receiver_control.call("is_interaction_enabled"))
		)
	)
	operation.operation_completed.connect(func(_operation) -> void:
		counts["complete"] += 1
		var saved := _saved_operation(host, authority_key, operation_id)
		counts["completion_published_first"] = (
			str(saved.get("phase", "")) == operation.PHASE_COMPLETED
			and bool(saved.get("field_resolved", false))
		)
	)
	field.field_resolved.connect(func(_field) -> void: counts["field"] += 1)

	check(not bool(operation.call("route_service"))
			and not bool(operation.call("complete_operation")),
		"%s direct compatibility verbs cannot bypass either physical source" % label)
	check(str((operation.call("get_state") as Dictionary).get("phase", "")) \
			== operation.PHASE_READY,
		"%s starts at the physical source with no routed service" % label)
	check(not bool(receiver_control.call("is_interaction_enabled")),
		"%s receiver stays disabled before commodity arrival" % label)
	receiver_control.set("active_character", ACTOR_ID)
	check(not bool(receiver_control.call("_trigger", false)),
		"%s receiver cannot be triggered before arrival" % label)

	# The exact source still rejects a remote actor even when a test asks the Interactable to trigger.
	_place_actor(host, source_control, ACTOR_ID, Vector3(20.0, 0.0, 20.0))
	source_control.set("active_character", ACTOR_ID)
	check(not bool(source_control.call("_trigger", false)),
		"%s exact source rejects a remote actor before consuming its receipt" % label)
	check(str((operation.call("get_state") as Dictionary).get("phase", "")) \
			== operation.PHASE_READY,
		"%s rejected source attempt leaves operation authority untouched" % label)

	_place_actor(host, source_control, ACTOR_ID)
	check(bool(source_control.call("_trigger", false)),
		"%s exact source Interactable accepts its nearby actor" % label)
	var launch_state: Dictionary = operation.call("get_state")
	var launch_saved := _saved_operation(host, authority_key, operation_id)
	check(str(launch_state.get("phase", "")) == operation.PHASE_IN_TRANSIT
			and str(launch_saved.get("phase", "")) == operation.PHASE_IN_TRANSIT
			and int(launch_saved.get("version", 0)) == operation.AUTHORITY_VERSION,
		"%s launch immediately publishes versioned in-transit authority" % label)
	check(bool(counts.get("launch_published_first", false))
			and int(counts.get("route", 0)) == 1,
		"%s authority is already saved when launch observers run" % label)
	check(str(launch_saved.get("source_actor_id", "")) == ACTOR_ID
			and str(launch_saved.get("source_id", "")) == str(source_control.get("data_id"))
			and str(launch_saved.get("receiver_id", "")) == str(receiver_control.get("data_id"))
			and bool(launch_saved.get("source_receipt_consumed", false)),
		"%s launch reserves exact actor, source, receiver, and paid receipt" % label)
	check((launch_saved.get("route", []) as Array).size() >= 2
			and float(launch_saved.get("started_at", -1.0)) >= 0.0
			and float(launch_saved.get("arrival_tick", -1.0)) \
				> float(launch_saved.get("started_at", -1.0))
			and str(launch_saved.get("progress_rule", "")) \
				== "piecewise_linear_route_by_scheduler_tick",
		"%s launch saves the physical route and absolute speed-derived arrival" % label)
	check(not bool(launch_state.get("receiver_enabled", true))
			and not bool((launch_state.get("field", {}) as Dictionary).get("resolved", true))
			and bool(launch_state.get("transit_visible", false)),
		"%s launch shows a traveling commodity while receiver and field remain unresolved" % label)

	var launch_tick := float(host.scheduler.get_current_tick())
	var arrival_tick := float(launch_saved.get("arrival_tick", -1.0))
	var transit_duration := arrival_tick - launch_tick
	var launch_position: Vector3 = launch_state.get("transit_position", Vector3.ZERO)
	host.scheduler.advance_ticks(transit_duration * 0.5)
	var midpoint_state: Dictionary = operation.call("get_state")
	var midpoint_position: Vector3 = midpoint_state.get("transit_position", Vector3.ZERO)
	check(str(midpoint_state.get("phase", "")) == operation.PHASE_IN_TRANSIT
			and float(midpoint_state.get("transit_progress", 0.0)) > 0.45
			and float(midpoint_state.get("transit_progress", 1.0)) < 0.55
			and midpoint_position.distance_to(launch_position) > 0.1,
		"%s transit advances analytically without a render/headless presenter call" % label)
	operation.call("_process", 0.0)
	var token = operation.get("_transit_token")
	check(is_instance_valid(token) and bool(token.get("visible"))
			and (token as Node3D).global_position.distance_to(
				midpoint_position + Vector3(0.0, 0.38, 0.0)
			) < 0.02,
		"%s visible commodity token projects the authoritative midpoint" % label)
	var midpoint_capture := _capture(host)
	var midpoint_saved := _saved_operation(host, authority_key, operation_id)
	check(str(midpoint_saved.get("phase", "")) == operation.PHASE_IN_TRANSIT
			and is_equal_approx(
				float(midpoint_saved.get("arrival_tick", -1.0)),
				arrival_tick
			),
		"%s midpoint save preserves the original absolute deadline" % label)

	var remaining := arrival_tick - float(host.scheduler.get_current_tick())
	host.scheduler.advance_ticks(remaining - DEADLINE_EPSILON)
	check(str((operation.call("get_state") as Dictionary).get("phase", "")) \
			== operation.PHASE_IN_TRANSIT
			and not bool(receiver_control.call("is_interaction_enabled")),
		"%s cannot arrive before its saved deadline" % label)
	host.scheduler.advance_ticks(DEADLINE_EPSILON)
	var arrived_state: Dictionary = operation.call("get_state")
	check(str(arrived_state.get("phase", "")) == operation.PHASE_ARRIVED
			and bool(arrived_state.get("receiver_enabled", false))
			and not bool((arrived_state.get("field", {}) as Dictionary).get("resolved", true)),
		"%s exact deadline seats the commodity and enables only the receiver" % label)
	check(int(counts.get("arrival", 0)) == 1
			and bool(counts.get("arrival_published_first", false)),
		"%s arrival authority is saved before its one external signal" % label)
	check(not bool(operation.call("complete_operation")),
		"%s direct completion stays inert after the commodity arrives" % label)

	_place_actor(host, receiver_control, ACTOR_ID)
	receiver_control.set("active_character", ACTOR_ID)
	check(bool(receiver_control.call("_trigger", false)),
		"%s exact receiver Interactable accepts the nearby actor" % label)
	var completed_state: Dictionary = operation.call("get_state")
	check(str(completed_state.get("phase", "")) == operation.PHASE_COMPLETED
			and bool((completed_state.get("field", {}) as Dictionary).get("resolved", false))
			and not bool(completed_state.get("transit_visible", true)),
		"%s receiver receipt resolves the field and retires the commodity token" % label)
	check(int(counts.get("complete", 0)) == 1
			and int(counts.get("field", 0)) == 1
			and bool(counts.get("completion_published_first", false)),
		"%s completion publishes once before its field and completion effects" % label)
	var completed_capture := _capture(host)

	# Rewind a reused presenter from completed to the saved midpoint.
	var counts_before_restore := counts.duplicate(true)
	_apply_capture(host, chunk, midpoint_capture)
	var same_midpoint_state: Dictionary = operation.call("get_state")
	check(str(same_midpoint_state.get("phase", "")) == operation.PHASE_IN_TRANSIT
			and not bool((same_midpoint_state.get("field", {}) as Dictionary).get(
				"resolved", true
			))
			and not bool(same_midpoint_state.get("receiver_enabled", true)),
		"%s same presenter retracts discarded arrival, receiver, and field futures" % label)
	check(_effect_counts(counts) == _effect_counts(counts_before_restore),
		"%s same-presenter midpoint restore emits no gameplay effect" % label)
	var same_pending := int(host.scheduler.pending_count())
	chunk.call("on_game_state_snapshot_restored")
	check(int(host.scheduler.pending_count()) == same_pending
			and _effect_counts(counts) == _effect_counts(counts_before_restore),
		"%s repeated restore leaves exactly one transit callback and no duplicate effect" % label)
	_advance_to_arrival(host, operation)
	check(str((operation.call("get_state") as Dictionary).get("phase", "")) \
			== operation.PHASE_ARRIVED,
		"%s same presenter reaches arrival again from its saved midpoint" % label)

	# A fresh scene instance reconstructs the same token position and one callback.
	var fresh: Dictionary = await fresh_factory.call()
	var fresh_operation = fresh.operation
	var fresh_field = fresh_operation.get("service_field")
	var fresh_counts := {"route": 0, "arrival": 0, "complete": 0, "field": 0}
	fresh_operation.service_routed.connect(
		func(_operation) -> void: fresh_counts["route"] += 1
	)
	fresh_operation.service_arrived.connect(
		func(_operation) -> void: fresh_counts["arrival"] += 1
	)
	fresh_operation.operation_completed.connect(
		func(_operation) -> void: fresh_counts["complete"] += 1
	)
	fresh_field.field_resolved.connect(func(_field) -> void: fresh_counts["field"] += 1)
	_apply_capture(fresh.host, fresh.chunk, midpoint_capture)
	var fresh_midpoint_state: Dictionary = fresh_operation.call("get_state")
	check(str(fresh_midpoint_state.get("phase", "")) == fresh_operation.PHASE_IN_TRANSIT
			and (fresh_midpoint_state.get("transit_position", Vector3.ZERO) as Vector3).distance_to(
				midpoint_position
			) < 0.02,
		"%s fresh presenter reconstructs the same physical transit midpoint" % label)
	check(_effect_counts(fresh_counts) == {"route": 0, "arrival": 0, "complete": 0, "field": 0},
		"%s fresh midpoint restoration is silent" % label)
	var fresh_pending := int(fresh.host.scheduler.pending_count())
	fresh.chunk.call("on_game_state_snapshot_restored")
	check(int(fresh.host.scheduler.pending_count()) == fresh_pending,
		"%s fresh repeated restore does not duplicate its transit callback" % label)
	_advance_to_arrival(fresh.host, fresh_operation)
	check(int(fresh_counts.get("arrival", 0)) == 1
			and str((fresh_operation.call("get_state") as Dictionary).get("phase", "")) \
				== fresh_operation.PHASE_ARRIVED,
		"%s fresh presenter completes exactly one scheduler-owned arrival" % label)

	# A fresh completed presenter mirrors field truth without re-emitting any effect.
	var fresh_completed: Dictionary = await fresh_factory.call()
	var completed_restore_counts := {"route": 0, "arrival": 0, "complete": 0, "field": 0}
	fresh_completed.operation.service_routed.connect(
		func(_operation) -> void: completed_restore_counts["route"] += 1
	)
	fresh_completed.operation.service_arrived.connect(
		func(_operation) -> void: completed_restore_counts["arrival"] += 1
	)
	fresh_completed.operation.operation_completed.connect(
		func(_operation) -> void: completed_restore_counts["complete"] += 1
	)
	fresh_completed.operation.get("service_field").field_resolved.connect(
		func(_field) -> void: completed_restore_counts["field"] += 1
	)
	_apply_capture(fresh_completed.host, fresh_completed.chunk, completed_capture)
	var fresh_completed_state: Dictionary = fresh_completed.operation.call("get_state")
	check(str(fresh_completed_state.get("phase", "")) \
			== fresh_completed.operation.PHASE_COMPLETED
			and bool((fresh_completed_state.get("field", {}) as Dictionary).get(
				"resolved", false
			))
			and _effect_counts(completed_restore_counts) \
				== {"route": 0, "arrival": 0, "complete": 0, "field": 0},
		"%s fresh completed restore mirrors the resolved field silently" % label)

	# Snapshot absence is authoritative even after this presenter has seen completion.
	var absent := baseline.duplicate(true)
	((absent.get("game_state", {}) as Dictionary).get(
		"world_state", {}
	) as Dictionary).erase(authority_key)
	_apply_capture(host, chunk, completed_capture)
	_apply_capture(host, chunk, absent)
	var absent_state: Dictionary = operation.call("get_state")
	check(str(absent_state.get("phase", "")) == operation.PHASE_READY
			and not bool((absent_state.get("field", {}) as Dictionary).get("resolved", true))
			and not bool(absent_state.get("transit_visible", true))
			and not bool(absent_state.get("receiver_enabled", true)),
		"%s authority absence retracts transit, arrival, completion, and field truth" % label)
	var absent_counts := _effect_counts(counts)
	host.scheduler.advance_ticks(60.0)
	check(str((operation.call("get_state") as Dictionary).get("phase", "")) \
			== operation.PHASE_READY
			and _effect_counts(counts) == absent_counts,
		"%s absence cancels the discarded arrival callback and future effects" % label)

	await _discard(host)
	await _discard(fresh.host)
	await _discard(fresh_completed.host)


func _advance_to_arrival(host, operation) -> void:
	var saved: Dictionary = operation.call("serialize_state")
	var remaining := float(saved.get("arrival_tick", -1.0)) \
		- float(host.scheduler.get_current_tick())
	host.scheduler.advance_ticks(maxf(0.0, remaining - DEADLINE_EPSILON))
	check(str((operation.call("get_state") as Dictionary).get("phase", "")) \
			== operation.PHASE_IN_TRANSIT,
		"restored transit remains active immediately before its absolute deadline")
	host.scheduler.advance_ticks(DEADLINE_EPSILON)


func _place_actor(
		host,
		control: Node3D,
		actor_id: String,
		offset := Vector3.ZERO
	) -> void:
	var position := control.global_position
	if host.game_state.coord_map != null \
			and host.game_state.coord_map.has_method("to_data"):
		position = host.game_state.coord_map.to_data(position)
	host.set_preview_character_position(actor_id, position + offset)
	control.set("active_character", actor_id)


func _saved_operation(host, authority_key: String, operation_id: String) -> Dictionary:
	var host_record: Dictionary = host.game_state.get_world_state(authority_key, {})
	return ((host_record.get("infrastructure", {}) as Dictionary).get(
		operation_id, {}
	) as Dictionary)


func _effect_counts(counts: Dictionary) -> Dictionary:
	return {
		"route": int(counts.get("route", 0)),
		"arrival": int(counts.get("arrival", 0)),
		"complete": int(counts.get("complete", 0)),
		"field": int(counts.get("field", 0)),
	}


func _boot_data_fragment() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var fragment := Fragment.new()
	fragment.id = "authority_infrastructure_fragment"
	fragment.party_ids = PackedStringArray([ACTOR_ID])
	fragment.spawns = {ACTOR_ID: Vector3.ZERO}
	fragment.objects = [{
		"type": "infrastructure_operation",
		"operation_id": OPERATION_ID,
		"commodity": "electricity",
		"source_control_pos": Vector3(1.0, 0.0, 0.0),
		"receiver_control_pos": Vector3(4.0, 0.0, 0.0),
		"effect_pos": Vector3(7.0, 0.0, 0.0),
		"effect_half": Vector2(1.2, 0.8),
		"damage_per_second": 6.0,
		"safe_concealment": true,
		"source_action": "ROUTE TEST POWER",
		"receiver_action": "COMMISSION TEST BAY",
		"transit_speed": 2.0,
	}]
	host.register_party(fragment.spawns)
	var chunk = DataChunkScript.new()
	chunk.fragment = fragment
	chunk.attach_chunk_host(host, fragment.id)
	host.add_child(chunk)
	await process_frame
	await process_frame
	chunk.call("reset_preview_state")
	var operations: Array = chunk.call("infrastructure_operations")
	check(operations.size() == 1, "DataFragment builds one shared physical operation owner")
	return {"host": host, "chunk": chunk, "operation": operations[0]}


func _boot_generated(spec: Dictionary) -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = GeneratedChunkScene.instantiate()
	chunk.configure_chunk({"spec": spec, "game_mode": "neutral", "food_test": "neutral"})
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_infrastructure_authority")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("reset_preview_state")
	var runtimes: Array = chunk.get("_infrastructure_runtime")
	check(runtimes.size() == 1, "generated stretch builds one shared physical operation owner")
	return {
		"host": host,
		"chunk": chunk,
		"operation": (runtimes[0] as Dictionary).get("operation"),
	}


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	chunk.call("on_game_state_snapshot_restored")


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
