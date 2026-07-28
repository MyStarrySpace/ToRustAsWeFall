extends SceneTree

## Regression for the Inflammashunt's physical causal chain. Opening a valve, tending a
## root, and opening a housing are saved processes with visible intermediate states; none
## may grant its downstream stock at interaction-start or from render-frame time.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const ChunkScript := preload("res://scripts/fragments/chunks/inflammashunt_chunk.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_exact_source_authority()
	var fixture := await _verify_same_presenter_and_interruption()
	await _verify_fresh_water_restore(fixture.water_midpoint)
	await _verify_fresh_root_restore(fixture.root_midpoint)
	await _verify_fresh_housing_restore(fixture.housing_midpoint)
	await _verify_device_claim_authority(fixture.open_source)
	await _verify_absence_retracts_future(fixture.baseline)
	print("INFLAMMASHUNT PROCESS AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_exact_source_authority() -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	var pipe: Node = chunk.find_child("PipeDiagram", true, false)
	var dead_roots: Node = chunk.find_child("DeadRootNetwork", true, false)
	check(pipe != null and dead_roots != null,
		"exact-source fixture contains the authored route-read objects")
	check(chunk._interaction_sources.size() == 19,
		"all nineteen authored Inflammashunt actions are bound to exact physical sources")

	chunk._on_pipe_diagram()
	check(not bool(chunk.route_info["aster_pipe_diagram"]),
		"the retired route callback cannot publish knowledge")
	check(not bool(chunk._read_pipe_diagram_from_receipt()),
		"the internal route consequence refuses without a consumed source receipt")
	pipe.emit_signal("interacted")
	check(not bool(chunk.route_info["aster_pipe_diagram"]),
		"manual signal emission cannot publish route knowledge")
	chunk._on_inflammashunt_source_interacted(ChunkScript.ACTION_PIPE_DIAGRAM, dead_roots)
	check(not bool(chunk.route_info["aster_pipe_diagram"]),
		"a different live Interactable cannot impersonate the pipe diagram")

	var pipe_pos := _source_position(gs, pipe)
	gs.snap_character_to("aster", pipe_pos + Vector3(8.0, 0.0, 0.0))
	gs.snap_character_to("peris", pipe_pos)
	pipe.set("active_character", "aster")
	check(not bool(pipe.call("_trigger", false))
			and gs.is_interactable_enabled(str(pipe.get("data_id"))),
		"a selected actor string cannot borrow another nearby body")
	pipe.set("active_character", "peris")
	check(not bool(pipe.call("_trigger", false))
			and gs.is_interactable_enabled(str(pipe.get("data_id"))),
		"the wrong nearby character cannot service an Aster-coded source")

	gs.snap_character_to("aster", pipe_pos)
	var moved := bool(gs.command_move_to_pos("aster", pipe_pos + Vector3(-1.5, 0.0, 0.0)))
	pipe.set("active_character", "aster")
	check(moved and gs.is_moving("aster") and not bool(pipe.call("_trigger", false))
			and gs.is_interactable_enabled(str(pipe.get("data_id"))),
		"a moving body cannot consume a source receipt")
	gs.command_stop("aster")
	check(_trigger_source(chunk, gs, "PipeDiagram", "aster")
			and bool(chunk.route_info["aster_pipe_diagram"]),
		"the same source remains retryable once its actual body is free")
	var read_capture := _capture(host)
	_apply_capture(host, chunk, read_capture)
	check(bool(chunk.route_info["aster_pipe_diagram"])
			and not gs.is_interactable_enabled(str(pipe.get("data_id"))),
		"a committed one-shot read remains spent across same-presenter restore")

	# Repeatable controls still consume distinct one-shot receipts. Two failed dry scrapes in the
	# same scheduler tick must have two monotonic identities rather than one sticky boolean.
	var char_a: Node = chunk.find_child("CharDepositA", true, false)
	check(_trigger_source(chunk, gs, "CharDepositA", "aster")
			and _trigger_source(chunk, gs, "CharDepositA", "aster"),
		"a retryable control can accept two distinct physical attempts in one tick")
	var char_spec: Dictionary = gs.get_interactable(str(char_a.get("data_id")))
	check(int(char_spec.get("trigger_count", 0)) == 2
			and int(chunk._source_committed_counts.get(ChunkScript.ACTION_CHAR_A, 0)) == 2
			and str(chunk.char_a_state) == "dry",
		"same-tick retries retain monotonic receipt identity without inventing progress")
	await _discard(host)

	# Consciousness/narrative availability is checked before GameState accepts the world source.
	context = await _boot()
	host = context.host
	chunk = context.chunk
	gs = host.game_state
	var log: Node = chunk.find_child("AsterLogTerminal", true, false)
	gs.snap_character_to("aster", _source_position(gs, log))
	gs.set_stat("aster", "hp", 0.0, "inflammashunt_source_guard")
	log.set("active_character", "aster")
	check(gs.is_downed("aster") and not bool(log.call("_trigger", false))
			and not bool(chunk.route_info["aster_log"])
			and gs.is_interactable_enabled(str(log.get("data_id"))),
		"an unconscious body leaves the consequential read untouched and retryable")
	await _discard(host)

	# Capture synchronously from GameState's accepted-trigger signal, before the callback can publish
	# a water phase. Restore must retract that orphan receipt instead of replaying a remote valve.
	context = await _boot()
	host = context.host
	chunk = context.chunk
	gs = host.game_state
	var valve: Node = chunk.find_child("DrainageValve", true, false)
	var valve_id := str(valve.get("data_id"))
	var accepted_box := {"value": {}}
	var accepted_capture := func(data_id: String, _actor: String) -> void:
		if data_id == valve_id:
			accepted_box["value"] = _capture(host)
	gs.interactable_triggered.connect(accepted_capture, CONNECT_ONE_SHOT)
	check(_trigger_source(chunk, gs, "DrainageValve", "aster")
			and not (accepted_box["value"] as Dictionary).is_empty(),
		"the verifier captures the accepted-source-before-callback seam")
	var accepted_only: Dictionary = accepted_box["value"]
	_apply_capture(host, chunk, accepted_only)
	check(str(chunk.water_phase) == "dry" and not bool(chunk.valve_open)
			and gs.is_interactable_enabled(valve_id),
		"same-presenter restore re-arms an accepted valve with no semantic commitment")
	check(_trigger_source(chunk, gs, "DrainageValve", "aster")
			and str(chunk.water_phase) == "flowing",
		"the retracted accepted source can be honestly retried")
	await _discard(host)

	var fresh := await _boot()
	_apply_capture(fresh.host, fresh.chunk, accepted_only)
	var fresh_valve: Node = fresh.chunk.find_child("DrainageValve", true, false)
	check(str(fresh.chunk.water_phase) == "dry"
			and fresh.host.game_state.is_interactable_enabled(str(fresh_valve.get("data_id"))),
		"a fresh presenter also retracts the orphan accepted source")
	await _discard(fresh.host)


func _verify_same_presenter_and_interruption() -> Dictionary:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	var baseline := _capture(host)
	var initial: Dictionary = chunk.headless_get_state()
	var initial_presenters: Dictionary = initial.get("process_presenters", {})
	check(int(initial_presenters.get("water_total", 0)) >= 6
			and int(initial_presenters.get("filaments_total", 0)) >= 4,
		"the room contains visible water-route and root-filament presenters")
	var feedback: Dictionary = chunk.get_causal_feedback_state()
	check(int(feedback.get("count", 0)) >= 4,
		"hover/planning feedback exposes the valve's effects and the root-to-housing link")

	check(_trigger_source(chunk, gs, "DrainageValve", "aster"),
		"a nearby body opens the exact drainage valve")
	var state: Dictionary = chunk.headless_get_state()
	check(str(state.get("water_phase", "")) == "flowing"
			and bool(state.get("valve_open", false)),
		"opening the valve starts a saved flow phase")
	check(str(state.get("char_a_state", "")) == "dry"
			and str(state.get("char_b_state", "")) == "dry",
		"the interaction cannot remotely damp either deposit before water arrives")
	check(not gs.is_interactable_enabled(chunk._interactable_data_id("DrainageValve")),
		"the moving valve process rejects interaction spam")
	host.scheduler.advance_ticks(ChunkScript.WATER_FLOW_DURATION * 0.5)
	chunk.headless_process(0.0)
	state = chunk.headless_get_state()
	var water_presenters: Dictionary = state.get("process_presenters", {})
	var water_visible := int(water_presenters.get("water_visible", 0))
	check(water_visible > 0 and water_visible < int(water_presenters.get("water_total", 0)),
		"the saved midpoint is visibly partway along the floor channel")
	check(str(state.get("char_a_state", "")) == "dry",
		"the midpoint remains an unresolved physical process")
	var water_midpoint := _capture(host)
	chunk.headless_process(1000.0)
	check(int((chunk.headless_get_state().get("process_presenters", {}) as Dictionary).get("water_visible", -1))
			== water_visible and str(chunk.water_phase) == "flowing",
		"render-frame time cannot advance water or its deterministic presenter")
	chunk._finish_water_flow()
	check(str(chunk.water_phase) == "flowing" and str(chunk.char_a_state) == "dry",
		"the retired direct water-completion helper cannot skip the saved arrival deadline")
	host.scheduler.advance_ticks(ChunkScript.WATER_FLOW_DURATION * 0.5 - 0.001)
	check(str(chunk.water_phase) == "flowing" and str(chunk.char_a_state) == "dry",
		"wetness cannot commit before the absolute arrival deadline")
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.water_phase) == "full" and str(chunk.char_a_state) == "damp"
			and str(chunk.char_b_state) == "damp",
		"arriving water visibly and mechanically dampens both deposits exactly once")

	_apply_capture(host, chunk, water_midpoint)
	_apply_capture(host, chunk, water_midpoint)
	check(str(chunk.water_phase) == "flowing" and str(chunk.char_a_state) == "dry",
		"same-presenter rollback idempotently restores the unresolved water midpoint")
	host.scheduler.advance_ticks(ChunkScript.WATER_FLOW_DURATION * 0.5)
	check(str(chunk.water_phase) == "full" and str(chunk.char_a_state) == "damp",
		"restored water consumes only its saved remainder")

	chunk.char_a_state = "cleared"
	chunk.char_b_state = "cleared"
	chunk._sync_char_visuals()
	chunk._publish_inflammashunt_authority()
	check(_trigger_source(chunk, gs, "RootTendril", "peris"),
		"Peris tends the exact nearby root source")
	check(str(chunk.root_state) == "connecting" and not bool(chunk.housing_unlocked),
		"tending starts filament growth without granting the housing lock")
	host.scheduler.advance_ticks(1.0)
	chunk.headless_process(0.0)
	state = chunk.headless_get_state()
	var root_presenters: Dictionary = state.get("process_presenters", {})
	check(int(root_presenters.get("filaments_visible", 0)) > 0
			and int(root_presenters.get("filaments_visible", 0)) < int(root_presenters.get("filaments_total", 0)),
		"root filaments visibly occupy an intermediate growth state")
	var root_midpoint := _capture(host)
	host.scheduler.advance_ticks(ChunkScript.ROOT_CONNECT_DURATION - 1.001)
	check(str(chunk.root_state) == "connecting" and not bool(chunk.housing_unlocked),
		"the living lock cannot release early")
	host.scheduler.advance_ticks(0.001)
	check(str(chunk.root_state) == "connected" and bool(chunk.housing_unlocked),
		"the completed filament reaches and releases the housing")

	check(_trigger_source(chunk, gs, "DeviceHousing", "aster"),
		"a nearby body starts the exact housing control")
	check(str(chunk.housing_state) == "opening" and not bool(chunk.device_retrieved)
			and str(chunk._phase) != "complete",
		"opening the housing starts a phase rather than granting the device")
	host.scheduler.advance_ticks(0.5)
	chunk.headless_process(0.0)
	state = chunk.headless_get_state()
	var lid_angle := float((state.get("process_presenters", {}) as Dictionary).get("lid_angle", 0.0))
	check(lid_angle < -0.05 and lid_angle > -1.30,
		"the actual housing lid is visibly partway open")
	var housing_midpoint := _capture(host)

	check(_trigger_source(chunk, gs, "StrikeCluster", "aster"),
		"the exact nearby strike source can interrupt the living circuit")
	check(str(chunk.housing_state) == "sealed" and not bool(chunk.device_retrieved)
			and not bool(chunk.housing_unlocked),
		"breaking the living circuit interrupts and reseals an in-flight housing opening")
	host.scheduler.advance_ticks(ChunkScript.HOUSING_OPEN_DURATION + 0.5)
	check(not bool(chunk.device_retrieved) and str(chunk._phase) != "complete",
		"a cancelled opening has no orphaned completion callback")

	_apply_capture(host, chunk, housing_midpoint)
	_apply_capture(host, chunk, housing_midpoint)
	check(str(chunk.housing_state) == "opening" and not bool(chunk.device_retrieved),
		"same-presenter rollback reconstructs the opening lid and pending consequence")
	host.scheduler.advance_ticks(ChunkScript.HOUSING_OPEN_DURATION - 0.501)
	check(not bool(chunk.device_retrieved),
		"restored housing cannot yield the catalyst before its original deadline")
	host.scheduler.advance_ticks(0.001)
	state = chunk.headless_get_state()
	check(str(chunk.housing_state) == "open" and not bool(chunk.device_retrieved)
			and str(chunk._phase) != "complete",
		"the fully opened lid exposes the device without pretending it was retrieved")
	check(str(state.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_AVAILABLE
			and bool(state.get("device_item_at_source", false))
			and str(state.get("device_item_id", "")) != "",
		"the open housing contains one source-tagged physical catalyst")
	var device_item: Dictionary = gs.items.get(str(state.get("device_item_id", "")), {})
	var device_properties: Dictionary = device_item.get("properties", {})
	check(str(device_properties.get("visual_scene", "")) == ChunkScript.DEVICE_VISUAL_SCENE
			and str(device_properties.get("visual_identity", ""))
				== "inflammashunt_resolution_catalyst_v1",
		"the physical catalyst carries its portable visual identity from source to hand")
	check(_portable_device_visual_has_uvs(),
		"the catalyst wrapper loads an external UV-mapped model instead of a proxy box")
	var open_source := _capture(host)
	check(_trigger_source(chunk, gs, "InflammashuntDevice", "aster"),
		"a nearby named actor with one free hand can lift the exact device")
	state = chunk.headless_get_state()
	check(bool(state.get("device_retrieved", false))
			and str(state.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_CLAIMED
			and str(state.get("device_item_holder", "")) == "aster"
			and str(chunk._phase) == "complete",
		"only the committed item pickup completes the fragment")
	await _discard(host)
	return {
		"baseline": baseline,
		"water_midpoint": water_midpoint,
		"root_midpoint": root_midpoint,
		"housing_midpoint": housing_midpoint,
		"open_source": open_source,
	}


func _verify_fresh_water_restore(midpoint: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	_apply_capture(host, chunk, midpoint)
	check(str(chunk.water_phase) == "flowing" and str(chunk.char_a_state) == "dry",
		"a fresh presenter reconstructs the unresolved water phase")
	host.scheduler.advance_ticks(ChunkScript.WATER_FLOW_DURATION * 0.5)
	check(str(chunk.water_phase) == "full" and str(chunk.char_a_state) == "damp",
		"fresh water restore commits after only the saved remainder")
	await _discard(host)


func _verify_fresh_root_restore(midpoint: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	_apply_capture(host, chunk, midpoint)
	var state: Dictionary = chunk.headless_get_state()
	check(str(state.get("root_state", "")) == "connecting" and not bool(state.get("housing_unlocked", true)),
		"a fresh presenter restores root growth without granting its downstream lock")
	host.scheduler.advance_ticks(ChunkScript.ROOT_CONNECT_DURATION - 1.0)
	check(str(chunk.root_state) == "connected" and bool(chunk.housing_unlocked),
		"fresh root restore finishes at its saved absolute deadline")
	await _discard(host)


func _verify_fresh_housing_restore(midpoint: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	_apply_capture(host, chunk, midpoint)
	var state: Dictionary = chunk.headless_get_state()
	var angle := float((state.get("process_presenters", {}) as Dictionary).get("lid_angle", 0.0))
	check(str(state.get("housing_state", "")) == "opening" and angle < -0.05,
		"a fresh presenter reconstructs the saved lid midpoint")
	host.scheduler.advance_ticks(ChunkScript.HOUSING_OPEN_DURATION - 0.5)
	var state_after: Dictionary = chunk.headless_get_state()
	check(not bool(chunk.device_retrieved) and str(chunk.housing_state) == "open"
			and bool(state_after.get("device_item_at_source", false)),
		"fresh housing restore exposes the same source item without granting retrieval")
	await _discard(host)


func _verify_device_claim_authority(open_source: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	var gs = host.game_state
	_apply_capture(host, chunk, open_source)
	var source_id := str(chunk.headless_get_state().get("device_item_id", ""))
	check(source_id != "" and chunk._is_device_item(source_id),
		"restore preserves the exact source-tagged catalyst identity")

	# An interaction method call is not a teleporting inventory grant: ordinary pickup distance and
	# free-hand authority still reject it.
	gs.snap_character_to(
		"aster", ChunkScript.DEVICE_SOURCE_POS + Vector3(-8.0, 0.0, 0.0))
	chunk._device_it.active_character = "aster"
	check(not bool(chunk._device_it._trigger(false)) and bool(chunk._device_item_at_source()),
		"an actor outside pickup range cannot consume the open device source")
	gs.snap_character_to("aster", ChunkScript.DEVICE_SOURCE_POS)
	var filler_a: String = str(gs.spawn_item("seed", ChunkScript.DEVICE_SOURCE_POS, {"test_filler": true}))
	var filler_b: String = str(gs.spawn_item("seed", ChunkScript.DEVICE_SOURCE_POS, {"test_filler": true}))
	check(gs.pick_up_item("aster", filler_a) and gs.pick_up_item("aster", filler_b),
		"fixture fills both of Aster's real hand slots")
	check(not bool(chunk._device_it._trigger(false)) and bool(chunk._device_item_at_source())
			and str(chunk._device_phase) == ChunkScript.DEVICE_PHASE_AVAILABLE,
		"full hands refuse before consuming the source or advancing its claim transaction")
	gs.remove_item(filler_a)
	gs.remove_item(filler_b)

	# Capture after GameState accepts the device source but before its callback begins CLAIMING.
	# Restore must re-arm the physical source rather than translating that orphan receipt into loot.
	var device_source: Node = chunk.find_child("InflammashuntDevice", true, false)
	var device_data_id := str(device_source.get("data_id"))
	var accepted_box := {"value": {}}
	var capture_accepted := func(data_id: String, _actor: String) -> void:
		if data_id == device_data_id:
			accepted_box["value"] = _capture(host)
	gs.interactable_triggered.connect(capture_accepted, CONNECT_ONE_SHOT)
	check(_trigger_source(chunk, gs, "InflammashuntDevice", "aster")
			and not (accepted_box["value"] as Dictionary).is_empty(),
		"the verifier captures the device's accepted-source-before-callback seam")
	var accepted_only: Dictionary = accepted_box["value"]
	_apply_capture(host, chunk, accepted_only)
	check(str(chunk._device_phase) == ChunkScript.DEVICE_PHASE_AVAILABLE
			and chunk._device_item_at_source()
			and not bool(chunk.device_retrieved)
			and str(chunk._phase) != "complete"
			and gs.is_interactable_enabled(device_data_id)
			and gs.get_hand_items("aster").is_empty(),
		"same-presenter restore retracts an orphan device receipt to its exact source item")
	var accepted_fresh := await _boot()
	_apply_capture(accepted_fresh.host, accepted_fresh.chunk, accepted_only)
	var accepted_fresh_source: Node = accepted_fresh.chunk.find_child(
		"InflammashuntDevice", true, false)
	check(str(accepted_fresh.chunk._device_phase) == ChunkScript.DEVICE_PHASE_AVAILABLE
			and accepted_fresh.chunk._device_item_at_source()
			and not bool(accepted_fresh.chunk.device_retrieved)
			and accepted_fresh.host.game_state.is_interactable_enabled(
				str(accepted_fresh_source.get("data_id")))
			and accepted_fresh.host.game_state.get_hand_items("aster").is_empty(),
		"a fresh presenter also retracts the orphan device receipt without granting loot")
	await _discard(accepted_fresh.host)

	# The saved source identity wins over any forged duplicate item on restore.
	var duplicate_id := str(chunk._spawn_device_item({"duplicate_save_fixture": true}))
	check(duplicate_id != "" and duplicate_id != source_id,
		"device duplicate fixture creates a distinct tagged catalyst")
	var duplicated_source := _capture(host)
	_apply_capture(host, chunk, duplicated_source)
	check(str(chunk._device_item_id) == source_id
			and gs.items.has(source_id)
			and not gs.items.has(duplicate_id)
			and _count_device_items(chunk, gs) == 1,
		"same-presenter restore keeps the saved catalyst and removes duplicate rewards")
	var duplicate_fresh := await _boot()
	_apply_capture(duplicate_fresh.host, duplicate_fresh.chunk, duplicated_source)
	check(str(duplicate_fresh.chunk._device_item_id) == source_id
			and duplicate_fresh.host.game_state.items.has(source_id)
			and not duplicate_fresh.host.game_state.items.has(duplicate_id)
			and _count_device_items(
				duplicate_fresh.chunk, duplicate_fresh.host.game_state) == 1,
		"a fresh presenter also removes a forged duplicate catalyst")
	await _discard(duplicate_fresh.host)

	# If the saved exact source disappears, another tagged item is not allowed to impersonate it.
	# Because this claim has not started, restore may retract to one newly spawned source item.
	gs.remove_item(source_id)
	var forged_source_id := str(chunk._spawn_device_item(
		{"forged_missing_source_fixture": true}))
	var missing_exact_source := _capture(host)
	_apply_capture(host, chunk, missing_exact_source)
	var recovered_source_id := str(chunk._device_item_id)
	check(recovered_source_id != "" and recovered_source_id != source_id
			and recovered_source_id != forged_source_id
			and chunk._device_item_at_source()
			and not gs.items.has(forged_source_id)
			and _count_device_items(chunk, gs) == 1
			and not bool(chunk.device_retrieved),
		"a missing unclaimed catalyst retracts to one new source instead of adopting a forgery")
	var missing_fresh := await _boot()
	_apply_capture(missing_fresh.host, missing_fresh.chunk, missing_exact_source)
	check(str(missing_fresh.chunk._device_item_id) != forged_source_id
			and missing_fresh.chunk._device_item_at_source()
			and not missing_fresh.host.game_state.items.has(forged_source_id)
			and _count_device_items(
				missing_fresh.chunk, missing_fresh.host.game_state) == 1
			and not bool(missing_fresh.chunk.device_retrieved),
		"a fresh presenter also refuses to adopt a forged replacement source")
	await _discard(missing_fresh.host)
	source_id = recovered_source_id

	check(not bool(chunk._on_take_device())
			and not bool(chunk._take_device_from_receipt("aster"))
			and chunk._device_item_at_source(),
		"retired and receipt-less device helpers cannot grant the catalyst")

	# Capture exactly inside GameState's synchronous pickup signal: the item has moved, while the
	# chunk's durable transaction is still CLAIMING. Restore must finish that same actor/item claim.
	var capture_box := {"value": {}}
	var capture_pickup := func(char_id: String, item_id: String) -> void:
		if char_id == "aster" and item_id == source_id:
			capture_box["value"] = _capture(host)
	gs.item_picked_up.connect(capture_pickup, CONNECT_ONE_SHOT)
	check(_trigger_source(chunk, gs, "InflammashuntDevice", "aster")
			and not (capture_box["value"] as Dictionary).is_empty(),
		"the verifier captured the real pickup-signal save seam")
	var signal_capture: Dictionary = capture_box["value"]
	_apply_capture(host, chunk, signal_capture)
	_apply_capture(host, chunk, signal_capture)
	var restored: Dictionary = chunk.headless_get_state()
	check(bool(restored.get("device_retrieved", false))
			and str(restored.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_CLAIMED
			and str(restored.get("device_item_id", "")) == source_id
			and str(restored.get("device_item_holder", "")) == "aster"
			and int(restored.get("device_claim_serial", 0)) == 1
			and gs.get_hand_items("aster").count(source_id) == 1
			and _count_device_items(chunk, gs) == 1,
		"repeated pickup-signal restore completes the reserved actor's exact item once")
	gs.remove_item(source_id)
	var consumed_claim := _capture(host)
	_apply_capture(host, chunk, consumed_claim)
	restored = chunk.headless_get_state()
	check(bool(restored.get("device_retrieved", false))
			and str(restored.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_CLAIMED
			and str(restored.get("device_item_id", "")) == source_id
			and chunk._find_device_item_id() == ""
			and str(chunk._phase) == "complete",
		"a consumed/stored claimed catalyst remains an exact-once tombstone instead of respawning")

	var consumed_fresh := await _boot()
	_apply_capture(consumed_fresh.host, consumed_fresh.chunk, consumed_claim)
	var fresh_consumed_state: Dictionary = consumed_fresh.chunk.headless_get_state()
	check(bool(fresh_consumed_state.get("device_retrieved", false))
			and str(fresh_consumed_state.get("device_item_id", "")) == source_id
			and consumed_fresh.chunk._find_device_item_id() == "",
		"a fresh presenter also preserves the claimed catalyst tombstone without a duplicate reward")
	await _discard(consumed_fresh.host)

	var forged_id := str(chunk._spawn_device_item({"forged_claim_fixture": true}))
	var forged_claim := _capture(host)
	_apply_capture(host, chunk, forged_claim)
	restored = chunk.headless_get_state()
	check(str(restored.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_CLAIMED
			and str(restored.get("device_item_id", "")) == source_id
			and not gs.items.has(forged_id)
			and chunk._find_device_item_id() == "",
		"a forged tagged item cannot replace the completed claim's exact tombstone")
	var forged_fresh := await _boot()
	_apply_capture(forged_fresh.host, forged_fresh.chunk, forged_claim)
	var forged_fresh_state: Dictionary = forged_fresh.chunk.headless_get_state()
	check(str(forged_fresh_state.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_CLAIMED
			and str(forged_fresh_state.get("device_item_id", "")) == source_id
			and not forged_fresh.host.game_state.items.has(forged_id)
			and forged_fresh.chunk._find_device_item_id() == "",
		"a fresh presenter cannot resurrect a claimed catalyst through a forged duplicate")
	await _discard(forged_fresh.host)
	await _discard(host)

	# A forged/mismatched holder may not be silently substituted for the reserved claimant.
	context = await _boot()
	host = context.host
	chunk = context.chunk
	gs = host.game_state
	_apply_capture(host, chunk, open_source)
	source_id = str(chunk.headless_get_state().get("device_item_id", ""))
	gs.snap_character_to("peris", ChunkScript.DEVICE_SOURCE_POS)
	chunk._device_phase = ChunkScript.DEVICE_PHASE_CLAIMING
	chunk._device_claimed_by = "aster"
	chunk._device_claim_serial = 1
	chunk._publish_inflammashunt_authority()
	check(gs.pick_up_item("peris", source_id), "fixture injects a mismatched physical holder")
	var mismatched := _capture(host)
	_apply_capture(host, chunk, mismatched)
	restored = chunk.headless_get_state()
	check(not bool(restored.get("device_retrieved", true))
			and str(restored.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_CLAIMING
			and str(restored.get("device_item_holder", "")) == "peris"
			and str(chunk._phase) != "complete",
		"restore never retargets a reserved claim to the wrong physical carrier")
	await _discard(host)

	# A different tagged item in the reserved actor's hand is still not the saved exact item. This
	# is the high-value load exploit: substituting it would turn a forged inventory entry into
	# completion. Restore instead removes it and re-arms one visible unclaimed source.
	context = await _boot()
	host = context.host
	chunk = context.chunk
	gs = host.game_state
	_apply_capture(host, chunk, open_source)
	source_id = str(chunk.headless_get_state().get("device_item_id", ""))
	gs.remove_item(source_id)
	var forged_claim_id := str(chunk._spawn_device_item(
		{"forged_claim_substitute_fixture": true}))
	gs.snap_character_to("aster", ChunkScript.DEVICE_SOURCE_POS)
	check(gs.pick_up_item("aster", forged_claim_id),
		"fixture puts a forged tagged catalyst in the reserved actor's hand")
	chunk._device_phase = ChunkScript.DEVICE_PHASE_CLAIMING
	chunk._device_claimed_by = "aster"
	chunk._device_claim_serial = 1
	chunk._publish_inflammashunt_authority()
	var forged_substitution := _capture(host)
	_apply_capture(host, chunk, forged_substitution)
	restored = chunk.headless_get_state()
	check(not bool(restored.get("device_retrieved", true))
			and str(restored.get("device_phase", "")) == ChunkScript.DEVICE_PHASE_AVAILABLE
			and str(restored.get("device_item_id", "")) != forged_claim_id
			and bool(restored.get("device_item_at_source", false))
			and not gs.items.has(forged_claim_id)
			and not gs.get_hand_items("aster").has(forged_claim_id)
			and str(chunk._phase) != "complete",
		"a claiming restore cannot substitute a forged tagged item held by the reserved actor")
	var forged_substitution_fresh := await _boot()
	_apply_capture(
		forged_substitution_fresh.host,
		forged_substitution_fresh.chunk,
		forged_substitution)
	var forged_substitution_fresh_state: Dictionary = \
		forged_substitution_fresh.chunk.headless_get_state()
	check(not bool(forged_substitution_fresh_state.get("device_retrieved", true))
			and str(forged_substitution_fresh_state.get("device_phase", "")) \
				== ChunkScript.DEVICE_PHASE_AVAILABLE
			and str(forged_substitution_fresh_state.get("device_item_id", "")) \
				!= forged_claim_id
			and bool(forged_substitution_fresh_state.get("device_item_at_source", false))
			and not forged_substitution_fresh.host.game_state.items.has(forged_claim_id),
		"a fresh presenter also rejects a forged claiming substitute")
	await _discard(forged_substitution_fresh.host)
	await _discard(host)


func _verify_absence_retracts_future(baseline: Dictionary) -> void:
	var context := await _boot()
	var host = context.host
	var chunk = context.chunk
	check(_trigger_source(chunk, host.game_state, "DrainageValve", "aster"),
		"absence fixture begins from a real valve trigger")
	var absent := baseline.duplicate(true)
	var world_state: Dictionary = (absent.get("game_state", {}) as Dictionary).get("world_state", {}) as Dictionary
	world_state.erase(ChunkScript.INFLAMMASHUNT_AUTHORITY_KEY)
	_apply_capture(host, chunk, absent)
	var state: Dictionary = chunk.headless_get_state()
	var presenters: Dictionary = state.get("process_presenters", {})
	check(str(state.get("water_phase", "")) == "dry"
			and str(state.get("root_state", "")) == "suppressed"
			and str(state.get("housing_state", "")) == "sealed"
			and not bool(state.get("device_retrieved", true)),
		"missing authority retracts every future physical process")
	check(int(presenters.get("water_visible", -1)) == 0
			and int(presenters.get("filaments_visible", -1)) == 0
			and is_zero_approx(float(presenters.get("lid_angle", 99.0))),
		"absence also retracts every derived process presenter")
	host.scheduler.advance_ticks(10.0)
	check(str(chunk.water_phase) == "dry" and not bool(chunk.device_retrieved),
		"absence restoration leaves no orphaned callbacks from the discarded future")
	await _discard(host)


func _boot() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = ChunkScript.new()
	chunk.attach_chunk_host(host, "inflammashunt_process_authority_fixture")
	# SceneChunk builds its Fragment on _ready; prime the same authored spawn map so canonical
	# characters exist before interactables and source items bind during construction.
	chunk.fragment = chunk._inflammashunt_fragment()
	for char_id_v in chunk.get_spawn_positions().keys():
		var char_id := str(char_id_v)
		host.game_state.register_character(char_id, chunk.get_spawn_positions()[char_id], 3.0, {
			"hp": 100.0, "stamina": 100.0, "atp": 8.0,
		})
	host.add_child(chunk)
	await process_frame
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	return {"host": host, "chunk": chunk}


func _source_position(gs, source: Node) -> Vector3:
	if gs == null or source == null:
		return Vector3.INF
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return Vector3.INF
	return gs.get_interactable(data_id).get("position", Vector3.INF)


func _trigger_source(chunk, gs, node_name: String, actor: String) -> bool:
	var source: Node = chunk.find_child(node_name, true, false)
	if source == null or gs == null or not gs.characters.has(actor):
		return false
	var source_position := _source_position(gs, source)
	if not source_position.is_finite():
		return false
	gs.snap_character_to(actor, source_position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	_notify_restore_children(chunk)
	chunk.on_game_state_snapshot_restored()


func _notify_restore_children(node: Node) -> void:
	for child in node.get_children():
		_notify_restore_children(child)
		if child.has_method("on_game_state_snapshot_restored"):
			child.call("on_game_state_snapshot_restored")


func _json_round_trip(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _portable_device_visual_has_uvs() -> bool:
	var packed := load(ChunkScript.DEVICE_VISUAL_SCENE) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate()
	var model := instance.get_node_or_null("Model") as MeshInstance3D
	var valid := model != null and model.mesh != null and model.mesh.get_surface_count() > 0
	if valid:
		var arrays: Array = model.mesh.surface_get_arrays(0)
		valid = arrays.size() > Mesh.ARRAY_TEX_UV \
			and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array \
			and not (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).is_empty()
	instance.free()
	return valid


func _count_device_items(chunk: Node, gs) -> int:
	var count := 0
	if chunk == null or gs == null or not "items" in gs:
		return count
	for item_id_v in gs.items.keys():
		if bool(chunk.call("_is_device_item", str(item_id_v))):
			count += 1
	return count


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await process_frame


func check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
