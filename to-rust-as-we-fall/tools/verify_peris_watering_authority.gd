extends SceneTree

## The optional Peris-room watering beat used to hide the canonical item, teleport
## its unrelated scene mesh to the fern, and store completion only in a local bool.
## This verifier proves one physical item/phase authority across carry, interruption,
## midpoint save/load, replay, completion, and rollback.

const PerisScene := preload("res://scenes/tutorial/peris_sim.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source := await _spawn_sequence()
	if source == null:
		_finish()
		return
	var pickup: Node3D = source.find_child("WateringCanPickup", true, false)
	var water: Node3D = source.find_child("WaterPlantSpot", true, false)
	check(pickup != null and water != null, "watering pickup and fern use point instantiate")
	if pickup == null or water == null:
		await _discard(source)
		_finish()
		return

	var gs: GameState = source._game_state
	var item_id: String = str(source._resolve_watering_can_item_id())
	check(item_id != "" and gs.items.has(item_id),
		"room starts with one tagged canonical watering can")
	var ground_item := gs.items.get(item_id, {}) as Dictionary
	check(str(ground_item.get("location", "")) == "ground"
			and source._watering_can_mesh.visible
			and source._watering_can_mesh.global_position.distance_to(
				ground_item.get("position", Vector3.ZERO) as Vector3) < 0.01,
		"ground mesh projects the canonical item position")
	var baseline_snapshot := _json_round_trip(source.build_save_snapshot())

	source._on_watering_can_picked()
	pickup.interacted.emit()
	check(not source._peris_holds_watering_can(),
		"direct and manually emitted pickup callbacks are inert")
	pickup.active_character = "peris"
	check(not bool(pickup.call("_trigger", false)),
		"a remote selected Peris cannot pick up the can")
	source.set_preview_character_position("peris", pickup.global_position)
	pickup.active_character = "monos"
	check(not bool(pickup.call("_trigger", false)),
		"the nearby wrong body cannot pick up Peris's can")
	pickup.active_character = "peris"
	check(bool(pickup.call("_trigger", false)),
		"the exact pickup accepts nearby action-free Peris")
	await process_frame
	check(source._peris_holds_watering_can()
			and source._watering_can_mesh.visible
			and source._watering_can_mesh.get_parent() == source.get_game_state_character_node("peris"),
		"pickup keeps the visible can attached to Peris's canonical hand")
	check(source._watering_phase() == &"" and not source._plant_watered,
		"pickup alone neither starts nor completes watering")
	var pickup_receipt := gs.get_world_state(
		source.WATERING_AUTHORITY_KEY, {}) as Dictionary
	var pickup_counts := pickup_receipt.get(
		"source_committed_counts", {}) as Dictionary
	check(int(pickup_counts.get(source.WATERING_PICKUP_ACTION, 0)) == 1,
		"pickup saves its exact monotonic source receipt")

	source._on_plant_watered()
	water.interacted.emit()
	check(source._watering_phase() == &"",
		"direct and manually emitted watering callbacks are inert")
	source.set_preview_character_position("peris", pickup.global_position)
	water.active_character = "peris"
	check(not bool(water.call("_trigger", false)),
		"a remote selected Peris cannot water the fern")
	source.set_preview_character_position("peris", water.global_position)
	water.active_character = "monos"
	check(not bool(water.call("_trigger", false)),
		"the nearby wrong body cannot water Peris's fern")
	water.active_character = "peris"
	check(bool(water.call("_trigger", false)),
		"the exact fern source accepts nearby Peris holding the can")
	await process_frame
	var started := gs.get_mechanism_phase_state(source.WATERING_PHASE_ID)
	var active_receipt := gs.get_world_state(source.WATERING_AUTHORITY_KEY, {}) as Dictionary
	check(StringName(str(started.get("phase", ""))) == source.WATERING_PHASE_ACTIVE
			and not source._plant_watered,
		"fern use commits a scheduler-owned watering phase without granting the endpoint")
	check(source._peris_holds_watering_can()
			and str(active_receipt.get("phase", "")) == str(source.WATERING_PHASE_ACTIVE)
			and str(active_receipt.get("item_id", "")) == item_id
			and int((active_receipt.get("source_committed_counts", {}) as Dictionary).get(
				source.WATERING_USE_ACTION, 0)) == 1,
		"active receipt identifies the exact fern edge and still-held can")

	source.headless_advance(0.45, 0.05)
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var saved_phases := (midpoint_snapshot.get("game_state", {}) as Dictionary).get(
		"timed_mechanism_phases", {}) as Dictionary
	var saved_phase := saved_phases.get(str(source.WATERING_PHASE_ID), {}) as Dictionary
	check(absf(float(saved_phase.get("remaining", -1.0)) - 0.75) < 0.06,
		"midpoint snapshot stores only the unpaid watering remainder")
	check(not bool(source.headless_get_state().get("plant_watered", true)),
		"midpoint remains unfinished and cannot claim the fern result")

	# Dropping the exact item interrupts the action. Advancing beyond the old
	# deadline must not resurrect its result.
	check(gs.drop_item("peris", item_id), "explicit drop releases the canonical can")
	check(not gs.has_mechanism_phase(source.WATERING_PHASE_ID)
			and not source._plant_watered,
		"dropping the can cancels the active use phase")
	source.headless_advance(source.WATERING_USE_DURATION + 0.1, 0.05)
	check(not source._plant_watered,
		"cancelled watering cannot finish from its stale deadline")
	var dropped_item := gs.items.get(item_id, {}) as Dictionary
	check(str(dropped_item.get("location", "")) == "ground"
			and source._watering_can_mesh.get_parent() == source._watering_can_home_parent
			and source._watering_can_mesh.global_position.distance_to(
				dropped_item.get("position", Vector3.ZERO) as Vector3) < 0.01,
		"drop returns the same mesh to the canonical ground location")

	# Roll back to the active midpoint. The presenter must retract the interrupted
	# future and the saved remainder must still be paid exactly once.
	source.apply_save_snapshot(midpoint_snapshot)
	check(source._watering_phase() == source.WATERING_PHASE_ACTIVE
			and source._peris_holds_watering_can()
			and not source._plant_watered,
		"same-presenter load reconstructs the held can and active phase")
	var projection_before: Dictionary = source._game_state.serialize()
	source.on_game_state_snapshot_restored()
	var projection_after: Dictionary = source._game_state.serialize()
	check(projection_after == projection_before,
		"repeated presenter attachment emits no synthetic gameplay command")
	source.headless_advance(0.65, 0.05)
	check(source._watering_phase() == source.WATERING_PHASE_ACTIVE
			and not source._plant_watered,
		"reloaded action cannot finish before its saved deadline")
	source.headless_advance(0.11, 0.01)
	check(source._watering_phase() == source.WATERING_PHASE_COMPLETE
			and source._plant_watered,
		"saved remainder reaches the watered endpoint once")
	var completed_receipt := source._game_state.get_world_state(
		source.WATERING_AUTHORITY_KEY, {}) as Dictionary
	check(str(completed_receipt.get("phase", "")) == str(source.WATERING_PHASE_COMPLETE),
		"completion commits the saved semantic fern result")
	check(source._peris_holds_watering_can()
			and source._watering_can_mesh.get_parent() == source.get_game_state_character_node("peris"),
		"using the reusable can does not secretly drop or teleport it")
	var completed_snapshot := _json_round_trip(source.build_save_snapshot())

	# Use a clean, linear recording for replay. The source fixture deliberately
	# rewound a snapshot above, and snapshot replacement is not itself a gameplay
	# event that belongs in an EventLog.
	var replay_source := await _spawn_sequence(true)
	if replay_source != null:
		var replay_pickup: Node3D = replay_source.find_child(
			"WateringCanPickup", true, false)
		var replay_water: Node3D = replay_source.find_child(
			"WaterPlantSpot", true, false)
		var replay_item_id: String = str(replay_source._resolve_watering_can_item_id())
		check(_move_authoritatively(replay_source, "peris", replay_pickup.global_position),
			"clean recording walks Peris to the can through logged simulation")
		replay_pickup.active_character = "peris"
		replay_pickup.call("_trigger", false)
		await process_frame
		check(_move_authoritatively(replay_source, "peris", replay_water.global_position),
			"clean recording carries the can to the fern through logged simulation")
		replay_water.active_character = "peris"
		replay_water.call("_trigger", false)
		await process_frame
		replay_source.headless_advance(replay_source.WATERING_USE_DURATION + 0.05, 0.05)
		replay_source._game_state.flush_tick()
		var log: EventLog = replay_source._game_state.event_log
		check(log != null and log.size() > 0,
			"normal tutorial run records an authoritative EventLog")
		if log != null:
			var replayed := GameState.replay(
				EventLog.from_bytes(log.to_bytes()), replay_source._grid)
			var replayed_phase := replayed.get_mechanism_phase_state(
				replay_source.WATERING_PHASE_ID)
			var replayed_receipt := replayed.get_world_state(
				replay_source.WATERING_AUTHORITY_KEY, {}) as Dictionary
			var replayed_item := replayed.items.get(replay_item_id, {}) as Dictionary
			check(StringName(str(replayed_phase.get("phase", "")))
					== replay_source.WATERING_PHASE_COMPLETE
					and str(replayed_receipt.get("phase", ""))
						== str(replay_source.WATERING_PHASE_COMPLETE),
				"EventLog replay reconstructs the watered fern result")
			check(str(replayed_item.get("holder", "")) == "peris"
					and str(replayed_item.get("location", "")) == "hand",
				"EventLog replay keeps the can in Peris's hand after use")
		await _discard(replay_source)

	var fresh := await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		check(fresh._watering_phase() == fresh.WATERING_PHASE_ACTIVE
				and fresh._peris_holds_watering_can()
				and fresh._watering_can_mesh.get_parent()
					== fresh.get_game_state_character_node("peris"),
			"fresh presenter reconstructs the exact midpoint hand item")
		fresh.headless_advance(0.65, 0.05)
		check(not fresh._plant_watered,
			"fresh presenter cannot fast-complete the unpaid remainder")
		fresh.headless_advance(0.11, 0.01)
		check(fresh._plant_watered and fresh._peris_holds_watering_can(),
			"fresh presenter completes once after the saved remainder")
		await _discard(fresh)

	# Rewinding to before pickup retracts every later fact; loading the completed
	# snapshot again restores it without relying on the old local bool.
	source.apply_save_snapshot(baseline_snapshot)
	check(not source._plant_watered
			and not source._game_state.has_mechanism_phase(source.WATERING_PHASE_ID)
			and str((source._game_state.items.get(item_id, {}) as Dictionary).get(
				"location", "")) == "ground",
		"baseline rollback retracts use, completion, and hand occupancy")
	var restored_baseline := source._game_state.get_world_state(
		source.WATERING_AUTHORITY_KEY, {}) as Dictionary
	check(str(restored_baseline.get("phase", ""))
			== str(source.WATERING_PHASE_AVAILABLE)
			and int((restored_baseline.get("source_committed_counts", {}) as Dictionary).get(
				source.WATERING_PICKUP_ACTION, -1)) == 0,
		"baseline restore retracts later source receipts to its saved zero counts")
	source.apply_save_snapshot(completed_snapshot)
	check(source._plant_watered and source._peris_holds_watering_can(),
		"completed snapshot restores result and canonical item ownership")

	await _verify_accepted_source_seams()
	await _discard(source)
	_finish()


func _verify_accepted_source_seams() -> void:
	await _verify_pickup_accepted_source_seam()
	await _verify_water_accepted_source_seam()


func _verify_pickup_accepted_source_seam() -> void:
	var same := await _spawn_sequence()
	if same == null:
		return
	var pickup: Node = same.find_child("WateringCanPickup", true, false)
	same.set_preview_character_position("peris", (pickup as Node3D).global_position)
	pickup.active_character = "peris"
	var callback := Callable(same, "_on_watering_can_picked").bind(pickup)
	if pickup.interacted.is_connected(callback):
		pickup.interacted.disconnect(callback)
	check(bool(pickup.call("_trigger", false)),
		"fixture captures accepted can pickup before its owner callback")
	var seam_snapshot := _json_round_trip(same.build_save_snapshot())
	pickup.interacted.connect(callback)
	check(not same._peris_holds_watering_can(),
		"accepted pickup edge alone leaves the can on the ground")

	same.apply_save_snapshot(seam_snapshot)
	var same_authority := same._game_state.get_world_state(
		same.WATERING_AUTHORITY_KEY, {}) as Dictionary
	check(not same._peris_holds_watering_can()
			and int((same_authority.get("source_committed_counts", {}) as Dictionary).get(
				same.WATERING_PICKUP_ACTION, 0)) == 1
			and pickup.is_interaction_enabled(),
		"same-presenter restore burns but rearms the orphan pickup edge")
	pickup.active_character = "peris"
	check(bool(pickup.call("_trigger", false)) and same._peris_holds_watering_can(),
		"same presenter requires a second exact pickup receipt")

	var fresh := await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(seam_snapshot)
		var fresh_pickup: Node = fresh.find_child(
			"WateringCanPickup", true, false)
		var fresh_authority := fresh._game_state.get_world_state(
			fresh.WATERING_AUTHORITY_KEY, {}) as Dictionary
		check(not fresh._peris_holds_watering_can()
				and int((fresh_authority.get(
					"source_committed_counts", {}) as Dictionary).get(
						fresh.WATERING_PICKUP_ACTION, 0)) == 1
				and fresh_pickup.is_interaction_enabled(),
			"fresh presenter burns and rearms the same orphan pickup edge")
		fresh_pickup.active_character = "peris"
		check(bool(fresh_pickup.call("_trigger", false))
				and fresh._peris_holds_watering_can(),
			"fresh presenter also needs a new exact pickup receipt")
		await _discard(fresh)
	await _discard(same)


func _verify_water_accepted_source_seam() -> void:
	var same := await _spawn_sequence()
	if same == null:
		return
	var pickup: Node = same.find_child("WateringCanPickup", true, false)
	var water: Node = same.find_child("WaterPlantSpot", true, false)
	same.set_preview_character_position("peris", (pickup as Node3D).global_position)
	pickup.active_character = "peris"
	check(bool(pickup.call("_trigger", false)) and same._peris_holds_watering_can(),
		"watering seam fixture physically picks up the exact can")
	same.set_preview_character_position("peris", (water as Node3D).global_position)
	water.active_character = "peris"
	var callback := Callable(same, "_on_plant_watered").bind(water)
	if water.interacted.is_connected(callback):
		water.interacted.disconnect(callback)
	check(bool(water.call("_trigger", false)),
		"fixture captures accepted fern use before its owner callback")
	var seam_snapshot := _json_round_trip(same.build_save_snapshot())
	water.interacted.connect(callback)
	check(same._watering_phase() == &"" and not same._plant_watered,
		"accepted fern edge alone starts no watering phase")

	same.apply_save_snapshot(seam_snapshot)
	var same_authority := same._game_state.get_world_state(
		same.WATERING_AUTHORITY_KEY, {}) as Dictionary
	check(same._watering_phase() == &"" and not same._plant_watered
			and int((same_authority.get("source_committed_counts", {}) as Dictionary).get(
				same.WATERING_USE_ACTION, 0)) == 1
			and water.is_interaction_enabled(),
		"same-presenter restore burns but rearms the orphan fern edge")
	water.active_character = "peris"
	check(bool(water.call("_trigger", false))
			and same._watering_phase() == same.WATERING_PHASE_ACTIVE,
		"same presenter needs a second exact fern receipt")

	var fresh := await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(seam_snapshot)
		var fresh_water: Node = fresh.find_child("WaterPlantSpot", true, false)
		var fresh_authority := fresh._game_state.get_world_state(
			fresh.WATERING_AUTHORITY_KEY, {}) as Dictionary
		check(fresh._watering_phase() == &"" and not fresh._plant_watered
				and int((fresh_authority.get(
					"source_committed_counts", {}) as Dictionary).get(
						fresh.WATERING_USE_ACTION, 0)) == 1
				and fresh_water.is_interaction_enabled(),
			"fresh presenter burns and rearms the same orphan fern edge")
		fresh_water.active_character = "peris"
		check(bool(fresh_water.call("_trigger", false))
				and fresh._watering_phase() == fresh.WATERING_PHASE_ACTIVE,
			"fresh presenter also needs a new exact fern receipt")
		await _discard(fresh)
	await _discard(same)


func _spawn_sequence(record_events := false) -> Node:
	if record_events:
		# Match CLI recording: attach before the sequence constructs GameState so
		# registration, item spawn, and every later action share one replayable log.
		GameState._pending_event_log = EventLog.new()
	var sequence := PerisScene.instantiate()
	sequence.set("suppress_scene_change", true)
	sequence.set("start_phase", 1)
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	# Do not leak a pending test recorder if construction failed before consuming it.
	if record_events and GameState._pending_event_log != null:
		GameState._pending_event_log = null
	if sequence._game_state == null or sequence._watering_can_mesh == null:
		check(false, "Peris sequence and watering presenter instantiate")
		await _discard(sequence)
		return null
	sequence._scheduler.clear()
	sequence._ui_scheduler.clear()
	sequence._start_workspace()
	await process_frame
	return sequence


func _json_round_trip(snapshot: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	return parsed as Dictionary if parsed is Dictionary else {}


func _move_authoritatively(sequence: Node, character_id: String, target: Vector3) -> bool:
	if not sequence._game_state.command_move_to_pos(character_id, target):
		return false
	for _step in range(600):
		if not sequence._game_state.is_moving(character_id):
			return sequence._game_state.get_position(character_id).distance_to(target) < 1.0
		sequence.headless_advance(0.05, 0.05)
	return false


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.has_method("_teardown_sequence"):
			node._teardown_sequence()
		node.queue_free()
		await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	print("PERIS WATERING AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
