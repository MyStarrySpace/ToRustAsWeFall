extends SceneTree

## Focused structural and active-play verification for the extended Elevator /
## Below route. Run with:
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


func _decoration_audit(chunk: Node) -> Dictionary:
	if chunk == null:
		return {}
	var decoration := chunk.get_node_or_null("LevelDecoration")
	if decoration == null:
		return {}
	return decoration.get_meta("decoration_audit", {}) as Dictionary


func _trigger_as(interactable: Node, character_id: String) -> void:
	interactable.set("active_character", character_id)
	interactable.call("_trigger")
	await process_frame


func _place_party(sequence: Node, pos: Vector3, z_spread := 0.8) -> void:
	sequence.set_preview_character_position("aster", pos + Vector3(0, 0.5, -z_spread * 0.5))
	sequence.set_preview_character_position("peris", pos + Vector3(-0.7, 0.5, z_spread * 0.5))


func _run() -> void:
	DialogueData.load_dir("res://data/dialogue/en/")
	# Load after autoload initialization. Direct preload occurs while the --script
	# runner is still compiling and is too early for singleton-backed UI scripts.
	var packed := load("res://scenes/tutorial/elevator.tscn") as PackedScene
	_check(packed != null, "Elevator scene loads")
	if packed == null:
		_finish()
		return
	var sequence: Node = packed.instantiate()
	sequence.set("suppress_scene_change", true)
	root.add_child(sequence)
	for _frame in range(6):
		await process_frame
	sequence._scheduler.clear()
	for character_id in ["aster", "peris"]:
		sequence._game_state.set_character_level(character_id, sequence.LEVEL_LOWER)
		sequence.set_preview_character_position(character_id,
			Vector3(sequence.BRIDGE_COLLAPSE_X, sequence.BELOW_Y + 0.5, 0.0))

	# The pacing contract makes the requested duration explicit while prohibiting
	# idle locks as a way to manufacture that duration.
	var contract: Dictionary = sequence.get_playtime_contract()
	_check(float(contract.get("required_first_clear_seconds", 0.0)) == 480.0,
		"the first-clear contract explicitly requires eight minutes")
	_check(float(contract.get("target_max_seconds", 0.0)) == 720.0,
		"the authored upper target is twelve minutes")
	_check(float(contract.get("modeled_first_clear_seconds", 0.0)) >= 480.0
		and float(contract.get("modeled_first_clear_seconds", 9999.0)) <= 720.0,
		"the evidence model falls inside the eight-to-twelve-minute band")
	_check(float(contract.get("modeled_meaningful_active_seconds", 0.0)) >= 480.0,
		"at least eight modeled minutes are meaningful active play")
	_check(float(contract.get("meaningful_active_ratio", 0.0)) >= 0.70,
		"meaningful play clears the canonical 70% active ratio")
	_check(float(contract.get("critical_route_meters", 0.0)) >= 190.0,
		"the critical route contains a materially long controlled traversal")
	_check(int(contract.get("decision_count", 0)) >= 7
		and int(contract.get("branch_count", 0)) >= 14,
		"route, preparation, relay, and three annex plans expose real branches")
	_check(float(contract.get("hard_idle_lock_seconds", -1.0)) == 0.0,
		"no added playtime can be earned by waiting")
	var manifest_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/pacing/level_targets.json"))
	var target: Dictionary = LevelPacingContract.target_by_id(
		manifest_variant as Dictionary if manifest_variant is Dictionary else {},
		"elevator_and_below")
	var pacing_report := LevelPacingContract.analyze(target, contract)
	_check(bool(pacing_report.get("passed", false)),
		"the central pacing analyzer accepts the full Elevator contract (%s)" %
		str(pacing_report.get("errors", [])))

	# Below: dual-character route read, three deterministic beats, and collision-
	# free authored dressing.
	var below: Node = sequence._load_chunk("below")
	await process_frame
	var below_audit := _decoration_audit(below)
	_check(not below_audit.is_empty(), "Below route has an authored decoration audit")
	_check(int(below_audit.get("collision_shapes", -1)) == 0
		and str(below_audit.get("clearance", "")) == "surface_only_no_obstacles",
		"Below dressing is explicitly collision-free")
	_check(int(below_audit.get("instances", 0)) >= 80,
		"Below dressing establishes a repeated authored facade hierarchy")
	_check(below.find_children("RouteIronField*", "MeshInstance3D", true, false).size() == 3,
		"the iron lane exposes three distinct deterministic hazard fields")
	_check(sequence._route_flure_interactables.size() == 3,
		"the green lane exposes one Flure station per course beat")
	_check(sequence._route_flure_enemy_groups.size() == 3,
		"each green-lane station owns an independent enemy pack")
	for beat_index in range(3):
		_check((sequence._route_flure_enemy_groups.get(beat_index, []) as Array).size() == 2,
			"route beat %d owns exactly two deterministic enemies" % (beat_index + 1))

	var read_aster: Node = below.find_child("RouteReadAster", true, false)
	var read_peris: Node = below.find_child("RouteReadPeris", true, false)
	_check(read_aster != null and read_peris != null,
		"Aster and Peris have separate spatial route-read stations")
	if read_aster == null or read_peris == null:
		await _dispose(sequence)
		_finish()
		return
	_check(str(read_aster.get("required_character")) == "aster"
		and str(read_peris.get("required_character")) == "peris",
		"each route read is data-authorized to its intended character")
	sequence._start_route_read_circuit()
	sequence._dialogue.clear()
	await _trigger_as(read_aster, "peris")
	_check(int(sequence.headless_get_state().get("route_read_count", -1)) == 0,
		"the wrong perspective cannot satisfy Aster's route read")
	await _trigger_as(read_aster, "aster")
	sequence._dialogue.clear()
	await _trigger_as(read_peris, "peris")
	sequence._dialogue.clear()
	sequence.headless_advance(0.6, 0.05)
	var state: Dictionary = sequence.headless_get_state()
	_check(int(state.get("route_read_count", 0)) == 2
		and str(state.get("current_step", "")) == "route_choice",
		"both character reads are mandatory before route commitment")

	var route_flure: Node = sequence._route_flure_interactables[0]
	await _trigger_as(route_flure, "aster")
	_check(not bool((sequence.headless_get_state()["route_flures_activated"] as Array)[0]),
		"Aster cannot fire Peris's route Flure")
	await _trigger_as(route_flure, "peris")
	_check(bool((sequence.headless_get_state()["route_flures_activated"] as Array)[0]),
		"Peris can redirect the first route pack")
	_check((sequence._route_flure_enemy_groups[0] as Array)[0]._detection_targets.is_empty(),
		"a primed route Flure removes its pack from party targeting")

	# Cross all three spatial beats in the green lane. This proves progress is
	# movement-earned rather than scheduler-earned.
	for beat_index in range(3):
		var beat_x: float = sequence.FORK_POS.x + float(sequence.ROUTE_BEAT_OFFSETS[beat_index]) + 6.4
		_place_party(sequence, Vector3(beat_x, sequence.BELOW_Y, -4.0))
		sequence._on_process(0.01, 1.0)
	state = sequence.headless_get_state()
	_check(str(state.get("route_lane", "")) == "flure",
		"spatial course position records the chosen green lane")
	_check((state.get("route_beats_crossed", []) as Array).count(true) == 3,
		"all three separated route beats are movement-gated")

	# Orange fields are gameplay hazard, not decoration-only paint.
	var hp_before_iron: float = sequence._game_state.get_stat("aster", "hp")
	var iron_x: float = sequence.FORK_POS.x + float(sequence.ROUTE_BEAT_OFFSETS[1])
	sequence.set_preview_character_position("aster", Vector3(iron_x, sequence.BELOW_Y + 0.5, 3.3))
	sequence._on_process(0.5, 1.0)
	_check(sequence._game_state.get_stat("aster", "hp") < hp_before_iron,
		"crossing an orange iron field changes authoritative party HP")

	# Junction: three different stations, both character perspectives, then one
	# preparation choice before the plant can advance the story.
	sequence._start_junction_arrive()
	await process_frame
	_check(sequence._junction_interactables.size() >= 6,
		"Endo's shelter retains a broad set of distinct inspection stations")
	var plant: Node = sequence._junction_plant_interactable
	_check(plant != null and not bool(plant.get("interaction_enabled")),
		"the dormant plant starts locked behind the active survey")
	var survey_plan := [
		{"label": "Workbench", "character": "aster"},
		{"label": "Monitor", "character": "peris"},
		{"label": "Food", "character": "peris"},
	]
	for item in survey_plan:
		await _trigger_as(sequence._junction_interactables[item["label"]], item["character"])
		sequence._dialogue.clear()
	state = sequence.headless_get_state()
	_check(int(state.get("junction_inspection_count", 0)) == 3,
		"three distinct shelter inspections satisfy the spatial survey")
	_check(bool((state["junction_inspected_by"] as Dictionary).get("aster", false))
		and bool((state["junction_inspected_by"] as Dictionary).get("peris", false)),
		"the shelter survey records both character perspectives")
	_check(bool(state.get("junction_survey_ready", false)),
		"the junction exposes a stable survey-ready state")
	var recover: Node = sequence._junction_prep_interactables.get("recover")
	var scout: Node = sequence._junction_prep_interactables.get("scout")
	_check(recover != null and scout != null
		and bool(recover.get("interaction_enabled")) and bool(scout.get("interaction_enabled")),
		"survey completion unlocks the recover-versus-scout preparation branch")
	await _trigger_as(scout, "peris")
	state = sequence.headless_get_state()
	_check(str(state.get("junction_preparation", "")) == "scout"
		and float(state.get("gauntlet_safe_window_bonus", 0.0)) == 6.0,
		"SCOUT commits a real longer relay window")
	_check(not bool(state.get("junction_plant_unlocked", false))
		and str(state.get("junction_field_protocol", "")) == "descent_power",
		"preparation opens the annex instead of skipping directly to the plant")

	# The service annex contributes 162 seconds of authored work: three distinct protocols,
	# four specialist reads each, then one of two plans and its branch-specific execution.
	_check(sequence._junction_field_interactables.size() == 24,
		"the annex builds twelve reads, six plans, and six branch executions")
	for site_id_variant in sequence.JUNCTION_FIELD_SITES.keys():
		var site_id := str(site_id_variant)
		var spec: Dictionary = sequence.JUNCTION_FIELD_SITES[site_id]
		var site: Node = sequence._junction_field_interactables.get(site_id)
		_check(site != null and int(site.get("interactable_type")) == int(Interactable.InteractableType.TIMED_ACTION),
			"%s is a click-gated timed field station" % site_id)
		_check(site != null and str(site.get("required_character")) == str(spec.get("role", "")),
			"%s is authoritative to its named specialist" % site_id)
		_check(site != null and absf(float(site.get("dwell_time")) - float(spec.get("dwell", 0.0))) < 0.01,
			"%s preserves its authored work duration" % site_id)

	for protocol_id_variant in sequence.JUNCTION_FIELD_PROTOCOL_ORDER:
		var protocol_id := str(protocol_id_variant)
		var protocol: Dictionary = sequence.JUNCTION_FIELD_PROTOCOLS[protocol_id]
		for choice_variant in protocol.get("choices", []):
			_check(not bool(sequence._junction_field_interactables[str(choice_variant)].get("interaction_enabled")),
				"%s planning stays locked until all four reads" % protocol_id)
		var first_evidence_id := str((protocol.get("evidence", []) as Array)[0])
		var first_spec: Dictionary = sequence.JUNCTION_FIELD_SITES[first_evidence_id]
		var wrong_role := "peris" if str(first_spec.get("role", "")) == "aster" else "aster"
		await _trigger_as(sequence._junction_field_interactables[first_evidence_id], wrong_role)
		state = sequence.headless_get_state()
		_check(not bool(((state.get("junction_field_evidence", {}) as Dictionary).get(protocol_id, {}) as Dictionary).get(first_evidence_id, false)),
			"%s rejects the wrong specialist" % first_evidence_id)
		for evidence_variant in protocol.get("evidence", []):
			var evidence_id := str(evidence_variant)
			var evidence_spec: Dictionary = sequence.JUNCTION_FIELD_SITES[evidence_id]
			await _trigger_as(sequence._junction_field_interactables[evidence_id], str(evidence_spec.get("role", "")))
			sequence._dialogue.clear()
		for choice_variant in protocol.get("choices", []):
			_check(bool(sequence._junction_field_interactables[str(choice_variant)].get("interaction_enabled")),
				"%s exposes both valid plans after evidence" % protocol_id)
		var choice_id := str((protocol.get("choices", []) as Array)[0])
		var choice_spec: Dictionary = sequence.JUNCTION_FIELD_SITES[choice_id]
		await _trigger_as(sequence._junction_field_interactables[choice_id], str(choice_spec.get("role", "")))
		var resolution_id := str((protocol.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
		_check(bool(sequence._junction_field_interactables[resolution_id].get("interaction_enabled")),
			"%s requires its chosen spatial execution" % protocol_id)
		var resolution_spec: Dictionary = sequence.JUNCTION_FIELD_SITES[resolution_id]
		await _trigger_as(sequence._junction_field_interactables[resolution_id], str(resolution_spec.get("role", "")))
		sequence._dialogue.clear()

	state = sequence.headless_get_state()
	_check(int(state.get("junction_field_completed_count", 0)) == 3
		and bool(state.get("junction_fieldwork_complete", false)),
		"all three annex protocols independently gate completion")
	_check((state.get("junction_field_findings", []) as Array).size() == 18,
		"clean fieldwork records twelve reads, three plans, and three executions")
	_check(bool(state.get("junction_plant_unlocked", false)),
		"only completed annex fieldwork unlocks the dormant plant transition")

	# Gauntlet: two independently armed packs, second station gated by a refuge,
	# safe-versus-fast strategy state, and a real midpoint reset.
	sequence._dialogue.clear()
	sequence._start_gauntlet()
	await process_frame
	sequence._dialogue.clear()
	sequence._finish_gauntlet_intro()
	var gauntlet: Node = sequence._chunks.get("gauntlet")
	var gauntlet_audit := _decoration_audit(gauntlet)
	_check(not gauntlet_audit.is_empty()
		and int(gauntlet_audit.get("collision_shapes", -1)) == 0,
		"gauntlet dressing is authored and collision-free")
	_check(sequence._gauntlet_flure_interactables.size() == 2
		and sequence._gauntlet_flure_meshes.size() == 2,
		"two visible Flure relay stations exist")
	_check(sequence._gauntlet_enemies.size() == 5
		and (sequence._gauntlet_enemy_groups[0] as Array).size() == 3
		and (sequence._gauntlet_enemy_groups[1] as Array).size() == 2,
		"the five enemies are divided into deterministic three/two stages")
	_check(not bool(sequence._gauntlet_flure_interactables[1].get("interaction_enabled")),
		"stage two remains locked before the midpoint refuge")

	# First prove the fast state is real, then rewind this tiny branch probe and
	# execute the safe relay path end-to-end.
	sequence._reach_gauntlet_midpoint()
	_check(str(sequence.headless_get_state().get("gauntlet_strategy", "")) == "fast_direct",
		"reaching the refuge without firing stage one records FAST DIRECT")
	sequence._gauntlet_midpoint_reached = false
	sequence._gauntlet_stage = 0
	sequence._gauntlet_strategy = ""
	sequence._gauntlet_flure_interactables[1].set_interaction_enabled(false)
	for enemy in sequence._gauntlet_enemy_groups[1]:
		enemy._detection_targets.clear()

	var flure_1: Node = sequence._gauntlet_flure_interactables[0]
	var flure_2: Node = sequence._gauntlet_flure_interactables[1]
	await _trigger_as(flure_1, "peris")
	sequence._dialogue.clear()
	_check(bool((sequence.headless_get_state()["gauntlet_flure_active"] as Dictionary).get(0, false)),
		"stage-one Flure activates through Peris")
	_place_party(sequence, sequence.GAUNTLET_MIDPOINT)
	sequence._on_process(0.01, 1.0)
	state = sequence.headless_get_state()
	_check(bool(state.get("gauntlet_midpoint_reached", false))
		and str(state.get("gauntlet_strategy", "")) == "safe_relay",
		"firing stage one before the refuge records SAFE RELAY")
	_check(bool(flure_2.get("interaction_enabled")),
		"the midpoint refuge arms stage two and its second Flure")
	await _trigger_as(flure_2, "peris")
	_check(bool((sequence.headless_get_state()["gauntlet_flure_active"] as Dictionary).get(1, false)),
		"stage-two Flure independently redirects the second pack")

	sequence._on_enemy_hit("aster", 1.0)
	sequence.headless_advance(0.6, 0.05)
	state = sequence.headless_get_state()
	_check(int(state.get("gauntlet_reset_count", 0)) == 1,
		"a gauntlet hit produces one deterministic refuge reset")
	var reset_pos: Vector3 = sequence._game_state.get_position("aster")
	_check(absf(reset_pos.x - sequence.GAUNTLET_MIDPOINT.x) < 2.0,
		"stage-two failure returns the party to the midpoint, not the beginning")
	_place_party(sequence, sequence.GAUNTLET_EXIT + Vector3(0.5, 0, 0))
	sequence._on_process(0.01, 1.0)
	_check(str(sequence.headless_get_state().get("current_step", "")) == "complete",
		"crossing the second stage's exit completes the playable Elevator sequence")

	await _dispose(sequence)
	_finish()


func _dispose(sequence: Node) -> void:
	if is_instance_valid(sequence):
		sequence.queue_free()
	await process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("Elevator quality extension verification: ALL PASSED")
		quit(0)
	else:
		print("Elevator quality extension verification: %d FAILED" % _failures.size())
		quit(1)
