extends SceneTree

## Focused systemic-puzzle verification for the Elevator lower route and Endo
## handoff. Run with:
##   godot --headless --path . --script res://tools/verify_elevator_quality_extension.gd

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _trigger_flure(sequence: Node, flure: Flure) -> bool:
	if flure == null:
		return false
	sequence._game_state.command_stop("peris")
	sequence._game_state.snap_character_to("peris", flure.get_source_data_position())
	flure.active_character = "peris"
	return bool(flure.call("_trigger", false))


func _place_party(sequence: Node, pos: Vector3, z_spread := 0.8) -> void:
	sequence.set_preview_character_position("aster", pos + Vector3(0.0, 0.5, -z_spread * 0.5))
	sequence.set_preview_character_position("peris", pos + Vector3(-0.7, 0.5, z_spread * 0.5))


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	var packed := load("res://scenes/tutorial/elevator.tscn") as PackedScene
	_check(packed != null, "Elevator scene loads")
	if packed == null:
		_finish()
		return
	var sequence: Node = packed.instantiate()
	sequence.set("suppress_scene_change", true)
	root.add_child(sequence)
	for _frame in range(8):
		await process_frame
	sequence._scheduler.clear()

	var contract: Dictionary = sequence.get_playtime_contract()
	_check(str(contract.get("contract_id", "")).contains("systemic"),
		"the pacing contract names the systemic redesign")
	_check(int(contract.get("route_strategies", 0)) >= 3
		and int(contract.get("route_crossovers", 0)) == 2,
		"the contract requires fast, cautious, and hybrid route plans")
	_check(int(contract.get("mandatory_route_overlay_reads", -1)) == 0
		and int(contract.get("mandatory_junction_inspections", -1)) == 0
		and int(contract.get("mandatory_field_actions", -1)) == 0,
		"information and world-building are not progression currency")
	_check(int(contract.get("solved_state_execution_tail_actions", 99)) <= 1
		and float(contract.get("solved_state_execution_tail_seconds", 99.0)) <= 15.0,
		"the solved-state execution tail is short")

	var below: Node = sequence._load_chunk("below")
	await process_frame
	_check(below != null, "the lower route builds")
	_check(sequence._route_flure_interactables.size() == 3
		and sequence._route_flure_enemy_groups.size() == 3,
		"three reusable Flures each own one deterministic pack")
	for beat_index in range(3):
		var flure: Node = sequence._route_flure_interactables[beat_index]
		var pack: Array = sequence._route_flure_enemy_groups.get(beat_index, [])
		_check(flure is Flure and not bool(flure.one_shot)
			and absf(float(flure.lure_duration) - sequence.ROUTE_FLURE_DURATION) < 0.01,
			"beat %d uses the reusable, re-tendable timed Flure" % (beat_index + 1))
		_check((flure as Flure).global_position.distance_to((flure as Flure).settle_pos) >= 4.0,
			"beat %d keeps Peris's interaction perch outside the lured pack's inner reach" % (beat_index + 1))
		_check(pack.size() == 2 and (sequence._route_causal_links.get(beat_index, []) as Array).size() == 2,
			"beat %d exposes two truthful Flure-to-pack links" % (beat_index + 1))

	var aster_overlay: Node = below.find_child("AsterRouteOverlay", true, false)
	var peris_overlay: Node = below.find_child("PerisRouteOverlay", true, false)
	_check(aster_overlay != null and peris_overlay != null,
		"both perception registers exist independently")
	_check(aster_overlay.find_children("*", "PathRenderer", true, false).is_empty()
		and peris_overlay.find_children("*", "PathRenderer", true, false).is_empty()
		and below.find_child("AsterEcologyRoute*", true, false) == null
		and below.find_child("PerisSafeRouteGuide", true, false) == null,
		"neither overlay contains an authored entry-to-exit solution path")
	_check(below.find_child("PerisRouteFinalPosition", true, false) == null,
		"the factual hazard overlay does not author a final solution position")
	_check(peris_overlay.find_children("PerisIronBoundary*", "MeshInstance3D", true, false).size() == 12,
		"Peris still exposes every exact iron boundary")

	for crossover_index in range(sequence.ROUTE_CROSSOVER_X_OFFSETS.size()):
		var offset := float(sequence.ROUTE_CROSSOVER_X_OFFSETS[crossover_index])
		var crossover_x: float = sequence.FORK_POS.x + offset
		var crossover_cell: Vector2i = sequence._grid.world_to_grid(
			Vector3(crossover_x, sequence.BELOW_Y, 0.0))
		var wall_cell: Vector2i = sequence._grid.world_to_grid(
			Vector3(crossover_x + sequence.ROUTE_CROSSOVER_WIDTH, sequence.BELOW_Y, 0.0))
		_check(sequence._grid.is_cell_allowed_on_level(crossover_cell, sequence.LEVEL_LOWER)
			and not sequence._grid.is_cell_allowed_on_level(wall_cell, sequence.LEVEL_LOWER),
			"crossover %d is a real opening in an otherwise blocked divider" % (crossover_index + 1))

	# Drive the real two-body thresholds for all three spatial plans. These are not contract metadata:
	# every result is derived from where both characters actually cross each beat.
	for plan_spec in [
		{"lanes": [-4.0, -4.0, -4.0], "expected": "flure"},
		{"lanes": [4.0, 4.0, 4.0], "expected": "iron"},
		{"lanes": [-4.0, 4.0, -4.0], "expected": "hybrid"},
	]:
		sequence._route_beats_crossed.assign([false, false, false])
		sequence._route_beat_character_lanes.assign([{}, {}, {}])
		sequence._route_beat_character_windows.assign([{}, {}, {}])
		sequence._route_beat_lanes.assign(["", "", ""])
		sequence._route_lane = ""
		var lanes: Array = plan_spec["lanes"]
		for beat_index in range(sequence.ROUTE_BEAT_COUNT):
			var threshold_x: float = sequence.FORK_POS.x \
				+ float(sequence.ROUTE_BEAT_OFFSETS[beat_index]) \
				+ float(sequence.ROUTE_BEAT_CLEARANCE_OFFSET) + 1.2
			var lane_z := float(lanes[beat_index])
			sequence.set_preview_character_position(
				"aster", Vector3(threshold_x, sequence.BELOW_Y + 0.5, lane_z - 0.25))
			sequence.set_preview_character_position(
				"peris", Vector3(threshold_x, sequence.BELOW_Y + 0.5, lane_z + 0.25))
			sequence._update_route_course_progress()
		_check(sequence._route_beats_crossed.count(true) == sequence.ROUTE_BEAT_COUNT
			and sequence._route_lane == str(plan_spec["expected"]),
			"the %s plan completes through real two-body spatial thresholds" % str(plan_spec["expected"]))
	# Preserve the lane at each body's crossing instant. A faster leader may use the next crossover
	# before the trailer arrives; later position must not rewrite earlier traversal history.
	sequence._route_beats_crossed.assign([false, false, false])
	sequence._route_beat_character_lanes.assign([{}, {}, {}])
	sequence._route_beat_character_windows.assign([{}, {}, {}])
	sequence._route_beat_lanes.assign(["", "", ""])
	var first_threshold: float = sequence.FORK_POS.x + float(sequence.ROUTE_BEAT_OFFSETS[0]) \
		+ float(sequence.ROUTE_BEAT_CLEARANCE_OFFSET) + 0.2
	sequence.set_preview_character_position("aster",
		Vector3(first_threshold, sequence.BELOW_Y + 0.5, -4.0))
	sequence.set_preview_character_position("peris",
		Vector3(sequence.FORK_POS.x, sequence.BELOW_Y + 0.5, -4.0))
	sequence._update_route_course_progress()
	sequence.set_preview_character_position("aster",
		Vector3(sequence.FORK_POS.x + float(sequence.ROUTE_CROSSOVER_X_OFFSETS[0]) + 1.0,
			sequence.BELOW_Y + 0.5, 4.0))
	sequence.set_preview_character_position("peris",
		Vector3(first_threshold, sequence.BELOW_Y + 0.5, -4.0))
	sequence._update_route_course_progress()
	_check(sequence._route_beat_lanes[0] == "flure",
		"a leader's later crossover cannot rewrite either body's beat-one lane history")
	sequence._route_beats_crossed.assign([false, false, false])
	sequence._route_beat_character_lanes.assign([{}, {}, {}])
	sequence._route_beat_character_windows.assign([{}, {}, {}])
	sequence._route_beat_lanes.assign(["", "", ""])
	sequence._route_lane = ""

	for character_id in ["aster", "peris"]:
		sequence._game_state.set_character_level(character_id, sequence.LEVEL_LOWER)
		sequence.set_preview_character_position(character_id,
			Vector3(sequence.FORK_POS.x - 2.0, sequence.BELOW_Y + 0.5, -4.0))
	sequence._activate_below_fauna()
	sequence._start_route_read_circuit()
	sequence._dialogue.clear()
	sequence.headless_advance(0.5, 0.05)
	var state: Dictionary = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "route_choice"
		and int(state.get("route_read_count", -1)) == 1,
		"route control starts with only Aster's already-live information")
	var cautious_before: bool = sequence._game_state.is_route_cautious()
	sequence._set_elevator_overlay_state("peris", true)
	sequence._dialogue.clear()
	_check(sequence._game_state.is_route_cautious() == cautious_before,
		"F2 adds hazard knowledge without silently changing SAFE/DIRECT policy")
	_check(bool(sequence.headless_get_state().get("wreckage_armed", false)),
		"the physical two-body gate is authoritative from route start")
	var route_walk_speed := 2.5
	var first_route_exit := Vector3(
		sequence.FORK_POS.x + float(sequence.ROUTE_BEAT_OFFSETS[0]) \
			+ float(sequence.ROUTE_BEAT_CLEARANCE_OFFSET) + 0.4,
		sequence.BELOW_Y + 0.5,
		-4.0
	)
	var staged_route_seconds: float = sequence._route_flure_position(0).distance_to(first_route_exit) / route_walk_speed
	var unstaged_route_seconds: float = Vector3(
		sequence.FORK_POS.x, sequence.BELOW_Y + 0.5, 0.0
	).distance_to(first_route_exit) / route_walk_speed
	_check(staged_route_seconds < sequence.ROUTE_FLURE_DURATION
		and unstaged_route_seconds > sequence.ROUTE_FLURE_DURATION,
		"the route window rewards staging while an unstaged walker misses it")

	# Causal ablation: activation alone makes no route progress. An early unused
	# window expires, restores the watch, and remains recoverable.
	var first_flure := sequence._route_flure_interactables[0] as Flure
	var first_pack: Array = sequence._route_flure_enemy_groups[0]
	# Stage at the actual interaction perch so proximity streaming wakes the complete linked cohort,
	# matching a real command-click instead of calling a distant station from the fork.
	_place_party(sequence, first_flure.global_position)
	sequence._update_below_fauna_activation(true)
	_check(first_pack.all(func(enemy: Enemy) -> bool:
		return sequence._game_state.characters.has(enemy.char_id)),
		"the interaction perch wakes the complete linked pack before evaluation")
	_check(not sequence._game_state.is_character_distracted((first_pack[0] as Enemy).char_id),
		"an unprimed route pack genuinely guards its lane")
	var first_pack_home: Array[Vector3] = []
	for enemy_variant in first_pack:
		var enemy := enemy_variant as Enemy
		first_pack_home.append(sequence._game_state.get_position(enemy.char_id))
		sequence._game_state.snap_character_to(
			enemy.char_id, Vector3(sequence.FORK_POS.x + 200.0, sequence.BELOW_Y, 0.0))
	_check(not _trigger_flure(sequence, first_flure),
		"a physical source with no eligible linked pack reports failure")
	var empty_report := first_flure.get_last_activation_report()
	state = sequence.headless_get_state()
	_check(not bool((state.get("route_flures_activated", []) as Array)[0])
		and int((state.get("route_flure_activation_counts", []) as Array)[0]) == 0
		and int(state.get("route_wasted_flure_windows", 0)) == 0
		and (empty_report.get("out_of_range_ids", []) as Array).size() == first_pack.size()
		and first_flure.is_interaction_enabled(),
		"an empty preflight spends no source, window, or successful-prime credit")
	first_flure.reset_flure()
	for enemy_index in range(first_pack.size()):
		var enemy := first_pack[enemy_index] as Enemy
		sequence._game_state.snap_character_to(enemy.char_id, first_pack_home[enemy_index])
		enemy.global_position = first_pack_home[enemy_index]
		enemy._fsm.transition_to("alert")
	_check(not _trigger_flure(sequence, first_flure),
		"a physical activation after acquisition is rejected as a timing error")
	var late_report := first_flure.get_last_activation_report()
	state = sequence.headless_get_state()
	_check((late_report.get("committed_ids", []) as Array).size() == first_pack.size()
		and not bool((state.get("route_flures_activated", []) as Array)[0])
		and int((state.get("route_flure_activation_counts", []) as Array)[0]) == 0
		and int(state.get("route_wasted_flure_windows", 0)) == 0
		and first_flure.is_interaction_enabled(),
		"a late preflight identifies committed guards without spending a window")
	first_flure.reset_flure()
	for enemy_index in range(first_pack.size()):
		var enemy := first_pack[enemy_index] as Enemy
		enemy.re_post(first_pack_home[enemy_index])
	(first_pack[0] as Enemy)._fsm.transition_to("alert")
	_check(_trigger_flure(sequence, first_flure),
		"a partial two-guard physical pull still reports that one guard moved")
	var partial_report := first_flure.get_last_activation_report()
	state = sequence.headless_get_state()
	_check((partial_report.get("pulled_ids", []) as Array).size() == 1
		and (partial_report.get("committed_ids", []) as Array).size() == 1
		and bool((state.get("route_flures_activated", []) as Array)[0])
		and int((state.get("route_flure_activation_counts", []) as Array)[0]) == 0
		and int(state.get("route_wasted_flure_windows", 0)) == 1
		and "PARTIAL 1/2" in sequence._route_flure_status(0).text,
		"a partial pull stays visibly unsafe and earns no successful-prime credit")
	first_flure.reset_flure()
	for enemy_index in range(first_pack.size()):
		var enemy := first_pack[enemy_index] as Enemy
		enemy.re_post(first_pack_home[enemy_index])
	_check(_trigger_flure(sequence, first_flure),
		"an informed physical activation pulls the linked first pack")
	_check((first_pack[0] as Enemy).get_state() == "lured"
		and sequence._game_state.is_character_distracted((first_pack[0] as Enemy).char_id),
		"the reusable enemy FSM owns the lured consequence")
	sequence._on_process(0.01, 1.0)
	_check((sequence.headless_get_state().get("route_beats_crossed", []) as Array).count(true) == 0,
		"activation without movement earns no spatial progress")
	sequence.headless_advance(sequence.ROUTE_FLURE_DURATION + 0.2, 0.1)
	state = sequence.headless_get_state()
	_check(not bool((state.get("route_flures_activated", []) as Array)[0])
		and int(state.get("route_wasted_flure_windows", 0)) == 2
		and (first_pack[0] as Enemy).get_state() != "lured",
		"an early window visibly expires and the pack resumes its watch")
	# A nearby pack may reacquire immediately when the song ends. Retreat, let it reset to its public
	# post contract, then revise the failed prediction instead of assuming a mid-attack signal works.
	_place_party(sequence, Vector3(sequence.FORK_POS.x - 10.0, sequence.BELOW_Y, 0.0))
	for enemy_index in range(first_pack.size()):
		(first_pack[enemy_index] as Enemy).re_post(first_pack_home[enemy_index])
	_check(_trigger_flure(sequence, first_flure),
		"the failed prediction can be revised by physically re-priming")
	var first_exit_x: float = sequence.FORK_POS.x + float(sequence.ROUTE_BEAT_OFFSETS[0]) \
		+ float(sequence.ROUTE_BEAT_CLEARANCE_OFFSET) + 0.4
	sequence.set_preview_character_position("aster", Vector3(first_exit_x, sequence.BELOW_Y + 0.5, -4.2))
	sequence._on_process(0.01, 1.0)
	_check(not bool((sequence.headless_get_state().get("route_beats_crossed", []) as Array)[0]),
		"one skilled scout cannot convert into party progress")
	sequence.set_preview_character_position("peris", Vector3(first_exit_x, sequence.BELOW_Y + 0.5, -3.8))
	sequence._on_process(0.01, 1.0)
	state = sequence.headless_get_state()
	_check(bool((state.get("route_beats_crossed", []) as Array)[0])
		and bool((state.get("route_flure_windows_used", []) as Array)[0]),
		"staging and crossing both characters during the window records a used plan")

	# Iron is an alternate plan with exact, inspectable failure provenance.
	var iron_x: float = sequence.FORK_POS.x + float(sequence.ROUTE_BEAT_OFFSETS[1])
	var hp_before: float = sequence._game_state.get_stat("aster", "hp")
	sequence.set_preview_character_position("aster", Vector3(iron_x, sequence.BELOW_Y + 0.5, 3.3))
	sequence._iron_hazard_tick()
	state = sequence.headless_get_state()
	var provenance: Array = state.get("route_failure_provenance", [])
	_check(sequence._game_state.get_stat("aster", "hp") < hp_before
		and not provenance.is_empty()
		and str((provenance.back() as Dictionary).get("source_id", "")) == "iron_field_2",
		"iron damage names the exact field and falsifies the player's prediction")

	# Endo's shelter keeps its optional world-building, but Peris's authored plant
	# is the only required transition. No reward menu mutates health or later timing.
	sequence._dialogue.clear()
	sequence._start_junction_arrive()
	await process_frame
	state = sequence.headless_get_state()
	_check(sequence._junction_interactables.size() >= 6
		and int(state.get("junction_inspection_count", -1)) == 0,
		"shelter objects remain optional world-building")
	var junction_chunk: Node = sequence._chunks.get("junction")
	_check(junction_chunk != null
		and junction_chunk.find_child("JunctionField_*", true, false) == null
		and junction_chunk.find_child("JunctionPrep*", true, false) == null
		and sequence._junction_beat.preparation_choices.is_empty()
		and not sequence.has_method("_build_junction_field_annex")
		and not state.has("junction_field_protocol")
		and not state.has("junction_preparation"),
		"the retired annex/preparation layer has no nodes, builder, or progress state")
	var plant: Node = sequence._junction_plant_interactable
	_check(is_instance_valid(plant) and bool(plant.get("interaction_enabled")),
		"Peris's dormant-plant transition is available immediately")
	_check(str(plant.get("required_character")) == "peris"
		and str(plant.get("tutorial_label")).contains("TEND")
		and not bool(state.get("junction_tended", true)),
		"the world labels the canonical Peris verb before it is committed")
	sequence._game_state.set_stat("aster", "hp", 20.0)
	sequence._game_state.set_stat("peris", "hp", 20.0)
	sequence._start_dusk_from_plant()
	state = sequence.headless_get_state()
	_check(bool(state.get("junction_tended", false))
		and sequence._game_state.get_stat("aster", "hp") == 20.0
		and sequence._game_state.get_stat("peris", "hp") == 20.0,
		"tending completes the story beat without inventing a health reward")

	if not sequence._game_state.characters.has("endo"):
		sequence._set_endo_presenter_present(true)
		sequence._endo.global_position = sequence._endo_entry_destination()
		sequence._register_gs_character("endo", sequence._endo, 2.5, {
			"hp": sequence.PARTY_MAX_HP,
			"stamina": GameState.STAMINA_MAX,
			"atp": GameState.ATP_MAX_PIPS,
		})
	var gauntlet_targets: Dictionary = sequence._gauntlet_intro_targets()
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		var target: Vector3 = gauntlet_targets[member_id]
		var approach := target + Vector3(-2.0, 0.0, 0.0)
		sequence._game_state.command_stop(member_id)
		sequence._game_state.set_character_level(member_id, sequence.LEVEL_LOWER)
		sequence._game_state.snap_character_to(member_id, approach)
	sequence._start_gauntlet()
	sequence._dialogue.clear()
	sequence._finish_gauntlet_intro()
	for member_id in sequence.GAUNTLET_INTRO_REQUIRED_MEMBERS:
		sequence._gauntlet_intro_authority["next_retry_tick"] = \
			sequence._scheduler.get_current_tick()
		sequence._issue_next_gauntlet_intro_move()
		sequence._game_state.command_stop(member_id)
		sequence._game_state.snap_character_to(member_id, gauntlet_targets[member_id])
		sequence._update_gauntlet_intro_formation()
	_check(str(sequence._gauntlet_intro_authority.get("phase", "")) \
		== sequence.GAUNTLET_INTRO_PHASE_READY,
		"the gauntlet test earns control through the physical three-body briefing endpoint")
	sequence._scheduler.clear()
	for enemy_variant in sequence._enemies:
		if is_instance_valid(enemy_variant) and enemy_variant is Enemy:
			(enemy_variant as Enemy).set_detection_targets([])
	# The fixed timing crossover rewards real staging: an unstaged midpoint walk is
	# too slow, while the actor already at Flure 2 can clear the same base window.
	var walking_speed: float = 2.5
	var exit_threshold := Vector3(sequence.GAUNTLET_EXIT.x - 2.0, sequence.BELOW_Y, 0.0)
	var unstaged_second_relay_seconds: float = sequence.GAUNTLET_MIDPOINT.distance_to(exit_threshold) / walking_speed
	var staged_peris_seconds: float = sequence.GAUNTLET_FLURE_2_POS.distance_to(exit_threshold) / walking_speed
	_check(unstaged_second_relay_seconds > sequence.FLURE_DURATION,
		"an unstaged partner cannot beat the fixed Flure window by walking")
	_check(staged_peris_seconds < sequence.FLURE_DURATION,
		"staging at Flure 2 beats the fixed window")
	sequence._reach_gauntlet_midpoint()
	var second_flure := sequence._gauntlet_flure_interactables[1] as Flure
	_check(absf(second_flure.lure_duration - sequence.FLURE_DURATION) < 0.01,
		"the gauntlet Flure always uses the canonical base duration")
	var second_pack: Array = sequence._gauntlet_enemy_groups[1]
	for enemy_variant in second_pack:
		var enemy := enemy_variant as Enemy
		enemy.set_detection_targets([])
		enemy.re_post(sequence._gauntlet_enemy_posts[enemy.char_id])
	(second_pack[0] as Enemy)._fsm.transition_to("alert")
	_check(_trigger_flure(sequence, second_flure),
		"a late physical relay can visibly pull only part of its pack")
	state = sequence.headless_get_state()
	_check(not bool(sequence._gauntlet_flure_active.get(1, false))
		and int(state.get("gauntlet_wasted_flure_windows", 0)) == 1,
		"a partial gauntlet pull remains unsafe and earns no active window")
	sequence._scheduler.advance_ticks(sequence.FLURE_DURATION + 0.1)
	_check(not second_flure.is_active() and second_flure.is_interaction_enabled(),
		"an early or late failed signal rearms without requiring death")
	for enemy_variant in second_pack:
		var enemy := enemy_variant as Enemy
		enemy.set_detection_targets([])
		enemy.re_post(sequence._gauntlet_enemy_posts[enemy.char_id])
	_check(_trigger_flure(sequence, second_flure),
		"the ordinary second Flure source pulls its complete live pack")
	sequence._scheduler.advance_ticks(sequence.FLURE_DURATION + 0.1)
	_check(not bool(sequence._gauntlet_flure_active.get(1, false)),
		"the ordinary second Flure has returned after 14 seconds")

	# Resetting a failed attempt owns and cancels its old timer generation. The stale first expiry
	# must not close a newly activated window twelve seconds later.
	for enemy_variant in second_pack:
		var enemy := enemy_variant as Enemy
		enemy.set_detection_targets([])
		enemy.re_post(sequence._gauntlet_enemy_posts[enemy.char_id])
	_check(_trigger_flure(sequence, second_flure),
		"a baseline physical window starts before the refuge reset race")
	sequence._scheduler.advance_ticks(2.0)
	sequence._reset_gauntlet_to_refuge()
	sequence._scheduler.advance_ticks(1.1)
	for enemy_variant in second_pack:
		var enemy := enemy_variant as Enemy
		enemy.set_detection_targets([])
		enemy.re_post(sequence._gauntlet_enemy_posts[enemy.char_id])
	_check(_trigger_flure(sequence, second_flure),
		"the reset station can begin a corrected physical attempt")
	sequence._scheduler.advance_ticks(12.1)
	_check(bool(sequence._gauntlet_flure_active.get(1, false)),
		"an obsolete expiry cannot close the corrected window early")
	sequence._scheduler.advance_ticks(2.0)
	_check(not bool(sequence._gauntlet_flure_active.get(1, false)),
		"the corrected baseline window closes on its own 14-second clock")

	await _dispose(sequence)
	_finish()


func _dispose(sequence: Node) -> void:
	if is_instance_valid(sequence):
		sequence.queue_free()
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("Elevator systemic puzzle verification: ALL PASSED")
		quit(0)
	else:
		print("Elevator systemic puzzle verification: %d FAILED" % _failures.size())
		quit(1)
