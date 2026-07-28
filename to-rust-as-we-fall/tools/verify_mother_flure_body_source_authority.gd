extends SceneTree

## Exact-source regression for the four Mother Flure corpses. A harvest interaction may move one
## already-visible starch identity into Endo's hand; it may never manufacture inventory from a
## counter, infer a holder during restore, or reopen a finite source after digestion.

const HostScript := preload("res://tools/mother_flure_authority_host.gd")
const MotherScript := preload("res://scripts/fragments/chunks/mother_flure_chunk.gd")
const FIXTURE_ID := "mother_flure_body_source_fixture"

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_physical_claim_and_signal_restore()
	await _verify_precommand_rollback()
	await _verify_legacy_and_malformed_recovery()
	print("MOTHER FLURE BODY SOURCE AUTHORITY: %d checks, %d failures" % [
		_checks, _failures
	])
	quit(0 if _failures == 0 else 1)


func _verify_physical_claim_and_signal_restore() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	var initial := _capture(host)
	var initial_state: Dictionary = chunk.get_preview_state()
	var body_a_sources: Array = (initial_state.get("body_source_item_ids", {}) as Dictionary).get(
		"body_a", [])
	var source_id := str(body_a_sources[0]) if not body_a_sources.is_empty() else ""
	_check(body_a_sources.size() == chunk.BODY_YIELD_PER_CORPSE
			and int(initial_state.get("body_physical_source_count", 0)) == 8
			and _tagged_item_count(gs, chunk) == 8,
		"all four corpses expose two finite physical starch identities before interaction")
	_check(not chunk.harvest_body("body_a") and _tagged_item_count(gs, chunk) == 8,
		"the retired direct harvest verb cannot consume or replace a source")
	_check(not _trigger_body_at_current_position(host, chunk, "body_a")
			and _tagged_item_count(gs, chunk) == 8,
		"the blocked collapse disables the physical corpse source")

	_check(_drive_source(host, chunk._collapse_interactable, "endo"),
		"Endo starts the physical collapse shift for the harvest fixture")
	host.scheduler.advance_ticks(chunk.COLLAPSE_SHIFT_SECONDS)
	chunk.headless_process(0.0)
	gs.snap_character_to("endo", Vector3(-30.0, 0.0, -30.0))
	_check(not _trigger_body_at_current_position(host, chunk, "body_a")
			and int(chunk.get_preview_state().body_physical_source_count) == 8,
		"an out-of-range request leaves the exact first nodule at its corpse")

	gs.snap_character_to("endo", chunk.BODY_POSITIONS.body_a)
	var blocker_id: String = str(gs.spawn_item(
		"body_source_test_blocker", gs.get_position("endo"), {
		"hand_slots": 2,
		"endocytosis_allowed": false,
	}))
	_check(gs.pick_up_item("endo", blocker_id), "fixture fills both of Endo's physical hands")
	_check(not _trigger_body_at_current_position(host, chunk, "body_a")
			and int(chunk.get_preview_state().body_physical_source_count) == 8,
		"full hands cannot spend a corpse source or mint a replacement")
	gs.remove_item(blocker_id)

	var signal_box := {"snapshot": {}}
	var pickup_capture := func(char_id: String, item_id: String) -> void:
		if char_id == "endo" and item_id == source_id \
				and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _capture(host)
	gs.item_picked_up.connect(pickup_capture, CONNECT_ONE_SHOT)
	_check(_drive_body_harvest(host, chunk, "body_a"),
		"a nearby free-handed Endo moves the first pre-existing nodule into his hand")
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {}) as Dictionary
	var signal_record := _mother_record(signal_snapshot, chunk)
	_check(not signal_snapshot.is_empty()
			and str(signal_record.get("body_claim_phase", "")) == chunk.BODY_CLAIMING
			and str(signal_record.get("body_claim_item_id", "")) == source_id
			and str(signal_record.get("body_claim_body_id", "")) == "body_a"
			and str(signal_record.get("body_claimed_by", "")) == "endo",
		"pickup-signal snapshot retains the exact item, corpse, and actor reservation")
	_check(chunk._body_item_holder(source_id) == "endo"
			and int(chunk.get_preview_state().bodies.body_a) == 1
			and _tagged_item_count(gs, chunk) == 8,
		"ordinary harvest transfers rather than creates or destroys the finite source identity")

	_apply_capture(host, chunk, signal_snapshot)
	_apply_capture(host, chunk, signal_snapshot)
	_check(str(chunk.get_preview_state().body_claim_phase) == chunk.BODY_CLAIM_IDLE
			and chunk._body_item_holder(source_id) == "endo"
			and int(chunk.get_preview_state().bodies.body_a) == 1,
		"same-presenter signal restore commits the exact pickup once")
	var fresh_pair := await _boot()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, signal_snapshot)
	_check(str(fresh_pair.chunk.get_preview_state().body_claim_phase)
			== fresh_pair.chunk.BODY_CLAIM_IDLE
			and fresh_pair.chunk._body_item_holder(source_id) == "endo"
			and int(fresh_pair.chunk.get_preview_state().body_physical_source_count) == 7,
		"fresh presenter reconstructs the same holder and seven remaining source nodules")

	var wrong_holder := _json_round_trip(signal_snapshot)
	var wrong_record := _mother_record(wrong_holder, chunk)
	wrong_record["body_claimed_by"] = "aster"
	_set_mother_record(wrong_holder, chunk, wrong_record)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, wrong_holder)
	var wrong_state: Dictionary = fresh_pair.chunk.get_preview_state()
	_check(str(wrong_state.get("body_claim_phase", "")) == fresh_pair.chunk.BODY_CLAIMING
			and str(wrong_state.get("body_claimed_by", "")) == "aster"
			and fresh_pair.chunk._body_item_holder(source_id) == "endo"
			and _enabled_body_count(fresh_pair.chunk) == 0,
		"wrong-holder injection remains unresolved and disables every new corpse claim")

	# Digestion legitimately removes the claimed live item, but its finite ID remains spent in the
	# Mother ledger and cannot be reconstructed at the body.
	_apply_capture(host, chunk, signal_snapshot)
	_check(gs.endocytose_item("endo", source_id), "Endo begins digesting the claimed starch identity")
	host.scheduler.advance_ticks(GameState.ENDOCYTOSE_DEFAULT_DURATION)
	var digested := _capture(host)
	_check(not gs.items.has(source_id)
			and int(chunk.get_preview_state().bodies.body_a) == 1,
		"digestion removes the live item without reopening its source slot")
	var digested_pair := await _boot()
	_apply_capture(digested_pair.host, digested_pair.chunk, digested)
	_check(not digested_pair.host.game_state.items.has(source_id)
			and int(digested_pair.chunk.get_preview_state().bodies.body_a) == 1
			and int(digested_pair.chunk.get_preview_state().body_physical_source_count) == 7,
		"fresh restore remembers a digested source identity as spent instead of respawning it")

	_apply_capture(host, chunk, initial)
	await _discard(host)
	await _discard(fresh_pair.host)
	await _discard(digested_pair.host)


func _verify_precommand_rollback() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	_drive_source(host, chunk._collapse_interactable, "endo")
	host.scheduler.advance_ticks(chunk.COLLAPSE_SHIFT_SECONDS)
	host.game_state.snap_character_to("endo", chunk.BODY_POSITIONS.body_b)
	var pre_box := {"snapshot": {}}
	var pre_capture := func(key: String, value: Variant) -> void:
		if key != chunk.mother_authority_key() or not value is Dictionary \
				or str((value as Dictionary).get("body_claim_phase", "")) != chunk.BODY_CLAIMING \
				or not (pre_box.get("snapshot", {}) as Dictionary).is_empty():
			return
		var claim_id := str((value as Dictionary).get("body_claim_item_id", ""))
		if chunk._body_item_at_source(claim_id):
			pre_box["snapshot"] = _capture(host)
	host.game_state.world_state_changed.connect(pre_capture)
	_check(_drive_body_harvest(host, chunk, "body_b"),
		"pre-command fixture completes one ordinary body claim")
	host.game_state.world_state_changed.disconnect(pre_capture)
	var pre_snapshot: Dictionary = pre_box.get("snapshot", {}) as Dictionary
	_check(not pre_snapshot.is_empty(),
		"claim publication exposes a save seam before GameState moves the exact item")
	_apply_capture(host, chunk, pre_snapshot)
	var restored: Dictionary = chunk.get_preview_state()
	_check(str(restored.get("body_claim_phase", "")) == chunk.BODY_CLAIM_IDLE
			and int(restored.get("bodies", {}).get("body_b", -1)) == 2
			and int(restored.get("body_physical_source_count", -1)) == 8,
		"pre-command restore rolls the reservation back to the same visible source identity")
	await _discard(host)


func _verify_legacy_and_malformed_recovery() -> void:
	var pair := await _boot()
	var host = pair.host
	var chunk = pair.chunk
	var baseline := _capture(host)
	var legacy := _json_round_trip(baseline)
	var legacy_record := _mother_record(legacy, chunk)
	legacy_record["version"] = 4
	legacy_record["body_remaining"] = {
		"body_a": 1,
		"body_b": 0,
		"body_c": 2,
		"body_d": 1,
	}
	for key in [
		"body_source_item_ids", "body_claimed_item_ids", "body_legacy_claimed",
		"body_claim_phase", "body_claim_item_id", "body_claim_body_id",
		"body_claimed_by", "body_claim_serial",
	]:
		legacy_record.erase(key)
	_set_mother_record(legacy, chunk, legacy_record)
	_remove_tagged_items_from_snapshot(legacy, chunk)
	var legacy_pair := await _boot()
	_apply_capture(legacy_pair.host, legacy_pair.chunk, legacy)
	var migrated: Dictionary = legacy_pair.chunk.get_preview_state()
	var migrated_record: Dictionary = legacy_pair.host.game_state.get_world_state(
		legacy_pair.chunk.mother_authority_key(), {})
	_check(int(migrated_record.get("version", 0)) == legacy_pair.chunk.MOTHER_AUTHORITY_VERSION
			and int(migrated.get("body_physical_source_count", -1)) == 4
			and int(migrated.get("bodies", {}).get("body_b", -1)) == 0,
		"v4 counters migrate to exactly the four genuinely remaining physical source units")
	_check(int((migrated.get("body_legacy_claimed", {}) as Dictionary).get("body_a", -1)) == 1
			and int((migrated.get("body_legacy_claimed", {}) as Dictionary).get("body_b", -1)) == 2
			and _tagged_carrier_count(legacy_pair.host.game_state, legacy_pair.chunk) == 0,
		"legacy migration records unknowable spent identities without guessing a carrier")

	var malformed := _json_round_trip(baseline)
	var malformed_record := _mother_record(malformed, chunk)
	var malformed_items: Dictionary = (malformed.get("game_state", {}) as Dictionary).get(
		"items", {})
	var first_id := ""
	for item_id_v in malformed_items.keys():
		var item: Dictionary = malformed_items[item_id_v]
		var properties: Dictionary = item.get("properties", {})
		if str(properties.get("mother_body_authority", "")) == chunk.mother_authority_key():
			first_id = str(item_id_v)
			break
	var forged_id := "forged_mother_body_reward"
	if first_id != "":
		malformed_items[forged_id] = (malformed_items[first_id] as Dictionary).duplicate(true)
	var malformed_gs: Dictionary = malformed.get("game_state", {})
	malformed_gs["items"] = malformed_items
	malformed["game_state"] = malformed_gs
	_set_mother_record(malformed, chunk, malformed_record)
	_apply_capture(host, chunk, malformed)
	_check(_tagged_item_count(host.game_state, chunk) == 8
			and not host.game_state.items.has(forged_id)
			and int(chunk.get_preview_state().body_physical_source_count) == 8,
		"an unledgered ninth tagged reward retracts to eight construction-source identities")

	await _discard(host)
	await _discard(legacy_pair.host)


func _drive_source(host, source: Node, actor: String) -> bool:
	if not is_instance_valid(source):
		return false
	host.active_character = actor
	host.game_state.snap_character_to(actor, (source as Node3D).global_position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _trigger_body_at_current_position(host, chunk, body_id: String) -> bool:
	var source: Node = chunk._body_interactables.get(body_id)
	if not is_instance_valid(source):
		return false
	host.active_character = "endo"
	source.set("active_character", "endo")
	return bool(source.call("_trigger", false))


func _drive_body_harvest(host, chunk, body_id: String) -> bool:
	return _drive_source(host, chunk._body_interactables.get(body_id), "endo")


func _boot() -> Dictionary:
	var host = HostScript.new()
	host.setup(false)
	var chunk = MotherScript.new()
	host.register_party(chunk.get_spawn_positions())
	for char_id in ["aster", "peris", "endo"]:
		host.game_state.set_stat(char_id, "hp", 100.0)
		host.game_state.set_stat(char_id, "stamina", 100.0)
		host.game_state.set_stat(char_id, "atp", 8.0)
	root.add_child(host)
	chunk.attach_chunk_host(host, FIXTURE_ID)
	host.add_child(chunk)
	await process_frame
	await process_frame
	chunk.reset_preview_state()
	chunk.on_game_state_grid_ready()
	await process_frame
	return {"host": host, "chunk": chunk}


func _tagged_item_count(gs, chunk) -> int:
	var count := 0
	for item_id_v in gs.items.keys():
		if chunk._is_tagged_mother_body_lysate(str(item_id_v)):
			count += 1
	return count


func _tagged_carrier_count(gs, chunk) -> int:
	var count := 0
	for char_id in ["aster", "peris", "endo"]:
		for item_id_v in gs.get_hand_items(char_id) + gs.get_internal_items(char_id):
			if chunk._is_tagged_mother_body_lysate(str(item_id_v)):
				count += 1
	return count


func _enabled_body_count(chunk) -> int:
	var count := 0
	for interactable in chunk._body_interactables.values():
		if is_instance_valid(interactable) and interactable.is_interaction_enabled():
			count += 1
	return count


func _remove_tagged_items_from_snapshot(snapshot: Dictionary, chunk) -> void:
	var gs: Dictionary = snapshot.get("game_state", {})
	var items: Dictionary = gs.get("items", {})
	var remove_ids: Array[String] = []
	for item_id_v in items.keys():
		var item: Dictionary = items[item_id_v]
		var properties: Dictionary = item.get("properties", {})
		if str(properties.get("mother_body_authority", "")) == chunk.mother_authority_key():
			remove_ids.append(str(item_id_v))
	for item_id in remove_ids:
		items.erase(item_id)
	gs["items"] = items
	snapshot["game_state"] = gs


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _mother_record(snapshot: Dictionary, chunk) -> Dictionary:
	var gs: Dictionary = snapshot.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	var raw: Variant = world.get(chunk.mother_authority_key(), {})
	return raw as Dictionary if raw is Dictionary else {}


func _set_mother_record(snapshot: Dictionary, chunk, record: Dictionary) -> void:
	var gs: Dictionary = snapshot.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	world[chunk.mother_authority_key()] = record
	gs["world_state"] = world
	snapshot["game_state"] = gs


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)
	chunk.headless_process(0.0)


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
		if "scheduler" in node and node.scheduler != null:
			node.scheduler.clear()
		node.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
