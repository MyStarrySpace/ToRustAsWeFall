extends SceneTree

## Tag Day used to wait five seconds, snap three render nodes into a formation, and
## start the corridor regardless of where the GameState actors actually were. This
## verifies that the handoff is now caused by both Naturalizers' saved physical arrivals.

const TagDayScene := preload("res://scenes/tutorial/tag_day.tscn")

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
	_prepare(source)
	var source_text := FileAccess.get_file_as_string(
		"res://scripts/tutorial/tag_day_sequence.gd")
	check("schedule_after(5.0, _begin_corridor_walk" not in source_text,
		"formation handoff contains no fixed five-second progression timer")
	check("_citizen.global_position =" not in source_text
			and "_naturalizer_1.global_position =" not in source_text
			and "_naturalizer_2.global_position =" not in source_text,
		"corridor handoff contains no render-node formation teleport")

	var original_nk1: Vector3 = source._game_state.get_position("nk1")
	var original_nk2: Vector3 = source._game_state.get_position("nk2")
	var absent_snapshot: Dictionary = _json_round_trip(source.build_save_snapshot())
	source._start_naturalizers_grip()
	check(source._current_step == "naturalizers_grip"
			and source._game_state.is_moving("nk1")
			and source._game_state.is_moving("nk2"),
		"grip beat commits real movement for both Naturalizers")
	source.headless_advance(2.0, 0.05)
	var nk1_mid: Vector3 = source._game_state.get_position("nk1")
	var nk2_mid: Vector3 = source._game_state.get_position("nk2")
	check(source._current_step == "naturalizers_grip"
			and nk1_mid.distance_to(original_nk1) > 0.5
			and nk2_mid.distance_to(original_nk2) > 0.5
			and nk2_mid.distance_to(source.NK_GRIP_POS_2) > source.GRIP_ARRIVAL_RADIUS,
		"midpoint shows physical approach and cannot begin the corridor early")
	var midpoint_snapshot: Dictionary = _json_round_trip(source.build_save_snapshot())

	var source_remaining: float = _advance_until_corridor(source, 10.0)
	check(source._current_step == "corridor_walk" and source_remaining > 0.1,
		"both physical arrivals—not elapsed wall time—begin the corridor")
	check(source._game_state.is_moving("citizen")
			and source._game_state.is_moving("nk1")
			and source._game_state.is_moving("nk2"),
		"arrival handoff continues into three authoritative corridor paths")

	source.apply_save_snapshot(midpoint_snapshot)
	check(source._current_step == "naturalizers_grip"
			and source._game_state.is_moving("nk1")
			and source._game_state.is_moving("nk2")
			and source._game_state.get_position("nk1").distance_to(nk1_mid) < 0.01
			and source._game_state.get_position("nk2").distance_to(nk2_mid) < 0.01,
		"same-presenter rewind retracts the corridor future to both saved path midpoints")
	var projection_before: Dictionary = source._game_state.serialize()
	source.on_game_state_snapshot_restored()
	check(source._game_state.serialize() == projection_before,
		"repeated grip attachment emits no synthetic movement or arrival command")
	var same_remaining: float = _advance_until_corridor(source, 10.0)
	check(source._current_step == "corridor_walk"
			and absf(same_remaining - source_remaining) < 0.11,
		"same-presenter reload consumes exactly the saved movement remainder")

	var fresh: Node = await _spawn_sequence()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		check(fresh._current_step == "naturalizers_grip"
				and fresh._game_state.is_moving("nk1")
				and fresh._game_state.is_moving("nk2"),
			"fresh presenter reconstructs both in-flight formation paths")
		var fresh_remaining: float = _advance_until_corridor(fresh, 10.0)
		check(fresh._current_step == "corridor_walk"
				and absf(fresh_remaining - source_remaining) < 0.11,
			"fresh presenter reaches the same arrival-owned handoff tick")
		await _discard(fresh)

	# A save from before the grip must retract both paths and the later corridor.
	source.apply_save_snapshot(absent_snapshot)
	check(source._current_step == "citizen_scan"
			and not source._game_state.is_moving("nk1")
			and not source._game_state.is_moving("nk2"),
		"pre-grip snapshot removes both discarded movement futures")
	check(source._game_state.get_position("nk1").distance_to(original_nk1) < 0.01
			and source._game_state.get_position("nk2").distance_to(original_nk2) < 0.01,
		"absence restores the authored Naturalizer posts instead of a snapped formation")
	source.headless_advance(12.0, 0.1)
	check(source._current_step == "citizen_scan",
		"advancing an absent future cannot synthesize a corridor handoff")

	await _discard(source)
	_finish()


func _spawn_sequence() -> Node:
	var sequence: Node = TagDayScene.instantiate()
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	if sequence._game_state == null:
		check(false, "Tag Day sequence instantiates")
		await _discard(sequence)
		return null
	sequence.set_process(false)
	return sequence


func _prepare(sequence: Node) -> void:
	sequence._scheduler.clear()
	sequence._dialogue.clear()
	sequence._current_step = "citizen_scan"


func _advance_until_corridor(sequence: Node, limit: float) -> float:
	var elapsed := 0.0
	while sequence._current_step == "naturalizers_grip" and elapsed < limit:
		sequence.headless_advance(0.05, 0.05)
		elapsed += 0.05
	return elapsed


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
	print("TAG DAY GRIP AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
