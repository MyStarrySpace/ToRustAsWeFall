extends SceneTree

## The Wash Intro used to inspect channel overlap every render/update call, teleport party members,
## damage hunters directly, and remember the solve only in scene-local counters. This regression
## proves the visible Channel kit is the sole consequence path, that its room-level result is
## portable across rollback and fresh reconstruction, and that the whole-party exit is decided
## only by its saved fixed scheduler cadence.

const PreviewScene := preload("res://scenes/fragments/fragment_preview.tscn")
const PARTY := ["aster", "peris", "endo"]
const POLL_EPSILON := 0.001

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source = await _spawn_preview()
	if source == null:
		_finish()
		return
	var chunk = source._active_chunk
	var gs: GameState = source._game_state
	var scheduler: EventScheduler = source._scheduler
	source.headless_advance(0.1, 0.1)

	var baseline := _json_round_trip(source.build_save_snapshot())
	var authority_key := str(chunk._fragment_authority_key())
	var channel = chunk.channels()[0]
	var channel_x := 11.0
	gs.snap_character_to("aster", Vector3(channel_x, 0.5, 0.0))
	chunk._channel_onset(0)
	var pre_sweep := _json_round_trip(source.build_save_snapshot())
	var pre_tick := float(scheduler.get_current_tick())
	var next_poll := float(channel.get_state().get("next_sweep_tick", -1.0))
	check(next_poll > pre_tick and channel.is_flooding() and _water_visible(channel),
		"entering a live wash stores its visible wet phase and absolute sweep deadline")

	for _frame in range(240):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	check(gs.get_position("aster").distance_to(Vector3(channel_x, 0.5, 0.0)) < 0.01
			and int(chunk.get_preview_state().get("washed_back", -1)) == 0,
		"render/headless presentation calls cannot perform the sweep without scheduler time")

	source.headless_advance(next_poll - float(scheduler.get_current_tick()) - POLL_EPSILON,
		POLL_EPSILON)
	check(gs.get_position("aster").x > 10.0,
		"the party member remains in the channel before the exact kit poll")
	source.headless_advance(POLL_EPSILON * 1.1, POLL_EPSILON * 1.1)
	var party_carry := gs.get_external_traversal_state("aster")
	var party_arrival := float(party_carry.get("end_tick", -1.0))
	check(gs.is_external_traversal_active("aster")
			and str(party_carry.get("traversal_id", "")).begins_with("channel_sweep/")
			and int(chunk.get_preview_state().get("washed_back", -1)) == 0,
		"the exact kit poll begins a locked physical carry without granting its endpoint")
	var carry_half := (party_arrival - float(scheduler.get_current_tick())) * 0.5
	source.headless_advance(carry_half, maxf(POLL_EPSILON, carry_half))
	var party_midpoint := _json_round_trip(source.build_save_snapshot())
	var party_mid_position := gs.get_position("aster")
	var party_mid_progress := float(gs.get_external_traversal_state("aster").get("progress", -1.0))
	check(party_mid_progress > 0.0 and party_mid_progress < 1.0
			and party_mid_position.distance_to(Vector3(channel_x, 0.5, 0.0)) > 0.05
			and party_mid_position.distance_to(chunk._wash_back) > 0.05,
		"the current exposes an authoritative in-between body position")
	_advance_across(source, party_arrival)
	check(gs.get_position("aster").distance_to(chunk._wash_back) < 0.01
			and int(chunk.get_preview_state().get("washed_back", -1)) == 1,
		"arrival commits the shelter endpoint and room bookkeeping together")
	var post_party_sweep := _json_round_trip(source.build_save_snapshot())

	source.apply_save_snapshot(party_midpoint)
	var restored_party_carry := gs.get_external_traversal_state("aster")
	check(gs.is_external_traversal_active("aster")
			and is_equal_approx(float(restored_party_carry.get("progress", -2.0)), party_mid_progress)
			and gs.get_position("aster").distance_to(party_mid_position) < 0.01
			and int(chunk.get_preview_state().get("washed_back", -1)) == 0,
		"mid-carry rollback restores exact progress and withholds the endpoint consequence")
	_advance_across(source, party_arrival)
	check(int(chunk.get_preview_state().get("washed_back", -1)) == 1,
		"restored current commits exactly one arrival consequence")

	source.apply_save_snapshot(pre_sweep)
	check(channel.is_flooding() and _water_visible(channel)
			and gs.get_position("aster").distance_to(Vector3(channel_x, 0.5, 0.0)) < 0.01
			and not gs.is_external_traversal_active("aster")
			and int(chunk.get_preview_state().get("washed_back", -1)) == 0,
		"same-presenter rollback retracts the later sweep and restores wet presentation")
	_advance_across(source, next_poll)
	var rolled_arrival := float(gs.get_external_traversal_state("aster").get("end_tick", -1.0))
	check(gs.is_external_traversal_active("aster"),
		"rolled-back channel rediscovers the body once at its original poll")
	_advance_across(source, rolled_arrival)
	check(gs.get_position("aster").distance_to(chunk._wash_back) < 0.01
			and int(chunk.get_preview_state().get("washed_back", -1)) == 1,
		"rolled-back physical carry commits once at its original arrival")

	source.apply_save_snapshot(post_party_sweep)
	var swept_count := int(chunk.get_preview_state().get("washed_back", -1))
	source.headless_advance(0.6, 0.05)
	check(int(chunk.get_preview_state().get("washed_back", -1)) == swept_count,
		"post-sweep refractory survives load and cannot duplicate the party consequence")

	# A hunter must be physically inside visible flood. Merely calling the old scene helper does
	# nothing; the channel moves the body out of its bed and applies lethal wash damage itself.
	var enemy = chunk.enemies()[0]
	var enemy_id := str(enemy.char_id)
	check(not chunk.has_method("_drown_enemy") and enemy.is_alive(),
		"the former direct-drown bypass no longer exists")
	gs.snap_character_to(enemy_id, Vector3(channel_x, 0.5, 0.5))
	chunk._channel_onset(0)
	var enemy_deadline := float(channel.get_state().get("next_sweep_tick", -1.0))
	var enemy_pre_sweep := _json_round_trip(source.build_save_snapshot())
	for _frame in range(120):
		chunk._process(1.0 / 60.0)
	check(enemy.is_alive(), "presentation frames cannot drown a hunter")
	_advance_across(source, enemy_deadline)
	var enemy_carry := gs.get_external_traversal_state(enemy_id)
	var enemy_arrival := float(enemy_carry.get("end_tick", -1.0))
	check(gs.is_external_traversal_active(enemy_id) and enemy.is_alive()
			and int(chunk.get_preview_state().get("drowned", -1)) == 0,
		"catching a hunter begins a carry but cannot drown it before arrival")
	var enemy_half := (enemy_arrival - float(scheduler.get_current_tick())) * 0.5
	source.headless_advance(enemy_half, maxf(POLL_EPSILON, enemy_half))
	var enemy_midpoint := _json_round_trip(source.build_save_snapshot())
	var enemy_mid_position := gs.get_position(enemy_id)
	var enemy_mid_progress := float(gs.get_external_traversal_state(enemy_id).get("progress", -1.0))
	_advance_across(source, enemy_arrival)
	check(not enemy.is_alive()
			and absf(gs.get_position(enemy_id).z) >= chunk.ENEMY_WASH_EDGE_Z - 0.01
			and int(chunk.get_preview_state().get("drowned", -1)) == 1,
		"Channel arrival carries and drowns the hunter instead of killing it in place")
	var one_drowned := _json_round_trip(source.build_save_snapshot())

	source.apply_save_snapshot(enemy_midpoint)
	check(enemy.is_alive() and gs.is_external_traversal_active(enemy_id)
			and is_equal_approx(float(gs.get_external_traversal_state(enemy_id).get("progress", -2.0)),
				enemy_mid_progress)
			and gs.get_position(enemy_id).distance_to(enemy_mid_position) < 0.01
			and int(chunk.get_preview_state().get("drowned", -1)) == 0,
		"mid-carry hunter restore keeps the body alive and the impact uncommitted")
	_advance_across(source, enemy_arrival)
	check(not enemy.is_alive() and int(chunk.get_preview_state().get("drowned", -1)) == 1,
		"mid-carry hunter restore commits one drown at its original arrival")

	# Rollback before impact must restore the live hunter, its source position, the room counter,
	# and one due poll. Enemy and Channel reconstruct from their own kit records.
	source.apply_save_snapshot(enemy_pre_sweep)
	check(enemy.is_alive() and int(chunk.get_preview_state().get("drowned", -1)) == 0
			and gs.get_position(enemy_id).distance_to(Vector3(channel_x, 0.5, 0.5)) < 0.01,
		"pre-impact rollback restores a live hunter and retracts the drowned counter")
	_advance_across(source, enemy_deadline)
	var restored_enemy_arrival := float(
		gs.get_external_traversal_state(enemy_id).get("end_tick", -1.0))
	_advance_across(source, restored_enemy_arrival)
	check(not enemy.is_alive() and int(chunk.get_preview_state().get("drowned", -1)) == 1,
		"restored hunter is carried and drowned exactly once")

	var fresh = await _spawn_preview()
	if fresh != null:
		fresh.apply_save_snapshot(one_drowned)
		var fresh_chunk = fresh._active_chunk
		var fresh_enemy = fresh_chunk.enemies()[0]
		check(not fresh_enemy.is_alive()
				and int(fresh_chunk.get_preview_state().get("drowned", -1)) == 1
				and absf(fresh._game_state.get_position(str(fresh_enemy.char_id)).z)
					>= fresh_chunk.ENEMY_WASH_EDGE_Z - 0.01,
			"fresh presenter reconstructs the drowned body and room progress from saved authority")
		await _discard(fresh)

	# Finish the second hunter through another real Channel, then isolate the exit predicate. Merely
	# drawing frames or invoking the headless presenter cannot discover a gathered party.
	check(_drown_remaining_hunters(source, chunk),
		"both stable hunters acquire physical downstream drown results before exit testing")
	check(bool(chunk.call("_all_hunters_physically_drowned")),
		"exit preflight reads the complete physical hunter result")
	var exit_state: Dictionary = chunk.get_preview_state()
	var partial_deadline := float(exit_state.get("next_exit_spatial_tick", -1.0))
	check(partial_deadline > float(scheduler.get_current_tick()),
		"the room publishes one future fixed-cadence exit receipt")
	gs.snap_character_to("aster", chunk._exit_pos)
	gs.snap_character_to("peris", chunk._exit_pos)
	gs.snap_character_to("endo", chunk._exit_pos + Vector3(chunk._exit_radius + 1.0, 0.0, 0.0))
	for _frame in range(240):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	check(str(chunk.get_preview_state().get("phase", "")) != "complete"
			and not bool(chunk.get_preview_state().get("exit_waiting_notified", false)),
		"render and headless presenter calls cannot evaluate a partial exit")
	_advance_scheduler_across(scheduler, partial_deadline)
	exit_state = chunk.get_preview_state()
	check(str(exit_state.get("phase", "")) != "complete"
			and bool(exit_state.get("exit_waiting_notified", false))
			and float(exit_state.get("next_exit_spatial_tick", -1.0))
				> float(scheduler.get_current_tick()),
		"the exact cadence tick records a partial gather and one future receipt")

	# Presence alone is insufficient: the complete authored party must also be conscious at the
	# sampled boundary. Restoring Endo does not grant completion between cadence edges.
	gs.snap_character_to("endo", chunk._exit_pos)
	gs.down_character("endo")
	var downed_deadline := float(chunk.get_preview_state().get("next_exit_spatial_tick", -1.0))
	_advance_scheduler_across(scheduler, downed_deadline)
	check(str(chunk.get_preview_state().get("phase", "")) != "complete",
		"a gathered but downed party member blocks the whole-party exit receipt")
	gs.restore_character("endo")
	var completion_deadline := float(
		chunk.get_preview_state().get("next_exit_spatial_tick", -1.0))
	for _frame in range(120):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	check(str(chunk.get_preview_state().get("phase", "")) != "complete",
		"restoring the gathered member cannot complete before the saved cadence edge")
	scheduler.advance_ticks(maxf(
		0.0,
		completion_deadline - float(scheduler.get_current_tick()) - POLL_EPSILON))
	check(str(chunk.get_preview_state().get("phase", "")) != "complete",
		"the gathered conscious party remains incomplete immediately before the exact poll")
	var exit_midpoint := _json_round_trip(source.build_save_snapshot())
	var midpoint_tick := float(scheduler.get_current_tick())
	check(completion_deadline > midpoint_tick,
		"the exit midpoint snapshot retains a strictly future completion receipt")
	_advance_scheduler_across(scheduler, completion_deadline)
	check(str(chunk.get_preview_state().get("phase", "")) == "complete",
		"scheduler-only advancement commits the gathered conscious party")

	# Same-presenter rollback restores the same future edge and cannot complete from any number of
	# presenter calls. Crossing that edge commits once.
	source.apply_save_snapshot(exit_midpoint)
	check(str(chunk.get_preview_state().get("phase", "")) != "complete"
			and is_equal_approx(
				float(chunk.get_preview_state().get("next_exit_spatial_tick", -1.0)),
				completion_deadline),
		"same-presenter midpoint restore reconstructs the original exit deadline")
	for _frame in range(120):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	check(str(chunk.get_preview_state().get("phase", "")) != "complete",
		"same-presenter restore remains independent of render/headless calls")
	_advance_scheduler_across(scheduler, completion_deadline)
	check(str(chunk.get_preview_state().get("phase", "")) == "complete",
		"same-presenter restore completes once at the original deadline")

	var fresh_exit = await _spawn_preview()
	if fresh_exit != null:
		fresh_exit.apply_save_snapshot(exit_midpoint)
		var fresh_exit_chunk = fresh_exit._active_chunk
		var fresh_exit_scheduler: EventScheduler = fresh_exit._scheduler
		check(str(fresh_exit_chunk.get_preview_state().get("phase", "")) != "complete"
				and is_equal_approx(
					float(fresh_exit_chunk.get_preview_state().get(
						"next_exit_spatial_tick", -1.0)),
					completion_deadline),
			"fresh presenter reconstructs the same future exit receipt")
		for _frame in range(120):
			fresh_exit_chunk._process(1.0 / 60.0)
			fresh_exit_chunk.headless_process(1.0 / 60.0)
		check(str(fresh_exit_chunk.get_preview_state().get("phase", "")) != "complete",
			"fresh presenter calls cannot consume the saved exit receipt")
		fresh_exit_scheduler.advance_ticks(
			completion_deadline - float(fresh_exit_scheduler.get_current_tick()) + 0.5)
		check(str(fresh_exit_chunk.get_preview_state().get("phase", "")) == "complete",
			"fresh presenter completes through a coarse fast-forward crossing the original deadline")
		await _discard(fresh_exit)

	# The room ledger is only provenance. An edited list cannot impersonate dead bodies at the
	# downstream endpoint and thereby unlock the exit while every real Enemy remains alive.
	var spoofed_drowned := _json_round_trip(baseline)
	_set_wash_intro_drowned_ids(
		spoofed_drowned, authority_key,
		chunk.enemies().map(func(candidate): return str(candidate.char_id)))
	source.apply_save_snapshot(spoofed_drowned)
	for party_id in PARTY:
		gs.snap_character_to(party_id, chunk._exit_pos)
	chunk.headless_process(0.1)
	check(int(chunk.get_preview_state().get("drowned", -1)) == 0
			and str(chunk.get_preview_state().get("phase", "")) != "complete"
			and chunk.enemies().all(func(candidate): return candidate.is_alive()),
		"a forged drowned-ID ledger cannot replace the living stable Enemy bodies")

	# A snapshot from before the room record existed must retract a later local solve. This is the
	# loading-system exploit that the scene-local _drowned counter previously allowed in reverse.
	_erase_world_key(baseline, authority_key)
	source.apply_save_snapshot(baseline)
	check(int(chunk.get_preview_state().get("drowned", -1)) == 0
			and int(chunk.get_preview_state().get("washed_back", -1)) == 0
			and str(chunk.get_preview_state().get("phase", "")) == "ready",
		"missing room authority retracts all later local progression")
	source.headless_advance(2.0, 0.1)
	check(int(chunk.get_preview_state().get("drowned", -1)) == 0,
		"discarded callbacks cannot re-grant progression after absence rollback")

	await _discard(source)
	_finish()


func _spawn_preview():
	var preview = PreviewScene.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "channels_wash_intro"
	preview.suppress_scene_change = true
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	check(preview._active_chunk != null, "Wash Intro preview boots its production chunk")
	if preview._active_chunk == null:
		await _discard(preview)
		return null
	return preview


func _advance_across(preview, deadline: float) -> void:
	var remaining := deadline - float(preview._scheduler.get_current_tick())
	preview.headless_advance(maxf(0.0, remaining - POLL_EPSILON), POLL_EPSILON)
	preview.headless_advance(POLL_EPSILON * 1.1, POLL_EPSILON * 1.1)


func _advance_scheduler_across(scheduler: EventScheduler, deadline: float) -> void:
	var remaining := deadline - float(scheduler.get_current_tick())
	scheduler.advance_ticks(maxf(0.0, remaining - POLL_EPSILON))
	scheduler.advance_ticks(POLL_EPSILON * 1.1)


func _drown_remaining_hunters(preview, chunk) -> bool:
	var channels: Array = chunk.channels()
	if channels.is_empty():
		return false
	var gs: GameState = preview._game_state
	var scheduler: EventScheduler = preview._scheduler
	var channel_index := 1
	for enemy in chunk.enemies():
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var selected_index := channel_index % channels.size()
		var channel = channels[selected_index]
		var channel_x := float(channel.get("_x"))
		gs.snap_character_to(str(enemy.char_id), Vector3(channel_x, 0.5, 0.5))
		chunk._channel_onset(selected_index)
		var poll_deadline := float(channel.get_state().get("next_sweep_tick", -1.0))
		if poll_deadline <= float(scheduler.get_current_tick()):
			return false
		_advance_across(preview, poll_deadline)
		var carry: Dictionary = gs.get_external_traversal_state(str(enemy.char_id))
		var arrival := float(carry.get("end_tick", -1.0))
		if arrival <= float(scheduler.get_current_tick()):
			return false
		_advance_across(preview, arrival)
		channel_index += 1
	return chunk.enemies().all(func(candidate): return not candidate.is_alive())


func _water_visible(channel) -> bool:
	var water := channel.get_node_or_null("Water") as MeshInstance3D
	return water != null and water.visible


func _erase_world_key(snapshot: Dictionary, key: String) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	world_state.erase(key)
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


func _set_wash_intro_drowned_ids(
		snapshot: Dictionary, authority_key: String, enemy_ids: Array) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var room: Dictionary = world_state.get(authority_key, {})
	var wash_intro: Dictionary = room.get("wash_intro", {})
	wash_intro["drowned_ids"] = enemy_ids.duplicate()
	room["wash_intro"] = wash_intro
	world_state[authority_key] = room
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.has_method("_teardown_sequence"):
			node.call("_teardown_sequence")
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


func _finish() -> void:
	print("CHANNELS WASH INTRO AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
