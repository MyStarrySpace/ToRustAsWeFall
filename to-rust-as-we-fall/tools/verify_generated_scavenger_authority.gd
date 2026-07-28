extends SceneTree

## Focused authority regression for the generated hydraulic scavenger chain.
## The cargo fall is caused by a stable GameState Enemy reaching the loading rack;
## basin clearance is caused by that same body reaching the lysate source.

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const SPEC_PATH := (
	"res://data/generated_stretches/generated_teaching_channels_shelter_1_to_2.json"
)
const CHUNK_SOURCE := "res://scripts/fragments/chunks/generated_stretch_chunk.gd"


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
	_verify_source_ratchet()
	await _verify_interrupted_approach_withholds_contact()
	await _verify_approach_contact_fall_and_retreat_save_seams()
	print(
		"GENERATED SCAVENGER AUTHORITY: %d checks, %d failures"
		% [_checks, _failures]
	)
	quit(0 if _failures == 0 else 1)


func _verify_source_ratchet() -> void:
	print("\n--- source authority ratchet ---")
	var source := FileAccess.get_file_as_string(CHUNK_SOURCE)
	check(not source.is_empty(), "generated chunk source is readable")
	check(
		not source.contains("scripted_setpiece_actor")
		and not source.contains("BRIDGE_INTRO_")
		and not source.contains("_schedule_bridge_cargo_intro")
		and not source.contains("canonical_sequence_tick")
		and not source.contains("func _update_hydraulic_scavenger")
		and not source.contains(
			"_set_hydraulic_flat_transform(\n\t\t_hydraulic_scavenger"
		),
		"scavenger has no proxy metadata, fixed endpoint ticks, or manual transform driver"
	)
	check(
		source.contains("gs.register_character(")
		and source.contains("gs.command_walk_path(character_id, path)")
		and source.contains("gs.character_arrived.connect(arrived_callback)"),
		"generated chain registers and moves one body through GameState arrival authority"
	)


func _verify_interrupted_approach_withholds_contact() -> void:
	print("\n--- interrupted approach ---")
	var pair := await _boot_pair()
	_assert_initial_body(pair, "initial")
	var durations := _route_durations(pair)
	check(_trigger_first_sluice(pair), "First Sluice commits the body approach")
	check(
		_phase(pair) == "approaching_rack" and _body_is_moving(pair),
		"opening the sluice starts a real GameState movement plan"
	)
	await _advance(pair, float(durations.approach) * 0.45)
	var interrupted_position := _body_position(pair)
	check(
		interrupted_position.distance_to(_route(pair)[0]) > 0.05
		and interrupted_position.distance_to(_route(pair)[1]) > 0.05,
		"approach presenter/data body occupies an in-flight position before contact"
	)
	pair.host.game_state.command_stop(_body_id(pair))
	var stopped_snapshot := _capture(pair)
	await _advance(pair, float(durations.total) + 2.0)
	_assert_interrupted(pair, interrupted_position, "live interruption")

	_apply_snapshot(pair, stopped_snapshot)
	await _advance(pair, float(durations.total) + 2.0)
	_assert_interrupted(pair, interrupted_position, "same-instance stopped restore")

	var fresh := await _boot_pair()
	_apply_snapshot(fresh, stopped_snapshot)
	await _advance(fresh, float(durations.total) + 2.0)
	_assert_interrupted(fresh, interrupted_position, "fresh stopped restore")
	await _free_pair(fresh)
	await _free_pair(pair)


func _verify_approach_contact_fall_and_retreat_save_seams() -> void:
	print("\n--- approach/contact/fall/retreat save seams ---")
	var pair := await _boot_pair()
	var durations := _route_durations(pair)
	check(_trigger_first_sluice(pair), "save-seam probe starts approach")
	await _advance(pair, float(durations.approach) * 0.37)
	var approach_snapshot := _capture(pair)
	var approach_position := _body_position(pair)
	_assert_in_flight(pair, "approaching_rack", "elevated", "approach capture")

	_apply_snapshot(pair, approach_snapshot)
	check(
		_body_position(pair).distance_to(approach_position) <= 0.001
		and _body_is_moving(pair),
		"same-instance approach restore preserves exact body position and remaining plan"
	)
	var fresh_approach := await _boot_pair()
	_apply_snapshot(fresh_approach, approach_snapshot)
	check(
		_body_position(fresh_approach).distance_to(approach_position) <= 0.001
		and _body_is_moving(fresh_approach)
		and _phase(fresh_approach) == "approaching_rack",
		"fresh approach restore preserves body, route phase, and elevated cargo"
	)
	await _free_pair(fresh_approach)

	var runtime_key := str(pair.chunk.call("_generated_runtime_authority_key"))
	var captures := {}
	pair.host.game_state.world_state_changed.connect(
		func(key: String, value: Variant) -> void:
			if key != runtime_key or not (value is Dictionary) or captures.has("contact"):
				return
			var events := _milestone_events_from_record(value as Dictionary)
			if not events.is_empty() and events.back() == "scavenger_dislodged_cargo":
				captures["contact"] = _capture(pair)
	)
	await _advance(pair, float(durations.approach))
	check(captures.has("contact"), "contact publication exposes a restorable transaction seam")
	if not captures.has("contact"):
		await _free_pair(pair)
		return

	var contact_snapshot := captures.contact as Dictionary
	_apply_snapshot(pair, contact_snapshot)
	_assert_contact_restore(pair, "same-instance contact restore")
	var fresh_contact := await _boot_pair()
	_apply_snapshot(fresh_contact, contact_snapshot)
	_assert_contact_restore(fresh_contact, "fresh contact restore")
	await _free_pair(fresh_contact)

	await _advance(pair, 0.37)
	var fall_snapshot := _capture(pair)
	var fall_position := _body_position(pair)
	var fall_start := float(pair.chunk.get("_bridge_cargo_fall_start_tick"))
	var fall_end := float(pair.chunk.get("_bridge_cargo_fall_end_tick"))
	_assert_in_flight(pair, "retreating_to_lysate", "falling", "mid-fall capture")

	_apply_snapshot(pair, fall_snapshot)
	check(
		_body_position(pair).distance_to(fall_position) <= 0.001
		and is_equal_approx(float(pair.chunk.get("_bridge_cargo_fall_start_tick")), fall_start)
		and is_equal_approx(float(pair.chunk.get("_bridge_cargo_fall_end_tick")), fall_end),
		"same-instance mid-fall restore preserves body progress and absolute fall interval"
	)
	var fresh_fall := await _boot_pair()
	_apply_snapshot(fresh_fall, fall_snapshot)
	check(
		_body_position(fresh_fall).distance_to(fall_position) <= 0.001
		and _body_is_moving(fresh_fall)
		and _cargo_phase(fresh_fall) == "falling",
		"fresh mid-fall restore preserves retreat movement and falling cargo"
	)
	await _free_pair(fresh_fall)

	var remaining_fall := maxf(0.0, fall_end - pair.host.scheduler.get_current_tick())
	await _advance(pair, remaining_fall + 0.01)
	check(
		_cargo_phase(pair) == "staged"
		and _phase(pair) == "retreating_to_lysate"
		and _body_is_moving(pair),
		"physical cargo can finish falling while the same body continues its retreat"
	)
	var retreat_snapshot := _capture(pair)
	var retreat_position := _body_position(pair)

	_apply_snapshot(pair, retreat_snapshot)
	check(
		_body_position(pair).distance_to(retreat_position) <= 0.001
		and _cargo_phase(pair) == "staged"
		and _body_is_moving(pair),
		"same-instance retreat restore keeps staged cargo and exact remaining body plan"
	)
	var fresh_retreat := await _boot_pair()
	_apply_snapshot(fresh_retreat, retreat_snapshot)
	check(
		_body_position(fresh_retreat).distance_to(retreat_position) <= 0.001
		and _phase(fresh_retreat) == "retreating_to_lysate"
		and _body_is_moving(fresh_retreat),
		"fresh retreat restore keeps the same body and route phase"
	)

	check(
		bool(pair.chunk.call("_advance_hydraulic_scavenger_chain_for_headless")),
		"same-instance completion advances actual movement/fall authority only"
	)
	_assert_complete_once(pair, "same-instance completion")
	check(
		bool(fresh_retreat.chunk.call("_advance_hydraulic_scavenger_chain_for_headless")),
		"fresh completion advances restored movement authority only"
	)
	_assert_complete_once(fresh_retreat, "fresh completion")
	var complete_snapshot := _capture(fresh_retreat)
	_apply_snapshot(fresh_retreat, complete_snapshot)
	fresh_retreat.chunk.call("on_game_state_snapshot_restored")
	_assert_complete_once(fresh_retreat, "repeated completed restore")

	await _free_pair(fresh_retreat)
	await _free_pair(pair)


func _boot_pair() -> Dictionary:
	var host := AuthorityHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk(
		{
			"spec_path": SPEC_PATH,
			"game_mode": "neutral",
			"food_test": "neutral",
			"branches": true,
		}
	)
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	host.game_state.coord_map = chunk.call("get_coord_map")
	chunk.call("on_game_state_grid_ready")
	chunk.call("reset_preview_state")
	await process_frame
	return {"host": host, "chunk": chunk}


func _free_pair(pair: Dictionary) -> void:
	var host: Node = pair.get("host", null)
	if host != null and is_instance_valid(host):
		host.queue_free()
	await process_frame


func _capture(pair: Dictionary) -> Dictionary:
	return {
		"scheduler": _json_round_trip(pair.host.scheduler.serialize()),
		"game_state": _json_round_trip(pair.host.game_state.serialize()),
	}


func _trigger_first_sluice(pair: Dictionary) -> bool:
	var source_v: Variant = pair.chunk.get("_hydraulic_first_control")
	if not (source_v is Node) or not is_instance_valid(source_v):
		return false
	var source := source_v as Node
	var position_v: Variant = pair.chunk.call(
		"_generated_interaction_data_position", source
	)
	if not (position_v is Vector3):
		return false
	pair.host.game_state.snap_character_to("aster", position_v as Vector3)
	source.set("active_character", "aster")
	return bool(source.call("_trigger", false))


func _apply_snapshot(pair: Dictionary, snapshot: Dictionary) -> void:
	pair.host.scheduler.clear()
	pair.host.scheduler.deserialize(
		(snapshot.get("scheduler", {}) as Dictionary).duplicate(true)
	)
	pair.host.game_state.deserialize(
		(snapshot.get("game_state", {}) as Dictionary).duplicate(true)
	)
	pair.chunk.call("on_game_state_snapshot_restored")


func _json_round_trip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _advance(pair: Dictionary, seconds: float) -> void:
	pair.host.scheduler.advance_ticks(maxf(0.0, seconds))
	pair.chunk.call("_update_hydraulic_cargo_sequence", seconds)
	await process_frame


func _runtime_record(pair: Dictionary) -> Dictionary:
	var key := str(pair.chunk.call("_generated_runtime_authority_key"))
	var record: Variant = pair.host.game_state.get_world_state(key, {})
	return record as Dictionary if record is Dictionary else {}


func _body_id(pair: Dictionary) -> String:
	return str((pair.chunk.call("get_preview_state") as Dictionary).get(
		"bridge_scavenger_character_id", ""
	))


func _body_position(pair: Dictionary) -> Vector3:
	return pair.host.game_state.get_position(_body_id(pair))


func _body_is_moving(pair: Dictionary) -> bool:
	return pair.host.game_state.is_moving(_body_id(pair))


func _route(pair: Dictionary) -> Array:
	var route_v: Variant = pair.chunk.get("_bridge_scavenger_route")
	return route_v as Array if route_v is Array else []


func _route_durations(pair: Dictionary) -> Dictionary:
	var route := _route(pair)
	var speed := float((pair.chunk.get("_hydraulic_scavenger") as Enemy).move_speed)
	var approach := (route[0] as Vector3).distance_to(route[1] as Vector3) / speed
	var retreat := (
		(route[1] as Vector3).distance_to(route[2] as Vector3)
		+ (route[2] as Vector3).distance_to(route[3] as Vector3)
	) / speed
	return {"approach": approach, "retreat": retreat, "total": approach + retreat + 1.05}


func _phase(pair: Dictionary) -> String:
	return str(_runtime_record(pair).get("bridge_scavenger_phase", ""))


func _cargo_phase(pair: Dictionary) -> String:
	return str(_runtime_record(pair).get("bridge_cargo_phase", ""))


func _milestone_events(pair: Dictionary) -> Array[String]:
	return _milestone_events_from_record(_runtime_record(pair))


func _milestone_events_from_record(record: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for milestone_v in (record.get("bridge_cargo_milestones", []) as Array):
		if milestone_v is Dictionary:
			result.append(str((milestone_v as Dictionary).get("event", "")))
	return result


func _event_count(events: Array[String], event_id: String) -> int:
	var count := 0
	for event in events:
		if event == event_id:
			count += 1
	return count


func _assert_initial_body(pair: Dictionary, label: String) -> void:
	var body_id := _body_id(pair)
	var body_v: Variant = pair.chunk.get("_hydraulic_scavenger")
	var route := _route(pair)
	check(
		body_v is Enemy
		and (body_v as Enemy).char_id == body_id
		and body_id.begins_with("generated_hydraulic_scavenger:")
		and pair.host.game_state.characters.has(body_id),
		"%s has one stable GameState-registered Enemy body" % label
	)
	check(
		_phase(pair) == "dormant"
		and _cargo_phase(pair) == "elevated"
		and not _body_is_moving(pair)
		and _body_position(pair).distance_to(route[0]) <= 0.001,
		"%s restores dormant body, rack cargo, and spawn position together" % label
	)


func _assert_interrupted(pair: Dictionary, expected_position: Vector3, label: String) -> void:
	var events := _milestone_events(pair)
	check(
		_phase(pair) == "approaching_rack"
		and _cargo_phase(pair) == "elevated"
		and not _body_is_moving(pair)
		and _body_position(pair).distance_to(expected_position) <= 0.001,
		"%s leaves the interrupted body parked and cargo elevated" % label
	)
	check(
		_event_count(events, "scavenger_dislodged_cargo") == 0
		and _event_count(events, "cargo_staged_in_basin") == 0
		and _event_count(events, "scavenger_reached_lysate_source") == 0,
		"%s withholds every unearned downstream consequence" % label
	)


func _assert_in_flight(
		pair: Dictionary, expected_phase: String, expected_cargo: String, label: String
	) -> void:
	check(
		_phase(pair) == expected_phase
		and _cargo_phase(pair) == expected_cargo
		and _body_is_moving(pair),
		"%s preserves body movement, route phase, and cargo phase" % label
	)


func _assert_contact_restore(pair: Dictionary, label: String) -> void:
	var events := _milestone_events(pair)
	check(
		_phase(pair) == "retreating_to_lysate"
		and _cargo_phase(pair) == "falling"
		and _body_is_moving(pair)
		and _body_position(pair).distance_to(_route(pair)[1]) <= 0.001
		and _event_count(events, "scavenger_dislodged_cargo") == 1,
		"%s restores rack contact exactly and resumes retreat without duplication" % label
	)


func _assert_complete_once(pair: Dictionary, label: String) -> void:
	var events := _milestone_events(pair)
	var route := _route(pair)
	check(
		_phase(pair) == "clear"
		and _cargo_phase(pair) == "staged"
		and not _body_is_moving(pair)
		and _body_position(pair).distance_to(route[3]) <= 0.001,
		"%s parks the same body at lysate with cargo staged" % label
	)
	check(
		events == [
			"cargo_elevated_on_breakaway_rack",
			"scavenger_dislodged_cargo",
			"cargo_staged_in_basin",
			"scavenger_reached_lysate_source",
		],
		"%s records each causal milestone exactly once and in order" % label
	)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
