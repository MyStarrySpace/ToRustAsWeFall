extends SceneTree

## ChainEnemy subclass regression: anchor/contact cadence must survive a midpoint load, while the
## render-smoothed segment array must never become gameplay authority.

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_visual_segments_cannot_create_hits()
	await _verify_mid_contact_same_and_fresh()
	print("CHAIN ENEMY SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_visual_segments_cannot_create_hits() -> void:
	var context := await _make_context("chain_visual_guard", Vector3(0.0, 0.0, 10.0))
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: ChainEnemy = context.enemy
	_begin_test_charge(enemy, scheduler.get_current_tick() + ChainEnemy.CHAIN_CONTACT_INTERVAL)
	# Put a smoothed mesh point directly on the victim, outside the analytic head/anchor chain.
	enemy._segment_positions[3] = state.get_position("target")
	scheduler.advance_ticks(ChainEnemy.CHAIN_CONTACT_INTERVAL)
	check(is_equal_approx(state.get_stat("target", "hp"), 100.0),
		"a render-only segment overlap cannot fabricate contact damage")
	# The same scheduler callback does hit once the authoritative target enters the analytic chain.
	state.snap_character_to("target", Vector3(2.4, 0.0, 0.0))
	scheduler.advance_ticks(ChainEnemy.CHAIN_CONTACT_INTERVAL)
	check(is_equal_approx(state.get_stat("target", "hp"), 75.0),
		"fixed-tick analytic chain contact deals the shared strike without a render frame")
	await _discard_context(context)


func _verify_mid_contact_same_and_fresh() -> void:
	var context := await _make_context("chain_snapshot_guard", Vector3(2.4, 0.0, 0.0))
	var scheduler: EventScheduler = context.scheduler
	var state: GameState = context.state
	var enemy: ChainEnemy = context.enemy
	var original_anchor := Vector3(4.2, 0.0, 0.0)
	var deadline := scheduler.get_current_tick() + 1.0
	_begin_test_charge(enemy, deadline, original_anchor)
	scheduler.advance_ticks(0.4)
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())
	var saved_record: Dictionary = state.get_world_state(enemy._enemy_authority_key(), {})
	check(bool((saved_record.get("chain", {}) as Dictionary).get("anchored", false))
			and is_equal_approx(float((saved_record.chain as Dictionary).next_contact_tick), deadline),
		"snapshot stores chain attachment and the absolute next contact tick")

	# Create a later future, then prove the same presenter is rolled back rather than merged.
	enemy.detach()
	enemy.anchor_to(Vector3(40.0, 0.0, 0.0))
	scheduler.advance_ticks(0.6)
	check(is_equal_approx(state.get_stat("target", "hp"), 100.0),
		"mutated future chain geometry misses before rollback")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	enemy.on_game_state_snapshot_restored()
	enemy.on_game_state_snapshot_restored()
	check(enemy._anchored and enemy._anchor_pos.is_equal_approx(original_anchor)
			and enemy.get_state() == "charge",
		"same-node rollback restores chain phase and attachment geometry")
	scheduler.advance_ticks(0.59)
	check(is_equal_approx(state.get_stat("target", "hp"), 100.0),
		"same-node load cannot move contact earlier than its saved deadline")
	scheduler.advance_ticks(0.01)
	check(is_equal_approx(state.get_stat("target", "hp"), 75.0),
		"same-node contact fires exactly once at the original deadline")

	var fresh := await _make_fresh_from_snapshot(
		"chain_snapshot_guard", saved_scheduler, saved_state)
	var fresh_scheduler: EventScheduler = fresh.scheduler
	var fresh_state: GameState = fresh.state
	var fresh_enemy: ChainEnemy = fresh.enemy
	check(fresh_enemy._anchored and fresh_enemy._anchor_pos.is_equal_approx(original_anchor)
			and fresh_enemy.get_state() == "charge",
		"fresh presenter reconstructs saved chain geometry and charge phase")
	fresh_scheduler.advance_ticks(0.59)
	check(is_equal_approx(fresh_state.get_stat("target", "hp"), 100.0),
		"fresh load preserves the remaining contact window")
	fresh_scheduler.advance_ticks(0.01)
	check(is_equal_approx(fresh_state.get_stat("target", "hp"), 75.0),
		"fresh presenter resolves one contact at the original deadline")
	await _discard_context(context)
	await _discard_context(fresh)


func _begin_test_charge(
		enemy: ChainEnemy,
		deadline: float,
		anchor := Vector3(4.2, 0.0, 0.0)
	) -> void:
	enemy._current_target_id = "target"
	enemy._detection_targets.assign(["target"])
	enemy._anchor_pos = anchor
	enemy._anchored = true
	enemy._charging = true
	enemy._charge_hit = false
	enemy._fsm.force_current("charge")
	enemy._arm_chain_contact_tick(deadline)


func _make_context(enemy_id: String, target_position: Vector3) -> Dictionary:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("target", target_position, 3.0, {"hp": 100.0})
	state.register_character(enemy_id, Vector3.ZERO, 2.0, {"detection_range": 8.0})
	var host := Node3D.new()
	root.add_child(host)
	var enemy := ChainEnemy.new()
	enemy.name = enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = state
	enemy.segment_count = 8
	enemy.segment_spacing = 0.6
	enemy.charge_damage = 25.0
	enemy.set_detection_targets([])
	host.add_child(enemy)
	await process_frame
	enemy.activate()
	return {"scheduler": scheduler, "state": state, "enemy": enemy, "host": host}


func _make_fresh_from_snapshot(
		enemy_id: String,
		scheduler_snapshot: Dictionary,
		state_snapshot: Dictionary
	) -> Dictionary:
	var scheduler := EventScheduler.new()
	scheduler.deserialize(scheduler_snapshot)
	var state := GameState.new()
	state.scheduler = scheduler
	state.deserialize(state_snapshot)
	var host := Node3D.new()
	root.add_child(host)
	var enemy := ChainEnemy.new()
	enemy.name = enemy_id
	enemy.char_id = enemy_id
	enemy.game_state = state
	enemy.segment_count = 8
	enemy.segment_spacing = 0.6
	enemy.charge_damage = 25.0
	host.add_child(enemy)
	await process_frame
	enemy.activate()
	enemy.on_game_state_snapshot_restored()
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
