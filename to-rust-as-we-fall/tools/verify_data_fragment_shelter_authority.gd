extends SceneTree

## Regression for the generic data-fragment exit. A shelter is a full-party, physical, canonical
## GameState rest transaction—not a one-activator checklist bit. The checks cover retryable rejection,
## atomic ATP preflight, real rest authority, same/fresh restore, and authority absence rollback.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const DataChunkScript := preload("res://scripts/fragments/chunks/data_fragment_chunk.gd")

const PARTY_IDS := ["aster", "peris", "endo"]
const EXIT_POS := Vector3(10.0, 0.5, 0.0)

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var pair := await _boot_pair()
	var host = pair.host
	var chunk = pair.chunk
	var shelter = pair.shelter
	var gs = host.game_state
	var authority_key := str(chunk.call("_fragment_authority_key"))
	var rest_signals := {"count": 0}
	gs.rest_started.connect(func(_char_id: String) -> void: rest_signals["count"] += 1)

	for char_id in PARTY_IDS:
		gs.set_stat(char_id, "hp", 80.0)
		gs.set_stat(char_id, "atp", 2.0)
	shelter.set("active_character", "aster")
	check(not bool(shelter.call("_trigger", false)),
		"remote selected portrait cannot spend the exact exit-shelter source")
	gs.snap_character_to("aster", EXIT_POS)
	check(bool(shelter.call("_trigger", false)),
		"one character can inspect the shelter without completing it")
	check(str(chunk.get("_phase")) == "ready"
			and bool(shelter.call("is_interaction_enabled"))
			and not bool(shelter.get("_used")),
		"partial-party rejection leaves the shelter retryable")
	check(_all_atp(gs, 2.0) and _resting_count(gs) == 0,
		"position rejection charges no ATP and starts no partial rest")

	for char_id in PARTY_IDS:
		gs.snap_character_to(char_id, EXIT_POS)
	gs.down_character("peris")
	shelter.set("active_character", "aster")
	check(bool(shelter.call("_trigger", false))
			and str(chunk.get("_phase")) == "ready",
		"exact shelter source accepts its ready activator while a downed party member blocks completion")
	check(_all_atp(gs, 2.0) and _resting_count(gs) == 0,
		"conscious-party rejection is side-effect free")
	gs.restore_character("peris")
	gs.snap_character_to("peris", EXIT_POS)
	gs.set_stat("peris", "hp", 80.0)
	check(not bool(chunk.call("_on_exit_shelter_rested", shelter)),
		"direct shelter callback cannot substitute for a new physical source receipt")
	shelter.emit_signal("interacted")
	check(str(chunk.get("_phase")) == "ready" and _all_atp(gs, 2.0),
		"manually emitted shelter signal cannot manufacture canonical party rest")

	gs.set_stat("endo", "atp", 0.0)
	shelter.set("active_character", "aster")
	check(bool(shelter.call("_trigger", false)) and str(chunk.get("_phase")) == "ready",
		"exact shelter attempt rejects atomically when a later member cannot pay")
	check(is_equal_approx(gs.get_stat("aster", "atp"), 2.0)
			and is_equal_approx(gs.get_stat("peris", "atp"), 2.0)
			and _resting_count(gs) == 0,
		"ATP preflight prevents early members being charged before later rejection")
	check(bool(shelter.call("is_interaction_enabled")) and not bool(shelter.get("_used")),
		"failed ATP attempt remains immediately retryable")

	gs.set_stat("endo", "atp", 2.0)
	var ready_capture := _capture(host)
	var accepted_box := {"snapshot": {}}
	var accepted_probe := func(source_id: String, _actor: String) -> void:
		if source_id == str(shelter.get("data_id")):
			accepted_box["snapshot"] = _capture(host)
	gs.interactable_triggered.connect(accepted_probe, CONNECT_ONE_SHOT)
	var signal_box := {"snapshot": {}}
	var stat_probe := func(_char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _capture(host)
	gs.stat_changed.connect(stat_probe)
	shelter.set("active_character", "aster")
	check(bool(shelter.call("_trigger", false)),
		"full conscious party starts canonical shelter rest")
	gs.stat_changed.disconnect(stat_probe)
	var signal_capture: Dictionary = signal_box.get("snapshot", {})
	var signal_record: Dictionary = (
		signal_capture.get("game_state", {}).get("world_state", {}).get(
			authority_key, {}) as Dictionary)
	check(not signal_capture.is_empty()
			and str(signal_record.get("phase", "")) == "committing"
			and str(signal_record.get("exit_rest_phase", "")) == "committing"
			and _all_atp(gs, 1.0) and _resting_count(gs) == 3,
		"first ATP signal sees COMMITTING owner truth after the whole batch is installed")
	check(str(chunk.get("_phase")) == "complete" and rest_signals["count"] == 3,
		"completion occurs only after all three real rest commands are accepted")
	check(_all_atp(gs, 1.0) and _resting_count(gs) == 3,
		"canonical rest charges exactly one ATP and owns timed recovery for every member")
	check(not bool(shelter.call("is_interaction_enabled")) and bool(shelter.get("_used")),
		"completed chunk authority spends and disables the shelter presenter")
	var completed_record: Dictionary = gs.get_world_state(authority_key, {})
	check(str(completed_record.get("phase", "")) == "complete",
		"completed shelter publishes chunk authority immediately")
	var completed_capture := _capture(host)
	var accepted_capture: Dictionary = accepted_box.get("snapshot", {})
	var accepted_record: Dictionary = accepted_capture.get(
		"game_state", {}).get("world_state", {}).get(authority_key, {})
	check(not accepted_capture.is_empty()
			and str(accepted_record.get("exit_rest_phase", "")) == "ready"
			and int((accepted_record.get(
				"exit_rest_trigger_consumed", {}) as Dictionary).get(
					str(shelter.get("data_id")), -1)) == 3,
		"accepted-before-owner shelter save contains no free rest consequence")

	var rest_events_before_signal_restore := _party_rest_event_count(gs)
	var rest_signals_before_signal_restore := int(rest_signals["count"])
	_apply_capture(host, chunk, signal_capture)
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.get("_phase")) == "complete"
			and str(chunk.get("_exit_rest_phase")) == "rested"
			and _all_atp(gs, 1.0) and _resting_count(gs) == 3
			and _party_rest_event_count(gs) == rest_events_before_signal_restore
			and int(rest_signals["count"]) == rest_signals_before_signal_restore,
		"same-instance signal-time restore reconciles without a second rest command or payment")

	var fresh_signal := await _boot_pair()
	var fresh_signal_events := _party_rest_event_count(fresh_signal.host.game_state)
	_apply_capture(fresh_signal.host, fresh_signal.chunk, signal_capture)
	fresh_signal.host.scheduler.advance_ticks(0.001)
	check(str(fresh_signal.chunk.get("_phase")) == "complete"
			and str(fresh_signal.chunk.get("_exit_rest_phase")) == "rested"
			and _all_atp(fresh_signal.host.game_state, 1.0)
			and _resting_count(fresh_signal.host.game_state) == 3
			and _party_rest_event_count(fresh_signal.host.game_state) == fresh_signal_events,
		"fresh signal-time restore reaches the same completed batch without replay")

	_apply_capture(host, chunk, ready_capture)
	check(str(chunk.get("_phase")) == "ready" and _all_atp(gs, 2.0)
			and _resting_count(gs) == 0,
		"same-instance rollback retracts completion, ATP cost, and active rests together")
	check(bool(shelter.call("is_interaction_enabled")) and not bool(shelter.get("_used")),
		"same-instance rollback re-arms the shelter from chunk authority")

	var signal_count_before_restore := int(rest_signals["count"])
	_apply_capture(host, chunk, completed_capture)
	_apply_capture(host, chunk, completed_capture)
	# Production restoration subsequently visits the Interactable child. The owner projection must
	# survive that generic hook rather than reverting `_used` from its non-one-shot trigger record.
	shelter.call("on_game_state_snapshot_restored")
	check(_all_atp(gs, 1.0) and _resting_count(gs) == 3
			and int(rest_signals["count"]) == signal_count_before_restore,
		"idempotent completed restore neither repays nor recharges ATP and emits no rest signal")
	check(not bool(shelter.call("is_interaction_enabled")) and bool(shelter.get("_used")),
		"generic Interactable restore preserves owner-derived completed state")

	_apply_capture(host, chunk, accepted_capture)
	_apply_capture(host, chunk, accepted_capture)
	var reconciled_record: Dictionary = gs.get_world_state(authority_key, {})
	check(str(chunk.get("_phase")) == "ready" and _all_atp(gs, 2.0)
			and _resting_count(gs) == 0
			and bool(shelter.call("is_interaction_enabled"))
			and int((reconciled_record.get(
				"exit_rest_trigger_consumed", {}) as Dictionary).get(
					str(shelter.get("data_id")), -1)) == 4,
		"same presenter retracts accepted pre-owner shelter edge and consumes only its receipt")

	var fresh := await _boot_pair()
	_apply_capture(fresh.host, fresh.chunk, completed_capture)
	fresh.shelter.call("on_game_state_snapshot_restored")
	check(str(fresh.chunk.get("_phase")) == "complete"
			and _all_atp(fresh.host.game_state, 1.0)
			and _resting_count(fresh.host.game_state) == 3,
		"fresh presenter reconstructs completed canonical party rest")
	check(not bool(fresh.shelter.call("is_interaction_enabled"))
			and bool(fresh.shelter.get("_used")),
		"fresh shelter control derives disabled/spent state from saved chunk authority")

	var fresh_accepted := await _boot_pair()
	_apply_capture(fresh_accepted.host, fresh_accepted.chunk, accepted_capture)
	_apply_capture(fresh_accepted.host, fresh_accepted.chunk, accepted_capture)
	check(str(fresh_accepted.chunk.get("_phase")) == "ready"
			and _all_atp(fresh_accepted.host.game_state, 2.0)
			and bool(fresh_accepted.shelter.call("is_interaction_enabled")),
		"fresh presenter retracts accepted pre-owner shelter edge without payment or completion")

	var absent := ready_capture.duplicate(true)
	(absent.get("game_state", {}).get("world_state", {}) as Dictionary).erase(authority_key)
	_apply_capture(host, chunk, completed_capture)
	_apply_capture(host, chunk, absent)
	check(str(chunk.get("_phase")) == "ready" and _all_atp(gs, 2.0)
			and _resting_count(gs) == 0,
		"authority absence retracts a discarded completed party rest")
	check(bool(shelter.call("is_interaction_enabled")) and not bool(shelter.get("_used")),
		"authority absence restores the retryable shelter baseline")

	var fresh_absent := await _boot_pair()
	_apply_capture(fresh_absent.host, fresh_absent.chunk, absent)
	check(str(fresh_absent.chunk.get("_phase")) == "ready"
			and bool(fresh_absent.shelter.call("is_interaction_enabled"))
			and not bool(fresh_absent.shelter.get("_used")),
		"fresh presenter treats missing chunk authority as pre-completion truth")

	await _discard(host)
	await _discard(fresh.host)
	await _discard(fresh_absent.host)
	await _discard(fresh_signal.host)
	await _discard(fresh_accepted.host)
	print("DATA FRAGMENT SHELTER AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _boot_pair() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var fragment := Fragment.new()
	fragment.id = "authority_party_shelter_fragment"
	fragment.party_ids = PackedStringArray(PARTY_IDS)
	fragment.spawns = {
		"aster": Vector3.ZERO,
		"peris": Vector3(0.0, 0.5, 2.5),
		"endo": Vector3(0.0, 0.5, -2.5),
	}
	fragment.objects = [{
		"type": "exit_shelter",
		"name": "AuthorityExitShelter",
		"pos": EXIT_POS,
		"radius": 1.6,
		"label": "AUTHORITY EXIT",
	}]
	host.register_party(fragment.spawns)
	var chunk = DataChunkScript.new()
	chunk.fragment = fragment
	chunk.attach_chunk_host(host, fragment.id)
	host.add_child(chunk)
	await process_frame
	await process_frame
	chunk.call("reset_preview_state")
	var shelters: Array = chunk.get("_exit_shelters")
	check(shelters.size() == 1, "fixture builds one generic exit shelter")
	return {"host": host, "chunk": chunk, "shelter": shelters[0]}


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


func _all_atp(gs, expected: float) -> bool:
	for char_id in PARTY_IDS:
		if not is_equal_approx(gs.get_stat(char_id, "atp"), expected):
			return false
	return true


func _resting_count(gs) -> int:
	var count := 0
	for char_id in PARTY_IDS:
		if gs.is_resting(char_id):
			count += 1
	return count


func _party_rest_event_count(gs) -> int:
	var count := 0
	if gs == null or gs.event_log == null:
		return count
	for event_v in gs.event_log.events:
		var event: Dictionary = event_v
		if str(event.get("kind", "")) == str(GameEvent.KIND_PARTY_REST):
			count += 1
	return count


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
