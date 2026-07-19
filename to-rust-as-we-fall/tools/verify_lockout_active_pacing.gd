extends SceneTree

## Focused Lockout structure, pair-gate, branch-persistence, decoration, and canonical pacing audit.
## Run with:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_lockout_active_pacing.gd

const PacingContract := preload("res://scripts/generation/level_pacing_contract.gd")
const EPSILON := 0.01

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
	_check(packed != null, "the shared fragment preview scene loads")
	if packed == null:
		_finish()
		return
	var preview: Node = packed.instantiate()
	preview.set("preview_menu", false)
	preview.set("preview_chunk", "lockout_chase")
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	var chunk: Node = preview.get("_active_chunk")
	_check(chunk != null, "the Lockout chase builds in the real playable preview host")
	if chunk == null:
		await _dispose(preview)
		_finish()
		return

	_verify_structure(chunk)
	_verify_pacing(chunk)
	_verify_normal_input_state_machine(preview, chunk)

	await _dispose(preview)
	_finish()


func _verify_structure(chunk: Node) -> void:
	print("\n=== Lockout live-sector structure and decoration ===")
	var interactables := chunk.find_children("LockoutRally_*", "Interactable", true, false)
	_check(interactables.size() == 56,
		"four sectors author 56 real nodes: 4 entry, 24 specialist, 8 choices, 16 branch, and 4 commit")
	var kind_counts := {
		"entry": 0,
		"specialist_work": 0,
		"strategy_choice": 0,
		"branch_execution": 0,
		"commit": 0,
	}
	var role_counts := {"aster": 0, "peris": 0}
	var timed_count := 0
	var outlined_count := 0
	for interactable in interactables:
		var kind := str(interactable.get_meta("rally_kind", ""))
		if kind_counts.has(kind):
			kind_counts[kind] += 1
		var role := str(interactable.get("required_character"))
		if role_counts.has(role):
			role_counts[role] += 1
		if int(interactable.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed_count += 1
		if interactable.get("_outline_target") != null:
			outlined_count += 1
		_check(absf(float(interactable.get("dwell_time")) - float(chunk.LOCKOUT_RALLY_WORK_SECONDS)) <= EPSILON,
			"%s uses the standardized 4.8-second work dwell" % str(interactable.name))
	_check(int(kind_counts["entry"]) == 4 and int(kind_counts["specialist_work"]) == 24
		and int(kind_counts["strategy_choice"]) == 8 and int(kind_counts["branch_execution"]) == 16
		and int(kind_counts["commit"]) == 4,
		"node metadata distinguishes pair latches, role work, decisions, executions, and commits")
	_check(timed_count == 56, "every sector verb is a normal click-gated TIMED_ACTION")
	_check(outlined_count == 56, "every visible sector apparatus binds object outline feedback")
	_check(int(role_counts["aster"]) == 32 and int(role_counts["peris"]) == 24,
		"both Aster and Peris own substantive required-character work")
	_check(chunk.find_children("LockoutRallyFrame_*", "Node3D", true, false).size() == 4,
		"four measured structural rally frames divide the corridor")
	_check(chunk.find_children("LockoutRallyLight_*", "OmniLight3D", true, false).size() == 4,
		"each rally bay has a WebGL-safe authored landmark light")

	var audit: Dictionary = chunk.call("get_decoration_audit")
	_check(chunk.find_child("LevelDecoration", true, false) != null and not audit.is_empty(),
		"Lockout uses the shared building-quality deterministic decoration pass")
	_check(str(audit.get("contract_id", "")) == "authored_level_decoration_v1"
		and str(audit.get("program", "")) == "boundary",
		"decoration keeps the institutional boundary grammar")
	_check(int(audit.get("stations", 0)) >= 20 and int(audit.get("instances", 0)) >= 300,
		"the 220-meter corridor receives a dense structural facade hierarchy")
	_check(int(audit.get("collision_shapes", -1)) == 0
		and str(audit.get("clearance", "")) == "surface_only_no_obstacles",
		"decoration cannot alter the chase grid, pair route, or interactions")


func _verify_pacing(chunk: Node) -> void:
	print("\n=== Lockout canonical active pacing ===")
	var contract: Dictionary = chunk.call("get_playtime_contract")
	var stage_count := (chunk.LOCKOUT_RALLY_STAGES as Array).size()
	var independently_added := float(stage_count) * (
		float(chunk.LOCKOUT_RALLY_LIVE_SECONDS) + 2.0 * float(chunk.LOCKOUT_RALLY_WORK_SECONDS))
	var independently_active := float(chunk.LOCKOUT_EXISTING_ACTIVE_SECONDS) + independently_added
	var independently_total := float(chunk.LOCKOUT_EXISTING_TOTAL_SECONDS) + independently_added \
		- float(chunk.LOCKOUT_OVERLAPPED_PRESENTATION_SECONDS)
	var independent_route := _independent_shortest_routes(chunk)

	_check(absf(float(chunk.LOCKOUT_RALLY_STAGE_FLOOR_SECONDS)
		- (float(chunk.LOCKOUT_RALLY_LIVE_SECONDS) + 2.0 * float(chunk.LOCKOUT_RALLY_WORK_SECONDS))) <= EPSILON,
		"each 90.5-second floor derives from entry, live pursuit, and commit")
	_check(absf(float(contract.get("meaningful_active_seconds", 0.0)) - independently_active) <= EPSILON,
		"active time independently recomputes to %.1f seconds" % independently_active)
	_check(absf(float(contract.get("total_play_seconds", 0.0)) - independently_total) <= EPSILON,
		"elapsed time independently recomputes to %.1f seconds after real presentation overlap" % independently_total)
	_check(float(contract.get("meaningful_active_seconds", 0.0)) >= 300.0
		and float(contract.get("meaningful_active_seconds", 9999.0)) <= 480.0,
		"meaningful-active play stays inside the canonical five-to-eight-minute band")
	_check(float(contract.get("active_ratio", 0.0)) >= 0.705,
		"active ratio has useful safety margin above seventy percent (%.2f%%)" % (
			float(contract.get("active_ratio", 0.0)) * 100.0))
	_check(absf(float(contract.get("shortest_rally_route_meters", 0.0))
		- float(independent_route.get("meters", 0.0))) <= EPSILON,
		"the contract's local movement uses an independent branch-constrained shortest-route search")
	_check(absf(float(contract.get("shortest_rally_route_seconds", 0.0))
		- float(independent_route.get("seconds", 0.0))) <= EPSILON,
		"route seconds derive from live geometry and the authored run speed")
	_check(int(contract.get("mandatory_pair_checks", 0)) == 44,
		"the successful route checks pair presence at every one of its forty-four actions")
	_check(int(contract.get("mandatory_specialist_actions", 0)) == 24
		and int(contract.get("mandatory_strategy_choices", 0)) == 4
		and int(contract.get("mandatory_branch_actions", 0)) == 8,
		"new active time comes from distinct specialist work and persistent branch execution")
	_check(int(contract.get("decision_count", 0)) == 5 and int(contract.get("branch_count", 0)) == 10,
		"four spatial rally choices plus Tyreg clear the canonical decision and branch minima")
	_check(float(contract.get("hard_idle_lock_seconds", -1.0)) == 0.0,
		"no passive timer lock contributes to the duration claim")

	var categories: Dictionary = contract.get("category_seconds", {})
	var category_total := 0.0
	var largest_category := 0.0
	for seconds_variant in categories.values():
		var seconds := float(seconds_variant)
		category_total += seconds
		largest_category = maxf(largest_category, seconds)
	_check(absf(category_total - independently_active) <= 0.02,
		"mutually exclusive active categories sum to the active model")
	_check(largest_category <= 150.0,
		"no repeated activity category exceeds the canonical 150-second cap (largest %.1fs)" % largest_category)

	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/pacing/level_targets.json"))
	_check(parsed is Dictionary, "canonical pacing manifest parses")
	if parsed is Dictionary:
		var manifest: Dictionary = parsed
		var target := PacingContract.target_by_id(manifest, "lockout")
		var report := PacingContract.analyze(target, {
			"meaningful_active_seconds": float(contract.get("meaningful_active_seconds", 0.0)),
			"total_play_seconds": float(contract.get("total_play_seconds", 0.0)),
			"active_ratio": float(contract.get("active_ratio", 0.0)),
			"max_dead_gap_seconds": float(contract.get("max_dead_gap_seconds", 0.0)),
			"max_single_mode_seconds": float(contract.get("max_single_mode_seconds", 0.0)),
			"decision_count": int(contract.get("decision_count", 0)),
			"branch_count": int(contract.get("branch_count", 0)),
			"category_seconds": categories.duplicate(true),
		}, manifest.get("rules", {}) as Dictionary)
		if not bool(report.get("passed", false)):
			for issue_variant in (report.get("errors", []) as Array):
				var issue: Dictionary = issue_variant
				push_error("[CANONICAL] %s: %s" % [str(issue.get("code", "error")), str(issue.get("message", ""))])
		_check(bool(report.get("passed", false)),
			"LevelPacingContract.analyze accepts the exact Lockout metrics")
	print("  INFO: active %.1fs / total %.1fs = %.2f%%; route %.1fm; largest category %.1fs" % [
		float(contract.get("meaningful_active_seconds", 0.0)),
		float(contract.get("total_play_seconds", 0.0)),
		float(contract.get("active_ratio", 0.0)) * 100.0,
		float(contract.get("shortest_rally_route_meters", 0.0)),
		largest_category,
	])


func _independent_shortest_routes(chunk: Node) -> Dictionary:
	var total_meters := 0.0
	for stage_variant in (chunk.LOCKOUT_RALLY_STAGES as Array):
		var stage: Dictionary = stage_variant
		var center: Vector3 = stage.get("center", Vector3.ZERO)
		var start := center + Vector3(-4.2, 0.0, 0.0)
		var finish := center + Vector3(4.2, 0.0, 0.0)
		var best_strategy_meters := INF
		for strategy_variant in (stage.get("strategies", []) as Array):
			var strategy: Dictionary = strategy_variant
			var role_points := {"aster": [], "peris": []}
			for action_variant in (stage.get("common", []) as Array):
				var action: Dictionary = action_variant
				var role := str(action.get("role", ""))
				(role_points[role] as Array).append(center + (action.get("offset", Vector3.ZERO) as Vector3))
			var choice_role := str(strategy.get("role", "aster"))
			(role_points[choice_role] as Array).append(center + (strategy.get("offset", Vector3.ZERO) as Vector3))
			for execution_variant in (strategy.get("executions", []) as Array):
				var execution: Dictionary = execution_variant
				var role := str(execution.get("role", ""))
				(role_points[role] as Array).append(center + (execution.get("offset", Vector3.ZERO) as Vector3))
			var strategy_meters := _shortest_path(start, finish, role_points["aster"] as Array) \
				+ _shortest_path(start, finish, role_points["peris"] as Array)
			best_strategy_meters = minf(best_strategy_meters, strategy_meters)
		total_meters += best_strategy_meters
	return {
		"meters": total_meters,
		"seconds": total_meters / float(chunk.LOCKOUT_RALLY_RUN_SPEED),
	}


func _shortest_path(start: Vector3, finish: Vector3, points: Array) -> float:
	if points.is_empty():
		return start.distance_to(finish)
	var all_mask := (1 << points.size()) - 1
	var distance_by_state := {}
	for point_index in range(points.size()):
		distance_by_state[Vector2i(1 << point_index, point_index)] = start.distance_to(points[point_index] as Vector3)
	for mask in range(1, all_mask + 1):
		for last_index in range(points.size()):
			var key := Vector2i(mask, last_index)
			if not distance_by_state.has(key):
				continue
			for next_index in range(points.size()):
				var bit := 1 << next_index
				if mask & bit:
					continue
				var next_key := Vector2i(mask | bit, next_index)
				var candidate := float(distance_by_state[key]) \
					+ (points[last_index] as Vector3).distance_to(points[next_index] as Vector3)
				if candidate < float(distance_by_state.get(next_key, INF)):
					distance_by_state[next_key] = candidate
	var best := INF
	for last_index in range(points.size()):
		var key := Vector2i(all_mask, last_index)
		best = minf(best, float(distance_by_state.get(key, INF))
			+ (points[last_index] as Vector3).distance_to(finish))
	return best


func _verify_normal_input_state_machine(preview: Node, chunk: Node) -> void:
	print("\n=== Lockout normal-input and pair-state gates ===")
	chunk.call("set_pursuit_start_deferred", true)
	var scanner: Node = chunk.find_child("BoundaryScanner", true, false)
	preview.call("headless_select_character", "aster")
	scanner.call("_trigger", false)
	_check(bool((chunk.call("get_preview_state") as Dictionary).get("chase_started", false)),
		"the ordinary boundary scanner starts the authored chase state")

	var stage: Dictionary = (chunk.LOCKOUT_RALLY_STAGES as Array)[0]
	var center: Vector3 = stage.get("center", Vector3.ZERO)
	preview.call("headless_set_character_position", "aster", center + Vector3(-4.0, 0.0, -0.6))
	preview.call("headless_set_character_position", "peris", center + Vector3(-4.0, 0.0, 0.6))
	var entry: Node = chunk.find_child("LockoutRally_records_entry", true, false)
	var relay_entry: Node = chunk.find_child("LockoutRally_relay_entry", true, false)
	_check(entry.is_interaction_enabled() and not relay_entry.is_interaction_enabled(),
		"only the first pair latch is initially exposed")

	preview.call("headless_select_character", "peris")
	entry.call("_trigger", false)
	_check(str((chunk.call("get_preview_state") as Dictionary).get("rally_phase", "")) == "awaiting_entry"
		and entry.is_interaction_enabled(),
		"GameState rejects Peris at Aster's entry latch without consuming it")
	preview.call("headless_select_character", "aster")
	entry.call("_trigger", false)
	var state: Dictionary = chunk.call("get_preview_state")
	_check(str(state.get("rally_phase", "")) == "surviving",
		"Aster's valid latch starts the live paired sector")

	var first_action_spec: Dictionary = (stage.get("common", []) as Array)[0]
	var first_action_id := str(first_action_spec.get("id", ""))
	var first_action: Node = chunk.find_child("LockoutRally_records_%s" % first_action_id, true, false)
	preview.call("headless_set_character_position", "peris", Vector3(center.x - 30.0, 0.0, center.z))
	preview.call("headless_select_character", str(first_action_spec.get("role", "aster")))
	first_action.call("_trigger", false)
	state = chunk.call("get_preview_state")
	_check(first_action.is_interaction_enabled()
		and not (state.get("rally_completed_actions", []) as Array).has("records:%s" % first_action_id),
		"a separated pair cannot consume specialist work")
	preview.call("headless_set_character_position", "peris", center + Vector3(-3.8, 0.0, 0.6))

	for action_variant in (stage.get("common", []) as Array):
		var action: Dictionary = action_variant
		var action_id := str(action.get("id", ""))
		var node: Node = chunk.find_child("LockoutRally_records_%s" % action_id, true, false)
		preview.call("headless_select_character", str(action.get("role", "")))
		node.call("_trigger", false)
	var north_choice: Node = chunk.find_child("LockoutRally_records_choose_north_shutter", true, false)
	var south_choice: Node = chunk.find_child("LockoutRally_records_choose_south_echo", true, false)
	_check(north_choice.is_interaction_enabled() and south_choice.is_interaction_enabled(),
		"six distinct specialist reads unlock both spatial strategy nodes")

	preview.call("headless_select_character", "aster")
	north_choice.call("_trigger", false)
	state = chunk.call("get_preview_state")
	_check(str((state.get("rally_choices", {}) as Dictionary).get("records", "")) == "north_shutter"
		and not south_choice.is_interaction_enabled(),
		"choosing north persists the strategy and permanently disables south")
	var north_strategy: Dictionary = (stage.get("strategies", []) as Array)[0]
	for execution_variant in (north_strategy.get("executions", []) as Array):
		var execution: Dictionary = execution_variant
		var execution_id := str(execution.get("id", ""))
		var node: Node = chunk.find_child("LockoutRally_records_%s" % execution_id, true, false)
		preview.call("headless_select_character", str(execution.get("role", "")))
		node.call("_trigger", false)
	var commit: Node = chunk.find_child("LockoutRally_records_commit", true, false)
	_check(not commit.is_interaction_enabled(),
		"branch execution alone cannot skip the live chase-survival requirement")
	chunk.set("_rally_elapsed", float(chunk.LOCKOUT_RALLY_LIVE_SECONDS))
	(chunk.get("_rally_elapsed_by_stage") as Dictionary)["records"] = float(chunk.LOCKOUT_RALLY_LIVE_SECONDS)
	chunk.call("_refresh_rally_commit", 0)
	_check(commit.is_interaction_enabled(),
		"the commit appears only after tasks, branch execution, and live survival are all complete")
	preview.call("headless_select_character", "peris")
	commit.call("_trigger", false)
	state = chunk.call("get_preview_state")
	_check((state.get("rally_completed_stages", []) as Array).has("records")
		and relay_entry.is_interaction_enabled(),
		"Peris's pair commit persists the branch and unlocks exactly the next sector")

	chunk.set("_checkpoint_x", 50.0)
	chunk.call("_checkpoint_resume")
	state = chunk.call("get_preview_state")
	_check((state.get("rally_completed_stages", []) as Array).has("records")
		and str((state.get("rally_choices", {}) as Dictionary).get("records", "")) == "north_shutter",
		"checkpoint recovery preserves completed work and the selected branch")

	var relay_center: Vector3 = ((chunk.LOCKOUT_RALLY_STAGES as Array)[1] as Dictionary).get("center", Vector3.ZERO)
	preview.call("headless_set_character_position", "aster", relay_center + Vector3(-4.0, 0.0, -0.5))
	preview.call("headless_set_character_position", "peris", relay_center + Vector3(-4.0, 0.0, 0.5))
	var game_state = preview.call("get_preview_game_state")
	game_state.down_character("peris")
	preview.call("headless_select_character", "aster")
	relay_entry.call("_trigger", false)
	_check(game_state.is_downed("aster") and game_state.is_downed("peris"),
		"a rally detects a missing/downed partner, drops the survivor, and enters the existing reset path")


func _dispose(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await process_frame
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nLOCKOUT ACTIVE PACING VERIFICATION: PASS")
		quit(0)
	else:
		push_error("LOCKOUT ACTIVE PACING VERIFICATION: %d failure(s)" % _failures.size())
		quit(1)
