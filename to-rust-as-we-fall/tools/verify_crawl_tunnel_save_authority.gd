extends SceneTree

## Receipt/consequence authority regression for CrawlTunnel and AlignmentCrossing.
## Exercises saves captured from the exact synchronous signals where an old delayed-teleport
## implementation could lose, duplicate, or remotely manufacture a traversal.

const WAYPOINTS := [
	Vector3(0.0, 0.0, 4.0),
	Vector3(4.0, 0.0, 4.0),
	Vector3(4.0, 0.0, 5.0),
]

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_source_receipts_and_exploits()
	await _verify_accepted_signal_recovery()
	await _verify_authored_path_start_signal_recovery()
	await _verify_finish_signal_recovery()
	await _verify_alignment_prediction_recovery()
	_verify_static_contracts()
	print("CRAWL TUNNEL SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_source_receipts_and_exploits() -> void:
	var context := await _make_crawl_context("crawl_receipts")
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var tunnel: CrawlTunnel = context.tunnel
	tunnel._on_interacted()
	check(tunnel._queue.is_empty() and tunnel._crawl_traversals.is_empty(),
		"direct interaction callback has no consequence without an accepted source receipt")
	check(not tunnel.start_group_crawl(["aster"]),
		"retired public group helper cannot remotely manufacture a crawl")
	state.snap_character_to("aster", Vector3(12.0, 0.0, 0.0))
	tunnel.active_character = "aster"
	check(not tunnel._trigger(false)
			and int(state.get_interactable("crawl_receipts").get("trigger_count", -1)) == 0,
		"remote body cannot obtain a source/proximity receipt")
	state.snap_character_to("aster", Vector3.ZERO)
	check(tunnel._trigger(false), "body at this exact mouth obtains one accepted receipt")
	var first_nonce := int(tunnel._activation_receipt.get("nonce", -1))
	tunnel._on_interacted()
	check(int(tunnel._activation_receipt.get("nonce", -1)) == first_nonce
			and tunnel._queue.size() == 1,
		"accepted receipt is consumed once; direct callback cannot replay it")
	scheduler.advance_ticks(20.0)
	state.command_stop("aster")
	state.snap_character_to("aster", Vector3.ZERO)

	# Capture publication of the SECOND provisional receipt, before GameState accepts it. The old
	# ever-triggered bool misread this as accepted because the repeatable mouth had fired once before.
	var provisional := {}
	var authority_key := tunnel._crawl_authority_key()
	state.world_state_changed.connect(func(key: String, value: Variant) -> void:
		if not provisional.is_empty() or key != authority_key or not value is Dictionary:
			return
		var pending: Dictionary = (value as Dictionary).get("source_receipt_pending", {})
		if int(pending.get("expected_trigger_count", -1)) == 2:
			provisional["snapshot"] = _snapshot(scheduler, state)
	)
	check(tunnel._trigger(false), "repeatable mouth accepts a distinct second receipt")
	check(int(state.get_interactable("crawl_receipts").get("trigger_count", -1)) == 2
			and int(tunnel._activation_receipt.get("nonce", -1)) > first_nonce,
		"repeat activation advances both acceptance and receipt identities")
	check(not provisional.is_empty(), "pre-acceptance repeat receipt boundary was captured")
	if not provisional.is_empty():
		_restore_same(context, provisional.snapshot)
		check(tunnel._queue.is_empty() and tunnel._source_receipt_pending.is_empty()
				and int(state.get_interactable("crawl_receipts").get("trigger_count", -1)) == 1,
			"pre-acceptance rollback discards the provisional receipt instead of consuming old use")
		check(tunnel._trigger(false)
				and int(state.get_interactable("crawl_receipts").get("trigger_count", -1)) == 2,
			"discarded provisional receipt leaves the repeatable mouth usable")
	await _discard_context(context)

	var group_context := await _make_crawl_context(
		"crawl_failed_approach", ["aster", "peris"])
	var group_scheduler: EventScheduler = group_context.scheduler
	var group_state: GameState = group_context.state
	var group_tunnel: CrawlTunnel = group_context.tunnel
	var peris_origin := group_state.get_position("peris")
	check(group_state.command_external_path_traversal(
			"peris", &"test/action_lock",
			[peris_origin, peris_origin + Vector3(20.0, 0.0, 0.0)],
			[peris_origin, peris_origin + Vector3(20.0, 0.0, 0.0)],
			100.0),
		"failed-approach fixture action-locks the remote group member")
	var refused := {"count": 0}
	group_tunnel.refused.connect(func() -> void: refused.count += 1)
	group_tunnel.active_character = "aster"
	check(group_tunnel._trigger(false), "valid lead body may commit its exact selected group")
	group_scheduler.advance_ticks(2.0)
	check(int(refused.count) >= 1 and not group_tunnel._crawl_traversals.has("peris"),
		"failed approach emits refusal and never creates a crawl reservation for remote member")
	check(group_state.is_external_traversal_active("peris")
			and str(group_state.get_external_traversal_state("peris").get(
				"traversal_id", "")) == "test/action_lock",
		"crawl refusal cannot steal or teleport an action-locked body")
	await _discard_context(group_context)


func _verify_accepted_signal_recovery() -> void:
	var context := await _make_crawl_context("crawl_accepted_signal", ["aster"], true)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var tunnel: CrawlTunnel = context.tunnel
	var captured := {}
	state.interactable_triggered.connect(func(id: String, actor: String) -> void:
		if id != "crawl_accepted_signal" or actor != "aster" or not captured.is_empty():
			return
		captured["authority"] = (
			state.get_world_state(tunnel._crawl_authority_key(), {}) as Dictionary).duplicate(true)
		captured["snapshot"] = _snapshot(scheduler, state)
	)
	tunnel.active_character = "aster"
	check(tunnel._trigger(false), "one-shot source interaction is accepted")
	var accepted_record: Dictionary = captured.get("authority", {})
	check(not captured.is_empty()
			and not (accepted_record.get("source_receipt_pending", {}) as Dictionary).is_empty()
			and (accepted_record.get("activation_receipt", {}) as Dictionary).is_empty(),
		"accepted-trigger signal sees exact source receipt before consequence consumption")

	var same_starts := {"count": 0}
	tunnel.crawl_started.connect(func(_who: String) -> void: same_starts.count += 1)
	_restore_same(context, captured.snapshot)
	tunnel.on_game_state_snapshot_restored()
	check(tunnel._queue == ["aster"] and tunnel._source_receipt_pending.is_empty()
			and not state.is_interactable_enabled("crawl_accepted_signal"),
		"same-instance restore consumes accepted one-shot receipt once despite disabled presenter")
	scheduler.advance_ticks(0.051)
	check(int(same_starts.count) == 1,
		"same-instance accepted-signal restore starts exactly one traversal")

	var fresh := await _make_fresh_crawl(
		"crawl_accepted_signal", captured.snapshot, ["aster"], false)
	var fresh_tunnel: CrawlTunnel = fresh.tunnel
	var fresh_starts := {"count": 0}
	fresh_tunnel.crawl_started.connect(func(_who: String) -> void: fresh_starts.count += 1)
	fresh_tunnel.on_game_state_snapshot_restored()
	fresh_tunnel.on_game_state_snapshot_restored()
	check(fresh_tunnel._queue == ["aster"]
			and not (fresh.state as GameState).is_interactable_enabled("crawl_accepted_signal"),
		"fresh presenter reconstructs the accepted one-shot consequence")
	(fresh.scheduler as EventScheduler).advance_ticks(0.051)
	check(int(fresh_starts.count) == 1,
		"fresh accepted-signal restore consumes the receipt idempotently")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_authored_path_start_signal_recovery() -> void:
	var context := await _make_crawl_context("crawl_path_start")
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var tunnel: CrawlTunnel = context.tunnel
	var captured := {}
	state.movement_started.connect(func(id: String) -> void:
		if id != "aster" or not state.is_external_traversal_active(id) or not captured.is_empty():
			return
		captured["authority"] = (
			state.get_world_state(tunnel._crawl_authority_key(), {}) as Dictionary).duplicate(true)
		captured["snapshot"] = _snapshot(scheduler, state)
	)
	tunnel.active_character = "aster"
	check(tunnel._trigger(false), "path-start fixture accepts exact mouth interaction")
	scheduler.advance_ticks(0.051)
	var record: Dictionary = captured.get("authority", {})
	var transaction: Dictionary = (
		record.get("traversals", {}) as Dictionary).get("aster", {})
	check(not captured.is_empty() and str(transaction.get("phase", "")) == "reserved"
			and (transaction.get("data_path", []) as Array).size() == 4,
		"movement-start signal sees reservation, full authored path, and deadline pre-published")

	var same_starts := {"count": 0}
	tunnel.crawl_started.connect(func(_who: String) -> void: same_starts.count += 1)
	_restore_same(context, captured.snapshot)
	tunnel.on_game_state_snapshot_restored()
	check(int(same_starts.count) == 1 and state.is_external_traversal_active("aster")
			and state.get_character_concealment("aster") == GameState.CONCEAL_FULL
			and is_equal_approx(float(state.characters.aster.move_speed), 1.0),
		"same-instance start-signal restore applies crawl effects once")
	scheduler.advance_ticks(4.5)
	check(state.get_position("aster").distance_to(Vector3(0.5, 0.0, 4.0)) < 0.03,
		"same-instance traversal follows authored bends rather than endpoint teleport/lerp")

	var fresh := await _make_fresh_crawl(
		"crawl_path_start", captured.snapshot, ["aster"], false)
	var fresh_tunnel: CrawlTunnel = fresh.tunnel
	var fresh_starts := {"count": 0}
	fresh_tunnel.crawl_started.connect(func(_who: String) -> void: fresh_starts.count += 1)
	fresh_tunnel.on_game_state_snapshot_restored()
	fresh_tunnel.on_game_state_snapshot_restored()
	(fresh.scheduler as EventScheduler).advance_ticks(4.5)
	check(int(fresh_starts.count) == 1
			and (fresh.state as GameState).get_position("aster").distance_to(
				Vector3(0.5, 0.0, 4.0)) < 0.03,
		"fresh/idempotent restore preserves one canonical waypoint traversal")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_finish_signal_recovery() -> void:
	var captured := {}
	var context := await _make_crawl_context(
		"crawl_finish_signal", ["aster"], false, captured)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var tunnel: CrawlTunnel = context.tunnel
	tunnel.active_character = "aster"
	check(tunnel._trigger(false), "finish-signal fixture accepts exact mouth interaction")
	scheduler.advance_ticks(9.1)
	var finish_record: Dictionary = captured.get("authority", {})
	var finish_transaction: Dictionary = (
		finish_record.get("traversals", {}) as Dictionary).get("aster", {})
	check(not captured.is_empty()
			and str(finish_transaction.get("phase", "")) == "carrying"
			and not (captured.snapshot.state.get("external_traversals", {}) as Dictionary).has("aster"),
		"finish signal snapshot captures arrived body before owner cleanup")
	check(tunnel._crawl_traversals.is_empty()
			and state.get_character_concealment("aster") == GameState.CONCEAL_NONE
			and is_equal_approx(float(state.characters.aster.move_speed), 3.0),
		"ordinary finish restores effects and retires transaction")

	var same_finishes := {"count": 0}
	tunnel.crawl_finished.connect(func(_who: String) -> void: same_finishes.count += 1)
	_restore_same(context, captured.snapshot)
	tunnel.on_game_state_snapshot_restored()
	check(int(same_finishes.count) == 1 and tunnel._crawl_traversals.is_empty()
			and state.get_character_concealment("aster") == GameState.CONCEAL_NONE
			and is_equal_approx(float(state.characters.aster.move_speed), 3.0),
		"same-instance finish-signal restore reconciles cleanup exactly once")

	var fresh := await _make_fresh_crawl(
		"crawl_finish_signal", captured.snapshot, ["aster"], false)
	var fresh_tunnel: CrawlTunnel = fresh.tunnel
	var fresh_finishes := {"count": 0}
	fresh_tunnel.crawl_finished.connect(func(_who: String) -> void: fresh_finishes.count += 1)
	fresh_tunnel.on_game_state_snapshot_restored()
	fresh_tunnel.on_game_state_snapshot_restored()
	check(int(fresh_finishes.count) == 1 and fresh_tunnel._crawl_traversals.is_empty()
			and is_equal_approx(float((fresh.state as GameState).characters.aster.move_speed), 3.0),
		"fresh/idempotent finish restore cannot duplicate or strand traversal effects")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_alignment_prediction_recovery() -> void:
	var context := await _make_alignment_context("alignment_prediction")
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var crossing: AlignmentCrossing = context.tunnel
	crossing._on_interacted()
	check(not crossing._pending_launch and not state.is_moving("aster"),
		"direct Alignment callback cannot create a predicted-window order")
	var captured := {}
	state.movement_started.connect(func(_id: String) -> void:
		if not captured.is_empty():
			return
		captured["authority"] = (
			state.get_world_state(crossing._crawl_authority_key(), {}) as Dictionary).duplicate(true)
		captured["snapshot"] = _snapshot(scheduler, state)
	)
	crossing.active_character = "aster"
	check(crossing._trigger(false), "closed Alignment mouth accepts exact source receipt")
	var record: Dictionary = captured.get("authority", {})
	var alignment: Dictionary = record.get("alignment", {})
	var phase: Dictionary = (record.get("phases", {}) as Dictionary).get(
		"alignment_launch", {})
	check(not captured.is_empty() and bool(alignment.get("pending", false))
			and alignment.get("group", []) == ["aster", "peris"]
			and is_equal_approx(float(phase.get("deadline", -1.0)), 5.05),
		"lineup movement signal sees predicted window/group transaction already published")

	var same_starts := {"count": 0}
	crossing.crawl_started.connect(func(_who: String) -> void: same_starts.count += 1)
	_restore_same(context, captured.snapshot)
	crossing.on_game_state_snapshot_restored()
	scheduler.advance_ticks(5.051)
	check(not crossing._pending_launch and crossing._queue == ["aster", "peris"],
		"same-instance restore releases the exact saved group at predicted window")
	scheduler.advance_ticks(0.5)
	check(int(same_starts.count) == 1,
		"same-instance predicted order starts its lead traversal once")

	var fresh := await _make_fresh_alignment(
		"alignment_prediction", captured.snapshot, ["aster", "peris"], false)
	var fresh_crossing: AlignmentCrossing = fresh.tunnel
	var fresh_starts := {"count": 0}
	fresh_crossing.crawl_started.connect(func(_who: String) -> void: fresh_starts.count += 1)
	fresh_crossing.on_game_state_snapshot_restored()
	fresh_crossing.on_game_state_snapshot_restored()
	(fresh.scheduler as EventScheduler).advance_ticks(5.551)
	check(int(fresh_starts.count) == 1 and not fresh_crossing._pending_launch,
		"fresh/idempotent predicted-window restore launches once")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_static_contracts() -> void:
	var alignment_source := FileAccess.get_file_as_string(
		"res://scripts/game/objects/alignment_crossing.gd")
	var schedule_at := alignment_source.find(
		"_schedule_crawl_phase(\"alignment_launch\", _launch_deadline)")
	var lineup_at := alignment_source.find("var slots := compute_queue_slots(group)")
	check(schedule_at >= 0 and lineup_at > schedule_at
			and not alignment_source.contains("start_group_crawl(group)")
			and not alignment_source.contains("_begin_crawl(str(group"),
		"Alignment source publishes prediction before lineup and has no authority bypass")
	var crawl_source := FileAccess.get_file_as_string(
		"res://scripts/game/objects/crawl_tunnel.gd")
	check(crawl_source.contains("command_external_path_traversal")
			and crawl_source.contains("\"data_path\": _portable_path(data_path)")
			and crawl_source.contains("func start_group_crawl(ids: Array) -> bool:"),
		"Crawl source commits canonical path state and explicitly retires legacy helper")
	var game_state_source := FileAccess.get_file_as_string(
		"res://scripts/system/core/game_state.gd")
	check(game_state_source.contains("func command_external_path_traversal(")
			and game_state_source.contains("\"trigger_count\""),
		"GameState owns waypoint traversal and repeatable acceptance identity")


func _make_crawl_context(
		stable_id: String,
		selected: Array = ["aster"],
		one_shot := false,
		finish_capture: Variant = null
	) -> Dictionary:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("aster", Vector3.ZERO, 3.0, {"hp": 100.0})
	state.register_character("peris", Vector3(0.0, 0.0, -1.0), 3.0, {"hp": 100.0})
	state.register_interactable({
		"id": stable_id,
		"position": Vector3.ZERO,
		"requires_hold": false,
		"one_shot": one_shot,
		"radius": 1.4,
	})
	if finish_capture is Dictionary:
		var holder := finish_capture as Dictionary
		state.external_traversal_finished.connect(
			func(id: String, _traversal_id: StringName) -> void:
				if id != "aster" or not holder.is_empty():
					return
				holder["authority"] = (
					state.get_world_state(
						"runtime:crawl_tunnel:" + stable_id, {}) as Dictionary).duplicate(true)
				holder["snapshot"] = _snapshot(scheduler, state)
		)
	var host := Node3D.new()
	root.add_child(host)
	var tunnel := CrawlTunnel.new()
	tunnel.name = "Crawl_" + stable_id
	tunnel.configure(state, Vector3.ZERO, WAYPOINTS, 1.4, 1.0)
	tunnel.bind_data(state, stable_id)
	tunnel.set_scheduler(scheduler)
	tunnel.set_movement_authority(state)
	var selected_copy := selected.duplicate()
	tunnel.set_group_provider(func() -> Array: return selected_copy.duplicate())
	host.add_child(tunnel)
	await process_frame
	return {"scheduler": scheduler, "state": state, "tunnel": tunnel, "host": host}


func _make_alignment_context(stable_id: String) -> Dictionary:
	var context := await _make_crawl_context(stable_id, ["aster", "peris"])
	var old_tunnel: CrawlTunnel = context.tunnel
	old_tunnel.queue_free()
	await process_frame
	var crossing := AlignmentCrossing.new()
	crossing.name = "Alignment_" + stable_id
	crossing.configure(context.state, Vector3.ZERO, WAYPOINTS, 1.4, 1.0)
	crossing.bind_data(context.state, stable_id)
	crossing.set_scheduler(context.scheduler)
	crossing.set_movement_authority(context.state)
	crossing.set_group_provider(func() -> Array: return ["aster", "peris"])
	crossing.set_window_gate(
		func(tick: float) -> bool: return tick >= 5.0 and tick < 6.0,
		func(tick: float) -> float: return 5.0 if tick <= 5.0 else -1.0)
	(context.host as Node).add_child(crossing)
	await process_frame
	context.tunnel = crossing
	return context


func _make_fresh_crawl(
		stable_id: String, snapshot: Dictionary, selected: Array, restore_now := true
	) -> Dictionary:
	var context := _make_loaded_base(snapshot)
	var tunnel := CrawlTunnel.new()
	tunnel.name = "FreshCrawl_" + stable_id
	tunnel.configure(context.state, Vector3.ZERO, WAYPOINTS, 1.4, 1.0)
	tunnel.bind_data(context.state, stable_id)
	tunnel.set_scheduler(context.scheduler)
	tunnel.set_movement_authority(context.state)
	var selected_copy := selected.duplicate()
	tunnel.set_group_provider(func() -> Array: return selected_copy.duplicate())
	(context.host as Node).add_child(tunnel)
	await process_frame
	context.tunnel = tunnel
	if restore_now:
		tunnel.on_game_state_snapshot_restored()
	return context


func _make_fresh_alignment(
		stable_id: String, snapshot: Dictionary, selected: Array, restore_now := true
	) -> Dictionary:
	var context := _make_loaded_base(snapshot)
	var crossing := AlignmentCrossing.new()
	crossing.name = "FreshAlignment_" + stable_id
	crossing.configure(context.state, Vector3.ZERO, WAYPOINTS, 1.4, 1.0)
	crossing.bind_data(context.state, stable_id)
	crossing.set_scheduler(context.scheduler)
	crossing.set_movement_authority(context.state)
	var selected_copy := selected.duplicate()
	crossing.set_group_provider(func() -> Array: return selected_copy.duplicate())
	crossing.set_window_gate(
		func(tick: float) -> bool: return tick >= 5.0 and tick < 6.0,
		func(tick: float) -> float: return 5.0 if tick <= 5.0 else -1.0)
	(context.host as Node).add_child(crossing)
	await process_frame
	context.tunnel = crossing
	if restore_now:
		crossing.on_game_state_snapshot_restored()
	return context


func _make_loaded_base(snapshot: Dictionary) -> Dictionary:
	var scheduler := EventScheduler.new()
	scheduler.deserialize(snapshot.scheduler)
	var state := GameState.new()
	state.scheduler = scheduler
	state.deserialize(snapshot.state)
	var host := Node3D.new()
	root.add_child(host)
	return {"scheduler": scheduler, "state": state, "host": host}


func _restore_same(context: Dictionary, snapshot: Dictionary) -> void:
	var scheduler: EventScheduler = context.scheduler
	scheduler.clear()
	scheduler.deserialize(snapshot.scheduler)
	(context.state as GameState).deserialize(snapshot.state)
	(context.tunnel as CrawlTunnel).on_game_state_snapshot_restored()


func _snapshot(scheduler: EventScheduler, state: GameState) -> Dictionary:
	return {
		"scheduler": _json_round_trip(scheduler.serialize()),
		"state": _json_round_trip(state.serialize()),
	}


func _discard_context(context: Dictionary) -> void:
	var host: Node = context.get("host")
	if host != null and is_instance_valid(host):
		host.queue_free()
	await process_frame


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
