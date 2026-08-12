extends SceneTree

## Focused regression for the generated data-layer solution executor.
## The solver may advance deterministic scheduler time, but it must express travel
## and set-piece progress through the same authoritative commands/callbacks as play.
## Run from the Godot project root:
##   ../Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##     --script res://tools/verify_generated_solution_physical_execution.gd

const CHUNK_SCENE := preload("res://scenes/fragments/chunks/generated_stretch_chunk.tscn")
const Catalog := preload("res://scripts/generation/stretch_spec_catalog.gd")
const BRANCH_INTERACTION_LIMIT := 2.25
const EPSILON := 0.001


class PhysicalSolutionHost:
	extends ChunkHostStub

	func emphasize_preview_target(
		_target: Node3D, _duration := 0.9, _pause_gameplay := false, _opts: Dictionary = {}
	) -> bool:
		return true

	func get_preview_character_stat(char_id: String, stat_name: String) -> float:
		return game_state.get_stat(char_id, stat_name)

	func set_preview_character_stat(char_id: String, stat_name: String, value: float) -> void:
		game_state.set_stat(char_id, stat_name, value)

	func adjust_preview_character_stat(char_id: String, stat_name: String, delta: float) -> void:
		game_state.adjust_stat(char_id, stat_name, delta)


var failures: Array[String] = []
var checks := 0
var branch_activation_samples: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	EventLog.print_events = false
	print("\n=== Generated solution physical execution ===")
	var host := PhysicalSolutionHost.new()
	host.setup()
	root.add_child(host)
	var chunk := CHUNK_SCENE.instantiate()
	chunk.configure_chunk({
		"spec_path": Catalog.teaching_path(),
		"game_mode": "neutral",
		"food_test": "neutral",
	})
	host.register_party(chunk.get_spawn_positions())
	chunk.attach_chunk_host(host, "generated_stretch")
	host.add_child(chunk)
	for _frame in range(4):
		await process_frame
	host.grid = GridWorld.from_data(chunk.call("get_grid_data"))
	host.game_state.grid = host.grid
	chunk.call("on_game_state_grid_ready")
	chunk.reset_preview_state()
	await process_frame

	var spans_v: Variant = chunk.get("_branch_span_producers")
	var spans: Array = spans_v as Array if spans_v is Array else []
	for span_v in spans:
		if span_v is BranchSpanProducer:
			var span := span_v as BranchSpanProducer
			span.extension_started.connect(_on_branch_extension_started.bind(host))

	var solution: Dictionary = chunk.call("get_solution_script")
	var branch_actions: Array = solution.get("branch_actions", [])
	check(
		not bool(chunk.call("activate_generated_node", "node_02", "aster"))
		and not bool(chunk.call("choose_generated_route", "main_00_01", false)),
		"public consequence and semantic-route helpers cannot advance the solution"
	)
	host.game_state.event_log = EventLog.new()
	branch_activation_samples.clear()
	var result: Dictionary = chunk.call("replay_generated_solution")
	host.game_state.flush_tick()
	if not bool(result.get("complete", false)):
		print(
			"  SOLUTION DIAGNOSTIC result=%s last=%s"
			% [
				JSON.stringify(result),
				str(chunk.call("get_preview_state").get("last_outcome", "")),
			]
		)

	verify_solution_result(result)
	verify_event_trace(host.game_state.event_log, solution, chunk, host.grid)
	verify_branch_ranges(branch_actions)

	host.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("\nGENERATED SOLUTION PHYSICAL EXECUTION PASS (%d checks)" % checks)
		quit(0)
	else:
		print(
			"\nGENERATED SOLUTION PHYSICAL EXECUTION FAIL (%d/%d failed)"
			% [failures.size(), checks]
		)
		quit(1)


func _on_branch_extension_started(
	_mechanism_id: StringName, state: Dictionary, host: PhysicalSolutionHost
) -> void:
	var phase: Dictionary = state.get("authoritative_phase", {})
	var metadata: Dictionary = phase.get("metadata", {})
	var actor := str(metadata.get("activated_by", ""))
	var producer: Vector3 = state.get("producer_data_position", Vector3.INF)
	var actor_position: Vector3 = (
		host.game_state.get_position(actor)
		if host.game_state.characters.has(actor)
		else Vector3.INF
	)
	branch_activation_samples.append({
		"actor": actor,
		"producer": producer,
		"actor_position": actor_position,
		"distance": actor_position.distance_to(producer),
		"tick": float(host.scheduler.get_current_tick()),
	})
func verify_solution_result(result: Dictionary) -> void:
	check(bool(result.get("complete", false)), "the emitted solution still reaches shelter completion")
	check(
		(result.get("blocked", []) as Array).is_empty(),
		"the physical solution does not leave a generated node blocked"
	)
	check(
		int(result.get("approach_mismatches", -1)) == 0,
		"physical execution preserves every emitted puzzle approach"
	)


func verify_event_trace(log: EventLog, solution: Dictionary, chunk: Node, grid) -> void:
	var branch_actions: Array = solution.get("branch_actions", [])
	var snap_count := 0
	var moves: Array[Dictionary] = []
	var branch_phases: Array[Dictionary] = []
	var trigger_counts: Dictionary = {}
	for event_index in range(log.events.size()):
		var event: Dictionary = log.events[event_index]
		var kind: StringName = event.get("kind", &"")
		if kind == GameEvent.KIND_SNAP_POSITION:
			snap_count += 1
		elif kind == GameEvent.KIND_MOVE_TO_POS \
				or kind == GameEvent.KIND_MOVE_TO_CELL \
				or kind == GameEvent.KIND_MOVE_CROSS_LEVEL:
			var move := event.duplicate(true)
			move["event_index"] = event_index
			moves.append(move)
		elif kind == GameEvent.KIND_BEGIN_MECHANISM_PHASE:
			var payload: Dictionary = event.get("payload", {})
			var metadata: Dictionary = payload.get("metadata", {})
			if str(metadata.get("mechanism_type", "")) == "branch_span_producer":
				var phase_event := event.duplicate(true)
				phase_event["event_index"] = event_index
				branch_phases.append(phase_event)
		elif kind == GameEvent.KIND_TRIGGER_INTERACTABLE:
			var trigger_payload: Dictionary = event.get("payload", {})
			var source_id := str(trigger_payload.get("id", ""))
			trigger_counts[source_id] = int(trigger_counts.get(source_id, 0)) + 1

	check(snap_count == 0, "the solution event trace contains no SNAP_POSITION shortcut")
	check(
		moves.size() >= branch_actions.size() * 2,
		"movement commands record both legs of every mandatory branch detour"
	)
	check(
		branch_phases.size() == branch_actions.size(),
		"every emitted branch action starts one authoritative mechanism phase"
	)
	var expected_trigger_ids := _solution_interactable_ids(solution, chunk)
	var exact_interactable_receipts := (
		not expected_trigger_ids.is_empty()
		and trigger_counts.size() == expected_trigger_ids.size()
	)
	for source_id in expected_trigger_ids:
		exact_interactable_receipts = (
			exact_interactable_receipts
			and int(trigger_counts.get(source_id, 0)) == 1
		)
	if not exact_interactable_receipts:
		print(
			"  RECEIPT DIAGNOSTIC actual=%s expected=%s"
			% [JSON.stringify(trigger_counts), JSON.stringify(expected_trigger_ids)]
		)
	check(
		exact_interactable_receipts,
		"every emitted solution verb consumes exactly one expected physical Interactable receipt"
	)

	var all_phases_have_physical_legs := branch_phases.size() == branch_actions.size()
	for phase_event in branch_phases:
		var payload: Dictionary = phase_event.get("payload", {})
		var metadata: Dictionary = payload.get("metadata", {})
		var actor := str(metadata.get("activated_by", ""))
		var producer := GameEvent.arr_to_v3(metadata.get("producer_data_position", []))
		var phase_index := int(phase_event.get("event_index", -1))
		var phase_tick := float(phase_event.get("tick", -1.0))
		var end_tick := float(payload.get("end_tick", -1.0))
		var inbound: Dictionary = {}
		var outbound: Dictionary = {}
		for move_v in moves:
			var move := move_v as Dictionary
			var move_payload: Dictionary = move.get("payload", {})
			if str(move_payload.get("id", "")) != actor:
				continue
			var move_index := int(move.get("event_index", -1))
			if move_index < phase_index:
				var target := _move_destination(move_payload, grid)
				if target.is_finite() and target.distance_to(producer) <= EPSILON:
					inbound = move
			elif move_index > phase_index and outbound.is_empty():
				outbound = move
		var inbound_tick := float(inbound.get("tick", phase_tick))
		all_phases_have_physical_legs = all_phases_have_physical_legs \
			and not inbound.is_empty() and phase_tick > inbound_tick + EPSILON \
			and not outbound.is_empty() and float(outbound.get("tick", -1.0)) >= end_tick - EPSILON
	check(
		all_phases_have_physical_legs,
		"branch phases begin after an inbound path and return movement begins only after work completes"
	)


func _move_destination(move_payload: Dictionary, grid) -> Vector3:
	if move_payload.has("pos"):
		return GameEvent.arr_to_v3(move_payload.get("pos", []))
	var cell_arr: Array = move_payload.get("cell", [])
	if grid != null and cell_arr.size() >= 2:
		return grid.grid_to_world(
			Vector2i(int(cell_arr[0]), int(cell_arr[1])),
			int(move_payload.get("level", 0))
		)
	return Vector3.INF


func _solution_interactable_ids(solution: Dictionary, chunk: Node) -> Array[String]:
	var ids: Array[String] = []
	var node_interactables := chunk.get("_node_interactables") as Dictionary
	for action_v in solution.get("actions", []):
		if not (action_v is Dictionary):
			continue
		var node_id := str((action_v as Dictionary).get("node", ""))
		var source: Node = node_interactables.get(node_id, null)
		_append_interactable_id(ids, source)
	var spans := chunk.get("_branch_span_by_id") as Dictionary
	for action_v in solution.get("branch_actions", []):
		if not (action_v is Dictionary):
			continue
		var branch_id := str((action_v as Dictionary).get(
			"branch_id", (action_v as Dictionary).get("target", "")
		))
		var span: Variant = spans.get(branch_id, null)
		if span is BranchSpanProducer:
			_append_interactable_id(
				ids,
				(span as BranchSpanProducer).get_producer_interactable()
			)
	return ids


func _append_interactable_id(ids: Array[String], source: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	var source_id := str(source.get("data_id"))
	if source_id != "" and not ids.has(source_id):
		ids.append(source_id)


func verify_branch_ranges(branch_actions: Array) -> void:
	check(
		branch_activation_samples.size() == branch_actions.size(),
		"every mandatory branch activation was observed at its producer"
	)
	var all_in_range := branch_activation_samples.size() == branch_actions.size()
	for sample in branch_activation_samples:
		all_in_range = all_in_range \
			and float(sample.get("distance", INF)) <= BRANCH_INTERACTION_LIMIT + EPSILON
	check(all_in_range, "all branch work begins inside the authoritative interaction radius")


