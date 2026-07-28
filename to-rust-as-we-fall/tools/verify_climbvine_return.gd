extends SceneTree

## Exact-source contract for the generated return point. TEND and CLIMB are consequences only of
## their bound Interactable receipts; GameState owns deployment and every rider's external traversal.

const ClimbvineScript := preload("res://scripts/game/objects/climbvine_return.gd")

class EndpointWarp:
	extends RefCounted
	var data_lower := Vector3.ZERO
	var data_upper := Vector3.ZERO
	var render_lower := Vector3.ZERO
	var render_upper := Vector3.ZERO

	func setup(dl: Vector3, du: Vector3, rl: Vector3, ru: Vector3) -> EndpointWarp:
		data_lower = dl
		data_upper = du
		render_lower = rl
		render_upper = ru
		return self

	func to_world(point: Vector3) -> Vector3:
		var axis := data_upper - data_lower
		var t := 0.0 if axis.length_squared() < 0.0001 \
			else clampf((point - data_lower).dot(axis) / axis.length_squared(), 0.0, 1.0)
		return render_lower.lerp(render_upper, t)


var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scheduler := EventScheduler.new()
	var log := EventLog.new()
	var gs := GameState.new()
	gs.scheduler = scheduler
	gs.event_log = log

	var lower_data := Vector3(18.0, 0.0, 2.0)
	var upper_data := Vector3(2.0, 0.0, 2.0)
	var lower_render := Vector3(6.0, -5.0, -3.0)
	var upper_render := Vector3(6.0, 1.0, -3.0)
	gs.coord_map = EndpointWarp.new().setup(
		lower_data, upper_data, lower_render, upper_render)
	gs.register_character("aster", lower_data, 3.0, {
		"hp": 100.0, "narrative_available": true,
	})
	gs.register_character("peris", upper_data, 3.0, {
		"hp": 100.0, "narrative_available": true,
	})
	gs.register_character("endo", lower_data, 3.0, {
		"hp": 100.0, "narrative_available": true,
	})

	var selected := {"ids": ([] as Array)}
	var vine = ClimbvineScript.new()
	check(vine.configure(
		gs, scheduler, lower_data, upper_data, lower_render, upper_render,
		{
			"return_id": "verify_return",
			"deployment_duration": 2.0,
			"deployment_steps": 4,
			"climb_duration": 4.0,
			"interaction_radius": 2.0,
		}), "configures separate data and render endpoints")
	vine.set_group_provider(func() -> Array: return selected.ids.duplicate())
	root.add_child(vine)
	await process_frame
	await process_frame

	var upper := vine.get_upper_interactable() as Interactable
	var lower := vine.get_lower_interactable() as Interactable
	var initial: Dictionary = vine.get_state()
	var upper_id := str(initial.get("upper_interactable_id", ""))
	var lower_id := str(initial.get("lower_interactable_id", ""))
	check(str(initial.get("contract", "")) == "climbvine_return/v1"
			and initial.get("visual_source") \
				== "res://resources/models/peris-sim/plants/plant_pothos.gltf",
		"state exposes its version and portable UV-mapped pothos source")
	check(initial.get("data_endpoints", {}).get("lower") == lower_data
			and initial.get("render_endpoints", {}).get("lower") == lower_render,
		"data and warped render endpoints remain independently readable")
	check(upper_id == "verify_return:upper_tend"
			and lower_id == "verify_return:lower_climb"
			and upper.data_id == upper_id and lower.data_id == lower_id,
		"both endpoint Interactables bind stable exact-source IDs")
	check(upper.get("_scheduler") == scheduler and lower.get("_scheduler") == scheduler
			and upper.get("_movement_gs") == gs and lower.get("_movement_gs") == gs,
		"both internal Interactables receive scheduler and movement authority")
	check(not bool(initial.get("lower_interaction_enabled", true))
			and not lower._trigger(false),
		"lower physical trigger refuses use before deployment")
	check(not vine.tend("peris") and vine.start_climb(["aster"]) == 0
			and not gs.has_mechanism_phase(vine.get_mechanism_id())
			and not gs.is_external_traversal_active("aster"),
		"public consequence helpers are inert")

	var rejected: Array = []
	vine.tend_rejected.connect(func(character_id, required):
		rejected.append({"character": character_id, "required": required}))
	selected.ids = ["peris"]
	upper.active_character = "aster"
	check(not upper._trigger(false) and rejected.size() == 1
			and rejected[0].get("required") == "peris"
			and not gs.has_mechanism_phase(vine.get_mechanism_id()),
		"selecting Peris's portrait cannot make Aster's remote body TEND")
	gs.snap_character_to("peris", upper_data + Vector3(8.0, 0.0, 0.0))
	upper.active_character = "peris"
	check(not upper._trigger(false)
			and not bool(gs.get_interactable(upper_id).get("triggered", false)),
		"exact tender identity cannot substitute for upper-anchor proximity")
	gs.snap_character_to("peris", upper_data)
	check(gs.command_move_to_pos("peris", upper_data + Vector3(1.0, 0.0, 0.0))
			and not upper._trigger(false),
		"a moving tender cannot mint an action-free source receipt")
	gs.command_stop("peris")
	gs.snap_character_to("peris", upper_data)

	# Capture the synchronous seam after GameState accepts the one-shot but before the owner consumes
	# the pending source receipt. Loading this snapshot must re-arm TEND, never infer deployment.
	var seam := {
		"state": {},
		"scheduler": {},
		"log_bytes": PackedByteArray(),
		"receipt": {},
	}
	gs.interactable_triggered.connect(func(id: String, _actor: String):
		if id != upper_id or not (seam.state as Dictionary).is_empty():
			return
		seam.state = gs.serialize().duplicate(true)
		seam.scheduler = scheduler.serialize().duplicate(true)
		seam.log_bytes = log.to_bytes()
		var authority: Dictionary = gs.get_world_state(
			vine.call("_receipt_authority_key"), {})
		seam.receipt = (authority.get("upper_pending", {}) as Dictionary).duplicate(true)
	)
	upper.active_character = "peris"
	check(upper._trigger(false) and vine.is_deploying()
			and not (seam.state as Dictionary).is_empty()
			and not (seam.receipt as Dictionary).is_empty(),
		"exact upper Interactable receipt starts deployment and exposes the accepted-trigger seam")

	# Same-instance rollback to that seam.
	scheduler.clear()
	scheduler.deserialize(seam.scheduler)
	log = EventLog.from_bytes(seam.log_bytes)
	gs.event_log = log
	gs.deserialize(seam.state)
	vine.on_game_state_snapshot_restored()
	var reset_events_after_first := _events_of_kind(
		log, GameEvent.KIND_RESET_INTERACTABLE).size()
	check(not vine.is_deploying() and not vine.is_deployed()
			and upper.is_interaction_enabled()
			and not bool(gs.get_interactable(upper_id).get("triggered", true))
			and (vine.get_state().get("interaction_receipts", {})
				.get("upper_pending", {}) as Dictionary).is_empty(),
		"same-instance accepted-trigger restore grants nothing and re-arms TEND")
	check(not bool(vine.call(
			"_commit_tend_from_receipt", upper, seam.receipt))
			and not gs.has_mechanism_phase(vine.get_mechanism_id()),
		"stale upper source receipt cannot be consumed after rollback")
	vine.on_game_state_snapshot_restored()
	check(_events_of_kind(log, GameEvent.KIND_RESET_INTERACTABLE).size()
			== reset_events_after_first,
		"same-instance restore reconciliation is idempotent")

	# Fresh presenter attached to the same accepted-trigger snapshot has the same retry semantics.
	var seam_fresh_scheduler := EventScheduler.new()
	seam_fresh_scheduler.deserialize(seam.scheduler)
	var seam_fresh_log := EventLog.from_bytes(seam.log_bytes)
	var seam_fresh_gs := GameState.new()
	seam_fresh_gs.scheduler = seam_fresh_scheduler
	seam_fresh_gs.event_log = seam_fresh_log
	seam_fresh_gs.deserialize(seam.state)
	var seam_fresh_vine = ClimbvineScript.new()
	check(seam_fresh_vine.configure(
		seam_fresh_gs, seam_fresh_scheduler,
		lower_data, upper_data, lower_render, upper_render,
		{"return_id": "verify_return", "deployment_duration": 2.0,
		 "climb_duration": 4.0, "interaction_radius": 2.0}),
		"fresh accepted-trigger presenter configures")
	root.add_child(seam_fresh_vine)
	await process_frame
	var seam_fresh_upper := seam_fresh_vine.get_upper_interactable() as Interactable
	check(not seam_fresh_vine.is_deploying() and seam_fresh_upper.is_interaction_enabled(),
		"fresh accepted-trigger restore is retryable without deploying")
	var fresh_reset_count := _events_of_kind(
		seam_fresh_log, GameEvent.KIND_RESET_INTERACTABLE).size()
	seam_fresh_vine.on_game_state_snapshot_restored()
	check(_events_of_kind(seam_fresh_log, GameEvent.KIND_RESET_INTERACTABLE).size()
			== fresh_reset_count,
		"fresh accepted-trigger reconciliation is idempotent")
	seam_fresh_upper.active_character = "peris"
	check(seam_fresh_upper._trigger(false) and seam_fresh_vine.is_deploying(),
		"fresh accepted-trigger restore accepts a new exact physical TEND")
	seam_fresh_vine.free()

	# Retry on the main restored presenter, then capture the authoritative deployment midpoint.
	upper.active_character = "peris"
	check(upper._trigger(false), "re-armed exact Peris TEND is accepted once")
	scheduler.advance_ticks(1.0)
	var half_deploy: Dictionary = vine.get_state()
	var mechanism_id: StringName = vine.get_mechanism_id()
	var authoritative_deploy := gs.get_mechanism_phase_state(mechanism_id)
	check(bool(half_deploy.get("deploying", false))
			and is_equal_approx(float(half_deploy.get("deployment_progress", 0.0)), 0.5)
			and not bool(half_deploy.get("lower_interaction_enabled", true)),
		"deployment midpoint is scheduler-owned and keeps the lower mouth gated")
	check(authoritative_deploy.get("metadata", {}).get("tender") == "peris"
			and authoritative_deploy.get("metadata", {}).get("source_interactable_id") == upper_id
			and int(authoritative_deploy.get("metadata", {}).get("receipt_nonce", 0)) > 0,
		"deployment records the exact tender and source-receipt provenance")
	var vine_visual = vine.get("_vine_visual") as Node3D
	check(vine_visual != null and vine_visual.visible
			and vine_visual.find_children("*", "MeshInstance3D", true, false).size() > 0,
		"deployment reveals external UV-mapped vine meshes")

	gs.flush_tick()
	var mid_deploy_log := EventLog.from_bytes(log.to_bytes())
	var replayed_deploy := GameState.replay(mid_deploy_log, null)
	check(replayed_deploy.get_mechanism_phase_state(mechanism_id).get("phase") == &"deploying"
			and is_equal_approx(float(replayed_deploy.get_mechanism_phase_state(
				mechanism_id).get("progress", 0.0)), 0.5),
		"event replay reconstructs deployment midway without a vine presenter")
	var mid_deploy_state := gs.serialize()
	var mid_deploy_scheduler := scheduler.serialize()
	var loaded_deploy_scheduler := EventScheduler.new()
	loaded_deploy_scheduler.deserialize(mid_deploy_scheduler)
	var loaded_deploy := GameState.new()
	loaded_deploy.scheduler = loaded_deploy_scheduler
	loaded_deploy.deserialize(mid_deploy_state)
	var loaded_vine = ClimbvineScript.new()
	check(loaded_vine.configure(
		loaded_deploy, loaded_deploy_scheduler,
		lower_data, upper_data, lower_render, upper_render,
		{"return_id": "verify_return", "deployment_duration": 2.0,
		 "climb_duration": 4.0, "interaction_radius": 2.0}),
		"fresh presenter attaches at deployment midpoint")
	root.add_child(loaded_vine)
	await process_frame
	check(loaded_vine.is_deploying()
			and not loaded_vine.get_upper_interactable().is_interaction_enabled()
			and not bool(loaded_vine.get_state().get("lower_interaction_enabled", true)),
		"fresh deployment midpoint preserves its spent upper source and lower gate")
	loaded_deploy_scheduler.advance_ticks(1.0)
	check(loaded_vine.is_deployed()
			and bool(loaded_vine.get_state().get("lower_interaction_enabled", false)),
		"fresh deployment completes after only the saved remainder")
	loaded_deploy_scheduler.advance_ticks(10.0)
	check(loaded_vine.is_deployed(), "deployment restore cannot complete twice")
	loaded_vine.free()

	scheduler.advance_ticks(1.0)
	check(vine.is_deployed() and lower.is_interaction_enabled(),
		"main deployment enables only the lower climb source")

	# Lower group authority is all-or-nothing. A selected remote portrait cannot be silently filtered
	# while a nearby member climbs.
	selected.ids = ["aster", "endo"]
	gs.snap_character_to("endo", lower_data + Vector3(12.0, 0.0, 0.0))
	lower.active_character = "aster"
	var lower_triggers_before := _trigger_events_for(log, lower_id).size()
	check(not lower._trigger(false)
			and not gs.is_external_traversal_active("aster")
			and not gs.is_external_traversal_active("endo")
			and _trigger_events_for(log, lower_id).size() == lower_triggers_before,
		"a selected remote group is refused wholly at the exact lower occupancy gate")
	lower.active_character = "peris"
	check(not lower._trigger(false) and not gs.is_external_traversal_active("peris"),
		"an upper-deck body cannot use CLIMB as a forward drop")

	gs.snap_character_to("endo", lower_data)
	selected.ids = ["aster", "endo"]
	# A synchronous traversal observer may invalidate a later group member after
	# the first BEGIN has committed. The vine must cancel that prefix and return
	# to a retryable source instead of wedging a partial party on the line.
	var invalidate_second := func(id: String, _state: Dictionary) -> void:
		if id == "aster":
			gs._knocked_down["endo"] = {"end_tick": 9999.0, "handle": 0}
	gs.external_traversal_started.connect(invalidate_second)
	lower.active_character = "aster"
	check(lower._trigger(false)
			and not gs.is_external_traversal_active("aster")
			and not gs.is_external_traversal_active("endo")
			and lower.is_interaction_enabled()
			and (vine.get_state().get("interaction_receipts", {})
				.get("lower_pending", {}) as Dictionary).is_empty(),
		"a signal-time later-rider rejection cancels the accepted prefix and rearms CLIMB")
	gs.external_traversal_started.disconnect(invalidate_second)
	gs._knocked_down.erase("endo")

	var stale_lower_receipt := {"value": ({} as Dictionary)}
	gs.interactable_triggered.connect(func(id: String, _actor: String):
		if id != lower_id or not (stale_lower_receipt.value as Dictionary).is_empty():
			return
		var authority: Dictionary = gs.get_world_state(
			vine.call("_receipt_authority_key"), {})
		stale_lower_receipt.value = (
			authority.get("lower_pending", {}) as Dictionary
		).duplicate(true)
	)
	var committed_groups: Array = []
	vine.climb_committed.connect(func(_return_id, ids):
		committed_groups.append((ids as Array).duplicate()))
	lower.active_character = "aster"
	check(lower._trigger(false)
			and gs.is_external_traversal_active("aster")
			and gs.is_external_traversal_active("endo")
			and committed_groups == [["aster", "endo"]],
		"exact lower Interactable commits the actual all-present selected group")
	var traversal_events := _events_of_kind(log, GameEvent.KIND_BEGIN_EXTERNAL_TRAVERSAL)
	check(traversal_events.size() >= 2
			and traversal_events[-2].get("payload", {}).get("id") == "aster"
			and traversal_events[-1].get("payload", {}).get("id") == "endo",
		"actual riders are recorded through canonical external traversals")
	check(gs.is_interactable_enabled(lower_id)
			and not bool(gs.get_interactable(lower_id).get("triggered", true))
			and (vine.get_state().get("interaction_receipts", {})
				.get("lower_pending", {}) as Dictionary).is_empty(),
		"repeatable lower receipt is synchronously consumed and re-armed")
	check(int(vine.call(
			"_commit_climb_from_receipt", lower, stale_lower_receipt.value)) == 0,
		"consumed lower source receipt cannot be replayed directly")

	check(not gs.command_move_to_pos("aster", Vector3(99.0, 0.0, 99.0)),
		"ordinary movement cannot cancel a locked climb")
	scheduler.advance_ticks(2.0)
	var midway_data := lower_data.lerp(upper_data, 0.5)
	var midway_render := lower_render.lerp(upper_render, 0.5)
	check(gs.get_position("aster").is_equal_approx(midway_data)
			and gs.get_position("endo").is_equal_approx(midway_data)
			and gs.get_render_position("aster").is_equal_approx(midway_render),
		"all riders expose the same authoritative climb midpoint")

	gs.flush_tick()
	var mid_climb_log := EventLog.from_bytes(log.to_bytes())
	var replayed_climb := GameState.replay(mid_climb_log, null)
	check(replayed_climb.is_external_traversal_active("aster")
			and replayed_climb.is_external_traversal_active("endo")
			and replayed_climb.get_position("aster").is_equal_approx(midway_data),
		"event replay reconstructs both in-progress riders")
	var climb_state := gs.serialize()
	var climb_scheduler_state := scheduler.serialize()
	var loaded_climb_scheduler := EventScheduler.new()
	loaded_climb_scheduler.deserialize(climb_scheduler_state)
	var loaded_climb_log := EventLog.from_bytes(log.to_bytes())
	var loaded_climb := GameState.new()
	loaded_climb.scheduler = loaded_climb_scheduler
	loaded_climb.event_log = loaded_climb_log
	loaded_climb.deserialize(climb_state)
	var loaded_climb_vine = ClimbvineScript.new()
	check(loaded_climb_vine.configure(
		loaded_climb, loaded_climb_scheduler,
		lower_data, upper_data, lower_render, upper_render,
		{"return_id": "verify_return", "deployment_duration": 2.0,
		 "climb_duration": 4.0, "interaction_radius": 2.0}),
		"fresh presenter attaches at a group climb midpoint")
	root.add_child(loaded_climb_vine)
	await process_frame
	check((loaded_climb_vine.get_state().get("active_climbs", []) as Array).size() == 2,
		"fresh presenter reconstructs the actual saved rider group")
	var loaded_begin_count := _events_of_kind(
		loaded_climb_log, GameEvent.KIND_BEGIN_EXTERNAL_TRAVERSAL).size()
	loaded_climb_vine.on_game_state_snapshot_restored()
	loaded_climb_vine.on_game_state_snapshot_restored()
	check(_events_of_kind(
			loaded_climb_log, GameEvent.KIND_BEGIN_EXTERNAL_TRAVERSAL).size()
			== loaded_begin_count,
		"repeated midpoint restore does not duplicate canonical traversals")
	loaded_climb_scheduler.advance_ticks(2.0)
	check(not loaded_climb.is_external_traversal_active("aster")
			and not loaded_climb.is_external_traversal_active("endo")
			and loaded_climb.get_position("aster").is_equal_approx(upper_data)
			and loaded_climb.get_position("endo").is_equal_approx(upper_data),
		"fresh group climb completes once after only its saved remainder")
	loaded_climb_vine.free()

	var climbed: Array[String] = []
	vine.character_climbed.connect(func(_return_id, id): climbed.append(id))
	scheduler.advance_ticks(2.0)
	climbed.sort()
	check(not gs.is_external_traversal_active("aster")
			and not gs.is_external_traversal_active("endo")
			and gs.get_position("aster").is_equal_approx(upper_data)
			and gs.get_position("endo").is_equal_approx(upper_data)
			and climbed == ["aster", "endo"],
		"main group finishes at the upper endpoint exactly once")

	# Reset still uses the explicit logged cancellation seam and retracts both source controls.
	gs.snap_character_to("endo", lower_data)
	selected.ids = ["endo"]
	lower.active_character = "endo"
	check(lower._trigger(false), "repeatable lower source accepts another exact occupant")
	scheduler.advance_ticks(1.0)
	var cancel_position := gs.get_position("endo")
	vine.reset()
	check(not gs.is_external_traversal_active("endo")
			and gs.get_position("endo").is_equal_approx(cancel_position)
			and not vine.is_deployed()
			and upper.is_interaction_enabled() and not lower.is_interaction_enabled(),
		"checkpoint reset cancels the rider, retracts the vine, and restores TEND only")
	var cancel_events := _events_of_kind(log, GameEvent.KIND_CANCEL_EXTERNAL_TRAVERSAL)
	var reset_cancel_events := cancel_events.filter(func(event):
		return event.get("payload", {}).get("reason") == &"climbvine_reset")
	check(reset_cancel_events.size() == 1,
		"reset cancellation remains an explicit canonical event")
	scheduler.advance_ticks(8.0)
	check(gs.get_position("endo").is_equal_approx(cancel_position)
			and not vine.is_deployed(),
		"cancelled traversal and deployment callbacks cannot resurrect after reset")

	vine.free()
	finish()


func _events_of_kind(log: EventLog, kind: StringName) -> Array:
	return log.events.filter(func(event): return event.get("kind") == kind)


func _trigger_events_for(log: EventLog, interactable_id: String) -> Array:
	return log.events.filter(func(event):
		return event.get("kind") == GameEvent.KIND_TRIGGER_INTERACTABLE \
			and event.get("payload", {}).get("id") == interactable_id)


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures += 1
	push_error("FAIL: %s" % message)


func finish() -> void:
	print("CLIMBVINE RETURN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
