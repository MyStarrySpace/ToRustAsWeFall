extends SceneTree

## Mid-queue save/load, stun-deadline, and rollback exploit regression for PortalPad. A fresh pad
## presenter must resume the exact queue index/deadline without repeating a teleport, and an earlier
## snapshot must invalidate all hops from the discarded timeline.

const PortalScript := preload("res://scripts/game/objects/portal_pad.gd")

const SOURCE := Vector3(5.0, 0.0, 5.0)
const DESTINATION := Vector3(40.0, 0.0, 5.0)
const IDS := ["aster", "peris", "endo"]
const EFFECT_KEY := "verify:portal_pad:stepped_effects"

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_signal_time_hop_transactions()
	await _verify_source_occupancy_receipts()

	var source_scheduler := EventScheduler.new()
	var source_state := _make_game_state(source_scheduler)
	var source := _make_portal(source_state)
	root.add_child(source)
	await process_frame
	var closed_scheduler := _json_round_trip(source_scheduler.serialize())
	var closed_state := _json_round_trip(source_state.serialize())

	var source_steps: Array[String] = []
	source.stepped_through.connect(func(id, _destination): source_steps.append(str(id)))
	check(source.authority_state_key() == "gameplay:portal_pad:verify_queue_portal",
		"authored identity produces a stable, instance-independent key")
	check(not source.step_through() and not source.step_group_through(IDS),
		"public solo/group compatibility verbs cannot mint portal transit")
	check(_trigger_portal(source, "aster", IDS),
		"exact gathered source-pad trigger commits group transit")
	check(source_steps == ["aster"],
		"commit teleports exactly the first member and records the remaining queue")
	source.active_character = "peris"
	check(not source.call("_trigger", false),
		"another physical trigger cannot bypass an already-committed one-at-a-time queue")
	var committed := source.get_transit_state()
	check(str(committed.get("contract", "")) == "portal_pad/v2"
			and str(committed.get("phase", "")) == "crossing"
			and int(committed.get("next_index", -1)) == 1
			and float(committed.get("next_hop_tick", -1.0)) > 0.0
			and bool((committed.get("trigger_receipt", {}) as Dictionary).get(
				"consumed", false)),
		"GameState owns queue order, consumed exact trigger receipt, and absolute hop deadline")

	source_scheduler.advance_ticks(0.4)
	source_state.flush_tick()
	var midpoint_scheduler := _json_round_trip(source_scheduler.serialize())
	var midpoint_state := _json_round_trip(source_state.serialize())
	var midpoint := source.get_transit_state()
	check(int(midpoint.get("next_index", -1)) == 1
			and float(midpoint.get("next_hop_in", -1.0)) > 0.0,
		"midpoint snapshot still names Aster as consumed and Peris as next")
	var replayed := GameState.replay(
		EventLog.from_bytes(source_state.event_log.to_bytes()), null)
	var replayed_queue: Dictionary = replayed.get_world_state(source.authority_state_key(), {})
	check(int(replayed_queue.get("next_index", -1)) == 1
			and replayed.get_position("aster").x > DESTINATION.x,
		"event replay reconstructs the consumed first hop without a PortalPad node")
	if replayed.scheduler != null:
		replayed.scheduler.clear()

	# Attach a completely fresh presenter to the JSON-round-tripped GameState. Stable identity is what
	# lets this different node find the same queue instead of creating a second one.
	var loaded_scheduler := EventScheduler.new()
	loaded_scheduler.deserialize(midpoint_scheduler)
	var loaded_state := _make_empty_game_state(loaded_scheduler)
	loaded_state.deserialize(midpoint_state)
	var loaded := _make_portal(loaded_state)
	var loaded_steps: Array[String] = []
	var loaded_finished := [0]
	loaded.stepped_through.connect(func(id, _destination): loaded_steps.append(str(id)))
	loaded.group_crossing_finished.connect(func(_ids): loaded_finished[0] += 1)
	root.add_child(loaded)
	await process_frame
	var restored := loaded.get_transit_state()
	check(loaded.authority_state_key() == source.authority_state_key()
			and int(restored.get("next_index", -1)) == 1,
		"fresh presenter resolves the saved queue by stable identity")
	check(loaded_state.get_position("aster").x > DESTINATION.x,
		"Aster remains in his saved far-side walk-off instead of returning to the source")
	var remaining := float(restored.get("next_hop_in", 0.0))
	loaded_scheduler.advance_ticks(maxf(0.0, remaining - 0.01))
	check(loaded_steps.is_empty(), "no member repeats or crosses before the saved hop deadline")
	loaded_scheduler.advance_ticks(0.01)
	check(loaded_steps == ["peris"],
		"the fresh presenter resumes with Peris, never teleporting Aster twice")
	loaded_scheduler.advance_ticks(10.0)
	check(loaded_steps == ["peris", "endo"] and loaded_finished[0] == 1
			and not loaded.is_group_crossing_active(),
		"the restored queue completes every remaining member exactly once")

	# Restore the pre-crossing snapshot on the same presenter. All later queue callbacks must disappear.
	loaded_scheduler.clear()
	loaded_scheduler.deserialize(closed_scheduler)
	loaded_state.deserialize(closed_state)
	loaded.on_game_state_snapshot_restored()
	var steps_before_rollback_advance := loaded_steps.size()
	loaded_scheduler.advance_ticks(20.0)
	check(not loaded.is_group_crossing_active()
			and loaded_steps.size() == steps_before_rollback_advance,
		"rollback invalidates every hop from the discarded crossing timeline")
	for id in IDS:
		check(loaded_state.get_position(id).x < 10.0,
			"rollback restores %s without a stale portal teleport" % id.capitalize())

	# Stun is the other PortalPad phase that previously lived only in the node. Preserve its remainder.
	loaded.stun(3.0)
	loaded_scheduler.advance_ticks(1.0)
	var stun_scheduler := _json_round_trip(loaded_scheduler.serialize())
	var stun_state := _json_round_trip(loaded_state.serialize())
	loaded_scheduler.clear()
	loaded_scheduler.deserialize(stun_scheduler)
	loaded_state.deserialize(stun_state)
	loaded.on_game_state_snapshot_restored()
	loaded.active_character = "aster"
	check(loaded.is_stunned() and not _trigger_portal(loaded, "aster", ["aster"])
			and is_equal_approx(float(loaded.get_transit_state().get("stun_remaining", -1.0)), 2.0),
		"mid-stun load preserves refusal and only the saved remaining duration")
	loaded_scheduler.advance_ticks(1.99)
	check(loaded.is_stunned() and not _trigger_portal(loaded, "aster", ["aster"]),
		"restored stun cannot expire early")
	loaded_scheduler.advance_ticks(0.01)
	check(not loaded.is_stunned() and _trigger_portal(loaded, "aster", ["aster"])
			and loaded.is_group_crossing_active(),
		"restored stun expires once and solo transit enters the saved hop transaction")

	source_scheduler.clear()
	loaded_scheduler.clear()
	source.queue_free()
	loaded.queue_free()
	await process_frame
	print("PORTAL PAD AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_source_occupancy_receipts() -> void:
	var scheduler := EventScheduler.new()
	var game_state := _make_game_state(scheduler)
	var portal := _make_portal(game_state)
	root.add_child(portal)
	await process_frame

	portal.set_pre_trigger_validator(func(_source: Node, _actor: String) -> bool: return true)
	game_state.snap_character_to("peris", SOURCE + Vector3(8.0, 0.0, 0.0))
	var before_aster := game_state.get_position("aster")
	var before_peris := game_state.get_position("peris")
	check(not _trigger_portal(portal, "aster", ["aster", "peris"])
			and game_state.get_position("aster").is_equal_approx(before_aster)
			and game_state.get_position("peris").is_equal_approx(before_peris)
			and not portal.is_group_crossing_active(),
		"a permissive scenario validator cannot bypass remote selected-member refusal")

	check(not _trigger_portal(portal, "peris", ["peris"])
			and game_state.get_position("peris").is_equal_approx(before_peris),
		"the real solo trigger rejects an actor without exact source-pad occupancy")

	game_state.snap_character_to("peris", SOURCE + Vector3(0.4, 0.0, 0.0))
	var gathered_aster := game_state.get_position("aster")
	var gathered_peris := game_state.get_position("peris")
	portal.active_character = "aster"
	portal.call("_on_interacted")
	check(not portal.step_through() and not portal.step_group_through(["aster", "peris"])
			and game_state.get_position("aster").is_equal_approx(gathered_aster)
			and game_state.get_position("peris").is_equal_approx(gathered_peris)
			and not portal.is_group_crossing_active(),
		"gathered bodies plus direct helpers or a stale callback still carry no trigger receipt")
	check(_trigger_portal(portal, "aster", ["aster", "peris"]),
		"the same group becomes eligible through the real trigger after every body gathers")
	var committed := portal.get_transit_state()
	var receipts: Dictionary = committed.get("source_receipts", {}) as Dictionary
	var trigger_receipt: Dictionary = committed.get("trigger_receipt", {}) as Dictionary
	check(receipts.has("aster") and receipts.has("peris")
			and (receipts.get("aster", []) as Array).size() == 3
			and (receipts.get("peris", []) as Array).size() == 3
			and str(trigger_receipt.get("source_key", "")) == portal.authority_state_key()
			and str(trigger_receipt.get("actor", "")) == "aster"
			and (trigger_receipt.get("group", []) as Array) == ["aster", "peris"]
			and bool(trigger_receipt.get("consumed", false)),
		"the portable queue records exact source/body positions and its consumed trigger receipt")
	scheduler.advance_ticks(10.0)
	game_state.flush_tick()
	game_state.snap_character_to("aster", SOURCE + Vector3(-0.4, 0.0, 0.0))
	game_state.snap_character_to("peris", SOURCE + Vector3(0.4, 0.0, 0.0))
	var stale_aster := game_state.get_position("aster")
	var stale_peris := game_state.get_position("peris")
	portal.call("_on_interacted")
	check(not portal.is_group_crossing_active()
			and game_state.get_position("aster").is_equal_approx(stale_aster)
			and game_state.get_position("peris").is_equal_approx(stale_peris),
		"a consumed receipt cannot be replayed by a later gathered stale callback")

	scheduler.clear()
	portal.queue_free()
	await process_frame


func _verify_signal_time_hop_transactions() -> void:
	var scheduler := EventScheduler.new()
	var game_state := _make_game_state(scheduler)
	var portal := _make_portal(game_state)
	root.add_child(portal)
	await process_frame

	var pre_snap_scheduler := {}
	var pre_snap_state := {}
	var post_snap_scheduler := {}
	var post_snap_state := {}
	var emitted := [0]
	var authority_key := portal.authority_state_key()
	game_state.world_state_changed.connect(func(key: String, value: Variant):
		if key != authority_key or not (value is Dictionary) or not pre_snap_state.is_empty():
			return
		var hop_v: Variant = (value as Dictionary).get("hop", {})
		if hop_v is Dictionary and str((hop_v as Dictionary).get("phase", "")) == "reserved":
			pre_snap_scheduler.assign(_json_round_trip(scheduler.serialize()))
			pre_snap_state.assign(_json_round_trip(game_state.serialize()))
	)
	# This handler represents a real downstream one-shot consequence. Connect it
	# before the signal-time capture so the captured consequence is already truth.
	portal.stepped_through.connect(func(id: String, _destination: Vector3):
		emitted[0] += 1
		var effects_v: Variant = game_state.get_world_state(EFFECT_KEY, {})
		var effects := (effects_v as Dictionary).duplicate(true) \
			if effects_v is Dictionary else {}
		effects[id] = int(effects.get(id, 0)) + 1
		game_state.set_world_state(EFFECT_KEY, effects)
	)
	portal.stepped_through.connect(func(id: String, _destination: Vector3):
		if id == "aster" and post_snap_state.is_empty():
			post_snap_scheduler.assign(_json_round_trip(scheduler.serialize()))
			post_snap_state.assign(_json_round_trip(game_state.serialize()))
	)

	check(_trigger_portal(portal, "aster", ["aster"]),
		"gathered solo trigger commits through the same saved queue/hop transaction")
	check(not pre_snap_state.is_empty()
			and _snapshot_position(pre_snap_state, "aster").x < 10.0,
		"reservation signal captures an explicit pre-snap transaction and unmoved body")
	var pre_record := _snapshot_portal_record(pre_snap_state, authority_key)
	var pre_hop_v: Variant = pre_record.get("hop", {})
	var pre_hop := pre_hop_v as Dictionary if pre_hop_v is Dictionary else {}
	var pre_trigger: Dictionary = pre_record.get("trigger_receipt", {}) as Dictionary
	check(str(pre_record.get("contract", "")) == "portal_pad/v2"
			and int(pre_record.get("next_index", -1)) == 1
			and str(pre_hop.get("who", "")) == "aster"
			and int(pre_hop.get("index", -1)) == 0
			and str(pre_trigger.get("actor", "")) == "aster"
			and (pre_trigger.get("group", []) as Array) == ["aster"]
			and bool(pre_trigger.get("consumed", false)),
		"pre-snap reservation carries stable actor, exact trigger receipt, endpoints, and claimed index")
	check(not post_snap_state.is_empty()
			and _snapshot_position(post_snap_state, "aster").x >= DESTINATION.x - 0.01
			and _snapshot_effect_count(post_snap_state, "aster") == 1,
		"stepped_through signal captures the teleported body and its downstream effect")
	var post_record := _snapshot_portal_record(post_snap_state, authority_key)
	check(not (post_record.get("hop", {}) as Dictionary).is_empty()
			and int(post_record.get("next_index", -1)) == 1,
		"post-snap/pre-finalize snapshot retains the same in-flight reservation")

	# Same-presenter pre-snap restore: restoration itself is silent; the rearmed
	# transaction performs the owed portal snap and consequence once on scheduler time.
	var emitted_before_restore := int(emitted[0])
	_restore_snapshot(scheduler, game_state, pre_snap_scheduler, pre_snap_state)
	portal.on_game_state_snapshot_restored()
	portal.on_game_state_snapshot_restored()
	check(int(emitted[0]) == emitted_before_restore
			and _effect_count(game_state, "aster") == 0,
		"same-presenter pre-snap restore twice emits nothing and invents no consequence")
	scheduler.advance_ticks(0.0)
	check(int(emitted[0]) == emitted_before_restore + 1
			and _effect_count(game_state, "aster") == 1
			and game_state.get_position("aster").x >= DESTINATION.x - 0.01,
		"same-presenter pre-snap resume teleports and applies the effect exactly once")

	# Same-presenter post-snap restore: physical evidence reconciles the reservation
	# without replaying stepped_through or its already-saved consequence.
	emitted_before_restore = int(emitted[0])
	_restore_snapshot(scheduler, game_state, post_snap_scheduler, post_snap_state)
	portal.on_game_state_snapshot_restored()
	portal.on_game_state_snapshot_restored()
	check(int(emitted[0]) == emitted_before_restore
			and _effect_count(game_state, "aster") == 1,
		"same-presenter post-snap restore twice is silent and preserves one saved effect")
	scheduler.advance_ticks(0.0)
	check(int(emitted[0]) == emitted_before_restore
			and _effect_count(game_state, "aster") == 1
			and (portal.get_transit_state().get("hop", {}) as Dictionary).is_empty(),
		"same-presenter reconciliation finalizes without duplicating the hop effect")

	# Fresh pre-snap restore exercises stable-ID lookup plus deferred realization.
	var fresh_pre_scheduler := EventScheduler.new()
	var fresh_pre_state := _make_empty_game_state(fresh_pre_scheduler)
	_restore_snapshot(fresh_pre_scheduler, fresh_pre_state,
		pre_snap_scheduler, pre_snap_state)
	var fresh_pre := _make_portal(fresh_pre_state)
	var fresh_pre_emits := [0]
	fresh_pre.stepped_through.connect(func(id: String, _destination: Vector3):
		fresh_pre_emits[0] += 1
		_increment_effect(fresh_pre_state, id)
	)
	root.add_child(fresh_pre)
	await process_frame
	fresh_pre.on_game_state_snapshot_restored()
	check(fresh_pre_emits[0] == 0 and _effect_count(fresh_pre_state, "aster") == 0,
		"fresh pre-snap attachment plus repeated restore owns only one derived callback")
	fresh_pre_scheduler.advance_ticks(0.0)
	check(fresh_pre_emits[0] == 1 and _effect_count(fresh_pre_state, "aster") == 1
			and _event_count(fresh_pre_state, GameEvent.KIND_SNAP_POSITION) == 1
			and fresh_pre_state.get_position("aster").x >= DESTINATION.x - 0.01,
		"fresh pre-snap presenter realizes the reserved portal hop exactly once")

	# Fresh post-snap restore must consume the reservation without re-emitting.
	var fresh_post_scheduler := EventScheduler.new()
	var fresh_post_state := _make_empty_game_state(fresh_post_scheduler)
	_restore_snapshot(fresh_post_scheduler, fresh_post_state,
		post_snap_scheduler, post_snap_state)
	var fresh_post := _make_portal(fresh_post_state)
	var fresh_post_emits := [0]
	fresh_post.stepped_through.connect(func(id: String, _destination: Vector3):
		fresh_post_emits[0] += 1
		_increment_effect(fresh_post_state, id)
	)
	root.add_child(fresh_post)
	await process_frame
	fresh_post.on_game_state_snapshot_restored()
	fresh_post_scheduler.advance_ticks(0.0)
	check(fresh_post_emits[0] == 0 and _effect_count(fresh_post_state, "aster") == 1
			and _event_count(fresh_post_state, GameEvent.KIND_SNAP_POSITION) == 0
			and fresh_post_state.get_position("aster").x >= DESTINATION.x - 0.01
			and (fresh_post.get_transit_state().get("hop", {}) as Dictionary).is_empty(),
		"fresh post-snap presenter reconciles without a duplicate signal, snap, or effect")

	scheduler.clear()
	fresh_pre_scheduler.clear()
	fresh_post_scheduler.clear()
	portal.queue_free()
	fresh_pre.queue_free()
	fresh_post.queue_free()
	await process_frame


func _restore_snapshot(
		scheduler: EventScheduler,
		game_state: GameState,
		scheduler_snapshot: Dictionary,
		state_snapshot: Dictionary
	) -> void:
	scheduler.clear()
	scheduler.deserialize(scheduler_snapshot)
	game_state.deserialize(state_snapshot)


func _snapshot_position(snapshot: Dictionary, id: String) -> Vector3:
	var characters_v: Variant = snapshot.get("characters", {})
	if not (characters_v is Dictionary):
		return Vector3.ZERO
	var character_v: Variant = (characters_v as Dictionary).get(id, {})
	if not (character_v is Dictionary):
		return Vector3.ZERO
	var position_v: Variant = (character_v as Dictionary).get("position", [])
	return GameEvent.arr_to_v3(position_v as Array) \
		if position_v is Array and (position_v as Array).size() >= 3 else Vector3.ZERO


func _snapshot_portal_record(snapshot: Dictionary, authority_key: String) -> Dictionary:
	var world_v: Variant = snapshot.get("world_state", {})
	if not (world_v is Dictionary):
		return {}
	var record_v: Variant = (world_v as Dictionary).get(authority_key, {})
	return (record_v as Dictionary).duplicate(true) if record_v is Dictionary else {}


func _snapshot_effect_count(snapshot: Dictionary, id: String) -> int:
	var world_v: Variant = snapshot.get("world_state", {})
	if not (world_v is Dictionary):
		return 0
	var effects_v: Variant = (world_v as Dictionary).get(EFFECT_KEY, {})
	return int((effects_v as Dictionary).get(id, 0)) if effects_v is Dictionary else 0


func _effect_count(game_state: GameState, id: String) -> int:
	var effects_v: Variant = game_state.get_world_state(EFFECT_KEY, {})
	return int((effects_v as Dictionary).get(id, 0)) if effects_v is Dictionary else 0


func _increment_effect(game_state: GameState, id: String) -> void:
	var effects_v: Variant = game_state.get_world_state(EFFECT_KEY, {})
	var effects := (effects_v as Dictionary).duplicate(true) \
		if effects_v is Dictionary else {}
	effects[id] = int(effects.get(id, 0)) + 1
	game_state.set_world_state(EFFECT_KEY, effects)


func _event_count(game_state: GameState, kind: StringName) -> int:
	var count := 0
	if game_state.event_log == null:
		return count
	for event_v in game_state.event_log.events:
		if event_v is Dictionary and StringName(str((event_v as Dictionary).get("kind", ""))) == kind:
			count += 1
	return count


func _make_empty_game_state(scheduler: EventScheduler) -> GameState:
	var game_state := GameState.new()
	game_state.scheduler = scheduler
	game_state.grid = _make_grid()
	game_state.event_log = EventLog.new()
	return game_state


func _make_game_state(scheduler: EventScheduler) -> GameState:
	var game_state := _make_empty_game_state(scheduler)
	for entry in [
		["aster", SOURCE + Vector3(-0.4, 0.0, 0.0)],
		["peris", SOURCE + Vector3(-0.7, 0.0, 0.7)],
		["endo", SOURCE + Vector3(-0.7, 0.0, -0.7)],
	]:
		game_state.register_character(str(entry[0]), entry[1] as Vector3, 2.0,
			{"hp": 100.0, "narrative_available": true})
	return game_state


func _make_grid() -> GridWorld:
	var grid := GridWorld.new()
	grid.create_room(64, 16, false)
	return grid


func _make_portal(game_state: GameState) -> PortalPad:
	var portal := PortalScript.new() as PortalPad
	portal.name = "AuthorityPortalPresenter"
	portal.authority_id = "verify_queue_portal"
	portal.configure(game_state, SOURCE, DESTINATION, 1.2)
	return portal


func _trigger_portal(portal: PortalPad, actor: String, selected: Array) -> bool:
	var exact_selection := selected.duplicate()
	portal.set_group_provider(func() -> Array: return exact_selection.duplicate())
	portal.active_character = actor
	return bool(portal.call("_trigger", false))


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
