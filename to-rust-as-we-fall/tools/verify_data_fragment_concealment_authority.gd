extends SceneTree

## Generic data-authored cover is sampled gameplay truth. Render/headless presenter calls must not
## decide when a body becomes hidden, and a save made between samples must preserve both the sampled
## tier and the next absolute boundary on same-instance and fresh-instance restoration.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const DataChunkScript := preload("res://scripts/fragments/chunks/data_fragment_chunk.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const CAPBAGE_POS := Vector3(5.0, 0.5, 0.0)
const SCARPET_POS := Vector3(10.0, 0.5, 0.0)
const EXPOSED_POS := Vector3.ZERO
const EPSILON := 0.00001

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var pair := await _boot_pair()
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	var authority_key := str(chunk.call("_fragment_authority_key"))
	var initial_record: Dictionary = gs.get_world_state(authority_key, {})
	var first_boundary := float(initial_record.get("concealment_epoch", -1.0))

	check(int(initial_record.get("version", 0)) == chunk.DATA_FRAGMENT_AUTHORITY_VERSION
			and bool(initial_record.get("scheduled", false)) and first_boundary > 0.0,
		"cover-only fragment constructs a versioned saved simulation cadence without a render poll")
	check(_tier(gs, "aster") == GameState.CONCEAL_NONE,
		"the first cover sample has not been invented before its explicit boundary")

	gs.snap_character_to("aster", CAPBAGE_POS)
	chunk.call("_process", 99.0)
	chunk.call("headless_process", 99.0)
	check(_tier(gs, "aster") == GameState.CONCEAL_NONE,
		"render and headless presenter calls cannot grant Capbage concealment")
	_advance_to(host, first_boundary - EPSILON)
	check(_tier(gs, "aster") == GameState.CONCEAL_NONE,
		"Capbage entry remains pending immediately before the saved sample")
	host.scheduler.advance_ticks(EPSILON * 2.0)
	check(_tier(gs, "aster") == GameState.CONCEAL_FULL,
		"crossing the saved sample grants full concealment from the physical Capbage footprint")

	gs.snap_character_to("peris", SCARPET_POS)
	var second_boundary: float = first_boundary + float(chunk.CONCEALMENT_TICK)
	_advance_to(host, second_boundary + EPSILON)
	check(_tier(gs, "peris") == GameState.CONCEAL_MEDIUM,
		"the same cadence independently samples Scarpet medium concealment for another body")

	# Leave cover midway through the next interval. The capture intentionally contains an exposed
	# body and the prior sampled tier; this is the state that render-driven implementations tear.
	gs.snap_character_to("aster", EXPOSED_POS)
	var third_boundary: float = second_boundary + float(chunk.CONCEALMENT_TICK)
	_advance_to(host, third_boundary - chunk.CONCEALMENT_TICK * 0.45)
	var midway_capture := _capture(host)
	chunk.call("_process", 999.0)
	chunk.call("headless_process", 999.0)
	check(_tier(gs, "aster") == GameState.CONCEAL_FULL,
		"leaving cover cannot retract the saved sampled tier between fixed boundaries")
	_advance_to(host, third_boundary + EPSILON)
	check(_tier(gs, "aster") == GameState.CONCEAL_NONE,
		"the next fixed boundary retracts concealment exactly once")

	_apply_capture(host, chunk, midway_capture)
	check(_tier(gs, "aster") == GameState.CONCEAL_FULL
			and gs.get_position("aster").is_equal_approx(EXPOSED_POS),
		"same-instance rollback restores both the prior sample and its exposed physical cause")
	chunk.call("_process", 500.0)
	check(_tier(gs, "aster") == GameState.CONCEAL_FULL,
		"same-instance render polling cannot consume the restored interval")
	_advance_to(host, third_boundary + EPSILON)
	check(_tier(gs, "aster") == GameState.CONCEAL_NONE,
		"same-instance restore reattaches the original absolute sample boundary")

	var fresh := await _boot_pair()
	_apply_capture(fresh.host, fresh.chunk, midway_capture)
	check(_tier(fresh.host.game_state, "aster") == GameState.CONCEAL_FULL
			and fresh.host.game_state.get_position("aster").is_equal_approx(EXPOSED_POS),
		"fresh presenter preserves the same pending sampled truth")
	_advance_to(fresh.host, third_boundary - EPSILON)
	check(_tier(fresh.host.game_state, "aster") == GameState.CONCEAL_FULL,
		"fresh restore cannot retract before the saved absolute boundary")
	fresh.host.scheduler.advance_ticks(EPSILON * 2.0)
	check(_tier(fresh.host.game_state, "aster") == GameState.CONCEAL_NONE,
		"fresh restore reaches the same concealment consequence without a presenter call")

	# V3 is a supported live-save migration: it predates only the explicit cover clock. Preserve its
	# sampled tier and begin one new interval from the restored scheduler tick.
	var v3_capture := _json_round_trip(midway_capture)
	var world_state: Dictionary = v3_capture.game_state.get("world_state", {})
	var v3_record: Dictionary = world_state.get(authority_key, {})
	v3_record["version"] = 3
	v3_record.erase("concealment_epoch")
	world_state[authority_key] = v3_record
	v3_capture.game_state["world_state"] = world_state
	_apply_capture(host, chunk, v3_capture)
	var migrated_record: Dictionary = gs.get_world_state(authority_key, {})
	var migrated_boundary: float = float(migrated_record.get("concealment_epoch", -1.0))
	check(int(migrated_record.get("version", 0)) == chunk.DATA_FRAGMENT_AUTHORITY_VERSION
			and migrated_boundary > float(host.scheduler.get_current_tick()),
		"V3 authority migrates to one explicit future cover boundary")
	check(_tier(gs, "aster") == GameState.CONCEAL_FULL,
		"migration preserves the last sampled cover tier instead of recomputing at load time")
	_advance_to(host, migrated_boundary + EPSILON)
	check(_tier(gs, "aster") == GameState.CONCEAL_NONE,
		"migrated cadence samples the restored exposed body at its declared boundary")

	await _discard(host)
	await _discard(fresh.host)
	print("DATA FRAGMENT CONCEALMENT AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _boot_pair() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var fragment := Fragment.new()
	fragment.id = "authority_cover_cadence_fragment"
	fragment.party_ids = PackedStringArray(PARTY_IDS)
	fragment.spawns = {
		"aster": EXPOSED_POS,
		"peris": Vector3(0.0, 0.5, 2.5),
		"endo": Vector3(0.0, 0.5, -2.5),
	}
	fragment.objects = [
		{
			"type": "capbage",
			"name": "AuthorityCapbage",
			"pos": CAPBAGE_POS,
			"radius": 1.4,
		},
		{
			"type": "scarpet",
			"name": "AuthorityScarpet",
			"pos": SCARPET_POS,
			"radius": 1.65,
		},
	]
	host.register_party(fragment.spawns)
	var chunk = DataChunkScript.new()
	chunk.fragment = fragment
	chunk.attach_chunk_host(host, fragment.id)
	host.add_child(chunk)
	await process_frame
	await process_frame
	return {"host": host, "chunk": chunk}


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


func _advance_to(host, deadline: float) -> void:
	var now := float(host.scheduler.get_current_tick())
	if deadline > now:
		host.scheduler.advance_ticks(deadline - now)


func _tier(gs, char_id: String) -> int:
	return int(gs.get_character_concealment(char_id))


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
