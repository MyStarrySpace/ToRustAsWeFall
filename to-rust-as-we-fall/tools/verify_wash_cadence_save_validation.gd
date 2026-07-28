extends SceneTree

## Focused malformed-save regression for Wash Relay's version-7 cadence record.
##
## Version 7 must reject typed/count/cadence contradictions before any saved value reaches the
## presenter, then restart from one clean authoritative cadence. Version 6 remains migratable.

const RelayScene := preload("res://scenes/fragments/chunks/wash_relay_chunk.tscn")
const PARTY: Array[String] = ["aster", "peris", "endo"]

var _checks := 0
var _failures := 0


class RelayHost extends Node:
	var game_state := GameState.new()
	var scheduler := EventScheduler.new()
	var active_character := "aster"
	var party: Array[String] = PARTY.duplicate()

	func configure(spawns: Dictionary) -> void:
		game_state.scheduler = scheduler
		game_state.set_party(party)
		for char_id in party:
			game_state.register_character(
				char_id,
				spawns.get(char_id, Vector3.ZERO),
				3.0,
				{
					"hp": 100.0,
					"max_hp": 100.0,
					"stamina": 100.0,
					"max_stamina": 100.0,
					"atp": 3.0,
				}
			)

	func get_preview_game_state():
		return game_state

	func get_preview_scheduler():
		return scheduler

	func get_preview_scheduler_tick() -> float:
		return scheduler.get_current_tick()

	func get_preview_character_position(char_id: String) -> Vector3:
		return game_state.get_position(char_id)

	func set_preview_character_position(char_id: String, value: Vector3) -> void:
		game_state.snap_character_to(char_id, value)

	func get_preview_character_move_speed(_char_id: String, _running := false) -> float:
		return 3.0

	func get_preview_active_character() -> String:
		return active_character

	func get_preview_selected_characters() -> Array:
		return party.duplicate()

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(
			char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)

	func set_preview_step(_step: String) -> void:
		pass

	func register_preview_interactable(_interactable: Node) -> void:
		pass

	func get_preview_dialogue_box():
		return null

	func get_preview_engram_overlay():
		return null

	func show_preview_note(_text: String, _duration := 3.0) -> void:
		pass

	func show_preview_message(_text: String, _duration := 2.0) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var pair := await _boot()
	var host: RelayHost = pair.host
	var chunk: Node = pair.chunk
	var dry_capture := _capture(host)
	var dry_record := _wash_record(host, chunk)
	check(bool(chunk.call(
			"_valid_v7_wash_cadence",
			dry_record,
			host.scheduler.get_current_tick()
		)),
		"a live dry version-7 cadence record validates")

	var bad := dry_record.duplicate(true)
	bad["cadence_t0"] = NAN
	_assert_rejected(host, chunk, dry_capture, bad,
		"NaN cadence anchor")

	bad = dry_record.duplicate(true)
	bad["cadence_t0"] = INF
	_assert_rejected(host, chunk, dry_capture, bad,
		"infinite cadence anchor")

	bad = dry_record.duplicate(true)
	(bad["flood_counts"] as Array)[0] = -1
	_assert_rejected(host, chunk, dry_capture, bad,
		"negative section flood count")

	bad = dry_record.duplicate(true)
	(bad["flood_counts"] as Array)[0] = NAN
	_assert_rejected(host, chunk, dry_capture, bad,
		"NaN section flood count")

	bad = dry_record.duplicate(true)
	(bad["section_wash_counts"] as Array)[0] = 0.5
	_assert_rejected(host, chunk, dry_capture, bad,
		"non-integral section wash count")

	bad = dry_record.duplicate(true)
	bad["drain_flood_count"] = INF
	_assert_rejected(host, chunk, dry_capture, bad,
		"infinite drain flood count")

	bad = dry_record.duplicate(true)
	bad["drain_flood_count"] = 0.5
	_assert_rejected(host, chunk, dry_capture, bad,
		"non-integral drain flood count")

	bad = dry_record.duplicate(true)
	(bad["section_flood_until"] as Array)[0] = -2.0
	_assert_rejected(host, chunk, dry_capture, bad,
		"negative non-sentinel section deadline")

	bad = dry_record.duplicate(true)
	(bad["flood_counts"] as Array)[0] = 1
	_assert_rejected(host, chunk, dry_capture, bad,
		"section count advanced before its cadence beat")

	bad = dry_record.duplicate(true)
	bad["drain_flood_count"] = 1
	_assert_rejected(host, chunk, dry_capture, bad,
		"drain count advanced before its cadence beat")

	bad = dry_record.duplicate(true)
	(bad["section_flood_until"] as Array)[0] = 1.0
	_assert_rejected(host, chunk, dry_capture, bad,
		"dry section carrying a live deadline")

	bad = dry_record.duplicate(true)
	bad["drain_flooding"] = true
	bad["drain_flood_until"] = -1.0
	_assert_rejected(host, chunk, dry_capture, bad,
		"flooding drain without an off deadline")

	bad = dry_record.duplicate(true)
	bad["spatial_authority_epoch"] = host.scheduler.get_current_tick() + 1.0
	_assert_rejected(host, chunk, dry_capture, bad,
		"future spatial cadence epoch")

	bad = dry_record.duplicate(true)
	bad["next_spatial_authority_tick"] = float(
		bad.get("next_spatial_authority_tick", 0.0)
	) + float(chunk.SPATIAL_AUTHORITY_INTERVAL) * 0.37
	_assert_rejected(host, chunk, dry_capture, bad,
		"off-grid spatial cadence boundary")

	bad = dry_record.duplicate(true)
	bad["next_spatial_authority_tick"] = host.scheduler.get_current_tick() \
			+ float(chunk.SPATIAL_AUTHORITY_INTERVAL) * 3.0
	_assert_rejected(host, chunk, dry_capture, bad,
		"postponed spatial cadence boundary")

	_apply_capture(host, chunk, dry_capture)
	var first_onset_in := float(chunk.call("_section_next_onset_in", 0))
	check(first_onset_in > 0.0,
		"fixture finds the first real section cadence beat")
	host.scheduler.advance_ticks(first_onset_in + 0.37)
	var wet_capture := _capture(host)
	var wet_record := _wash_record(host, chunk)
	check(bool((wet_record.get("flooding", []) as Array)[0])
			and bool(chunk.call(
				"_valid_v7_wash_cadence",
				wet_record,
				host.scheduler.get_current_tick()
			)),
		"a scheduler-produced wet midpoint validates")

	bad = wet_record.duplicate(true)
	(bad["section_flood_until"] as Array)[0] = INF
	_assert_rejected(host, chunk, wet_capture, bad,
		"infinite wet-section deadline")

	bad = wet_record.duplicate(true)
	(bad["section_flood_until"] as Array)[0] = \
			float((bad["section_flood_until"] as Array)[0]) + 0.25
	_assert_rejected(host, chunk, wet_capture, bad,
		"wet deadline misaligned from its count and cadence")

	bad = wet_record.duplicate(true)
	(bad["section_flood_until"] as Array)[0] = -1.0
	_assert_rejected(host, chunk, wet_capture, bad,
		"flooding section without an off deadline")

	bad = wet_record.duplicate(true)
	(bad["flooding"] as Array)[0] = false
	_assert_rejected(host, chunk, wet_capture, bad,
		"dry section retaining a wet off deadline")

	_verify_legacy_v6_migration(host, chunk, wet_capture, wet_record)
	_verify_completion_normalizes_deadlines(host, chunk, wet_capture)

	await _discard(host)
	print("WASH CADENCE SAVE VALIDATION: %d checks, %d failures" % [
		_checks, _failures
	])
	quit(0 if _failures == 0 else 1)


func _assert_rejected(
		host: RelayHost,
		chunk: Node,
		capture: Dictionary,
		tampered: Dictionary,
		label: String
	) -> void:
	_apply_capture(host, chunk, capture)
	var now := float(host.scheduler.get_current_tick())
	check(not bool(chunk.call("_valid_v7_wash_cadence", tampered, now)),
		"%s is rejected by the coherent-record validator" % label)
	host.game_state.world_state[chunk.WASH_AUTHORITY_KEY] = tampered.duplicate(true)
	_notify_snapshot_restored(chunk)
	check(_is_clean_rebootstrap(host, chunk),
		"%s fails closed to one clean cadence" % label)


func _verify_legacy_v6_migration(
		host: RelayHost,
		chunk: Node,
		wet_capture: Dictionary,
		wet_record: Dictionary
	) -> void:
	_apply_capture(host, chunk, wet_capture)
	var legacy := wet_record.duplicate(true)
	legacy["version"] = 6
	legacy.erase("control_committed_counts")
	host.game_state.world_state[chunk.WASH_AUTHORITY_KEY] = legacy
	_notify_snapshot_restored(chunk)
	var migrated := _wash_record(host, chunk)
	check(bool((chunk.get("_flooding") as Array)[0])
			and int((chunk.get("_flood_counts") as Array)[0]) == 1,
		"legacy version 6 preserves its earned wet midpoint")
	check(int(migrated.get("version", 0)) == int(chunk.WASH_AUTHORITY_VERSION)
			and bool(chunk.call(
				"_valid_v7_wash_cadence",
				migrated,
				host.scheduler.get_current_tick()
			)),
		"accepted version 6 migrates forward to a valid version-7 record")


func _verify_completion_normalizes_deadlines(
		host: RelayHost,
		chunk: Node,
		wet_capture: Dictionary
	) -> void:
	_apply_capture(host, chunk, wet_capture)
	chunk.call("_complete_wash_relay")
	var complete := _wash_record(host, chunk)
	var all_dry := not bool(complete.get("drain_flooding", true)) \
			and float(complete.get("drain_flood_until", 0.0)) == -1.0
	for value in (complete.get("flooding", []) as Array):
		all_dry = all_dry and not bool(value)
	for value in (complete.get("section_flood_until", []) as Array):
		all_dry = all_dry and float(value) == -1.0
	check(all_dry,
		"completion quiescence clears every flooding flag and off deadline together")
	check(bool(chunk.call(
			"_valid_v7_wash_cadence",
			complete,
			host.scheduler.get_current_tick()
			)),
		"the normalized complete record satisfies the strict version-7 contract")


func _is_clean_rebootstrap(host: RelayHost, chunk: Node) -> bool:
	var record := _wash_record(host, chunk)
	if int(record.get("version", 0)) != int(chunk.WASH_AUTHORITY_VERSION) \
			or str(record.get("phase", "")) != "active" \
			or not bool(record.get("scheduled", false)) \
			or not is_finite(float(record.get("cadence_t0", NAN))) \
			or not bool(chunk.call(
				"_valid_v7_wash_cadence",
				record,
				host.scheduler.get_current_tick()
			)):
		return false
	for count in (record.get("flood_counts", []) as Array):
		if int(count) != 0:
			return false
	for count in (record.get("section_wash_counts", []) as Array):
		if int(count) != 0:
			return false
	for flooding in (record.get("flooding", []) as Array):
		if bool(flooding):
			return false
	for deadline in (record.get("section_flood_until", []) as Array):
		if float(deadline) != -1.0:
			return false
	return int(record.get("drain_flood_count", -1)) == 0 \
			and not bool(record.get("drain_flooding", true)) \
			and float(record.get("drain_flood_until", 0.0)) == -1.0


func _boot() -> Dictionary:
	var resource = load("res://data/fragments/wash_relay.tres")
	var host := RelayHost.new()
	host.configure(resource.spawns)
	root.add_child(host)
	var chunk: Node = RelayScene.instantiate()
	chunk.call("attach_chunk_host", host, "wash_relay")
	chunk.set_process(false)
	host.add_child(chunk)
	await process_frame
	host.game_state.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	chunk.call("reset_preview_state")
	chunk.set_process(false)
	return {"host": host, "chunk": chunk}


func _wash_record(host: RelayHost, chunk: Node) -> Dictionary:
	var raw: Variant = host.game_state.get_world_state(
		chunk.WASH_AUTHORITY_KEY, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func _capture(host: RelayHost) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(
		host: RelayHost, chunk: Node, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)


func _notify_snapshot_restored(node: Node) -> void:
	if node.has_method("on_game_state_snapshot_restored"):
		node.call("on_game_state_snapshot_restored")
	for child in node.get_children():
		_notify_snapshot_restored(child)


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
