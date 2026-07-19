extends Node

## Focused campaign-host verification for the authored Rings route and Lockout chase.
##
## Run:
##   ../Godot_v4.7-stable_win64_console.exe --headless --path . \
##     res://tools/verify_act1_campaign_extensions.tscn

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const RINGS_TRACE_ORDER := ["client_bloom", "forget_me_not", "doorvine"]

var _failures := 0


func _ready() -> void:
	EventLog.print_events = false
	await get_tree().process_frame
	await _verify_rings_campaign_route()
	await _verify_lockout_campaign_handoff()
	_finish()


func _verify_rings_campaign_route() -> void:
	print("\n=== Act 1 Rings campaign route ===")
	var act1: Node = await _instantiate_act1("rings")
	if act1 == null:
		_fail("Rings Act 1 instance boots")
		return

	var rings_chunk: Node = act1.find_child("Chunk_rings", true, false)
	_expect(rings_chunk != null, "start_chunk=rings loads the campaign Rings chunk")
	_expect(act1.find_child("ClientNPC", true, false) != null, "former-client interactable is authored")
	for trace_id in RINGS_TRACE_ORDER:
		_expect(
			act1.find_child("RingsTrace_%s" % trace_id, true, false) != null,
			"trace interactable exists: %s" % trace_id
		)

	# Enter the first player-controlled gate without waiting through the opening conversation. Calls
	# below use the same trigger methods wired to the interactables, while private start methods only
	# replace dialogue time in this focused headless contract.
	act1.call("_start_rings_client")
	var state: Dictionary = act1.call("headless_get_state")
	_expect(str(state.get("current_step", "")) == "rings_client", "Rings begins at the former-client gate")
	_expect(not bool((state.get("rings", {}) as Dictionary).get("client_seen", false)), "former client starts unresolved")

	# No trace callback is allowed to skip the client gate.
	for trace_id in RINGS_TRACE_ORDER:
		act1.call("trigger_rings_trace", trace_id)
	state = act1.call("headless_get_state")
	_expect(_rings_trace_count(state) == 0, "all residential traces reject a pre-client skip")
	_expect(str(state.get("current_step", "")) == "rings_client", "pre-client trace attempts leave the client gate active")

	act1.call("trigger_rings_client", false)
	state = act1.call("headless_get_state")
	_expect(bool((state.get("rings", {}) as Dictionary).get("client_seen", false)), "former-client trigger resolves first")
	_expect(str(state.get("current_step", "")) == "endo_departs", "client resolution advances to Endo's departure")
	act1.call("trigger_rings_trace", RINGS_TRACE_ORDER[0])
	_expect(_rings_trace_count(act1.call("headless_get_state")) == 0, "a trace cannot skip Endo's departure beat")

	# Dialogue presentation is covered elsewhere. Start its authored first trace, then prove that every
	# future trace refuses until the current one is resolved.
	act1.call("_start_rings_trace", RINGS_TRACE_ORDER[0])
	for index in range(RINGS_TRACE_ORDER.size()):
		var expected_id: String = RINGS_TRACE_ORDER[index]
		state = act1.call("headless_get_state")
		_expect(
			str(state.get("current_step", "")) == "rings_trace_%s" % expected_id,
			"ordered trace gate is active: %s" % expected_id
		)

		for future_index in range(index + 1, RINGS_TRACE_ORDER.size()):
			act1.call("trigger_rings_trace", RINGS_TRACE_ORDER[future_index])
		state = act1.call("headless_get_state")
		_expect(
			_rings_trace_count(state) == index,
			"future traces cannot skip ahead of %s" % expected_id
		)

		act1.call("trigger_rings_trace", expected_id)
		state = act1.call("headless_get_state")
		_expect(
			bool(_rings_trace_seen(state).get(expected_id, false)),
			"current trace resolves: %s" % expected_id
		)
		_expect(_rings_trace_count(state) == index + 1, "exactly one trace resolves at gate %d" % (index + 1))
		act1.call("headless_advance", 0.25, 0.05)

	state = act1.call("headless_get_state")
	_expect(
		str(state.get("current_step", "")) == "rings_residence_survey",
		"third ordered trace releases the occupied-residence fieldwork"
	)
	_expect(_rings_trace_count(state) == RINGS_TRACE_ORDER.size(), "all three traces are recorded exactly once")
	for trace_id in RINGS_TRACE_ORDER:
		_expect(bool(_rings_trace_seen(state).get(trace_id, false)), "completion records %s" % trace_id)

	# The route now earns its exploration handoff through two player-controlled field operations.
	# Drive the same Interactable signals and specialist gates that normal play uses, choosing a
	# different valid branch in each operation so this shared campaign check covers both outcomes.
	_drive_rings_field_operation(act1, "residence", 0)
	state = act1.call("headless_get_state")
	_expect(str(state.get("current_step", "")) == "rings_boundary_commit", "residence execution opens the boundary handoff")
	_drive_rings_field_operation(act1, "boundary", 1)
	state = act1.call("headless_get_state")
	_expect(str(state.get("current_step", "")) == "rings_explore", "both Rings field operations release exploration")
	var field_state: Dictionary = (state.get("rings", {}) as Dictionary).get("fieldwork", {})
	_expect(int(field_state.get("operation_count", 0)) == 2, "both Rings field operations persist")
	_expect(int(field_state.get("decision_count", 0)) == 2, "both Rings branch decisions persist")

	await _dispose_act1(act1)


func _drive_rings_field_operation(act1: Node, operation_id: String, choice_index: int) -> void:
	var operations: Dictionary = act1.RINGS_FIELD_OPERATIONS
	var specs: Dictionary = act1.RINGS_FIELD_SITES
	var site_nodes: Dictionary = act1.get("_rings_field_sites")
	var operation: Dictionary = operations[operation_id]
	for evidence_id_variant in operation.get("evidence", []):
		var evidence_id := str(evidence_id_variant)
		var evidence_spec: Dictionary = specs[evidence_id]
		act1.call("headless_select_character", str(evidence_spec.get("role", "")))
		site_nodes[evidence_id].call("_trigger", false)
	var choices: Array = operation.get("choices", [])
	var choice_id := str(choices[clampi(choice_index, 0, choices.size() - 1)])
	var choice_spec: Dictionary = specs[choice_id]
	act1.call("headless_select_character", str(choice_spec.get("role", "")))
	site_nodes[choice_id].call("_trigger", false)
	var resolution_id := str((operation.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
	var resolution_spec: Dictionary = specs[resolution_id]
	act1.call("headless_select_character", str(resolution_spec.get("role", "")))
	site_nodes[resolution_id].call("_trigger", false)


func _verify_lockout_campaign_handoff() -> void:
	print("\n=== Act 1 Lockout campaign handoff ===")
	var act1: Node = await _instantiate_act1("lockout")
	if act1 == null:
		_fail("Lockout Act 1 instance boots")
		return

	var chunks_variant: Variant = act1.get("_chunks")
	var chunks: Dictionary = chunks_variant if chunks_variant is Dictionary else {}
	var chase: Node = chunks.get("lockout_chase_campaign") as Node
	_expect(chase != null and is_instance_valid(chase), "campaign loads lockout_chase_campaign")
	if chase == null or not is_instance_valid(chase):
		await _dispose_act1(act1)
		return

	_expect(
		chase.scene_file_path == "res://scenes/fragments/chunks/lockout_chase_chunk.tscn",
		"campaign chunk is the authored Lockout chase scene"
	)
	var grid_data: Dictionary = chase.call("get_grid_data")
	var game_state: Variant = act1.get("_game_state")
	var live_grid: Variant = game_state.grid if game_state != null else null
	_expect(not grid_data.is_empty(), "Lockout chase publishes its carved local grid")
	_expect(live_grid != null, "Act 1 adopts a live Lockout grid")
	if live_grid != null and not grid_data.is_empty():
		_expect(int(live_grid.width) == int(grid_data.get("width", -1)), "live grid width matches the chase grid")
		_expect(int(live_grid.height) == int(grid_data.get("height", -1)), "live grid height matches the chase grid")
		_expect(absf(float(live_grid.cell_size) - float(grid_data.get("cell_size", -1.0))) < 0.001, "live grid cell size matches the chase grid")

	var spawns: Dictionary = chase.call("get_spawn_positions")
	for char_id in ["aster", "peris"]:
		var spawn: Vector3 = spawns.get(char_id, Vector3.INF)
		var actual: Vector3 = act1.call("get_preview_character_position", char_id)
		_expect(actual.distance_to(spawn) < 0.05, "%s spawns on the chase's local course" % char_id.capitalize())
		if live_grid != null:
			var cell: Vector2i = live_grid.world_to_grid(actual)
			_expect(bool(live_grid.is_walkable(cell.x, cell.y)), "%s spawn is on a walkable chase cell" % char_id.capitalize())

	var chase_state: Dictionary = chase.call("get_preview_state")
	_expect(not bool(chase_state.get("chase_started", false)), "Lockout is quiet before the boundary scan")
	_expect(not bool(chase_state.get("pursuit_armed", false)), "pursuit is unarmed before rejection")
	_expect(str((act1.call("headless_get_state") as Dictionary).get("current_step", "")) == "lockout_approach", "campaign owns the pre-scan approach beat")

	var scanner: Node = chase.find_child("BoundaryScanner", true, false)
	_expect(scanner != null, "boundary scanner exists in the campaign-hosted chase")
	if scanner != null:
		scanner.set("active_character", "aster")
		scanner.call("_trigger")
	chase_state = chase.call("get_preview_state")
	var campaign_state: Dictionary = act1.call("headless_get_state")
	_expect(bool(chase_state.get("chase_started", false)), "scanner rejection marks the chase started")
	_expect(not bool(chase_state.get("pursuit_armed", false)), "scanner rejection defers pursuit to the Act 1 beat")
	_expect(str(campaign_state.get("current_step", "")) == "lockout_rejected", "rejection hands narrative control to Act 1")
	_expect(int(chase_state.get("pursuers", 0)) == 0, "deferred rejection spawns no early pursuit wave")

	act1.call("_start_lockout_chase")
	chase_state = chase.call("get_preview_state")
	campaign_state = act1.call("headless_get_state")
	_expect(bool(chase_state.get("pursuit_armed", false)), "Act 1's chase beat arms the authored pursuit")
	_expect(str(campaign_state.get("current_step", "")) == "lockout_chase", "campaign enters lockout_chase")

	# The wall completion remains pair-gated in campaign. Exercise the real shelter interactable so
	# its rejected one-shot reset and accepted completion path both run.
	var wall_x := float(chase.get("WALL_X"))
	act1.call("set_preview_character_position", "aster", Vector3(wall_x + 2.0, 0.5, 0.0))
	act1.call("set_preview_character_position", "peris", spawns.get("peris", Vector3.ZERO))
	var wall_rest: Node = chase.find_child("EndoWall", true, false)
	_expect(wall_rest != null, "Endo's wall rest exists in the hosted chase")
	if wall_rest != null:
		wall_rest.set("active_character", "aster")
		wall_rest.call("_trigger")
	_expect(not bool((chase.call("get_preview_state") as Dictionary).get("complete", false)), "one runner at Endo's wall cannot complete the chase")

	act1.call("set_preview_character_position", "peris", Vector3(wall_x + 2.0, 0.5, 1.5))
	if wall_rest != null:
		wall_rest.set("active_character", "aster")
		wall_rest.call("_trigger")
	_expect(bool((chase.call("get_preview_state") as Dictionary).get("complete", false)), "both runners at Endo's wall complete the authored chase")
	act1.call("headless_advance", 0.1, 0.05)
	campaign_state = act1.call("headless_get_state")
	_expect(str(campaign_state.get("current_step", "")) == "lockout_exile", "wall completion hands campaign control to lockout_exile")
	_expect(not bool((campaign_state.get("lockout", {}) as Dictionary).get("campaign_chase_active", true)), "campaign chase polling disarms after the handoff")

	await _dispose_act1(act1)


func _instantiate_act1(start_chunk: String) -> Node:
	var instance: Node = ACT1_SCENE.instantiate()
	instance.set("start_chunk", start_chunk)
	instance.set("suppress_scene_change", true)
	get_tree().root.add_child(instance)
	for _frame in range(8):
		await get_tree().process_frame
	return instance


func _dispose_act1(instance: Node) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if instance.has_method("_teardown_sequence"):
		instance.call("_teardown_sequence")
	instance.queue_free()
	await get_tree().process_frame


func _rings_trace_seen(state: Dictionary) -> Dictionary:
	var rings_variant: Variant = state.get("rings", {})
	var rings: Dictionary = rings_variant if rings_variant is Dictionary else {}
	var seen_variant: Variant = rings.get("trace_seen", {})
	return seen_variant if seen_variant is Dictionary else {}


func _rings_trace_count(state: Dictionary) -> int:
	var rings_variant: Variant = state.get("rings", {})
	if not rings_variant is Dictionary:
		return -1
	return int((rings_variant as Dictionary).get("trace_count", -1))


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	_fail(label)


func _fail(label: String, detail: Variant = null) -> void:
	_failures += 1
	if detail == null:
		push_error("[FAIL] %s" % label)
	else:
		push_error("[FAIL] %s | %s" % [label, str(detail)])


func _finish() -> void:
	if _failures == 0:
		print("\nACT 1 CAMPAIGN EXTENSIONS: PASS")
		get_tree().quit(0)
	else:
		push_error("\nACT 1 CAMPAIGN EXTENSIONS: FAIL (%d checks)" % _failures)
		get_tree().quit(1)
