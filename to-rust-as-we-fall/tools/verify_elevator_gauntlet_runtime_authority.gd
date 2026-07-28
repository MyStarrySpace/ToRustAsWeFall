extends SceneTree

## Adversarial save/load coverage for the playable three-character gauntlet.
## Uses build_save_snapshot/apply_save_snapshot so fresh fixtures exercise real
## chunk construction, dormant-enemy attachment, presenter controls, and camera.

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source := await _spawn_ready_gauntlet()
	check(source._game_state.characters.has("endo") \
		and source._hud.get_portrait_ids().has("endo") \
		and source._available_party_control_ids() \
			== source.GAUNTLET_INTRO_REQUIRED_MEMBERS,
		"Endo joins the real playable roster and HUD at the gauntlet")
	source._hud.set_multi_select_enabled(true)
	source._hud.set_selected_portraits(["endo", "aster"])
	check(source._active_character == "endo" \
		and source._player == source._endo \
		and source._selected_character_ids == ["endo", "aster"],
		"Endo is selectable as an active controller, including multi-selection")
	check(_pack_targets_full_party(source, 0),
		"the unlocked first pack detects Aster, Peris, and Endo")
	check("all three characters" in str(
		(source._gauntlet_flure_interactables[0] as Flure).consequence_preview),
		"the Flure prediction names the same three-body gate the runtime enforces")

	var midpoint_threshold: float = source.GAUNTLET_MIDPOINT.x - 2.0
	_place_members_at_x(source, ["aster", "peris"], midpoint_threshold + 1.0)
	_place_members_at_x(source, ["endo"], midpoint_threshold - 2.0)
	source._scheduler.advance_ticks(source.GAUNTLET_POLL_INTERVAL + 0.02)
	check(not source._gauntlet_midpoint_reached,
		"Aster and Peris cannot earn the refuge while Endo is left behind")
	_place_members_at_x(source, ["endo"], midpoint_threshold + 1.0)
	source._scheduler.advance_ticks(source.GAUNTLET_POLL_INTERVAL + 0.02)
	check(source._gauntlet_midpoint_reached \
		and int(source._gauntlet_run_authority.get("stage", -1)) == 1,
		"the scheduler commits the refuge only after all three conscious bodies cross")
	check(_all_live_gauntlet_enemies_target_full_party(source),
		"unlocking stage two gives every live pack the complete target roster")
	var midpoint_capture := _capture(source)

	# A full second-pack pull owns one exact window. Saving after several seconds
	# must preserve both Enemy lured FSMs and the original absolute expiry.
	_prepare_pack(source, 1)
	var second_flure := source._gauntlet_flure_interactables[1] as Flure
	check(_trigger_flure(source, second_flure),
		"a staged Peris body services the second Flure and pulls its complete physical pack")
	var active_window: Dictionary = source._gauntlet_window_state(1)
	var active_deadline := float(active_window.get("deadline", -1.0))
	check(str(active_window.get("phase", "")) == source.GAUNTLET_WINDOW_ACTIVE \
		and active_deadline > source._scheduler.get_current_tick() \
		and _pack_has_state(source, 1, "lured"),
		"the successful signal commits a timed host window and real lured enemy FSMs")
	source._scheduler.advance_ticks(3.0)
	var active_capture := _capture(source)
	var active_remaining: float = active_deadline - source._scheduler.get_current_tick()
	if active_remaining > 0.02:
		source._scheduler.advance_ticks(active_remaining - 0.01)
	check(str(source._gauntlet_window_state(1).get("phase", "")) \
		== source.GAUNTLET_WINDOW_ACTIVE,
		"the live window does not expire before its committed deadline")
	source._scheduler.advance_ticks(0.02)
	check(str(source._gauntlet_window_state(1).get("phase", "")) \
		== source.GAUNTLET_WINDOW_READY,
		"the live window expires once at its committed deadline")

	await _apply_capture(source, active_capture)
	check(str(source._gauntlet_window_state(1).get("phase", "")) \
		== source.GAUNTLET_WINDOW_ACTIVE \
		and is_equal_approx(float(source._gauntlet_window_state(1).get(
			"deadline", -1.0)), active_deadline) \
		and _pack_has_state(source, 1, "lured"),
		"same-presenter rollback retracts expiry without cancelling the restored lure")

	var fresh := await _spawn_blank_sequence()
	await _apply_capture(fresh, active_capture)
	check(_gauntlet_presenters_attached(fresh) \
		and _pack_has_state(fresh, 1, "lured"),
		"production-fresh loading activates dormant presenters and preserves lured FSMs")
	check(fresh._active_character == "endo" \
		and fresh._selected_character_ids == ["endo", "aster"] \
		and bool(fresh._hud.get("_multi_select")) \
		and fresh._camera.target == fresh._endo,
		"fresh loading restores selection, multi-select, and camera target together")
	var fresh_remaining: float = active_deadline - fresh._scheduler.get_current_tick()
	if fresh_remaining > 0.02:
		fresh._scheduler.advance_ticks(fresh_remaining - 0.01)
	check(str(fresh._gauntlet_window_state(1).get("phase", "")) \
		== fresh.GAUNTLET_WINDOW_ACTIVE,
		"fresh restoration preserves the original remaining window time")
	fresh._scheduler.advance_ticks(0.02)
	check(str(fresh._gauntlet_window_state(1).get("phase", "")) \
		== fresh.GAUNTLET_WINDOW_READY,
		"fresh restoration expires the window once, on the original clock")

	# Partial pull is a distinct failed/rearming phase, not a successful boolean.
	await _apply_capture(source, midpoint_capture)
	_prepare_pack(source, 1)
	var partial_pack: Array = source._gauntlet_enemy_groups.get(1, [])
	(partial_pack[0] as Enemy)._fsm.transition_to("alert")
	second_flure = source._gauntlet_flure_interactables[1] as Flure
	check(_trigger_flure(source, second_flure),
		"a late physical source still pulls the uncommitted guard")
	var failed_window: Dictionary = source._gauntlet_window_state(1)
	var failed_deadline := float(failed_window.get("deadline", -1.0))
	check(str(failed_window.get("phase", "")) == source.GAUNTLET_WINDOW_FAILED,
		"a partial pull commits FAILED rather than granting a safe window")
	source._scheduler.advance_ticks(2.0)
	var failed_capture := _capture(source)
	await _apply_capture(fresh, failed_capture)
	check(str(fresh._gauntlet_window_state(1).get("phase", "")) \
		== fresh.GAUNTLET_WINDOW_FAILED \
		and is_equal_approx(float(fresh._gauntlet_window_state(1).get(
			"deadline", -1.0)), failed_deadline),
		"fresh loading keeps the partial-pull rearm deadline")
	var failed_remaining: float = failed_deadline - fresh._scheduler.get_current_tick()
	if failed_remaining > 0.02:
		fresh._scheduler.advance_ticks(failed_remaining - 0.01)
	check(str(fresh._gauntlet_window_state(1).get("phase", "")) \
		== fresh.GAUNTLET_WINDOW_FAILED,
		"failed Flure does not rearm early after fresh loading")
	fresh._scheduler.advance_ticks(0.02)
	check(str(fresh._gauntlet_window_state(1).get("phase", "")) \
		== fresh.GAUNTLET_WINDOW_READY,
		"failed Flure rearms once at its saved deadline")

	# The hit reaction before a refuge reset is itself saved authority. A player
	# cannot save in the 0.4 second delay to erase the downed-character reset.
	await _apply_capture(source, midpoint_capture)
	var first_pack_pursuer := (source._gauntlet_enemy_groups.get(0, []) as Array)[0] as Enemy
	var pursued_refuge_pos: Vector3 = source.GAUNTLET_MIDPOINT + Vector3(2.0, 0.0, 0.0)
	source._game_state.snap_character_to(first_pack_pursuer.char_id, pursued_refuge_pos)
	first_pack_pursuer.global_position = pursued_refuge_pos
	first_pack_pursuer._fsm.transition_to("alert")
	source._game_state.down_character("endo")
	source._request_gauntlet_reset(0.4, "endo_downed")
	var pending_station := source._gauntlet_flure_interactables[1] as Flure
	check(not pending_station.is_interaction_enabled() \
		and str(pending_station.get_effect_state().get("phase", "")) \
		== Flure.PHASE_READY,
		"RESET_PENDING immediately removes the click surface without firing a lure")
	source._scheduler.advance_ticks(0.1)
	var pending_capture := _capture(source)
	var reset_start_deadline := float(source._gauntlet_run_authority.get(
		"reset_start_deadline", -1.0))
	var resets_before: int = source._gauntlet_reset_count
	await _apply_capture(source, pending_capture)
	check(str(source._gauntlet_run_authority.get("phase", "")) \
		== source.GAUNTLET_RUN_PHASE_RESET_PENDING \
		and str(source._gauntlet_run_authority.get("reset_reason", "")) \
		== "endo_downed",
		"same-presenter rollback preserves the pending defeat consequence")
	var reset_wait: float = reset_start_deadline - source._scheduler.get_current_tick()
	if reset_wait > 0.02:
		source._scheduler.advance_ticks(reset_wait - 0.01)
	check(source._gauntlet_reset_count == resets_before,
		"pending refuge reset does not fire before its saved start deadline")
	source._scheduler.advance_ticks(0.02)
	check(source._gauntlet_reset_count == resets_before + 1 \
		and str(source._gauntlet_run_authority.get("phase", "")) \
		== source.GAUNTLET_RUN_PHASE_RESETTING,
		"the pending defeat commits one refuge reset at its deadline")
	check(not source._game_state.is_downed("endo"),
		"the refuge reset clears Endo's authoritative downed latch")
	check(_party_at_refuge(source),
		"the refuge reset relocates the entire party to its saved physical checkpoint")
	check(_pack_at_authored_posts(source, 0),
		"a first-pack pursuer dragged across the midpoint is re-posted away from the refuge")
	var resetting_capture := _capture(source)
	var release_deadline := float(source._gauntlet_run_authority.get(
		"reset_release_deadline", -1.0))
	await _apply_capture(fresh, resetting_capture)
	check(str(fresh._gauntlet_run_authority.get("phase", "")) \
		== fresh.GAUNTLET_RUN_PHASE_RESETTING \
		and is_equal_approx(float(fresh._gauntlet_run_authority.get(
			"reset_release_deadline", -1.0)), release_deadline),
		"fresh loading preserves the post-reset control-release deadline")
	var release_wait: float = release_deadline - fresh._scheduler.get_current_tick()
	if release_wait > 0.02:
		fresh._scheduler.advance_ticks(release_wait - 0.01)
	check(str(fresh._gauntlet_run_authority.get("phase", "")) \
		== fresh.GAUNTLET_RUN_PHASE_RESETTING,
		"fresh reset keeps controls locked until the exact release deadline")
	fresh._scheduler.advance_ticks(0.02)
	check(str(fresh._gauntlet_run_authority.get("phase", "")) \
		== fresh.GAUNTLET_RUN_PHASE_ACTIVE,
		"fresh reset returns to active play once at the saved deadline")
	var count_after_release: int = fresh._gauntlet_reset_count
	fresh._begin_gauntlet_reset(reset_start_deadline)
	check(fresh._gauntlet_reset_count == count_after_release,
		"a stale reset-start callback cannot reset the corrected future")

	# Malformed run authority fails closed at the three-body start checkpoint.
	# Even unauthoritative exit-side positions cannot be converted into completion.
	var corrupt := midpoint_capture.duplicate(true)
	var corrupt_game: Dictionary = corrupt.get("game_state", {})
	var corrupt_world: Dictionary = corrupt_game.get("world_state", {})
	var corrupt_outer: Dictionary = corrupt_world.get(
		source.ELEVATOR_RUNTIME_AUTHORITY_KEY, {})
	var corrupt_run: Dictionary = (corrupt_outer.get("gauntlet_run", {}) as Dictionary).duplicate(true)
	corrupt_run.erase("required_party")
	corrupt_outer["gauntlet_run"] = corrupt_run
	corrupt_world[source.ELEVATOR_RUNTIME_AUTHORITY_KEY] = corrupt_outer
	var corrupt_chars: Dictionary = corrupt_game.get("characters", {})
	for member_id in source.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		var char_data: Dictionary = corrupt_chars.get(member_id, {})
		char_data["position"] = [source.GAUNTLET_EXIT.x + 10.0, source.BELOW_Y + 0.5, 0.0]
		corrupt_chars[member_id] = char_data
	corrupt_game["characters"] = corrupt_chars
	corrupt_game["world_state"] = corrupt_world
	corrupt["game_state"] = corrupt_game
	await _apply_capture(fresh, corrupt)
	check(fresh._current_step == "gauntlet" \
		and not fresh._gauntlet_midpoint_reached \
		and int(fresh._gauntlet_run_authority.get("stage", -1)) == 0 \
		and _party_at_intro(fresh),
		"malformed run authority can only recover backward to the start checkpoint")
	fresh._scheduler.advance_ticks(fresh.GAUNTLET_POLL_INTERVAL * 2.0 + 0.02)
	check(fresh._current_step == "gauntlet" and fresh.requested_scene_change == "",
		"malformed exit-side positions cannot grant completion after recovery")
	var mismatched_complete := midpoint_capture.duplicate(true)
	mismatched_complete["current_step"] = "complete"
	await _apply_capture(fresh, mismatched_complete)
	check(fresh._current_step == "gauntlet" \
		and str(fresh._gauntlet_run_authority.get("phase", "")) \
		== fresh.GAUNTLET_RUN_PHASE_ACTIVE,
		"ACTIVE run plus complete step fails closed instead of softlocking or transitioning")

	# Exit and transition are likewise all-body and deadline-owned.
	await _apply_capture(source, midpoint_capture)
	var exit_threshold: float = source.GAUNTLET_EXIT.x - 2.0
	_place_members_at_x(source, ["aster", "peris"], exit_threshold + 1.0)
	_place_members_at_x(source, ["endo"], exit_threshold - 3.0)
	source._scheduler.advance_ticks(source.GAUNTLET_POLL_INTERVAL + 0.02)
	check(source._current_step == "gauntlet",
		"Aster and Peris cannot exit while Endo is left behind")
	_place_members_at_x(source, ["endo"], exit_threshold + 1.0)
	source._scheduler.advance_ticks(source.GAUNTLET_POLL_INTERVAL + 0.02)
	check(source._current_step == "complete" \
		and str(source._gauntlet_run_authority.get("phase", "")) \
		== source.GAUNTLET_RUN_PHASE_TRANSITIONING,
		"all three bodies commit one saved transition phase at the exit")
	source._scheduler.advance_ticks(0.5)
	var transition_capture := _capture(source)
	var transition_deadline := float(source._gauntlet_run_authority.get(
		"transition_deadline", -1.0))
	var transition_fresh := await _spawn_blank_sequence()
	await _apply_capture(transition_fresh, transition_capture)
	var transition_wait: float = transition_deadline \
		- transition_fresh._scheduler.get_current_tick()
	if transition_wait > 0.02:
		transition_fresh._scheduler.advance_ticks(transition_wait - 0.01)
	check(transition_fresh.requested_scene_change == "",
		"fresh transition restore cannot change scenes before its saved deadline")
	transition_fresh._scheduler.advance_ticks(0.02)
	check(transition_fresh.requested_scene_change \
		== "res://scenes/tutorial/act1.tscn",
		"fresh transition restore changes scenes once at the saved deadline")
	await _verify_signal_time_seams()

	await _dispose(source)
	await _dispose(fresh)
	await _dispose(transition_fresh)
	print("ELEVATOR GAUNTLET RUNTIME AUTHORITY: %d checks, %d failures" % [
		_checks, _failures,
	])
	quit(0 if _failures == 0 else 1)


## Saving from observers of a constituent GameState write is harsher than saving
## on the following frame. These probes prove the host phase is committed before
## Enemy, stat, station, or transition signals can expose a half-written future.
func _verify_signal_time_seams() -> void:
	var seam_source := await _spawn_assembling_gauntlet()
	seam_source._finish_gauntlet_intro()
	var targets: Dictionary = seam_source._gauntlet_intro_targets()
	_earn_intro_arrival(seam_source, "aster", targets["aster"])
	_earn_intro_arrival(seam_source, "peris", targets["peris"])

	var intro_box: Dictionary = {"snapshot": {}}
	var intro_callback: Callable = func(key: String, _value: Variant) -> void:
		if not (intro_box.get("snapshot", {}) as Dictionary).is_empty() \
				or not key.begins_with("runtime:enemy:"):
			return
		var outer: Dictionary = seam_source._game_state.get_world_state(
			seam_source.ELEVATOR_RUNTIME_AUTHORITY_KEY, {}) as Dictionary
		var intro: Dictionary = outer.get("gauntlet_intro", {}) as Dictionary
		if str(intro.get("phase", "")) == seam_source.GAUNTLET_INTRO_PHASE_ARMING:
			intro_box["snapshot"] = _capture(seam_source)
	seam_source._game_state.world_state_changed.connect(intro_callback)
	_earn_intro_arrival(seam_source, "endo", targets["endo"])
	seam_source._game_state.world_state_changed.disconnect(intro_callback)
	var intro_signal_capture: Dictionary = intro_box.get("snapshot", {}) as Dictionary
	var intro_signal_outer := _snapshot_outer(
		intro_signal_capture, seam_source.ELEVATOR_RUNTIME_AUTHORITY_KEY)
	check(not intro_signal_capture.is_empty() \
		and str((intro_signal_outer.get("gauntlet_intro", {}) as Dictionary).get(
			"phase", "")) == seam_source.GAUNTLET_INTRO_PHASE_ARMING,
		"an Enemy-authority observer can save only after intro ARMING is durable")
	var intro_fresh := await _spawn_blank_sequence()
	await _apply_capture(intro_fresh, intro_signal_capture)
	check(str(intro_fresh._gauntlet_intro_authority.get("phase", "")) \
		== intro_fresh.GAUNTLET_INTRO_PHASE_READY \
		and _pack_targets_full_party(intro_fresh, 0) \
		and _pack_is_armed(intro_fresh, 0) \
		and (intro_fresh._gauntlet_flure_interactables[0] as Flure).is_interaction_enabled(),
		"fresh loading from intro ARMING finishes the real pack before releasing play")

	var midpoint_box: Dictionary = {"snapshot": {}}
	var midpoint_callback: Callable = func(key: String, _value: Variant) -> void:
		if not (midpoint_box.get("snapshot", {}) as Dictionary).is_empty() \
				or not key.begins_with("runtime:enemy:"):
			return
		var outer: Dictionary = seam_source._game_state.get_world_state(
			seam_source.ELEVATOR_RUNTIME_AUTHORITY_KEY, {}) as Dictionary
		var run: Dictionary = outer.get("gauntlet_run", {}) as Dictionary
		if str(run.get("phase", "")) == seam_source.GAUNTLET_RUN_PHASE_MIDPOINT_ARMING:
			midpoint_box["snapshot"] = _capture(seam_source)
	seam_source._game_state.world_state_changed.connect(midpoint_callback)
	_place_members_at_x(
		seam_source, seam_source.GAUNTLET_INTRO_REQUIRED_MEMBERS,
		seam_source.GAUNTLET_MIDPOINT.x - 1.0)
	seam_source._scheduler.advance_ticks(seam_source.GAUNTLET_POLL_INTERVAL + 0.02)
	seam_source._game_state.world_state_changed.disconnect(midpoint_callback)
	var midpoint_signal_capture: Dictionary = midpoint_box.get("snapshot", {}) as Dictionary
	var midpoint_signal_outer := _snapshot_outer(
		midpoint_signal_capture, seam_source.ELEVATOR_RUNTIME_AUTHORITY_KEY)
	check(not midpoint_signal_capture.is_empty() \
		and str((midpoint_signal_outer.get("gauntlet_run", {}) as Dictionary).get(
			"phase", "")) == seam_source.GAUNTLET_RUN_PHASE_MIDPOINT_ARMING,
		"a stage-two Enemy observer can save only after midpoint arming is durable")
	var midpoint_fresh := await _spawn_blank_sequence()
	await _apply_capture(midpoint_fresh, midpoint_signal_capture)
	check(str(midpoint_fresh._gauntlet_run_authority.get("phase", "")) \
		== midpoint_fresh.GAUNTLET_RUN_PHASE_ACTIVE \
		and int(midpoint_fresh._gauntlet_run_authority.get("stage", -1)) == 1 \
		and _pack_is_armed(midpoint_fresh, 1) \
		and float(midpoint_fresh._gauntlet_run_authority.get("next_poll_tick", -1.0)) \
			> midpoint_fresh._scheduler.get_current_tick() \
		and midpoint_fresh._scheduler.pending_count() > 0,
		"fresh loading from midpoint arming finishes stage two and restores its poll")

	# Install the capture observer ahead of the sequence handler. Its save lands
	# after hp=0 but before the handler can publish RESET_PENDING, and therefore
	# exercises restore-time defeat reconciliation rather than the normal path.
	var stat_box: Dictionary = {"snapshot": {}}
	var stat_callback: Callable = func(id: String, stat: String, value: float) -> void:
		if id == "endo" and stat == "hp" and value <= 0.0 \
				and (stat_box.get("snapshot", {}) as Dictionary).is_empty():
			stat_box["snapshot"] = _capture(seam_source)
	var sequence_stat_handler := Callable(seam_source, "_on_party_stat_changed")
	if seam_source._game_state.stat_changed.is_connected(sequence_stat_handler):
		seam_source._game_state.stat_changed.disconnect(sequence_stat_handler)
	seam_source._game_state.stat_changed.connect(stat_callback)
	seam_source._game_state.stat_changed.connect(sequence_stat_handler)
	seam_source._game_state.set_stat("endo", "hp", 0.0, "signal_seam_probe")
	seam_source._game_state.stat_changed.disconnect(stat_callback)
	var stat_signal_capture: Dictionary = stat_box.get("snapshot", {}) as Dictionary
	var stat_signal_outer := _snapshot_outer(
		stat_signal_capture, seam_source.ELEVATOR_RUNTIME_AUTHORITY_KEY)
	check(not stat_signal_capture.is_empty() \
		and str((stat_signal_outer.get("gauntlet_run", {}) as Dictionary).get(
			"phase", "")) == seam_source.GAUNTLET_RUN_PHASE_ACTIVE,
		"the pre-handler hp observer proves the adversarial save really precedes RESET_PENDING")
	check(str(seam_source._gauntlet_run_authority.get("phase", "")) \
		== seam_source.GAUNTLET_RUN_PHASE_RESET_PENDING \
		and not (seam_source._gauntlet_flure_interactables[1] as Flure) \
			.is_interaction_enabled(),
		"RESET_PENDING is durable before its derived station click surface disappears")
	var defeat_fresh := await _spawn_blank_sequence()
	await _apply_capture(defeat_fresh, stat_signal_capture)
	check(str(defeat_fresh._gauntlet_run_authority.get("phase", "")) \
		== defeat_fresh.GAUNTLET_RUN_PHASE_RESET_PENDING \
		and str(defeat_fresh._gauntlet_run_authority.get("reset_reason", "")) \
			== "recovered_endo_downed",
		"fresh loading reconciles an hp-zero pre-handler save into the owed refuge reset")
	var defeat_deadline := float(defeat_fresh._gauntlet_run_authority.get(
		"reset_start_deadline", -1.0))
	defeat_fresh._scheduler.advance_ticks(
		defeat_deadline - defeat_fresh._scheduler.get_current_tick() + 1.02)
	check(str(defeat_fresh._gauntlet_run_authority.get("phase", "")) \
		== defeat_fresh.GAUNTLET_RUN_PHASE_ACTIVE \
		and defeat_fresh._gauntlet_reset_count == 1 \
		and defeat_fresh._game_state.get_stat("endo", "hp") > 0.0,
		"the reconciled signal-time defeat performs exactly one physical reset")

	var transition_source := await _spawn_ready_gauntlet()
	var transition_box: Dictionary = {"snapshot": {}}
	var transition_callback: Callable = func(key: String, value: Variant) -> void:
		if key != transition_source.ELEVATOR_RUNTIME_AUTHORITY_KEY \
				or not (value is Dictionary) \
				or not (transition_box.get("snapshot", {}) as Dictionary).is_empty():
			return
		var run: Dictionary = (value as Dictionary).get("gauntlet_run", {}) as Dictionary
		if str(run.get("phase", "")) == transition_source.GAUNTLET_RUN_PHASE_TRANSITIONING:
			transition_box["snapshot"] = _capture(transition_source)
	transition_source._game_state.world_state_changed.connect(transition_callback)
	_place_members_at_x(
		transition_source, transition_source.GAUNTLET_INTRO_REQUIRED_MEMBERS,
		transition_source.GAUNTLET_EXIT.x - 1.0)
	transition_source._scheduler.advance_ticks(
		transition_source.GAUNTLET_POLL_INTERVAL + 0.02)
	transition_source._scheduler.advance_ticks(
		transition_source.GAUNTLET_POLL_INTERVAL + 0.02)
	transition_source._game_state.world_state_changed.disconnect(transition_callback)
	var transition_signal_capture: Dictionary = transition_box.get("snapshot", {}) as Dictionary
	check(not transition_signal_capture.is_empty() \
		and str(transition_signal_capture.get("current_step", "")) == "complete",
		"TRANSITIONING is never observable before the saved sequence step is complete")
	var transition_signal_fresh := await _spawn_blank_sequence()
	await _apply_capture(transition_signal_fresh, transition_signal_capture)
	check(transition_signal_fresh._current_step == "complete" \
		and str(transition_signal_fresh._gauntlet_run_authority.get("phase", "")) \
			== transition_signal_fresh.GAUNTLET_RUN_PHASE_TRANSITIONING,
		"fresh loading from the transition signal restores the exact committed phase")

	await _dispose(seam_source)
	await _dispose(intro_fresh)
	await _dispose(midpoint_fresh)
	await _dispose(defeat_fresh)
	await _dispose(transition_source)
	await _dispose(transition_signal_fresh)


func _snapshot_outer(snapshot: Dictionary, key: String) -> Dictionary:
	var game_state: Dictionary = snapshot.get("game_state", {}) as Dictionary
	var world_state: Dictionary = game_state.get("world_state", {}) as Dictionary
	return world_state.get(key, {}) as Dictionary


func _trigger_flure(sequence: Node, flure: Flure) -> bool:
	if flure == null:
		return false
	sequence._game_state.command_stop("peris")
	sequence._game_state.snap_character_to("peris", flure.get_source_data_position())
	flure.active_character = "peris"
	return bool(flure.call("_trigger", false))


func _spawn_ready_gauntlet() -> Node:
	var sequence := await _spawn_assembling_gauntlet()
	sequence._finish_gauntlet_intro()
	var targets: Dictionary = sequence._gauntlet_intro_targets()
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		_earn_intro_arrival(sequence, member_id, targets[member_id])
	return sequence


func _spawn_assembling_gauntlet() -> Node:
	var sequence := ElevatorScene.instantiate()
	sequence.suppress_scene_change = true
	sequence.start_chunk = "gauntlet"
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	sequence._reset_endo_entry_dialogue_for_restore()
	if not sequence._game_state.characters.has("endo"):
		sequence._set_endo_presenter_present(true)
		sequence._endo.global_position = sequence._endo_entry_destination()
		sequence._register_gs_character("endo", sequence._endo, 2.5, {
			"hp": sequence.PARTY_MAX_HP,
			"stamina": GameState.STAMINA_MAX,
			"atp": GameState.ATP_MAX_PIPS,
		})
	_stage_intro_approach(sequence)
	sequence._start_gauntlet()
	sequence._reset_endo_entry_dialogue_for_restore()
	return sequence


func _earn_intro_arrival(sequence: Node, member_id: String, target: Vector3) -> void:
	sequence._gauntlet_intro_authority["next_retry_tick"] = \
		sequence._scheduler.get_current_tick()
	sequence._issue_next_gauntlet_intro_move()
	_settle_member(sequence, member_id, target)
	sequence._update_gauntlet_intro_formation()


func _stage_intro_approach(sequence: Node) -> void:
	var targets: Dictionary = sequence._gauntlet_intro_targets()
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		var target: Vector3 = targets[member_id]
		var approach := target + Vector3(-2.0, 0.0, 0.0)
		sequence._game_state.command_stop(member_id)
		sequence._game_state.set_character_level(member_id, sequence.LEVEL_LOWER)
		sequence._game_state.snap_character_to(member_id, approach)
		var presenter: Node3D = sequence._elevator_party_node(member_id)
		if presenter != null:
			presenter.global_position = approach


func _spawn_blank_sequence() -> Node:
	var sequence := ElevatorScene.instantiate()
	sequence.suppress_scene_change = true
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	return sequence


func _prepare_pack(sequence: Node, stage: int) -> void:
	for enemy_v in sequence._gauntlet_enemy_groups.get(stage, []):
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy):
			continue
		enemy.set_detection_targets([])
		enemy.re_post(sequence._gauntlet_enemy_posts.get(
			enemy.char_id, enemy.global_position))


func _place_members_at_x(sequence: Node, member_ids: Array, x: float) -> void:
	for index in range(member_ids.size()):
		var member_id := str(member_ids[index])
		_settle_member(sequence, member_id, Vector3(
			x, sequence.BELOW_Y + 0.5, float(index) - 0.5))


func _settle_member(sequence: Node, member_id: String, target: Vector3) -> void:
	sequence._game_state.command_stop(member_id)
	sequence._game_state.snap_character_to(member_id, target)
	var presenter: Node3D = sequence._elevator_party_node(member_id)
	if presenter != null:
		presenter.global_position = target


func _pack_has_state(sequence: Node, stage: int, expected: String) -> bool:
	var pack: Array = sequence._gauntlet_enemy_groups.get(stage, [])
	if pack.is_empty():
		return false
	for enemy_v in pack:
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy) or enemy.get_state() != expected:
			return false
	return true


func _pack_is_armed(sequence: Node, stage: int) -> bool:
	var pack: Array = sequence._gauntlet_enemy_groups.get(stage, [])
	if pack.is_empty():
		return false
	for enemy_v in pack:
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy) \
				or enemy.get_state() == "idle" \
				or enemy.get_detection_targets() \
					!= sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
			return false
	return true


func _all_live_gauntlet_enemies_target_full_party(sequence: Node) -> bool:
	for enemy_v in sequence._gauntlet_enemies:
		var enemy := enemy_v as Enemy
		if is_instance_valid(enemy) and enemy.is_alive() \
				and enemy.get_detection_targets() \
				!= sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
			return false
	return true


func _pack_targets_full_party(sequence: Node, stage: int) -> bool:
	var pack: Array = sequence._gauntlet_enemy_groups.get(stage, [])
	if pack.is_empty():
		return false
	for enemy_v in pack:
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy) or enemy.get_detection_targets() \
				!= sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
			return false
	return true


func _pack_at_authored_posts(sequence: Node, stage: int) -> bool:
	for enemy_v in sequence._gauntlet_enemy_groups.get(stage, []):
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy):
			return false
		var post: Vector3 = sequence._gauntlet_enemy_posts.get(
			enemy.char_id, enemy.global_position)
		var state_pos: Vector3 = sequence._game_state.get_position(enemy.char_id)
		if Vector2(state_pos.x, state_pos.z).distance_to(Vector2(post.x, post.z)) > 0.05 \
				or sequence._game_state.is_character_distracted(enemy.char_id):
			return false
	return true


func _gauntlet_presenters_attached(sequence: Node) -> bool:
	for enemy_v in sequence._gauntlet_enemies:
		var enemy := enemy_v as Enemy
		if not is_instance_valid(enemy) \
				or enemy.process_mode == Node.PROCESS_MODE_DISABLED \
				or not sequence._game_state.characters.has(enemy.char_id) \
				or not sequence._game_state.detection_predicted.is_connected(
					Callable(enemy, "_on_detection_predicted")):
			return false
	return not sequence._gauntlet_enemies.is_empty()


func _party_at_refuge(sequence: Node) -> bool:
	var base: Vector3 = sequence.GAUNTLET_MIDPOINT
	var expected := {
		"aster": base + Vector3(-0.8, 0.5, -0.7),
		"peris": base + Vector3(-0.8, 0.5, 0.7),
		"endo": base + Vector3(-1.8, 0.5, 0.0),
	}
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		var actual: Vector3 = sequence._game_state.get_position(member_id)
		var expected_presenter: Vector3 = expected[member_id]
		var expected_state := Vector3(
			expected_presenter.x, sequence.BELOW_Y, expected_presenter.z)
		var presenter: Node3D = sequence._elevator_party_node(member_id)
		if actual.distance_to(expected_state) > 0.05 \
				or presenter == null \
				or presenter.global_position.distance_to(expected_presenter) > 0.05:
			return false
	return true


func _party_at_intro(sequence: Node) -> bool:
	var expected: Dictionary = sequence._gauntlet_intro_targets()
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		if sequence._game_state.get_position(member_id).distance_to(expected[member_id]) > 0.05:
			return false
	return true


func _capture(sequence: Node) -> Dictionary:
	return _json_round_trip(sequence.build_save_snapshot())


func _apply_capture(sequence: Node, capture: Dictionary) -> void:
	sequence.apply_save_snapshot(capture)
	for _frame in range(6):
		await process_frame


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		sequence.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
