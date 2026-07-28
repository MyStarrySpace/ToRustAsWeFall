extends SceneTree

## Focused regression for Showcase Room damage authority. The room used to own a second HP
## dictionary, render-integrate iron damage, and keep i-frame deadlines outside saves. These checks
## exercise the production snapshot seam without advancing a render frame.

const ShowcaseScene := preload("res://scenes/showcase/showcase.tscn")
const DEADLINE_EPSILON := 0.01

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_static_contract()
	await _verify_fixed_iron_cadence()
	await _verify_discrete_iframe_restore()
	await _verify_signal_boundary_transactions()
	await _verify_downed_signal_boundary()
	await _verify_coarse_fine_invariance()
	print("SHOWCASE ROOM SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_static_contract() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/showcase/showcase_room.gd")
	check("var _character_hp" not in source and "var _character_iframes" not in source,
		"Showcase Room has no scene-local HP or i-frame dictionary")
	check("_apply_iron_damage(delta" not in source
			and "IRON_DAMAGE_PER_SEC * delta" not in source,
		"iron damage is not integrated from render delta")
	var enemy_listener := _function_slice(source, "_on_enemy_hit", "_on_physics_collision")
	check("_apply_damage(" not in enemy_listener and "adjust_stat(" not in enemy_listener,
		"Enemy hit feedback cannot apply the Enemy kit's canonical strike a second time")
	check("DAMAGE_AUTHORITY_KEY" in source and "schedule_at(" in source
			and "on_game_state_snapshot_restored" in source,
		"Showcase damage declares a saved absolute scheduler authority and restore seam")


func _verify_fixed_iron_cadence() -> void:
	var room := await _spawn_room()
	var positions: Dictionary = room.get_station_positions()
	room.headless_set_character_position("aster", positions["iron_patch"])
	room.headless_set_character_position("peris", positions["iron_safe"])
	room.headless_set_character_position("endo", positions["iron_safe"])
	var damage_quantum: float = room.IRON_DAMAGE_PER_SEC * room.IRON_DAMAGE_INTERVAL
	var authority: Dictionary = room._damage_authority_record()
	var deadline: float = float(authority.get("next_iron_tick", -1.0))
	var start_tick: float = float(room._scheduler.get_current_tick())
	var hp_before: float = room._game_state.get_stat("aster", "hp")
	check(str(authority.get("phase", "")) == room.DAMAGE_PHASE_ACTIVE
			and deadline > start_tick,
		"fresh room publishes an active damage record with one absolute future iron tick")

	var absent_snapshot: Dictionary = _json_round_trip(room.build_save_snapshot())
	_erase_damage_authority(absent_snapshot, room.DAMAGE_AUTHORITY_KEY)
	room._scheduler.advance_ticks(maxf(0.0, deadline - start_tick) + 0.001)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"),
		hp_before - damage_quantum),
		"fixed iron cadence applies one canonical GameState quantum without a render frame")
	room.apply_save_snapshot(absent_snapshot)
	room.on_game_state_snapshot_restored()
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), hp_before)
			and room._game_state.get_world_state(room.DAMAGE_AUTHORITY_KEY, null) == null,
		"absence rollback retracts both discarded damage and its future authority")
	room._scheduler.advance_ticks(room.IRON_DAMAGE_INTERVAL * 2.1)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), hp_before),
		"absent authority cannot retain an iron callback")

	# Re-arm explicitly as a new scene-start commitment, then save between fixed ticks.
	room._start_damage_authority()
	authority = room._damage_authority_record()
	deadline = float(authority.get("next_iron_tick", -1.0))
	room._scheduler.advance_ticks(room.IRON_DAMAGE_INTERVAL * 0.4)
	var midpoint_snapshot: Dictionary = _json_round_trip(room.build_save_snapshot())
	var midpoint_tick: float = float(room._scheduler.get_current_tick())
	var midpoint_hp: float = room._game_state.get_stat("aster", "hp")
	var midpoint_deadline: float = _snapshot_damage_deadline(
		midpoint_snapshot, room.DAMAGE_AUTHORITY_KEY)
	check(midpoint_deadline > midpoint_tick,
		"midpoint snapshot preserves the exact remaining iron deadline")
	room._scheduler.advance_ticks(midpoint_deadline - midpoint_tick + 0.001)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"),
		midpoint_hp - damage_quantum),
		"discarded midpoint future reaches exactly one iron hit")
	room.apply_save_snapshot(midpoint_snapshot)
	room.on_game_state_snapshot_restored()
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), midpoint_hp),
		"same-presenter restore applies no damage")
	_advance_across_iron_deadline(
		room, midpoint_deadline, midpoint_hp, damage_quantum, "same-presenter")

	_end_room(room)
	var fresh := await _spawn_room()
	fresh.apply_save_snapshot(midpoint_snapshot)
	fresh.on_game_state_snapshot_restored()
	var expected_data_position := Vector3(
		(positions["iron_patch"] as Vector3).x,
		0.0,
		(positions["iron_patch"] as Vector3).z
	)
	check(fresh._game_state.get_position("aster").is_equal_approx(expected_data_position)
			and is_equal_approx(
				float(fresh._damage_authority_record().get("next_iron_tick", -1.0)),
				midpoint_deadline),
		"fresh presenter restores the hazard position and absolute cadence")
	_advance_across_iron_deadline(
		fresh, midpoint_deadline, midpoint_hp, damage_quantum, "fresh-presenter")
	_end_room(fresh)


func _verify_discrete_iframe_restore() -> void:
	var room := await _spawn_room()
	var safe_position: Vector3 = room.get_station_positions()["iron_safe"]
	room.headless_set_character_position("endo", safe_position)
	room.headless_set_character_hp("endo", room.DEFAULT_HP)
	var hp_before: float = room._game_state.get_stat("endo", "hp")
	check(room._apply_damage("endo", 12.0, "fixture impact"),
		"first discrete impact commits through canonical damage authority")
	check(not room._apply_damage("endo", 12.0, "fixture impact")
			and is_equal_approx(room._game_state.get_stat("endo", "hp"), hp_before - 12.0),
		"saved i-frame suppresses a duplicate impact at the same tick")
	var record: Dictionary = room._damage_authority_record()
	var iframe_deadline: float = float(
		(record.get("iframe_deadlines", {}) as Dictionary).get("endo", -1.0))
	room._scheduler.advance_ticks(room.DAMAGE_IFRAME * 0.35)
	var midpoint_snapshot: Dictionary = _json_round_trip(room.build_save_snapshot())
	var midpoint_hp: float = room._game_state.get_stat("endo", "hp")
	room._scheduler.advance_ticks(room.DAMAGE_IFRAME)
	check(room._apply_damage("endo", 12.0, "future impact"),
		"discarded future can spend the expired i-frame")
	room.apply_save_snapshot(midpoint_snapshot)
	room.on_game_state_snapshot_restored()
	check(is_equal_approx(room._game_state.get_stat("endo", "hp"), midpoint_hp)
			and not room._apply_damage("endo", 12.0, "blocked after restore"),
		"same-presenter rollback restores HP and the still-live i-frame")
	_advance_across_iframe(room, "endo", iframe_deadline, midpoint_hp, "same-presenter")

	_end_room(room)
	var fresh := await _spawn_room()
	fresh.apply_save_snapshot(midpoint_snapshot)
	fresh.on_game_state_snapshot_restored()
	check(not fresh._apply_damage("endo", 12.0, "fresh blocked"),
		"fresh presenter attaches to the same saved i-frame")
	_advance_across_iframe(fresh, "endo", iframe_deadline, midpoint_hp, "fresh-presenter")
	_end_room(fresh)


func _verify_signal_boundary_transactions() -> void:
	var room := await _spawn_room()
	room.headless_set_character_position("aster", room.get_station_positions()["iron_safe"])
	room.headless_set_character_hp("aster", room.DEFAULT_HP)
	var before_hp: float = room._game_state.get_stat("aster", "hp")
	var committed_capture := {}
	var applied_capture := {}
	room._game_state.world_state_changed.connect(func(key: String, value: Variant) -> void:
		if committed_capture.has("snapshot") or key != room.DAMAGE_AUTHORITY_KEY \
				or not value is Dictionary:
			return
		var record := value as Dictionary
		if str(record.get("phase", "")) == room.DAMAGE_PHASE_RESOLVING:
			committed_capture["snapshot"] = _json_round_trip(room.build_save_snapshot())
	)
	room._game_state.stat_changed.connect(func(char_id: String, stat: String, _value: float) -> void:
		if applied_capture.has("snapshot") or char_id != "aster" or stat != "hp":
			return
		var record: Dictionary = room._damage_authority_record()
		if str(record.get("phase", "")) == room.DAMAGE_PHASE_RESOLVING:
			applied_capture["snapshot"] = _json_round_trip(room.build_save_snapshot())
	)
	check(room._apply_damage("aster", 17.0, "transaction seam"),
		"fixture impact completes its committed transaction")
	check(committed_capture.has("snapshot") and applied_capture.has("snapshot"),
		"saves can observe both pre-effect and post-stat signal seams")
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), before_hp - 17.0),
		"uninterrupted transaction applies one exact absolute HP result")

	var pre_effect_snapshot: Dictionary = committed_capture.get("snapshot", {})
	room.apply_save_snapshot(pre_effect_snapshot)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), before_hp),
		"loading a committed pre-effect seam does not apply damage during restoration")
	room._scheduler.advance_ticks(0.001)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), before_hp - 17.0)
			and str(room._damage_authority_record().get("phase", ""))
				== room.DAMAGE_PHASE_ACTIVE,
		"committed pre-effect seam resolves once on the scheduler lane")
	room._scheduler.advance_ticks(0.001)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), before_hp - 17.0),
		"resolved pre-effect seam cannot duplicate its consequence")

	_end_room(room)
	var fresh := await _spawn_room()
	var post_stat_snapshot: Dictionary = applied_capture.get("snapshot", {})
	fresh.apply_save_snapshot(post_stat_snapshot)
	var saved_hp: float = fresh._game_state.get_stat("aster", "hp")
	fresh._scheduler.advance_ticks(0.001)
	check(is_equal_approx(saved_hp, before_hp - 17.0)
			and is_equal_approx(fresh._game_state.get_stat("aster", "hp"), saved_hp),
		"fresh presenter finalizes a post-stat signal save without double damage")
	_end_room(fresh)


func _verify_downed_signal_boundary() -> void:
	var room := await _spawn_room()
	room.headless_set_character_position("peris", room.get_station_positions()["iron_safe"])
	room.headless_set_character_hp("peris", 5.0)
	var signal_capture := {}
	room._game_state.stat_changed.connect(func(char_id: String, stat: String, value: float) -> void:
		if signal_capture.has("snapshot") or char_id != "peris" or stat != "hp" \
				or value > 0.0:
			return
		var record: Dictionary = room._damage_authority_record()
		if str(record.get("phase", "")) == room.DAMAGE_PHASE_RESOLVING:
			signal_capture["snapshot"] = _json_round_trip(room.build_save_snapshot())
	)
	check(room._apply_damage("peris", 10.0, "downing seam")
			and room._game_state.is_downed("peris"),
		"lethal showcase damage reaches canonical GameState downed state")
	check(signal_capture.has("snapshot"),
		"lethal stat signal exposes the midpoint before the derived down transition")
	_end_room(room)

	var fresh := await _spawn_room()
	fresh.apply_save_snapshot(signal_capture.get("snapshot", {}))
	check(not fresh._game_state.is_downed("peris")
			and is_zero_approx(fresh._game_state.get_stat("peris", "hp")),
		"fresh restore preserves the exact pre-down signal seam without inventing an endpoint")
	fresh._scheduler.advance_ticks(0.001)
	check(fresh._game_state.is_downed("peris")
			and is_zero_approx(fresh._game_state.get_stat("peris", "hp")),
		"scheduled transaction reconciliation closes the 0-HP loading exploit")
	_end_room(fresh)


func _verify_coarse_fine_invariance() -> void:
	var fine := await _spawn_room()
	var coarse := await _spawn_room()
	var fine_patch: Vector3 = fine.get_station_positions()["iron_patch"]
	var coarse_patch: Vector3 = coarse.get_station_positions()["iron_patch"]
	fine.headless_set_character_position("aster", fine_patch)
	coarse.headless_set_character_position("aster", coarse_patch)
	for _step in range(99):
		fine._scheduler.advance_ticks(0.01)
	coarse._scheduler.advance_ticks(0.99)
	var fine_hp: float = fine._game_state.get_stat("aster", "hp")
	var coarse_hp: float = coarse._game_state.get_stat("aster", "hp")
	check(is_equal_approx(fine_hp, coarse_hp),
		"fine and coarse scheduler advances produce identical iron HP")
	check(is_equal_approx(
			float(fine._damage_authority_record().get("next_iron_tick", -1.0)),
			float(coarse._damage_authority_record().get("next_iron_tick", -1.0))),
		"fine and coarse advances preserve the same next absolute cadence")
	_end_room(fine)
	_end_room(coarse)


func _advance_across_iron_deadline(
		room: Node,
		deadline: float,
		starting_hp: float,
		damage_quantum: float,
		label: String
	) -> void:
	var remaining := deadline - float(room._scheduler.get_current_tick())
	room._scheduler.advance_ticks(maxf(0.0, remaining - DEADLINE_EPSILON))
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"), starting_hp),
		"%s iron cannot hit before the saved deadline" % label)
	room._scheduler.advance_ticks(DEADLINE_EPSILON + 0.001)
	check(is_equal_approx(room._game_state.get_stat("aster", "hp"),
		starting_hp - damage_quantum),
		"%s iron applies exactly one quantum at the saved deadline" % label)


func _advance_across_iframe(
		room: Node,
		char_id: String,
		deadline: float,
		starting_hp: float,
		label: String
	) -> void:
	var remaining := deadline - float(room._scheduler.get_current_tick())
	room._scheduler.advance_ticks(maxf(0.0, remaining - DEADLINE_EPSILON))
	check(not room._apply_damage(char_id, 12.0, "%s early" % label)
			and is_equal_approx(room._game_state.get_stat(char_id, "hp"), starting_hp),
		"%s impact stays blocked immediately before the saved i-frame deadline" % label)
	room._scheduler.advance_ticks(DEADLINE_EPSILON + 0.001)
	check(room._apply_damage(char_id, 12.0, "%s due" % label)
			and is_equal_approx(room._game_state.get_stat(char_id, "hp"), starting_hp - 12.0),
		"%s impact becomes legal exactly after the saved i-frame deadline" % label)


func _spawn_room() -> Node:
	var room := ShowcaseScene.instantiate()
	room.suppress_scene_change = true
	root.add_child(room)
	# The focused verifier advances only EventScheduler. Disable the rendered sequence loop so wall
	# frames cannot become an accidental second clock while other presenters finish one setup frame.
	room.set_process(false)
	await process_frame
	return room


func _end_room(room: Node) -> void:
	if room.has_method("_teardown_sequence"):
		room._teardown_sequence()
	room.free()


func _erase_damage_authority(snapshot: Dictionary, key: String) -> void:
	var game_state_data: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state_data.get("world_state", {})
	world_state.erase(key)
	game_state_data["world_state"] = world_state
	snapshot["game_state"] = game_state_data


func _snapshot_damage_deadline(snapshot: Dictionary, key: String) -> float:
	var game_state_data: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state_data.get("world_state", {})
	var record_v: Variant = world_state.get(key, {})
	if not record_v is Dictionary:
		return -1.0
	return float((record_v as Dictionary).get("next_iron_tick", -1.0))


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _function_slice(source: String, start_name: String, end_name: String) -> String:
	var start := source.find("func %s" % start_name)
	var finish := source.find("func %s" % end_name, start + 1)
	if start < 0:
		return ""
	return source.substr(start, finish - start if finish > start else source.length() - start)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
