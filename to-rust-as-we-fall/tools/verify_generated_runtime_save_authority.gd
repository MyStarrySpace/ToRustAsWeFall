extends SceneTree

## Mid-phase rollback/fresh-load regression for the generated stretch. This specifically prevents the
## cost-refund/progress-keep exploit: hydraulic topology, cargo, and a captured flow must roll back with
## character/item state and resume from their original absolute deadlines.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const SPEC_PATH := "res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"

class AuthorityHost:
	extends ChunkHostStub

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source_pair := await _boot_pair()
	var host: AuthorityHost = source_pair.host
	var chunk: Node = source_pair.chunk

	check(
		not bool(chunk.call("open_first_sluice"))
		and not bool(chunk.call("release_cistern_bridge"))
		and not bool(chunk.call("toggle_borrowed_current"))
		and not bool(chunk.call("activate_generated_node", "node_02", "aster"))
		and not bool(chunk.call("choose_generated_route", "main_00_01", false)),
		"public consequence and semantic-route helpers are inert without physical receipts"
	)
	check(
		_trigger_control(host, chunk, "_hydraulic_first_control"),
		"source opens the First Sluice through its exact world control"
	)
	host.scheduler.advance_ticks(_scavenger_approach_duration(chunk) + 0.37)
	var mid_state: Dictionary = chunk.call("get_preview_state")
	check(str(mid_state.get("bridge_cargo_phase", "")) == "falling",
		"source snapshot point is the committed falling-cargo midpoint")
	chunk.call("_on_bridge_cargo_staged", false)
	check(
		str(chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "falling",
		"direct cargo-stage callback cannot bypass the saved fall deadline"
	)
	var saved_fall_end := float(chunk.get("_bridge_cargo_fall_end_tick"))
	var saved_scheduler := _json_round_trip(host.scheduler.serialize())
	var saved_state := _json_round_trip(host.game_state.serialize())

	# Advance the same scene into the future, then roll back. The future bridge/topology cannot survive.
	check(bool(chunk.call("_advance_hydraulic_scavenger_chain_for_headless")),
		"future branch advances the actual scavenger route to clearance")
	check(
		_trigger_control(host, chunk, "_hydraulic_cistern_control"),
		"future branch starts bridge transport through its exact world control"
	)
	host.scheduler.advance_ticks(3.001)
	check(bool(chunk.call("get_preview_state").get("cistern_bridge_installed", false)),
		"future branch seats the bridge before rollback")
	host.scheduler.clear()
	host.scheduler.deserialize(saved_scheduler)
	host.game_state.deserialize(saved_state)
	chunk.call("on_game_state_snapshot_restored")
	var rolled: Dictionary = chunk.call("get_preview_state")
	check(str(rolled.get("bridge_cargo_phase", "")) == "falling"
			and not bool(rolled.get("cistern_bridge_installed", true)),
		"same-instance rollback retracts future cargo and bridge topology")
	var same_remaining: float = saved_fall_end - float(host.scheduler.get_current_tick())
	host.scheduler.advance_ticks(maxf(0.0, same_remaining - 0.001))
	check(str(chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "falling",
		"restored cargo cannot stage before its original deadline")
	host.scheduler.advance_ticks(0.002)
	check(str(chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "staged",
		"restored cargo stages exactly at the saved absolute deadline")

	# Fresh presenter: build normally, then replace its GameState/clock with the midpoint snapshot.
	var fresh_pair := await _boot_pair()
	var fresh_host: AuthorityHost = fresh_pair.host
	var fresh_chunk: Node = fresh_pair.chunk
	fresh_host.scheduler.clear()
	fresh_host.scheduler.deserialize(saved_scheduler)
	fresh_host.game_state.deserialize(saved_state)
	fresh_chunk.call("on_game_state_snapshot_restored")
	var fresh_mid: Dictionary = fresh_chunk.call("get_preview_state")
	check(str(fresh_mid.get("bridge_cargo_phase", "")) == "falling"
			and bool(fresh_mid.get("first_sluice_open", false)),
		"fresh generated presenter restores the committed hydraulic midpoint")
	var fresh_remaining: float = saved_fall_end - float(fresh_host.scheduler.get_current_tick())
	fresh_host.scheduler.advance_ticks(fresh_remaining + 0.001)
	check(str(fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "staged",
		"fresh generated presenter consumes only the saved remainder")

	# Mandatory bridge transport is itself an in-flight transaction. Preserve the
	# stable physical cargo/context and consume only the remainder of its original deadline.
	check(bool(fresh_chunk.call("_advance_hydraulic_scavenger_chain_for_headless")),
		"fresh run completes the restored body retreat before bridge release")
	check(
		_trigger_control(fresh_host, fresh_chunk, "_hydraulic_cistern_control"),
		"fresh run starts the mandatory bridge carry through its exact world control"
	)
	fresh_chunk.call("_complete_bridge_cargo_transport", false)
	check(
		str(fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", ""))
			== "transporting",
		"direct cargo completion cannot bypass the physical transport deadline"
	)
	var runtime_key := str(fresh_chunk.call("_generated_runtime_authority_key"))
	var cargo_context: Dictionary = fresh_chunk.call("_bridge_cargo_authority_context")
	var transport_start := float(fresh_chunk.get("_bridge_transport_start_tick"))
	var transport_deadline := (
		transport_start + float(cargo_context.get("transport_duration", 0.0))
	)
	fresh_host.scheduler.advance_ticks(1.25)
	var transport_scheduler := _json_round_trip(fresh_host.scheduler.serialize())
	var transport_state := _json_round_trip(fresh_host.game_state.serialize())
	var transport_record := _runtime_record(transport_state, runtime_key)
	check(
		str(transport_record.get("bridge_cargo_phase", "")) == "transporting"
		and is_equal_approx(
			float(transport_record.get("bridge_transport_start_tick", -1.0)),
			transport_start
		)
		and _same_json(
			transport_record.get("bridge_cargo_context", {}),
			cargo_context
		),
		"transport midpoint saves its phase, stable cargo identity/route, and absolute timing"
	)
	fresh_host.scheduler.advance_ticks(
		maxf(0.0, transport_deadline - float(fresh_host.scheduler.get_current_tick()) + 0.001)
	)
	check(str(fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "seated",
		"future branch seats the exact transported cargo")
	fresh_host.scheduler.clear()
	fresh_host.scheduler.deserialize(transport_scheduler)
	fresh_host.game_state.deserialize(transport_state)
	fresh_chunk.call("on_game_state_snapshot_restored")
	fresh_chunk.call("on_game_state_snapshot_restored")
	check(
		str(fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "transporting"
		and _same_json(
			fresh_chunk.call("_bridge_cargo_authority_context"),
			cargo_context
		),
		"same-instance rollback restores one transporting cargo after repeated restore hooks"
	)
	var transport_remaining := (
		transport_deadline - float(fresh_host.scheduler.get_current_tick())
	)
	fresh_host.scheduler.advance_ticks(maxf(0.0, transport_remaining - 0.001))
	check(str(fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "transporting",
		"same-instance transported cargo cannot seat before its original deadline")
	fresh_host.scheduler.advance_ticks(0.002)
	check(str(fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", "")) == "seated",
		"same-instance transported cargo seats once at the saved deadline")

	var transport_fresh_pair := await _boot_pair()
	var transport_fresh_host: AuthorityHost = transport_fresh_pair.host
	var transport_fresh_chunk: Node = transport_fresh_pair.chunk
	transport_fresh_host.scheduler.clear()
	transport_fresh_host.scheduler.deserialize(transport_scheduler)
	transport_fresh_host.game_state.deserialize(transport_state)
	transport_fresh_chunk.call("on_game_state_snapshot_restored")
	transport_fresh_chunk.call("on_game_state_snapshot_restored")
	var fresh_transport_record := _runtime_record(
		transport_fresh_host.game_state.serialize(), runtime_key
	)
	check(
		str(transport_fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", ""))
			== "transporting"
		and _same_json(
			fresh_transport_record.get("bridge_cargo_context", {}),
			cargo_context
		),
		"fresh presenter restores the same pending cargo identity and route"
	)
	var fresh_transport_remaining := (
		transport_deadline - float(transport_fresh_host.scheduler.get_current_tick())
	)
	transport_fresh_host.scheduler.advance_ticks(maxf(0.0, fresh_transport_remaining - 0.001))
	check(
		str(transport_fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", ""))
			== "transporting",
		"fresh transported cargo consumes only the saved remainder"
	)
	transport_fresh_host.scheduler.advance_ticks(0.002)
	check(
		str(transport_fresh_chunk.call("get_preview_state").get("bridge_cargo_phase", ""))
			== "seated",
		"fresh transported cargo seats once at the original deadline"
	)

	# Router/captured payload uses the same authority record and its own portable pending-flow contract.
	check(
		_trigger_control(
			transport_fresh_host,
			transport_fresh_chunk,
			"_hydraulic_diverter_control"
		),
		"fresh run launches the optional captured-route payload through its exact world control"
	)
	check(
		not bool(transport_fresh_chunk.call("_latch_borrowed_current_delivery"))
		and str(transport_fresh_chunk.call("get_preview_state").get(
			"spillway_delivery_phase", ""
		)) == "traveling",
		"direct delivery callback cannot forge a router arrival receipt"
	)
	transport_fresh_host.scheduler.advance_ticks(1.0)
	var flow_scheduler := _json_round_trip(transport_fresh_host.scheduler.serialize())
	var flow_state := _json_round_trip(transport_fresh_host.game_state.serialize())
	transport_fresh_host.scheduler.advance_ticks(1.61)
	check(str(transport_fresh_chunk.call("get_preview_state").get("spillway_delivery_phase", "")) == "available",
		"future branch lets the captured payload arrive")
	transport_fresh_host.scheduler.clear()
	transport_fresh_host.scheduler.deserialize(flow_scheduler)
	transport_fresh_host.game_state.deserialize(flow_state)
	transport_fresh_chunk.call("on_game_state_snapshot_restored")
	check(str(transport_fresh_chunk.call("get_preview_state").get("spillway_delivery_phase", "")) == "traveling",
		"rollback retracts the future arrival and restores in-transit flow")
	transport_fresh_host.scheduler.advance_ticks(1.599)
	check(str(transport_fresh_chunk.call("get_preview_state").get("spillway_delivery_phase", "")) == "traveling",
		"captured flow cannot arrive before its original deadline")
	transport_fresh_host.scheduler.advance_ticks(0.002)
	check(str(transport_fresh_chunk.call("get_preview_state").get("spillway_delivery_phase", "")) == "available",
		"captured flow arrives once at its restored deadline")

	# The automatic catch is also a saved receipt, not an unsaved deferred call.
	# Its actor and exact Interactable identity survive same-instance and fresh restore.
	var catch_source: Node = (
		transport_fresh_chunk.get("_node_interactables") as Dictionary
	).get("node_04", null)
	var catch_position: Vector3 = transport_fresh_chunk.call(
		"_generated_interaction_data_position", catch_source
	)
	transport_fresh_host.game_state.snap_character_to("aster", catch_position)
	check(
		bool(transport_fresh_chunk.call("_begin_hydraulic_catch_receipt", "aster")),
		"physical catch overlap begins a durable pending receipt"
	)
	transport_fresh_chunk.call("_complete_hydraulic_catch_receipt")
	check(
		_node_completion_count(transport_fresh_chunk, "node_04") == 0
		and str((transport_fresh_chunk.get("_hydraulic_catch_receipt") as Dictionary).get(
			"phase", ""
		)) == "pending",
		"direct catch completion cannot bypass the receipt deadline"
	)
	var catch_scheduler := _json_round_trip(transport_fresh_host.scheduler.serialize())
	var catch_state := _json_round_trip(transport_fresh_host.game_state.serialize())
	var saved_catch_record := (
		_runtime_record(catch_state, runtime_key).get("hydraulic_catch_receipt", {})
		as Dictionary
	)
	var catch_deadline := float(saved_catch_record.get("deadline", -1.0))
	var catch_source_id := str(saved_catch_record.get("source_interactable_id", ""))
	check(
		str(saved_catch_record.get("phase", "")) == "pending"
		and str(saved_catch_record.get("actor_id", "")) == "aster"
		and catch_source_id == str(catch_source.get("data_id"))
		and catch_deadline > float(transport_fresh_host.scheduler.get_current_tick()),
		"catch midpoint saves pending phase, exact actor/source identity, and absolute deadline"
	)
	transport_fresh_host.scheduler.advance_ticks(0.002)
	check(
		_node_completion_count(transport_fresh_chunk, "node_04") == 1
		and _hand_item_count(transport_fresh_host, "aster") == 1
		and str((transport_fresh_chunk.get("_hydraulic_catch_receipt") as Dictionary).get(
			"phase", ""
		)) == "complete",
		"future catch boundary consumes the exact Interactable and transfers one payload"
	)
	transport_fresh_host.scheduler.clear()
	transport_fresh_host.scheduler.deserialize(catch_scheduler)
	transport_fresh_host.game_state.deserialize(catch_state)
	transport_fresh_chunk.call("on_game_state_snapshot_restored")
	transport_fresh_chunk.call("on_game_state_snapshot_restored")
	check(
		_node_completion_count(transport_fresh_chunk, "node_04") == 0
		and _hand_item_count(transport_fresh_host, "aster") == 0
		and str((transport_fresh_chunk.get("_hydraulic_catch_receipt") as Dictionary).get(
			"phase", ""
		)) == "pending",
		"same-instance rollback restores one pending catch after repeated restore hooks"
	)
	var catch_remaining := (
		catch_deadline - float(transport_fresh_host.scheduler.get_current_tick())
	)
	transport_fresh_host.scheduler.advance_ticks(maxf(0.0, catch_remaining - 0.0005))
	check(
		_node_completion_count(transport_fresh_chunk, "node_04") == 0
		and _hand_item_count(transport_fresh_host, "aster") == 0,
		"same-instance catch cannot commit before its saved deadline"
	)
	transport_fresh_host.scheduler.advance_ticks(0.001)
	transport_fresh_host.scheduler.advance_ticks(0.1)
	check(
		_node_completion_count(transport_fresh_chunk, "node_04") == 1
		and _hand_item_count(transport_fresh_host, "aster") == 1,
		"same-instance catch commits exactly once at the saved deadline"
	)

	var catch_fresh_pair := await _boot_pair()
	var catch_fresh_host: AuthorityHost = catch_fresh_pair.host
	var catch_fresh_chunk: Node = catch_fresh_pair.chunk
	catch_fresh_host.scheduler.clear()
	catch_fresh_host.scheduler.deserialize(catch_scheduler)
	catch_fresh_host.game_state.deserialize(catch_state)
	catch_fresh_chunk.call("on_game_state_snapshot_restored")
	catch_fresh_chunk.call("on_game_state_snapshot_restored")
	var restored_catch := catch_fresh_chunk.get("_hydraulic_catch_receipt") as Dictionary
	check(
		str(restored_catch.get("phase", "")) == "pending"
		and str(restored_catch.get("actor_id", "")) == "aster"
		and str(restored_catch.get("source_interactable_id", "")) == catch_source_id
		and is_equal_approx(float(restored_catch.get("deadline", -1.0)), catch_deadline),
		"fresh presenter restores the same pending catch identity and deadline"
	)
	var fresh_catch_remaining := (
		catch_deadline - float(catch_fresh_host.scheduler.get_current_tick())
	)
	catch_fresh_host.scheduler.advance_ticks(maxf(0.0, fresh_catch_remaining - 0.0005))
	check(
		_node_completion_count(catch_fresh_chunk, "node_04") == 0
		and _hand_item_count(catch_fresh_host, "aster") == 0,
		"fresh catch consumes only the saved remainder"
	)
	catch_fresh_host.scheduler.advance_ticks(0.001)
	catch_fresh_host.scheduler.advance_ticks(0.1)
	check(
		_node_completion_count(catch_fresh_chunk, "node_04") == 1
		and _hand_item_count(catch_fresh_host, "aster") == 1,
		"fresh catch commits exactly once through the restored Interactable"
	)

	var catch_absent_pair := await _boot_pair()
	var catch_absent_host: AuthorityHost = catch_absent_pair.host
	var catch_absent_chunk: Node = catch_absent_pair.chunk
	var catch_absent_state := _json_round_trip(catch_state)
	_runtime_record(catch_absent_state, runtime_key).erase("hydraulic_catch_receipt")
	catch_absent_host.scheduler.clear()
	catch_absent_host.scheduler.deserialize(catch_scheduler)
	catch_absent_host.game_state.deserialize(catch_absent_state)
	catch_absent_chunk.call("on_game_state_snapshot_restored")
	catch_absent_host.scheduler.advance_ticks(0.2)
	check(
		_node_completion_count(catch_absent_chunk, "node_04") == 0
		and _hand_item_count(catch_absent_host, "aster") == 0
		and str((catch_absent_chunk.get("_hydraulic_catch_receipt") as Dictionary).get(
			"phase", ""
		)) == "idle",
		"missing catch receipt is authoritative absence and cannot resurrect a deferred pickup"
	)

	# Absence is also authoritative. This models an old/pre-stretch save whose world-state dictionary
	# has no generated-runtime key, then rolls a progressed same-instance chunk back to it.
	var absent_pair := await _boot_pair()
	var absent_host: AuthorityHost = absent_pair.host
	var absent_chunk: Node = absent_pair.chunk
	var absent_scheduler := _json_round_trip(absent_host.scheduler.serialize())
	var absent_state := _json_round_trip(absent_host.game_state.serialize())
	runtime_key = str(absent_chunk.call("_generated_runtime_authority_key"))
	(absent_state.get("world_state", {}) as Dictionary).erase(runtime_key)
	check(_trigger_control(absent_host, absent_chunk, "_hydraulic_first_control"),
		"absence regression creates progress in the discarded future")
	check(bool(absent_chunk.call("_advance_hydraulic_scavenger_chain_for_headless")),
		"absence regression advances the actual future scavenger route")
	check(_trigger_control(absent_host, absent_chunk, "_hydraulic_cistern_control"),
		"absence regression advances future bridge topology")
	absent_host.scheduler.advance_ticks(3.001)
	absent_host.scheduler.clear()
	absent_host.scheduler.deserialize(absent_scheduler)
	absent_host.game_state.deserialize(absent_state)
	absent_chunk.call("on_game_state_snapshot_restored")
	var absent_rolled: Dictionary = absent_chunk.call("get_preview_state")
	check(not bool(absent_rolled.get("first_sluice_open", true))
			and not bool(absent_rolled.get("cistern_bridge_installed", true))
			and str(absent_rolled.get("bridge_cargo_phase", "")) == "elevated",
		"missing authority retracts all future generated progress to the construction baseline")
	check(absent_host.game_state.get_world_state(runtime_key, {}).get("version", 0) == 1,
		"legacy absence is normalized into an explicit authoritative baseline")
	check(
		_trigger_control(absent_host, absent_chunk, "_hydraulic_first_control"),
		"authority absence also retracts the discarded one-shot presenter for honest replay"
	)

	host.queue_free()
	fresh_host.queue_free()
	transport_fresh_host.queue_free()
	catch_fresh_host.queue_free()
	catch_absent_host.queue_free()
	absent_host.queue_free()
	await process_frame
	print("GENERATED RUNTIME SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _boot_pair() -> Dictionary:
	var host := AuthorityHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({"spec_path": SPEC_PATH, "game_mode": "neutral", "food_test": "neutral"})
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("reset_preview_state")
	await process_frame
	return {"host": host, "chunk": chunk}


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _runtime_record(state: Dictionary, runtime_key: String) -> Dictionary:
	var world_state: Variant = state.get("world_state", {})
	if not (world_state is Dictionary):
		return {}
	var record: Variant = (world_state as Dictionary).get(runtime_key, {})
	return record as Dictionary if record is Dictionary else {}


func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _node_completion_count(chunk: Node, node_id: String) -> int:
	var completed: Variant = chunk.get("_completed_nodes")
	return (completed as Array).count(node_id) if completed is Array else 0


func _hand_item_count(host: AuthorityHost, actor: String) -> int:
	var items: Variant = host.game_state.get_hand_items(actor)
	return (items as Array).size() if items is Array else 0


func _scavenger_approach_duration(chunk: Node) -> float:
	var route_v: Variant = chunk.get("_bridge_scavenger_route")
	var scavenger_v: Variant = chunk.get("_hydraulic_scavenger")
	if not (route_v is Array) or (route_v as Array).size() < 2 \
			or not (scavenger_v is Enemy):
		return 0.0
	var route := route_v as Array
	return (
		(route[0] as Vector3).distance_to(route[1] as Vector3)
		/ float((scavenger_v as Enemy).move_speed)
	)


func _trigger_control(
	host: AuthorityHost, chunk: Node, field_name: String, actor := "aster"
) -> bool:
	var source_v: Variant = chunk.get(field_name)
	if not (source_v is Node) or not is_instance_valid(source_v):
		return false
	var source := source_v as Node
	var position_v: Variant = chunk.call(
		"_generated_interaction_data_position", source
	)
	if not (position_v is Vector3):
		return false
	host.game_state.snap_character_to(actor, position_v as Vector3)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
