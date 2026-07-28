extends SceneTree

## Campaign Rings used to hide Endo in a dialogue callback while leaving his canonical
## character record alive. This verifier proves that the visible walk is the gameplay state:
## it is locked, saveable at a midpoint, and retires Endo only at the authored junction.

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const DEADLINE_EPSILON := 0.001

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source = await _spawn_rings()
	if source == null:
		_finish()
		return
	var gs: GameState = source._game_state
	var scheduler: EventScheduler = source._scheduler
	var anchors: Dictionary = source.headless_get_anchor_positions()
	var departure_origin: Vector3 = anchors.get(
		"rings_marco", source.RINGS_START + Vector3(78.0, 0.5, -4.0))
	departure_origin += Vector3(-2.0, 0.0, 1.0)
	gs.set_party(["aster", "peris", "endo"])

	var absent_snapshot := _json_round_trip(source.build_save_snapshot())
	_erase_authority(absent_snapshot, source.rings_endo_departure_authority_key())
	_check(gs.characters.has("endo") and source._endo.visible,
		"campaign Rings begins with Endo present in canonical and rendered truth")
	source._start_rings_explore()
	_check(str(source._current_step) == "rings_client"
		and str(source._rings_endo_phase) == source.RINGS_ENDO_PHASE_PRESENT,
		"an endpoint helper cannot bypass the physical departure")
	var marco = source._rings_client_interactable
	_check(not source.trigger_rings_client(false),
		"the retired Rings compatibility helper is explicitly inert")
	source._on_act1_rings_client_interacted(marco, false)
	_check(not source._rings_client_seen
			and str(source._rings_endo_phase) == source.RINGS_ENDO_PHASE_PRESENT,
		"a direct named callback cannot impersonate Marco's post-trigger receipt")

	marco.active_character = "peris"
	marco.set_interaction_enabled(true)
	_check(not marco._trigger(false)
			and not marco._used and marco.is_interaction_enabled(),
		"remote Peris/Endo are rejected before Marco's one-shot is consumed")
	source.headless_set_character_position("endo", departure_origin)
	source.headless_set_character_position(
		"peris", departure_origin + Vector3(1.0, 0.0, -0.4))
	_check(marco._trigger(false),
		"the real Marco interactable accepts the gathered Peris/Endo conversation")
	var committed := gs.get_external_traversal_state("endo")
	var authority: Dictionary = gs.get_world_state(
		source.rings_endo_departure_authority_key(), {})
	_check(str(source._rings_endo_phase) == source.RINGS_ENDO_PHASE_DEPARTING
		and gs.is_external_traversal_active("endo")
		and StringName(str(committed.get("traversal_id", "")))
			== source.RINGS_ENDO_TRAVERSAL_ID,
		"Marco commits Endo to the shared locked external-traversal state")
	_check(str(authority.get("phase", "")) == source.RINGS_ENDO_PHASE_DEPARTING
		and int(authority.get("version", 0)) == source.RINGS_ENDO_AUTHORITY_VERSION
		and str(authority.get("reassignment_actor", "")) == "peris"
		and (authority.get("reassignment_positions", {}) as Dictionary).size() == 2
		and is_equal_approx(
			float(authority.get("deadline", -1.0)),
			float(committed.get("end_tick", -2.0))),
		"the versioned campaign record carries the traversal's exact deadline")
	_check(gs.characters.has("endo") and gs.get_party().has("endo") and source._endo.visible,
		"Endo remains present and in-party while the visible walk is in flight")
	_check(not gs.command_move_to_pos("endo", source.RINGS_ENDO_JUNCTION_POS),
		"ordinary movement cannot interrupt or skip Endo's locked departure")
	var route_renderer := PathRenderer.new()
	source.add_child(route_renderer)
	route_renderer.setup(gs, "endo", Color.WHITE)
	route_renderer._process(0.0)
	_check(route_renderer._line.mesh == null,
		"the ordinary route renderer safely ignores mechanism-owned traversals")
	route_renderer.queue_free()

	var initial_remaining := float(committed.get("remaining", 0.0))
	source.headless_advance(initial_remaining * 0.42, 0.1)
	var middle := gs.get_external_traversal_state("endo")
	var midpoint_position := gs.get_position("endo")
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var midpoint_tick := float(scheduler.get_current_tick())
	_check(float(middle.get("progress", 0.0)) > 0.0
		and float(middle.get("progress", 1.0)) < 1.0
		and midpoint_position.distance_to(departure_origin) > 0.1
		and midpoint_position.distance_to(source.RINGS_ENDO_JUNCTION_POS) > 0.1,
		"midpoint save observes Endo physically between the authored endpoints")

	var completion_count := {"value": 0}
	gs.external_traversal_finished.connect(
		func(char_id: String, traversal_id: StringName) -> void:
			if char_id == "endo" and traversal_id == source.RINGS_ENDO_TRAVERSAL_ID:
				completion_count.value = int(completion_count.value) + 1
	)
	_advance_to_departure_endpoint(source)
	_verify_departed_truth(source, completion_count, "uninterrupted")
	var completed_snapshot := _json_round_trip(source.build_save_snapshot())

	source.apply_save_snapshot(midpoint_snapshot)
	var events_before_repeat := _event_count(gs)
	source.on_game_state_snapshot_restored()
	var restored := gs.get_external_traversal_state("endo")
	_check(str(source._rings_endo_phase) == source.RINGS_ENDO_PHASE_DEPARTING
		and gs.characters.has("endo") and source._endo.visible
		and gs.is_external_traversal_active("endo"),
		"same-presenter rollback retracts the departed future and restores Endo in flight")
	_check(is_equal_approx(float(scheduler.get_current_tick()), midpoint_tick)
		and is_equal_approx(
			float(restored.get("progress", -1.0)),
			float(middle.get("progress", -2.0)))
		and gs.get_position("endo").distance_to(midpoint_position) < 0.01,
		"same-presenter rollback restores exact tick, progress, and midpoint position")
	_check(_event_count(gs) == events_before_repeat,
		"repeated campaign attachment emits no synthetic gameplay command")
	var same_count_before := int(completion_count.value)
	_advance_to_departure_endpoint(source)
	_check(int(completion_count.value) == same_count_before + 1,
		"same-presenter rollback consumes the saved completion exactly once")
	_verify_departed_truth(source, completion_count, "same-presenter")

	var fresh = await _spawn_rings()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		var fresh_gs: GameState = fresh._game_state
		var fresh_middle := fresh_gs.get_external_traversal_state("endo")
		_check(fresh_gs.is_external_traversal_active("endo")
			and fresh._endo.visible
			and is_equal_approx(
				float(fresh_middle.get("progress", -1.0)),
				float(middle.get("progress", -2.0))),
			"fresh campaign presenter attaches to the same saved in-flight Endo")
		var fresh_count := {"value": 0}
		fresh_gs.external_traversal_finished.connect(
			func(char_id: String, traversal_id: StringName) -> void:
				if char_id == "endo" and traversal_id == fresh.RINGS_ENDO_TRAVERSAL_ID:
					fresh_count.value = int(fresh_count.value) + 1
		)
		_advance_to_departure_endpoint(fresh)
		_verify_departed_truth(fresh, fresh_count, "fresh-presenter")
		_check(int(fresh_count.value) == 1,
			"fresh campaign presenter commits exactly one completion")
		await _discard(fresh)

	var completed = await _spawn_rings()
	if completed != null:
		completed.apply_save_snapshot(completed_snapshot)
		_verify_departed_truth(completed, {}, "completed-save")
		_check(not completed._game_state.is_external_traversal_active("endo"),
			"completed save cannot resurrect Endo or a departure timer")
		await _discard(completed)

	source.apply_save_snapshot(absent_snapshot)
	var absent_events_before := _event_count(gs)
	source.on_game_state_snapshot_restored()
	_check(str(source._rings_endo_phase) == source.RINGS_ENDO_PHASE_PRESENT
		and not source._rings_client_seen
		and gs.characters.has("endo") and source._endo.visible,
		"missing authority retracts every departure fact to the pre-interaction baseline")
	_check(gs.get_world_state(source.rings_endo_departure_authority_key(), null) == null
		and not gs.is_external_traversal_active("endo")
		and _event_count(gs) == absent_events_before,
		"absence stays absent and retains no callback or synthetic attachment command")
	source.headless_advance(initial_remaining * 2.0, 0.2)
	_check(gs.characters.has("endo") and source._endo.visible
		and str(source._rings_endo_phase) == source.RINGS_ENDO_PHASE_PRESENT,
		"discarded departure callbacks cannot grant the endpoint after rollback")

	await _discard(source)
	_finish()


func _advance_to_departure_endpoint(act1: Node) -> void:
	var gs: GameState = act1._game_state
	var traversal := gs.get_external_traversal_state("endo")
	var remaining := float(traversal.get("remaining", 0.0))
	act1.headless_advance(maxf(0.0, remaining - DEADLINE_EPSILON), 0.1)
	_check(gs.is_external_traversal_active("endo") and gs.characters.has("endo"),
		"Endo cannot retire before the saved physical deadline")
	act1.headless_advance(DEADLINE_EPSILON * 1.1, DEADLINE_EPSILON * 1.1)


func _verify_departed_truth(
		act1: Node, completion_count: Dictionary, label: String
	) -> void:
	var gs: GameState = act1._game_state
	var state: Dictionary = act1.headless_get_state().get("rings", {})
	_check(str(state.get("endo_phase", "")) == act1.RINGS_ENDO_PHASE_DEPARTED
		and str(act1._current_step) == "rings_explore",
		"%s endpoint commits departure and opens exploration" % label)
	_check(not gs.characters.has("endo") and not gs.get_party().has("endo"),
		"%s endpoint removes Endo from canonical presence and party" % label)
	_check(not act1._endo.visible,
		"%s endpoint removes Endo from rendered presence" % label)
	if not completion_count.is_empty():
		_check(int(completion_count.get("value", 0)) >= 1,
			"%s endpoint crossed the external-traversal callback" % label)


func _spawn_rings():
	var act1 = ACT1_SCENE.instantiate()
	act1.start_chunk = "rings"
	act1.suppress_scene_change = true
	root.add_child(act1)
	for _frame in range(12):
		await process_frame
	act1.set_process(false)
	act1.set_physics_process(false)
	act1.prepare_rings_fragment("client")
	_check(act1._game_state != null and act1._chunks.has("rings"),
		"Act 1 boots its production Rings chunk")
	return act1


func _erase_authority(snapshot: Dictionary, key: String) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	world_state.erase(key)
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _event_count(gs: GameState) -> int:
	return gs.event_log.size() if gs != null and gs.event_log != null else 0


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.has_method("_teardown_sequence"):
			node._teardown_sequence()
		node.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	print("ACT1 RINGS DEPARTURE AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)
