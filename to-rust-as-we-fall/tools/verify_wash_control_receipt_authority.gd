extends SceneTree

## Focused anti-forgery coverage for every consequential Wash Relay control. The accepted
## Interactable edge must come from this exact registered source and a nearby, ready canonical
## party body. Owner callbacks, manually emitted signals, and a remote selected portrait are inert.

const RelayScene := preload("res://scenes/fragments/chunks/wash_relay_chunk.tscn")
const PARTY: Array[String] = ["aster", "peris", "endo"]
const AUTHORITY_KEY := "chunk:wash_relay"

var _checks := 0
var _failures := 0


class RelayHost extends Node:
	var game_state := GameState.new()
	var scheduler := EventScheduler.new()
	var active_character := "aster"
	var party: Array[String] = PARTY.duplicate()

	func configure(spawns: Dictionary) -> void:
		game_state.scheduler = scheduler
		game_state.set_party(party)
		for char_id in party:
			game_state.register_character(
				char_id, spawns.get(char_id, Vector3.ZERO), 3.0, {
					"hp": 100.0, "max_hp": 100.0,
					"stamina": 100.0, "max_stamina": 100.0,
					"atp": 3.0,
				})

	func get_preview_game_state():
		return game_state

	func get_preview_scheduler():
		return scheduler

	func get_preview_scheduler_tick() -> float:
		return scheduler.get_current_tick()

	func get_preview_character_position(char_id: String) -> Vector3:
		return game_state.get_position(char_id)

	func set_preview_character_position(char_id: String, value: Vector3) -> void:
		game_state.snap_character_to(char_id, value)

	func get_preview_character_move_speed(_char_id: String, _running := false) -> float:
		return 3.0

	func get_preview_active_character() -> String:
		return active_character

	func get_preview_selected_characters() -> Array:
		return party.duplicate()

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(
			char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(
			char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)

	func spawn_preview_item(
			item_type: String, position: Vector3,
			properties: Dictionary = {}) -> String:
		return game_state.spawn_item(item_type, position, properties)

	func remove_preview_item(item_id: String) -> void:
		game_state.remove_item(item_id)

	func pick_up_preview_item(char_id: String, item_id: String) -> bool:
		return game_state.pick_up_item(char_id, item_id)

	func get_preview_item_state(item_id: String) -> Dictionary:
		return game_state.items.get(item_id, {}).duplicate(true)

	func set_preview_step(_step: String) -> void:
		pass

	func register_preview_interactable(_interactable: Node) -> void:
		pass

	func get_preview_dialogue_box():
		return null

	func get_preview_engram_overlay():
		return null

	func show_preview_note(_text: String, _duration := 3.0) -> void:
		pass

	func show_preview_message(_text: String, _duration := 2.0) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var pair := await _boot()
	var host: RelayHost = pair.host
	var chunk: Node = pair.chunk
	var baseline := _capture(host)
	var controls: Dictionary = chunk.get("_wash_control_sources")
	var action_ids: Array = controls.keys()
	action_ids.sort()
	check(not action_ids.is_empty(),
		"Wash Relay registers a physical source for every consequential control")
	for required_prefix in [
		"override:", "cadence:", "branch_cache:", "branch_switch:",
		"pressure_valve", "drain_cache", "drain_flora",
	]:
		check(_first_action_with_prefix(action_ids, required_prefix) != "",
			"control registry includes %s" % required_prefix)

	for action_id_v in action_ids:
		var action_id := str(action_id_v)
		_apply_capture(host, chunk, baseline)
		await _verify_negative_edges(host, chunk, action_id)

	for prefix in [
		"override:", "cadence:", "branch_cache:", "branch_switch:",
		"pressure_valve", "drain_cache", "drain_flora",
	]:
		_apply_capture(host, chunk, baseline)
		var action_id := _ready_action_with_prefix(chunk, prefix)
		check(action_id != "", "baseline exposes one ready %s source" % prefix)
		if action_id != "":
			_verify_exact_success(host, chunk, action_id)

	await _verify_repeatable_controls(host, chunk, baseline)
	await _verify_reusable_flures(host, chunk, baseline)
	await _verify_accepted_finite_source_seam(host, chunk, baseline)
	await _verify_legacy_migration(host, chunk, baseline)

	await _discard(host)
	print("WASH CONTROL RECEIPT AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_negative_edges(
		host: RelayHost, chunk: Node, action_id: String) -> void:
	var control: Dictionary = (
		chunk.get("_wash_control_sources") as Dictionary).get(action_id, {})
	var source: Node = control.get("source")
	var before_count := _owner_count(chunk, action_id)
	var before_token := _semantic_token(chunk, action_id)
	check(not _invoke_owner_direct(chunk, action_id),
		"%s source-less owner callback is inert" % action_id)
	if is_instance_valid(source):
		source.interacted.emit()
	check(_owner_count(chunk, action_id) == before_count \
			and _semantic_token(chunk, action_id) == before_token,
		"%s manually emitted signal cannot forge a receipt" % action_id)
	var actor := _actor_for_source(source)
	var source_position := _source_position(host, source)
	host.game_state.command_stop(actor)
	host.game_state.snap_character_to(
		actor, source_position + Vector3(20.0, 0.0, 20.0))
	source.set("active_character", actor)
	check(not bool(source.call("_trigger", false)),
		"%s remote selected portrait is rejected" % action_id)
	check(_owner_count(chunk, action_id) == before_count \
			and _semantic_token(chunk, action_id) == before_token,
		"%s rejected remote use leaves owner truth unchanged" % action_id)


func _verify_exact_success(
		host: RelayHost, chunk: Node, action_id: String) -> void:
	var control: Dictionary = (
		chunk.get("_wash_control_sources") as Dictionary).get(action_id, {})
	var source: Node = control.get("source")
	var before_count := _owner_count(chunk, action_id)
	var before_token := _semantic_token(chunk, action_id)
	check(_trigger_exact(host, source, _actor_for_source(source)),
		"%s accepts its exact nearby ready party body" % action_id)
	check(_owner_count(chunk, action_id) == before_count + 1,
		"%s consumes exactly the next monotonic source receipt" % action_id)
	check(_semantic_token(chunk, action_id) != before_token \
			or str(control.get("kind", "")) == "override",
		"%s changes only its typed owner consequence" % action_id)
	if bool(control.get("one_shot", false)):
		check(not bool(source.call("is_interaction_enabled")),
			"%s finite source remains spent after its owner consequence" % action_id)


func _verify_repeatable_controls(
		host: RelayHost, chunk: Node, baseline: Dictionary) -> void:
	for prefix in ["override:", "cadence:", "pressure_valve"]:
		_apply_capture(host, chunk, baseline)
		var action_id := _ready_action_with_prefix(chunk, prefix)
		if action_id == "":
			continue
		var control: Dictionary = (
			chunk.get("_wash_control_sources") as Dictionary)[action_id]
		var source: Node = control.get("source")
		var actor := _actor_for_source(source)
		check(_trigger_exact(host, source, actor),
			"%s repeatable fixture accepts its first receipt" % action_id)
		match str(control.get("kind", "")):
			"pressure_valve":
				chunk.call("_on_pressure_vent_closed")
		chunk.call("headless_process", 0.0)
		check(bool(source.call("is_interaction_enabled")),
			"%s physically rearms after its causal reset" % action_id)
		check(_trigger_exact(host, source, actor),
			"%s accepts a second honest physical use" % action_id)
		check(_owner_count(chunk, action_id) == 2,
			"%s retry advances rather than reusing receipt one" % action_id)


func _verify_reusable_flures(
		host: RelayHost, chunk: Node, baseline: Dictionary) -> void:
	for fixture in [
		{"name": "Flure0", "target": "ch_sentry", "legacy": "_on_lure"},
		{"name": "DrainBait", "target": "ch_drain", "legacy": "_on_drain_bait"},
	]:
		_apply_capture(host, chunk, baseline)
		var fixture_name := str(fixture.get("name", ""))
		var source: Node = chunk.find_child(fixture_name, true, false)
		check(source is Flure,
			"%s is the reusable Flure object, not a generic box" % fixture_name)
		var target := str(fixture.get("target", ""))
		var before_distracted := host.game_state.is_character_distracted(target)
		var legacy := str(fixture.get("legacy", ""))
		if legacy == "_on_lure":
			check(not bool(chunk.call(legacy, 0)),
				"%s legacy chunk callback cannot forge a lure" % fixture_name)
		else:
			check(not bool(chunk.call(legacy)),
				"%s legacy chunk callback cannot forge a lure" % fixture_name)
		if is_instance_valid(source):
			source.interacted.emit()
		check(host.game_state.is_character_distracted(target) == before_distracted,
			"%s manually emitted signal cannot forge a target receipt" % fixture_name)
		var source_position := _source_position(host, source)
		host.game_state.snap_character_to(
			"peris", source_position + Vector3(20.0, 0.0, 20.0))
		source.set("active_character", "peris")
		check(not bool(source.call("_trigger", false)),
			"%s rejects a remote selected portrait" % fixture_name)
		check(_trigger_exact(host, source, "peris"),
			"%s accepts its exact nearby ready party body" % fixture_name)
		var effect: Dictionary = source.call("get_effect_state")
		check(str(effect.get("phase", "")) in ["applying", "active"] \
				and host.game_state.is_character_distracted(target),
			"%s owns the saved song and exact Enemy lure consequence" % fixture_name)
		var duplicated := false
		for control_v in (
				chunk.get("_wash_control_sources") as Dictionary).values():
			if control_v is Dictionary \
					and (control_v as Dictionary).get("source") == source:
				duplicated = true
				break
		check(not duplicated,
			"%s is not duplicated in Wash's legacy receipt registry" % fixture_name)


func _verify_accepted_finite_source_seam(
		host: RelayHost, chunk: Node, baseline: Dictionary) -> void:
	_apply_capture(host, chunk, baseline)
	var action_id := "drain_flora"
	var source: Node = (
		(chunk.get("_wash_control_sources") as Dictionary)[action_id]
		as Dictionary).get("source")
	var actor := _actor_for_source(source)
	var captured := {"snapshot": {}}
	var listener := func(source_id: String, _actor: String) -> void:
		if source_id == str(source.get("data_id")) \
				and (captured.snapshot as Dictionary).is_empty():
			captured.snapshot = _capture(host)
	host.game_state.interactable_triggered.connect(listener, CONNECT_ONE_SHOT)
	check(_trigger_exact(host, source, actor),
		"finite flora fixture reaches the accepted-before-owner signal seam")
	var accepted: Dictionary = captured.snapshot
	check(not accepted.is_empty(),
		"signal-time snapshot captures the exact accepted flora source")
	_apply_capture(host, chunk, accepted)
	_apply_capture(host, chunk, accepted)
	source = (
		(chunk.get("_wash_control_sources") as Dictionary)[action_id]
		as Dictionary).get("source")
	check(not bool(chunk.get("_drain_flora_tended")) \
			and bool(source.call("is_interaction_enabled")) \
			and _owner_count(chunk, action_id) == 1,
		"same presenter burns but does not grant an accepted pre-owner tend")
	check(_trigger_exact(host, source, actor) \
			and bool(chunk.get("_drain_flora_tended")) \
			and _owner_count(chunk, action_id) == 2,
		"same presenter can spend the next exact flora receipt normally")

	var fresh_pair := await _boot()
	var fresh_host: RelayHost = fresh_pair.host
	var fresh: Node = fresh_pair.chunk
	_apply_capture(fresh_host, fresh, accepted)
	_apply_capture(fresh_host, fresh, accepted)
	var fresh_source: Node = (
		(fresh.get("_wash_control_sources") as Dictionary)[action_id]
		as Dictionary).get("source")
	check(not bool(fresh.get("_drain_flora_tended")) \
			and bool(fresh_source.call("is_interaction_enabled")) \
			and _owner_count(fresh, action_id) == 1,
		"fresh presenter also retracts the accepted pre-owner tend")
	check(_trigger_exact(fresh_host, fresh_source, actor) \
			and bool(fresh.get("_drain_flora_tended")),
		"fresh presenter requires a new physical flora receipt")
	await _discard(fresh_host)


func _verify_legacy_migration(
		host: RelayHost, chunk: Node, baseline: Dictionary) -> void:
	_apply_capture(host, chunk, baseline)
	var action_id := _ready_action_with_prefix(chunk, "cadence:")
	var source: Node = (
		(chunk.get("_wash_control_sources") as Dictionary)[action_id]
		as Dictionary).get("source")
	check(_trigger_exact(host, source, _actor_for_source(source)),
		"legacy fixture first earns one exact cadence read")
	var legacy := _capture(host)
	var legacy_gs: Dictionary = legacy.get("game_state", {})
	var world: Dictionary = legacy_gs.get("world_state", {})
	var wash: Dictionary = world.get(AUTHORITY_KEY, {})
	wash["version"] = 6
	wash.erase("control_committed_counts")
	world[AUTHORITY_KEY] = wash
	legacy_gs["world_state"] = world
	legacy["game_state"] = legacy_gs
	_apply_capture(host, chunk, legacy)
	var migrated: Dictionary = host.game_state.get_world_state(
		AUTHORITY_KEY, {})
	check(int(migrated.get("version", 0)) == int(chunk.WASH_AUTHORITY_VERSION) \
			and _owner_count(chunk, action_id) \
				== int(host.game_state.get_interactable(
					str(source.get("data_id"))).get("trigger_count", -1)),
		"v6 Wash state preserves its physical result and seeds exact registry counts")


func _invoke_owner_direct(chunk: Node, action_id: String) -> bool:
	var control: Dictionary = (
		chunk.get("_wash_control_sources") as Dictionary).get(action_id, {})
	var kind := str(control.get("kind", ""))
	var index := int(control.get("index", -1))
	match kind:
		"override":
			return bool(chunk.call("_on_override", index))
		"cadence":
			return bool(chunk.call("_on_cadence_read", index))
		"branch_cache":
			return bool(chunk.call("_on_branch_cache", index))
		"branch_switch":
			return bool(chunk.call("_on_branch_switch", index))
		"pressure_valve":
			return bool(chunk.call("_on_pressure_valve"))
		"drain_cache":
			return bool(chunk.call("_on_drain_cache"))
		"drain_bait":
			return bool(chunk.call("_on_drain_bait"))
		"drain_flora":
			return bool(chunk.call("_on_drain_flora_tended"))
		"lure":
			return bool(chunk.call("_on_lure", index))
	return false


func _semantic_token(chunk: Node, action_id: String) -> String:
	var control: Dictionary = (
		chunk.get("_wash_control_sources") as Dictionary).get(action_id, {})
	var kind := str(control.get("kind", ""))
	var index := int(control.get("index", -1))
	match kind:
		"override":
			return str(_owner_count(chunk, action_id))
		"cadence":
			return "%s:%s" % [
				chunk.get("_cadence_read_section"),
				chunk.get("_cadence_read_until"),
			]
		"branch_cache":
			var branch := (
				chunk.get("_branches") as Array)[index] as Dictionary
			return "%s:%s" % [
				branch.get("reward_phase", ""),
				branch.get("reward_item_id", ""),
			]
		"branch_switch":
			var branch := (
				chunk.get("_branches") as Array)[index] as Dictionary
			return "%s:%s" % [
				branch.get("mechanism_phase", ""),
				branch.get("phase_deadline", -1.0),
			]
		"pressure_valve":
			return str(chunk.get("_pressure_vent_until"))
		"drain_cache":
			return str((chunk.get("_drain_reward") as Dictionary).get(
				"reward_phase", ""))
		"drain_bait":
			return str(chunk.get("_drain_bait_until"))
		"drain_flora":
			return str(chunk.get("_drain_flora_tended"))
		"lure":
			var lure_until: Array = chunk.get("_lure_until")
			return str(lure_until[index] if index < lure_until.size() else -1.0)
	return ""


func _ready_action_with_prefix(chunk: Node, prefix: String) -> String:
	var ids: Array = (
		chunk.get("_wash_control_sources") as Dictionary).keys()
	ids.sort()
	for action_id_v in ids:
		var action_id := str(action_id_v)
		if action_id.begins_with(prefix) \
				and bool(chunk.call(
					"_wash_control_action_ready", action_id, "")):
			return action_id
	return ""


func _first_action_with_prefix(ids: Array, prefix: String) -> String:
	for action_id_v in ids:
		var action_id := str(action_id_v)
		if action_id.begins_with(prefix):
			return action_id
	return ""


func _owner_count(chunk: Node, action_id: String) -> int:
	return int((chunk.get("_wash_control_committed_counts") as Dictionary).get(
		action_id, 0))


func _actor_for_source(source: Node) -> String:
	var required := str(source.get("required_character")) \
		if is_instance_valid(source) else ""
	return required if required != "" else "aster"


func _source_position(host: RelayHost, source: Node) -> Vector3:
	var data_id := str(source.get("data_id")) if is_instance_valid(source) else ""
	return host.game_state.get_interactable(data_id).get(
		"position", Vector3.INF) \
		if data_id != "" and host.game_state.has_interactable(data_id) \
		else Vector3.INF


func _trigger_exact(host: RelayHost, source: Node, actor: String) -> bool:
	if not is_instance_valid(source) or not host.game_state.characters.has(actor):
		return false
	host.game_state.command_stop(actor)
	host.game_state.snap_character_to(actor, _source_position(host, source))
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _boot() -> Dictionary:
	var resource = load("res://data/fragments/wash_relay.tres")
	var host := RelayHost.new()
	host.configure(resource.spawns)
	root.add_child(host)
	var chunk: Node = RelayScene.instantiate()
	chunk.call("attach_chunk_host", host, "wash_relay")
	host.add_child(chunk)
	await process_frame
	host.game_state.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	chunk.call("reset_preview_state")
	chunk.call("headless_process", 0.0)
	await process_frame
	return {"host": host, "chunk": chunk}


func _capture(host: RelayHost) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(
		host: RelayHost, chunk: Node, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_snapshot_restored(chunk)
	chunk.call("headless_process", 0.0)


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
