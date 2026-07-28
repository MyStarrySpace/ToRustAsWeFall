extends SceneTree

## Focused regression for Lockout Tyreg's causal contract:
## player body at station + party/consciousness/proximity/LOS -> exact Tyreg body and held magazine
## -> accepted escort -> one exact round replacement -> one suppress effect.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const LockoutScene := preload("res://scenes/fragments/chunks/lockout_chase_chunk.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_physical_acceptance_guards()
	await _verify_acceptance_save_seams()
	await _verify_suppress_item_transaction()
	await _verify_fresh_reconstruction_and_absence()
	print("LOCKOUT TYREG AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_physical_acceptance_guards() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	var tyreg := chunk._tyreg_interactable as Interactable
	var magazine_id := str(chunk._tyreg_magazine_item_id)
	check(host.game_state.characters.has(chunk.TYREG_ID)
			and chunk._tyreg_presenter is CharacterBody3D
			and str(chunk._tyreg_presenter.get("char_id")) == chunk.TYREG_ID,
		"fresh junction has one stable physical Tyreg GameState body and presenter")
	check(chunk._tyreg_owns_exact_magazine(magazine_id)
			and chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES,
		"Tyreg starts with one exact held magazine containing three named rounds")
	check(str(chunk.get_preview_state().get("tyreg_phase", "")) == chunk.TYREG_PHASE_AVAILABLE
			and tyreg.is_interaction_enabled(),
		"the offer is available only through the physical body-and-magazine mechanism")

	_move_actor_to_tyreg(host, chunk)
	var baseline := _capture(host)
	var data_id := str(tyreg.data_id)

	host.game_state.set_party(["peris"])
	check(not tyreg._trigger()
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false))
			and not bool(host.game_state.get_interactable(data_id).get("triggered", false)),
		"an active portrait outside the authoritative party cannot accept")
	await _restore_capture(host, chunk, baseline)

	host.game_state.down_character(chunk.TYREG_ID)
	check(not tyreg._trigger()
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false)),
		"a downed or narratively unavailable Tyreg body cannot offer Suppress")
	await _restore_capture(host, chunk, baseline)

	host.game_state.unregister_character(chunk.TYREG_ID)
	chunk.headless_process(0.0)
	check(not chunk._tyreg_presenter.visible and not tyreg._trigger()
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false)),
		"a missing Tyreg body hides the presenter and cannot advance the choice")
	await _restore_capture(host, chunk, baseline)

	host.game_state.snap_character_to(
		chunk.TYREG_ID,
		chunk.TYREG_STATION + Vector3(8.0, 0.0, 0.0)
	)
	chunk.headless_process(0.0)
	check(not tyreg._trigger()
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false)),
		"a real Tyreg body away from the authored station cannot remotely accept")
	await _restore_capture(host, chunk, baseline)

	host.game_state.snap_character_to(
		"aster",
		chunk.TYREG_STATION + Vector3(-3.0, 0.0, 0.0)
	)
	var actor_cell: Vector2i = host.grid.world_to_grid(host.game_state.get_position("aster"))
	var tyreg_cell: Vector2i = host.grid.world_to_grid(
		host.game_state.get_position(chunk.TYREG_ID)
	)
	var sight_cell: Vector2i = host.grid.world_to_grid(
		host.game_state.get_position("aster").lerp(
			host.game_state.get_position(chunk.TYREG_ID),
			0.5
		)
	)
	check(sight_cell != actor_cell and sight_cell != tyreg_cell,
		"occlusion fixture places a distinct authoritative sight cell between both bodies")
	host.grid.add_sight_blocker(sight_cell)
	check(not host.grid.has_line_of_sight(
			host.game_state.get_position("aster"),
			host.game_state.get_position(chunk.TYREG_ID)
		) and not tyreg._trigger(),
		"an occluding grid cell blocks acceptance despite valid distance and bodies")
	host.grid.clear_sight_blocker(sight_cell)
	await _restore_capture(host, chunk, baseline)

	host.game_state.snap_character_to(
		"aster",
		chunk.TYREG_STATION + Vector3(-1.0, 0.0, 0.0)
	)
	check(host.game_state.transfer_item(chunk.TYREG_ID, "aster", magazine_id),
		"wrong-holder fixture transfers the exact magazine through canonical inventory")
	check(not tyreg._trigger()
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false)),
		"a magazine held by the actor instead of Tyreg cannot fund acceptance")
	await _restore_capture(host, chunk, baseline)

	chunk._spawn_wave(1, false, chunk.JUNCTION_X)
	var fixture_enemy = chunk.enemies().back()
	for _round_index in range(chunk.SUPPRESS_CHARGES):
		check(chunk._consume_tyreg_round_for_target(fixture_enemy),
			"fixture consumes one exact round through the production transaction")
	chunk.headless_process(0.0)
	check(chunk._tyreg_suppress_charge_count() == 0
			and not tyreg._trigger()
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false)),
		"an exact but empty magazine cannot be replaced by a chunk counter")

	await _discard(host)


func _verify_acceptance_save_seams() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	var tyreg := chunk._tyreg_interactable as Interactable
	_move_actor_to_tyreg(host, chunk)
	var baseline := _capture(host)
	var joining_capture_box := {"value": {}}
	var capture_joining := func(key: String, value: Variant) -> void:
		if key != chunk.CHASE_AUTHORITY_KEY or not value is Dictionary:
			return
		if str(value.get("tyreg_phase", "")) == chunk.TYREG_PHASE_JOINING \
				and (joining_capture_box.value as Dictionary).is_empty():
			joining_capture_box.value = _capture(host)
	host.game_state.world_state_changed.connect(capture_joining)
	check(tyreg._trigger()
			and bool(chunk.get_preview_state().get("tyreg_accepted", false))
			and not tyreg.is_interaction_enabled(),
		"ordinary interaction accepts once and spends only the semantic offer")
	host.game_state.world_state_changed.disconnect(capture_joining)
	check(not (joining_capture_box.value as Dictionary).is_empty(),
		"signal-time save captured the published JOINING reservation")
	var accepted := _capture(host)

	await _restore_capture(host, chunk, joining_capture_box.value)
	check(str(chunk.get_preview_state().get("tyreg_phase", ""))
			== chunk.TYREG_PHASE_AVAILABLE
			and not bool(chunk.get_preview_state().get("tyreg_accepted", false))
			and tyreg.is_interaction_enabled()
			and chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES,
		"same-instance JOINING restore retracts to one retryable physical offer")
	check(tyreg._trigger()
			and bool(chunk.get_preview_state().get("tyreg_accepted", false))
			and not tyreg._trigger(),
		"ordinary retry accepts once and input spam cannot duplicate acceptance")

	await _restore_capture(host, chunk, baseline)
	check(not bool(chunk.get_preview_state().get("tyreg_accepted", false))
			and tyreg.is_interaction_enabled()
			and chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES,
		"rollback before acceptance retracts future semantic and presenter state")
	await _restore_capture(host, chunk, accepted)
	check(bool(chunk.get_preview_state().get("tyreg_accepted", false))
			and not tyreg.is_interaction_enabled()
			and chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES,
		"accepted snapshot reconstructs the spent offer without minting ammunition")

	await _discard(host)


func _verify_suppress_item_transaction() -> void:
	var pair := await _boot_lockout()
	var host = pair.host
	var chunk = pair.chunk
	_move_actor_to_tyreg(host, chunk)
	check(chunk._tyreg_interactable._trigger(), "Suppress fixture accepts Tyreg physically")
	chunk._spawn_wave(1, false, chunk.JUNCTION_X + 1.0)
	var enemy = chunk.enemies().back()
	var enemy_id := str(enemy.char_id)
	host.game_state.snap_character_to(
		enemy_id,
		chunk.TYREG_STATION + Vector3(2.0, 0.0, 0.0)
	)
	host.game_state.snap_character_to(
		"aster",
		chunk.TYREG_STATION + Vector3(1.0, 0.0, 0.0)
	)
	host.game_state.snap_character_to(
		"peris",
		chunk.TYREG_STATION + Vector3(1.0, 0.0, 1.0)
	)
	chunk.headless_process(0.0)
	var pre_shot := _capture(host)

	var reserve_capture_box := {"value": {}}
	var capture_reserve := func(key: String, value: Variant) -> void:
		if key != chunk.CHASE_AUTHORITY_KEY or not value is Dictionary:
			return
		var tx: Dictionary = value.get("suppress_transaction", {})
		if str(tx.get("phase", "")) == chunk.SUPPRESS_TX_RESERVING \
				and str(tx.get("replacement_item_id", "")) == "" \
				and (reserve_capture_box.value as Dictionary).is_empty():
			reserve_capture_box.value = _capture(host)
	host.game_state.world_state_changed.connect(capture_reserve)
	check(chunk._consume_tyreg_round_for_target(enemy)
			and chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES - 1,
		"ordinary Suppress replaces one held magazine and consumes one named round")
	host.game_state.world_state_changed.disconnect(capture_reserve)
	check(not (reserve_capture_box.value as Dictionary).is_empty(),
		"save captured the round reservation before source removal")

	await _restore_capture(host, chunk, reserve_capture_box.value)
	check(chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES
			and str(chunk._suppress_transaction.get("phase", "")) == chunk.SUPPRESS_TX_IDLE
			and not enemy.is_stunned(),
		"reservation-before-removal restore rolls back with the same exact source and no free shot")

	await _restore_capture(host, chunk, pre_shot)
	enemy = chunk._enemy_by_id(enemy_id)
	var pickup_capture_box := {"value": {}}
	var capture_pickup := func(char_id: String, item_id: String) -> void:
		if char_id != chunk.TYREG_ID or item_id == str(chunk._tyreg_magazine_item_id):
			return
		if (pickup_capture_box.value as Dictionary).is_empty():
			pickup_capture_box.value = _capture(host)
	host.game_state.item_picked_up.connect(capture_pickup)
	check(chunk._consume_tyreg_round_for_target(enemy),
		"replacement-pickup fixture completes one live shot")
	host.game_state.item_picked_up.disconnect(capture_pickup)
	check(not (pickup_capture_box.value as Dictionary).is_empty(),
		"save captured the replacement already owned while the shot remained reserved")

	await _restore_capture(host, chunk, pickup_capture_box.value)
	enemy = chunk._enemy_by_id(enemy_id)
	check(str(chunk._suppress_transaction.get("phase", "")) == chunk.SUPPRESS_TX_IDLE
			and chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES - 1
			and enemy != null and enemy.is_stunned(),
		"signal-time restore commits the exact replacement and one suppress effect")
	var post_signal_restore := _capture(host)
	await _restore_capture(host, chunk, post_signal_restore)
	enemy = chunk._enemy_by_id(enemy_id)
	check(chunk._tyreg_suppress_charge_count() == chunk.SUPPRESS_CHARGES - 1
			and enemy != null and enemy.is_stunned(),
		"idempotent reconstruction cannot consume a second round or lose the saved effect")

	var fresh_pair := await _boot_lockout()
	var fresh_host = fresh_pair.host
	var fresh_chunk = fresh_pair.chunk
	await _restore_capture(fresh_host, fresh_chunk, reserve_capture_box.value)
	var fresh_enemy = fresh_chunk._enemy_by_id(enemy_id)
	check(fresh_chunk._tyreg_suppress_charge_count() == fresh_chunk.SUPPRESS_CHARGES
			and str(fresh_chunk._suppress_transaction.get("phase", ""))
				== fresh_chunk.SUPPRESS_TX_IDLE
			and fresh_enemy != null and not fresh_enemy.is_stunned(),
		"fresh reservation-before-removal reconstruction keeps the exact source and no free shot")
	await _restore_capture(fresh_host, fresh_chunk, pickup_capture_box.value)
	fresh_enemy = fresh_chunk._enemy_by_id(enemy_id)
	check(fresh_chunk._tyreg_suppress_charge_count() == fresh_chunk.SUPPRESS_CHARGES - 1
			and str(fresh_chunk._suppress_transaction.get("phase", ""))
				== fresh_chunk.SUPPRESS_TX_IDLE
			and fresh_enemy != null and fresh_enemy.is_stunned(),
		"fresh post-replacement reconstruction consumes exactly one round and commits one effect")

	await _discard(host)
	await _discard(fresh_host)


func _verify_fresh_reconstruction_and_absence() -> void:
	var source_pair := await _boot_lockout()
	var source_host = source_pair.host
	var source_chunk = source_pair.chunk
	_move_actor_to_tyreg(source_host, source_chunk)
	check(source_chunk._tyreg_interactable._trigger(),
		"fresh reconstruction fixture accepts Tyreg")
	var accepted := _capture(source_host)

	var fresh_pair := await _boot_lockout()
	var fresh_host = fresh_pair.host
	var fresh_chunk = fresh_pair.chunk
	await _restore_capture(fresh_host, fresh_chunk, accepted)
	check(bool(fresh_chunk.get_preview_state().get("tyreg_accepted", false))
			and fresh_host.game_state.characters.has(fresh_chunk.TYREG_ID)
			and fresh_chunk._tyreg_presenter.visible
			and fresh_chunk._tyreg_suppress_charge_count() == fresh_chunk.SUPPRESS_CHARGES,
		"fresh presenter attaches to the saved body and exact magazine")

	var missing := accepted.duplicate(true)
	var missing_state: Dictionary = missing.get("game_state", {})
	var chars: Dictionary = missing_state.get("characters", {})
	chars.erase(fresh_chunk.TYREG_ID)
	await _restore_capture(fresh_host, fresh_chunk, missing)
	var tyreg_magazines := _count_tyreg_magazines(fresh_host.game_state, fresh_chunk)
	check(not fresh_host.game_state.characters.has(fresh_chunk.TYREG_ID)
			and not fresh_chunk._tyreg_presenter.visible
			and tyreg_magazines == 1
			and not fresh_chunk._tyreg_interactable._trigger(),
		"fresh missing-body restore never remints Tyreg or converts her orphaned item into acceptance")

	await _discard(source_host)
	await _discard(fresh_host)


func _boot_lockout() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = LockoutScene.instantiate()
	chunk.attach_chunk_host(host, "lockout_chase")
	host.add_child(chunk)
	await process_frame
	host.register_party(chunk.get_spawn_positions())
	host.game_state.set_party(["aster", "peris"])
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.headless_process(0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _move_actor_to_tyreg(host, chunk) -> void:
	host.active_character = "aster"
	host.game_state.set_party(["aster", "peris"])
	host.game_state.snap_character_to(
		"aster",
		chunk.TYREG_STATION + Vector3(-1.5, 0.0, 0.0)
	)
	chunk._tyreg_interactable.active_character = "aster"
	chunk.headless_process(0.0)


func _count_tyreg_magazines(game_state: GameState, chunk) -> int:
	var count := 0
	for item_id_v in game_state.items.keys():
		if chunk._is_tyreg_magazine(str(item_id_v)):
			count += 1
	return count


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _restore_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)
	await process_frame
	chunk.headless_process(0.0)
	await process_frame


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
