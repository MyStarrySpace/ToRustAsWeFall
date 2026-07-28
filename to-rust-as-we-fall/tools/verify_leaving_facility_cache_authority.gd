extends SceneTree

## Exact-source and save-boundary regression for Leaving Facility's optional lysate cache.
## The cache contains one visible item before interaction; the timed action may only transfer that
## identity through ordinary GameState pickup rules. Run:
##   godot --headless --path . --script res://tools/verify_leaving_facility_cache_authority.gd

const LeavingFacilityScene := preload("res://scenes/tutorial/leaving_facility.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: Node = await _spawn_sequence()
	var initial := _json_round_trip(source.build_save_snapshot())
	var initial_state: Dictionary = source.headless_get_state()
	var source_id := str(initial_state.get("cache_item_id", ""))
	check(source_id != "" and bool(initial_state.get("cache_item_at_source", false))
			and str(initial_state.get("cache_phase", "")) == source.CACHE_PHASE_AVAILABLE
			and _count_cache_items(source) == 1,
		"construction exposes exactly one source-tagged lysate before interaction")
	source._cache_interactable.active_character = "aster"
	check(not source._on_cache_collected()
			and bool(source.headless_get_state().get("cache_item_at_source", false)),
		"a direct owner callback has no exact-source receipt and is inert")
	source._cache_interactable.emit_signal("interacted")
	check(bool(source.headless_get_state().get("cache_item_at_source", false)),
		"a manually emitted interacted signal cannot counterfeit source acceptance")

	# The exact source receipt is not a pickup bypass. Its validator still owns the
	# registered actor body, two-metre transfer range, and action-ready state.
	check(not bool(source._cache_interactable.call("_trigger", false))
			and str(source.headless_get_state().get("cache_item_id", "")) == source_id
			and bool(source.headless_get_state().get("cache_item_at_source", false)),
		"an out-of-range exact-source request leaves the same item visibly in the cache")

	# A completed dwell cannot conjure another hand. A two-slot blocker makes the ordinary pickup fail
	# without consuming, replacing, or duplicating the cache reward.
	source.set_preview_character_position("aster", source.CACHE_POS)
	var blocker_id: String = source._game_state.spawn_item("authority_test_blocker", source.CACHE_POS, {
		"display_name": "Authority test blocker",
		"hand_slots": 2,
		"endocytosis_allowed": false,
	})
	check(source._game_state.pick_up_item("aster", blocker_id),
		"test fixture fills both of Aster's ordinary hand slots")
	source._cache_interactable.active_character = "aster"
	check(not bool(source._cache_interactable.call("_trigger", false))
			and bool(source.headless_get_state().get("cache_item_at_source", false))
			and _count_cache_items(source) == 1,
		"full hands leave the original cache item untouched")
	source._game_state.remove_item(blocker_id)

	# Peris, not a hard-coded Aster, claims the exact existing identity. Capture from inside
	# item_picked_up, after GameState moved the item but before the chunk publishes CLAIMED.
	source.set_preview_character_position("peris", source.CACHE_POS)
	source._cache_interactable.active_character = "peris"
	var signal_box := {"snapshot": {}}
	var accepted_box := {"snapshot": {}}
	var source_committed_box := {"snapshot": {}}
	var capture_accepted := func(data_id: String, char_id: String) -> void:
		if data_id == str(source._cache_interactable.get("data_id")) \
				and char_id == "peris" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _json_round_trip(source.build_save_snapshot())
	var capture_source_committed := func(key: String, _value: Variant) -> void:
		if key == source.LEAVING_SOURCE_AUTHORITY_KEY \
				and (source_committed_box.get("snapshot", {}) as Dictionary).is_empty():
			source_committed_box["snapshot"] = _json_round_trip(
				source.build_save_snapshot())
	var capture_pickup := func(char_id: String, item_id: String) -> void:
		if char_id == "peris" and item_id == source_id \
				and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _json_round_trip(source.build_save_snapshot())
	source._game_state.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	source._game_state.world_state_changed.connect(capture_source_committed)
	source._game_state.item_picked_up.connect(capture_pickup, CONNECT_ONE_SHOT)
	check(bool(source._cache_interactable.call("_trigger", false)),
		"a nearby free-handed Peris can claim the cache through its exact source")
	if source._game_state.world_state_changed.is_connected(capture_source_committed):
		source._game_state.world_state_changed.disconnect(capture_source_committed)
	var claimed: Dictionary = source.headless_get_state()
	check(str(claimed.get("cache_item_id", "")) == source_id
			and str(claimed.get("cache_item_holder", "")) == "peris"
			and str(claimed.get("cache_phase", "")) == source.CACHE_PHASE_CLAIMED
			and bool(claimed.get("cache_collected", false)),
		"successful salvage transfers the pre-existing identity to the actual actor")
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {}) as Dictionary
	check(not signal_snapshot.is_empty()
			and str(_cache_record(signal_snapshot, source).get("phase", "")) \
				== source.CACHE_PHASE_CLAIMING,
		"the pickup signal sees a durable CLAIMING reservation rather than an ambiguous boolean")

	# The source publication precedes its owner callback. Loading that exact edge burns the old
	# receipt and rearms the still-available source; it must never infer the later pickup endpoint.
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {}) as Dictionary
	check(not accepted_snapshot.is_empty(),
		"the exact registry acceptance boundary can be saved before the cache owner runs")
	var source_committed_snapshot: Dictionary = source_committed_box.get(
		"snapshot", {}) as Dictionary
	check(not source_committed_snapshot.is_empty(),
		"the consumed source receipt can be saved before the cache owner runs")
	source.apply_save_snapshot(accepted_snapshot)
	var accepted_same: Dictionary = source.headless_get_state()
	check(str(accepted_same.get("cache_phase", "")) == source.CACHE_PHASE_AVAILABLE
			and bool(accepted_same.get("cache_item_at_source", false))
			and str(accepted_same.get("cache_item_holder", "")) == ""
			and source._cache_interactable.is_interaction_enabled(),
		"same-presenter accepted-before-owner restore burns the edge without manufacturing pickup")
	source.apply_save_snapshot(source_committed_snapshot)
	var committed_same: Dictionary = source.headless_get_state()
	check(str(committed_same.get("cache_phase", "")) == source.CACHE_PHASE_AVAILABLE
			and bool(committed_same.get("cache_item_at_source", false))
			and source._cache_interactable.is_interaction_enabled(),
		"same-presenter source-committed restore rearms without reusing the consumed receipt")

	# Same-presenter rollback must reconcile the exact signal-time item/actor pair once.
	source.apply_save_snapshot(signal_snapshot)
	claimed = source.headless_get_state()
	check(str(claimed.get("cache_phase", "")) == source.CACHE_PHASE_CLAIMED
			and str(claimed.get("cache_item_id", "")) == source_id
			and str(claimed.get("cache_item_holder", "")) == "peris",
		"same-presenter signal restore completes the reserved exact-source claim")

	# A fresh view reaches the same result and its item presenter follows the hand instead of leaving
	# a fake glowing sphere in the emptied cache.
	var fresh: Node = await _spawn_sequence()
	fresh.apply_save_snapshot(accepted_snapshot)
	var accepted_fresh: Dictionary = fresh.headless_get_state()
	check(str(accepted_fresh.get("cache_phase", "")) == fresh.CACHE_PHASE_AVAILABLE
			and bool(accepted_fresh.get("cache_item_at_source", false))
			and fresh._cache_interactable.is_interaction_enabled(),
		"fresh accepted-before-owner restore also rearms without granting the reward")
	fresh.apply_save_snapshot(source_committed_snapshot)
	var committed_fresh: Dictionary = fresh.headless_get_state()
	check(str(committed_fresh.get("cache_phase", "")) == fresh.CACHE_PHASE_AVAILABLE
			and bool(committed_fresh.get("cache_item_at_source", false))
			and fresh._cache_interactable.is_interaction_enabled(),
		"fresh source-committed restore also rearms without manufacturing pickup")
	fresh.apply_save_snapshot(signal_snapshot)
	claimed = fresh.headless_get_state()
	var item_node: Node3D = fresh._chunk_item_nodes.get(source_id) as Node3D
	var expected_hand_pos: Vector3 = fresh._peris.global_position + Vector3(0.38, 1.05, 0.1)
	check(str(claimed.get("cache_phase", "")) == fresh.CACHE_PHASE_CLAIMED
			and str(claimed.get("cache_item_holder", "")) == "peris",
		"fresh-presenter signal restore preserves the same actor and item")
	check(is_instance_valid(item_node) and item_node.visible
			and item_node.global_position.distance_to(expected_hand_pos) <= 0.05,
		"the tutorial item presenter visibly follows the authoritative holder")

	# A syntactically valid reservation paired with a different physical holder is unresolved, not
	# silently retargeted. This fails closed even on a fresh presenter.
	var wrong_holder := _json_round_trip(initial)
	_inject_claiming_holder(wrong_holder, source, source_id, "aster", "peris")
	fresh.apply_save_snapshot(wrong_holder)
	var wrong_state: Dictionary = fresh.headless_get_state()
	check(str(wrong_state.get("cache_phase", "")) == fresh.CACHE_PHASE_CLAIMING
			and str(wrong_state.get("cache_claimed_by", "")) == "aster"
			and str(wrong_state.get("cache_item_holder", "")) == "peris"
			and not bool(wrong_state.get("cache_collected", true))
			and not fresh._cache_interactable.is_interaction_enabled(),
		"wrong-holder injection cannot complete or retarget the reserved claim")

	# Absence is the conservative legacy migration: retract a discarded future to one visible source
	# item, clearing any holder rather than minting a reward into somebody's inventory.
	var legacy := _json_round_trip(initial)
	var legacy_gs: Dictionary = legacy.get("game_state", {})
	var legacy_world: Dictionary = legacy_gs.get("world_state", {})
	legacy_world.erase(source.CACHE_AUTHORITY_KEY)
	legacy_gs["world_state"] = legacy_world
	legacy["game_state"] = legacy_gs
	fresh.apply_save_snapshot(legacy)
	var legacy_state: Dictionary = fresh.headless_get_state()
	check(str(legacy_state.get("cache_phase", "")) == fresh.CACHE_PHASE_AVAILABLE
			and bool(legacy_state.get("cache_item_at_source", false))
			and str(legacy_state.get("cache_item_holder", "")) == ""
			and _count_cache_items(fresh) == 1,
		"legacy/absent authority restores one visible source item and no phantom carrier")

	# Duplicate source identities are an exploit, not extra loot. Keep the authority-selected identity
	# and discard only tagged duplicates.
	var duplicated := _json_round_trip(initial)
	var duplicated_gs: Dictionary = duplicated.get("game_state", {})
	var duplicated_items: Dictionary = duplicated_gs.get("items", {})
	duplicated_items["item_999"] = (duplicated_items.get(source_id, {}) as Dictionary).duplicate(true)
	duplicated_gs["items"] = duplicated_items
	duplicated["game_state"] = duplicated_gs
	fresh.apply_save_snapshot(duplicated)
	check(_count_cache_items(fresh) == 1
			and str(fresh.headless_get_state().get("cache_item_id", "")) == source_id,
		"restore deterministically removes duplicate tagged cache rewards")

	_end_sequence(source)
	_end_sequence(fresh)
	print("LEAVING FACILITY CACHE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _spawn_sequence() -> Node:
	var sequence := LeavingFacilityScene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	sequence._scheduler.clear()
	sequence._scheduler.resume()
	return sequence


func _cache_record(snapshot: Dictionary, sequence: Node) -> Dictionary:
	var gs: Dictionary = snapshot.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	var raw: Variant = world.get(sequence.CACHE_AUTHORITY_KEY, {})
	return raw as Dictionary if raw is Dictionary else {}


func _inject_claiming_holder(
		snapshot: Dictionary,
		sequence: Node,
		item_id: String,
		reserved_actor: String,
		actual_holder: String
	) -> void:
	var gs: Dictionary = snapshot.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	var authority: Dictionary = world.get(sequence.CACHE_AUTHORITY_KEY, {})
	authority["phase"] = sequence.CACHE_PHASE_CLAIMING
	authority["claimed_by"] = reserved_actor
	authority["claim_serial"] = 1
	world[sequence.CACHE_AUTHORITY_KEY] = authority
	gs["world_state"] = world
	var items: Dictionary = gs.get("items", {})
	var item: Dictionary = items.get(item_id, {})
	item["holder"] = actual_holder
	item["location"] = "hand"
	items[item_id] = item
	gs["items"] = items
	var characters: Dictionary = gs.get("characters", {})
	for char_id_v in characters.keys():
		var char_id := str(char_id_v)
		var character: Dictionary = characters[char_id]
		character["hands"] = [item_id, null] if char_id == actual_holder else [null, null]
		characters[char_id] = character
	gs["characters"] = characters
	snapshot["game_state"] = gs


func _count_cache_items(sequence: Node) -> int:
	var count := 0
	for item_id_v in sequence._game_state.items.keys():
		if sequence._is_cache_item(str(item_id_v)):
			count += 1
	return count


func _end_sequence(sequence: Node) -> void:
	if sequence.has_method("_teardown_sequence"):
		sequence._teardown_sequence()
	sequence.free()


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
