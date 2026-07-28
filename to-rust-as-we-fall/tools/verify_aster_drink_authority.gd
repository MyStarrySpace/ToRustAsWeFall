extends SceneTree

## The Aster drink tutorial used to set ATP to max and mark the beat complete in the
## same callback that touched the machine. This verifier proves the replacement is a
## real GameState item/endocytosis transaction whose midpoint, remaining duration,
## hand occupancy, semantic receipt, and presenter all survive production save/load.

const AsterScene := preload("res://scenes/tutorial/aster_sim.tscn")
const EPSILON := 0.001

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source: Node = await _spawn_sequence()
	if source == null:
		_finish()
		return
	_prepare_drink_step(source)
	var absent_snapshot := _json_round_trip(source.build_save_snapshot())
	_erase_drink_authority(absent_snapshot, source.DRINK_AUTHORITY_KEY)

	var source_text := FileAccess.get_file_as_string(
		"res://scripts/tutorial/aster_sim_sequence.gd")
	check("_game_state.set_stat(\"aster\", \"atp\"" not in source_text,
		"drink production contains no direct ATP grant")
	check(str(source.headless_get_state().get("drink_phase", ""))
			== source.DRINK_PHASE_AVAILABLE,
		"drink begins as an available physical transaction")

	source._on_drink_interacted()
	source._drink_machine.interacted.emit()
	check(source._drink_item_id == "" and not source._has_drunk,
		"direct and manually emitted drink callbacks are inert without the source receipt")
	source._drink_machine.active_character = "aster"
	check(not bool(source._drink_machine.call("_trigger", false))
			and source._drink_item_id == "",
		"a remote selected Aster cannot operate the drink machine")
	source.set_preview_character_position(
		"aster", source._drink_machine.global_position)
	source._drink_machine.active_character = "ron"
	check(not bool(source._drink_machine.call("_trigger", false)),
		"the nearby wrong body cannot operate Aster's machine")
	source._drink_machine.active_character = "aster"
	check(bool(source._drink_machine.call("_trigger", false)),
		"the exact machine accepts nearby action-free Aster")

	var gs: GameState = source._game_state
	var item_id := str(source._drink_item_id)
	var authority := gs.get_world_state(source.DRINK_AUTHORITY_KEY, {}) as Dictionary
	check(source._current_step == "drink" and not source._has_drunk,
		"machine interaction begins the drink action without granting its endpoint")
	check(item_id != "" and gs.items.has(item_id)
			and item_id in gs.get_hand_items("aster")
			and gs.is_endocytosing("aster"),
		"machine dispenses a canonical lysate into Aster's hand and begins endocytosis")
	check(str(authority.get("phase", "")) == source.DRINK_PHASE_ENDOCYTOSING
			and str(authority.get("item_id", "")) == item_id
			and str(authority.get("source_data_id", ""))
				== source.ASTER_DRINK_SOURCE_ID
			and int(authority.get("source_trigger_count", 0)) == 1,
		"semantic receipt identifies the exact source edge and in-flight item")
	check(is_equal_approx(gs.get_stat("aster", "atp"), source.ATP_START),
		"ATP remains unchanged at action commitment")
	check(not source._drink_machine.is_interaction_enabled(),
		"machine cannot duplicate a drink while endocytosis owns the action")
	check(source._chunk_item_nodes.has(item_id),
		"dispensed lysate has a visible world/hand presenter")

	source.headless_advance(0.75, 0.05)
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var saved_endocytosis := (midpoint_snapshot.get("game_state", {}) as Dictionary).get(
		"endocytosing", {}) as Dictionary
	var saved_aster := saved_endocytosis.get("aster", {}) as Dictionary
	check(gs.is_endocytosing("aster") and not source._has_drunk
			and is_equal_approx(gs.get_stat("aster", "atp"), source.ATP_START),
		"midpoint remains an unfinished action with no ATP reward")
	check(abs(float(saved_aster.get("remaining", -1.0)) - 1.25) < 0.06,
		"midpoint snapshot stores only the unpaid endocytosis remainder")

	source.headless_advance(1.15, 0.05)
	check(gs.is_endocytosing("aster") and not source._has_drunk,
		"action cannot complete before its exact saved deadline")
	source.headless_advance(0.11, 0.01)
	check(not gs.is_endocytosing("aster") and source._has_drunk
			and is_equal_approx(gs.get_stat("aster", "atp"), source.ATP_MAX),
		"deadline consumes the item and applies its canonical digest reward once")
	check(not gs.items.has(item_id) and item_id not in gs.get_hand_items("aster")
			and not source._chunk_item_nodes.has(item_id),
		"completion removes both canonical lysate and its hand presenter")
	check(str(source.headless_get_state().get("drink_phase", ""))
			== source.DRINK_PHASE_CONSUMED,
		"completion commits a terminal semantic receipt")
	var completed_snapshot := _json_round_trip(source.build_save_snapshot())

	# Same-presenter rewind must retract the future receipt/reward and rebuild the
	# exact item, hand, timer, and visible presenter from the saved midpoint.
	source.apply_save_snapshot(midpoint_snapshot)
	check(source._current_step == "drink" and not source._has_drunk
			and source._game_state.is_endocytosing("aster")
			and is_equal_approx(source._game_state.get_stat("aster", "atp"), source.ATP_START),
		"same-presenter rewind retracts the consumed future to the midpoint")
	check(source._drink_item_id == item_id and source._chunk_item_nodes.has(item_id),
		"same-presenter rewind reconstructs the exact in-hand lysate presenter")
	var projection_before: Dictionary = source._game_state.serialize()
	source.on_game_state_snapshot_restored()
	var projection_after: Dictionary = source._game_state.serialize()
	if projection_after != projection_before:
		for key_variant in projection_before.keys():
			var key := str(key_variant)
			if projection_before.get(key_variant) != projection_after.get(key_variant):
				print("DRINK ATTACHMENT DIFF [", key, "]: before=",
					projection_before.get(key_variant), " after=", projection_after.get(key_variant))
	check(projection_after == projection_before,
		"repeated drink presenter attachment emits no synthetic gameplay command")
	source.headless_advance(1.15, 0.05)
	check(not source._has_drunk and source._game_state.is_endocytosing("aster"),
		"same-presenter reload still pays the saved remainder")
	source.headless_advance(0.11, 0.01)
	check(source._has_drunk
			and is_equal_approx(source._game_state.get_stat("aster", "atp"), source.ATP_MAX),
		"same-presenter reload reaches the endpoint once after the remainder")

	var fresh: Node = await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		check(not fresh._has_drunk and fresh._game_state.is_endocytosing("aster")
				and fresh._drink_item_id == item_id
				and fresh._chunk_item_nodes.has(item_id),
			"fresh presenter reconstructs the saved hand item and midpoint action")
		fresh.headless_advance(1.15, 0.05)
		check(not fresh._has_drunk and fresh._game_state.is_endocytosing("aster"),
			"fresh presenter cannot finish early")
		fresh.headless_advance(0.11, 0.01)
		check(fresh._has_drunk
				and is_equal_approx(fresh._game_state.get_stat("aster", "atp"), fresh.ATP_MAX),
			"fresh presenter completes after only the saved remainder")
		await _discard(fresh)

	# A save from before the transaction must erase every later fact, including a
	# consumed receipt. Loading it cannot silently synthesize a new baseline command.
	source.apply_save_snapshot(completed_snapshot)
	check(source._has_drunk, "completed snapshot reconstructs the consumed endpoint")
	source.apply_save_snapshot(absent_snapshot)
	check(not source._has_drunk and not source._game_state.is_endocytosing("aster")
			and source._game_state.items.is_empty()
			and is_equal_approx(source._game_state.get_stat("aster", "atp"), source.ATP_START),
		"absent authority retracts the item, timer, receipt, and ATP future")
	check(source._current_step == "walk_to_drink"
			and source._drink_machine.is_interaction_enabled(),
		"absent authority returns the player to the actionable machine baseline")
	check(source._game_state.get_world_state(source.DRINK_AUTHORITY_KEY, null) == null,
		"absence restoration does not manufacture an authority record")

	await _verify_accepted_source_seam()
	await _discard(source)
	_finish()


func _verify_accepted_source_seam() -> void:
	var same: Node = await _spawn_sequence()
	if same == null:
		return
	_prepare_drink_step(same)
	same.set_preview_character_position(
		"aster", same._drink_machine.global_position)
	same._drink_machine.active_character = "aster"
	var callback := Callable(same, "_on_drink_interacted")
	if same._drink_machine.interacted.is_connected(callback):
		same._drink_machine.interacted.disconnect(callback)
	check(bool(same._drink_machine.call("_trigger", false)),
		"fixture captures the accepted machine edge before its owner callback")
	var seam_snapshot := _json_round_trip(same.build_save_snapshot())
	same._drink_machine.interacted.connect(callback)
	check(same._drink_item_id == "" and not same._game_state.is_endocytosing("aster"),
		"accepted source edge alone grants no item or endocytosis")

	same.apply_save_snapshot(seam_snapshot)
	var same_receipt := same._game_state.get_world_state(
		same.DRINK_AUTHORITY_KEY, {}) as Dictionary
	check(same._drink_item_id == "" and not same._has_drunk
			and int(same_receipt.get("source_trigger_count", 0)) == 1
			and same._drink_machine.is_interaction_enabled(),
		"same-presenter restore burns but rearms the orphan machine edge")
	same._drink_machine.active_character = "aster"
	check(bool(same._drink_machine.call("_trigger", false))
			and same._drink_item_id != "",
		"same presenter requires a second physical machine receipt")

	var fresh: Node = await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(seam_snapshot)
		var fresh_receipt := fresh._game_state.get_world_state(
			fresh.DRINK_AUTHORITY_KEY, {}) as Dictionary
		check(fresh._drink_item_id == "" and not fresh._has_drunk
				and int(fresh_receipt.get("source_trigger_count", 0)) == 1
				and fresh._drink_machine.is_interaction_enabled(),
			"fresh presenter also burns and rearms the accepted edge")
		fresh._drink_machine.active_character = "aster"
		check(bool(fresh._drink_machine.call("_trigger", false))
				and fresh._drink_item_id != "",
			"fresh presenter also needs a new physical machine receipt")
		await _discard(fresh)
	await _discard(same)


func _spawn_sequence() -> Node:
	var sequence: Node = AsterScene.instantiate()
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	if sequence._game_state == null or sequence._drink_machine == null:
		check(false, "Aster sequence and drink machine instantiate")
		await _discard(sequence)
		return null
	return sequence


func _prepare_drink_step(sequence: Node) -> void:
	sequence._scheduler.clear()
	if sequence._dialogue != null:
		sequence._dialogue.clear()
	sequence._start_walk_to_drink()
	sequence._scheduler.clear()


func _erase_drink_authority(snapshot: Dictionary, key: String) -> void:
	var game_state := snapshot.get("game_state", {}) as Dictionary
	var world_state := game_state.get("world_state", {}) as Dictionary
	world_state.erase(key)


func _json_round_trip(snapshot: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
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
	print("ASTER DRINK AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
