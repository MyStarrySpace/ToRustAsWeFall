extends SceneTree

## Focused duration, interaction, recovery, and environment-quality audit for
## Shelter-To-Shelter Survival Range. Run with:
##   godot --headless --path . --script res://tools/verify_survival_range_extension.gd

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	var packed := load("res://scenes/fragments/fragment_preview.tscn") as PackedScene
	_check(packed != null, "fragment preview scene loads")
	if packed == null:
		_finish()
		return
	var preview: Node = packed.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "survival_range")
	root.add_child(preview)
	for _frame in range(8):
		await process_frame
	var chunk: Node = preview.get("_active_chunk")
	_check(chunk != null, "Survival Range boots in the shared playable preview")
	if chunk == null:
		await _dispose(preview)
		_finish()
		return

	_verify_pacing(chunk)
	_verify_environment(chunk)
	await _verify_measured_shortest()
	_verify_interactions(preview, chunk)
	_verify_failure_recovery(preview, chunk)

	await _dispose(preview)
	_finish()


func _verify_pacing(chunk: Node) -> void:
	print("\n=== Survival Range measured pacing ===")
	var contract: Dictionary = chunk.call("get_pacing_contract")
	var predictions: Dictionary = chunk.call("get_route_timing_predictions")
	var shortest_seconds := float(contract.get("shortest_modeled_clear_seconds", 0.0))
	var active_seconds := float(contract.get("active_seconds", 0.0))
	var route_distance := float(contract.get("route_distance_meters", 0.0))
	_check(float(contract.get("target_min_seconds", 0.0)) == 180.0
		and float(contract.get("target_max_seconds", 0.0)) == 300.0,
		"the range owns the ordinary-stretch three-to-five-minute target")
	_check(shortest_seconds >= 180.0 and shortest_seconds <= 300.0,
		"shortest successful modeled clear is inside the target (%.1fs)" % shortest_seconds)
	_check(str(contract.get("shortest_profile", "")) == "tuned_direct",
		"the risky tuned branch is honestly modeled as the shortest successful clear")
	_check(active_seconds >= 180.0 and float(contract.get("active_share", 0.0)) >= 0.99,
		"the shortest clear is traversal/work rather than padding (%.1fs active, %.1f%%)" % [
			active_seconds, float(contract.get("active_share", 0.0)) * 100.0])
	_check(route_distance >= 500.0,
		"the role-switched shortest route measures at least 500 combined meters (%.1fm)" % route_distance)
	_check(float(contract.get("work_seconds", 0.0)) >= 40.0,
		"more than forty seconds are distinct click-gated field work")
	_check(int(contract.get("decision_count", 0)) >= 2 and int(contract.get("branch_count", 0)) >= 3,
		"route, tune, and recovery choices expose at least three outcomes")
	_check(float(contract.get("idle_lock_seconds", -1.0)) == 0.0,
		"the duration model contains no idle timer lock")
	var manifest_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/pacing/level_targets.json"))
	var manifest: Dictionary = manifest_variant if manifest_variant is Dictionary else {}
	var target: Dictionary = LevelPacingContract.target_by_id(manifest, "ordinary_stretch")
	var pacing_report := LevelPacingContract.analyze(
		target,
		contract,
		manifest.get("rules", {}) as Dictionary
	)
	_check(bool(pacing_report.get("passed", false)),
		"the measured route passes the canonical ordinary-stretch pacing contract")

	var safe: Dictionary = predictions.get("optimal_safe", {})
	var direct: Dictionary = predictions.get("tuned_direct", {})
	var untuned: Dictionary = predictions.get("staged_safe", {})
	_check(bool(safe.get("success", false)) and float(safe.get("total_time", 0.0)) >= shortest_seconds,
		"scouted safe is successful and deliberately longer (%.1fs)" % float(safe.get("total_time", 0.0)))
	_check(bool(direct.get("success", false)) and float(direct.get("predicted_damage", 0.0)) > float(safe.get("predicted_damage", 0.0)),
		"direct is a real health-for-time tradeoff")
	_check(not bool(untuned.get("success", true)) and str(untuned.get("outcome", "")) == "late_window",
		"skipping the tune creates the authored recoverable window failure")
	print("  INFO: shortest %.1fs | active %.1fs | route %.1fm | movement %.1fs | work %.1fs" % [
		shortest_seconds,
		active_seconds,
		route_distance,
		float(contract.get("movement_seconds", 0.0)),
		float(contract.get("work_seconds", 0.0)),
	])


func _verify_measured_shortest() -> void:
	print("\n=== Survival Range shortest scheduler playthrough ===")
	var preview := await _spawn_preview()
	var chunk: Node = preview.get("_active_chunk")
	var prediction: Dictionary = chunk.call("predict_route_timing", "tuned_direct")
	var segments: Dictionary = prediction.get("segments", {})
	preview.call("headless_set_routing_mode", "direct")
	var start_tick := float((preview.call("headless_get_state") as Dictionary).get("scheduler_tick", 0.0))

	_dwell_and_call(preview, chunk, "aster", segments.get("depart", {}), "depart_range")
	_move_segment(preview, segments.get("scout", {}))
	_dwell_and_call(preview, chunk, "aster", segments.get("scout", {}), "survey_route")
	_move_segment(preview, segments.get("stage_endo", {}))
	_move_segment(preview, segments.get("echo", {}))
	_dwell_and_call(preview, chunk, "peris", segments.get("echo", {}), "tune_echo_coupler")
	_move_segment(preview, segments.get("stage_peris", {}))
	_dwell_and_call(preview, chunk, "peris", segments.get("lure", {}), "activate_range_lure")
	_check(bool(preview.call("headless_activate_ability", "peris_tune")),
		"Peris's real preview ability extends the shortest-route window")
	_dwell_and_call(preview, chunk, "endo", segments.get("cross", {}), "cross_seam")
	_move_segment(preview, segments.get("hide", {}))
	_dwell_and_call(preview, chunk, "endo", segments.get("hide", {}), "commit_hide")
	_check(not bool(chunk.call("rest_at_east_shelter")),
		"Endo releasing the sprint does not complete a proximity-only shelter win")
	var shelter_segment: Dictionary = segments.get("shelter", {})
	_move_party_segment(preview, shelter_segment)
	var atp_before := {}
	for char_id in ["aster", "peris", "endo"]:
		atp_before[char_id] = float(preview.call("get_preview_character_stat", char_id, "atp"))
	preview.call("headless_advance", float(shelter_segment.get("dwell_time", 0.0)), 0.05)
	_check(bool(chunk.call("rest_at_east_shelter")),
		"the assembled conscious party resolves the paid east-shelter rest")

	var final_state := preview.call("headless_get_state") as Dictionary
	var final_chunk: Dictionary = final_state.get("chunk", {})
	var measured_seconds := float(final_state.get("scheduler_tick", 0.0)) - start_tick
	var predicted_seconds := float(prediction.get("total_time", 0.0))
	_check(absf(measured_seconds - predicted_seconds) <= 0.08,
		"real GameState traversal/work matches the shortest model (%.1fs measured, %.1fs predicted)" % [
			measured_seconds, predicted_seconds])
	_check(str(final_chunk.get("route_phase", "")) == "complete"
		and str(final_chunk.get("last_outcome", "")) == "success",
		"the measured risky branch reaches the east shelter successfully")
	_check((final_chunk.get("segments_completed", []) as Array).has("departed")
		and (final_chunk.get("segments_completed", []) as Array).has("scouted")
		and (final_chunk.get("segments_completed", []) as Array).has("echo")
		and (final_chunk.get("segments_completed", []) as Array).has("lure")
		and (final_chunk.get("segments_completed", []) as Array).has("seam")
		and (final_chunk.get("segments_completed", []) as Array).has("hide")
		and (final_chunk.get("segments_completed", []) as Array).has("shelter"),
		"the shortest measured clear performs every authored field beat")
	for char_id in ["aster", "peris", "endo"]:
		_check(is_equal_approx(
			float(preview.call("get_preview_character_stat", char_id, "atp")),
			float(atp_before[char_id]) - chunk.SHELTER_ATP_COST
		), "%s pays one ATP for the authored night rest" % char_id.capitalize())
	await _dispose(preview)


func _spawn_preview() -> Node:
	var packed := load("res://scenes/fragments/fragment_preview.tscn") as PackedScene
	var preview: Node = packed.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "survival_range")
	root.add_child(preview)
	for _frame in range(8):
		await process_frame
	return preview


func _move_segment(preview: Node, segment: Dictionary) -> void:
	var character_id := str(segment.get("character", ""))
	preview.call("headless_select_character", character_id)
	var destination: Vector3 = segment.get("end_position", Vector3.ZERO)
	var running := bool(segment.get("running", false))
	_check(bool(preview.call("headless_move_character", character_id, destination, running)),
		"%s begins the %s traversal command" % [character_id.capitalize(), str(segment.get("label", "route"))])
	var movement_info := preview.call("headless_get_character_movement_info", character_id) as Dictionary
	var duration := float(movement_info.get("duration", 0.0))
	preview.call("headless_advance", duration, 0.05)
	if bool(preview.call("headless_is_character_moving", character_id)):
		preview.call("headless_advance", 0.001, 0.001)


func _move_party_segment(preview: Node, segment: Dictionary) -> void:
	var movements: Dictionary = segment.get("party_movements", {})
	var longest_duration := 0.0
	for character_id in ["aster", "peris", "endo"]:
		var movement: Dictionary = movements.get(character_id, {})
		var destination: Vector3 = movement.get("end_position", Vector3.ZERO)
		var running := bool(movement.get("running", false))
		_check(bool(preview.call("headless_move_character", character_id, destination, running)),
			"%s begins parallel shelter assembly" % character_id.capitalize())
		var movement_info := preview.call("headless_get_character_movement_info", character_id) as Dictionary
		longest_duration = maxf(longest_duration, float(movement_info.get("duration", 0.0)))
	preview.call("headless_advance", longest_duration, 0.05)
	for character_id in ["aster", "peris", "endo"]:
		if bool(preview.call("headless_is_character_moving", character_id)):
			preview.call("headless_advance", 0.001, 0.001)


func _dwell_and_call(preview: Node, chunk: Node, character_id: String,
		segment: Dictionary, method_name: String) -> void:
	preview.call("headless_select_character", character_id)
	var dwell_seconds := float(segment.get("dwell_time", 0.0))
	preview.call("headless_advance", dwell_seconds, 0.05)
	_check(bool(chunk.call(method_name)), "%s resolves its %.0fs click-gated work beat" % [
		character_id.capitalize(), dwell_seconds])


func _verify_environment(chunk: Node) -> void:
	print("\n=== Survival Range environment hierarchy ===")
	var audit: Dictionary = chunk.call("get_decoration_audit")
	_check(chunk.find_child("LevelDecoration", true, false) != null and not audit.is_empty(),
		"the range uses the shared building-quality decoration system")
	_check(int(audit.get("collision_shapes", -1)) == 0
		and str(audit.get("clearance", "")) == "surface_only_no_obstacles",
		"environment dressing is explicitly collision-free")
	_check(int(audit.get("instances", 0)) >= 400 and int(audit.get("stations", 0)) >= 20,
		"the 324m course has a dense deterministic facade hierarchy")
	_check(chunk.find_children("RangeRibBeam_*", "MeshInstance3D", true, false).size() == 8,
		"eight measured structural ribs divide the long course")
	_check(chunk.find_children("RangeMeasure_*", "MeshInstance3D", true, false).size() == 39,
		"continuous distance ticks make the traversal scale readable")
	_check(chunk.find_child("RangeSafeDatum", true, false) != null
		and chunk.find_child("RangeDirectDatum", true, false) != null,
		"safe and direct floor datums physically advertise the route decision")
	print("  INFO: decoration %d instances / %d facade stations / %d batches / %d signs / %d landmark lights" % [
		int(audit.get("instances", 0)),
		int(audit.get("stations", 0)),
		int(audit.get("batches", 0)),
		int(audit.get("labels", 0)),
		int(audit.get("lights", 0)),
	])


func _verify_interactions(preview: Node, chunk: Node) -> void:
	print("\n=== Survival Range interaction gates ===")
	var range_interactables := chunk.find_children("Range*Interactable", "Interactable", true, false)
	_check(range_interactables.size() == 9,
		"briefing, scout, echo, lure, two routes, hide, recovery, and shelter are nine real Interactables")
	var timed_count := 0
	var outlined_count := 0
	for interactable in range_interactables:
		if int(interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed_count += 1
		if interactable.get("_outline_target") != null:
			outlined_count += 1
	_check(timed_count == 9, "every range station is a click-gated timed action")
	_check(outlined_count == 9, "every range station binds visible object outline feedback")

	var depart: Node = chunk.find_child("RangeDepartureInteractable", true, false)
	var scout: Node = chunk.find_child("RangeScoutInteractable", true, false)
	var echo: Node = chunk.find_child("RangeEchoInteractable", true, false)
	var lure: Node = chunk.find_child("RangeLureInteractable", true, false)
	var seam: Node = chunk.find_child("RangeSeamInteractable", true, false)
	var direct: Node = chunk.find_child("RangeDirectInteractable", true, false)
	var hide: Node = chunk.find_child("RangeHideInteractable", true, false)
	var recovery: Node = chunk.find_child("RangeRecoveryInteractable", true, false)
	var shelter: Node = chunk.find_child("RangeEastShelterInteractable", true, false)
	_check(depart.is_interaction_enabled() and not scout.is_interaction_enabled() and not echo.is_interaction_enabled()
		and not lure.is_interaction_enabled() and not seam.is_interaction_enabled() and not direct.is_interaction_enabled()
		and not hide.is_interaction_enabled() and not recovery.is_interaction_enabled()
		and not shelter.is_interaction_enabled(),
		"initial gates expose only the west-shelter briefing")
	_check(str(shelter.get("required_character")) == ""
		and is_equal_approx(float(shelter.get("dwell_time")), chunk.SHELTER_REST_SECONDS),
		"the shelter is a four-second party interaction rather than an Endo-only trigger")

	preview.call("headless_select_character", "aster")
	preview.call("headless_set_character_position", "aster", chunk.WEST_SHELTER_POS)
	_check(bool(chunk.call("depart_range")), "Aster can commit the shelter briefing")
	_check(scout.is_interaction_enabled() and not lure.is_interaction_enabled(),
		"safe routing unlocks scout work before lure work")
	preview.call("headless_set_routing_mode", "direct")
	_check(not lure.is_interaction_enabled() and not seam.is_interaction_enabled() and direct.is_interaction_enabled(),
		"direct exposes its own unprotected clickable bloom but cannot skip Aster's success-critical read")


func _verify_failure_recovery(preview: Node, chunk: Node) -> void:
	print("\n=== Survival Range bounded failure recovery ===")
	preview.call("headless_select_character", "endo")
	preview.call("headless_set_character_position", "endo", chunk.SHORT_BLOOM_POS)
	_check(bool(chunk.call("cross_seam")), "Endo can take the exposed direct bloom")
	preview.call("headless_set_character_position", "endo", chunk.HIDE_SLIT_POS)
	_check(not bool(chunk.call("commit_hide")), "crossing without a lure fails at the hide slit")
	var state: Dictionary = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "failed"
		and str(state.get("last_outcome", "")) == "hide_without_window",
		"the failure has a specific, inspectable cause")
	var recovery: Node = chunk.find_child("RangeRecoveryInteractable", true, false)
	_check(recovery.is_interaction_enabled(), "failure enables the local reset winch")

	preview.call("headless_set_character_position", "endo", chunk.RECOVERY_RIG_POS)
	_check(bool(chunk.call("recover_from_failure")), "Endo can work the reset winch without restarting the fragment")
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) != "failed"
		and int(state.get("recovery_count", 0)) == 1
		and bool(state.get("recovery_assist", false)),
		"recovery preserves progress and grants one bounded retry assist")

	preview.call("headless_select_character", "aster")
	preview.call("headless_set_character_position", "aster", chunk.SCOUT_PERCH_POS)
	_check(bool(chunk.call("survey_route")), "a greedy failure rejoins at the missing course-read gate")
	preview.call("headless_select_character", "peris")
	preview.call("headless_set_character_position", "peris", chunk.ECHO_COUPLER_POS)
	_check(bool(chunk.call("tune_echo_coupler")), "Peris restores the missing mid-course echo calibration")
	preview.call("headless_set_character_position", "peris", chunk.LURE_SPINDLE_POS)
	_check(bool(chunk.call("activate_range_lure")), "the recovered lure station opens a retry window")
	state = chunk.call("get_preview_state")
	_check(float(state.get("lure_remaining", 0.0)) >= chunk.LURE_DURATION + chunk.PERIS_TUNE_BONUS - 0.01,
		"the winch's one-shot stored pulse makes the retry independently solvable")

	preview.call("headless_select_character", "endo")
	preview.call("headless_set_character_position", "endo", chunk.SHORT_BLOOM_POS)
	_check(bool(chunk.call("cross_seam")), "Endo can recommit the seam after recovery")
	preview.call("headless_set_character_position", "endo", chunk.HIDE_SLIT_POS)
	_check(bool(chunk.call("commit_hide")), "the recovered concealment releases the shelter sprint immediately")
	preview.call("headless_set_character_position", "endo", chunk.EAST_SHELTER_POS)
	chunk.call("headless_process", 0.01)
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "run" and not bool(state.get("shelter_reached", false))
		and not bool(chunk.call("rest_at_east_shelter")),
		"Endo alone cannot finish the route by crossing the shelter radius")
	for char_id in ["aster", "peris", "endo"]:
		preview.call("headless_set_character_position", char_id, chunk.EAST_SHELTER_POS)
	var atp_before := {}
	for char_id in ["aster", "peris", "endo"]:
		atp_before[char_id] = float(preview.call("get_preview_character_stat", char_id, "atp"))
	_check(bool(chunk.call("rest_at_east_shelter")),
		"the conscious full party can pay for the bounded-recovery shelter rest")
	state = chunk.call("get_preview_state")
	_check(str(state.get("route_phase", "")) == "complete" and bool(state.get("shelter_rested", false)),
		"the bounded recovery rejoins and completes through the authored hearth")
	for char_id in ["aster", "peris", "endo"]:
		_check(is_equal_approx(
			float(preview.call("get_preview_character_stat", char_id, "atp")),
			float(atp_before[char_id]) - chunk.SHELTER_ATP_COST
		), "%s pays the recovery-route night cost" % char_id.capitalize())


func _dispose(preview: Node) -> void:
	preview.queue_free()
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nSurvival Range extension verification: ALL PASSED")
		quit(0)
	else:
		print("\nSurvival Range extension verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		quit(1)
