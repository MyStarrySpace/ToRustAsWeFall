extends SceneTree

## Midpoint save/load + rollback coverage for the remaining chunk-owned scheduler state. A
## production-shaped load clears Callables, restores only the scheduler clock and GameState, then
## asks the existing scene presenter to reattach from its versioned world-state record.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const DataChunkScript := preload("res://scripts/fragments/chunks/data_fragment_chunk.gd")
const WashChunkScript := preload("res://scripts/fragments/chunks/wash_relay_chunk.gd")
const LockoutChunkScript := preload("res://scripts/fragments/chunks/lockout_chase_chunk.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_data_fragment_strict_future_boundary()
	await _verify_data_fragment_midpoints()
	await _verify_wash_midpoints()
	await _verify_wash_climb_midpoint()
	await _verify_lockout_wave_midpoint()
	print("CHUNK CADENCE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_data_fragment_strict_future_boundary() -> void:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	host.scheduler.advance_ticks(4.1)
	var chunk = DataChunkScript.new()
	chunk.attach_chunk_host(host, "strict_future_boundary")
	check(is_equal_approx(float(chunk.call("_next_fixed_tick", 0.1, 0.5)), 4.6),
		"DataFragment fractional epoch reconstructs the next strict-future damage tick, not now")
	chunk.free()
	await _discard(host)


func _verify_data_fragment_midpoints() -> void:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var frag := Fragment.new()
	frag.id = "authority_data_fragment"
	frag.party_ids = PackedStringArray(["aster"])
	frag.spawns = {"aster": Vector3.ZERO}
	frag.objects = [
		{"type": "candid_zone", "name": "AuthorityCandid", "pos": Vector3.ZERO,
			"half": Vector2(2.0, 2.0), "dot": 10.0},
		{"type": "weak_wall", "name": "AuthorityWall", "pos": Vector3(4.0, 0.0, 0.0),
			"n": Vector3(1.0, 0.0, 0.0), "kill_min": Vector3(3.0, -1.0, -1.0),
			"kill_max": Vector3(5.0, 2.0, 1.0)},
	]
	host.register_party({"aster": Vector3.ZERO})
	host.game_state.set_stat("aster", "hp", 100.0)
	var chunk = DataChunkScript.new()
	chunk.fragment = frag
	chunk.attach_chunk_host(host, frag.id)
	host.add_child(chunk)
	await process_frame
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	host.scheduler.advance_ticks(0.2)
	var cadence_midpoint := _capture(host)
	var cadence_record: Dictionary = host.game_state.get_world_state(chunk._fragment_authority_key(), {})
	check(bool(cadence_record.get("scheduled", false))
			and is_equal_approx(float(cadence_record.get("candid_epoch", -1.0)), 0.5),
		"DataFragment stores the fixed damage epoch in GameState")
	host.scheduler.advance_ticks(0.29)
	check(is_equal_approx(host.game_state.get_stat("aster", "hp"), 100.0),
		"Candid damage cannot arrive before its original midpoint deadline")
	host.scheduler.advance_ticks(0.01)
	check(is_equal_approx(host.game_state.get_stat("aster", "hp"), 95.0),
		"Candid damage arrives once at the original deadline")
	_apply_capture(host, chunk, cadence_midpoint)
	check(is_equal_approx(host.game_state.get_stat("aster", "hp"), 100.0),
		"DataFragment rollback retracts future cadence damage")
	host.scheduler.advance_ticks(0.3)
	check(is_equal_approx(host.game_state.get_stat("aster", "hp"), 95.0),
		"DataFragment rollback re-arms one exact Candid callback")

	var wall_source: Interactable = (chunk._weak_walls[0] as Dictionary).get("source")
	check(not chunk._on_weak_wall_pried(0) and chunk._weak_wall_deadlines.is_empty(),
		"source-less weak-wall helper cannot manufacture a pry receipt")
	wall_source.interacted.emit()
	check(chunk._weak_wall_deadlines.is_empty(),
		"manually emitted weak-wall signal cannot start the physical collapse")
	wall_source.active_character = "aster"
	check(not wall_source._trigger(false) and wall_source.is_interaction_enabled(),
		"remote selected portrait cannot spend the weak-wall source")
	var wall_source_position: Vector3 = chunk._weak_wall_source_data_position(wall_source)
	host.game_state.snap_character_to("aster", wall_source_position)
	var accepted_pre_owner := {"capture": {}}
	var accepted_listener := func(source_id: String, _actor: String) -> void:
		if source_id == wall_source.data_id:
			accepted_pre_owner.capture = _capture(host)
	host.game_state.interactable_triggered.connect(accepted_listener, CONNECT_ONE_SHOT)
	check(wall_source._trigger(false),
		"nearby ready party body spends the exact weak-wall one-shot")
	check(int((chunk._weak_walls[0] as Dictionary).get("trigger_consumed", 0)) == 1
			and chunk._weak_wall_deadlines.has(0),
		"weak-wall owner consumes the exact monotonic source receipt before scheduling motion")
	host.scheduler.advance_ticks(0.4)
	chunk.headless_process(0.0)
	var wall_midpoint := _capture(host)
	var wall: Dictionary = chunk._weak_walls[0]
	var panel := (wall.get("panels", []) as Array)[1] as MeshInstance3D
	var midpoint_rotation := panel.rotation.x
	check(not bool((chunk._weak_walls[0] as Dictionary).get("crumbled", true)),
		"weak wall remains intact at its saved midpoint")
	check(panel.mesh != null and panel.mesh.resource_path.ends_with("weak_wall_slab.obj"),
		"weak-wall motion uses the portable UV-mapped slab asset")
	check(midpoint_rotation < -0.1 and midpoint_rotation > -1.4,
		"saved midpoint visibly tips the wall toward its debris field")
	var original_deadline := float(chunk._weak_wall_deadlines.get(0, -1.0))
	check(not chunk._on_weak_wall_pried(0) and not wall_source._trigger(false),
		"direct and repeated source edges cannot postpone a committed collapse")
	check(is_equal_approx(float(chunk._weak_wall_deadlines.get(0, -2.0)), original_deadline),
		"repeated pry cannot postpone an already committed collapse")
	host.scheduler.advance_ticks(0.5)
	check(bool((chunk._weak_walls[0] as Dictionary).get("crumbled", false)),
		"weak wall commits on its original absolute tick")
	check(panel.rotation.x < -1.45 and bool((wall.get("rubble") as Node3D).visible),
		"physical endpoint leaves fallen slabs and rubble instead of a mesh pop")
	_apply_capture(host, chunk, wall_midpoint)
	check(not bool((chunk._weak_walls[0] as Dictionary).get("crumbled", true)),
		"weak-wall rollback restores the intact presenter and pending commitment")
	check(is_equal_approx(panel.rotation.x, midpoint_rotation),
		"weak-wall rollback reconstructs exact saved visual progress")
	host.scheduler.advance_ticks(0.49)
	check(not bool((chunk._weak_walls[0] as Dictionary).get("crumbled", true)),
		"restored weak wall cannot crumble early")
	host.scheduler.advance_ticks(0.01)
	check(bool((chunk._weak_walls[0] as Dictionary).get("crumbled", false)),
		"restored weak wall crumbles exactly once at its saved deadline")

	# Version 2 stored the physical endpoint/deadline but not the source receipt count. Migration
	# preserves that already-committed interval and consumes only the count in the restored registry.
	var legacy_midpoint := wall_midpoint.duplicate(true)
	var legacy_world: Dictionary = legacy_midpoint.get("game_state", {}).get("world_state", {})
	var legacy_record: Dictionary = legacy_world.get(chunk._fragment_authority_key(), {})
	legacy_record["version"] = 2
	for state_v in legacy_record.get("weak_walls", []) as Array:
		if state_v is Dictionary:
			(state_v as Dictionary).erase("trigger_consumed")
	_apply_capture(host, chunk, legacy_midpoint)
	var migrated_record: Dictionary = host.game_state.get_world_state(
		chunk._fragment_authority_key(), {})
	check(int(migrated_record.get("version", 0)) == chunk.DATA_FRAGMENT_AUTHORITY_VERSION
			and int(((migrated_record.get("weak_walls", []) as Array)[0] as Dictionary).get(
				"trigger_consumed", -1)) == 1
			and chunk._weak_wall_deadlines.has(0),
		"v2 weak-wall authority migrates its exact pending wall and registry receipt")

	# GameState accepts a one-shot synchronously before the chunk callback can publish the wall
	# deadline. Loading that seam must re-arm the same physical source without moving the wall.
	var accepted_capture: Dictionary = accepted_pre_owner.capture
	var accepted_record: Dictionary = accepted_capture.get(
		"game_state", {}).get("world_state", {}).get(chunk._fragment_authority_key(), {})
	check(not accepted_capture.is_empty()
			and int(((accepted_record.get("weak_walls", []) as Array)[0] as Dictionary).get(
				"trigger_consumed", -1)) == 0
			and float(((accepted_record.get("weak_walls", []) as Array)[0] as Dictionary).get(
				"deadline", -1.0)) < 0.0,
		"signal-time fixture captures accepted weak-wall source before owner commitment")
	_apply_capture(host, chunk, accepted_capture)
	_apply_capture(host, chunk, accepted_capture)
	check(not bool((chunk._weak_walls[0] as Dictionary).get("crumbled", true))
			and chunk._weak_wall_deadlines.is_empty()
			and wall_source.is_interaction_enabled() and not bool(wall_source.get("_used"))
			and int((chunk._weak_walls[0] as Dictionary).get("trigger_consumed", 0)) == 1,
		"same presenter repeatedly retracts accepted pre-owner pry without a free collapse")
	check(not chunk._on_weak_wall_pried(0),
		"reconciled signal seam still cannot be advanced through the retired helper")
	wall_source.active_character = "aster"
	check(wall_source._trigger(false)
			and int((chunk._weak_walls[0] as Dictionary).get("trigger_consumed", 0)) == 2,
		"rearmed exact source spends the next monotonic receipt normally")

	var fresh_host = HostScript.new()
	fresh_host.setup()
	root.add_child(fresh_host)
	fresh_host.register_party({"aster": Vector3.ZERO})
	var fresh_chunk = DataChunkScript.new()
	fresh_chunk.fragment = frag
	fresh_chunk.attach_chunk_host(fresh_host, frag.id)
	fresh_host.add_child(fresh_chunk)
	await process_frame
	_apply_capture(fresh_host, fresh_chunk, accepted_capture)
	_apply_capture(fresh_host, fresh_chunk, accepted_capture)
	var fresh_source: Interactable = (fresh_chunk._weak_walls[0] as Dictionary).get("source")
	check(fresh_chunk._weak_wall_deadlines.is_empty()
			and not bool((fresh_chunk._weak_walls[0] as Dictionary).get("crumbled", true))
			and fresh_source.is_interaction_enabled() and not bool(fresh_source.get("_used")),
		"fresh presenter repeatedly retracts accepted pre-owner pry to physical baseline")
	fresh_source.active_character = "aster"
	check(fresh_source._trigger(false) and fresh_chunk._weak_wall_deadlines.has(0),
		"fresh presenter can use the rearmed exact weak-wall source")
	await _discard(fresh_host)
	await _discard(host)


func _verify_wash_midpoints() -> void:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = WashChunkScript.new()
	chunk.attach_chunk_host(host, "wash_relay")
	var wash_party: Array[String] = []
	for id_v in chunk.get_spawn_positions().keys():
		var char_id := str(id_v)
		wash_party.append(char_id)
		host.game_state.register_character(char_id, chunk.get_spawn_positions()[id_v], 3.0,
			{"hp": 100.0})
	host.game_state.set_party(wash_party)
	host.add_child(chunk)
	await process_frame
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	# Enter the wet phase through the real cadence callback. Calling the onset
	# helper directly while its scheduled onset remains queued forks a second
	# recurrence chain and can make rollback tests pass for the wrong reason.
	var first_onset_in := float(chunk._section_next_onset_in(0))
	check(first_onset_in > 0.0,
		"Wash Relay exposes a strictly-future first onset for the authority fixture")
	host.scheduler.advance_ticks(first_onset_in)
	# Stay deliberately between 0.1 s spatial-authority boundaries. This verifier
	# is about the wet-window midpoint; exact poll-boundary snapshot semantics
	# belong to the dedicated Wash spatial-authority suite.
	host.scheduler.advance_ticks(0.37)
	var wet_midpoint := _capture(host)
	var wet_record: Dictionary = host.game_state.get_world_state(chunk.WASH_AUTHORITY_KEY, {})
	var off_tick := float((wet_record.get("section_flood_until", []) as Array)[0])
	check(bool((wet_record.get("flooding", []) as Array)[0]) and off_tick > 0.4,
		"Wash Relay stores wet phase and absolute off deadline")
	host.scheduler.advance_ticks(off_tick - float(host.scheduler.get_current_tick()))
	check(not bool(chunk._flooding[0]), "Wash Relay dries at its original off tick")
	_apply_capture(host, chunk, wet_midpoint)
	check(bool(chunk._flooding[0]), "Wash rollback restores active water immediately")
	var remaining := off_tick - float(host.scheduler.get_current_tick())
	host.scheduler.advance_ticks(remaining - 0.01)
	check(bool(chunk._flooding[0]), "restored Wash water cannot disappear before the saved deadline")
	host.scheduler.advance_ticks(0.011)
	check(not bool(chunk._flooding[0]), "restored Wash water ends exactly once")

	var pressure_valve: Node = chunk._pressure_valve
	var valve_position: Vector3 = host.game_state.get_interactable(
		str(pressure_valve.get("data_id"))).get("position", Vector3.INF)
	host.game_state.command_stop("aster")
	host.game_state.snap_character_to("aster", valve_position)
	pressure_valve.set("active_character", "aster")
	check(bool(pressure_valve.call("_trigger", false)),
		"nearby ready party body vents through the exact pressure valve")
	host.scheduler.advance_ticks(5.03)
	var vent_midpoint := _capture(host)
	var vent_until := float(chunk._pressure_vent_until)
	host.scheduler.advance_ticks(vent_until - float(host.scheduler.get_current_tick()))
	check(chunk._pressure_vent_until < 0.0, "pressure vent closes on its original tick")
	_apply_capture(host, chunk, vent_midpoint)
	check(is_equal_approx(float(chunk._pressure_vent_until), vent_until),
		"pressure-vent rollback restores the absolute deadline")
	var vent_remaining := vent_until - float(host.scheduler.get_current_tick())
	host.scheduler.advance_ticks(vent_remaining - 0.01)
	check(chunk._pressure_vent_until >= 0.0, "restored vent cannot close early")
	host.scheduler.advance_ticks(0.011)
	check(chunk._pressure_vent_until < 0.0, "restored vent closes exactly once")
	await _discard(host)


func _trigger_wash_vine_tend(chunk: Node, gs: GameState) -> bool:
	var source: Node = chunk.find_child("ClimbvineTendAnchor", true, false)
	if source == null:
		return false
	if gs.is_moving("peris"):
		gs.command_stop("peris")
	gs.snap_character_to("peris", chunk.RETURN_LANDING)
	source.set("active_character", "peris")
	return bool(source.call("_trigger", false))


func _trigger_wash_vine_climb(chunk: Node, gs: GameState, active: String) -> bool:
	var source: Node = chunk.find_child("ClimbLine", true, false)
	if source == null:
		return false
	var waiting: Array = (chunk.get("_washed") as Dictionary).keys()
	waiting.sort()
	if not waiting.has(active):
		return false
	for id_v in waiting:
		var id := str(id_v)
		if gs.is_moving(id):
			gs.command_stop(id)
		gs.snap_character_to(id, chunk.CLIMB_POS)
	source.set("active_character", active)
	return bool(source.call("_trigger", false))


func _verify_wash_climb_midpoint() -> void:
	var pair := await _boot_wash_chunk()
	var host = pair.host
	var chunk = pair.chunk
	# Earn each causal phase before inspecting the climb itself. A wash now has a real knock + return
	# current, and the recovery vine has a Peris-only timed deployment; neither grants its endpoint early.
	chunk._wash_character("aster")
	host.scheduler.advance_ticks(
		chunk.WASH_CURRENT_KNOCK_DURATION + chunk.WASH_CURRENT_RETURN_MAX + 0.01)
	host.game_state.snap_character_to("peris", chunk.RETURN_LANDING)
	chunk._on_sloperope("peris")
	check(not chunk._climbvine_return.is_deploying()
			and not chunk._climbvine_return.is_deployed(),
		"retired Wash upper helper cannot manufacture a source receipt")
	check(_trigger_wash_vine_tend(chunk, host.game_state),
		"exact upper Interactable and Peris body commit deployment")
	host.scheduler.advance_ticks(chunk.SLOPEROPE_DEPLOY_DURATION)
	host.game_state.snap_character_to("aster", chunk.CLIMB_POS)
	var before_climb := _capture(host)
	chunk._on_climb()
	check(not host.game_state.is_external_traversal_active("aster"),
		"retired Wash lower helper cannot manufacture a source receipt")
	check(_trigger_wash_vine_climb(chunk, host.game_state, "aster"),
		"exact lower Interactable commits the physically gathered waiting body")
	var committed: Dictionary = host.game_state.get_external_traversal_state("aster")
	check(host.game_state.is_external_traversal_active("aster")
			and str(committed.get("traversal_id", "")).begins_with(
				chunk.SLOPEROPE_TRAVERSAL_PREFIX)
			and host.game_state.get_position("aster").x < 10.0,
		"Wash climbvine commits a real traversal without endpoint teleporting")
	check(int(chunk.get_preview_state().get("washed_count", -1)) == 0
			and int(chunk.get_preview_state().get("climbing_count", -1)) == 1,
		"waiting and climbing are distinct authoritative character states")
	host.scheduler.advance_ticks(2.0)
	var midpoint := _capture(host)
	var mid_state: Dictionary = host.game_state.get_external_traversal_state("aster")
	var mid_position: Vector3 = host.game_state.get_position("aster")
	check(float(mid_state.get("progress", 0.0)) > 0.3
			and float(mid_state.get("progress", 1.0)) < 0.35
			and mid_position.x > 10.0 and mid_position.x < chunk.RETURN_LANDING.x,
		"mid-climb state records spatial progress instead of only endpoints")
	check(not chunk._wash_character("aster")
			and host.game_state.is_external_traversal_active("aster"),
		"flat relay coordinates cannot wash a character physically on the vine")
	host.scheduler.advance_ticks(4.0)
	check(not host.game_state.is_external_traversal_active("aster")
			and host.game_state.get_position("aster").distance_to(chunk.RETURN_LANDING) < 0.01,
		"the uninterrupted climb finishes at its authored deadline")

	_apply_capture(host, chunk, midpoint)
	_apply_capture(host, chunk, midpoint)
	var restored: Dictionary = host.game_state.get_external_traversal_state("aster")
	check(host.game_state.is_external_traversal_active("aster")
			and is_equal_approx(float(restored.get("progress", -1.0)),
				float(mid_state.get("progress", -2.0)))
			and host.game_state.get_position("aster").distance_to(mid_position) < 0.01,
		"same-instance rollback restores the exact mid-vine state")
	host.scheduler.advance_ticks(3.999)
	check(host.game_state.is_external_traversal_active("aster"),
		"restored climb cannot finish before its saved remainder")
	host.scheduler.advance_ticks(0.001)
	check(not host.game_state.is_external_traversal_active("aster")
			and host.game_state.get_position("aster").distance_to(chunk.RETURN_LANDING) < 0.01,
		"idempotent restore attaches exactly one climb completion")

	var fresh_pair := await _boot_wash_chunk()
	var fresh_host = fresh_pair.host
	var fresh = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, midpoint)
	check(fresh_host.game_state.is_external_traversal_active("aster")
			and fresh_host.game_state.get_position("aster").distance_to(mid_position) < 0.01,
		"fresh Wash presenter reconstructs the same mid-climb progress")
	fresh_host.scheduler.advance_ticks(4.0)
	check(not fresh_host.game_state.is_external_traversal_active("aster")
			and fresh_host.game_state.get_position("aster").distance_to(fresh.RETURN_LANDING) < 0.01,
		"fresh Wash presenter consumes only the saved climb remainder")

	_apply_capture(host, chunk, before_climb)
	check(not host.game_state.is_external_traversal_active("aster")
			and int(chunk.get_preview_state().get("washed_count", -1)) == 1
			and host.game_state.get_position("aster").x < 10.0,
		"rollback to before commitment retracts the future climb and upper landing")
	await _discard(host)
	await _discard(fresh_host)


func _boot_wash_chunk() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = WashChunkScript.new()
	chunk.attach_chunk_host(host, "wash_relay")
	for id_v in chunk.get_spawn_positions().keys():
		host.game_state.register_character(str(id_v), chunk.get_spawn_positions()[id_v], 3.0,
			{"hp": 100.0})
	host.add_child(chunk)
	await process_frame
	chunk.reset_preview_state()
	return {"host": host, "chunk": chunk}


func _verify_lockout_wave_midpoint() -> void:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = LockoutChunkScript.new()
	chunk.attach_chunk_host(host, "lockout_chase")
	host.add_child(chunk)
	await process_frame
	host.register_party(chunk.get_spawn_positions())
	host.game_state.set_party(["aster", "peris"])
	var scanner: Interactable = chunk._boundary_scanner
	var scanner_position: Vector3 = host.game_state.get_interactable(scanner.data_id).get(
		"position", scanner.position)
	host.game_state.snap_character_to("aster", scanner_position)
	scanner.active_character = "aster"
	check(scanner._trigger(false), "Lockout cadence fixture starts through the exact scanner")
	host.scheduler.advance_ticks(2.0)
	var wave_midpoint := _capture(host)
	var record: Dictionary = host.game_state.get_world_state(chunk.CHASE_AUTHORITY_KEY, {})
	var wave_deadlines: Dictionary = record.get("one_shot_deadlines", {})
	check(is_equal_approx(float(wave_deadlines.get("chase_wave_1", -1.0)), 4.5)
			and bool(record.get("pursuit_armed", false)),
		"Lockout stores the first wave's absolute deadline and armed phase")
	host.scheduler.advance_ticks(2.49)
	check(chunk.enemies().is_empty(), "Lockout wave cannot spawn before its saved deadline")
	host.scheduler.advance_ticks(0.01)
	check(chunk.enemies().size() == 2, "Lockout wave spawns exactly once at its original deadline")
	_apply_capture(host, chunk, wave_midpoint)
	check(chunk.enemies().is_empty(), "Lockout rollback retracts pursuers from the discarded future")
	host.scheduler.advance_ticks(2.5)
	check(chunk.enemies().size() == 2 and int(chunk._wave_count) == 2,
		"Lockout rollback replays one wave without duplicating its progression counter")
	await _discard(host)


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	chunk.on_game_state_snapshot_restored()


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
