extends SceneTree

## Exact physical-source and atomic save/replay coverage for the three BossShowcase controls.
## The broader set-piece verifier owns the surrounding landmark/cadence contract.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const BossScene := preload("res://scenes/fragments/chunks/boss_showcase_chunk.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_survey_source_authority()
	await _verify_brake_source_transaction()
	await _verify_winch_batch_transaction()
	print("BOSS CONTROL TRANSACTIONS: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_survey_source_authority() -> void:
	var pair := await _boot_boss(31)
	var host = pair.host
	var chunk = pair.chunk
	var source: Node = chunk._survey_interactable
	var source_pos := _control_position(host, source)
	var baseline := _capture(host)
	check(not chunk._on_watch_vantage_reached()
			and not bool(chunk.get_preview_state().get("watch_vantage", false)),
		"survey direct/no-source callback is inert")
	host.game_state.snap_character_to("aster", source_pos + Vector3(8.0, 0.0, 0.0))
	check(not _trigger(source, "aster"),
		"survey rejects a remote body rather than the selected portrait")

	host.game_state.snap_character_to("aster", source_pos)
	check(host.game_state.command_external_traversal(
			"aster", &"boss_survey_busy_fixture",
			source_pos + Vector3(0.5, 0.0, 0.0), source_pos,
			source_pos + Vector3(0.5, 0.0, 0.0), 1.0, &"locked"),
		"survey busy fixture owns Aster through a locked traversal")
	check(not _trigger(source, "aster"),
		"survey rejects the nearby body while another action owns it")
	host.game_state.cancel_external_traversal("aster", &"fixture_complete")
	host.game_state.snap_character_to("aster", source_pos)

	var accepted_box := {"capture": {}}
	var accepted_listener := func(interactable_id: String, actor: String) -> void:
		if interactable_id == str(source.get("data_id")) and actor == "aster" \
				and not bool(chunk.get_preview_state().get("watch_vantage", false)):
			accepted_box.capture = _capture(host)
	host.game_state.interactable_triggered.connect(accepted_listener)
	host.active_character = "peris"
	check(_trigger(source, "aster"),
		"nearby Aster completes the survey while Peris is the selected portrait")
	host.game_state.interactable_triggered.disconnect(accepted_listener)
	var completed := _capture(host)
	check(not (accepted_box.capture as Dictionary).is_empty()
			and bool(chunk.get_preview_state().get("watch_vantage", false))
			and str(chunk.get_preview_state().get("survey_actor", "")) == "aster"
			and int(chunk.get_preview_state().get("survey_trigger_consumed", 0)) == 1,
		"survey records its exact actor and monotonic source receipt")
	check(not chunk._on_watch_vantage_reached(source),
		"survey cannot reuse its spent receipt")

	var accepted := await _boot_boss(31)
	_apply_capture(accepted.host, accepted.chunk, accepted_box.capture)
	_apply_capture(accepted.host, accepted.chunk, accepted_box.capture)
	var accepted_source: Node = accepted.chunk._survey_interactable
	check(not bool(accepted.chunk.get_preview_state().get("watch_vantage", true))
			and accepted_source.is_interaction_enabled()
			and int(accepted.chunk.get_preview_state().get(
				"survey_trigger_consumed", 0)) == 1,
		"accepted-trigger restore rearms survey without granting the vantage")
	check(not accepted.chunk._on_watch_vantage_reached(accepted_source),
		"accepted-trigger restore consumes the stale survey callback")
	accepted.host.game_state.snap_character_to(
		"aster", _control_position(accepted.host, accepted_source))
	check(_trigger(accepted_source, "aster")
			and int(accepted.chunk.get_preview_state().get(
				"survey_trigger_consumed", 0)) == 2,
		"rearmed survey accepts one new physical receipt")

	var fresh_completed := await _boot_boss(31)
	_apply_capture(fresh_completed.host, fresh_completed.chunk, completed)
	_apply_capture(fresh_completed.host, fresh_completed.chunk, completed)
	check(bool(fresh_completed.chunk.get_preview_state().get("watch_vantage", false))
			and not fresh_completed.chunk._survey_interactable.is_interaction_enabled(),
		"fresh repeated restore preserves one completed survey")

	_apply_capture(host, chunk, baseline)
	check(not bool(chunk.get_preview_state().get("watch_vantage", true))
			and source.is_interaction_enabled(),
		"survey rollback retracts the discarded future and restores its source")
	await _discard(host)
	await _discard(accepted.host)
	await _discard(fresh_completed.host)


func _verify_brake_source_transaction() -> void:
	var pair := await _boot_boss(37)
	var host = pair.host
	var chunk = pair.chunk
	var source: Node = chunk._brake_ia
	var source_pos := _control_position(host, source)
	check(not chunk._on_brake_used()
			and not bool(chunk.get_preview_state().get("ring0_parked", false)),
		"brake direct/no-source callback is inert")
	host.game_state.snap_character_to("aster", source_pos + Vector3(7.0, 0.0, 0.0))
	check(not _trigger(source, "aster"),
		"brake rejects a distant body")
	host.game_state.snap_character_to("aster", source_pos)

	var accepted_box := {"capture": {}}
	var reserved_box := {"capture": {}}
	var accepted_listener := func(interactable_id: String, actor: String) -> void:
		if interactable_id == str(source.get("data_id")) and actor == "aster" \
				and not bool(chunk.get_preview_state().get("ring0_parked", false)):
			accepted_box.capture = _capture(host)
	var reserved_listener := func(key: String, value: Variant) -> void:
		if key != chunk.boss_authority_key() or not value is Dictionary:
			return
		var tx: Dictionary = (value as Dictionary).get("brake_transaction", {})
		if str(tx.get("phase", "")) == chunk.BRAKE_TRANSACTION_RESERVED:
			reserved_box.capture = _capture(host)
	host.game_state.interactable_triggered.connect(accepted_listener)
	host.game_state.world_state_changed.connect(reserved_listener)
	host.active_character = "peris"
	check(_trigger(source, "aster"),
		"brake uses nearby Aster while Peris remains the selected portrait")
	host.game_state.interactable_triggered.disconnect(accepted_listener)
	host.game_state.world_state_changed.disconnect(reserved_listener)
	var committed := _capture(host)
	var transaction: Dictionary = chunk.get_preview_state().get("brake_transaction", {})
	check(not (accepted_box.capture as Dictionary).is_empty()
			and not (reserved_box.capture as Dictionary).is_empty(),
		"brake exposes accepted-source and pre-mutation reservation seams")
	check(bool(chunk.get_preview_state().get("ring0_parked", false))
			and str(transaction.get("phase", "")) == chunk.BRAKE_TRANSACTION_COMMITTED
			and int(transaction.get("receipt_count", 0)) == 1
			and bool(transaction.get("target_is_parked", false)),
		"brake commits its chosen detent from the reserved outcome")
	var parked_phase := float(transaction.get("target_parked_phase", -1.0))
	check(not chunk._on_brake_used(source)
			and is_equal_approx(float(chunk._ring0_parked), parked_phase),
		"brake stale receipt cannot release or retarget the wheel")

	var accepted := await _boot_boss(37)
	_apply_capture(accepted.host, accepted.chunk, accepted_box.capture)
	_apply_capture(accepted.host, accepted.chunk, accepted_box.capture)
	var accepted_source: Node = accepted.chunk._brake_ia
	check(not bool(accepted.chunk.get_preview_state().get("ring0_parked", true))
			and int(accepted.chunk.get_preview_state().get(
				"brake_trigger_consumed", 0)) == 1
			and not accepted.chunk._on_brake_used(accepted_source),
		"accepted-only brake restore grants no detent and consumes the stale edge")
	accepted.host.game_state.snap_character_to(
		"aster", _control_position(accepted.host, accepted_source))
	check(_trigger(accepted_source, "aster")
			and int(accepted.chunk.get_preview_state().get(
				"brake_trigger_consumed", 0)) == 2,
		"accepted-only brake restore remains retryable with a new receipt")

	var reserved := await _boot_boss(37)
	_apply_capture(reserved.host, reserved.chunk, reserved_box.capture)
	_apply_capture(reserved.host, reserved.chunk, reserved_box.capture)
	var reserved_tx: Dictionary = reserved.chunk.get_preview_state().get(
		"brake_transaction", {})
	check(bool(reserved.chunk.get_preview_state().get("ring0_parked", false))
			and str(reserved_tx.get("phase", "")) \
				== reserved.chunk.BRAKE_TRANSACTION_COMMITTED
			and is_equal_approx(
				float(reserved.chunk._ring0_parked),
				float(reserved_tx.get("target_parked_phase", -1.0))),
		"reserved brake restore applies the exact saved target once")

	var fresh_committed := await _boot_boss(37)
	_apply_capture(fresh_committed.host, fresh_committed.chunk, committed)
	_apply_capture(fresh_committed.host, fresh_committed.chunk, committed)
	check(bool(fresh_committed.chunk.get_preview_state().get("ring0_parked", false))
			and is_equal_approx(
				float(fresh_committed.chunk._ring0_parked), parked_phase),
		"fresh repeated restore preserves the committed detent")

	# AlignmentCrossing owns this occupancy flag in production; forcing its pending-window phase
	# isolates the brake's refusal without moving the test clock into a later wheel window.
	var occupied := await _boot_boss(41)
	occupied.chunk._align_mouths[0]._pending_launch = true
	var occupied_source: Node = occupied.chunk._brake_ia
	occupied.host.game_state.snap_character_to(
		"aster", _control_position(occupied.host, occupied_source))
	var count_before := _source_trigger_count(occupied.host, occupied_source)
	check(not _trigger(occupied_source, "aster")
			and _source_trigger_count(occupied.host, occupied_source) == count_before
			and not bool(occupied.chunk.get_preview_state().get("ring0_parked", false)),
		"brake refuses before consuming a receipt while the wheel crossing is occupied")

	await _discard(host)
	await _discard(accepted.host)
	await _discard(reserved.host)
	await _discard(fresh_committed.host)
	await _discard(occupied.host)


func _verify_winch_batch_transaction() -> void:
	var pair := await _boot_boss(43)
	var host = pair.host
	var chunk = pair.chunk
	var source: Node = chunk._winch_interactable
	var source_pos := _control_position(host, source)
	var apron := Vector3(float(chunk.TOWER_X) - 5.4, 0.0, float(chunk.CRAG_R) + 1.0)
	check(not chunk._on_winch_used()
			and (chunk.get_preview_state().get("winch_batch", {}) as Dictionary).is_empty(),
		"winch direct/no-source callback is inert")
	host.game_state.snap_character_to("peris", source_pos + Vector3(8.0, 0.0, 0.0))
	check(not _trigger(source, "peris"),
		"winch rejects a distant servicing body")
	host.game_state.snap_character_to("peris", source_pos)
	check(host.game_state.command_external_traversal(
			"peris", &"boss_winch_busy_fixture",
			source_pos + Vector3(0.5, 0.0, 0.0), source_pos,
			source_pos + Vector3(0.5, 0.0, 0.0), 1.0, &"locked"),
		"winch busy fixture owns Peris through a locked traversal")
	check(not _trigger(source, "peris"),
		"winch rejects its nearby servicing body while another action owns it")
	host.game_state.cancel_external_traversal("peris", &"fixture_complete")
	host.game_state.snap_character_to("peris", source_pos)
	host.game_state.snap_character_to("aster", apron)

	var enemy = _enemy(chunk, "trail_gnawer_0")
	check(enemy != null, "winch batch fixture finds the physical trail Gnawer")
	var enemy_hp_before := float(enemy.get_hp())
	var accepted_box := {"capture": {}}
	var reserved_box := {"capture": {}}
	var start_reserved_box := {"capture": {}}
	var pre_impact_box := {"capture": {}}
	var damage_signal_box := {"capture": {}}
	var post_damage_box := {"capture": {}}
	var accepted_listener := func(interactable_id: String, actor: String) -> void:
		if interactable_id == str(source.get("data_id")) and actor == "peris" \
				and (chunk.get_preview_state().get("winch_batch", {}) as Dictionary).is_empty():
			accepted_box.capture = _capture(host)
	var boss_state_listener := func(key: String, value: Variant) -> void:
		if key != chunk.boss_authority_key() or not value is Dictionary:
			return
		var batch: Dictionary = (value as Dictionary).get("winch_batch", {})
		if str(batch.get("phase", "")) == chunk.WINCH_BATCH_RESERVED:
			reserved_box.capture = _capture(host)
		if str(batch.get("phase", "")) != chunk.WINCH_BATCH_SWEEPING:
			return
		var target := _batch_target(batch, "trail_gnawer_0")
		if bool(target.get("start_committed", false)) \
				and not bool(target.get("traversal_started", false)):
			start_reserved_box.capture = _capture(host)
	var damage_listener := func(_amount: float, _hp: float) -> void:
		var target := _batch_target(
			chunk.get_preview_state().get("winch_batch", {}), "trail_gnawer_0")
		if bool(target.get("impact_committed", false)) \
				and not bool(target.get("impact_applied", false)):
			damage_signal_box.capture = _capture(host)
	var enemy_state_listener := func(key: String, _value: Variant) -> void:
		if key != str(enemy.call("_enemy_authority_key")):
			return
		var target := _batch_target(
			chunk.get_preview_state().get("winch_batch", {}), "trail_gnawer_0")
		if bool(target.get("impact_committed", false)) \
				and not bool(target.get("impact_applied", false)):
			post_damage_box.capture = _capture(host)

	# Put the test observer before the boss owner for the physical-arrival/pre-impact seam.
	var boss_finished := Callable(chunk, "_on_boss_external_traversal_finished")
	host.game_state.external_traversal_finished.disconnect(boss_finished)
	var finish_listener := func(char_id: String, traversal_id: StringName) -> void:
		var target := _batch_target(
			chunk.get_preview_state().get("winch_batch", {}), char_id)
		if char_id == "trail_gnawer_0" \
				and StringName(str(target.get("traversal_id", ""))) == traversal_id:
			pre_impact_box.capture = _capture(host)
	host.game_state.external_traversal_finished.connect(finish_listener)
	host.game_state.external_traversal_finished.connect(boss_finished)
	host.game_state.interactable_triggered.connect(accepted_listener)
	host.game_state.world_state_changed.connect(boss_state_listener)
	host.game_state.world_state_changed.connect(enemy_state_listener)
	enemy.damaged.connect(damage_listener)

	host.active_character = "endo"
	check(_trigger(source, "peris"),
		"winch uses nearby Peris while Endo remains the selected portrait")
	host.game_state.interactable_triggered.disconnect(accepted_listener)
	host.game_state.world_state_changed.disconnect(boss_state_listener)
	var started: Dictionary = chunk.get_preview_state().get("winch_batch", {})
	var targets: Array = started.get("targets", [])
	check(not (accepted_box.capture as Dictionary).is_empty()
			and not (reserved_box.capture as Dictionary).is_empty()
			and not (start_reserved_box.capture as Dictionary).is_empty(),
		"winch exposes accepted, whole-batch, and per-body command reservation seams")
	check(str(started.get("phase", "")) == chunk.WINCH_BATCH_SWEEPING
			and targets.size() >= 3
			and int(started.get("receipt_count", 0)) == 1
			and int(started.get("serial", 0)) == 1,
		"winch reserves one exact sorted physical cohort before movement")
	var all_started := true
	for target_v in targets:
		var target := target_v as Dictionary
		var char_id := str(target.get("id", ""))
		var transit: Dictionary = host.game_state.get_external_traversal_state(char_id)
		all_started = all_started \
			and bool(target.get("start_committed", false)) \
			and bool(target.get("traversal_started", false)) \
			and StringName(str(transit.get("traversal_id", ""))) \
				== StringName(str(target.get("traversal_id", ""))) \
			and str(transit.get("interrupt_policy", "")) == "locked"
	check(all_started and is_equal_approx(float(enemy.get_hp()), enemy_hp_before),
		"every reserved body starts its locked sweep and button press deals no enemy damage")

	host.scheduler.advance_ticks(chunk.SCREE_SWEEP_DURATION * 0.5)
	var midpoint := _capture(host)
	var enemy_mid: Dictionary = host.game_state.get_external_traversal_state(
		"trail_gnawer_0")
	check(float(enemy_mid.get("progress", 0.0)) > 0.49
			and float(enemy_mid.get("progress", 0.0)) < 0.51
			and is_equal_approx(float(enemy.get_hp()), enemy_hp_before),
		"mid-batch snapshot preserves physical progress without early impact")
	host.scheduler.advance_ticks(chunk.SCREE_SWEEP_DURATION * 0.5)
	host.game_state.external_traversal_finished.disconnect(finish_listener)
	enemy.damaged.disconnect(damage_listener)
	host.game_state.world_state_changed.disconnect(enemy_state_listener)
	var completed := _capture(host)
	var completed_batch: Dictionary = chunk.get_preview_state().get("winch_batch", {})
	var enemy_target := _batch_target(completed_batch, "trail_gnawer_0")
	check(not (pre_impact_box.capture as Dictionary).is_empty()
			and not (damage_signal_box.capture as Dictionary).is_empty()
			and not (post_damage_box.capture as Dictionary).is_empty(),
		"winch exposes arrival, damage-signal, and post-damage/pre-suffix save seams")
	check(str(completed_batch.get("phase", "")) == chunk.WINCH_BATCH_COMPLETE
			and bool(enemy_target.get("impact_applied", false))
			and is_equal_approx(
				float(enemy.get_hp()), enemy_hp_before - chunk.WINCH_IMPACT_DAMAGE),
		"enemy damage commits once from physical scree impact")
	check(not chunk._on_winch_used(source),
		"completed winch cannot reuse its stale source receipt")

	var accepted := await _boot_boss(43)
	_apply_capture(accepted.host, accepted.chunk, accepted_box.capture)
	_apply_capture(accepted.host, accepted.chunk, accepted_box.capture)
	check((accepted.chunk.get_preview_state().get(
				"winch_batch", {}) as Dictionary).is_empty()
			and int(accepted.chunk.get_preview_state().get(
				"winch_trigger_consumed", 0)) == 1
			and not accepted.chunk._on_winch_used(
				accepted.chunk._winch_interactable),
		"accepted-only winch restore grants no sweep and consumes the stale edge")

	var reserved := await _boot_boss(43)
	_apply_capture(reserved.host, reserved.chunk, reserved_box.capture)
	_apply_capture(reserved.host, reserved.chunk, reserved_box.capture)
	reserved.host.scheduler.advance_ticks(0.000001)
	check(_batch_all_active(reserved.host,
			reserved.chunk.get_preview_state().get("winch_batch", {})),
		"fresh whole-batch reservation restore starts the exact unpaid cohort")

	var start_reserved := await _boot_boss(43)
	_apply_capture(start_reserved.host, start_reserved.chunk, start_reserved_box.capture)
	start_reserved.host.scheduler.advance_ticks(0.000001)
	check(_batch_all_active(start_reserved.host,
			start_reserved.chunk.get_preview_state().get("winch_batch", {})),
		"fresh per-body reservation restore resumes the saved command suffix")

	var fresh_mid := await _boot_boss(43)
	_apply_capture(fresh_mid.host, fresh_mid.chunk, midpoint)
	_apply_capture(fresh_mid.host, fresh_mid.chunk, midpoint)
	var fresh_mid_enemy = _enemy(fresh_mid.chunk, "trail_gnawer_0")
	check(fresh_mid.host.game_state.is_external_traversal_active("trail_gnawer_0")
			and is_equal_approx(float(fresh_mid_enemy.get_hp()), enemy_hp_before),
		"fresh repeated midpoint restore reconstructs movement with no early damage")
	fresh_mid.host.scheduler.advance_ticks(chunk.SCREE_SWEEP_DURATION * 0.5)
	check(is_equal_approx(
			float(fresh_mid_enemy.get_hp()), enemy_hp_before - chunk.WINCH_IMPACT_DAMAGE),
		"fresh midpoint consumes the saved remainder and damages once")

	await _verify_winch_impact_seam(
		"arrival/pre-owner", pre_impact_box.capture, enemy_hp_before, chunk.WINCH_IMPACT_DAMAGE)
	await _verify_winch_impact_seam(
		"damage-signal", damage_signal_box.capture, enemy_hp_before, chunk.WINCH_IMPACT_DAMAGE)
	await _verify_winch_impact_seam(
		"post-damage", post_damage_box.capture, enemy_hp_before, chunk.WINCH_IMPACT_DAMAGE)

	var fresh_completed := await _boot_boss(43)
	_apply_capture(fresh_completed.host, fresh_completed.chunk, completed)
	_apply_capture(fresh_completed.host, fresh_completed.chunk, completed)
	var fresh_completed_enemy = _enemy(fresh_completed.chunk, "trail_gnawer_0")
	check(str((fresh_completed.chunk.get_preview_state().get(
				"winch_batch", {}) as Dictionary).get("phase", "")) \
			== fresh_completed.chunk.WINCH_BATCH_COMPLETE
			and is_equal_approx(
				float(fresh_completed_enemy.get_hp()),
				enemy_hp_before - chunk.WINCH_IMPACT_DAMAGE),
		"fresh repeated completed restore neither moves nor damages the cohort again")

	await _discard(host)
	await _discard(accepted.host)
	await _discard(reserved.host)
	await _discard(start_reserved.host)
	await _discard(fresh_mid.host)
	await _discard(fresh_completed.host)


func _verify_winch_impact_seam(
	label: String, capture: Dictionary, hp_before: float, damage: float
) -> void:
	var pair := await _boot_boss(43)
	_apply_capture(pair.host, pair.chunk, capture)
	_apply_capture(pair.host, pair.chunk, capture)
	pair.host.scheduler.advance_ticks(0.000001)
	var enemy = _enemy(pair.chunk, "trail_gnawer_0")
	check(is_equal_approx(float(enemy.get_hp()), hp_before - damage)
			and bool(_batch_target(
				pair.chunk.get_preview_state().get("winch_batch", {}),
				"trail_gnawer_0").get("impact_applied", false)),
		"fresh repeated %s restore reconciles exactly one physical impact" % label)
	await _discard(pair.host)


func _boot_boss(seed: int) -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = BossScene.instantiate()
	chunk.configure_chunk({"seed": seed})
	chunk.attach_chunk_host(host, "boss_showcase")
	host.add_child(chunk)
	await process_frame
	host.register_party(chunk.get_spawn_positions())
	for char_id in chunk.get_spawn_positions().keys():
		host.game_state.set_stat(str(char_id), "hp", 100.0)
		host.game_state.set_stat(str(char_id), "stamina", 100.0)
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _trigger(source: Node, actor: String) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _control_position(host, source: Node) -> Vector3:
	if source == null or not is_instance_valid(source):
		return Vector3.ZERO
	var data_id := str(source.get("data_id"))
	if data_id != "" and host.game_state.has_interactable(data_id):
		return host.game_state.get_interactable(data_id).get("position", Vector3.ZERO)
	return (source as Node3D).global_position if source is Node3D else Vector3.ZERO


func _source_trigger_count(host, source: Node) -> int:
	var data_id := str(source.get("data_id")) if source != null else ""
	return int(host.game_state.get_interactable(data_id).get("trigger_count", -1)) \
		if data_id != "" and host.game_state.has_interactable(data_id) else -1


func _batch_target(batch_value: Variant, char_id: String) -> Dictionary:
	var batch: Dictionary = batch_value if batch_value is Dictionary else {}
	for target_v in (batch.get("targets", []) as Array):
		var target := target_v as Dictionary
		if str(target.get("id", "")) == char_id:
			return target
	return {}


func _batch_all_active(host, batch_value: Variant) -> bool:
	var batch: Dictionary = batch_value if batch_value is Dictionary else {}
	var targets: Array = batch.get("targets", [])
	if targets.is_empty():
		return false
	for target_v in targets:
		var target := target_v as Dictionary
		var transit: Dictionary = host.game_state.get_external_traversal_state(
			str(target.get("id", "")))
		if StringName(str(transit.get("traversal_id", ""))) \
				!= StringName(str(target.get("traversal_id", ""))):
			return false
	return true


func _enemy(chunk, char_id: String):
	for enemy in chunk._enemies:
		if is_instance_valid(enemy) and str(enemy.char_id) == char_id:
			return enemy
	return null


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


func _notify_snapshot_restored(node: Node) -> void:
	if node.has_method("on_game_state_snapshot_restored"):
		node.call("on_game_state_snapshot_restored")
	for child in node.get_children():
		_notify_snapshot_restored(child)


func _json_round_trip(value: Variant) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(host: Node) -> void:
	host.queue_free()
	await process_frame


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
