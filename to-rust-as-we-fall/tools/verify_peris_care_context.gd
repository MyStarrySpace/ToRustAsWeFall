extends SceneTree

## Focused first-clear and state-machine contract for Peris's care audit and
## four-stage field-care operation circuit.
##
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_peris_care_context.gd

const PERIS_SCENE := preload("res://scenes/tutorial/peris_sim.tscn")
const EPSILON := 0.01

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	var sequence: Node = await _make_sequence()
	if sequence == null:
		_finish()
		return

	var zones := {
		"BookshelfPlantsZone": sequence.find_child("BookshelfPlantsZone", true, false),
		"PlantStandZone": sequence.find_child("PlantStandZone", true, false),
		"CoffeeTablePlantsZone": sequence.find_child("CoffeeTablePlantsZone", true, false),
		"FernZone": sequence.find_child("FernZone", true, false),
		"PeaceLilyZone": sequence.find_child("PeaceLilyZone", true, false),
		"PaintingZone": sequence.find_child("PaintingZone", true, false),
		"WellnessZone": sequence.find_child("WellnessZone", true, false),
		"StrikeWarningZone": sequence.find_child("StrikeWarningZone", true, false),
	}
	var logbook: Node = sequence.find_child("LogbookGate", true, false)
	var watering_can: Node = sequence.find_child("WateringCanPickup", true, false)
	var water_fern: Node = sequence.find_child("WaterPlantSpot", true, false)
	for zone_name in zones:
		_check(zones[zone_name] != null, "%s first-read station exists" % zone_name)
	_check(logbook != null, "existing logbook remains the audit terminal")
	_check(watering_can != null and water_fern != null, "watering carry remains intact")
	if zones.values().has(null) or logbook == null or watering_can == null or water_fern == null:
		await _dispose(sequence)
		_finish()
		return

	_verify_playtime_contract(sequence)

	var initial: Dictionary = sequence.headless_get_state()
	_check(str(initial.get("current_step", "")) == "workspace", "first visit starts in workspace")
	_check(int(initial.get("care_context_count", -1)) == 0, "context starts at 0/8")
	_check(not bool(initial.get("care_context_ready", true)), "context starts incomplete")
	_check(not bool(logbook.get("interaction_enabled")), "locked logbook is not a silent proximity trigger")

	# Waiting and watering are prerequisites, never an autoplay substitute for reading.
	sequence.headless_advance(sequence.EXPLORE_MIN_TIME + 2.0, 0.1)
	sequence.set_preview_character_position("peris", watering_can.global_position)
	watering_can.call("_trigger", false)
	await process_frame
	sequence.set_preview_character_position("peris", water_fern.global_position)
	water_fern.call("_trigger", false)
	await process_frame
	var state: Dictionary = sequence.headless_get_state()
	_check(bool(state.get("plant_watered", false)), "watering still frees the hand slot")
	_check(int(state.get("care_context_count", -1)) == 0, "watering records no context read")
	_check(not bool(state.get("care_context_ready", true)), "waiting plus watering cannot open the audit")
	sequence.headless_advance(30.0, 0.1)
	_check(str(sequence._current_step) == "workspace", "no passive timer starts or clears the audit")

	# Every distinct plant group is a first-read record. Repeats are observable but
	# never replace another group; the three non-plant fixtures make eight records.
	var expected_count := 0
	for plant_zone_name in sequence.CARE_CONTEXT_PLANT_BRANCHES:
		await _trigger_and_finish(sequence, zones[str(plant_zone_name)])
		expected_count += 1
		state = sequence.headless_get_state()
		_check(int(state.get("care_context_count", -1)) == expected_count,
			"%s adds one distinct plant-group record" % plant_zone_name)
	await _trigger_and_finish(sequence, zones["PlantStandZone"])
	state = sequence.headless_get_state()
	_check(int(state.get("care_context_count", -1)) == 5, "re-reading a plant group cannot pad 5/5 plant progress")
	_check(int((state.get("care_context_zone_visits", {}) as Dictionary).get("PlantStandZone", 0)) == 2,
		"repeat plant reads remain observable")

	for fixture_name in ["PaintingZone", "WellnessZone", "StrikeWarningZone"]:
		await _trigger_and_finish(sequence, zones[fixture_name])
	state = sequence.headless_get_state()
	_check(int(state.get("care_context_count", -1)) == 8, "five plant groups plus three fixtures make 8/8")
	_check(bool(state.get("care_context_complete", false)), "headless state exposes the complete first read")
	_check(bool(state.get("care_context_ready", false)), "timer, watering, and 8/8 context open the audit")
	_check(not bool(state.get("explore_gate_unlocked", true)), "first read does not bypass the audit to Monos")
	_check(bool(logbook.get("interaction_enabled")), "completed first read enables the logbook")
	_check(int(logbook.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"audit logbook becomes click-gated timed work")
	_check(absf(float(logbook.get("dwell_time")) - sequence.CARE_AUDIT_WORK_SECONDS) <= EPSILON,
		"logbook work uses the measured sub-five-second duration")

	# Exercise the production click-arrival work path: it cannot fire before its
	# progress ring reaches the authored duration, then opens case 1 exactly once.
	logbook.call("on_interaction_arrived")
	sequence.headless_advance(sequence.CARE_AUDIT_WORK_SECONDS - 0.1, 0.1)
	_check(str(sequence._current_step) == "workspace", "logbook audit does not fire before work completes")
	sequence.headless_advance(0.2, 0.1)
	state = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "care_audit", "logbook opens the three-case audit")
	_check(int(state.get("care_audit_case_index", -1)) == 0, "audit starts at case zero")
	_check((state.get("care_audit_case_evidence", []) as Array).is_empty(), "case starts with no reviewed records")
	_verify_live_audit_interactables(sequence)
	var timed_fern: Node = sequence._care_audit_evidence_interactables["fern"]
	timed_fern.call("on_interaction_arrived")
	sequence.headless_advance(sequence.CARE_AUDIT_WORK_SECONDS - 0.1, 0.1)
	state = sequence.headless_get_state()
	_check(not (state.get("care_audit_case_evidence", []) as Array).has("fern"),
		"audit evidence does not register before timed work completes")
	sequence.headless_advance(0.2, 0.1)
	state = sequence.headless_get_state()
	_check((state.get("care_audit_case_evidence", []) as Array).has("fern"),
		"audit evidence registers through production arrival timing")

	# Review all eight priority records. Strike before wellness makes wellness the last priority
	# candidate and therefore selects the care-first branch at commit.
	var common_case: Dictionary = sequence._current_care_audit_case()
	var common_order := _candidate_last_order(common_case, "wellness")
	common_order.erase("fern")
	await _drive_audit_case(sequence, common_order)
	state = sequence.headless_get_state()
	_check(str(state.get("care_audit_selected_candidate", "")) == "wellness",
		"last common priority record is staged explicitly")
	_check(bool(logbook.get("interaction_enabled")), "eight priority records enable the case commit")
	sequence._on_care_audit_logbook_interacted()
	state = sequence.headless_get_state()
	_check(str(state.get("care_audit_branch", "")) == "care", "wellness priority selects care-first route")
	_check(int(state.get("care_audit_case_index", -1)) == 1, "commit advances to branch case two")
	var care_case_two_ids: Array = sequence._current_care_audit_case().get("evidence", [])
	_check(care_case_two_ids.has("stand") and care_case_two_ids.has("fern"),
		"care-first consequence changes the second evidence set")

	# Finish the two care-first cases. Each requires six fresh click-gated reviews.
	var care_final_ids: Array = []
	for case_number in [1, 2]:
		var case_data: Dictionary = sequence._current_care_audit_case()
		await _drive_audit_case(sequence, case_data.get("evidence", []) as Array)
		_check(sequence._care_audit_case_evidence_complete(), "case %d requires all six records" % (case_number + 1))
		sequence._on_care_audit_logbook_interacted()
		if case_number == 1:
			state = sequence.headless_get_state()
			care_final_ids = sequence._current_care_audit_case().get("evidence", [])
			_check(str(state.get("care_audit_secondary_route", "")) == "coffee",
				"second decision selects the client-memory final route")
			_check(care_final_ids == (sequence.CARE_AUDIT_FINAL_CASES["coffee"] as Dictionary).get("evidence", []),
				"second decision changes the third mandatory evidence set")
	state = sequence.headless_get_state()
	_check(bool(state.get("care_audit_complete", false)), "three committed cases close the audit")
	_check(int((state.get("care_audit_commit_history", []) as Array).size()) == 3, "three decisions are recorded")
	_check(str(state.get("care_audit_outcome", "")) == "strike",
		"third decision changes the recorded final disposition")
	_check(int(_sum_counts(state.get("care_audit_review_counts", {}) as Dictionary)) == 20,
		"shortest valid audit performs twenty evidence reviews")
	_check(bool(state.get("explore_gate_unlocked", false)), "closed audit releases the story gate")

	# Closing the third case is not the story handoff. The next clicked logbook
	# beat opens the active care plan; it does not skip directly to Monos.
	sequence.headless_advance(8.0, 0.1)
	_check(str(sequence._current_step) == "care_audit", "closed audit waits for explicit care-plan handoff")
	logbook.call("on_interaction_arrived")
	sequence.headless_advance(sequence.CARE_AUDIT_WORK_SECONDS - 0.1, 0.1)
	_check(str(sequence._current_step) == "care_audit", "care-plan handoff waits for its clicked work beat")
	sequence.headless_advance(0.2, 0.1)
	state = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "care_operations", "audit hands off to executable care operations")
	_check(str(state.get("care_operation_stage", "")) == "collect_kit", "operations begin by collecting real inventory")
	await _verify_and_drive_care_operations(sequence, logbook)
	_check(str(sequence._current_step) == "monos_breakthrough", "completed operations and final release hand off to Monos")

	await _dispose(sequence)
	await _verify_compliance_branch(care_case_two_ids)
	_finish()


func _verify_playtime_contract(sequence: Node) -> void:
	var contract: Dictionary = sequence.get_playtime_contract()
	var context_route := _independent_context_route_meters(sequence)
	var care_route := _independent_audit_route_meters(sequence, "care")
	var compliance_route := _independent_audit_route_meters(sequence, "compliance")
	var shortest_audit_route := minf(care_route, compliance_route)
	var operation_route := _independent_operation_route_meters(sequence)
	var story_dialogue := _independent_dialogue_seconds(sequence.CARE_AUDIT_STORY_DIALOGUE_KEYS, sequence)
	var context_dialogue := _independent_dialogue_seconds(sequence.CARE_AUDIT_CONTEXT_DIALOGUE_KEYS, sequence)
	var fixed_components: Dictionary = contract.get("fixed_presentation_components", {})
	var fixed_seconds := 0.0
	for raw_seconds in fixed_components.values():
		fixed_seconds += float(raw_seconds)
	var station_work_seconds := (
		int(contract.get("mandatory_audit_evidence_reviews", 0))
		+ int(contract.get("mandatory_operation_task_reviews", 0))
		+ int(contract.get("mandatory_operation_resolution_actions", 0))
		+ int(contract.get("mandatory_logbook_actions", 0))
	) * float(contract.get("operation_work_seconds_each", 0.0))
	var inventory_work_seconds := float(contract.get("mandatory_inventory_work_seconds", 0.0))
	var speed := float(contract.get("movement_speed_meters_per_second", 0.0))
	var independent_active := station_work_seconds + inventory_work_seconds \
		+ (context_route + shortest_audit_route + operation_route) / speed
	var independently_modeled := fixed_seconds + story_dialogue + context_dialogue + independent_active

	_check(float(contract.get("target_min_seconds", 0.0)) == 300.0, "planning floor is five minutes")
	_check(float(contract.get("target_max_seconds", 0.0)) == 480.0, "planning ceiling is eight minutes")
	_check(float(contract.get("meaningful_active_seconds", 0.0)) >= 300.0,
		"conservative shortest route reaches five active minutes (%.1fs)" % float(contract.get("meaningful_active_seconds", 0.0)))
	_check(float(contract.get("meaningful_active_seconds", 9999.0)) <= 480.0,
		"meaningful active play stays inside the eight-minute planning ceiling")
	_check(float(contract.get("active_ratio", 0.0)) >= 0.70,
		"modeled total remains at least seventy percent active")
	_check(not contract.has("care_context_modeled_seconds"), "old circular 110-second estimate is removed")
	_check(int(contract.get("mandatory_audit_evidence_reviews", 0)) == 20,
		"priority reviews eight records; two branch cases review six each")
	_check(int(contract.get("mandatory_operation_task_reviews", 0)) == 32,
		"four phases contribute thirty-two distinct care jobs")
	_check(int(contract.get("mandatory_operation_resolution_actions", 0)) == 4,
		"each planning choice adds one selected physical resolution")
	_check(int(contract.get("mandatory_logbook_actions", 0)) == 10,
		"audit, plan commits, handoff, and final release are explicit logbook work")
	_check(float(contract.get("audit_work_seconds_each", 99.0)) < 5.0,
		"each scheduler-backed work beat stays below five seconds")
	_check(float(contract.get("maximum_authored_dead_gap_seconds", 99.0)) < 5.0,
		"authored dead-gap ceiling is below five seconds")
	_check(int(contract.get("decision_count", 0)) == 7, "audit and operations record seven decisions")
	_check(int(contract.get("branch_count", 0)) == 12, "audit paths and eight operation resolutions are consequential")
	_check(absf(float(contract.get("modeled_meaningful_active_seconds", 0.0)) - independent_active) <= EPSILON,
		"active seconds recompute from timed jobs, inventory, and constrained routes")
	_check(context_route > 35.0 and shortest_audit_route > 79.0,
		"live-marker route minima require substantial traversal")
	_check(absf(float(contract.get("mandatory_watering_inventory_seconds", 0.0)) \
			- (float(sequence._can_pickup_interactable.get("dwell_time")) \
			+ float(sequence._water_plant_interactable.get("dwell_time")))) <= EPSILON,
		"watering work derives from the two live interactable dwells")
	_check(int(contract.get("mandatory_care_kit_actions", 0)) == 2,
		"field-kit pickup and return are counted once each")
	_check(absf(float(contract.get("minimum_context_route_meters", 0.0)) - context_route) <= EPSILON,
		"contract context route matches an independent live-node TSP")
	_check(absf(float(contract.get("care_branch_route_meters", 0.0)) - care_route) <= EPSILON,
		"care-first route matches independent branch computation")
	_check(absf(float(contract.get("compliance_branch_route_meters", 0.0)) - compliance_route) <= EPSILON,
		"compliance-first route matches independent branch computation")
	_check(absf(float(contract.get("minimum_operation_route_meters", 0.0)) - operation_route) <= EPSILON,
		"four operation circuits match independent branch-constrained TSPs")
	_check(absf(float(contract.get("modeled_story_dialogue_seconds", 0.0)) - story_dialogue) <= EPSILON,
		"story reading time derives from live authored dialogue")
	_check(absf(float(contract.get("modeled_context_dialogue_seconds", 0.0)) - context_dialogue) <= EPSILON,
		"context reading time derives from live authored dialogue")
	_check(absf(float(contract.get("authored_fixed_presentation_seconds", 0.0)) - fixed_seconds) <= EPSILON,
		"fixed time is the sum of named authored transitions")
	_check(absf(float(contract.get("modeled_first_clear_seconds", 0.0)) - independently_modeled) <= EPSILON,
		"first-clear total recomputes from dialogue, named transitions, work, and routes")
	_verify_canonical_contract(contract)
	print("[MODEL] Peris shortest first clear %.1fs; active %.1fs; ratio %.1f%%; routes %.1fm context + %.1fm audit + %.1fm operations" % [
		float(contract.get("modeled_first_clear_seconds", 0.0)),
		float(contract.get("modeled_meaningful_active_seconds", 0.0)),
		float(contract.get("active_ratio", 0.0)) * 100.0,
		context_route,
		shortest_audit_route,
		operation_route,
	])


func _verify_canonical_contract(contract: Dictionary) -> void:
	var manifest_text := FileAccess.get_file_as_string("res://data/pacing/level_targets.json")
	var parsed = JSON.parse_string(manifest_text)
	_check(parsed is Dictionary, "canonical pacing manifest parses")
	if not parsed is Dictionary:
		return
	var manifest: Dictionary = parsed
	var target := LevelPacingContract.target_by_id(manifest, "peris_sim")
	_check(not target.is_empty(), "canonical manifest contains Peris's planning band")
	if target.is_empty():
		return
	var metrics := {
		"meaningful_active_seconds": float(contract.get("meaningful_active_seconds", 0.0)),
		"total_play_seconds": float(contract.get("total_play_seconds", 0.0)),
		"active_ratio": float(contract.get("active_ratio", 0.0)),
		"max_dead_gap_seconds": float(contract.get("max_dead_gap_seconds", 0.0)),
		"max_single_mode_seconds": float(contract.get("max_single_mode_seconds", 0.0)),
		"decision_count": int(contract.get("decision_count", 0)),
		"branch_count": int(contract.get("branch_count", 0)),
		"category_seconds": (contract.get("category_seconds", {}) as Dictionary).duplicate(true),
	}
	var report := LevelPacingContract.analyze(target, metrics, manifest.get("rules", {}) as Dictionary)
	if not bool(report.get("passed", false)):
		for raw_issue in (report.get("errors", []) as Array):
			var issue: Dictionary = raw_issue
			push_error("[CANONICAL] %s: %s" % [str(issue.get("code", "error")), str(issue.get("message", ""))])
	_check(bool(report.get("passed", false)), "LevelPacingContract accepts Peris's conservative active model")


func _verify_live_audit_interactables(sequence: Node) -> void:
	_check(sequence._care_audit_evidence_interactables.size() == 8, "eight existing visible records back the audit")
	for evidence_id in sequence._care_audit_evidence_interactables:
		var evidence: Node = sequence._care_audit_evidence_interactables[evidence_id]
		_check(int(evidence.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
			"%s is click-gated timed work" % evidence_id)
		_check(absf(float(evidence.get("dwell_time")) - sequence.CARE_AUDIT_WORK_SECONDS) <= EPSILON,
			"%s uses the measured work duration" % evidence_id)
		_check(str(evidence.get("required_character")) == "peris", "%s requires Peris" % evidence_id)
		var config: Dictionary = sequence.CARE_AUDIT_EVIDENCE_SOURCES[evidence_id]
		var source: Node = sequence.find_child(str(config.get("zone", "")), true, false)
		if source != null and source.has_meta("interaction_target_position"):
			_check(evidence.has_meta("interaction_target_position") \
					and evidence.get_meta("interaction_target_position") == source.get_meta("interaction_target_position"),
				"%s preserves its authoritative approach point" % evidence_id)


func _verify_and_drive_care_operations(sequence: Node, logbook: Node) -> void:
	var kit: Node = sequence.find_child("CareKitPickup", true, false)
	_check(kit != null, "care plan exposes a visible field-kit pickup")
	if kit == null:
		return
	_check(int(kit.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"field kit is click-gated carried inventory work")
	_check(str(kit.get("required_character")) == "peris", "only Peris can take her care kit")
	sequence.set_preview_character_position("peris", (kit as Node3D).global_position)
	kit.call("on_interaction_arrived")
	sequence.headless_advance(sequence.CARE_OPERATION_WORK_SECONDS - 0.1, 0.1)
	_check(str(sequence._care_operation_stage) == "collect_kit", "field kit cannot be collected before work completes")
	sequence.headless_advance(0.2, 0.1)
	var state: Dictionary = sequence.headless_get_state()
	_check(bool(state.get("care_kit_held", false)), "completed pickup occupies Peris's real hand inventory")
	_check(str(state.get("care_operation_stage", "")) == "work", "kit pickup arms the first operation")
	_check(sequence._care_operation_interactables.size() == 32, "four operations expose thirty-two unique task ids")

	var seen_task_ids: Dictionary = {}
	for raw_phase in sequence.CARE_OPERATION_PHASES:
		for raw_task in ((raw_phase as Dictionary).get("tasks", []) as Array):
			var task: Dictionary = raw_task
			var task_id := str(task.get("id", ""))
			_check(not seen_task_ids.has(task_id), "%s is a non-repeated care verb" % task_id)
			seen_task_ids[task_id] = true
			var task_interactable: Node = sequence._care_operation_interactables.get(task_id)
			_check(task_interactable != null, "%s has a live normal-input interactable" % task_id)
			if task_interactable != null:
				_check(int(task_interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
					"%s is click-gated work" % task_id)
				_check(str(task_interactable.get("required_character")) == "peris", "%s requires Peris" % task_id)

	for phase_index in range(sequence.CARE_OPERATION_PHASES.size()):
		var phase: Dictionary = sequence.CARE_OPERATION_PHASES[phase_index]
		state = sequence.headless_get_state()
		_check(int(state.get("care_operation_phase_index", -1)) == phase_index,
			"operation %d begins in authored order" % (phase_index + 1))
		var candidates: Array = phase.get("candidates", [])
		var selected := str(candidates[phase_index % candidates.size()])
		var order := _operation_candidate_last_order(phase, selected)
		for order_index in range(order.size()):
			var task_id := str(order[order_index])
			if phase_index == 0 and order_index == 0:
				var timed_task: Node = sequence._care_operation_interactables[task_id]
				sequence.set_preview_character_position("peris", (timed_task as Node3D).global_position)
				timed_task.call("on_interaction_arrived")
				sequence.headless_advance(sequence.CARE_OPERATION_WORK_SECONDS - 0.1, 0.1)
				state = sequence.headless_get_state()
				_check(not (state.get("care_operation_completed_tasks", []) as Array).has(task_id),
					"operation task cannot register before its progress ring completes")
				sequence.headless_advance(0.2, 0.1)
			else:
				sequence._on_care_operation_task_completed(task_id)
			await process_frame
		state = sequence.headless_get_state()
		_check(str(state.get("care_operation_stage", "")) == "resolution",
			"eight distinct jobs open one branch-specific resolution")
		_check(str(state.get("care_operation_selected_candidate", "")) == selected,
			"last policy job selects operation %d's route" % (phase_index + 1))
		var expected_resolution: Dictionary = (phase.get("resolutions", {}) as Dictionary)[selected]
		var resolution: Node = sequence._care_operation_resolution_interactable
		_check(resolution != null and str(resolution.get_meta("care_operation_resolution_id", "")) \
				== str(expected_resolution.get("id", "")),
			"operation %d builds the selected physical resolution" % (phase_index + 1))
		if resolution == null:
			return
		if phase_index == 0:
			sequence.set_preview_character_position("peris", (resolution as Node3D).global_position)
			resolution.call("on_interaction_arrived")
			sequence.headless_advance(sequence.CARE_OPERATION_WORK_SECONDS - 0.1, 0.1)
			_check(str(sequence._care_operation_stage) == "resolution",
				"resolution cannot commit before timed work completes")
			sequence.headless_advance(0.2, 0.1)
		else:
			sequence._on_care_operation_resolution_completed(str(expected_resolution.get("id", "")))
		state = sequence.headless_get_state()
		_check(str(state.get("care_operation_stage", "")) == "commit",
			"resolved operation returns to the logbook")
		_check(bool(logbook.get("interaction_enabled")), "resolved operation enables a clicked commit")
		sequence._on_care_operation_logbook_interacted()
		await process_frame

	state = sequence.headless_get_state()
	_check(bool(state.get("care_operations_complete", false)), "four operation commits complete the care plan")
	_check(int((state.get("care_operation_decisions", []) as Array).size()) == 4,
		"each operation records its consequential resolution")
	_check(str(state.get("care_operation_stage", "")) == "return_kit",
		"completed work still requires returning carried inventory")
	sequence._on_care_operation_logbook_interacted()
	state = sequence.headless_get_state()
	_check(bool(state.get("care_kit_returned", false)) and not bool(state.get("care_kit_held", true)),
		"logbook return frees Peris's real hand slot")
	_check(str(state.get("care_operation_stage", "")) == "release",
		"returned kit exposes a separate final release")
	sequence.headless_advance(8.0, 0.1)
	_check(str(sequence._current_step) == "care_operations", "scheduler time cannot release the connection")
	sequence.set_preview_character_position("peris", (logbook as Node3D).global_position)
	logbook.call("on_interaction_arrived")
	sequence.headless_advance(sequence.CARE_OPERATION_WORK_SECONDS - 0.1, 0.1)
	_check(str(sequence._current_step) == "care_operations", "final release remains click-gated timed work")
	sequence.headless_advance(0.2, 0.1)


func _operation_candidate_last_order(phase: Dictionary, selected: String) -> Array:
	var order: Array = []
	var candidates: Array = phase.get("candidates", [])
	for raw_task in (phase.get("tasks", []) as Array):
		var task_id := str((raw_task as Dictionary).get("id", ""))
		if task_id != selected and not candidates.has(task_id):
			order.append(task_id)
	for raw_candidate in candidates:
		if str(raw_candidate) != selected:
			order.append(str(raw_candidate))
	order.append(selected)
	return order


func _verify_compliance_branch(care_case_two_ids: Array) -> void:
	var sequence := await _make_sequence()
	if sequence == null:
		return
	sequence._plant_watered = true
	sequence._explore_time_elapsed = true
	for branch_id in sequence.CARE_CONTEXT_PLANT_BRANCHES:
		sequence._on_care_context_zone_interacted("plant", str(branch_id))
	for category in ["painting", "wellness", "strike_warning"]:
		sequence._on_care_context_zone_interacted(category, category)
	sequence._maybe_unlock_exploration_gate()
	sequence._on_exploration_gate_interacted()
	var common_case: Dictionary = sequence._current_care_audit_case()
	await _drive_audit_case(sequence, _candidate_last_order(common_case, "strike"))
	sequence._on_care_audit_logbook_interacted()
	var state: Dictionary = sequence.headless_get_state()
	_check(str(state.get("care_audit_branch", "")) == "compliance", "strike priority selects compliance-first route")
	var compliance_case_two_ids: Array = sequence._current_care_audit_case().get("evidence", [])
	_check(compliance_case_two_ids != care_case_two_ids, "first decision changes later mandatory evidence")
	_check(compliance_case_two_ids.has("strike") and compliance_case_two_ids.has("wellness"),
		"compliance-first second case exposes its authored evidence set")
	await _dispose(sequence)


func _make_sequence() -> Node:
	var sequence: Node = PERIS_SCENE.instantiate()
	sequence.set("suppress_scene_change", true)
	sequence.set("start_phase", 1)
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	sequence._scheduler.clear()
	sequence._ui_scheduler.clear()
	sequence._start_workspace()
	await process_frame
	return sequence


func _drive_audit_case(sequence: Node, order: Array) -> void:
	for raw_id in order:
		sequence._on_care_audit_evidence_reviewed(str(raw_id))
		await process_frame


func _candidate_last_order(case_data: Dictionary, selected: String) -> Array:
	var order: Array = []
	var candidates: Array = case_data.get("candidates", [])
	for raw_id in (case_data.get("evidence", []) as Array):
		if str(raw_id) != selected and not candidates.has(str(raw_id)):
			order.append(str(raw_id))
	for raw_candidate in candidates:
		if str(raw_candidate) != selected:
			order.append(str(raw_candidate))
	order.append(selected)
	return order


func _trigger_and_finish(sequence: Node, zone: Node) -> void:
	zone.call("_trigger", false)
	await process_frame
	sequence._dialogue.clear()
	sequence._dialogue.dialogue_finished.emit()
	await process_frame


func _sum_counts(counts: Dictionary) -> int:
	var total := 0
	for raw_count in counts.values():
		total += int(raw_count)
	return total


func _independent_dialogue_seconds(keys: Array, sequence: Node) -> float:
	var characters := 0
	var count := 0
	for raw_key in keys:
		var line := DialogueData.get_line(str(raw_key))
		if line.text == "" or line.text.begins_with("[MISSING:"):
			continue
		characters += line.text.length()
		count += 1
	return characters / float(sequence.CARE_AUDIT_DIALOGUE_CPS) \
		+ count * float(sequence.CARE_AUDIT_RESPONSE_SECONDS_PER_LINE)


func _independent_context_route_meters(sequence: Node) -> float:
	var start: Vector3 = sequence._player.global_position
	var can: Vector3 = sequence.find_child("WateringCanPickup", true, false).global_position
	var fern := _source_position(sequence, "fern")
	var logbook: Vector3 = sequence.find_child("LogbookGate", true, false).global_position
	var remaining := ["bookshelf", "stand", "coffee", "peace", "painting", "wellness", "strike"]
	return _horizontal(start, can) + _horizontal(can, fern) \
		+ _independent_minimum_route(sequence, fern, logbook, remaining)


func _independent_audit_route_meters(sequence: Node, branch: String) -> float:
	var continuity: Dictionary = sequence.CARE_AUDIT_BRANCH_CASES[branch]
	var primary := "wellness" if branch == "care" else "strike"
	var common_distance := _independent_case_route_meters(sequence, sequence.CARE_AUDIT_COMMON_CASE, primary)
	var best := INF
	for raw_secondary in (continuity.get("candidates", []) as Array):
		var secondary := str(raw_secondary)
		var final_case: Dictionary = sequence.CARE_AUDIT_FINAL_CASES[secondary]
		var distance := common_distance \
			+ _independent_case_route_meters(sequence, continuity, secondary) \
			+ _independent_case_route_meters(sequence, final_case, "")
		best = minf(best, distance)
	return best


func _independent_operation_route_meters(sequence: Node) -> float:
	var total := 0.0
	var logbook: Vector3 = sequence.find_child("LogbookGate", true, false).global_position
	for raw_phase in sequence.CARE_OPERATION_PHASES:
		var phase: Dictionary = raw_phase
		var source_ids: Array = []
		var task_sources: Dictionary = {}
		for raw_task in (phase.get("tasks", []) as Array):
			var task: Dictionary = raw_task
			var task_id := str(task.get("id", ""))
			var source_id := str(task.get("source", ""))
			task_sources[task_id] = source_id
			source_ids.append(source_id)
		var candidates: Array = phase.get("candidates", [])
		var resolutions: Dictionary = phase.get("resolutions", {})
		var best := INF
		for raw_selected in candidates:
			var selected := str(raw_selected)
			var other := ""
			for raw_candidate in candidates:
				if str(raw_candidate) != selected:
					other = str(raw_candidate)
					break
			var resolution: Dictionary = resolutions[selected]
			var resolution_source := str(resolution.get("source", ""))
			var resolution_position := _source_position(sequence, resolution_source)
			var distance := _independent_minimum_route(
				sequence,
				logbook,
				resolution_position,
				source_ids,
				str(task_sources.get(selected, "")),
				str(task_sources.get(other, ""))
			) + _horizontal(resolution_position, logbook)
			best = minf(best, distance)
		total += best
	return total


func _independent_case_route_meters(sequence: Node, case_data: Dictionary, selected: String) -> float:
	var logbook: Vector3 = sequence.find_child("LogbookGate", true, false).global_position
	var candidates: Array = case_data.get("candidates", [])
	var other := ""
	if selected != "":
		for raw_candidate in candidates:
			if str(raw_candidate) != selected:
				other = str(raw_candidate)
				break
	return _independent_minimum_route(
		sequence,
		logbook,
		logbook,
		case_data.get("evidence", []) as Array,
		selected,
		other
	)


func _source_position(sequence: Node, evidence_id: String) -> Vector3:
	var config: Dictionary = sequence.CARE_AUDIT_EVIDENCE_SOURCES[evidence_id]
	var source := sequence.find_child(str(config.get("zone", "")), true, false) as Node3D
	if source.has_meta("interaction_target_position"):
		var target = source.get_meta("interaction_target_position")
		if target is Vector3:
			return target
	return source.global_position


func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _independent_minimum_route(
	sequence: Node,
	start: Vector3,
	finish: Vector3,
	ids: Array,
	selected := "",
	other := ""
) -> float:
	if ids.is_empty():
		return _horizontal(start, finish)
	var points: Array[Vector3] = []
	for raw_id in ids:
		points.append(_source_position(sequence, str(raw_id)))
	var selected_index := ids.find(selected) if selected != "" else -1
	var other_index := ids.find(other) if other != "" else -1
	var full_mask := (1 << ids.size()) - 1
	var costs: Dictionary = {}
	for index in range(ids.size()):
		if index == selected_index and other_index >= 0:
			continue
		costs[((1 << index) << 5) | index] = _horizontal(start, points[index])
	for mask in range(1, full_mask + 1):
		for last in range(ids.size()):
			var key := (mask << 5) | last
			if not costs.has(key):
				continue
			var current := float(costs[key])
			for next in range(ids.size()):
				var bit := 1 << next
				if (mask & bit) != 0:
					continue
				if next == selected_index and other_index >= 0 and (mask & (1 << other_index)) == 0:
					continue
				var next_mask := mask | bit
				var next_key := (next_mask << 5) | next
				var candidate := current + _horizontal(points[last], points[next])
				if not costs.has(next_key) or candidate < float(costs[next_key]):
					costs[next_key] = candidate
	var best := INF
	for last in range(ids.size()):
		var key := (full_mask << 5) | last
		if costs.has(key):
			best = minf(best, float(costs[key]) + _horizontal(points[last], finish))
	return best


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.queue_free()
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	_failures.append(message)
	push_error("[FAIL] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nPERIS CARE-AUDIT PACING: PASS")
		quit(0)
	else:
		push_error("\nPERIS CARE-AUDIT PACING: FAIL (%d checks)" % _failures.size())
		quit(1)
