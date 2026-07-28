extends SceneTree

## Regression for the two campaign iron hazards that once integrated damage from render delta.
## Each scene is exercised through its production save artifact, including same-presenter rollback,
## fresh-scene attachment, exact midpoint cadence, an idempotent attachment pass, and snapshot
## absence retracting callbacks from the discarded future.

const Act1Scene := preload("res://scenes/tutorial/act1.tscn")
const LeavingFacilityScene := preload("res://scenes/tutorial/leaving_facility.tscn")
const MIDPOINT_ADVANCE := 0.2
const DEADLINE_EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_act1_iron()
	await _verify_leaving_facility_iron()
	print("CAMPAIGN IRON SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_act1_iron() -> void:
	var sequence: Node = await _spawn_sequence(Act1Scene)
	check(sequence._iron_patches.size() == 4,
		"Act 1 builds the four deterministic Channels iron patches")
	var patch: Dictionary = sequence._iron_patches[0]
	var hazard_position: Vector3 = patch.get("pos", Vector3.ZERO)
	var safe_position := hazard_position + Vector3(0.0, 0.0, 20.0)
	_prepare_cadence(sequence)
	_set_character_position(sequence, "aster", hazard_position)
	_set_character_position(sequence, "peris", safe_position)
	var damage_per_tick: float = sequence.IRON_DAMAGE_PER_SEC * sequence.IRON_DAMAGE_INTERVAL

	var absent_snapshot: Dictionary = _json_round_trip(sequence.build_save_snapshot())
	_erase_authority_record(absent_snapshot, sequence.IRON_HAZARD_AUTHORITY_KEY)
	var absent_hp: float = sequence._game_state.get_stat("aster", "hp")
	sequence._scheduler.advance_ticks(sequence.IRON_DAMAGE_INTERVAL)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"),
		absent_hp - damage_per_tick),
		"Act 1 scheduler applies one fixed iron quantum without a render frame")
	sequence.apply_save_snapshot(absent_snapshot)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), absent_hp),
		"Act 1 absence rollback retracts discarded-future iron damage")
	check(not sequence._iron_hazard_active and sequence._iron_hazard_next_tick < 0.0,
		"Act 1 absent authority leaves no local cadence phase")
	check(sequence._game_state.get_world_state(
		sequence.IRON_HAZARD_AUTHORITY_KEY, null) == null,
		"Act 1 absent authority remains absent after attachment")
	sequence._scheduler.advance_ticks(sequence.IRON_DAMAGE_INTERVAL * 2.1)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), absent_hp),
		"Act 1 absent authority cannot retain a future iron callback")

	_prepare_cadence(sequence)
	sequence._scheduler.advance_ticks(MIDPOINT_ADVANCE)
	var midpoint_snapshot: Dictionary = _json_round_trip(sequence.build_save_snapshot())
	var midpoint_hp: float = sequence._game_state.get_stat("aster", "hp")
	var deadline: float = _saved_deadline(sequence)
	var saved_tick: float = float(sequence._scheduler.get_current_tick())
	check(deadline > saved_tick,
		"Act 1 save carries an absolute future iron deadline")
	sequence._scheduler.advance_ticks(deadline - saved_tick)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"),
		midpoint_hp - damage_per_tick),
		"Act 1 discarded midpoint future reaches its scheduled hit")
	sequence.apply_save_snapshot(midpoint_snapshot)
	sequence.on_game_state_snapshot_restored()
	check(sequence._iron_hazard_active
			and is_equal_approx(sequence._iron_hazard_next_tick, deadline),
		"Act 1 repeated attachment preserves one saved cadence phase")
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), midpoint_hp),
		"Act 1 midpoint rollback restores authoritative HP")
	_advance_across_deadline(sequence, deadline, midpoint_hp, damage_per_tick,
		"Act 1 same-presenter")

	_end_sequence(sequence)
	var fresh: Node = await _spawn_sequence(Act1Scene)
	fresh.apply_save_snapshot(midpoint_snapshot)
	fresh.on_game_state_snapshot_restored()
	check(fresh._iron_hazard_active and is_equal_approx(fresh._iron_hazard_next_tick, deadline),
		"fresh Act 1 scene attaches to the saved absolute iron deadline")
	check(fresh._game_state.get_position("aster").is_equal_approx(hazard_position),
		"fresh Act 1 scene restores the party's hazard position")
	_advance_across_deadline(fresh, deadline, midpoint_hp, damage_per_tick,
		"Act 1 fresh-presenter")
	_end_sequence(fresh)


func _verify_leaving_facility_iron() -> void:
	var sequence: Node = await _spawn_sequence(LeavingFacilityScene)
	_prepare_cadence(sequence)
	sequence._current_step = "first_corridor"
	var hazard_position: Vector3 = sequence.IRON_1_POS
	var safe_position := hazard_position + Vector3(0.0, 0.0, 12.0)
	_set_character_position(sequence, "aster", hazard_position)
	_set_character_position(sequence, "peris", safe_position)
	_set_character_position(sequence, "endo", safe_position + Vector3(2.0, 0.0, 0.0))
	var damage_per_tick: float = sequence.IRON_DAMAGE_PER_SEC * sequence.IRON_DAMAGE_INTERVAL

	var absent_snapshot: Dictionary = _json_round_trip(sequence.build_save_snapshot())
	_erase_authority_record(absent_snapshot, sequence.IRON_HAZARD_AUTHORITY_KEY)
	var absent_hp: float = sequence._game_state.get_stat("aster", "hp")
	sequence._scheduler.advance_ticks(sequence.IRON_DAMAGE_INTERVAL)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"),
		absent_hp - damage_per_tick),
		"Leaving Facility scheduler applies one fixed iron quantum without a render frame")
	check(is_equal_approx(sequence._iron_damage_total, damage_per_tick)
			and is_equal_approx(sequence._iron_exposure_seconds, sequence.IRON_DAMAGE_INTERVAL),
		"Leaving Facility cadence updates its cumulative QA evidence atomically")
	sequence.apply_save_snapshot(absent_snapshot)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), absent_hp),
		"Leaving Facility absence rollback retracts discarded-future damage")
	check(not sequence._iron_hazard_active and sequence._iron_hazard_next_tick < 0.0,
		"Leaving Facility absent authority leaves no local cadence phase")
	check(is_zero_approx(sequence._iron_damage_total)
			and is_zero_approx(sequence._iron_exposure_seconds)
			and sequence._sectors_entered.is_empty(),
		"Leaving Facility absent authority retracts future-only metrics and discovery")
	sequence._scheduler.advance_ticks(sequence.IRON_DAMAGE_INTERVAL * 2.1)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), absent_hp),
		"Leaving Facility absent authority cannot retain a future iron callback")

	_prepare_cadence(sequence)
	sequence._current_step = "first_corridor"
	sequence._scheduler.advance_ticks(MIDPOINT_ADVANCE)
	var midpoint_snapshot: Dictionary = _json_round_trip(sequence.build_save_snapshot())
	var midpoint_hp: float = sequence._game_state.get_stat("aster", "hp")
	var deadline: float = _saved_deadline(sequence)
	var saved_tick: float = float(sequence._scheduler.get_current_tick())
	check(deadline > saved_tick,
		"Leaving Facility save carries an absolute future iron deadline")
	sequence._scheduler.advance_ticks(deadline - saved_tick)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"),
		midpoint_hp - damage_per_tick),
		"Leaving Facility discarded midpoint future reaches its scheduled hit")
	check(sequence._sectors_entered.has("bleedway"),
		"Leaving Facility future tick records the entered field")
	sequence.apply_save_snapshot(midpoint_snapshot)
	sequence.on_game_state_snapshot_restored()
	check(sequence._iron_hazard_active
			and is_equal_approx(sequence._iron_hazard_next_tick, deadline),
		"Leaving Facility repeated attachment preserves one saved cadence phase")
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), midpoint_hp)
			and sequence._sectors_entered.is_empty(),
		"Leaving Facility midpoint rollback restores HP and retracts future discovery")
	_advance_across_deadline(sequence, deadline, midpoint_hp, damage_per_tick,
		"Leaving Facility same-presenter")

	_end_sequence(sequence)
	var fresh: Node = await _spawn_sequence(LeavingFacilityScene)
	fresh.apply_save_snapshot(midpoint_snapshot)
	fresh.on_game_state_snapshot_restored()
	check(fresh._current_step == "first_corridor" and fresh._iron_hazard_active
			and is_equal_approx(fresh._iron_hazard_next_tick, deadline),
		"fresh Leaving Facility scene restores step and absolute iron deadline")
	check(fresh._game_state.get_position("aster").is_equal_approx(hazard_position),
		"fresh Leaving Facility scene restores the party's hazard position")
	_advance_across_deadline(fresh, deadline, midpoint_hp, damage_per_tick,
		"Leaving Facility fresh-presenter")
	# A repeating hazard must coexist with ordinary story callbacks on the same scheduler lane.
	fresh._start_dusk_approaches()
	fresh._scheduler.advance_ticks(4.01)
	check(fresh._current_step == "second_iron" and fresh._iron_hazard_active,
		"Leaving Facility cadence does not starve the scheduled dusk handoff")
	_end_sequence(fresh)


func _spawn_sequence(scene: PackedScene) -> Node:
	var sequence := scene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	return sequence


func _prepare_cadence(sequence: Node) -> void:
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	sequence._iron_hazard_active = false
	sequence._iron_hazard_next_tick = -1.0
	sequence._start_iron_hazard_cadence()


func _set_character_position(sequence: Node, character_id: String, position: Vector3) -> void:
	sequence.set_preview_character_position(character_id, position)


func _saved_deadline(sequence: Node) -> float:
	var authority_v: Variant = sequence._game_state.get_world_state(
		sequence.IRON_HAZARD_AUTHORITY_KEY, {})
	if not authority_v is Dictionary:
		return -1.0
	return float((authority_v as Dictionary).get("next_tick", -1.0))


func _erase_authority_record(snapshot: Dictionary, authority_key: String) -> void:
	var game_state_data: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state_data.get("world_state", {})
	world_state.erase(authority_key)
	game_state_data["world_state"] = world_state
	snapshot["game_state"] = game_state_data


func _advance_across_deadline(
		sequence: Node,
		deadline: float,
		starting_hp: float,
		damage_per_tick: float,
		label_prefix: String
	) -> void:
	var remaining: float = deadline - float(sequence._scheduler.get_current_tick())
	sequence._scheduler.advance_ticks(maxf(0.0, remaining - DEADLINE_EPSILON))
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"), starting_hp),
		"%s does not hit before the saved remainder" % label_prefix)
	# Cross by one millisecond instead of relying on binary float equality at the exact boundary.
	sequence._scheduler.advance_ticks(DEADLINE_EPSILON + 0.001)
	check(is_equal_approx(sequence._game_state.get_stat("aster", "hp"),
		starting_hp - damage_per_tick),
		"%s applies exactly one hit at the saved deadline" % label_prefix)


func _end_sequence(sequence: Node) -> void:
	if sequence.has_method("_teardown_sequence"):
		sequence._teardown_sequence()
	sequence.free()


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
