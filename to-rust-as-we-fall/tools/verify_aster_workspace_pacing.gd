extends Node

## Focused active-play contract for Aster's workspace review and fault circuit.
##
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_aster_workspace_pacing.tscn

const ASTER_SCENE := preload("res://scenes/tutorial/aster_sim.tscn")
const PACING_MANIFEST_PATH := "res://data/pacing/level_targets.json"
const PACING_CONTRACT := preload("res://scripts/generation/level_pacing_contract.gd")

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	var sequence: Node = ASTER_SCENE.instantiate()
	sequence.set("suppress_scene_change", true)
	get_tree().root.add_child(sequence)
	for _frame in range(6):
		await get_tree().process_frame

	sequence._scheduler.clear()
	# This focused entry skips the real opening drink; reproduce the state the authored path carries
	# into the workspace so ATP/refill assertions model an actual first clear.
	sequence._game_state.set_stat("aster", "atp", sequence.ATP_MAX)
	sequence._start_explore_workspace()
	await get_tree().process_frame

	var contract: Dictionary = sequence.get_playtime_contract()
	var manifest := _load_manifest()
	var pacing_target: Dictionary = PACING_CONTRACT.target_by_id(manifest, "aster_sim")
	var report: Dictionary = PACING_CONTRACT.analyze(pacing_target, contract, manifest.get("rules", {}))
	var active := float(contract.get("meaningful_active_seconds", 0.0))
	var total := float(contract.get("total_play_seconds", 0.0))
	var ratio := active / maxf(total, 0.001)
	var categories: Dictionary = contract.get("category_seconds", {})
	var category_total := 0.0
	var category_max := 0.0
	for seconds in categories.values():
		category_total += float(seconds)
		category_max = maxf(category_max, float(seconds))
	_check(bool(report.get("passed", false)), "Aster passes the shared level-pacing analyzer (%s)" % str(report.get("errors", [])))
	_check(active >= 300.0 and active <= 480.0, "meaningful active play is inside 300-480s (%.1fs)" % active)
	_check(total >= 300.0 and total <= 480.0, "authored first-clear elapsed time stays inside 300-480s (%.1fs)" % total)
	_check(ratio >= 0.70, "meaningful-active ratio clears 70%% (%.1f%%)" % (ratio * 100.0))
	_check(float(contract.get("max_dead_gap_seconds", 99.0)) <= 5.0, "maximum dead gap stays at or below five seconds")
	_check(float(contract.get("max_single_mode_seconds", 99.0)) <= 45.0, "maximum uninterrupted mode stays at or below 45 seconds")
	_check(absf(category_total - active) <= 0.01, "mutually exclusive categories exactly equal active play")
	_check(category_max <= 150.0, "no activity category exceeds 150 seconds (max %.1fs)" % category_max)
	_check(not contract.has("provisional_pre_fault_elapsed_seconds")
		and str(contract.get("timing_basis", "")).contains("exact shortest geometry"),
		"the former provisional 210-second assumption is absent from the measured contract")
	_check(int(contract.get("mandatory_evidence_reviews", 0)) == 9,
		"three cases require nine spatial evidence reviews")
	_check(int(contract.get("mandatory_terminal_commits", 0)) == 3,
		"three real terminal decisions are mandatory")
	_check(int(contract.get("mandatory_drink_recoveries", 0)) == 1,
		"an error-free ATP route still revisits the drink machine once")
	_check(int(contract.get("mandatory_protocol_count", 0)) == 3
		and int(contract.get("mandatory_protocol_action_count", 0)) == 21,
		"three varied protocols add twenty-one mandatory spatial actions")
	_check(int(contract.get("mandatory_protocol_evidence_count", 0)) == 12
		and int(contract.get("protocol_site_count", 0)) == 30,
		"twelve protocol reads and every physical branch are explicitly authored")
	_check(int(contract.get("decision_count", 0)) == 6 and int(contract.get("branch_count", 0)) == 12,
		"three fault commits plus three protocol decisions preserve twelve valid branches")
	_check(float(contract.get("hard_idle_lock_seconds", -1.0)) == 0.0,
		"the added playtime has no passive wait gate")
	print("[ASTER_PACING] active %.1fs | elapsed %.1fs | ratio %.1f%% | route %.1fm | protocol work %.1fs" % [
		active, total, ratio * 100.0, float(contract.get("total_measured_route_meters", 0.0)),
		float(contract.get("workspace_protocol_work_seconds", 0.0)),
	])
	_verify_workspace_protocol_construction(sequence)

	var glass: Node = sequence.find_child("GlassBeadZone", true, false)
	var painting: Node = sequence.find_child("macabre_tealZone", true, false)
	var awards: Node = sequence.find_child("AwardsCenterZone", true, false)
	var jstore: Node = sequence.find_child("JStoreMainZone", true, false)
	var hallway: Node = sequence.find_child("HallwayGate", true, false)
	_check(glass != null, "glass bead review zone exists")
	_check(painting != null, "painting review zone keeps its existing name")
	_check(awards != null, "awards review zone keeps its existing name")
	_check(jstore != null, "J-store review zone keeps its existing name")
	_check(hallway != null, "hallway gate exists")
	if glass == null or painting == null or awards == null or jstore == null or hallway == null:
		await _dispose(sequence)
		_finish()
		return

	var painting_keys: Array = painting.get_meta("exploration_dialogue_keys", [])
	var awards_keys: Array = awards.get_meta("exploration_dialogue_keys", [])
	var jstore_keys: Array = jstore.get_meta("exploration_dialogue_keys", [])
	_check(painting_keys.size() == 2, "painting inspection has two meaningful beats")
	_check(
		painting_keys.size() >= 2
		and str(painting_keys[0]) == "aster.sim_expand.painting_1.line"
		and str(painting_keys[1]) == "aster.sim_expand.collection_community.line",
		"painting keeps its first line and deepens into the authored community line"
	)
	_check(awards_keys.size() == 2, "awards inspection has two meaningful beats")
	_check(
		awards_keys.size() >= 2
		and str(awards_keys[0]) == "aster.sim_expand.awards.line"
		and str(awards_keys[1]) == "aster.sim_expand.awards.journalism_line",
		"awards keeps its first line and deepens into the journalism line"
	)
	_check(
		jstore_keys.size() >= 2
		and str(jstore_keys[0]) == "aster.sim_expand.bookshelf.line"
		and str(jstore_keys[1]) == "aster.sim_expand.bookshelf.articles_line",
		"J-store keeps its existing two-step sequence"
	)

	var initial: Dictionary = sequence.headless_get_state()
	_check(str(initial.get("current_step", "")) == "explore_workspace", "workspace review owns one stable sequence step")
	_check(int(initial.get("workspace_thread_total", 0)) == 4, "four characterization threads are exposed")
	_check(int(initial.get("workspace_threads_complete", -1)) == 0, "all threads start unresolved")
	_check(not bool(initial.get("explore_gate_unlocked", true)), "hallway starts locked")

	# The old 12-second lock is now reminder-only. Waiting, even well beyond it, cannot manufacture
	# progress or release the player without engaging with the room.
	sequence.headless_advance(sequence.EXPLORE_MIN_TIME + 2.0, 0.1)
	var after_wait: Dictionary = sequence.headless_get_state()
	_check(int(after_wait.get("workspace_threads_complete", -1)) == 0, "waiting records no characterization progress")
	_check(not bool(after_wait.get("explore_gate_unlocked", true)), "timer reminder never unlocks the hallway")
	sequence._on_exploration_gate_interacted()
	_check(str(sequence._current_step) == "explore_workspace", "locked hallway cannot skip the review")

	var first_text := await _trigger_and_finish(sequence, glass)
	_check(first_text == DialogueData.text("aster.sim_expand.glass_bead.line"), "glass keeps its existing first line")
	var state: Dictionary = sequence.headless_get_state()
	_check(int((state["workspace_thread_counts"] as Dictionary).get("glass", 0)) == 1, "one glass inspection completes its thread")
	await _trigger_and_finish(sequence, glass)
	state = sequence.headless_get_state()
	_check(int((state["workspace_thread_counts"] as Dictionary).get("glass", 0)) == 1, "repeating glass cannot pad the contract")

	first_text = await _trigger_and_finish(sequence, painting)
	_check(first_text == DialogueData.text("aster.sim_expand.painting_1.line"), "painting first click preserves its authored first line")
	var second_text := await _trigger_and_finish(sequence, painting)
	_check(second_text == DialogueData.text("aster.sim_expand.collection_community.line"), "painting second click reaches the authored community beat")
	state = sequence.headless_get_state()
	_check(int((state["workspace_thread_counts"] as Dictionary).get("paintings", 0)) == 2, "two painting beats complete the art thread")

	first_text = await _trigger_and_finish(sequence, awards)
	_check(first_text == DialogueData.text("aster.sim_expand.awards.line"), "awards first click preserves its authored first line")
	second_text = await _trigger_and_finish(sequence, awards)
	_check(second_text == DialogueData.text("aster.sim_expand.awards.journalism_line"), "awards second click reaches the safety-journalism beat")
	state = sequence.headless_get_state()
	_check(int((state["workspace_thread_counts"] as Dictionary).get("awards", 0)) == 2, "two awards beats complete the status thread")

	first_text = await _trigger_and_finish(sequence, jstore)
	_check(first_text == DialogueData.text("aster.sim_expand.bookshelf.line"), "J-store first click preserves its authored first line")
	state = sequence.headless_get_state()
	_check(not bool(state.get("explore_gate_unlocked", true)), "three complete threads plus one J-store beat remain locked")
	second_text = await _trigger_and_finish(sequence, jstore)
	_check(second_text == DialogueData.text("aster.sim_expand.bookshelf.articles_line"), "J-store second click reaches Aster's repeated fault research")

	state = sequence.headless_get_state()
	_check(int((state["workspace_thread_counts"] as Dictionary).get("jstore", 0)) == 2, "J-store two-step completes the research thread")
	_check(int(state.get("workspace_threads_complete", 0)) == 4, "all four characterization threads complete")
	_check(bool(state.get("workspace_review_complete", false)), "headless state exposes review completion")
	_check(not bool(state.get("explore_gate_unlocked", true)), "four room threads hand off to fault review instead of bypassing it")
	_check(str(state.get("current_step", "")) == "fault_review", "fault review owns the post-workspace step")
	_check(bool(state.get("fault_review_started", false)) and not bool(state.get("fault_review_complete", true)),
		"headless state exposes the active incomplete fault circuit")
	_check(int(state.get("fault_case_number", 0)) == 1 and str(state.get("fault_case_id", "")) == "normalization_recurrence",
		"the first authored fault case is active")

	var fault_glass: Node = sequence.find_child("FaultEvidenceGlass", true, false)
	var fault_teal: Node = sequence.find_child("FaultEvidenceTeal", true, false)
	var fault_ash: Node = sequence.find_child("FaultEvidenceAsh", true, false)
	var fault_awards: Node = sequence.find_child("FaultEvidenceAwards", true, false)
	var fault_jstore: Node = sequence.find_child("FaultEvidenceJStore", true, false)
	var terminal: Node = sequence.find_child("Terminal", true, false)
	var drink: Node = sequence.find_child("DrinkMachine", true, false)
	var fault_nodes := {
		"glass": fault_glass,
		"painting_teal": fault_teal,
		"painting_ash": fault_ash,
		"awards": fault_awards,
		"jstore": fault_jstore,
	}
	for evidence_id in fault_nodes:
		var evidence: Node = fault_nodes[evidence_id]
		_check(evidence != null, "%s fault trace reuses a visible room object" % evidence_id)
		if evidence == null:
			continue
		_check(int(evidence.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
			"%s trace is a click-gated timed review" % evidence_id)
		_check(is_equal_approx(float(evidence.get("dwell_time")), sequence.FAULT_EVIDENCE_WORK_SECONDS),
			"%s trace carries the authored eight-second work beat" % evidence_id)
		_check(evidence.get("_outline_target") != null,
			"%s trace remains bound to visible evidence geometry" % evidence_id)
	_check(terminal != null and drink != null, "the existing terminal and drink machine drive the circuit")
	if terminal == null or drink == null or fault_nodes.values().has(null):
		await _dispose(sequence)
		_finish()
		return

	var target_pairs := {
		"RoomTargetGlassBeadGame": fault_glass,
		"RoomTargetMacabreTealPainting": fault_teal,
		"RoomTargetHunterAshPainting": fault_ash,
		"RoomTargetAwardsShelf": fault_awards,
		"RoomTargetJStoreShelf": fault_jstore,
	}
	for target_name in target_pairs:
		var target: Node = sequence.find_child(str(target_name), true, false)
		_check(target != null and target.call("get_interaction_delegate") == target_pairs[target_name],
			"%s routes fault clicks through its reused visible surface" % target_name)
	_check(not glass.is_interaction_enabled() and not painting.is_interaction_enabled()
		and not awards.is_interaction_enabled() and not jstore.is_interaction_enabled(),
		"the original named inspection zones remain present but yield interaction during fault work")

	# No scheduler duration can solve a case. Work begins only after the player chooses a trace.
	sequence.headless_advance(20.0, 0.1)
	state = sequence.headless_get_state()
	_check((state.get("fault_evidence_collected", []) as Array).is_empty(),
		"waiting during fault review collects no evidence")
	_check(int(state.get("fault_correct_commits", -1)) == 0 and not bool(state.get("explore_gate_unlocked", true)),
		"waiting cannot commit a branch or unlock the hallway")

	# Case 1: collect three distinct traces, deliberately stage the local-topology branch last,
	# and prove a rejected commit gives a clue with a once-per-case ATP penalty.
	fault_awards.call("on_interaction_arrived")
	sequence.headless_advance(sequence.FAULT_EVIDENCE_WORK_SECONDS - 0.1, 0.1)
	state = sequence.headless_get_state()
	_check(not (state.get("fault_evidence_collected", []) as Array).has("awards"),
		"timed evidence cannot fire before its active work finishes")
	sequence.headless_advance(0.2, 0.05)
	await get_tree().process_frame
	state = sequence.headless_get_state()
	_check((state.get("fault_evidence_collected", []) as Array).has("awards"),
		"scheduler-backed evidence fires when its eight-second work completes")
	await _trigger_fault_evidence(fault_jstore)
	await _trigger_fault_evidence(fault_glass)
	state = sequence.headless_get_state()
	_check((state.get("fault_evidence_collected", []) as Array).size() == 3,
		"case one requires three distinct evidence traces")
	_check(str(state.get("fault_selected_candidate", "")) == "glass",
		"the last reviewed candidate is honestly staged for commit")
	await _commit_fault_terminal(sequence, terminal)
	state = sequence.headless_get_state()
	_check(int(state.get("fault_wrong_commits", 0)) == 1, "the wrong branch is recorded as a real decision")
	_check(is_equal_approx(float(state.get("fault_wrong_atp_spent", 0.0)), sequence.FAULT_WRONG_ATP_COST),
		"the first wrong commit pays exactly the bounded ATP clue cost")
	_check(is_equal_approx(float(state.get("aster_atp", 0.0)), sequence.ATP_MAX - sequence.FAULT_WRONG_ATP_COST),
		"wrong-branch ATP cost reaches the live GameState stat")
	_check(str(state.get("fault_last_clue", "")).contains("Recheck the J-store"),
		"wrong branch exposes an actionable discriminating clue")
	_check((state.get("fault_evidence_collected", []) as Array).size() == 3,
		"wrong commit preserves collected evidence instead of forcing idle repetition")

	await _trigger_fault_evidence(fault_glass)
	await _commit_fault_terminal(sequence, terminal)
	state = sequence.headless_get_state()
	_check(int(state.get("fault_wrong_commits", 0)) == 2, "a repeated wrong branch remains an explicit commit")
	_check(is_equal_approx(float(state.get("fault_wrong_atp_spent", 0.0)), sequence.FAULT_WRONG_ATP_COST),
		"repeating the same wrong case cannot exceed its ATP penalty cap")
	await _trigger_fault_evidence(fault_jstore)
	await _commit_fault_terminal(sequence, terminal)
	state = sequence.headless_get_state()
	_check(int(state.get("fault_correct_commits", 0)) == 1 and int(state.get("fault_case_number", 0)) == 2,
		"correcting case one advances immediately to case two")

	# Case 2: the ash-band branch is the only trace coupled to heat.
	await _trigger_fault_evidence(fault_teal)
	await _trigger_fault_evidence(fault_glass)
	await _trigger_fault_evidence(fault_ash)
	await _commit_fault_terminal(sequence, terminal)
	state = sequence.headless_get_state()
	_check(int(state.get("fault_correct_commits", 0)) == 2 and int(state.get("fault_case_number", 0)) == 3,
		"the heat-linked ash commit advances to the attribution case")
	_check(is_equal_approx(float(state.get("aster_atp", 0.0)), 1.0),
		"two correct commits plus one bounded mistake leave one live ATP")

	# Case 3: evidence can be fully staged at low ATP, but committing points directly to recovery.
	await _trigger_fault_evidence(fault_teal)
	await _trigger_fault_evidence(fault_awards)
	await _trigger_fault_evidence(fault_jstore)
	await _commit_fault_terminal(sequence, terminal)
	state = sequence.headless_get_state()
	_check(int(state.get("fault_correct_commits", 0)) == 2 and not bool(state.get("fault_terminal_pending", true)),
		"insufficient ATP refuses the commit without starting a hidden wait")
	_check(str(state.get("fault_selected_candidate", "")) == "jstore",
		"ATP refusal preserves the staged candidate")
	_check(str(state.get("fault_last_clue", "")).contains("drink machine"),
		"ATP refusal names the existing recovery object")

	await _trigger_fault_evidence(drink)
	state = sequence.headless_get_state()
	_check(is_equal_approx(float(state.get("aster_atp", 0.0)), sequence.ATP_MAX),
		"the existing drink machine restores live ATP during fault review")
	_check(int(state.get("fault_drink_recoveries", 0)) == 1,
		"headless state records the mandatory recovery circuit")
	_check((state.get("fault_evidence_collected", []) as Array).size() == 3
		and str(state.get("fault_selected_candidate", "")) == "jstore",
		"drinking preserves evidence and the real commit decision")

	await _commit_fault_terminal(sequence, terminal)
	state = sequence.headless_get_state()
	_check(int(state.get("fault_correct_commits", 0)) == 3, "all three correct causes are committed")
	_check(bool(state.get("fault_review_complete", false)), "headless state exposes circuit completion")
	_check(not bool(state.get("explore_gate_unlocked", true)), "diagnosis alone cannot skip the spatial validation protocols")
	_check(bool(state.get("workspace_protocol_started", false))
		and str(state.get("workspace_protocol_phase", "")) == "phase_alignment",
		"the preserved fault circuit hands off to the ordered phase protocol")
	_check((state.get("fault_commit_history", []) as Array).size() == 5,
		"commit history exposes both wrong branches and all correct resolutions")

	await _verify_workspace_protocol_gates(sequence)
	state = sequence.headless_get_state()
	_check(bool(state.get("workspace_protocol_complete", false)), "all three workspace protocols complete")
	_check(bool(state.get("explore_gate_unlocked", false)), "workspace, diagnosis, and executed protocols unlock the hallway")
	_check((state.get("workspace_protocol_choices", {}) as Dictionary).size() == 3
		and int(state.get("workspace_protocol_decision_count", 0)) == 3,
		"all three consequential protocol choices persist")
	_check((state.get("workspace_protocol_completed", {}) as Dictionary).size() == 3
		and (state.get("workspace_protocol_execution_history", []) as Array).size() == 6,
		"one-, three-, and two-station physical branch executions persist")
	_check((state.get("workspace_protocol_effects", {}) as Dictionary).size() >= 7,
		"branch consequences remain available after the final operation")

	sequence._on_exploration_gate_interacted()
	_check(str(sequence._current_step) == "tag_notify", "completed long-form route hands off through the existing Tag Day step")

	await _dispose(sequence)
	_finish()

func _verify_workspace_protocol_construction(sequence: Node) -> void:
	var layer := sequence.find_child("AsterWorkspaceProtocols", true, false)
	var groups := sequence.find_children("AsterProtocolGroup_*", "Node3D", true, false)
	var sites := sequence.find_children("AsterProtocol_*", "Interactable", true, false)
	var frames := sequence.find_children("AsterProtocolFrame_*", "Node3D", true, false)
	var lights := sequence.find_children("AsterProtocolLight_*", "OmniLight3D", true, false)
	var datums := sequence.find_children("AsterProtocolDatum_*", "MeshInstance3D", true, false)
	_check(layer != null, "three protocols own a dedicated projected-instrument layer")
	_check(groups.size() == 3, "ordered, survey, and handoff protocols have distinct visual groups")
	_check(sites.size() == 30, "twelve evidence, six plans, and twelve branch execution stations are real Interactables")
	_check(frames.size() == 3 and lights.size() == 3, "every protocol has a measured frame and WebGL-safe landmark light")
	_check(datums.size() == 27, "twenty-seven route datums visibly expose evidence and every branch path")
	var timed := 0
	var outlined := 0
	var delegated := 0
	var routed := 0
	var registered := 0
	var kinds := {"evidence": 0, "choice": 0, "execution": 0}
	var minimum_drink_clearance := INF
	var drink := sequence.find_child("DrinkMachine", true, false) as Node3D
	for site in sites:
		if int(site.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION:
			timed += 1
		var outline_target = site.get("_outline_target")
		if outline_target != null:
			outlined += 1
			if outline_target.has_method("get_interaction_delegate") \
					and outline_target.call("get_interaction_delegate") == site:
				delegated += 1
		if site.interaction_requested.get_connections().size() >= 1:
			routed += 1
		var data_id := str(site.get("data_id"))
		if data_id != "" and sequence._game_state.has_interactable(data_id):
			var registered_spec: Dictionary = sequence._game_state.get_interactable(data_id)
			if str(registered_spec.get("required_character", "")) == "aster":
				registered += 1
		var site_id := str(site.get_meta("workspace_protocol_site_id", ""))
		var kind := str(sequence.WORKSPACE_PROTOCOL_SITES.get(site_id, {}).get("kind", ""))
		if kinds.has(kind):
			kinds[kind] += 1
		if drink != null:
			minimum_drink_clearance = minf(minimum_drink_clearance,
				Vector2(site.global_position.x, site.global_position.z).distance_to(Vector2(drink.global_position.x, drink.global_position.z)))
	_check(timed == 30, "every protocol station is a click-gated timed action")
	_check(outlined == 30, "every projected station binds a visible constructed-object outline")
	_check(delegated == 30, "clicking projected station geometry delegates to its timed protocol action")
	_check(routed == 30, "every protocol click routes through Aster's normal interaction controller")
	_check(registered == 30, "every protocol specialist gate is authoritative in GameState")
	_check(int(kinds["evidence"]) == 12 and int(kinds["choice"]) == 6 and int(kinds["execution"]) == 12,
		"protocol station roles match the authored evidence/choice/execution grammar")
	_check(minimum_drink_clearance >= 1.8, "projected instruments preserve drink-machine clearance (%.2fm)" % minimum_drink_clearance)

func _verify_workspace_protocol_gates(sequence: Node) -> void:
	var protocol_order: Array = sequence.WORKSPACE_PROTOCOL_ORDER
	var protocols: Dictionary = sequence.WORKSPACE_PROTOCOLS
	var specs: Dictionary = sequence.WORKSPACE_PROTOCOL_SITES
	var sites: Dictionary = sequence.get("_workspace_protocol_sites")
	var branch_indices := [0, 1, 0]
	for protocol_index in range(protocol_order.size()):
		var protocol_id := str(protocol_order[protocol_index])
		var protocol: Dictionary = protocols[protocol_id]
		var state: Dictionary = sequence.headless_get_state()
		_check(str(state.get("workspace_protocol_phase", "")) == protocol_id
			and str(state.get("current_step", "")) == str(protocol.get("step", "")),
			"%s owns its player-controlled sequence step" % protocol_id)
		for choice_id_variant in protocol.get("choices", []):
			_check(not sites[str(choice_id_variant)].is_interaction_enabled(),
				"%s plans stay locked before evidence" % protocol_id)
		var evidence: Array = protocol.get("evidence", [])
		if bool(protocol.get("ordered_evidence", false)) and evidence.size() > 1:
			var out_of_order_id := str(evidence[1])
			_check(not sites[out_of_order_id].is_interaction_enabled(), "phase walk exposes only its next spatial node")
			sites[out_of_order_id].call("_trigger", false)
			state = sequence.headless_get_state()
			_check(not (state.get("workspace_protocol_evidence", {}) as Dictionary).get(protocol_id, {}).has(out_of_order_id),
				"an out-of-order phase node cannot manufacture progress")

		for evidence_index in range(evidence.size()):
			var evidence_id := str(evidence[evidence_index])
			var evidence_site: Node = sites[evidence_id]
			_check(evidence_site.is_interaction_enabled(), "%s exposes reachable evidence %s" % [protocol_id, evidence_id])
			if protocol_index == 0 and evidence_index == 0:
				evidence_site.interaction_requested.emit(evidence_site, evidence_site.global_position)
				await get_tree().process_frame
				_check(sequence._game_state.is_moving("aster"), "normal protocol click starts scheduler-backed Aster movement")
				var movement_safety := 0
				while sequence._game_state.is_moving("aster") and movement_safety < 200:
					sequence.headless_advance(0.1, 0.05)
					movement_safety += 1
				_check(movement_safety < 200, "normal interaction controller reaches the first protocol station")
				sequence.headless_advance(float(specs[evidence_id].get("dwell", 0.0)) - 0.1, 0.1)
				state = sequence.headless_get_state()
				var partial: Dictionary = (state.get("workspace_protocol_evidence", {}) as Dictionary).get(protocol_id, {})
				_check(not partial.has(evidence_id), "protocol work cannot resolve before its authored dwell")
				sequence.headless_advance(0.2, 0.05)
				await get_tree().process_frame
			else:
				evidence_site.call("_trigger", false)
				await get_tree().process_frame
		state = sequence.headless_get_state()
		var completed_evidence: Dictionary = (state.get("workspace_protocol_evidence", {}) as Dictionary).get(protocol_id, {})
		_check(completed_evidence.size() == evidence.size(), "%s requires every distinct evidence station" % protocol_id)
		for choice_id_variant in protocol.get("choices", []):
			_check(sites[str(choice_id_variant)].is_interaction_enabled(), "%s unlocks both valid plans" % protocol_id)

		var choice_id := str((protocol.get("choices", []) as Array)[int(branch_indices[protocol_index])])
		sites[choice_id].call("_trigger", false)
		await get_tree().process_frame
		var execution: Array = (protocol.get("execution_sites", {}) as Dictionary).get(choice_id, [])
		for execution_index in range(execution.size()):
			var execution_id := str(execution[execution_index])
			_check(sites[execution_id].is_interaction_enabled(), "%s exposes committed execution %s" % [protocol_id, execution_id])
			if execution_index + 1 < execution.size():
				_check(not sites[str(execution[execution_index + 1])].is_interaction_enabled(),
					"%s execution remains spatially ordered" % protocol_id)
			sites[execution_id].call("_trigger", false)
			await get_tree().process_frame
		state = sequence.headless_get_state()
		_check(str((state.get("workspace_protocol_choices", {}) as Dictionary).get(protocol_id, "")) == choice_id,
			"%s choice persists after physical execution" % protocol_id)

func _load_manifest() -> Dictionary:
	var text := FileAccess.get_file_as_string(PACING_MANIFEST_PATH)
	var parsed = JSON.parse_string(text)
	_check(parsed is Dictionary, "pacing manifest loads for the shared analyzer")
	return parsed as Dictionary if parsed is Dictionary else {}


func _trigger_and_finish(sequence: Node, zone: Node) -> String:
	zone.call("_trigger", false)
	await get_tree().process_frame
	var text := str(sequence._dialogue.get("_current_text"))
	sequence._dialogue.clear()
	sequence._dialogue.dialogue_finished.emit()
	await get_tree().process_frame
	return text


func _trigger_fault_evidence(evidence: Node) -> void:
	evidence.call("_trigger", false)
	await get_tree().process_frame


func _commit_fault_terminal(sequence: Node, terminal: Node) -> void:
	terminal.call("_trigger", false)
	await get_tree().process_frame
	if bool(sequence.headless_get_state().get("fault_terminal_pending", false)):
		sequence.headless_advance(sequence.TERMINAL_FOCUS_DURATION + 0.1, 0.1)
		await get_tree().process_frame


func _dispose(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.queue_free()
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	_failures.append(message)
	push_error("[FAIL] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("\nASTER WORKSPACE PACING: PASS")
		get_tree().quit(0)
	else:
		push_error("\nASTER WORKSPACE PACING: FAIL (%d checks)" % _failures.size())
		get_tree().quit(1)
