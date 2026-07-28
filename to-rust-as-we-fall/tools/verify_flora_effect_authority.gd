extends SceneTree

## Mid-window save/load and rollback exploit regression for the reusable effect flora. Flure and
## Hushbloom must resume absolute deadlines on both the same node and a fresh presenter; restoration
## must never re-apply a lure/stun or preserve a picked/spent state from a discarded future.

const FlureScript := preload("res://scripts/game/objects/flure.gd")
const HushbloomScript := preload("res://scripts/game/objects/hushbloom.gd")

const FLURE_ORIGIN := Vector3(4.0, 0.0, 4.0)
const HUSH_ORIGIN := Vector3(12.0, 0.0, 4.0)

var _checks := 0
var _failures := 0


class FakeLureTarget:
	extends Node3D
	var char_id := "watcher"
	var game_state: GameState
	var lure_calls := 0
	var last_settle := Vector3.ZERO
	var last_duration := 0.0
	var availability := "available"
	var before_lure := Callable()
	var after_lure := Callable()

	func get_lure_availability() -> String:
		return availability

	func lure_to(settle: Vector3, duration: float, _source_context := {}) -> bool:
		if availability != "available" or game_state == null \
				or not game_state.characters.has(char_id):
			return false
		lure_calls += 1
		last_settle = settle
		last_duration = duration
		if before_lure.is_valid():
			before_lure.call(self)
		game_state.set_character_distracted(char_id, true)
		var accepted := game_state.command_move_to_pos(char_id, settle)
		if after_lure.is_valid():
			after_lure.call(self)
		return accepted

	func reset_target(position: Vector3) -> void:
		availability = "available"
		if game_state == null or not game_state.characters.has(char_id):
			return
		game_state.command_stop(char_id)
		game_state.set_character_distracted(char_id, false)
		game_state.snap_character_to(char_id, position)


class FakeEnemy:
	extends Node3D
	var char_id := "hush_enemy"
	var stun_calls := 0
	var last_stun_secs := 0.0

	func stun(duration: float) -> void:
		stun_calls += 1
		last_stun_secs = duration


class FakePortal:
	extends Node3D
	var stun_calls := 0
	var last_stun_secs := 0.0

	func stun(duration: float) -> void:
		stun_calls += 1
		last_stun_secs = duration

	func authority_state_key() -> String:
		return "gameplay:portal_pad:flora_verifier"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_flure_midpoint_and_rollback()
	await _verify_flure_accepted_source_seam()
	await _verify_flure_target_receipt_seams()
	await _verify_hushbloom_midpoint_and_rollback()
	_verify_hushbloom_strict_future_boundary()
	await _verify_hushbloom_poll_cadence()
	print("FLORA EFFECT AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_hushbloom_strict_future_boundary() -> void:
	var bloom := HushbloomScript.new()
	check(is_equal_approx(float(bloom.call("_next_poll_deadline", 0.1, 0.35)), 0.6),
		"Hushbloom fractional epoch reconstructs the next strict-future proximity poll, not now")
	bloom.free()


func _verify_flure_midpoint_and_rollback() -> void:
	var scheduler := EventScheduler.new()
	var state := _make_state(scheduler)
	state.register_character("peris", FLURE_ORIGIN, 2.0,
		{"hp": 100.0, "narrative_available": true})
	state.register_character("aster", FLURE_ORIGIN + Vector3(30.0, 0.0, 0.0), 2.0,
		{"hp": 100.0, "narrative_available": true})
	state.register_character("watcher", FLURE_ORIGIN + Vector3(1.0, 0.0, 0.0), 2.0,
		{"hp": 100.0, "narrative_available": true})
	var target := FakeLureTarget.new()
	target.game_state = state
	root.add_child(target)
	var flure := _make_flure(state, target)
	root.add_child(flure)
	await process_frame

	var ready_scheduler := _json_round_trip(scheduler.serialize())
	var ready_state := _json_round_trip(state.serialize())
	check(flure.authority_state_key() == "gameplay:flure:verify_flure",
		"Flure authored identity produces a stable fresh-node key")
	check(str(flure.get_effect_state().get("phase", "")) == "ready",
		"Flure begins from authoritative READY state")
	check(not flure.activate() and target.lure_calls == 0,
		"direct Flure consequence helper is an inert compatibility seam")
	flure.active_character = "aster"
	check(not bool(flure.call("_trigger", false))
			and _flure_source_count(state, flure) == 0 and target.lure_calls == 0,
		"a remote selected portrait cannot substitute for its body at the exact Flure")
	state.command_move_to_pos("peris", FLURE_ORIGIN + Vector3(5.0, 0.0, 0.0))
	flure.active_character = "peris"
	check(not bool(flure.call("_trigger", false))
			and _flure_source_count(state, flure) == 0 and target.lure_calls == 0,
		"a moving body cannot spend a Flure while its action is still in flight")
	state.snap_character_to("peris", FLURE_ORIGIN)
	target.availability = "committed"
	check(not bool(flure.call("_trigger", false))
			and _flure_source_count(state, flure) == 0 and target.lure_calls == 0,
		"target preflight rejects an unavailable pack without spending the physical source")
	target.availability = "available"
	check(_stage_and_trigger_flure(flure, state, "peris") and target.lure_calls == 1,
		"the exact action-free body and bound source commit the lure exactly once")
	var committed := flure.get_effect_state()
	var effect: Dictionary = committed.get("last_effect", {}) as Dictionary
	var source_spec := state.get_interactable(flure.get_source_interactable_id())
	check(str(committed.get("contract", "")) == "flure/v2"
			and str(committed.get("phase", "")) == "active"
			and is_equal_approx(float(committed.get("end_tick", -1.0)), 10.0)
			and (effect.get("pulled_ids", []) as Array) == ["watcher"]
			and str(((committed.get("target_receipts", {}) as Dictionary).get(
				"watcher", {}) as Dictionary).get("status", "")) == "applied"
			and int(source_spec.get("trigger_count", 0)) == 1
			and str(source_spec.get("last_trigger_character", "")) == "peris",
		"GameState owns the accepted source nonce, full plan, target receipt, and lure window")
	var replayed_flure := GameState.replay(
		EventLog.from_bytes(state.event_log.to_bytes()), null)
	var replayed_flure_state: Dictionary = replayed_flure.get_world_state(
		flure.authority_state_key(), {})
	check(str(replayed_flure_state.get("phase", "")) == "active"
			and ((replayed_flure_state.get("last_effect", {}) as Dictionary).get(
				"pulled_ids", []) as Array) == ["watcher"],
		"event replay reconstructs the committed Flure window and target context without a node")

	scheduler.advance_ticks(3.0)
	state.flush_tick()
	var midpoint_scheduler := _json_round_trip(scheduler.serialize())
	var midpoint_state := _json_round_trip(state.serialize())

	# Same-node reload after running into a discarded future. Reattachment must not call lure_to again.
	scheduler.advance_ticks(7.0)
	check(not flure.is_active(), "source Flure naturally rearms at its absolute deadline")
	scheduler.clear()
	scheduler.deserialize(midpoint_scheduler)
	state.deserialize(midpoint_state)
	flure.on_game_state_snapshot_restored()
	var restored := flure.get_effect_state()
	check(flure.is_active() and is_equal_approx(float(restored.get("remaining", -1.0)), 7.0)
			and target.lure_calls == 1,
		"same-node load restores only the saved remainder without replaying the lure")
	scheduler.advance_ticks(6.99)
	check(flure.is_active(), "same-node restored Flure cannot rearm early")
	scheduler.advance_ticks(0.01)
	check(not flure.is_active() and target.lure_calls == 1,
		"same-node restored Flure rearms once at the original deadline")

	# Roll back a second active timeline to the pre-activation snapshot. Its callback must disappear.
	target.reset_target(FLURE_ORIGIN + Vector3(1.0, 0.0, 0.0))
	check(_stage_and_trigger_flure(flure, state, "peris") and target.lure_calls == 2
			and _flure_source_count(state, flure) == 2,
		"a repeatable Flure consumes a new monotonic source nonce for a later window")
	scheduler.clear()
	scheduler.deserialize(ready_scheduler)
	state.deserialize(ready_state)
	flure.on_game_state_snapshot_restored()
	check(not flure.is_active() and str(flure.get_effect_state().get("phase", "")) == "ready",
		"rollback retracts a future active Flure immediately")
	scheduler.advance_ticks(25.0)
	check(not flure.is_active() and target.lure_calls == 2,
		"discarded Flure callbacks cannot relure or mutate the rolled-back state")

	# A completely fresh node resolves the midpoint record by stable ID and resumes the same deadline.
	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(midpoint_scheduler)
	var loaded_state := _make_state(loaded_scheduler)
	loaded_state.deserialize(midpoint_state)
	var loaded_target := FakeLureTarget.new()
	loaded_target.game_state = loaded_state
	root.add_child(loaded_target)
	var loaded := _make_flure(loaded_state, loaded_target)
	root.add_child(loaded)
	await process_frame
	var fresh := loaded.get_effect_state()
	check(loaded.is_active() and is_equal_approx(float(fresh.get("remaining", -1.0)), 7.0)
			and loaded_target.lure_calls == 0,
		"fresh Flure presenter resumes midpoint state without duplicating target effects")
	loaded_scheduler.advance_ticks(6.99)
	check(loaded.is_active(), "fresh Flure presenter retains the saved active window")
	loaded_scheduler.advance_ticks(0.01)
	check(not loaded.is_active() and loaded_target.lure_calls == 0,
		"fresh Flure presenter rearms once after only the saved remainder")

	scheduler.clear()
	loaded_scheduler.clear()
	flure.queue_free()
	loaded.queue_free()
	target.queue_free()
	loaded_target.queue_free()
	await process_frame


func _verify_flure_accepted_source_seam() -> void:
	var scheduler := EventScheduler.new()
	var state := _make_state(scheduler)
	state.register_character("peris", FLURE_ORIGIN, 2.0,
		{"hp": 100.0, "narrative_available": true})
	state.register_character("watcher", FLURE_ORIGIN + Vector3(1.0, 0.0, 0.0), 2.0,
		{"hp": 100.0, "narrative_available": true})
	var target := FakeLureTarget.new()
	target.game_state = state
	root.add_child(target)
	var flure := _make_flure(state, target, "verify_flure_source_seam")
	root.add_child(flure)
	await process_frame

	var signal_snapshot := {"scheduler": {}, "state": {}, "count": 0}
	state.interactable_triggered.connect(func(id: String, actor: String) -> void:
		if id != flure.get_source_interactable_id() or actor != "peris" \
				or int(signal_snapshot["count"]) > 0:
			return
		signal_snapshot["count"] = 1
		signal_snapshot["scheduler"] = _json_round_trip(scheduler.serialize())
		signal_snapshot["state"] = _json_round_trip(state.serialize()))
	check(_stage_and_trigger_flure(flure, state, "peris")
			and int(signal_snapshot["count"]) == 1 and target.lure_calls == 1,
		"accepted-source signal captures the exact pre-owner receipt seam")

	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(signal_snapshot["scheduler"])
	var loaded_state := _make_state(loaded_scheduler)
	loaded_state.deserialize(signal_snapshot["state"])
	var loaded_target := FakeLureTarget.new()
	loaded_target.game_state = loaded_state
	root.add_child(loaded_target)
	var loaded := _make_flure(loaded_state, loaded_target, "verify_flure_source_seam")
	root.add_child(loaded)
	await process_frame
	var restored := loaded.get_effect_state()
	var source_spec := loaded_state.get_interactable(loaded.get_source_interactable_id())
	check(str(restored.get("phase", "")) == "ready"
			and (restored.get("pending_source_receipt", {}) as Dictionary).is_empty()
			and int(source_spec.get("trigger_count", 0)) == 1
			and loaded_state.is_interactable_enabled(loaded.get_source_interactable_id())
			and not loaded_state.is_character_distracted("watcher")
			and loaded_target.lure_calls == 0,
		"an accepted trigger without an owner commit is consumed and rearmed without inventing an effect")
	check(_stage_and_trigger_flure(loaded, loaded_state, "peris")
			and _flure_source_count(loaded_state, loaded) == 2
			and loaded_target.lure_calls == 1,
		"retry consumes the next monotonic source nonce after an orphan receipt")

	scheduler.clear()
	loaded_scheduler.clear()
	flure.queue_free()
	loaded.queue_free()
	target.queue_free()
	loaded_target.queue_free()
	await process_frame


func _verify_flure_target_receipt_seams() -> void:
	var scheduler := EventScheduler.new()
	var state := _make_state(scheduler)
	state.register_character("peris", FLURE_ORIGIN, 2.0,
		{"hp": 100.0, "narrative_available": true})
	state.register_character("watcher_a", FLURE_ORIGIN + Vector3(1.0, 0.0, 0.0), 2.0,
		{"hp": 100.0, "narrative_available": true})
	state.register_character("watcher_b", FLURE_ORIGIN + Vector3(-1.0, 0.0, 0.0), 2.0,
		{"hp": 100.0, "narrative_available": true})
	var targets := _make_lure_targets(state, ["watcher_a", "watcher_b"])
	var target_a := targets["watcher_a"] as FakeLureTarget
	var target_b := targets["watcher_b"] as FakeLureTarget
	var flure := _make_flure_targets(
		state, targets, ["watcher_a", "watcher_b"], "verify_flure_target_seams")
	root.add_child(flure)
	await process_frame

	var pre_effect_snapshot := {"scheduler": {}, "state": {}, "count": 0}
	var post_effect_snapshot := {"scheduler": {}, "state": {}, "count": 0}
	var completed_snapshot := {"scheduler": {}, "state": {}, "count": 0}
	target_a.before_lure = func(_target: FakeLureTarget) -> void:
		if int(pre_effect_snapshot["count"]) > 0:
			return
		pre_effect_snapshot["count"] = 1
		pre_effect_snapshot["scheduler"] = _json_round_trip(scheduler.serialize())
		pre_effect_snapshot["state"] = _json_round_trip(state.serialize())
	state.movement_started.connect(func(id: String) -> void:
		if id != "watcher_a" or int(post_effect_snapshot["count"]) > 0:
			return
		post_effect_snapshot["count"] = 1
		post_effect_snapshot["scheduler"] = _json_round_trip(scheduler.serialize())
		post_effect_snapshot["state"] = _json_round_trip(state.serialize()))
	flure.flure_activated.connect(func(_pulled: int) -> void:
		if int(completed_snapshot["count"]) > 0:
			return
		completed_snapshot["count"] = 1
		completed_snapshot["scheduler"] = _json_round_trip(scheduler.serialize())
		completed_snapshot["state"] = _json_round_trip(state.serialize()))
	check(_stage_and_trigger_flure(flure, state, "peris")
			and target_a.lure_calls == 1 and target_b.lure_calls == 1
			and int(pre_effect_snapshot["count"]) == 1
			and int(post_effect_snapshot["count"]) == 1
			and int(completed_snapshot["count"]) == 1,
		"a two-target activation exposes pre-effect, effect-signal, and completed save seams")

	var pre_pair := await _load_flure_target_snapshot(
		pre_effect_snapshot, "verify_flure_target_seams")
	var pre_loaded := pre_pair["flure"] as Flure
	var pre_scheduler := pre_pair["scheduler"] as EventScheduler
	var pre_targets := pre_pair["targets"] as Dictionary
	pre_loaded.on_game_state_snapshot_restored()
	pre_loaded.on_game_state_snapshot_restored()
	pre_scheduler.advance_ticks(0.001)
	check((pre_targets["watcher_a"] as FakeLureTarget).lure_calls == 1
			and (pre_targets["watcher_b"] as FakeLureTarget).lure_calls == 1
			and str(pre_loaded.get_effect_state().get("phase", "")) == "active",
		"a pre-effect save resumes each unpaid receipt once despite repeated restore hooks")

	var post_pair := await _load_flure_target_snapshot(
		post_effect_snapshot, "verify_flure_target_seams")
	var post_loaded := post_pair["flure"] as Flure
	var post_scheduler := post_pair["scheduler"] as EventScheduler
	var post_targets := post_pair["targets"] as Dictionary
	post_loaded.on_game_state_snapshot_restored()
	post_loaded.on_game_state_snapshot_restored()
	post_scheduler.advance_ticks(0.001)
	check((post_targets["watcher_a"] as FakeLureTarget).lure_calls == 0
			and (post_targets["watcher_b"] as FakeLureTarget).lure_calls == 1
			and str(((post_loaded.get_effect_state().get(
				"target_receipts", {}) as Dictionary).get(
					"watcher_a", {}) as Dictionary).get("status", "")) == "applied",
		"a signal-time save reconciles the paid target and resumes only the untouched suffix")
	post_loaded.on_game_state_snapshot_restored()
	post_scheduler.advance_ticks(0.01)
	check((post_targets["watcher_a"] as FakeLureTarget).lure_calls == 0
			and (post_targets["watcher_b"] as FakeLureTarget).lure_calls == 1,
		"completed target receipts remain idempotent across later restore hooks")

	var completed_pair := await _load_flure_target_snapshot(
		completed_snapshot, "verify_flure_target_seams")
	var completed_loaded := completed_pair["flure"] as Flure
	var completed_scheduler := completed_pair["scheduler"] as EventScheduler
	var completed_targets := completed_pair["targets"] as Dictionary
	completed_loaded.on_game_state_snapshot_restored()
	completed_scheduler.advance_ticks(0.01)
	check((completed_targets["watcher_a"] as FakeLureTarget).lure_calls == 0
			and (completed_targets["watcher_b"] as FakeLureTarget).lure_calls == 0
			and str(completed_loaded.get_effect_state().get("phase", "")) == "active",
		"a post-completion save restores the committed window without replaying either target")

	# Same-node rollback from the completed future follows the same receipt ledger: A's canonical
	# movement survives in the snapshot, while B's not-yet-published suffix is the only reapplied call.
	scheduler.clear()
	scheduler.deserialize(post_effect_snapshot["scheduler"])
	state.deserialize(post_effect_snapshot["state"])
	flure.on_game_state_snapshot_restored()
	flure.on_game_state_snapshot_restored()
	scheduler.advance_ticks(0.001)
	check(target_a.lure_calls == 1 and target_b.lure_calls == 2,
		"same-node rollback also resumes only the unpaid target suffix")

	scheduler.clear()
	for pair_v in [pre_pair, post_pair, completed_pair]:
		var loaded_pair := pair_v as Dictionary
		(loaded_pair["scheduler"] as EventScheduler).clear()
		(loaded_pair["flure"] as Flure).queue_free()
		for target_v in (loaded_pair["targets"] as Dictionary).values():
			(target_v as FakeLureTarget).queue_free()
	flure.queue_free()
	for target_v in targets.values():
		(target_v as FakeLureTarget).queue_free()
	await process_frame


func _verify_hushbloom_midpoint_and_rollback() -> void:
	var scheduler := EventScheduler.new()
	var state := _make_state(scheduler)
	state.register_character("peris", HUSH_ORIGIN + Vector3(8.0, 0.0, 0.0), 2.0,
		{"hp": 100.0, "narrative_available": true})
	var enemy := FakeEnemy.new()
	enemy.position = HUSH_ORIGIN + Vector3(1.0, 0.0, 0.0)
	root.add_child(enemy)
	var portal := FakePortal.new()
	portal.position = HUSH_ORIGIN + Vector3(-1.0, 0.0, 0.0)
	root.add_child(portal)
	var bloom := _make_hushbloom(state, enemy, portal)
	root.add_child(bloom)
	await process_frame

	var charged_scheduler := _json_round_trip(scheduler.serialize())
	var charged_state := _json_round_trip(state.serialize())
	check(bloom.authority_state_key() == "gameplay:hushbloom:verify_hushbloom",
		"Hushbloom authored identity produces a stable fresh-node key")
	check(bloom.burst("bait") and enemy.stun_calls == 1 and portal.stun_calls == 1,
		"Hushbloom applies each in-range effect exactly once")
	var committed := bloom.get_effect_state()
	var context: Dictionary = committed.get("last_effect", {}) as Dictionary
	check(str(committed.get("contract", "")) == "hushbloom/v2"
			and str(committed.get("phase", "")) == "recharging"
			and is_equal_approx(float(committed.get("recharge_tick", -1.0)), 10.0)
			and (context.get("enemy_ids", []) as Array) == ["hush_enemy"]
			and (context.get("portal_ids", []) as Array) == ["gameplay:portal_pad:flora_verifier"]
			and str(context.get("trigger_body_id", "")) == "bait"
			and is_equal_approx(float(context.get("effect_end_tick", -1.0)), 6.0),
		"GameState records Hushbloom recharge, trigger, targets, and effect deadline")
	var replayed_hush := GameState.replay(
		EventLog.from_bytes(state.event_log.to_bytes()), null)
	var replayed_hush_state: Dictionary = replayed_hush.get_world_state(
		bloom.authority_state_key(), {})
	check(str(replayed_hush_state.get("phase", "")) == "recharging"
			and (((replayed_hush_state.get("last_effect", {}) as Dictionary).get(
				"enemy_ids", []) as Array) == ["hush_enemy"]),
		"event replay reconstructs Hushbloom recharge and effect targets without a node")

	scheduler.advance_ticks(3.0)
	state.flush_tick()
	var midpoint_scheduler := _json_round_trip(scheduler.serialize())
	var midpoint_state := _json_round_trip(state.serialize())
	scheduler.advance_ticks(7.0)
	check(bloom.is_charged(), "source Hushbloom recharges at its absolute deadline")
	check(bloom.burst("discarded") and enemy.stun_calls == 2 and portal.stun_calls == 2,
		"a later timeline can create effects before rollback")

	# Same-node midpoint restoration cancels that future recharge and never reapplies the saved stun.
	scheduler.clear()
	scheduler.deserialize(midpoint_scheduler)
	state.deserialize(midpoint_state)
	bloom.on_game_state_snapshot_restored()
	var restored := bloom.get_effect_state()
	check(not bloom.is_charged()
			and is_equal_approx(float(restored.get("recharge_remaining", -1.0)), 7.0)
			and enemy.stun_calls == 2 and portal.stun_calls == 2,
		"same-node Hushbloom load resumes recharge without duplicating stun effects")
	scheduler.advance_ticks(6.99)
	check(not bloom.is_charged(), "same-node Hushbloom cannot recharge early")
	scheduler.advance_ticks(0.01)
	check(bloom.is_charged() and enemy.stun_calls == 2 and portal.stun_calls == 2,
		"same-node Hushbloom recharges once after only the saved remainder")

	# Pick, then roll back to the earlier charged snapshot: presentation and gameplay both retract.
	state.snap_character_to("peris", HUSH_ORIGIN)
	bloom.active_character = "peris"
	var pickup_signal_capture := {"scheduler": {}, "state": {}, "count": 0, "item_id": ""}
	state.item_picked_up.connect(func(char_id: String, item_id: String) -> void:
		if char_id != "peris" or not state.items.has(item_id):
			return
		var properties: Dictionary = (state.items[item_id] as Dictionary).get("properties", {})
		if str(properties.get("source_hushbloom", "")) != bloom.authority_state_key():
			return
		pickup_signal_capture["count"] = int(pickup_signal_capture["count"]) + 1
		pickup_signal_capture["item_id"] = item_id
		pickup_signal_capture["scheduler"] = _json_round_trip(scheduler.serialize())
		pickup_signal_capture["state"] = _json_round_trip(state.serialize()))
	check(bloom.pick() and not bloom.visible and not bloom.is_charged(),
		"picking converts the plant into a terminal carried state")
	var carried_id := str(bloom.get_effect_state().get("carried_item_id", ""))
	check(carried_id != "" and state.items.has(carried_id)
			and str((state.items[carried_id] as Dictionary).get("type", "")) == "hushbloom"
			and str((state.items[carried_id] as Dictionary).get("holder", "")) == "peris"
			and str((state.items[carried_id] as Dictionary).get("location", "")) == "hand",
		"picked Hushbloom is a canonical GameState hand item, not a scene counter")
	check(int(pickup_signal_capture.get("count", 0)) == 1
			and str(pickup_signal_capture.get("item_id", "")) == carried_id,
		"item-pickup signal observes one source-tagged physical bloom")
	var picked_scheduler := _json_round_trip(scheduler.serialize())
	var picked_state := _json_round_trip(state.serialize())
	check(state.drop_item("peris", carried_id)
			and str((state.items[carried_id] as Dictionary).get("location", "")) == "ground"
			and not bloom.visible,
		"dropping moves the same bloom item to the ground without regrowing its source plant")
	scheduler.clear()
	scheduler.deserialize(charged_scheduler)
	state.deserialize(charged_state)
	bloom.on_game_state_snapshot_restored()
	check(bloom.is_charged() and bloom.visible and bloom.is_interaction_enabled()
			and state.items.is_empty(),
		"same-node rollback retracts the future item and restores the charged plant")
	scheduler.advance_ticks(20.0)
	check(bloom.is_charged() and bloom.visible,
		"discarded picked/recharge callbacks cannot corrupt the rolled-back plant")

	# Fresh midpoint presenter: no stun is granted again, but the remaining recharge is exact.
	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(midpoint_scheduler)
	var loaded_state := _make_state(loaded_scheduler)
	loaded_state.deserialize(midpoint_state)
	var loaded_enemy := FakeEnemy.new()
	loaded_enemy.position = enemy.position
	root.add_child(loaded_enemy)
	var loaded_portal := FakePortal.new()
	loaded_portal.position = portal.position
	root.add_child(loaded_portal)
	var loaded := _make_hushbloom(loaded_state, loaded_enemy, loaded_portal)
	root.add_child(loaded)
	await process_frame
	var fresh := loaded.get_effect_state()
	check(not loaded.is_charged()
			and is_equal_approx(float(fresh.get("recharge_remaining", -1.0)), 7.0)
			and loaded_enemy.stun_calls == 0 and loaded_portal.stun_calls == 0,
		"fresh Hushbloom presenter resumes midpoint recharge without re-stunning targets")
	loaded_scheduler.advance_ticks(6.99)
	check(not loaded.is_charged(), "fresh Hushbloom presenter preserves the saved empty window")
	loaded_scheduler.advance_ticks(0.01)
	check(loaded.is_charged() and loaded_enemy.stun_calls == 0 and loaded_portal.stun_calls == 0,
		"fresh Hushbloom presenter recharges once at the original deadline")

	# A picked snapshot remains one exact item on another node forever; load cannot manufacture a
	# recharge or duplicate the source bloom.
	var picked_loaded_scheduler := EventScheduler.new()
	picked_loaded_scheduler.deserialize(picked_scheduler)
	var picked_loaded_state := _make_state(picked_loaded_scheduler)
	picked_loaded_state.deserialize(picked_state)
	var picked_loaded := _make_hushbloom(picked_loaded_state, loaded_enemy, loaded_portal)
	root.add_child(picked_loaded)
	await process_frame
	check(not picked_loaded.visible and not picked_loaded.is_charged()
			and str(picked_loaded.get_effect_state().get("phase", "")) == "picked"
			and picked_loaded_state.items.size() == 1
			and picked_loaded_state.get_hand_items("peris").size() == 1,
		"fresh presenter reconstructs one saved picked item and its exact holder")
	picked_loaded_scheduler.advance_ticks(120.0)
	check(not picked_loaded.visible and not picked_loaded.is_charged()
			and picked_loaded_state.items.size() == 1,
		"picked Hushbloom cannot gain a phantom recharge or duplicate item after load")

	# The item_picked_up signal occurs before the source can publish its final item id. Its prior
	# PICKING reservation plus the source tag must still make that signal-time snapshot terminal.
	var seam_scheduler := EventScheduler.new()
	seam_scheduler.deserialize(pickup_signal_capture.get("scheduler", {}) as Dictionary)
	var seam_state := _make_state(seam_scheduler)
	seam_state.deserialize(pickup_signal_capture.get("state", {}) as Dictionary)
	var seam_loaded := _make_hushbloom(seam_state, loaded_enemy, loaded_portal)
	root.add_child(seam_loaded)
	await process_frame
	seam_loaded.active_character = "peris"
	check(str(seam_loaded.get_effect_state().get("phase", "")) == "picking"
			and not seam_loaded.visible and seam_state.items.size() == 1,
		"signal-time restore reconciles PICKING against the source-tagged physical item")
	check(not seam_loaded.pick() and seam_state.items.size() == 1,
		"signal-time restore cannot pick the same plant twice")
	seam_scheduler.advance_ticks(0.0)
	var seam_item_id := str((seam_state.items.keys() as Array)[0])
	check(str(seam_loaded.get_effect_state().get("phase", "")) == "picked"
			and str(seam_loaded.get_effect_state().get("carried_item_id", "")) == seam_item_id
			and seam_state.items.size() == 1,
		"restored PICKING reservation finalizes once without duplicating its item")
	seam_state.remove_item(seam_item_id)
	var spent_seam_scheduler := _json_round_trip(seam_scheduler.serialize())
	var spent_seam_state := _json_round_trip(seam_state.serialize())
	var spent_loaded_scheduler := EventScheduler.new()
	spent_loaded_scheduler.deserialize(spent_seam_scheduler)
	var spent_loaded_state := _make_state(spent_loaded_scheduler)
	spent_loaded_state.deserialize(spent_seam_state)
	var spent_loaded := _make_hushbloom(spent_loaded_state, loaded_enemy, loaded_portal)
	root.add_child(spent_loaded)
	await process_frame
	check(not spent_loaded.visible and not spent_loaded.is_charged()
			and spent_loaded_state.items.is_empty(),
		"saving after pending-item consumption cannot regrow or duplicate its source plant")

	scheduler.clear()
	loaded_scheduler.clear()
	picked_loaded_scheduler.clear()
	seam_scheduler.clear()
	spent_loaded_scheduler.clear()
	bloom.queue_free()
	loaded.queue_free()
	picked_loaded.queue_free()
	seam_loaded.queue_free()
	spent_loaded.queue_free()
	enemy.queue_free()
	portal.queue_free()
	loaded_enemy.queue_free()
	loaded_portal.queue_free()
	await process_frame


func _verify_hushbloom_poll_cadence() -> void:
	var scheduler := EventScheduler.new()
	var state := _make_state(scheduler)
	state.register_character("body", HUSH_ORIGIN, 2.0,
		{"hp": 100.0, "narrative_available": true})
	var source := _make_hushbloom(state, null, null, "verify_hush_poll")
	root.add_child(source)
	await process_frame
	scheduler.advance_ticks(0.10)
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	scheduler.clear()
	source.queue_free()
	await process_frame

	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(saved_scheduler)
	var loaded_state := _make_state(loaded_scheduler)
	loaded_state.deserialize(saved_state)
	var loaded := _make_hushbloom(loaded_state, null, null, "verify_hush_poll")
	root.add_child(loaded)
	await process_frame
	check(is_equal_approx(float(loaded.get_effect_state().get("next_poll_tick", -1.0)), 0.25),
		"fresh charged Hushbloom derives the exact next poll from its saved cadence anchor")
	loaded_scheduler.advance_ticks(0.149)
	check(loaded.is_charged(), "restored proximity poll cannot fire before the original cadence")
	loaded_scheduler.advance_ticks(0.001)
	check(not loaded.is_charged()
			and str(loaded.get_effect_state().get("last_effect", {}).get("trigger_body_id", "")) == "body",
		"restored proximity poll fires once at the original absolute cadence")

	loaded_scheduler.clear()
	loaded.queue_free()
	await process_frame


func _make_state(scheduler: EventScheduler) -> GameState:
	var state := GameState.new()
	state.scheduler = scheduler
	state.event_log = EventLog.new()
	return state


func _make_flure(
		state: GameState,
		target: FakeLureTarget,
		id := "verify_flure"
	) -> Flure:
	target.game_state = state
	return _make_flure_targets(state, {"watcher": target}, ["watcher"], id)


func _make_flure_targets(
		state: GameState,
		targets: Dictionary,
		target_ids: Array,
		id: String
	) -> Flure:
	var flure := FlureScript.new() as Flure
	flure.name = "AuthorityFlurePresenter"
	flure.authority_id = id
	flure.configure(state, FLURE_ORIGIN, target_ids, 20.0, 1.5)
	flure.one_shot = false
	flure.required_character = "peris"
	flure.lure_duration = 10.0
	flure.settle_pos = FLURE_ORIGIN + Vector3(2.0, 0.0, 0.0)
	flure.set_enemy_resolver(func(id: String):
		return targets.get(id))
	return flure


func _make_lure_targets(state: GameState, ids: Array) -> Dictionary:
	var targets := {}
	for id_v in ids:
		var id := str(id_v)
		var target := FakeLureTarget.new()
		target.char_id = id
		target.game_state = state
		root.add_child(target)
		targets[id] = target
	return targets


func _load_flure_target_snapshot(snapshot: Dictionary, id: String) -> Dictionary:
	var scheduler := EventScheduler.new()
	scheduler.deserialize(snapshot.get("scheduler", {}) as Dictionary)
	var state := _make_state(scheduler)
	state.deserialize(snapshot.get("state", {}) as Dictionary)
	var targets := _make_lure_targets(state, ["watcher_a", "watcher_b"])
	var flure := _make_flure_targets(
		state, targets, ["watcher_a", "watcher_b"], id)
	root.add_child(flure)
	await process_frame
	return {
		"scheduler": scheduler,
		"state": state,
		"targets": targets,
		"flure": flure,
	}


func _stage_and_trigger_flure(flure: Flure, state: GameState, actor: String) -> bool:
	if flure == null or not state.characters.has(actor):
		return false
	state.command_stop(actor)
	state.snap_character_to(actor, flure.get_source_data_position())
	flure.active_character = actor
	return bool(flure.call("_trigger", false))


func _flure_source_count(state: GameState, flure: Flure) -> int:
	if flure == null or not state.has_interactable(flure.get_source_interactable_id()):
		return 0
	return int(state.get_interactable(
		flure.get_source_interactable_id()).get("trigger_count", 0))


func _make_hushbloom(state: GameState, enemy, portal, id := "verify_hushbloom") -> Hushbloom:
	var bloom := HushbloomScript.new() as Hushbloom
	bloom.name = "AuthorityHushbloomPresenter"
	bloom.authority_id = id
	bloom.configure(state, HUSH_ORIGIN, {
		"trigger_radius": 1.5,
		"stun_radius": 3.4,
		"stun_secs": 6.0,
		"regen_secs": 10.0,
		"pickable": true,
	})
	bloom.set_enemy_provider(func() -> Array: return [enemy] if enemy != null else [])
	bloom.set_portal_provider(func() -> Array: return [portal] if portal != null else [])
	return bloom


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
