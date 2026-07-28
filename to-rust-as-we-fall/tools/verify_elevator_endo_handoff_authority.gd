extends SceneTree

## Focused exploit regression for Endo's junction water handoff. The real body must reach the
## container, a saved/interruptible mechanism phase must finish, and only then may a canonical
## GameState item enter Endo's hand and travel back to the party.

const ElevatorScene := preload("res://scenes/tutorial/elevator.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_static_guardrails()
	await _verify_junction_plant_precommit()
	await _verify_junction_signal_continuation()
	await _verify_endo_entry_authority()

	var source := await _spawn_elevator()
	_stage_endo_at_water(source)
	var drink_id := str(source._resolve_endo_drink_item_id())
	check(drink_id != "" and _item_is_grounded(source, drink_id),
		"the authored container has one canonical grounded GameState item")

	source._start_endo_shelter()
	var started: Dictionary = source._game_state.get_mechanism_phase_state(
		source.ENDO_DRINK_PICKUP_PHASE_ID)
	check(str(started.get("phase", "")) == str(source.ENDO_DRINK_PICKUP_PHASE)
			and float(started.get("remaining", 0.0)) > 1.4,
		"physical arrival begins the saved pickup hold instead of a scene timer")
	check(_item_is_grounded(source, drink_id)
			and source._game_state.get_hand_items("endo").is_empty(),
		"starting the hold neither moves the prop nor grants the item early")

	source.headless_advance(0.57, 0.01)
	var midpoint: Dictionary = source._game_state.get_mechanism_phase_state(
		source.ENDO_DRINK_PICKUP_PHASE_ID)
	var midpoint_remaining := float(midpoint.get("remaining", -1.0))
	var midpoint_progress := float(midpoint.get("progress", -1.0))
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	check(midpoint_progress > 0.25 and midpoint_progress < 0.55
			and midpoint_remaining > 0.7,
		"mid-hold save exposes truthful progress and remaining time")

	# The discarded future completes the hold and visibly carries the same item.
	source.headless_advance(midpoint_remaining + 0.05, 0.01)
	check(_item_is_held_by_endo(source, drink_id)
			and str(source._current_step) == "endo_delivery",
		"the endpoint alone picks up the item and starts physical delivery")
	check(is_instance_valid(source._drink_mesh)
			and source._drink_mesh.get_parent() == source._endo,
		"the authored mesh derives its hand attachment from canonical item ownership")

	# Same-presenter rollback must retract both the hand item and the discarded route while retaining
	# the exact paid portion of the hold. Repeated attachment is observational.
	source.apply_save_snapshot(midpoint_snapshot)
	var same_midpoint: Dictionary = source._game_state.get_mechanism_phase_state(
		source.ENDO_DRINK_PICKUP_PHASE_ID)
	check(str(source._current_step) == "endo_shelter"
			and _item_is_grounded(source, drink_id)
			and is_equal_approx(float(same_midpoint.get("progress", -1.0)), midpoint_progress),
		"same-presenter rollback restores the grounded midpoint, not the future hand")
	var pending_after_restore := int(source._scheduler.pending_count())
	var events_after_restore := _event_count(source)
	source.on_game_state_snapshot_restored()
	source.on_game_state_snapshot_restored()
	check(source._scheduler.pending_count() == pending_after_restore,
		"repeated midpoint attachment keeps one authoritative completion callback")
	check(_event_count(source) == events_after_restore,
		"repeated midpoint attachment emits no pickup or movement command")
	source.headless_advance(maxf(0.0, midpoint_remaining - 0.01), 0.01)
	check(_item_is_grounded(source, drink_id),
		"the item remains on the container one tick before the saved endpoint")
	source.headless_advance(0.02, 0.01)
	check(_item_is_held_by_endo(source, drink_id)
			and str(source._current_step) == "endo_delivery",
		"the same presenter grants the hand once at the original endpoint")

	# A fresh scene/process must reconstruct the identical midpoint and result.
	var fresh := await _spawn_elevator()
	fresh.apply_save_snapshot(midpoint_snapshot)
	var fresh_drink_id := str(fresh._resolve_endo_drink_item_id())
	var fresh_midpoint: Dictionary = fresh._game_state.get_mechanism_phase_state(
		fresh.ENDO_DRINK_PICKUP_PHASE_ID)
	check(fresh_drink_id == drink_id and _item_is_grounded(fresh, fresh_drink_id)
			and is_equal_approx(float(fresh_midpoint.get("progress", -1.0)), midpoint_progress),
		"fresh presenter restores the same item id and paid hold progress")
	fresh.headless_advance(maxf(0.0, midpoint_remaining - 0.01), 0.01)
	check(_item_is_grounded(fresh, fresh_drink_id),
		"fresh presenter cannot pick up before the saved deadline")
	fresh.headless_advance(0.02, 0.01)
	check(_item_is_held_by_endo(fresh, fresh_drink_id)
			and str(fresh._current_step) == "endo_delivery",
		"fresh presenter commits the same physical pickup once")
	await _destroy_elevator(fresh)

	# Movement is an explicit interruption. The stale completion cannot put a remote item in Endo's
	# hand; after the detour ends, the story route returns him to the source and earns a new full hold.
	var interrupted := await _spawn_elevator()
	_stage_endo_at_water(interrupted)
	var interrupted_id := str(interrupted._resolve_endo_drink_item_id())
	interrupted._start_endo_shelter()
	interrupted.headless_advance(0.25, 0.01)
	var away: Vector3 = interrupted._endo_drink_ground_position() + Vector3(4.0, 0.0, 0.0)
	interrupted._game_state.command_move_to_pos("endo", away)
	check(not interrupted._game_state.has_mechanism_phase(
			interrupted.ENDO_DRINK_PICKUP_PHASE_ID)
			and _item_is_grounded(interrupted, interrupted_id),
		"moving away resets the hold immediately and leaves the water at its source")
	interrupted.headless_advance(1.35, 0.01)
	check(_item_is_grounded(interrupted, interrupted_id),
		"the cancelled hold's old deadline cannot grant a remote pickup")
	interrupted.headless_advance(4.5, 0.01)
	check(_item_is_held_by_endo(interrupted, interrupted_id),
		"after returning to the source, a new complete hold recovers the handoff")
	await _destroy_elevator(interrupted)

	# Absence is authoritative too: rolling back before Junction cannot retain Endo, the item, or its
	# future phase merely because this presenter already played them.
	var absence := await _spawn_elevator()
	var absence_snapshot := _json_round_trip(absence.build_save_snapshot())
	_stage_endo_at_water(absence)
	absence._start_endo_shelter()
	absence.headless_advance(absence.ENDO_DRINK_PICKUP_SECONDS + 0.05, 0.01)
	check(absence._game_state.characters.has("endo")
			and not str(absence._resolve_endo_drink_item_id()).is_empty(),
		"the discarded future creates the junction roster and held-item truth")
	absence.apply_save_snapshot(absence_snapshot)
	check(not absence._game_state.characters.has("endo")
			and str(absence._resolve_endo_drink_item_id()).is_empty()
			and not absence._game_state.has_mechanism_phase(
				absence.ENDO_DRINK_PICKUP_PHASE_ID),
		"absence rollback retracts Endo, the water item, and the pickup phase")
	check(not absence._endo.visible,
		"the absent roster truth also retracts Endo's presenter")
	await _destroy_elevator(absence)

	await _destroy_elevator(source)
	print("ELEVATOR ENDO HANDOFF AUTHORITY: %d checks, %d failures" % [
		_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_junction_plant_precommit() -> void:
	var source := await _spawn_elevator()
	source._load_chunk("junction")
	source._current_step = "junction_arrive"
	source._select_character("peris")
	var plant = source._junction_plant_interactable
	check(is_instance_valid(plant),
		"Junction builds the real Peris plant interactable")
	if not is_instance_valid(plant):
		await _destroy_elevator(source)
		return
	plant.active_character = "peris"
	plant.set_interaction_enabled(true)
	for character_id in ["aster", "peris"]:
		source._game_state.set_character_level(character_id, source.LEVEL_LOWER)
		source._game_state.set_stat(character_id, "atp", 3.0)
	source._game_state.snap_character_to(
		"peris", source.JUNCTION_SHELTER_CENTER + Vector3(0.5, 0.0, 0.0))
	source._game_state.snap_character_to(
		"aster", source.JUNCTION_SHELTER_CENTER + Vector3(12.0, 0.0, 0.0))
	var signal_count := {"value": 0}
	plant.interacted.connect(func() -> void:
		signal_count.value = int(signal_count.value) + 1)
	var continuation_before: Dictionary = source._portable_continuation.duplicate(true)
	check(not plant._trigger(false)
			and not plant._used
			and plant.is_interaction_enabled()
			and int(signal_count.value) == 0
			and source._portable_continuation == continuation_before
			and not source._game_state.characters.has("endo"),
		"missing Aster is rejected before one-shot, signal, or Endo handoff authority")

	source._game_state.snap_character_to(
		"aster", source.JUNCTION_SHELTER_CENTER + Vector3(-0.5, 0.0, 0.0))
	source._on_junction_plant_interacted()
	check(not plant._used
			and int(signal_count.value) == 0
			and source._portable_continuation == continuation_before
			and not source._game_state.characters.has("endo"),
		"calling the plant callback directly cannot impersonate its world interaction")
	plant.active_character = "aster"
	check(not plant._trigger(false)
			and not plant._used
			and int(signal_count.value) == 0,
		"Aster cannot consume Peris's plant interaction even with the pair gathered")
	plant.active_character = "peris"
	check(plant._trigger(false)
			and plant._used
			and int(signal_count.value) == 1
			and str(source._portable_continuation.get("next_method", ""))
				== "_start_endo_enters",
		"the exact conscious shelter pair commits the plant and saved dusk handoff once")
	await _destroy_elevator(source)


func _verify_junction_signal_continuation() -> void:
	var source := await _spawn_elevator()
	source._load_chunk("junction")
	source._current_step = "junction_arrive"
	source._start_dusk_from_plant()
	var started: Dictionary = source._portable_continuation.duplicate(true)
	check(str(started.get("kind", "")) == "method_delay"
			and str(started.get("owner_step", "")) == "junction_arrive"
			and str(started.get("next_method", "")) == "_start_endo_enters"
			and float(started.get("deadline", -1.0))
				> source._scheduler.get_current_tick()
			and not source._game_state.characters.has("endo"),
		"tending the plant commits a saved dusk phase before Endo exists")

	source.headless_advance(0.73, 0.01)
	var midpoint := _json_round_trip(source.build_save_snapshot())
	var saved_continuation: Dictionary = midpoint.get("portable_continuation", {})
	var remaining: float = float(saved_continuation.get("deadline", -1.0)) \
		- float(source._scheduler.get_current_tick())
	check(remaining > 1.1 and remaining < 1.4
			and str(source._current_step) == "junction_arrive"
			and not source._game_state.characters.has("endo"),
		"mid-dusk save exposes the original absolute deadline without granting arrival")

	# Let the discarded future begin Endo's physical approach, then prove rollback retracts both the
	# roster addition and callback while preserving the already-paid dusk duration.
	source.headless_advance(remaining + 0.02, 0.01)
	check(str(source._current_step) == "endo_enters"
			and source._game_state.characters.has("endo"),
		"the dusk endpoint alone begins Endo's physical approach")
	source.apply_save_snapshot(midpoint)
	var restored: Dictionary = source._portable_continuation.duplicate(true)
	check(str(source._current_step) == "junction_arrive"
			and not source._game_state.characters.has("endo")
			and str(restored.get("next_method", "")) == "_start_endo_enters",
		"same-presenter rollback retracts Endo and restores the pending signal")
	var pending_after_restore := int(source._scheduler.pending_count())
	source._restore_portable_continuation(midpoint.get("portable_continuation", {}))
	check(source._scheduler.pending_count() == pending_after_restore,
		"repeated dusk attachment keeps one continuation callback")
	source.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
	check(not source._game_state.characters.has("endo"),
		"same-presenter restore cannot summon Endo one tick early")
	source.headless_advance(0.02, 0.01)
	check(source._game_state.characters.has("endo")
			and str(source._current_step) == "endo_enters",
		"same-presenter restore resumes at the saved dusk endpoint")

	var fresh := await _spawn_elevator()
	fresh.apply_save_snapshot(midpoint)
	check(str(fresh._current_step) == "junction_arrive"
			and not fresh._game_state.characters.has("endo")
			and str(fresh._portable_continuation.get("next_method", ""))
				== "_start_endo_enters",
		"fresh presenter reconstructs the same pending junction signal")
	fresh.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
	check(not fresh._game_state.characters.has("endo"),
		"fresh load also remains pre-arrival until the saved endpoint")
	fresh.headless_advance(0.02, 0.01)
	check(fresh._game_state.characters.has("endo")
			and str(fresh._current_step) == "endo_enters",
		"fresh load fires the same physical approach once")
	await _destroy_elevator(fresh)
	await _destroy_elevator(source)


func _verify_endo_entry_authority() -> void:
	var source := await _spawn_elevator()
	source._load_chunk("junction")
	check(not source._game_state.characters.has("endo")
			and source._endo_entry_authority_state().is_empty(),
		"before the entrance Endo has neither a gameplay body nor semantic join state")
	source._current_step = "junction_arrive"
	source._start_endo_enters()
	var started: Dictionary = source._endo_entry_authority_state()
	var destination := GameEvent.arr_to_v3(started.get("destination", []))
	var start_position: Vector3 = source._game_state.get_position("endo")
	check(str(started.get("phase", "")) == source.ENDO_ENTRY_PHASE_APPROACHING
			and source._game_state.characters.has("endo")
			and source._game_state.get_character_level("endo") == source.LEVEL_LOWER
			and source._game_state.is_moving("endo")
			and float(started.get("arrival_deadline", -1.0))
				> source._scheduler.get_current_tick(),
		"entry commits an observable saved movement phase with an absolute arrival tick")
	check(source._endo.visible and not source._endo_entry_dialogue_started
			and str(source._current_step) == "endo_enters",
		"showing the approaching body does not grant the arrival dialogue early")

	source.headless_advance(0.47, 0.01)
	var midpoint_position: Vector3 = source._game_state.get_position("endo")
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var midpoint_state: Dictionary = source._endo_entry_authority_state()
	var remaining: float = float(midpoint_state.get("arrival_deadline", -1.0)) \
		- source._scheduler.get_current_tick()
	check(midpoint_position.distance_to(start_position) > 0.2
			and midpoint_position.distance_to(destination) > source.ENDO_ENTRY_RADIUS
			and remaining > 0.1,
		"mid-entry save observes Endo between the authored doorway and shelter")
	check(str(midpoint_state.get("phase", "")) == source.ENDO_ENTRY_PHASE_APPROACHING
			and not source._endo_entry_dialogue_started,
		"a midpoint has not semantically joined Endo or started consequences")

	# Play the discarded future through physical arrival, then prove the same
	# presenter can retract it to the saved in-flight body.
	source.headless_advance(remaining + 0.02, 0.01)
	var arrived: Dictionary = source._endo_entry_authority_state()
	check(str(arrived.get("phase", "")) == source.ENDO_ENTRY_PHASE_ARRIVED
			and source._endo_entry_dialogue_started,
		"authoritative arrival alone commits Endo's story dialogue")
	source.apply_save_snapshot(midpoint_snapshot)
	var rolled: Dictionary = source._endo_entry_authority_state()
	check(str(rolled.get("phase", "")) == source.ENDO_ENTRY_PHASE_APPROACHING
			and source._game_state.get_character_level("endo") == source.LEVEL_LOWER
			and source._game_state.is_moving("endo")
			and not source._endo_entry_dialogue_started,
		"same-presenter rollback retracts both semantic arrival and discarded dialogue")
	var pending_after_restore := int(source._scheduler.pending_count())
	var events_after_restore := _event_count(source)
	source.on_game_state_snapshot_restored()
	source.on_game_state_snapshot_restored()
	check(source._scheduler.pending_count() == pending_after_restore,
		"repeated entry attachment preserves one saved movement callback")
	check(_event_count(source) == events_after_restore,
		"repeated entry attachment emits neither movement nor story commands")
	source.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
	check(str(source._endo_entry_authority_state().get("phase", ""))
			== source.ENDO_ENTRY_PHASE_APPROACHING,
		"same-presenter load cannot commit one tick before saved arrival")
	source.headless_advance(0.02, 0.01)
	check(str(source._endo_entry_authority_state().get("phase", ""))
			== source.ENDO_ENTRY_PHASE_ARRIVED
			and source._endo_entry_dialogue_started,
		"same-presenter load commits at the original physical endpoint")

	var fresh := await _spawn_elevator()
	fresh.apply_save_snapshot(midpoint_snapshot)
	var fresh_state: Dictionary = fresh._endo_entry_authority_state()
	check(str(fresh_state.get("phase", "")) == fresh.ENDO_ENTRY_PHASE_APPROACHING
			and fresh._game_state.get_character_level("endo") == fresh.LEVEL_LOWER
			and fresh._game_state.is_moving("endo")
			and fresh._game_state.get_position("endo").distance_to(midpoint_position) < 0.02
			and not fresh._endo_entry_dialogue_started,
		"fresh presenter reconstructs the same in-flight body without granting arrival")
	fresh.headless_advance(maxf(0.0, remaining - 0.01), 0.01)
	check(str(fresh._endo_entry_authority_state().get("phase", ""))
			== fresh.ENDO_ENTRY_PHASE_APPROACHING,
		"fresh load also remains pre-arrival until the saved endpoint")
	fresh.headless_advance(0.02, 0.01)
	check(str(fresh._endo_entry_authority_state().get("phase", ""))
			== fresh.ENDO_ENTRY_PHASE_ARRIVED
			and fresh._endo_entry_dialogue_started,
		"fresh load produces the same one-time arrival consequence")
	await _destroy_elevator(fresh)
	await _destroy_elevator(source)

	# Incapacitation interrupts the authored walk in GameState. Recovery starts a
	# new saved leg from the actual body position; it never cashes out the endpoint.
	var interrupted := await _spawn_elevator()
	interrupted._load_chunk("junction")
	interrupted._current_step = "junction_arrive"
	interrupted._start_endo_enters()
	interrupted.headless_advance(0.22, 0.01)
	interrupted._game_state.down_character("endo")
	var stopped: Dictionary = interrupted._endo_entry_authority_state()
	check(str(stopped.get("phase", "")) == interrupted.ENDO_ENTRY_PHASE_INTERRUPTED
			and not interrupted._game_state.is_moving("endo")
			and not interrupted._endo_entry_dialogue_started,
		"downing Endo interrupts the approach without teleporting or joining him")
	var interrupted_position: Vector3 = interrupted._game_state.get_position("endo")
	interrupted.headless_advance(1.0, 0.01)
	check(interrupted._game_state.get_position("endo").distance_to(
			interrupted_position) < 0.01
			and str(interrupted._endo_entry_authority_state().get("phase", ""))
				== interrupted.ENDO_ENTRY_PHASE_INTERRUPTED,
		"an interrupted entry remains visibly stopped instead of completing on a stale timer")
	interrupted._game_state.restore_character("endo")
	var resumed: Dictionary = interrupted._endo_entry_authority_state()
	check(str(resumed.get("phase", "")) == interrupted.ENDO_ENTRY_PHASE_APPROACHING
			and int(resumed.get("attempt", 0)) == 2
			and interrupted._game_state.is_moving("endo"),
		"recovery resumes a second authoritative leg from the interruption point")
	var resumed_remaining: float = float(resumed.get("arrival_deadline", -1.0)) \
		- interrupted._scheduler.get_current_tick()
	interrupted.headless_advance(maxf(0.0, resumed_remaining) + 0.02, 0.01)
	check(str(interrupted._endo_entry_authority_state().get("phase", ""))
			== interrupted.ENDO_ENTRY_PHASE_ARRIVED
			and interrupted._endo_entry_dialogue_started,
		"resumed physical arrival, not recovery itself, commits Endo's story beat")
	await _destroy_elevator(interrupted)


func _static_guardrails() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/tutorial/elevator_sequence.gd")
	check("command_begin_mechanism_phase" in source and "pick_up_item(\"endo\"" in source,
		"source guard: the handoff uses saved mechanism and canonical item authority")
	check("schedule_after(1.5, _endo_pickup_drink" not in source,
		"source guard: no fixed scene callback owns pickup completion")
	check("_endo.add_child(_drink_mesh)" not in source,
		"source guard: no view-only reparent can impersonate a held item")
	check("_horizontal_distance(" in source and "_endo_holds_drink()" in source,
		"source guard: delivery checks physical endpoint and canonical hand state")
	check("ENDO_ENTRY_PHASE_APPROACHING" in source
			and "_commit_endo_entry_arrival" in source
			and "\"endo_enters\":" in source,
		"source guard: Endo's entrance has a saved phase and arrival-owned commit")
	check("schedule_after(1.0, _start_endo_shelter" not in source,
		"source guard: elapsed dialogue time cannot commit the shelter transition")
	check("_schedule_portable_method(2.0, _start_endo_enters" in source
			and "schedule_after(2.0, _start_endo_enters" not in source,
		"source guard: the plant-to-Endo dusk handoff survives save/load")
	check("set_pre_trigger_validator(_validate_junction_plant_trigger)" in source
			and "func _on_junction_plant_interacted" in source
			and "plant_interact.interacted.connect(func" not in source,
		"source guard: Junction validates party truth before consuming its named plant one-shot")
	var forbidden_linear_callbacks := [
		"schedule_after(1.0, _start_consciousness_fragments",
		"schedule_after(5.8, _start_fade_in",
		"schedule_after(1.5, _start_waking",
		"func(): _scheduler.schedule_after",
		"dialogue_finished.connect(func()",
		"schedule_after(2.0, _start_rally_tutorial",
		"schedule_after(0.2, _start_route_read_circuit",
		"schedule_after(0.35, _start_route_choice",
		"schedule_after(1.5, _start_gauntlet",
	]
	var raw_linear_callback := false
	for forbidden in forbidden_linear_callbacks:
		raw_linear_callback = raw_linear_callback or str(forbidden) in source
	check(not raw_linear_callback
			and "_dialogue_chain([\"elevator.aster.surface\"], _queue_start_conversation)" \
				in source
			and "_dialogue_chain([\"elevator.bridge.narration\"]," in source,
		"source guard: Elevator's causal story line uses named portable continuations")


func _spawn_elevator() -> Node:
	var elevator := ElevatorScene.instantiate()
	elevator.suppress_scene_change = true
	root.add_child(elevator)
	for _frame in range(8):
		await process_frame
	_clear_sequence_runtime(elevator)
	return elevator


func _stage_endo_at_water(elevator: Node) -> void:
	elevator._load_chunk("junction")
	var drink_id := str(elevator._ensure_endo_drink_item())
	var source_pos: Vector3 = elevator._endo_drink_ground_position()
	if not elevator._game_state.characters.has("endo"):
		elevator._endo.visible = true
		elevator._endo.global_position = source_pos
		elevator._register_gs_character("endo", elevator._endo, 2.5, {
			"hp": GameState.HP_MAX,
		})
	else:
		elevator._game_state.command_stop("endo")
		elevator._game_state.snap_character_to("endo", source_pos)
		elevator._endo.global_position = source_pos
	elevator._current_step = "junction_arrive"
	elevator._sync_endo_drink_presenter()
	check(drink_id != "", "fixture resolves the unique water-container item")


func _clear_sequence_runtime(elevator: Node) -> void:
	elevator._scheduler.clear()
	elevator._scheduler.resume()
	if elevator._dialogue != null and elevator._dialogue.has_method("clear"):
		elevator._dialogue.clear()
	if elevator._tutorial_prompt != null:
		elevator._tutorial_prompt.hide_prompt()


func _item_is_grounded(elevator: Node, item_id: String) -> bool:
	if item_id == "" or not elevator._game_state.items.has(item_id):
		return false
	var item: Dictionary = elevator._game_state.items[item_id]
	return str(item.get("location", "")) == "ground" \
		and str(item.get("holder", "")) == ""


func _item_is_held_by_endo(elevator: Node, item_id: String) -> bool:
	if item_id == "" or not elevator._game_state.items.has(item_id):
		return false
	var item: Dictionary = elevator._game_state.items[item_id]
	return str(item.get("location", "")) == "hand" \
		and str(item.get("holder", "")) == "endo" \
		and elevator._game_state.get_hand_items("endo").has(item_id)


func _event_count(elevator: Node) -> int:
	return elevator._game_state.event_log.events.size() \
		if elevator._game_state.event_log != null else 0


func _destroy_elevator(elevator: Node) -> void:
	if elevator != null and is_instance_valid(elevator):
		if elevator.has_method("_teardown_sequence"):
			elevator._teardown_sequence()
		elevator.free()
	await process_frame


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
