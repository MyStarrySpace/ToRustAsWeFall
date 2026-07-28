extends SceneTree

## Snapshot/rollback regression for the generated PuzzleAtom's chunk-owned state. The atom's
## enemies and interactions have their own GameState authority; this tool covers the causal phase
## the chunk itself owns: lure deadlines, clear/failure bookkeeping, completion, and win cadence.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const AtomScene := preload("res://scenes/fragments/chunks/puzzle_atom_chunk.tscn")

const TEST_STAGES := ["distract:lure"]
const TEST_SEED := 7

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var outbound_case: Dictionary = await _verify_same_instance_lure_and_completion_rollback()
	await _verify_fresh_presenter_lure(
		outbound_case.get("capture", {}),
		float(outbound_case.get("capture_tick", -1.0)),
		float(outbound_case.get("activation_deadline", -1.0)),
		float(outbound_case.get("ready_deadline", -1.0)))
	await _verify_party_checkpoint_and_canonical_shelter()
	await _verify_clear_and_failure_flags()
	await _verify_fixed_win_poll_cadence()
	await _verify_missing_record_retraction()
	print("PUZZLE ATOM SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_same_instance_lure_and_completion_rollback() -> Dictionary:
	var pair := await _boot_atom()
	var host = pair.host
	var chunk = pair.chunk
	check(_trigger_atom_flure(host, chunk, 0),
		"same-instance exact physical source commits its lure")
	var physical_flure := (chunk._stages[0] as Dictionary).get("flure", null) as Flure
	var physical_effect := physical_flure.get_effect_state()
	var activation_tick := float(physical_effect.get("start_tick", -1.0))
	var activation_deadline := float(physical_effect.get("end_tick", -1.0))
	# The authored lesson is source -> retreat -> crossing. Preserve that actual intervention in
	# the save fixture: leaving Peris parked on the flower would truthfully let the arriving watcher
	# reacquire her at point-blank range and test a failed play, not an in-flight restore.
	var stage_live := chunk._stages[0] as Dictionary
	host.game_state.snap_character_to("peris", stage_live.get("conceal_world", Vector3.ZERO))
	# Save while the watcher is physically travelling.  The old proximity shortcut
	# could never represent this phase: GAP CLEAR was merely inferred from a radius.
	host.scheduler.advance_ticks(0.25)
	var outbound_state: Dictionary = chunk.get_preview_state()
	var outbound_stage: Dictionary = (outbound_state.get("stages", []) as Array)[0]
	check(bool(outbound_stage.get("luring_outbound", false))
			and not bool(outbound_stage.get("lure_ready", true)),
		"midpoint is a real in-progress watcher transit, not an early ready flag")
	var midpoint := _capture(host)
	var authority_key := str(chunk._atom_runtime_authority_key())
	var record: Dictionary = host.game_state.get_world_state(authority_key, {})
	var stage_record: Dictionary = (record.get("stages", []) as Array)[0]
	check(str(record.get("phase", "")) == "active"
			and bool(stage_record.get("luring_outbound", false))
			and is_equal_approx(
				float(stage_record.get("lure_until", -1.0)), activation_deadline),
		"mid-transit snapshot stores its phase, outbound authority, and failsafe deadline")
	check(is_equal_approx(
				float(host.scheduler.get_current_tick()), activation_tick + 0.25)
			and is_equal_approx(float(stage_record.get("lure_until", -1.0))
				- float(host.scheduler.get_current_tick()), 19.75),
		"mid-transit snapshot exposes the exact unconsumed failsafe remainder")
	var capture_tick := float(host.scheduler.get_current_tick())

	# Complete in a discarded future through the real party checkpoint and shelter contract. Loading
	# the midpoint must restore both party positions/stats and phase, not retain endpoint success.
	var end_pos: Vector3 = chunk.get_preview_anchors()["end"]
	_place_party(host, end_pos)
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	_damage_party_for_rest(host)
	chunk._on_shelter_rested()
	check(bool(chunk.get_preview_state().get("complete", false))
			and _all_party_resting(host),
		"discarded future completes only through canonical full-party shelter rest")
	_apply_capture(host, chunk, midpoint)
	var rolled: Dictionary = chunk.get_preview_state()
	var rolled_stage: Dictionary = (rolled.get("stages", []) as Array)[0]
	check(str(rolled.get("phase", "")) == "active"
			and not bool(rolled.get("complete", true))
			and bool(rolled_stage.get("lure_active", false))
			and bool(rolled_stage.get("luring_outbound", false))
			and not bool(rolled_stage.get("lure_ready", true)),
		"same-instance rollback retracts future completion and restores mid-transit authority")
	check(host.game_state.get_position("peris").distance_to(end_pos) > 1.0
			and not _any_party_resting(host),
		"same-instance rollback retracts party endpoints and their future rest state")

	var ready_tick := _advance_until_lure_ready(host, chunk)
	rolled_stage = (chunk.get_preview_state().get("stages", []) as Array)[0]
	var ready_record: Dictionary = host.game_state.get_world_state(authority_key, {})
	var ready_stage_record: Dictionary = (ready_record.get("stages", []) as Array)[0]
	var ready_deadline := float(ready_stage_record.get("lure_until", -1.0))
	check(ready_tick >= 0.0 and bool(rolled_stage.get("lure_ready", false))
			and not bool(rolled_stage.get("luring_outbound", true))
			and ready_deadline > ready_tick
			and ready_deadline <= ready_tick + chunk.LURE_RACE_GRACE_SECONDS + 0.000001,
		"authoritative watcher arrival retires transit and starts one exact race beat")
	host.scheduler.advance_ticks(maxf(
		ready_deadline - float(host.scheduler.get_current_tick()) - 0.001, 0.0))
	rolled_stage = (chunk.get_preview_state().get("stages", []) as Array)[0]
	check(bool(rolled_stage.get("lure_ready", false))
			and not bool(rolled_stage.get("returning", false)),
		"restored arrival window cannot expire before its saved callback")
	host.scheduler.advance_ticks(0.001)
	rolled_stage = (chunk.get_preview_state().get("stages", []) as Array)[0]
	check(not bool(rolled_stage.get("lure_active", true))
			and not bool(rolled_stage.get("lure_ready", true))
			and bool(rolled_stage.get("returning", false)),
		"arrival callback expires once into the physical return race")

	await _discard(host)
	return {
		"capture": midpoint,
		"capture_tick": capture_tick,
		"activation_deadline": activation_deadline,
		"ready_deadline": ready_deadline,
	}


func _verify_fresh_presenter_lure(
	midpoint: Dictionary,
	expected_capture_tick: float,
	expected_activation_deadline: float,
	expected_ready_deadline: float
) -> void:
	var pair := await _boot_atom()
	var host = pair.host
	var chunk = pair.chunk
	_apply_capture(host, chunk, midpoint)
	var state: Dictionary = chunk.get_preview_state()
	var stage: Dictionary = (state.get("stages", []) as Array)[0]
	check(str(state.get("phase", "")) == "active"
			and bool(stage.get("lure_active", false))
			and bool(stage.get("luring_outbound", false))
			and not bool(stage.get("lure_ready", true))
			and is_equal_approx(
				float(stage.get("lure_remaining", -1.0)),
				expected_activation_deadline - expected_capture_tick),
		"fresh atom presenter restores the midpoint and its in-flight watcher")
	var record: Dictionary = host.game_state.get_world_state(chunk._atom_runtime_authority_key(), {})
	var stage_record: Dictionary = (record.get("stages", []) as Array)[0]
	check(is_equal_approx(
			float(stage_record.get("lure_until", -1.0)), expected_activation_deadline),
		"fresh presenter preserves the source scene's outbound failsafe deadline")

	var ready_tick := _advance_until_lure_ready(host, chunk)
	var ready_record: Dictionary = host.game_state.get_world_state(chunk._atom_runtime_authority_key(), {})
	var ready_stage_record: Dictionary = (ready_record.get("stages", []) as Array)[0]
	var ready_deadline := float(ready_stage_record.get("lure_until", -1.0))
	stage = (chunk.get_preview_state().get("stages", []) as Array)[0]
	check(ready_tick >= 0.0 and bool(stage.get("lure_ready", false))
			and is_equal_approx(ready_deadline, expected_ready_deadline),
		"fresh restore reaches the same physical arrival tick and one-beat deadline")
	host.scheduler.advance_ticks(maxf(
		ready_deadline - float(host.scheduler.get_current_tick()) - 0.001, 0.0))
	stage = (chunk.get_preview_state().get("stages", []) as Array)[0]
	check(bool(stage.get("lure_ready", false)) and not bool(stage.get("returning", false)),
		"fresh restore cannot run the return callback early")
	host.scheduler.advance_ticks(0.001)
	stage = (chunk.get_preview_state().get("stages", []) as Array)[0]
	check(not bool(stage.get("lure_active", true)) and bool(stage.get("returning", false)),
		"fresh restore consumes the same arrival beat and begins one return")
	await _discard(host)


func _verify_party_checkpoint_and_canonical_shelter() -> void:
	var pair := await _boot_atom()
	var host = pair.host
	var chunk = pair.chunk
	var stage: Dictionary = chunk._stages[0]
	# Isolate the checkpoint receipt from watcher acquisition. The encounter tests
	# cover detection; here a deliberately safe crossing must still use scheduler authority.
	chunk._set_stage_watch_armed(stage, false)
	var lead: Dictionary = (stage.get("sentries", []) as Array)[0]
	var gate_x: float = float((lead.get("post", Vector3.ZERO) as Vector3).x) \
		+ float(chunk.CELL) * 1.5
	host.game_state.snap_character_to("peris", Vector3(gate_x, 0.5, 0.0))
	# Presentation frames cannot manufacture or suppress the crossing receipt.
	chunk.headless_process(0.0)
	check(not bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary)
			.get("cleared", false)),
		"headless presentation cannot commit a watcher checkpoint")
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	check(not bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary)
			.get("cleared", false)),
		"one fast runner cannot dismiss a watcher checkpoint for bodies left behind")
	for char_id in ["aster", "endo"]:
		host.game_state.snap_character_to(char_id, Vector3(gate_x, 0.5,
			-0.5 if char_id == "aster" else 0.5))
	chunk.headless_process(0.0)
	check(not bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary)
			.get("cleared", false)),
		"crossing waits for the saved authority deadline after a presentation frame")
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	check(bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary)
			.get("cleared", false)),
		"fixed authority poll commits when the full conscious party crosses its causal boundary")

	var end_pos: Vector3 = chunk.get_preview_anchors()["end"]
	host.game_state.snap_character_to("peris", end_pos)
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	check(str(chunk.get_preview_state().get("phase", "")) != "shelter_ready"
			and not bool(chunk.get_preview_state().get("complete", false)),
		"one body reaching the endpoint cannot announce a party shelter arrival")
	var atp_before_reject := _party_atp(host)
	chunk._on_shelter_rested()
	check(not bool(chunk.get_preview_state().get("shelter_rested", false))
			and chunk._exit_shelter_interactable.is_interaction_enabled()
			and _party_atp(host) == atp_before_reject,
		"rejected partial-party shelter use remains retryable and charges nobody")

	_place_party(host, end_pos)
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	check(str(chunk.get_preview_state().get("phase", "")) == "shelter_ready"
			and not bool(chunk.get_preview_state().get("complete", false)),
		"whole-party arrival exposes rest as the final verb instead of auto-completing")
	_damage_party_for_rest(host)
	var paid_from := _party_atp(host)
	var authority_key := str(chunk._atom_runtime_authority_key())
	var signal_box := {"snapshot": {}}
	var stat_probe := func(_char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _capture(host)
	host.game_state.stat_changed.connect(stat_probe)
	chunk._on_shelter_rested()
	host.game_state.stat_changed.disconnect(stat_probe)
	var paid_to := _party_atp(host)
	var paid_once := true
	for char_id in chunk.PARTY_IDS:
		paid_once = paid_once and is_equal_approx(
			float(paid_to.get(char_id, 0.0)), float(paid_from.get(char_id, 0.0)) - 1.0)
	check(bool(chunk.get_preview_state().get("complete", false))
			and bool(chunk.get_preview_state().get("shelter_rested", false))
			and _all_party_resting(host) and paid_once
			and not chunk._exit_shelter_interactable.is_interaction_enabled(),
		"completion begins canonical rest for every party member and commits each ATP cost once")
	var signal_capture: Dictionary = signal_box.get("snapshot", {})
	var signal_record: Dictionary = (
		signal_capture.get("game_state", {}).get("world_state", {}).get(
			authority_key, {}) as Dictionary)
	check(not signal_capture.is_empty()
			and str(signal_record.get("shelter_rest_phase", "")) == "committing"
			and not bool(signal_record.get("shelter_rested", true))
			and _party_atp(host) == paid_to and _all_party_resting(host),
		"first ATP signal sees the atom COMMITTING after all party effects are installed")

	var same_events_before := _party_rest_event_count(host)
	_apply_capture(host, chunk, signal_capture)
	host.scheduler.advance_ticks(0.001)
	check(bool(chunk.get_preview_state().get("complete", false))
			and str(chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
			and _party_atp(host) == paid_to and _all_party_resting(host)
			and _party_rest_event_count(host) == same_events_before,
		"same-instance signal-time restore reconciles the atom without a second party-rest command")

	var fresh := await _boot_atom()
	var fresh_events_before := _party_rest_event_count(fresh.host)
	_apply_capture(fresh.host, fresh.chunk, signal_capture)
	fresh.host.scheduler.advance_ticks(0.001)
	check(bool(fresh.chunk.get_preview_state().get("complete", false))
			and str(fresh.chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
			and _party_atp(fresh.host) == paid_to and _all_party_resting(fresh.host)
			and _party_rest_event_count(fresh.host) == fresh_events_before,
		"fresh signal-time restore reaches the same atomic shelter result without replay")
	await _discard(fresh.host)
	await _discard(host)


func _verify_clear_and_failure_flags() -> void:
	var pair := await _boot_atom()
	var host = pair.host
	var chunk = pair.chunk
	var stage_live: Dictionary = chunk._stages[0]
	chunk._set_stage_watch_armed(stage_live, false)
	var lead: Dictionary = (stage_live.get("sentries", []) as Array)[0]
	var post: Vector3 = lead["post"]
	host.game_state.snap_character_to("peris", post + Vector3(chunk.CELL * 1.5, 0.0, 0.0))
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	check(not bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary)
			.get("cleared", false)),
		"a representative solo crossing remains pending until the party follows")
	host.game_state.snap_character_to("aster", post + Vector3(chunk.CELL * 1.5, 0.0, -0.5))
	host.game_state.snap_character_to("endo", post + Vector3(chunk.CELL * 1.5, 0.0, 0.5))
	chunk.headless_process(0.0)
	check(not bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary)
			.get("cleared", false)),
		"stage clearance is absent until its saved scheduler receipt")
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	var cleared_state: Dictionary = chunk.get_preview_state()
	var cleared_stage: Dictionary = (cleared_state.get("stages", []) as Array)[0]
	check(bool(cleared_stage.get("cleared", false))
			and not bool(cleared_stage.get("spotted", true)),
		"representative crossing publishes a cleared, non-failed stage")
	var cleared_capture := _capture(host)

	chunk._on_spotted("peris", 0)
	var terminal_stage: Dictionary = (chunk.get_preview_state().get("stages", []) as Array)[0]
	check(bool(terminal_stage.get("cleared", false))
			and not bool(terminal_stage.get("spotted", true)),
		"a late watcher signal cannot revoke a committed stage clear")
	chunk._reset_sentry_to_post(0)
	chunk._on_spotted("peris", 0)
	check(bool(((chunk.get_preview_state().get("stages", []) as Array)[0] as Dictionary).get("spotted", false)),
		"discarded branch can fail a re-armed stage")
	_apply_capture(host, chunk, cleared_capture)
	cleared_state = chunk.get_preview_state()
	cleared_stage = (cleared_state.get("stages", []) as Array)[0]
	check(bool(cleared_stage.get("cleared", false))
			and not bool(cleared_stage.get("spotted", true))
			and not bool(cleared_state.get("retry_pending", true)),
		"rollback restores cleared/spotted/retry flags from authority")

	chunk._reset_sentry_to_post(0)
	chunk._on_spotted("peris", 0)
	var failed_capture := _capture(host)
	var failed_record: Dictionary = host.game_state.get_world_state(chunk._atom_runtime_authority_key(), {})
	var failed_stage_record: Dictionary = (failed_record.get("stages", []) as Array)[0]
	check(bool(failed_stage_record.get("spotted", false))
			and not bool(failed_stage_record.get("cleared", true))
			and bool(failed_record.get("retry_pending", false))
			and int(failed_record.get("caught_count", 0)) == 1,
		"failure snapshot stores all failure bookkeeping together")
	chunk._on_spotted("peris", 0)
	check(int(chunk.get_preview_state().get("caught_count", 0)) == 1,
		"overlapping watcher signals count one causal failure per armed attempt")
	chunk.reset_preview_state()
	_apply_capture(host, chunk, failed_capture)
	var failed_state: Dictionary = chunk.get_preview_state()
	var failed_stage: Dictionary = (failed_state.get("stages", []) as Array)[0]
	check(bool(failed_stage.get("spotted", false))
			and not bool(failed_stage.get("cleared", true))
			and bool(failed_state.get("retry_pending", false))
			and int(failed_state.get("caught_count", 0)) == 1,
		"failure restore cannot refund its caught/retry state")
	await _discard(host)


func _verify_fixed_win_poll_cadence() -> void:
	var pair := await _boot_atom()
	var host = pair.host
	var chunk = pair.chunk
	var key := str(chunk._atom_runtime_authority_key())
	var initial: Dictionary = host.game_state.get_world_state(key, {})
	check(is_equal_approx(float(initial.get("win_poll_next_tick", -1.0)), 0.1),
		"atom begins with a fixed scheduler win-poll deadline")
	host.scheduler.advance_ticks(0.04)
	var midpoint := _capture(host)
	host.scheduler.advance_ticks(0.06)
	var after_tick: Dictionary = host.game_state.get_world_state(key, {})
	check(is_equal_approx(float(after_tick.get("win_poll_next_tick", -1.0)), 0.2),
		"win poll rearms one fixed interval after its callback")

	_apply_capture(host, chunk, midpoint)
	var restored: Dictionary = host.game_state.get_world_state(key, {})
	check(is_equal_approx(float(restored.get("win_poll_next_tick", -1.0)), 0.1),
		"win-poll rollback restores its original absolute callback tick")
	host.scheduler.advance_ticks(0.059)
	restored = host.game_state.get_world_state(key, {})
	check(is_equal_approx(float(restored.get("win_poll_next_tick", -1.0)), 0.1),
		"restored win poll cannot fire before the saved deadline")
	host.scheduler.advance_ticks(0.001)
	restored = host.game_state.get_world_state(key, {})
	check(is_equal_approx(float(host.scheduler.get_current_tick()), 0.1)
			and is_equal_approx(float(restored.get("win_poll_next_tick", -1.0)), 0.2),
		"restored win poll fires once and preserves fixed cadence")
	await _discard(host)


func _verify_missing_record_retraction() -> void:
	var pair := await _boot_atom()
	var host = pair.host
	var chunk = pair.chunk
	var authority_key := str(chunk._atom_runtime_authority_key())
	var absent := _capture(host)
	(absent.get("game_state", {}).get("world_state", {}) as Dictionary).erase(authority_key)

	check(_trigger_atom_flure(host, chunk, 0),
		"absence regression creates a future exact-source lure")
	chunk._on_spotted("peris", 0)
	chunk._reset_sentry_to_post(0)
	_place_party(host, chunk.get_preview_anchors()["end"])
	host.scheduler.advance_ticks(chunk.WIN_POLL_INTERVAL)
	_damage_party_for_rest(host)
	chunk._on_shelter_rested()
	var future: Dictionary = chunk.get_preview_state()
	check(bool(future.get("complete", false))
			and bool(future.get("shelter_rested", false))
			and int(future.get("caught_count", 0)) == 1,
		"absence regression advances multiple local flags in the discarded future")

	_apply_capture(host, chunk, absent)
	var rolled: Dictionary = chunk.get_preview_state()
	var stage: Dictionary = (rolled.get("stages", []) as Array)[0]
	check(str(rolled.get("phase", "")) == "ready"
			and not bool(rolled.get("complete", true))
			and not bool(rolled.get("shelter_rested", true))
			and int(rolled.get("caught_count", -1)) == 0
			and not bool(rolled.get("retry_pending", true)),
		"missing authority retracts future phase, completion, catch, and retry flags")
	check(not bool(stage.get("cleared", true))
			and not bool(stage.get("spotted", true))
			and not bool(stage.get("lure_active", true))
			and not bool(stage.get("returning", true)),
		"missing authority retracts every stage-local future state")
	var normalized: Dictionary = host.game_state.get_world_state(authority_key, {})
	check(int(normalized.get("version", 0)) == chunk.ATOM_RUNTIME_AUTHORITY_VERSION
			and is_equal_approx(float(normalized.get("win_poll_next_tick", -1.0)),
				float(host.scheduler.get_current_tick()) + chunk.WIN_POLL_INTERVAL),
		"legacy absence is normalized to an explicit baseline with a fresh fixed poll")
	await _discard(host)


func _boot_atom() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = AtomScene.instantiate()
	chunk.configure_chunk({"stages": TEST_STAGES, "seed": TEST_SEED, "zone_setpieces": false})
	host.register_party(chunk.get_spawn_positions())
	for char_id in ["aster", "peris", "endo"]:
		host.game_state.set_stat(char_id, "hp", 100.0)
		host.game_state.set_stat(char_id, "stamina", 100.0)
		host.game_state.set_stat(char_id, "atp", GameState.ATP_MAX_PIPS)
	chunk.attach_chunk_host(host, "puzzle_atom_authority")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	await process_frame
	return {"host": host, "chunk": chunk}


func _trigger_atom_flure(host, chunk, stage_index: int) -> bool:
	if stage_index < 0 or stage_index >= chunk._stages.size():
		return false
	var stage := chunk._stages[stage_index] as Dictionary
	var flure := stage.get("flure", null) as Flure
	if flure == null:
		return false
	host.game_state.snap_character_to("peris", flure.get_source_data_position())
	host.game_state.set_party(["peris"])
	flure.active_character = "peris"
	flure.on_interaction_arrived()
	host.scheduler.advance_ticks(float(flure.dwell_time))
	return str(flure.get_effect_state().get("phase", "")) == Flure.PHASE_ACTIVE


func _place_party(host, center: Vector3) -> void:
	var offsets := {
		"aster": Vector3(0.1, 0.0, -0.45),
		"peris": Vector3(0.25, 0.0, 0.0),
		"endo": Vector3(0.1, 0.0, 0.45),
	}
	for char_id in offsets:
		host.game_state.snap_character_to(char_id, center + offsets[char_id])


func _damage_party_for_rest(host) -> void:
	for char_id in ["aster", "peris", "endo"]:
		host.game_state.set_stat(char_id, "hp", 90.0)


func _party_atp(host) -> Dictionary:
	var result := {}
	for char_id in ["aster", "peris", "endo"]:
		result[char_id] = host.game_state.get_stat(char_id, "atp")
	return result


func _all_party_resting(host) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if not host.game_state.is_resting(char_id):
			return false
	return true


func _any_party_resting(host) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if host.game_state.is_resting(char_id):
			return true
	return false


func _party_rest_event_count(host) -> int:
	var count := 0
	if host == null or host.game_state == null or host.game_state.event_log == null:
		return count
	for event_v in host.game_state.event_log.events:
		var event: Dictionary = event_v
		if str(event.get("kind", "")) == str(GameEvent.KIND_PARTY_REST):
			count += 1
	return count


func _advance_until_lure_ready(host, chunk, max_seconds := -1.0) -> float:
	if max_seconds < 0.0:
		# Generated geometry varies by seed. The physical Flure's outbound deadline is the
		# authoritative travel budget; a fixed twelve-second test horizon rejected legitimate
		# longer routes while seven-plus seconds of the visible song still remained.
		max_seconds = float(chunk.LURE_DURATION) + 0.5
	var elapsed := 0.0
	while elapsed <= max_seconds:
		var stage: Dictionary = (chunk.get_preview_state().get("stages", []) as Array)[0]
		if bool(stage.get("lure_ready", false)):
			return float(host.scheduler.get_current_tick())
		if not bool(stage.get("luring_outbound", false)):
			return -1.0
		var step := minf(0.01, max_seconds - elapsed)
		if step <= 0.0:
			break
		host.scheduler.advance_ticks(step)
		elapsed += step
	return -1.0


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)


func _notify_snapshot_restored(chunk: Node) -> void:
	var pending: Array[Node] = [chunk]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node.has_method("on_game_state_snapshot_restored"):
			node.call("on_game_state_snapshot_restored")


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
