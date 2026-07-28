extends Node

## Focused contract for Aster's canonical workspace:
## four characterization threads are optional, while the hallway advances immediately.
##
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_aster_workspace_pacing.tscn

const ASTER_SCENE := preload("res://scenes/tutorial/aster_sim.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	await _verify_direct_hallway_route()
	await _verify_optional_workspace_route()
	_finish()


func _verify_direct_hallway_route() -> void:
	var sequence := await _make_sequence()
	if sequence == null:
		return
	var hallway: Node = sequence.find_child("HallwayGate", true, false)
	_check(hallway != null, "the authored hallway progression gate exists")
	if hallway == null:
		await _dispose(sequence)
		return

	var state: Dictionary = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "explore_workspace",
		"the workspace opens as free exploration")
	_check(bool(state.get("workspace_reads_optional", false)),
		"workspace characterization reads are explicitly optional")
	_check(int(state.get("workspace_reads_complete", -1)) == 0,
		"the optional-read counter starts empty")
	_check(int(state.get("workspace_read_target_count", 0)) == 4,
		"four optional characterization threads are tracked")
	_check(bool(state.get("explore_gate_unlocked", false)),
		"the hallway unlocks immediately")
	_check(bool(hallway.get("interaction_enabled")),
		"the hallway is interactable before any optional read")
	_check(sequence.find_child("FaultEvidence*", true, false) == null,
		"no fault-review interactables are generated")
	_check(sequence.find_child("WorkspaceProtocol*", true, false) == null,
		"no workspace-protocol interactables are generated")
	_verify_playtime_contract(sequence)

	hallway.call("_trigger", false)
	await get_tree().process_frame
	state = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "tag_notify",
		"clicking the hallway immediately begins the Tag Day handoff")
	_check(int(state.get("workspace_reads_complete", -1)) == 0,
		"direct progression requires no optional workspace reads")
	await _dispose(sequence)


func _verify_optional_workspace_route() -> void:
	var sequence := await _make_sequence()
	if sequence == null:
		return
	var zones := {
		"glass": sequence.find_child("GlassBeadZone", true, false),
		"painting": sequence.find_child("macabre_tealZone", true, false),
		"awards": sequence.find_child("AwardsCenterZone", true, false),
		"jstore": sequence.find_child("JStoreMainZone", true, false),
	}
	var hallway: Node = sequence.find_child("HallwayGate", true, false)
	for thread_id in zones:
		var zone: Node = zones[thread_id]
		_check(zone != null, "%s optional workspace object exists" % thread_id)
		if zone != null:
			_check(bool(zone.get("interaction_enabled")),
				"%s is available during free exploration" % thread_id)
	if zones.values().has(null) or hallway == null:
		await _dispose(sequence)
		return

	var first_text := await _trigger_and_finish(sequence, zones["glass"])
	_check(first_text == DialogueData.text("aster.sim_expand.glass_bead.line"),
		"the glass-bead object keeps its authored worldbuilding line")
	first_text = await _trigger_and_finish(sequence, zones["painting"])
	var second_text := await _trigger_and_finish(sequence, zones["painting"])
	_check(first_text == DialogueData.text("aster.sim_expand.painting_1.line")
		and second_text == DialogueData.text("aster.sim_expand.collection_community.line"),
		"the painting object keeps both authored optional beats")
	first_text = await _trigger_and_finish(sequence, zones["awards"])
	second_text = await _trigger_and_finish(sequence, zones["awards"])
	_check(first_text == DialogueData.text("aster.sim_expand.awards.line")
		and second_text == DialogueData.text("aster.sim_expand.awards.journalism_line"),
		"the awards object keeps both authored optional beats")
	first_text = await _trigger_and_finish(sequence, zones["jstore"])
	second_text = await _trigger_and_finish(sequence, zones["jstore"])
	_check(first_text == DialogueData.text("aster.sim_expand.bookshelf.line")
		and second_text == DialogueData.text("aster.sim_expand.bookshelf.articles_line"),
		"the J-store object keeps both authored optional beats")

	var state: Dictionary = sequence.headless_get_state()
	_check(int(state.get("workspace_reads_complete", 0)) == 4,
		"all four optional characterization threads can still be completed")
	_check(bool(state.get("explore_gate_unlocked", false))
		and bool(hallway.get("interaction_enabled")),
		"optional reads leave the already-open hallway available")
	_check(str(state.get("current_step", "")) == "explore_workspace",
		"optional reads do not advance the tutorial by themselves")

	hallway.call("_trigger", false)
	await get_tree().process_frame
	_check(str(sequence.headless_get_state().get("current_step", "")) == "tag_notify",
		"the hallway advances after any amount of optional exploration")
	await _dispose(sequence)


func _verify_playtime_contract(sequence: Node) -> void:
	var contract: Dictionary = sequence.get_playtime_contract()
	_check(bool(contract.get("free_exploration", false)),
		"playtime contract declares free exploration")
	_check(str(contract.get("progression_gate", "")) == "hallway",
		"playtime contract names the hallway gate")
	_check(int(contract.get("mandatory_optional_reads", -1)) == 0,
		"playtime contract requires zero workspace reads")
	_check(int(contract.get("optional_interactable_count", 0)) == 4,
		"playtime contract inventories four optional characterization threads")
	_check(is_equal_approx(float(contract.get("target_min_seconds", 0.0)), 30.0)
		and is_equal_approx(float(contract.get("target_max_seconds", 0.0)), 90.0),
		"playtime contract models a concise optional exploration lap")


func _make_sequence() -> Node:
	var sequence: Node = ASTER_SCENE.instantiate()
	sequence.set("suppress_scene_change", true)
	get_tree().root.add_child(sequence)
	for _frame in range(6):
		await get_tree().process_frame
	sequence._scheduler.clear()
	sequence._ui_scheduler.clear()
	sequence._start_explore_workspace()
	await get_tree().process_frame
	return sequence


func _trigger_and_finish(sequence: Node, zone: Node) -> String:
	zone.call("_trigger", false)
	await get_tree().process_frame
	var text := str(sequence._dialogue.get("_current_text"))
	sequence._dialogue.clear()
	sequence._dialogue.dialogue_finished.emit()
	await get_tree().process_frame
	return text


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
		print("\nASTER OPTIONAL-WORKSPACE FLOW: PASS")
		get_tree().quit(0)
	else:
		push_error("\nASTER OPTIONAL-WORKSPACE FLOW: FAIL (%d checks)" % _failures.size())
		get_tree().quit(1)
