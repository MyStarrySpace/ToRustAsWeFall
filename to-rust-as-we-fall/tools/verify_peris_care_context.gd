extends SceneTree

## Focused contract for Peris's canonical first-visit room:
## room reads and watering are optional, while the logbook advances immediately.
##
## Run:
##   godot --headless --path . --script res://tools/verify_peris_care_context.gd

const PERIS_SCENE := preload("res://scenes/tutorial/peris_sim.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	await _verify_direct_logbook_route()
	await _verify_optional_room_route()
	_finish()


func _verify_direct_logbook_route() -> void:
	var sequence := await _make_sequence()
	if sequence == null:
		return
	var logbook: Node = sequence.find_child("LogbookGate", true, false)
	_check(logbook != null, "the authored logbook progression gate exists")
	if logbook == null:
		await _dispose(sequence)
		return

	var state: Dictionary = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "workspace", "first visit opens in free room exploration")
	_check(bool(state.get("room_reads_optional", false)), "room reads are explicitly optional")
	_check(int(state.get("room_read_count", -1)) == 0, "the optional-read counter starts empty")
	_check(bool(state.get("explore_gate_unlocked", false)), "the logbook gate unlocks immediately")
	_check(bool(state.get("logbook_ready", false)), "headless state reports the logbook ready")
	_check(bool(logbook.get("interaction_enabled")), "the logbook is interactable before any room read")
	_check(not bool(state.get("plant_watered", true)), "watering is not completed implicitly")
	_check(sequence.find_child("CareAudit*", true, false) == null, "no care-audit interactables are generated")
	_check(sequence.find_child("CareOperation*", true, false) == null, "no care-operation interactables are generated")
	_check(sequence.find_child("CareKitPickup", true, false) == null, "no mandatory field-kit pickup is generated")
	_verify_playtime_contract(sequence)

	logbook.call("_trigger", false)
	await process_frame
	state = sequence.headless_get_state()
	_check(str(state.get("current_step", "")) == "monos_breakthrough",
		"clicking the logbook immediately starts Monos's breakthrough")
	_check(int(state.get("room_read_count", -1)) == 0,
		"direct progression requires no optional room reads")
	_check(not bool(state.get("plant_watered", true)),
		"direct progression requires no watering action")
	await _dispose(sequence)


func _verify_optional_room_route() -> void:
	var sequence := await _make_sequence()
	if sequence == null:
		return
	var zone_names := [
		"Plant1Zone", "Plant2Zone", "Plant3Zone", "Plant4Zone", "Plant5Zone",
		"Plant6Zone", "Plant7Zone", "Plant8Zone", "Plant9Zone",
		"PaintingZone", "WellnessZone", "StrikeWarningZone",
	]
	var zones: Dictionary = {}
	for zone_name in zone_names:
		var zone: Node = sequence.find_child(zone_name, true, false)
		zones[zone_name] = zone
		_check(zone != null, "%s optional worldbuilding object exists" % zone_name)
		if zone != null:
			_check(bool(zone.get("interaction_enabled")), "%s is available during free exploration" % zone_name)
	var logbook: Node = sequence.find_child("LogbookGate", true, false)
	var watering_can: Node = sequence.find_child("WateringCanPickup", true, false)
	var water_fern: Node = sequence.find_child("WaterPlantSpot", true, false)
	_check(logbook != null and watering_can != null and water_fern != null,
		"the logbook and optional watering interaction exist")
	if zones.values().has(null) or logbook == null or watering_can == null or water_fern == null:
		await _dispose(sequence)
		return

	await _trigger_and_finish(sequence, zones["Plant1Zone"])
	await _trigger_and_finish(sequence, zones["PaintingZone"])
	await _trigger_and_finish(sequence, zones["WellnessZone"])
	await _trigger_and_finish(sequence, zones["StrikeWarningZone"])
	var state: Dictionary = sequence.headless_get_state()
	_check(int(state.get("room_read_count", 0)) == 4,
		"optional room interactions record coverage without becoming prerequisites")
	_check(bool(state.get("explore_gate_unlocked", false)) and bool(logbook.get("interaction_enabled")),
		"optional reads leave the already-open logbook available")
	_check(str(state.get("current_step", "")) == "workspace",
		"optional reads do not advance the tutorial by themselves")

	sequence.set_preview_character_position("peris", watering_can.global_position)
	watering_can.call("_trigger", false)
	await process_frame
	sequence.set_preview_character_position("peris", water_fern.global_position)
	water_fern.call("_trigger", false)
	await process_frame
	state = sequence.headless_get_state()
	_check(str(state.get("watering_phase", "")) == str(sequence.WATERING_PHASE_ACTIVE)
		and not bool(state.get("plant_watered", true)),
		"watering begins a real action instead of granting the result on click")
	sequence.headless_advance(sequence.WATERING_USE_DURATION + 0.05, 0.05)
	state = sequence.headless_get_state()
	_check(bool(state.get("plant_watered", false)), "watering remains a functional optional character beat")
	var item_id := str(state.get("watering_can_item_id", ""))
	var item := sequence._game_state.items.get(item_id, {}) as Dictionary
	_check(str(item.get("location", "")) == "hand" and str(item.get("holder", "")) == "peris",
		"using the reusable can leaves it in Peris's hand until an explicit drop")
	_check(bool(logbook.get("interaction_enabled")), "watering does not gate or consume the logbook")

	logbook.call("_trigger", false)
	await process_frame
	_check(str(sequence.headless_get_state().get("current_step", "")) == "monos_breakthrough",
		"the logbook advances after any amount of optional exploration")
	await _dispose(sequence)


func _verify_playtime_contract(sequence: Node) -> void:
	var contract: Dictionary = sequence.get_playtime_contract()
	_check(bool(contract.get("free_exploration", false)), "playtime contract declares free exploration")
	_check(str(contract.get("progression_gate", "")) == "logbook", "playtime contract names the logbook gate")
	_check(int(contract.get("mandatory_optional_reads", -1)) == 0, "playtime contract requires zero room reads")
	_check(int(contract.get("mandatory_watering_actions", -1)) == 0, "playtime contract requires zero watering actions")
	_check(int(contract.get("optional_interactable_count", 0)) == 12, "playtime contract inventories twelve optional room reads")
	_check(is_equal_approx(float(contract.get("target_min_seconds", 0.0)), 30.0)
		and is_equal_approx(float(contract.get("target_max_seconds", 0.0)), 90.0),
		"playtime contract models a concise optional exploration lap")


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


func _trigger_and_finish(sequence: Node, zone: Node) -> void:
	zone.call("_trigger", false)
	await process_frame
	sequence._dialogue.clear()
	sequence._dialogue.dialogue_finished.emit()
	await process_frame


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
		print("\nPERIS OPTIONAL-ROOM FLOW: PASS")
		quit(0)
	else:
		push_error("\nPERIS OPTIONAL-ROOM FLOW: FAIL (%d checks)" % _failures.size())
		quit(1)
