extends SceneTree

## Mid-phase save/load regression for Enemy. Scheduler snapshots restore only the deterministic
## clock, not Callables, so every scenario proves that the stable char-id authority record rebuilds
## one exact callback on both a rolled-back node and a newly-instanced scene presenter.

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_absent_authority_retracts_future_activation()
	await _verify_mid_windup_same_and_fresh()
	await _verify_mid_stun_same_and_fresh()
	await _verify_mid_lure_same_and_fresh()
	await _verify_lure_return_policy_same_and_fresh()
	await _verify_damaged_hp_same_and_fresh()
	await _verify_impact_restore_is_side_effect_free()
	print("ENEMY SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_absent_authority_retracts_future_activation() -> void:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("target", Vector3(1.0, 0.0, 0.0), 3.0, {"hp": 100.0})
	state.register_character("dormant_guard", Vector3.ZERO, 2.0, {"detection_range": 8.0})
	var host := Node3D.new()
	root.add_child(host)
	var enemy := Enemy.new()
	enemy.name = "dormant_guard"
	enemy.char_id = "dormant_guard"
	enemy.game_state = state
	enemy.max_hp = 50.0
	enemy.alert_duration = 1.0
	enemy.windup_duration = 10.0
	enemy.set_detection_targets([])
	host.add_child(enemy)
	await process_frame
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	check(not state.world_state.has(enemy._enemy_authority_key()),
		"pre-activation snapshot contains no invented enemy phase")

	enemy.activate()
	check(enemy.engage_target("target"), "future activation can acquire a target")
	scheduler.advance_ticks(1.0)
	check(enemy.get_state() == "windup", "future activation reaches a timed combat phase")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	check(enemy.get_state() == "idle" and is_equal_approx(enemy.get_hp(), enemy.max_hp)
			and enemy._state_deadlines.is_empty(),
		"authority absence retracts the future phase instead of freezing it")
	check(not bool(state.characters.dormant_guard.stats.get("detection_enabled", true)),
		"a rolled-back uncommitted enemy cannot keep scanning")
	scheduler.advance_ticks(100.0)
	check(enemy.get_state() == "idle", "retracted future callbacks never fire after rollback")
	host.queue_free()
	await process_frame


func _verify_mid_windup_same_and_fresh() -> void:
	var context := await _make_context("windup_guard", true)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: Enemy = context.enemy
	enemy.alert_duration = 1.0
	enemy.windup_duration = 10.0
	check(enemy.engage_target("target"), "windup fixture acquires its stable target")
	scheduler.advance_ticks(1.0)
	check(enemy.get_state() == "windup", "fixture enters windup after its alert")
	scheduler.advance_ticks(3.0)
	var authority: Dictionary = state.get_world_state(enemy._enemy_authority_key(), {})
	check(is_equal_approx(float((authority.deadlines as Dictionary).get("windup_end", -1.0)), 11.0),
		"windup commits its original absolute completion tick")
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())

	# Let the future happen, then load the earlier snapshot onto the same node. Restoring the node is
	# deliberately invoked twice: attachment passes must be idempotent and leave one callback.
	scheduler.advance_ticks(7.0)
	check(enemy.get_state() == "charge", "future windup completes before rollback")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	enemy.on_game_state_snapshot_restored()
	check(enemy.get_state() == "windup", "same-node rollback retracts the future charge phase")
	var before_same_charge := int(Enemy.CALLS.get("enter_charge", 0))
	scheduler.advance_ticks(6.99)
	check(enemy.get_state() == "windup", "same-node windup cannot finish before saved deadline")
	scheduler.advance_ticks(0.01)
	check(enemy.get_state() == "charge"
			and int(Enemy.CALLS.get("enter_charge", 0)) == before_same_charge + 1,
		"same-node windup re-arms exactly one transition at saved deadline")

	var fresh := await _make_fresh_from_snapshot(
		"windup_guard", saved_scheduler, saved_state, true)
	var fresh_scheduler: EventScheduler = fresh.scheduler
	var fresh_enemy: Enemy = fresh.enemy
	check(fresh_enemy.get_state() == "windup"
			and fresh_enemy._current_target_id == "target",
		"fresh presenter restores windup and target context by char id")
	var before_fresh_charge := int(Enemy.CALLS.get("enter_charge", 0))
	fresh_scheduler.advance_ticks(6.99)
	check(fresh_enemy.get_state() == "windup", "fresh windup preserves the saved remainder")
	fresh_scheduler.advance_ticks(0.01)
	check(fresh_enemy.get_state() == "charge"
			and int(Enemy.CALLS.get("enter_charge", 0)) == before_fresh_charge + 1,
		"fresh windup completes once at the original deadline")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_mid_stun_same_and_fresh() -> void:
	var context := await _make_context("stun_guard", false)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: Enemy = context.enemy
	enemy.stun(10.0)
	scheduler.advance_ticks(4.0)
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	check(enemy.get_state() == "stunned" and enemy.is_stunned(),
		"stun remains authoritative at its midpoint")

	scheduler.advance_ticks(6.0)
	check(enemy.get_state() == "return", "future stun expires before rollback")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	check(enemy.get_state() == "stunned", "same-node rollback restores the stun phase")
	scheduler.advance_ticks(5.99)
	check(enemy.get_state() == "stunned", "same-node stun cannot be shortened by loading")
	scheduler.advance_ticks(0.01)
	check(enemy.get_state() == "return", "same-node stun expires at its original tick")

	var fresh := await _make_fresh_from_snapshot(
		"stun_guard", saved_scheduler, saved_state, false)
	var fresh_scheduler: EventScheduler = fresh.scheduler
	var fresh_enemy: Enemy = fresh.enemy
	check(fresh_enemy.get_state() == "stunned" and fresh_enemy._stun_duration == 10.0,
		"fresh presenter restores stun phase and duration context")
	fresh_scheduler.advance_ticks(5.99)
	check(fresh_enemy.get_state() == "stunned", "fresh stun preserves its saved remainder")
	fresh_scheduler.advance_ticks(0.01)
	check(fresh_enemy.get_state() == "return", "fresh stun expires exactly once")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_mid_lure_same_and_fresh() -> void:
	var context := await _make_context("lure_guard", false)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: Enemy = context.enemy
	var settle := Vector3(5.0, 0.0, 1.0)
	check(enemy.lure_to(settle, 10.0), "lure fixture accepts the intervention")
	scheduler.advance_ticks(2.0)
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	check(enemy.get_state() == "lured" and state.is_character_distracted("lure_guard"),
		"mid-lure phase and distracted detector state are committed")

	scheduler.advance_ticks(8.0)
	check(enemy.get_state() == "return", "future lure expires before rollback")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	check(enemy.get_state() == "lured" and enemy._lure_settle.is_equal_approx(settle)
			and state.is_character_distracted("lure_guard"),
		"same-node rollback restores lure target and distracted state")
	scheduler.advance_ticks(7.99)
	check(enemy.get_state() == "lured", "same-node lure cannot be skipped by loading")
	scheduler.advance_ticks(0.01)
	check(enemy.get_state() == "return" and not state.is_character_distracted("lure_guard"),
		"same-node lure ends once at its original deadline")

	var fresh := await _make_fresh_from_snapshot(
		"lure_guard", saved_scheduler, saved_state, false)
	var fresh_scheduler: EventScheduler = fresh.scheduler
	var fresh_state: GameState = fresh.state
	var fresh_enemy: Enemy = fresh.enemy
	check(fresh_enemy.get_state() == "lured"
			and fresh_enemy._lure_settle.is_equal_approx(settle)
			and fresh_state.is_character_distracted("lure_guard"),
		"fresh presenter restores lure context without replaying its movement command")
	var saved_lure_pos := fresh_state.get_render_position("lure_guard")
	check(Vector2(fresh_enemy.global_position.x, fresh_enemy.global_position.z).is_equal_approx(
			Vector2(saved_lure_pos.x, saved_lure_pos.z)),
		"fresh presenter mirrors the saved data-layer position immediately")
	fresh_scheduler.advance_ticks(7.99)
	check(fresh_enemy.get_state() == "lured", "fresh lure preserves its saved remainder")
	fresh_scheduler.advance_ticks(0.01)
	check(fresh_enemy.get_state() == "return"
			and not fresh_state.is_character_distracted("lure_guard"),
		"fresh lure expires exactly once")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_lure_return_policy_same_and_fresh() -> void:
	var context := await _make_context("return_policy_guard", false)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: Enemy = context.enemy
	enemy._post_position = Vector3(1.0, 0.0, 0.0)
	state.snap_character_to("return_policy_guard", enemy._post_position)
	enemy.set_lure_return_policy(true, 3.0)
	check(enemy.lure_to(Vector3(5.0, 0.0, 0.0), 3.0, {
			"source_key": "gameplay:flure:return_policy_fixture",
			"activation_serial": 7,
		}), "return-policy fixture accepts the exact-source lure")
	scheduler.advance_ticks(3.0)
	check(enemy.get_state() == "return"
			and state.is_character_distracted("return_policy_guard"),
		"song expiry begins a physical return while the authored reduced watch remains")
	scheduler.advance_ticks(0.25)
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	var authority: Dictionary = state.get_world_state(enemy._enemy_authority_key(), {})
	check(bool(authority.get("lure_returning_from_song", false))
			and bool(authority.get("lure_return_keeps_distraction", false))
			and is_equal_approx(float(authority.get("lure_return_speed", -1.0)), 3.0)
			and str(authority.get("lure_source_key", ""))
				== "gameplay:flure:return_policy_fixture"
			and int(authority.get("lure_source_activation_serial", 0)) == 7,
		"mid-return save records policy, exact source provenance, and physical phase")
	scheduler.advance_ticks(2.0)
	check(enemy.get_state() == "idle"
			and not state.is_character_distracted("return_policy_guard"),
		"finishing the real return restores the full watch")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	check(enemy.get_state() == "return"
			and state.is_character_distracted("return_policy_guard"),
		"same-node rollback restores the still-distracted return leg")
	scheduler.advance_ticks(2.0)
	check(enemy.get_state() == "idle"
			and not state.is_character_distracted("return_policy_guard"),
		"same-node restored return finishes once and clears its policy surface")

	var fresh := await _make_fresh_from_snapshot(
		"return_policy_guard", saved_scheduler, saved_state, false)
	var fresh_scheduler: EventScheduler = fresh.scheduler
	var fresh_state: GameState = fresh.state
	var fresh_enemy: Enemy = fresh.enemy
	check(fresh_enemy.get_state() == "return"
			and fresh_state.is_character_distracted("return_policy_guard")
			and fresh_enemy.lure_return_keeps_distraction
			and is_equal_approx(fresh_enemy.lure_return_speed, 3.0),
		"fresh presenter restores the physical return policy without replaying the lure")
	fresh_scheduler.advance_ticks(2.0)
	check(fresh_enemy.get_state() == "idle"
			and not fresh_state.is_character_distracted("return_policy_guard"),
		"fresh restored return reaches its post and restores full watch exactly once")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_damaged_hp_same_and_fresh() -> void:
	var context := await _make_context("damaged_guard", false)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: Enemy = context.enemy
	var died_count := {"value": 0}
	enemy.died.connect(func(): died_count.value += 1)
	enemy.take_damage(17.0)
	check(is_equal_approx(enemy.get_hp(), 33.0), "enemy HP changes are committed before any phase ends")
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	enemy.take_damage(100.0)
	check(enemy.get_state() == "dead" and int(died_count.value) == 1,
		"future lethal damage occurs before rollback")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	check(enemy.get_state() == "idle" and enemy.is_alive()
			and is_equal_approx(enemy.get_hp(), 33.0) and enemy.visible,
		"same-node rollback restores damaged HP and revives only the presenter")
	check(int(died_count.value) == 1, "same-node restoration emits no synthetic death signal")

	var fresh := await _make_fresh_from_snapshot(
		"damaged_guard", saved_scheduler, saved_state, false)
	var fresh_enemy: Enemy = fresh.enemy
	var fresh_died_count := {"value": 0}
	fresh_enemy.died.connect(func(): fresh_died_count.value += 1)
	fresh_enemy.on_game_state_snapshot_restored()
	check(fresh_enemy.get_state() == "idle" and fresh_enemy.is_alive()
			and is_equal_approx(fresh_enemy.get_hp(), 33.0),
		"fresh presenter restores non-max HP by stable char id")
	check(int(fresh_died_count.value) == 0, "fresh restoration emits no gameplay signals")
	await _discard_context(context)
	await _discard_context(fresh)


func _verify_impact_restore_is_side_effect_free() -> void:
	var context := await _make_context("impact_guard", true)
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: Enemy = context.enemy
	enemy.impact_duration = 2.0
	enemy._current_target_id = "target"
	enemy._charge_hit = false
	enemy._change_state("impact")
	check(is_equal_approx(state.get_stat("target", "hp"), 75.0),
		"impact fixture deals its one real strike before the snapshot")
	scheduler.advance_ticks(0.75)
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	var fresh := await _make_fresh_from_snapshot(
		"impact_guard", saved_scheduler, saved_state, true)
	var fresh_scheduler: EventScheduler = fresh.scheduler
	var fresh_state: GameState = fresh.state
	var fresh_enemy: Enemy = fresh.enemy
	check(fresh_enemy.get_state() == "impact"
			and is_equal_approx(fresh_state.get_stat("target", "hp"), 75.0),
		"loading impact rebuilds presentation without replaying strike damage")
	fresh_scheduler.advance_ticks(1.25)
	check(fresh_enemy.get_state() == "recover"
			and is_equal_approx(fresh_state.get_stat("target", "hp"), 75.0),
		"restored impact finishes without a second strike")
	await _discard_context(context)
	await _discard_context(fresh)


func _make_context(enemy_id: String, with_target: bool) -> Dictionary:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	if with_target:
		state.register_character("target", Vector3(1.0, 0.0, 0.0), 3.0, {"hp": 100.0})
	state.register_character(enemy_id, Vector3.ZERO, 2.0, {"detection_range": 8.0})
	var host := Node3D.new()
	host.name = "Host_%s" % enemy_id
	root.add_child(host)
	var enemy := Enemy.new()
	enemy.name = enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = state
	enemy.max_hp = 50.0
	enemy.move_speed = 2.0
	enemy.detection_range = 8.0
	enemy.set_detection_targets([])
	host.add_child(enemy)
	await process_frame
	enemy.activate()
	return {"scheduler": scheduler, "state": state, "enemy": enemy, "host": host}


func _make_fresh_from_snapshot(
		enemy_id: String, scheduler_snapshot: Dictionary, state_snapshot: Dictionary,
		with_target: bool) -> Dictionary:
	var scheduler := EventScheduler.new()
	scheduler.deserialize(scheduler_snapshot)
	var state := GameState.new()
	state.scheduler = scheduler
	state.deserialize(state_snapshot)
	# This assertion belongs in the helper because a fresh-load bug that drops the enemy registry would
	# otherwise be hidden by re-registering it here.
	check(state.characters.has(enemy_id)
			and (not with_target or state.characters.has("target")),
		"fresh GameState contains the serialized combat roster")
	var host := Node3D.new()
	host.name = "FreshHost_%s" % enemy_id
	root.add_child(host)
	var enemy := Enemy.new()
	enemy.name = enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = state
	enemy.max_hp = 50.0
	enemy.move_speed = 2.0
	enemy.detection_range = 8.0
	if with_target:
		enemy._detection_targets.assign(["target"])
	var synthetic_spots := {"value": 0}
	enemy.target_spotted.connect(func(_target_id: String): synthetic_spots.value += 1)
	host.add_child(enemy)
	await process_frame
	enemy.activate() # detects the saved authority record instead of publishing default idle
	enemy.on_game_state_snapshot_restored() # production attachment pass; deliberately idempotent
	check(int(synthetic_spots.value) == 0,
		"fresh attachment emits no synthetic target acquisition")
	return {"scheduler": scheduler, "state": state, "enemy": enemy, "host": host}


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
