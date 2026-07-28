extends SceneTree

## Focused proof for BranchSpanProducer: the mandatory route is genuinely blocked until a logged,
## scheduler-owned extension completes, including save/load and replay reconstruction at midpoint.

const BranchSpanScript := preload("res://scripts/game/objects/branch_span_producer.gd")
const MECHANISM_ID := &"verify_mandatory_branch_span"
const BLOCKER_TAG := "verify_branch_span_gap"
const DURATION := 4.0

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := _make_corridor_grid()
	var scheduler := EventScheduler.new()
	var log := EventLog.new()
	var gs := GameState.new()
	gs.scheduler = scheduler
	gs.event_log = log
	gs.grid = grid

	var start_cell := Vector2i(1, 2)
	var end_cell := Vector2i(7, 2)
	var blocker_cell := Vector2i(4, 2)
	var producer_data := grid.grid_to_world(Vector2i(2, 2))
	var producer_render := Vector3(-5.0, 0.0, 7.0)
	var span_start := Vector3(10.0, 0.35, -2.0)
	var span_end := Vector3(14.0, 0.35, -2.0)
	gs.register_character("aster", grid.grid_to_world(start_cell), 3.0,
		{"hp": 100.0, "narrative_available": true})
	gs.register_character("peris", grid.grid_to_world(end_cell), 3.0,
		{"hp": 100.0, "narrative_available": true})

	var span = BranchSpanScript.new()
	check(span.configure(
		gs, scheduler, producer_data, producer_render, span_start, span_end,
		[blocker_cell], _options()),
		"configures explicit producer, span, blocker, timing, and stable ids")
	root.add_child(span)
	await process_frame
	await process_frame

	var initial: Dictionary = span.get_state()
	check(str(initial.get("contract", "")) == "branch_span_producer/v1"
			and initial.get("phase") == &"dormant",
		"absent authoritative phase reads as dormant")
	check(initial.get("bridge_visual_source") == "res://resources/models/elevator/bridge.glb"
			and _visible_mesh_count(span.get("_span_model")) > 0,
		"physical span reuses the external UV-mapped BridgeCargoScene model")
	check(initial.get("producer_visual_source") ==
			"res://resources/models/peris-sim/props/wellness_terminal/"
			and _mesh_count(span.get("_producer_visual")) >= 2,
		"producer reuses portable external terminal meshes instead of named primitives")
	check(grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG
			and grid.find_path(start_cell, end_cell).is_empty(),
		"before activation the declared downstream route is physically blocked")
	check(not bool(initial.get("bridge_collision_enabled", true))
			and bool(initial.get("producer_interaction_enabled", false)),
		"dormant bridge has no collision while its producer is available")

	var rejections: Array[Dictionary] = []
	span.activation_rejected.connect(func(id, reason):
		rejections.append({"id": id, "reason": reason}))
	var source: Interactable = span.get_producer_interactable()
	var accepted_pre_owner := {"snapshot": {}}
	gs.interactable_triggered.connect(func(source_id: String, _actor: String) -> void:
		if source_id == span.producer_interactable_id() \
				and not gs.has_mechanism_phase(MECHANISM_ID):
			accepted_pre_owner.snapshot = gs.serialize().duplicate(true)
	)
	check(not span.activate("aster") and not gs.has_mechanism_phase(MECHANISM_ID),
		"public actor-id helper cannot forge a physical producer receipt")
	source.active_character = "peris"
	check(not source._trigger(false) and source.is_interaction_enabled()
			and not bool(source.get("_used")) and not gs.has_mechanism_phase(MECHANISM_ID),
		"producer refuses a real character outside data-space proximity without spending its source")
	source.active_character = "aster"
	check(source._trigger(false),
		"nearby branch visitor uses the exact terminal to commit the downstream bridge extension")
	var begun := gs.get_mechanism_phase_state(MECHANISM_ID)
	check(begun.get("phase") == &"extending"
			and begun.get("metadata", {}).get("activated_by") == "aster"
			and begun.get("metadata", {}).get("blocker_tag") == BLOCKER_TAG,
		"GameState owns extending phase and complete causal metadata at commitment")
	var begin_events := log.events.filter(func(event):
		return event.get("kind") == GameEvent.KIND_BEGIN_MECHANISM_PHASE)
	check(begin_events.size() == 1
			and begin_events[0].get("payload", {}).get("mechanism_id") == MECHANISM_ID
			and begin_events[0].get("payload", {}).has("end_tick"),
		"one logged command records the full scheduler window")
	check(not source._trigger(false) and not span.activate("aster"),
		"a committed producer cannot be fired twice or through its retired helper")

	scheduler.advance_ticks(DURATION * 0.5)
	var midpoint: Dictionary = span.get_state()
	check(midpoint.get("phase") == &"extending"
			and is_equal_approx(float(midpoint.get("progress", 0.0)), 0.5)
			and is_equal_approx(float(midpoint.get("bridge_visual_progress", 0.0)), 0.5),
		"visible extension samples scheduler-derived authoritative midpoint progress")
	var span_root := span.get("_span_root") as Node3D
	var span_model := span.get("_span_model") as Node3D
	check(span_root != null and span_model != null
			and span_root.basis.z.normalized().is_equal_approx((span_end - span_start).normalized())
			and span_model.position.is_equal_approx(Vector3(0.0, 0.0, 1.0)),
		"halfway bridge grows from its declared start toward its declared render endpoint")
	check(grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG
			and grid.find_path(start_cell, end_cell).is_empty()
			and not bool(midpoint.get("bridge_collision_enabled", true)),
		"halfway extension keeps navigation and collision closed")

	# Record the canonical tick before copying the event stream. Replay must recover the active delay
	# without ever having seen a BranchSpanProducer node.
	gs.flush_tick()
	var mid_log := EventLog.from_bytes(log.to_bytes())
	var replay_grid := _make_corridor_grid()
	var replayed := GameState.replay(mid_log, replay_grid)
	var replay_phase := replayed.get_mechanism_phase_state(MECHANISM_ID)
	check(replay_phase.get("phase") == &"extending"
			and is_equal_approx(float(replay_phase.get("progress", 0.0)), 0.5),
		"event replay reconstructs the authoritative half-extension without a presenter")
	var replay_span = BranchSpanScript.new()
	check(replay_span.configure(
		replayed, replayed.scheduler, producer_data, producer_render, span_start, span_end,
		[blocker_cell], _options()),
		"presenter configures after event replay")
	root.add_child(replay_span)
	await process_frame
	var replay_presented: Dictionary = replay_span.get_state()
	check(replay_grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG
			and replay_grid.find_path(start_cell, end_cell).is_empty()
			and is_equal_approx(float(replay_presented.get("bridge_visual_progress", 0.0)), 0.5),
		"replayed presenter restores the halfway visual and closed route from GameState alone")
	replayed.scheduler.advance_ticks(DURATION * 0.5)
	check(replay_span.is_bridged()
			and not replay_grid.dynamic_blockers.has(blocker_cell)
			and not replay_grid.find_path(start_cell, end_cell).is_empty(),
		"replayed extension opens the route only after its original remaining duration")
	replay_span.free()

	# Save/load uses a fresh GridWorld. The recreated kit must derive the dynamic blocker; no scene
	# snapshot or stale callback is allowed to be the source of truth.
	var snapshot := gs.serialize()
	var loaded_grid := _make_corridor_grid()
	var loaded_scheduler := EventScheduler.new()
	var loaded := GameState.new()
	loaded.scheduler = loaded_scheduler
	loaded.grid = loaded_grid
	loaded.deserialize(snapshot)
	var loaded_span = BranchSpanScript.new()
	check(loaded_span.configure(
		loaded, loaded_scheduler, producer_data, producer_render, span_start, span_end,
		[blocker_cell], _options()),
		"presenter configures after save/load")
	root.add_child(loaded_span)
	await process_frame
	var loaded_midpoint: Dictionary = loaded_span.get_state()
	check(loaded_midpoint.get("phase") == &"extending"
			and is_equal_approx(float(loaded_midpoint.get("progress", 0.0)), 0.5)
			and loaded_grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG,
		"save/load restores progress and the still-blocked route without scene-local state")
	loaded_scheduler.advance_ticks(DURATION * 0.5)
	check(loaded_span.is_bridged()
			and not loaded_grid.dynamic_blockers.has(blocker_cell)
			and not loaded_grid.find_path(start_cell, end_cell).is_empty(),
		"loaded extension completes after only its saved remaining duration")
	loaded_span.free()

	# Finish the original run, then prove the delayed consequence and reset contract.
	scheduler.advance_ticks(DURATION * 0.5)
	var completed: Dictionary = span.get_state()
	check(completed.get("phase") == &"bridged"
			and is_equal_approx(float(completed.get("progress", 0.0)), 1.0)
			and bool(completed.get("bridge_collision_enabled", false)),
		"completion produces a full visible, collidable physical bridge")
	check(not grid.dynamic_blockers.has(blocker_cell)
			and not grid.find_path(start_cell, end_cell).is_empty(),
		"only bridged completion removes the declared blocker")
	span.sync_from_game_state()
	span.sync_from_game_state()
	check(not grid.dynamic_blockers.has(blocker_cell)
			and not grid.find_path(start_cell, end_cell).is_empty(),
		"repeated presenter sync cannot re-close an already bridged route")
	check(span.reset(&"focused_verifier_reset"),
		"reset emits an authoritative mechanism reset")
	var reset_state: Dictionary = span.get_state()
	check(reset_state.get("phase") == &"dormant"
			and grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG
			and grid.find_path(start_cell, end_cell).is_empty(),
		"reset restores the closed route from dormant GameState truth")
	span.sync_from_game_state()
	span.sync_from_game_state()
	check(grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG
			and grid.find_path(start_cell, end_cell).is_empty(),
		"repeated dormant sync keeps exactly one stable route blocker")
	var reset_events := log.events.filter(func(event):
		return event.get("kind") == GameEvent.KIND_RESET_MECHANISM_PHASE)
	check(reset_events.size() == 1
			and reset_events[0].get("payload", {}).get("reason") == &"focused_verifier_reset"
			and bool(reset_state.get("producer_interaction_enabled", false))
			and not bool(reset_state.get("bridge_collision_enabled", true)),
		"reset is logged, re-arms the producer, and retracts bridge collision")

	# GameState emits the accepted terminal edge synchronously before the owner callback begins its
	# mechanism phase. Loading that exact seam must re-arm the physical source rather than granting a
	# bridge or leaving a spent, inert terminal. Repeating attachment cannot consume the orphan later.
	var accepted_pre_owner_snapshot: Dictionary = accepted_pre_owner.snapshot
	check(not accepted_pre_owner_snapshot.is_empty()
			and not (accepted_pre_owner_snapshot.get(
				"timed_mechanism_phases", {}) as Dictionary).has(MECHANISM_ID),
		"signal-time fixture captures the accepted terminal before owner commitment")
	gs.deserialize(accepted_pre_owner_snapshot)
	span.on_game_state_snapshot_restored()
	span.on_game_state_snapshot_restored()
	check(not gs.has_mechanism_phase(MECHANISM_ID)
			and source.is_interaction_enabled() and not bool(source.get("_used"))
			and gs.is_interactable_enabled(span.producer_interactable_id()),
		"same presenter re-arms an accepted pre-owner receipt without bridging")
	check(not span.activate("aster") and not gs.has_mechanism_phase(MECHANISM_ID),
		"rearmed accepted seam still rejects the actor-id compatibility helper")

	var fresh_grid := _make_corridor_grid()
	var fresh_scheduler := EventScheduler.new()
	var fresh_gs := GameState.new()
	fresh_gs.scheduler = fresh_scheduler
	fresh_gs.grid = fresh_grid
	fresh_gs.deserialize(accepted_pre_owner_snapshot)
	var fresh_span = BranchSpanScript.new()
	check(fresh_span.configure(
		fresh_gs, fresh_scheduler, producer_data, producer_render, span_start, span_end,
		[blocker_cell], _options()),
		"fresh presenter configures from the accepted pre-owner snapshot")
	root.add_child(fresh_span)
	await process_frame
	fresh_span.on_game_state_snapshot_restored()
	fresh_span.on_game_state_snapshot_restored()
	var fresh_source: Interactable = fresh_span.get_producer_interactable()
	check(not fresh_gs.has_mechanism_phase(MECHANISM_ID)
			and fresh_source.is_interaction_enabled() and not bool(fresh_source.get("_used"))
			and fresh_grid.dynamic_blockers.get(blocker_cell) == BLOCKER_TAG,
		"fresh repeated restore re-arms the exact terminal and keeps the route closed")
	fresh_span.free()

	span.free()
	finish()


func _options() -> Dictionary:
	return {
		"mechanism_id": MECHANISM_ID,
		"blocker_tag": BLOCKER_TAG,
		"duration": DURATION,
		"interaction_radius": 1.25,
	}


func _make_corridor_grid() -> GridWorld:
	var grid := GridWorld.new()
	grid.create_room(9, 5, true)
	for z in range(1, 4):
		for x in range(1, 8):
			grid.set_tile(x, z, GridWorld.Tile.WALL)
	for x in range(1, 8):
		grid.set_tile(x, 2, GridWorld.Tile.FLOOR)
	return grid


func _mesh_count(root_node: Node) -> int:
	if root_node == null:
		return 0
	return root_node.find_children("*", "MeshInstance3D", true, false).size()


func _visible_mesh_count(root_node: Node) -> int:
	if root_node == null:
		return 0
	var count := 0
	for mesh_variant in root_node.find_children("*", "MeshInstance3D", true, false):
		if mesh_variant is MeshInstance3D and (mesh_variant as MeshInstance3D).visible:
			count += 1
	return count


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)


func finish() -> void:
	print("BRANCH SPAN PRODUCER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
