extends Node

## Focused regression contract for Tag Day's authored checkpoint cinematic.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_tag_day_extension.tscn

const TAG_DAY_SCENE := preload("res://scenes/tutorial/tag_day.tscn")

const REMOVED_STATION_NAMES := [
	"TagDayPublicWitnessSeal",
	"TagDayPrivateWitnessSeal",
	"TagDayReturnScanner",
	"TagDayScanFailureRecord",
	"TagDayEastQueueWitness",
	"TagDayWestQueueWitness",
	"TagDayReportProvenance",
	"TagDayMedicalOverride",
	"TagDayCustodyThreshold",
	"TagDayGaitVariance",
	"TagDayGripTelemetry",
	"TagDayIronShadowSample",
	"TagDayReportEchoTriangulation",
	"TagDayErasureReceipt",
]

const CANONICAL_STEPS := [
	"arrive",
	"citizen_scan",
	"naturalizers_grip",
	"corridor_walk",
	"fragments",
	"neutralization",
	"lockdown",
	"return_focus",
	"aster_scans",
	"clearance",
	"complete",
]

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	var sequence := await _spawn_sequence()
	_verify_production_structure(sequence)
	_verify_direct_authored_transitions(sequence)
	await _dispose_sequence(sequence)
	await _verify_complete_fast_forward_playthrough()

	if _failures.is_empty():
		print("Tag Day extension verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("Tag Day extension verification: %d FAILED" % _failures.size())
		get_tree().quit(1)


func _spawn_sequence() -> Node:
	var sequence := TAG_DAY_SCENE.instantiate()
	sequence.suppress_scene_change = true
	get_tree().root.add_child(sequence)
	for _frame in range(3):
		await get_tree().process_frame
	return sequence


func _dispose_sequence(sequence: Node) -> void:
	if sequence != null and is_instance_valid(sequence):
		if sequence.has_method("_teardown_sequence"):
			sequence._teardown_sequence()
		sequence.queue_free()
	await get_tree().process_frame


func _advance_until_step(sequence: Node, target_step: String, limit: float) -> float:
	var elapsed := 0.0
	while str(sequence._current_step) != target_step and elapsed < limit:
		sequence.headless_advance(0.05, 0.05)
		elapsed += 0.05
	return elapsed


func _verify_production_structure(sequence: Node) -> void:
	print("\n=== Tag Day authored structure ===")
	_check(sequence.find_child("Environment", true, false) != null,
		"the production checkpoint environment is present")
	_check(sequence.find_child("Characters", true, false) != null,
		"the authored checkpoint cast is present")
	for station_name in REMOVED_STATION_NAMES:
		_check(sequence.find_child(station_name, true, false) == null,
			"no invented mandatory station is built: %s" % station_name)
	_check(not sequence.has_method("trigger_witness_record"),
		"no mandatory witness-choice progression hook remains")
	_check(not sequence.has_method("current_escort_field_site_id"),
		"no eleven-stop incident circuit progression hook remains")
	_check(not sequence.has_method("trigger_return_scanner"),
		"no mandatory return-scan progression hook remains")

	var camera_prompt := str(sequence._camera_control_prompt_text())
	for action in [
		"camera_pan_forward",
		"camera_pan_left",
		"camera_pan_back",
		"camera_pan_right",
		"camera_rotate_left",
		"camera_rotate_right",
	]:
		_check(camera_prompt.contains(InputHints.label_for_action(action, "")),
			"optional camera prompt follows the live %s binding" % action)
	_check(camera_prompt.contains("rotate view"),
		"optional witnessing explicitly includes camera rotation")

	sequence._show_fastforward_prompt()
	var prompt_label := sequence.get_node_or_null(
		"TutorialUI/TutorialPrompt/PromptRow/PromptLabel"
	) as Label
	var prompt_text := prompt_label.text if prompt_label != null else ""
	_check(prompt_text.contains(InputHints.label_for_action("fast_forward", "X")),
		"fast-forward prompt follows the live action binding")
	_check(prompt_text.to_lower().contains("hold")
		and prompt_text.to_lower().contains("fast-forward"),
		"fast-forward is presented as an available hold action")

	Input.action_press("fast_forward")
	_check(is_equal_approx(float(sequence._compute_speed()), 10.0),
		"holding fast-forward accelerates the shared gameplay beat")
	Input.action_release("fast_forward")


func _verify_direct_authored_transitions(sequence: Node) -> void:
	print("\n=== Tag Day authored transitions ===")
	sequence.set_process(false)
	sequence._scheduler.clear()
	sequence._dialogue.clear()

	sequence._start_citizen_scan()
	_check(str(sequence._current_step) == "citizen_scan",
		"checkpoint failure enters the citizen-scan beat")
	sequence._scheduler.advance_ticks(2.9)
	_check(str(sequence._current_step) == "citizen_scan",
		"the scan failure remains visible before the escort responds")
	sequence._scheduler.advance_ticks(0.2)
	_check(str(sequence._current_step) == "naturalizers_grip",
		"scan failure proceeds directly to the Naturalizer escort")

	var nk2_start: Vector3 = sequence._game_state.get_position("nk2")
	sequence._scheduler.advance_ticks(2.0)
	var nk2_mid: Vector3 = sequence._game_state.get_position("nk2")
	_check(str(sequence._current_step) == "naturalizers_grip"
		and nk2_mid.distance_to(nk2_start) > 0.5
		and nk2_mid.distance_to(sequence.NK_GRIP_POS_2) > sequence.GRIP_ARRIVAL_RADIUS,
		"the slower Naturalizer visibly approaches instead of being snapped into formation")
	var grip_midpoint: Dictionary = sequence.build_save_snapshot()
	_advance_until_step(sequence, "corridor_walk", 12.0)
	_check(str(sequence._current_step) == "corridor_walk",
		"the escort begins only after both Naturalizers physically arrive")
	_check(sequence._game_state.is_moving("citizen")
		and sequence._game_state.is_moving("nk1")
		and sequence._game_state.is_moving("nk2"),
		"citizen and both Naturalizers execute the corridor choreography")
	sequence.apply_save_snapshot(grip_midpoint)
	_check(str(sequence._current_step) == "naturalizers_grip"
		and sequence._game_state.is_moving("nk2")
		and sequence._game_state.get_position("nk2").distance_to(nk2_mid) < 0.01,
		"mid-approach save retracts the corridor future to the physical formation path")
	_advance_until_step(sequence, "corridor_walk", 12.0)
	_check(str(sequence._current_step) == "corridor_walk",
		"restored formation consumes only its saved remaining travel before handoff")
	sequence._on_poem_finished()
	_check(str(sequence._current_step) == "corridor_walk",
		"finishing the poem cannot skip the three bodies' physical corridor arrivals")
	_advance_until_step(sequence, "fragments", 150.0)
	_check(str(sequence._current_step) == "fragments",
		"the authored fragments begin after presentation and all three arrivals join")

	sequence._scheduler.clear()
	sequence._dialogue.clear()
	sequence._start_return_focus()
	sequence._scheduler.advance_ticks(1.9)
	_check(str(sequence._current_step) == "return_focus",
		"post-lockdown focus holds for the authored two-second beat")
	sequence._scheduler.advance_ticks(0.2)
	_check(str(sequence._current_step) == "aster_scans",
		"post-lockdown focus proceeds directly to Aster's pass scan")
	_check(sequence._dialogue.is_active(),
		"Aster's pass scan presents its authored dialogue before transition")


func _verify_complete_fast_forward_playthrough() -> void:
	print("\n=== Tag Day complete fast-forward playthrough ===")
	var sequence := await _spawn_sequence()
	sequence.set_process(false)
	var observed_steps: Array[String] = []
	var last_step := ""
	Input.action_press("fast_forward")
	for _frame in range(3000):
		sequence._process(0.1)
		var step := str(sequence._current_step)
		if step != last_step:
			observed_steps.append(step)
			last_step = step
		if step == "complete":
			break
	Input.action_release("fast_forward")

	_check(observed_steps.has("complete"),
		"the authored sequence reaches the elevator transition without injected clicks")
	var cursor := 0
	for step in observed_steps:
		if cursor < CANONICAL_STEPS.size() and step == CANONICAL_STEPS[cursor]:
			cursor += 1
	_check(cursor == CANONICAL_STEPS.size(),
		"checkpoint, escort, poem, Aster scan, and elevator beats remain in canonical order (%s)"
			% str(observed_steps))
	var invented_step_seen := false
	for step in observed_steps:
		invented_step_seen = invented_step_seen \
			or step == "witness_choice" \
			or step.begins_with("escort_record_") \
			or step == "return_to_scanner"
	_check(not invented_step_seen,
		"the complete playthrough contains no witness/circuit/return-scan padding")
	await _dispose_sequence(sequence)
