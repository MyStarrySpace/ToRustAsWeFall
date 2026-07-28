extends Node

## Focused regression for the restored Channels causal core.
## The filename is retained so existing CI entry points keep working.

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const ACT1_SOURCE_PATH := "res://scripts/tutorial/act1_sequence.gd"

var _failures: Array[String] = []


func _ready() -> void:
	EventLog.print_events = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	var act1 := await _spawn_channels()
	if act1 == null:
		_failures.append("Act 1 Channels instance boots")
		_finish()
		return
	_verify_causal_structure(act1)
	_verify_window_handoffs(act1)
	_verify_optional_worldbuilding(act1)
	_verify_shelter_rest_authority(act1)
	await _dispose(act1)
	_finish()


func _spawn_channels() -> Node:
	var act1 := ACT1_SCENE.instantiate()
	act1.set("start_chunk", "channels")
	act1.set("suppress_scene_change", true)
	get_tree().root.add_child(act1)
	for _frame in range(10):
		await get_tree().process_frame
	return act1


func _verify_causal_structure(act1: Node) -> void:
	print("\n=== Channels causal structure ===")
	var source := FileAccess.get_file_as_string(ACT1_SOURCE_PATH)
	_check(not source.contains("CHANNELS_FIELD_OPERATIONS"), "retired operation table is absent")
	_check(not source.contains("CHANNELS_FIELD_SITES"), "retired evidence-site table is absent")
	_check(not source.contains("_start_channels_field_operation"), "retired field-operation dispatcher is absent")
	_check(act1.find_child("ChannelsFieldwork", true, false) == null,
		"no mandatory fieldwork layer is constructed")
	_check(act1.find_child("ChannelsOperationLandmarks", true, false) == null,
		"no checklist rooms remain after the authored hydraulic route")
	var optional_sites := act1.find_children("ChannelsOptional_*", "Interactable", true, false)
	_check(optional_sites.size() == act1.CHANNELS_OPTIONAL_SITES.size(),
		"the six optional worldbuilding reads remain real interactables")

	var contract: Dictionary = act1.get_channels_playtime_contract()
	_check(str(contract.get("measurement_kind", "")) == "causal_structure_not_first_clear_elapsed",
		"contract reports causal structure, not synthetic first-clear time")
	_check(int(contract.get("window_count", 0)) == 2,
		"both hydraulic timing windows remain in the causal core")
	_check(int(contract.get("mandatory_checklist_operation_count", -1)) == 0
		and int(contract.get("mandatory_checklist_action_count", -1)) == 0,
		"contract contains no mandatory checklist padding")
	_check(not contract.has("meaningful_active_seconds")
		and not contract.has("modeled_first_clear_seconds")
		and not contract.has("target_min_seconds"),
		"contract makes no unobserved duration claim")
	var beats: Array = contract.get("required_causal_beats", [])
	for beat in [
		"memory_at_body", "window_one_lure_and_flow", "flure_flush",
		"window_two_lure_and_flow", "lure_hide_run_encounter", "shelter_rest_and_shortcut",
	]:
		_check(beats.has(beat), "causal measurement retains %s" % beat)

	var lane_state: Dictionary = act1.get("_channels_window_lanes")
	_check(lane_state.size() == 2, "both playable window lanes are constructed")
	for window_id in ["window_one", "window_two"]:
		var lane: Dictionary = lane_state.get(window_id, {})
		_check(not lane.is_empty(), "%s has authored state" % window_id)
		_check((lane.get("periodic_channels", []) as Array).size() >= 3,
			"%s exposes multiple flow phases to read" % window_id)
		_check((lane.get("enemy_ids", []) as Array).size() > 0,
			"%s has registered Enemy bodies whose wash outcome follows the timing prediction" % window_id)


func _verify_window_handoffs(act1: Node) -> void:
	print("\n=== Channels direct causal handoffs ===")
	_check(_wash_window_through_real_channel(act1, "window_one"),
		"the first Flure leads its registered Enemy pack into a real carrying current")
	var window_one: Dictionary = act1._channels_window_lanes["window_one"]
	for char_id in act1.CHANNELS_PARTY_IDS:
		act1.headless_set_character_position(char_id, window_one["goal_pos"])
	act1._evaluate_channels_window_authority()
	_check(str(act1._current_step) == "channels_to_flure",
		"full-party first-window arrival hands to the ferrolure beat")
	_check(_wash_window_through_real_channel(act1, "window_two"),
		"the second Flure leads its registered Enemy pack into a real carrying current")
	var window_two: Dictionary = act1._channels_window_lanes["window_two"]
	for char_id in act1.CHANNELS_PARTY_IDS:
		act1.headless_set_character_position(char_id, window_two["goal_pos"])
	act1._evaluate_channels_window_authority()
	_check(str(act1._current_step) == "channels_to_encounter",
		"full-party second-window arrival hands to the lure-hide-run encounter")


func _wash_window_through_real_channel(act1: Node, window_id: String) -> bool:
	act1.start_channels_window_puzzle(window_id)
	act1._scheduler.resume()
	var lane: Dictionary = act1._channels_window_lanes.get(window_id, {})
	var flure := act1._valid_channels_flure(lane) as Flure
	if not _trigger_flure(act1, flure, "peris"):
		return false
	var entries: Array = lane.get("periodic_channels", [])
	var enemy_ids: Array = lane.get("enemy_ids", [])
	if entries.is_empty() or enemy_ids.is_empty():
		return false
	var entry: Dictionary = entries[0]
	var channel: Channel = entry.get("channel")
	var channel_position: Vector3 = entry.get("position", Vector3.ZERO)
	if not is_instance_valid(channel):
		return false
	# Keep the party clear of the forced contact used by this focused verifier. The production
	# route earns that separation by timing the crossing after the visible carry.
	var safe_observer_position := channel_position + Vector3(-40.0, 0.0, 40.0)
	for char_id in act1.CHANNELS_PARTY_IDS:
		act1.headless_set_character_position(char_id, safe_observer_position)
	for enemy_id_v in enemy_ids:
		var enemy_id := str(enemy_id_v)
		act1._game_state.command_stop(enemy_id)
		act1._game_state.snap_character_to(enemy_id, channel_position)
	channel.flood_now()
	act1.headless_advance(0.061, 0.001)
	var last_arrival := -1.0
	for enemy_id_v in enemy_ids:
		var traversal: Dictionary = act1._game_state.get_external_traversal_state(
			str(enemy_id_v))
		if str(traversal.get("traversal_id", "")).begins_with("channel_sweep/"):
			last_arrival = maxf(last_arrival, float(traversal.get("end_tick", -1.0)))
	if last_arrival < 0.0:
		return false
	act1.headless_advance(
		maxf(0.0, last_arrival - float(act1._scheduler.get_current_tick())) + 0.01,
		0.01)
	lane = act1._channels_window_lanes.get(window_id, {})
	return act1._channels_scope_is_fully_swept(
		lane.get("enemy_ids", []), lane.get("swept_ids", []))


func _trigger_flure(act1: Node, flure: Flure, actor: String) -> bool:
	if flure == null:
		return false
	act1._game_state.command_stop(actor)
	act1._game_state.snap_character_to(actor, flure.get_source_data_position())
	act1._select_character(actor)
	flure.active_character = actor
	return bool(flure.call("_trigger", false))


func _verify_optional_worldbuilding(act1: Node) -> void:
	print("\n=== Channels optional worldbuilding ===")
	act1.prepare_channels_fragment()
	var seed_spec: Dictionary = act1.CHANNELS_OPTIONAL_SITES["optional_seed_cache"]
	var report_spec: Dictionary = act1.CHANNELS_OPTIONAL_SITES["optional_report_stub"]
	_check(str(seed_spec.get("verb", "")).begins_with("INSPECT")
			and not str(seed_spec.get("finding", "")).contains("recover")
			and str(seed_spec.get("finding", "")).contains("leaves"),
		"the seed cache is explicitly inspected in place rather than falsely collected")
	_check(str(report_spec.get("verb", "")).begins_with("READ")
			and not str(report_spec.get("finding", "")).contains("recover")
			and str(report_spec.get("finding", "")).contains("in place"),
		"the fixed report page is explicitly read in place rather than falsely collected")
	var seed_visual: Node = act1.get("_channels_optional_visuals").get("optional_seed_cache")
	var report_visual: Node = act1.get("_channels_optional_visuals").get("optional_report_stub")
	_check(seed_visual != null
			and seed_visual.find_child("SeedCacheCradle", true, false) != null
			and seed_visual.find_children("SealedSeedPod*", "MeshInstance3D", true, false).size() == 4,
		"seed evidence has a distinct visible cradle with four sealed pods")
	_check(report_visual != null
			and report_visual.find_child("ReportLectern", true, false) != null
			and report_visual.find_child("FixedReportPage", true, false) != null,
		"report evidence has a distinct fixed lectern and readable page assembly")
	for site_id_variant in act1.CHANNELS_OPTIONAL_SITES.keys():
		var site_id := str(site_id_variant)
		var site: Node = act1.get("_channels_optional_sites").get(site_id)
		_check(site != null and not site.is_interaction_enabled(),
			"%s does not gate the authored route" % site_id)
	act1._start_channels_explore()
	var first_id := str(act1.CHANNELS_OPTIONAL_SITES.keys()[0])
	var first_site: Node = act1.get("_channels_optional_sites").get(first_id)
	for site_id_variant in act1.CHANNELS_OPTIONAL_SITES.keys():
		var site_id := str(site_id_variant)
		var site: Node = act1.get("_channels_optional_sites").get(site_id)
		_check(site != null and site.is_interaction_enabled(),
			"%s opens only in free exploration" % site_id)

	var required := str(act1.CHANNELS_OPTIONAL_SITES[first_id].get("role", ""))
	var wrong := "peris" if required != "peris" else "aster"
	first_site.set("active_character", wrong)
	first_site.call("_trigger", false)
	var optional_state: Dictionary = act1.headless_get_state().get("channels_optional_worldbuilding", {})
	_check(int(optional_state.get("optional_count", 0)) == 0,
		"wrong specialist cannot consume an optional read")
	first_site.set("active_character", required)
	first_site.call("_trigger", false)
	optional_state = act1.headless_get_state().get("channels_optional_worldbuilding", {})
	_check(int(optional_state.get("optional_count", 0)) == 1,
		"correct specialist records one optional finding")
	_check(str(act1._current_step) == "channels_explore",
		"optional worldbuilding never becomes a progression gate")


func _verify_shelter_rest_authority(act1: Node) -> void:
	print("\n=== Channels shelter rest authority ===")
	act1.prepare_channels_fragment()
	for char_id in ["aster", "peris", "endo"]:
		act1.headless_set_character_position(char_id, act1.CHANNELS_SHELTER_POS)
		act1._game_state.set_stat(char_id, "hp", 80.0)
		act1._game_state.set_stat(char_id, "stamina", 20.0)
		act1._game_state.set_stat(char_id, "atp", 3.0)
	act1._current_step = "channels_shelter"
	act1._on_channels_shelter_party_arrived()
	_check(act1._channels_shelter_reached and not act1._channels_party_recuperated
		and not act1._channels_shelter_interactable.interaction_enabled,
		"party arrival keeps the proximity hearth locked throughout its introduction")
	for char_id in ["aster", "peris", "endo"]:
		_check(not act1._game_state.is_resting(char_id)
				and is_equal_approx(act1._game_state.get_stat(char_id, "atp"), 3.0),
			"%s remains unpaid and awake before REST PARTY" % char_id)
	act1._dialogue.clear()
	act1._enable_channels_shelter_rest()
	_check(act1._channels_shelter_interactable.interaction_enabled,
		"the named introduction completion arms the explicit REST PARTY control")
	act1._select_character("aster")
	act1._channels_shelter_interactable.active_character = "aster"
	_check(bool(act1._channels_shelter_interactable._trigger(false)),
		"REST PARTY enters through the real Channels hearth interaction")
	_check(act1._channels_party_recuperated,
		"present conscious party members can begin the explicit shelter rest")
	for char_id in ["aster", "peris", "endo"]:
		_check(act1._game_state.is_resting(char_id), "%s rests through GameState" % char_id)
		_check(is_equal_approx(act1._game_state.get_stat(char_id, "atp"), 2.0),
			"%s pays the shared one-pip rest cost" % char_id)
		_check(is_equal_approx(act1._game_state.get_stat(char_id, "hp"), 80.0),
			"%s is not healed instantly by scene-local mutation" % char_id)
	act1.headless_advance(1.1, 0.05)
	for char_id in ["aster", "peris", "endo"]:
		_check(act1._game_state.get_stat(char_id, "hp") > 80.0
			and act1._game_state.get_stat(char_id, "hp") < act1._game_state.get_stat_cap(char_id, "hp"),
			"%s recovers incrementally while resting" % char_id)
	act1.headless_advance(22.0, 0.05)
	for char_id in ["aster", "peris", "endo"]:
		_check(is_equal_approx(
			act1._game_state.get_stat(char_id, "hp"),
			act1._game_state.get_stat_cap(char_id, "hp")
		), "%s completes recovery through the shared rest loop" % char_id)


func _dispose(act1: Node) -> void:
	if act1 != null and is_instance_valid(act1):
		act1.set_process(false)
		act1.set_physics_process(false)
		if act1.has_method("_teardown_sequence"):
			act1._teardown_sequence()
		act1.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nChannels causal-core verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nChannels causal-core verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)
