extends SceneTree

## Regression for the endpoint-only interaction exploit. A timed action is committed when work begins,
## not only when it finishes: same-instance rollback and fresh-instance load must preserve the actor and
## original absolute deadline, re-arm exactly one callback, and mirror one-shot usage from GameState.

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_pre_trigger_validator()
	await _verify_unbound_factory_spec()
	await _verify_registry_activation_grammar()
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	state.register_character("aster", Vector3.ZERO, 3.0, {"hp": 100.0})
	state.register_interactable(_spec())

	var host := Node3D.new()
	root.add_child(host)
	var action := await _make_action(host, state, scheduler)
	var completion_counter := {"value": 0}
	action.interacted.connect(func(): completion_counter.value += 1)
	action.active_character = "aster"
	action.on_interaction_arrived()
	scheduler.advance_ticks(3.0)
	var authority: Dictionary = state.get_world_state(
		action._dwell_authority_key(), {})
	check(str(authority.get("phase", "")) == "dwelling"
			and str(authority.get("actor", "")) == "aster"
			and is_equal_approx(float(authority.get("deadline", -1.0)), 10.0),
		"work start commits actor, dwelling phase, and absolute deadline")
	var saved_scheduler := _json_round_trip(scheduler.serialize())
	var saved_state := _json_round_trip(state.serialize())

	# Let the future happen, then roll back on the SAME node. Its local `_used` and FSM state must
	# not survive the earlier authoritative snapshot.
	scheduler.advance_ticks(7.0)
	check(int(completion_counter.value) == 1 and not state.is_interactable_enabled("authority_work"),
		"future one-shot completion occurs before rollback")
	scheduler.clear()
	scheduler.deserialize(saved_scheduler)
	state.deserialize(saved_state)
	action.on_game_state_snapshot_restored()
	check(action.is_interaction_enabled() and action.get_action_verb() != ""
			and is_equal_approx(action.get_dwell_progress(), 0.3),
		"earlier rollback retracts future usage and restores midpoint presentation")
	scheduler.advance_ticks(6.99)
	check(int(completion_counter.value) == 1 and state.is_interactable_enabled("authority_work"),
		"rollback cannot finish work before its original deadline")
	scheduler.advance_ticks(0.01)
	check(int(completion_counter.value) == 2 and not state.is_interactable_enabled("authority_work"),
		"rollback resumes once and commits at the original deadline")
	scheduler.advance_ticks(30.0)
	check(int(completion_counter.value) == 2, "restoration does not duplicate the completion callback")

	# Fresh scene/node load exercises stable-ID portability rather than relying on local variables.
	var fresh_scheduler := EventScheduler.new()
	fresh_scheduler.deserialize(saved_scheduler)
	var fresh_state := GameState.new()
	fresh_state.scheduler = fresh_scheduler
	fresh_state.deserialize(saved_state)
	var fresh_host := Node3D.new()
	root.add_child(fresh_host)
	var fresh_action := await _make_action(fresh_host, fresh_state, fresh_scheduler)
	var fresh_completion_counter := {"value": 0}
	fresh_action.interacted.connect(func(): fresh_completion_counter.value += 1)
	fresh_action.on_game_state_snapshot_restored()
	check(is_equal_approx(fresh_action.get_dwell_progress(), 0.3),
		"fresh presenter finds the same in-flight commitment by stable interactable ID")
	fresh_scheduler.advance_ticks(7.0)
	check(int(fresh_completion_counter.value) == 1 and not fresh_state.is_interactable_enabled("authority_work"),
		"fresh load finishes exactly once after the saved remainder")

	host.queue_free()
	fresh_host.queue_free()
	print("INTERACTABLE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_pre_trigger_validator() -> void:
	var state := GameState.new()
	state.register_interactable({
		"id": "validator_guarded",
		"position": Vector3.ZERO,
		"requires_hold": false,
		"one_shot": true,
		"enabled": true,
	})
	state.register_interactable({
		"id": "validator_default",
		"position": Vector3.ZERO,
		"requires_hold": false,
		"one_shot": true,
		"enabled": true,
	})
	var host := Node3D.new()
	root.add_child(host)
	var guarded := Interactable.new()
	guarded.bind_data(state, "validator_guarded")
	guarded.active_character = "aster"
	host.add_child(guarded)
	var ordinary := Interactable.new()
	ordinary.bind_data(state, "validator_default")
	ordinary.active_character = "aster"
	host.add_child(ordinary)
	await process_frame
	var validator_calls := {"value": 0}
	var guarded_interactions := {"value": 0}
	guarded.interacted.connect(func(): guarded_interactions.value += 1)
	guarded.set_pre_trigger_validator(func(
			interactable: Interactable, actor_id: String) -> bool:
		validator_calls.value += 1
		return interactable == guarded and actor_id == "peris"
	)
	check(not guarded._trigger()
			and int(validator_calls.value) == 1
			and int(guarded_interactions.value) == 0
			and state.is_interactable_enabled("validator_guarded")
			and not bool(state.get_interactable("validator_guarded").get("triggered", false)),
		"pre-trigger validator rejects before GameState, one-shot, and interacted mutation")
	guarded.active_character = "peris"
	check(guarded._trigger()
			and int(validator_calls.value) == 2
			and int(guarded_interactions.value) == 1
			and not state.is_interactable_enabled("validator_guarded"),
		"accepted pre-trigger validation preserves the ordinary one-shot path")
	check(ordinary._trigger() and not state.is_interactable_enabled("validator_default"),
		"an interactable without a validator preserves default trigger behavior")
	host.queue_free()
	await process_frame


func _verify_unbound_factory_spec() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var action := InteractableFactory.spawn(
		null,
		host,
		"unbound_authored_work",
		{
			"position": Vector3(2.0, 0.5, -3.0),
			"radius": 4.25,
			"hold_time": 2.75,
			"one_shot": true,
			"requires_hold": false,
			"interactable_type": Interactable.InteractableType.TIMED_ACTION,
			"required_character": "peris",
			"tutorial_label": "TEND",
		},
		null,
		null,
		"peris") as Interactable
	await process_frame
	var collision := action.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as SphereShape3D if collision != null else null
	check(action.one_shot
			and is_equal_approx(action.dwell_time, 2.75)
			and is_equal_approx(action.interaction_radius, 4.25)
			and action.interactable_type == Interactable.InteractableType.TIMED_ACTION
			and action.required_character == "peris"
			and action.tutorial_label == "TEND",
		"unbound factory construction preserves the complete authored interaction grammar")
	check(shape != null and is_equal_approx(shape.radius, 4.25),
		"unbound factory radius reaches the physical trigger shape before ready")
	var interactions := {"value": 0}
	action.interacted.connect(func(): interactions.value += 1)
	check(action._trigger(false) and int(interactions.value) == 1
			and action._used and not action.interaction_enabled,
		"unbound factory one-shot commits exactly once instead of degrading to a generic repeatable")
	host.queue_free()
	await process_frame


func _verify_registry_activation_grammar() -> void:
	var scheduler := EventScheduler.new()
	var state := GameState.new()
	state.scheduler = scheduler
	var log := EventLog.new()
	state.event_log = log
	state.register_character("peris", Vector3.ZERO, 3.0, {"hp": 100.0})
	state.register_interactable({
		"id": "bound_timed_work",
		"position": Vector3.ZERO,
		"requires_hold": false,
		"interactable_type": Interactable.InteractableType.TIMED_ACTION,
		"hold_time": 1.25,
		"one_shot": true,
		"required_character": "peris",
		"enabled": true,
	})
	var stored := state.get_interactable("bound_timed_work")
	check(int(stored.get("interactable_type", -1))
			== Interactable.InteractableType.TIMED_ACTION
			and not bool(stored.get("requires_hold", true)),
		"registry preserves TIMED_ACTION while retaining a truthful legacy projection")
	var registration_payload: Dictionary = log.events[1]["payload"]
	check(int(registration_payload.get("interactable_type", -1))
			== Interactable.InteractableType.TIMED_ACTION,
		"registration event records the complete activation grammar")

	var host := Node3D.new()
	root.add_child(host)
	var action := InteractableFactory.spawn(
		state,
		host,
		"bound_timed_work",
		{
			"position": Vector3.ZERO,
			"requires_hold": false,
			"interactable_type": Interactable.InteractableType.TIMED_ACTION,
			"hold_time": 1.25,
			"one_shot": true,
			"required_character": "peris",
			"enabled": true,
		},
		scheduler,
		null,
		"peris") as Interactable
	await process_frame
	check(action.interactable_type == Interactable.InteractableType.TIMED_ACTION
			and is_equal_approx(action.dwell_time, 1.25),
		"bound factory presenter remains TIMED_ACTION after add_child and _ready")
	action.on_interaction_arrived()
	check(int(state.get_interactable("bound_timed_work").get("trigger_count", -1)) == 0,
		"timed registry source does not collapse into an instant arrival trigger")
	scheduler.advance_ticks(1.249)
	check(int(state.get_interactable("bound_timed_work").get("trigger_count", -1)) == 0,
		"timed registry source cannot finish before its authored work deadline")
	scheduler.advance_ticks(0.001)
	check(int(state.get_interactable("bound_timed_work").get("trigger_count", -1)) == 1,
		"timed registry source commits once at its scheduler-owned deadline")

	var saved_state := _json_round_trip(state.serialize())
	var restored := GameState.new()
	restored.scheduler = EventScheduler.new()
	restored.deserialize(saved_state)
	check(int(restored.get_interactable("bound_timed_work").get("interactable_type", -1))
			== Interactable.InteractableType.TIMED_ACTION,
		"snapshot round-trip retains the complete activation grammar")
	var replayed := GameState.replay(log, null)
	check(int(replayed.get_interactable("bound_timed_work").get("interactable_type", -1))
			== Interactable.InteractableType.TIMED_ACTION,
		"event replay retains the complete activation grammar")

	var legacy_log := EventLog.new()
	legacy_log.append(GameEvent.make(0.0, GameEvent.KIND_REGISTER_INTERACTABLE, {
		"id": "legacy_click",
		"position": GameEvent.v3_to_arr(Vector3.ZERO),
		"requires_hold": false,
		"hold_time": 0.0,
		"one_shot": false,
		"enabled": true,
	}))
	var legacy_replay := GameState.replay(legacy_log, null)
	check(int(legacy_replay.get_interactable("legacy_click").get("interactable_type", -1))
			== Interactable.InteractableType.INSPECTION,
		"legacy two-state registration events migrate deterministically to INSPECTION")
	check(InteractableCatalog.parse_interactable_type("TIMED_ACTION")
			== Interactable.InteractableType.TIMED_ACTION,
		"catalog parser exposes TIMED_ACTION instead of silently falling back to HOLD_ACTION")
	host.queue_free()
	await process_frame


func _make_action(parent: Node3D, state: GameState, scheduler: EventScheduler) -> Interactable:
	var action := Interactable.new()
	action.name = "AuthorityWork"
	action.bind_data(state, "authority_work")
	action.set_movement_authority(state)
	action.set_scheduler(scheduler)
	parent.add_child(action)
	await process_frame
	return action


func _spec() -> Dictionary:
	return {
		"id": "authority_work",
		"position": Vector3.ZERO,
		"requires_hold": false,
		"interactable_type": Interactable.InteractableType.TIMED_ACTION,
		"hold_time": 10.0,
		"one_shot": true,
		"enabled": true,
		"tutorial_label": "TEND",
	}


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
