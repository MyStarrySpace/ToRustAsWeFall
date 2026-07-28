extends SceneTree

## Focused production smoke for the canonical Open Files chunk. Mechanism-level save seams live in
## their dedicated verifiers; this proves the scene composes those mechanisms without reviving the
## retired bank comparison, patrol scan, enemy spoof, fake sentry, or push-button bridge.

const PreviewScene := preload("res://scenes/fragments/fragment_preview.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var preview = PreviewScene.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "stacks"
	preview.suppress_scene_change = true
	root.add_child(preview)
	for _frame in range(12):
		await process_frame
	var chunk = preview._active_chunk
	check(chunk != null, "Open Files preview boots its production chunk")
	if chunk == null:
		_finish()
		return
	var gs: GameState = preview._game_state
	var state: Dictionary = chunk.get_preview_state()
	check(chunk.get_scene_title() == "The Open Files Initiative"
			and str(state.get("contract", "")) == "open_files_encounter/v2",
		"player-facing district name and encounter contract are canonical")
	check(gs.grid.level_count == 3 and chunk._drawer_stairs.size() == 2,
		"the chunk composes three vertical levels and both six-index drawer bays")
	check(chunk._sapscraps.size() == 2
			and not chunk.has_node("Naturalizer")
			and not chunk.has_node("IndexSentry"),
		"abandoned-space pressure is two real Sapscraps, not invented Stacks enemies")
	check((state.get("terminal_effects", []) as Array) == [
		"scan_data", "toggle_global_index", "expose_iron_fixture",
		"authorize_tracked_access", "emp_power_cut",
	], "Aster's composed kit has five distinct truthful consequences")

	var arrival = chunk.get_playthrough_interaction_target("arrival_terminal")
	check(_physical_trigger(preview, arrival, "aster"),
		"Aster physically reads the authored cleaned-data arrival terminal")
	var support = chunk.get_playthrough_interaction_target("support_log")
	check(_physical_trigger(preview, support, "aster"),
		"Aster physically reads the authored support intake")
	check(chunk._shelter_interactable.is_interaction_enabled(),
		"the two authored records provide shelter narrative context without a policy-bank gate")
	chunk._clear_dialogue()
	preview.headless_advance(0.2, 0.1)

	var aster_read = chunk.get_playthrough_interaction_target(
		"drawer_bay_one_bay_one_column_a_aster")
	var peris_read = chunk.get_playthrough_interaction_target(
		"drawer_bay_one_bay_one_column_a_peris")
	var aster_read_ok := _physical_trigger(preview, aster_read, "aster")
	var peris_read_ok := _physical_trigger(preview, peris_read, "peris")
	check(aster_read_ok and peris_read_ok,
		"Aster and Peris contribute separate physical reads to one candidate column")
	chunk.update_preview_overlay_states({"aster": true, "peris": true}, 0.0, 0.0)
	var read_labels := chunk._inspection_labels.get(
		"drawer_bay_one:bay_one_column_a", {}) as Dictionary
	check(bool((read_labels.get("aster") as Label3D).visible)
			and bool((read_labels.get("peris") as Label3D).visible),
		"accepted reads persist in their contributor's visible overlay")
	chunk.update_preview_overlay_states({"aster": false, "peris": true}, 0.0, 0.0)
	check(not bool((read_labels.get("aster") as Label3D).visible)
			and bool((read_labels.get("peris") as Label3D).visible),
		"Aster's read hides with Aster while Peris's independent read remains")

	var bay_one = chunk._drawer_stairs.get("drawer_bay_one")
	var bay_one_ok := true
	for category_id in ["sensory", "motor", "memory"]:
		bay_one_ok = bay_one_ok and _physical_trigger(
			preview, bay_one.get_index_interactable(category_id), "aster")
		preview.headless_advance(1.5, 0.1)
	check(bay_one_ok and bay_one.is_staircase_ready(),
		"the first bay's deduced exact category set creates a real inter-level stair")

	var purge = chunk.get_playthrough_interaction_target("purge_terminal")
	check(_physical_trigger(preview, purge, "aster")
			and chunk._purge_receiver.is_fixture_exposed(),
		"HACK PURGE consumes its terminal and exposes the physical iron fixture")
	var access = chunk.get_playthrough_interaction_target("spoof_terminal")
	check(str(access.get_effect()) == "authorize"
			and _physical_trigger(preview, access, "aster")
			and chunk._access_receiver.is_authorized(),
		"SPOOF LOCATION authorizes Aster's optional access instead of rerouting an enemy")
	check(chunk._emp_circuit.apply_emp(1.0)
			and str(chunk._emp_circuit.get_state().get("phase", "")) == "power_cut_open",
		"EMP fail-opens the explicitly electronic cutoff circuit")

	var snapshot: Dictionary = preview.build_save_snapshot()
	preview.apply_save_snapshot(_json_round_trip(snapshot))
	chunk.on_game_state_snapshot_restored()
	var restored: Dictionary = chunk.get_preview_state()
	check(bool((restored.get("drawer_bays", {}) as Dictionary).get(
			"drawer_bay_one", {}).get("staircase_ready", false))
			and str((restored.get("iron_purge", {}) as Dictionary).get("phase", ""))
				== "fixture_exposed"
			and str((restored.get("spoofed_access", {}) as Dictionary).get("phase", ""))
				== "tracked_access_authorized"
			and str((restored.get("emp_cutoff", {}) as Dictionary).get("phase", ""))
				== "power_cut_open",
		"one save/load reconstructs drawer, iron, access, and EMP physical truth")

	await _discard(preview)
	_finish()


func _physical_trigger(preview: Node, target: Node, actor: String) -> bool:
	if target == null or not is_instance_valid(target) \
			or not target.has_method("_trigger") or not (target is Node3D):
		return false
	var gs: GameState = preview._game_state
	preview.headless_select_character(actor)
	gs.command_stop(actor)
	preview.headless_set_character_position(actor, (target as Node3D).global_position)
	gs.command_stop(actor)
	target.set("active_character", actor)
	return bool(target.call("_trigger", false))


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.has_method("_teardown_sequence"):
			node.call("_teardown_sequence")
		node.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	print("OPEN FILES CHUNK SMOKE: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
