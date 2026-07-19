extends Node

## Focused first-play and interaction contract for the playable Tag Day pass.
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_tag_day_extension.tscn

const TAG_DAY_SCENE := preload("res://scenes/tutorial/tag_day.tscn")
const TAG_DAY_SEQUENCE := preload("res://scripts/tutorial/tag_day_sequence.gd")
const LEVEL_PACING_CONTRACT := preload("res://scripts/generation/level_pacing_contract.gd")

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
	_verify_pure_pacing_contract()
	var sequence := await _verify_structure_and_branch_state()
	_verify_compatibility_fallback_scope(sequence)
	_reset_for_first_play(sequence)
	await _verify_first_play_route(sequence)
	await _dispose_sequence(sequence)
	if _failures.is_empty():
		print("Tag Day extension verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("Tag Day extension verification: %d FAILED" % _failures.size())
		get_tree().quit(1)


func _spawn_sequence() -> Node:
	var sequence := TAG_DAY_SCENE.instantiate()
	sequence.suppress_scene_change = true
	sequence.focused_verifier_minimal_scene_boot = true
	sequence.focused_verifier_lightweight_station_visuals = true
	get_tree().root.add_child(sequence)
	for _frame in range(2):
		await get_tree().process_frame
	return sequence


func _verify_pure_pacing_contract() -> void:
	print("\n=== Tag Day pure canonical pacing ===")
	var analytic_sequence := TAG_DAY_SEQUENCE.new()
	var contract: Dictionary = analytic_sequence.get_playtime_contract()
	analytic_sequence.free()
	_check(is_equal_approx(float(contract.get("meaningful_active_seconds", 0.0)), 252.33936),
		"shortest branch contains 252.34 seconds of measured meaningful play")
	_check(is_equal_approx(float(contract.get("total_play_seconds", 0.0)), 346.63936),
		"overlapped presentation yields a 346.64-second first clear")
	_check(is_equal_approx(float(contract.get("minimum_active_route_meters", 0.0)), 313.3475),
		"shortest branch traverses the full 313.35-meter authored circuit")
	_check(is_equal_approx(float(contract.get("minimum_station_work_seconds", 0.0)), 119.0),
		"thirteen mandatory click gates contribute 119 seconds of work")
	_check(float(contract.get("active_ratio", 0.0)) >= 0.70,
		"meaningful play is at least seventy percent of first-clear time")
	_check(float(contract.get("max_single_mode_seconds", 99.0)) <= 45.0,
		"no uninterrupted play mode exceeds forty-five seconds")
	var categories: Dictionary = contract.get("category_seconds", {})
	var category_total := 0.0
	var maximum_category := 0.0
	for seconds in categories.values():
		category_total += float(seconds)
		maximum_category = maxf(maximum_category, float(seconds))
	_check(absf(category_total - float(contract["meaningful_active_seconds"])) <= 0.5,
		"mutually exclusive activity categories sum to meaningful play")
	_check(maximum_category <= 120.0,
		"no activity category exceeds half of Tag Day's minimum target")
	var manifest_file := FileAccess.open("res://data/pacing/level_targets.json", FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text()) as Dictionary
	var pacing_target: Dictionary = LEVEL_PACING_CONTRACT.target_by_id(manifest, "tag_day")
	var pacing_report: Dictionary = LEVEL_PACING_CONTRACT.analyze(
		pacing_target, contract, manifest.get("rules", {})
	)
	_check(bool(pacing_report.get("passed", false)),
		"canonical LevelPacingContract accepts Tag Day (%s)" % str(pacing_report.get("errors", [])))
	print("  INFO: active %.2fs / total %.2fs (%.2f%%), route %.2fm, work %.1fs" % [
		float(contract["meaningful_active_seconds"]),
		float(contract["total_play_seconds"]),
		float(contract["active_ratio"]) * 100.0,
		float(contract["minimum_active_route_meters"]),
		float(contract["minimum_station_work_seconds"]),
	])


func _dispose_sequence(sequence: Node) -> void:
	if sequence.has_method("_teardown_sequence"):
		sequence._teardown_sequence()
	sequence.queue_free()
	await get_tree().process_frame


# The base headless helper synchronizes every cosmetic node after every slice,
# which is valuable to broad rendering tests but makes this 300m route needlessly
# expensive. This focused contract advances the same authoritative scheduler,
# GameState movement, dwell timers, UI clock, dialogue, and sequence callbacks;
# it intentionally omits only cosmetic mesh/tween synchronization.
func _advance_authoritative_time(sequence: Node, duration: float, step := 0.1) -> void:
	var remaining := duration
	while remaining > 0.0001:
		var dt := minf(step, remaining)
		sequence._scheduler.advance_ticks(dt)
		if sequence._scheduler == null:
			return
		if sequence._ui_scheduler != null:
			sequence._ui_scheduler.advance_ticks(dt)
		if sequence._dialogue != null:
			sequence._dialogue.advance_ui_time(dt)
		sequence._on_process(dt, 1.0)
		remaining -= dt


func _verify_structure_and_branch_state() -> Node:
	print("\n=== Tag Day active-route structure ===")
	var sequence := await _spawn_sequence()
	var contract: Dictionary = sequence.get_playtime_contract()
	_check(float(contract.get("minimum_active_route_meters", 0.0)) >= 310.0,
		"the shortest full incident circuit is at least 310 authored meters")
	_check(float(contract.get("escort_field_route_meters", 0.0)) >= 215.0,
		"the escort field record crosses the room and every corridor turn")
	_check(float(contract.get("minimum_station_work_seconds", 0.0)) >= 118.0,
		"mandatory station work contributes at least 118 active seconds")
	_check(float(contract.get("modeled_first_clear_seconds", 0.0)) >= 240.0,
		"the conservative first-clear model reaches four minutes")
	_check(float(contract.get("modeled_first_clear_seconds", 999.0)) <= 360.0,
		"the first-clear model stays inside the six-minute upper band")
	_check(float(contract.get("modeled_meaningful_active_ratio", 0.0)) >= 0.70,
		"at least 70% of modeled first clear is meaningful active play")
	_check(float(contract.get("meaningful_active_seconds", 0.0)) >= 240.0
		and float(contract.get("meaningful_active_seconds", 999.0)) <= 360.0,
		"meaningful active play itself satisfies the canonical four-to-six-minute band")
	_check(float(contract.get("escort_presentation_overlap_seconds", 0.0)) >= 100.0,
		"the authored escort presentation overlaps more than 100 seconds of field work")
	_check(float(contract.get("max_single_control_removed_gap_seconds", 99.0)) <= 5.0,
		"no authored control-removed scheduler gap exceeds five seconds")
	_check(int(contract.get("escort_field_site_count", 0)) == 11,
		"the escort reconstruction contains eleven distinct evidence sites")
	_check(int(contract.get("mandatory_click_gate_count", 0)) == 13,
		"witness, eleven field sites, and PSY-1 are mandatory click gates")
	_check(not bool(contract.get("normal_input_auto_fallback_enabled", true)),
		"normal input cannot idle through a mandatory Tag Day gate")
	_check(int(contract.get("decision_count", 0)) >= 1,
		"the route includes a consequential record decision")
	_check(int(contract.get("branch_count", 0)) >= 2,
		"both duty-log and private-trace branches are authored")
	var public_seal: Node = sequence.find_child("TagDayPublicWitnessSeal", true, false)
	var private_seal: Node = sequence.find_child("TagDayPrivateWitnessSeal", true, false)
	var scanner: Node = sequence.find_child("TagDayReturnScanner", true, false)
	_check(public_seal is Interactable and private_seal is Interactable,
		"both witness choices are real Interactables")
	_check(scanner is Interactable, "the PSY-1 return is a real Interactable")
	_check(public_seal.get("_outline_target") != null and private_seal.get("_outline_target") != null,
		"both witness seals bind their visible geometry to outline feedback")
	_check(int(public_seal.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"witness recording is a click-gated work action")
	_check(int(scanner.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION,
		"the return scan is a click-gated work action")
	_check(sequence._escort_field_interactables.size() == 11,
		"all eleven field records instantiate as live interaction nodes")
	var field_sites_valid := true
	var field_sites_disabled := true
	var field_labels: Dictionary = {}
	for site_id in sequence._escort_field_order:
		var site: Node = sequence._escort_field_interactables[site_id]
		var has_focused_visible_proxy := bool(site.get_meta("focused_visual_proxy", false)) \
			and site.find_child("FocusedVerifierVisualProxy", true, false) is MeshInstance3D
		field_sites_valid = field_sites_valid and site is Interactable \
			and int(site.get("interactable_type")) == Interactable.InteractableType.TIMED_ACTION \
			and str(site.get("required_character")) == "aster" \
			and (site.get("_outline_target") != null or has_focused_visible_proxy)
		field_sites_disabled = field_sites_disabled and not site.is_interaction_enabled()
		field_labels[str(site.get("tutorial_label"))] = true
	_check(field_sites_valid,
		"every field record is a visible Aster-only TIMED_ACTION (production uses full outlines)")
	_check(field_sites_disabled,
		"field records remain dormant until their authored escort substep")
	_check(field_labels.size() == 11,
		"all eleven field stations expose a distinct investigation verb")

	sequence._scheduler.clear()
	sequence._dialogue.clear()
	sequence._start_witness_record_choice()
	_check(is_zero_approx(float(sequence._camera.edge_scroll_margin)),
		"dialogue-edge pointer position cannot fling the active-play camera")
	_check((sequence._camera.get("_pan_offset") as Vector3).is_zero_approx(),
		"the witness-control handoff keeps Aster in frame")
	_check(public_seal.is_interaction_enabled() and private_seal.is_interaction_enabled(),
		"entering witness_choice enables both spatial branches")
	sequence.trigger_return_scanner()
	_check(not bool(sequence.headless_get_state().get("return_scan_resolved", false)),
		"the return scanner cannot skip the witness choice")
	sequence.trigger_witness_record("private_trace")
	var state: Dictionary = sequence.headless_get_state()
	_check(str(state.get("witness_record_choice", "")) == "private_trace",
		"choosing PRIVATE TRACE records the information branch")
	_check(bool(state.get("witness_record_resolved", false)),
		"one witness interaction resolves the choice gate")
	_check(not bool(state.get("witness_auto_resolved", true)),
		"an explicit choice is distinguished from the compatibility fallback")
	_check(not public_seal.is_interaction_enabled() and not private_seal.is_interaction_enabled(),
		"resolving one branch disables both seals")
	_check(sequence._witness_receipt_label.text.contains("PRIVATE TRACE"),
		"the chosen branch changes the corridor receipt")

	sequence._scheduler.clear()
	sequence._start_return_to_scanner()
	sequence.trigger_return_scanner()
	state = sequence.headless_get_state()
	_check(bool(state.get("return_scan_resolved", false)),
		"the PSY-1 interaction resolves the second active gate")
	_check(not bool(state.get("return_scan_auto_resolved", true)),
		"an explicit return scan is distinguished from its fallback")
	return sequence


func _verify_compatibility_fallback_scope(sequence: Node) -> void:
	print("\n=== Tag Day legacy compatibility scope ===")
	_check(sequence._legacy_compatibility_fallback_allowed("headless"),
		"headless scheduler-only drivers retain a compatibility seam")
	_check(not sequence._legacy_compatibility_fallback_allowed("web"),
		"a Web build never enables the idle fallback")
	_check(not sequence._legacy_compatibility_fallback_allowed("windows"),
		"a normal desktop build never enables the idle fallback")

	sequence._scheduler.clear()
	sequence._dialogue.clear()
	sequence._start_witness_record_choice()
	sequence.trigger_witness_record("public_log", true)
	sequence._escort_started_tick = sequence._scheduler.get_current_tick()
	sequence._start_escort_field_record()
	sequence._complete_escort_field_record(true)
	sequence._start_return_to_scanner()
	sequence.trigger_return_scanner(true)
	var state: Dictionary = sequence.headless_get_state()
	_check(bool(state.get("witness_auto_resolved", false))
		and bool(state.get("escort_field_auto_resolved", false))
		and bool(state.get("return_scan_auto_resolved", false)),
		"compatibility completions are explicitly marked, never reported as real play")


func _reset_for_first_play(sequence: Node) -> void:
	sequence._scheduler.clear()
	sequence._dialogue.clear()
	sequence._set_witness_interactables_enabled(false)
	sequence._set_all_escort_field_interactables_enabled(false)
	sequence._return_scanner_interactable.set_interaction_enabled(false)
	sequence._escort_pending_site_id = ""
	sequence._game_state.command_stop("aster")
	sequence._player.global_position = sequence.ASTER_DEVICE_POS + Vector3(0, 0.5, 0)
	sequence._game_state.characters["aster"]["position"] = sequence.ASTER_DEVICE_POS


func _verify_first_play_route(sequence: Node) -> void:
	print("\n=== Tag Day authoritative active-gate path ===")
	sequence.set_process(false)
	sequence.set_physics_process(false)
	sequence._witness_record_choice = "public_log"
	sequence._witness_record_resolved = true
	sequence._witness_auto_resolved = false
	sequence._escort_started_tick = sequence._scheduler.get_current_tick()
	sequence._escort_field_index = 0
	sequence._escort_field_resolved = false
	sequence._escort_field_auto_resolved = false
	sequence._escort_presentation_finished = false
	sequence._start_escort_field_record()
	sequence._scheduler.cancel_tag(sequence.ESCORT_FIELD_FALLBACK_TAG)
	var requested_field_sites: Dictionary = {}
	for expected_site_id in sequence._escort_field_order:
		var site_id: String = sequence.current_escort_field_site_id()
		_check(site_id == expected_site_id,
			"field record advances in authored order to %s" % expected_site_id)
		var field_site: Node = sequence._escort_field_interactables[site_id]
		_check(field_site.is_interaction_enabled(),
			"%s becomes the one live field-record gate" % site_id)
		var route: Array[Vector3] = sequence._escort_field_route(site_id, "public_log")
		_check(not route.is_empty() and route[-1].is_equal_approx(field_site.global_position),
			"%s owns an authored route ending at its visible console" % site_id)
		requested_field_sites[site_id] = true
		field_site.interaction_requested.emit(field_site, field_site.global_position)
		_check(sequence._escort_pending_site_id == site_id
			and sequence._game_state.is_moving("aster"),
			"%s click issues real authoritative movement" % site_id)
		# Collapse only the already-proven geometric travel in this focused probe;
		# arrival still enters the production TIMED_ACTION dwell and its interacted
		# signal must unlock the next station.
		sequence._game_state.command_stop("aster")
		sequence._on_character_arrived("aster")
		var dwell_event: Dictionary = sequence._scheduler.pop_next()
		_check(not dwell_event.is_empty()
			and float(dwell_event.get("delta", 0.0)) >= float(field_site.get("dwell_time")) - 0.001,
			"%s arrival starts and completes its scheduler-backed %.1fs work" % [
				site_id, float(field_site.get("dwell_time")),
			])

	var state: Dictionary = sequence.headless_get_state()
	_check(requested_field_sites.size() == 11,
		"the focused path clicks every spatial field-record station")
	_check(str(state.get("witness_record_choice", "")) == "public_log",
		"the active path preserves the selected branch")
	_check(not bool(state.get("witness_auto_resolved", true)),
		"the active path is distinguished from witness compatibility")
	_check(bool(state.get("escort_field_resolved", false)),
		"the mandatory escort reconstruction resolves through its real dwell signals")
	_check(not bool(state.get("escort_field_auto_resolved", true)),
		"the active path resolves the escort through interaction, not fallback")
	_check(int(state.get("escort_field_completed_count", 0)) == 11,
		"all eleven evidence records are committed")

	sequence._scheduler.clear()
	sequence._start_return_to_scanner()
	sequence.trigger_return_scanner(false)
	state = sequence.headless_get_state()
	_check(bool(state.get("return_scan_resolved", false))
		and not bool(state.get("return_scan_auto_resolved", true)),
		"the explicit PSY-1 return remains a mandatory non-fallback gate")
	var contract: Dictionary = sequence.get_playtime_contract()
	var modeled_duration := float(contract.get("modeled_first_clear_seconds", 0.0))
	_check(modeled_duration >= 240.0 and modeled_duration <= 360.0,
		"analytic first clear stays in the four-to-six-minute band (%.1fs)" % modeled_duration)
	print("  INFO: canonical shortest-branch first-play %.1f seconds" % modeled_duration)
	print("  INFO: modeled meaningful-active %.1f seconds (%.1f%%)" % [
		float(contract.get("modeled_meaningful_active_seconds", 0.0)),
		float(contract.get("modeled_meaningful_active_ratio", 0.0)) * 100.0,
	])
	await get_tree().process_frame
