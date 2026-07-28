extends SceneTree

## Exploit regression for Endo's Junction. The chunk used to grant routes and the return grate as
## scene-local booleans: rollback retained the future on the same presenter, a fresh presenter forgot
## it, and the direct route damaged every party member without asking where anyone stood. This suite
## proves the replacement contract across traversal, HazardField, PartyGate3D, and chunk semantics.

const PreviewScene := preload("res://scenes/fragments/fragment_preview.tscn")
const EPSILON := 0.001

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_exact_source_receipts()
	await _verify_crossing_hazard_and_chunk_authority()
	await _verify_gate_midpoint_and_topology()
	await _verify_forage_claim_authority()
	await _verify_shelter_preflight_atomicity()
	print("ENDO JUNCTION SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_exact_source_receipts() -> void:
	var preview = await _spawn_preview()
	if preview == null:
		return
	var chunk = preview._active_chunk
	var gs: GameState = preview._game_state
	var controls := [
		[chunk._junction_interactable, "endo", Callable(chunk, "read_junction")],
		[chunk._route_interactable, "aster", Callable(chunk, "mark_safe_route")],
		[chunk._cache_interactable, "peris", Callable(chunk, "collect_forage")],
		[chunk._safe_interactable, "endo", Callable(chunk, "commit_safe_route")],
		[chunk._direct_interactable, "aster", Callable(chunk, "commit_direct_route")],
		[chunk._shortcut_interactable, "endo", Callable(chunk, "unlock_shortcut")],
		[chunk._shelter_interactable, "aster", Callable(chunk, "reach_shelter")],
	]
	for control_v in controls:
		var control: Node = control_v[0]
		var actor := str(control_v[1])
		var helper: Callable = control_v[2]
		control.set("active_character", actor)
		check(not bool(helper.call()),
			"%s public no-source helper is inert" % control.name)
		check(not bool(helper.call(control)),
			"%s callback cannot be forged with an unconsumed source" % control.name)

	# A manually emitted presentation signal also lacks GameState's accepted one-shot receipt.
	chunk._direct_interactable.set("active_character", "aster")
	chunk._direct_interactable.interacted.emit()
	check(str(chunk.get_preview_state().get("route_phase", "")) == "junction"
			and not gs.is_external_traversal_active("aster"),
		"manually emitted interaction feedback cannot manufacture a direct crossing")

	# A route prerequisite rejects before the one-shot is spent.
	check(not _trigger_endo_control(
			preview, chunk._route_interactable, "aster", true),
		"route mark refuses its exact nearby Aster before Endo reads the junction")
	check(_control_is_unspent(gs, chunk._route_interactable),
		"failed route preflight leaves its exact one-shot unspent")
	check(not _trigger_endo_control(
			preview, chunk._safe_interactable, "endo", true),
		"safe ledge pre-validator refuses nearby Endo before the route is marked")
	check(_control_is_rearmed(gs, chunk._safe_interactable),
		"failed safe-ledger prerequisite does not spend its one-shot")

	# Capture the narrow accepted-trigger/pre-owner seam. Keep Aster selected while the exact
	# Interactable names Endo; neither the selected portrait nor a remote Endo may impersonate him.
	preview.headless_select_character("aster")
	chunk._junction_interactable.set("active_character", "endo")
	check(not bool(chunk._junction_interactable.call("_trigger", false)),
		"selected Aster cannot make remote Endo read the junction")
	check(_control_is_rearmed(gs, chunk._junction_interactable),
		"remote-body refusal leaves the junction source retryable")
	_set_actor_at_control(preview, chunk._junction_interactable, "endo")
	var accepted_box := {"snapshot": {}}
	var junction_data_id := str(chunk._junction_interactable.get("data_id"))
	var accepted_probe := func(id: String, actor: String) -> void:
		if id == junction_data_id and actor == "endo" \
				and (accepted_box.get("snapshot", {}) as Dictionary).is_empty():
			accepted_box["snapshot"] = _json_round_trip(preview.build_save_snapshot())
	gs.interactable_triggered.connect(accepted_probe)
	check(bool(chunk._junction_interactable.call("_trigger", false)),
		"exact nearby Endo source succeeds while Aster remains the selected portrait")
	gs.interactable_triggered.disconnect(accepted_probe)
	check(bool(chunk.get_preview_state().get("junction_read", false)),
		"junction outcome records the source actor rather than the selected portrait")
	var accepted_snapshot: Dictionary = accepted_box.get("snapshot", {})
	var accepted_record := _saved_endo_authority(
		accepted_snapshot, chunk.endo_authority_key())
	check(not accepted_snapshot.is_empty()
			and not bool(accepted_record.get("junction_read", true)),
		"accepted-trigger signal snapshot still contains pre-owner junction truth")

	preview.apply_save_snapshot(accepted_snapshot)
	var events_after_accepted_restore := _event_count(gs)
	chunk.on_game_state_snapshot_restored()
	chunk.on_game_state_snapshot_restored()
	check(not bool(chunk.get_preview_state().get("junction_read", true))
			and _control_is_rearmed(gs, chunk._junction_interactable)
			and _event_count(gs) == events_after_accepted_restore,
		"same-presenter accepted seam grants nothing and rearms exactly once")
	check(_trigger_endo_control(preview, chunk._junction_interactable, "endo", true)
			and bool(chunk.get_preview_state().get("junction_read", false)),
		"same-presenter accepted seam remains physically retryable")

	var fresh = await _spawn_preview()
	if fresh != null:
		fresh.apply_save_snapshot(accepted_snapshot)
		fresh._active_chunk.on_game_state_snapshot_restored()
		fresh._active_chunk.on_game_state_snapshot_restored()
		check(not bool(fresh._active_chunk.get_preview_state().get("junction_read", true))
				and _control_is_rearmed(
					fresh._game_state, fresh._active_chunk._junction_interactable),
			"fresh accepted seam grants nothing and repeated attachment stays idempotent")
		check(_trigger_endo_control(
				fresh, fresh._active_chunk._junction_interactable, "endo", true),
			"fresh accepted seam can be retried only through the exact world source")
		await _discard(fresh)
	await _discard(preview)


func _verify_crossing_hazard_and_chunk_authority() -> void:
	var source = await _spawn_preview()
	if source == null:
		return
	var chunk = source._active_chunk
	var gs: GameState = source._game_state
	var scheduler: EventScheduler = source._scheduler
	var gate: PartyGate3D = chunk._shortcut_gate
	var hazard = chunk._direct_bloom_field

	var absent_snapshot := _json_round_trip(source.build_save_snapshot())
	_erase_world_records(absent_snapshot, [
		chunk.endo_authority_key(),
		hazard.authority_state_key(),
		gate.authority_state_key(),
	])
	check(not gate.navigation_cells().is_empty()
			and _gate_cells_blocked(gs.grid, gate),
		"authored baseline has a real closed return-channel topology")
	var safe_cell := gs.grid.world_to_grid(chunk.SAFE_LEDGE_CENTER)
	var bloom_cell := gs.grid.world_to_grid(chunk.RISKY_BLOOM_CENTER)
	check(not gs.grid.is_cell_risky(safe_cell) and gs.grid.is_cell_risky(bloom_cell),
		"navigation truth marks only the visible bloom lane as recoverable risk")
	var cautious_path := gs.grid.find_path(
		gs.grid.world_to_grid(chunk.SPAWNS["aster"]),
		gs.grid.world_to_grid(chunk.SHELTER_POS), {}, true)
	var cautious_crosses_risk := false
	for waypoint in cautious_path:
		if gs.grid.is_cell_risky(gs.grid.world_to_grid(waypoint)):
			cautious_crosses_risk = true
			break
	check(not cautious_path.is_empty() and not cautious_crosses_risk,
		"closed optional grate leaves a complete start-to-shelter route whose cautious plan uses the ledge")

	# Position is evidence, not semantic authority. A teleport, ordinary move, or arrival callback at
	# the far lip must not manufacture a committed route or expose the return grate.
	source.headless_set_character_position("aster", chunk.RISKY_BLOOM_END)
	source.headless_set_character_position("endo", chunk.SHORTCUT_LOCK_POS)
	chunk.headless_process(0.0)
	var precommit_state: Dictionary = chunk.get_preview_state()
	check(str(precommit_state.get("route_phase", "")) == "junction"
			and not bool(precommit_state.get("danger_resolved", true))
			and gate.state == PartyGate3D.State.CLOSED
			and _gate_cells_blocked(gs.grid, gate),
		"far-side position alone cannot grant route completion or retract the shortcut blocker")
	check(not chunk.unlock_shortcut()
			and gate.state == PartyGate3D.State.CLOSED
			and str(chunk.get_preview_state().get("route_phase", "")) == "junction",
		"the chunk's public shortcut seam rejects a physically present actor before route authority")

	var hp_before := _party_hp(gs)
	source.headless_select_character("aster")
	check(_trigger_endo_control(source, chunk._direct_interactable, "aster", true),
		"direct-route control commits Aster to the spatial bloom crossing")
	var committed := gs.get_external_traversal_state("aster")
	var chunk_record: Dictionary = gs.get_world_state(chunk.endo_authority_key(), {})
	check(gs.is_external_traversal_active("aster")
			and str(chunk_record.get("route_phase", "")) == "direct_crossing"
			and str(chunk_record.get("crossing_actor", "")) == "aster"
			and is_equal_approx(float(chunk_record.get("crossing_deadline", -1.0)),
				float(committed.get("end_tick", -2.0))),
		"versioned chunk truth records the in-flight actor and traversal deadline")
	check(int(chunk_record.get("version", 0)) == chunk.ENDO_AUTHORITY_VERSION
			and str(chunk_record.get("authority_id", "")) == chunk.endo_authority_key(),
		"chunk authority is versioned and instance-stable")
	check(not gs.command_move_to_pos("aster", chunk.SHELTER_POS),
		"ordinary movement cannot cancel or skip the locked crossing")

	var fixed_tick := float(scheduler.get_current_tick())
	var fixed_position := gs.get_position("aster")
	var fixed_hazard: Dictionary = hazard.get_state()
	var fixed_chunk: Dictionary = chunk.get_preview_state()
	for _frame in range(240):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	check(is_equal_approx(float(scheduler.get_current_tick()), fixed_tick)
			and gs.get_position("aster").distance_to(fixed_position) < 0.0001
			and hazard.get_state() == fixed_hazard
			and chunk.get_preview_state().get("route_phase") == fixed_chunk.get("route_phase"),
		"480 presentation calls advance neither traversal, hazard cadence, nor route phase")

	source.headless_advance(2.25, 0.05)
	var middle := gs.get_external_traversal_state("aster")
	var midpoint_position := gs.get_position("aster")
	var midpoint_hp := _party_hp(gs)
	var midpoint_hazard: Dictionary = hazard.get_state()
	var midpoint_chunk: Dictionary = chunk.get_preview_state()
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var midpoint_tick := float(scheduler.get_current_tick())
	check(float(middle.get("progress", 0.0)) > 0.0
			and float(middle.get("progress", 1.0)) < 1.0
			and midpoint_position.x > 36.0 and midpoint_position.x < 52.0,
		"midpoint save observes Aster physically inside the bloom")
	check(float(midpoint_hp["aster"]) < float(hp_before["aster"])
			and is_equal_approx(float(midpoint_hp["peris"]), float(hp_before["peris"]))
			and is_equal_approx(float(midpoint_hp["endo"]), float(hp_before["endo"])),
		"HazardField damages only the body physically occupying its rectangle")
	check(float(midpoint_chunk.get("direct_damage_total", 0.0))
			== float(hp_before["aster"]) - float(midpoint_hp["aster"]),
		"chunk damage telemetry mirrors actual kit bites instead of projected party-wide damage")

	var finish_count := {"value": 0}
	gs.external_traversal_finished.connect(func(id: String, traversal_id: StringName) -> void:
		if id == "aster" and traversal_id == chunk.DIRECT_TRAVERSAL_ID:
			finish_count.value = int(finish_count.value) + 1
	)
	source.headless_advance(8.0, 0.05)
	check(str(chunk.get_preview_state().get("route_phase", "")) == "direct_route"
			and not gs.is_external_traversal_active("aster")
			and int(finish_count.value) == 1,
		"uninterrupted crossing resolves exactly once from far-side position")
	var completed_record: Dictionary = gs.get_world_state(chunk.endo_authority_key(), {}).duplicate(true)
	var completed_hp := _party_hp(gs)
	var completed_events := _event_count(gs)
	chunk.on_game_state_snapshot_restored()
	chunk.on_game_state_snapshot_restored()
	check(gs.get_world_state(chunk.endo_authority_key(), {}) == completed_record
			and _party_hp(gs) == completed_hp
			and _event_count(gs) == completed_events
			and int(finish_count.value) == 1,
		"repeated completion attachment replays no traversal, damage, command, or semantic effect")

	# Same-presenter rollback must retract route completion, position, damage after the save, and all
	# opaque callbacks. Calling the chunk attachment twice is an explicit idempotence stress.
	source.apply_save_snapshot(midpoint_snapshot)
	var events_before_repeat := _event_count(gs)
	chunk.on_game_state_snapshot_restored()
	var same_middle := gs.get_external_traversal_state("aster")
	check(str(chunk.get_preview_state().get("route_phase", "")) == "direct_crossing"
			and gs.is_external_traversal_active("aster")
			and gs.get_position("aster").distance_to(midpoint_position) < 0.01
			and _party_hp(gs) == midpoint_hp,
		"same-presenter rollback retracts the future to the exact spatial/damage midpoint")
	check(is_equal_approx(float(scheduler.get_current_tick()), midpoint_tick)
			and is_equal_approx(float(same_middle.get("progress", -1.0)),
				float(middle.get("progress", -2.0)))
			and _hazard_equivalent(hazard.get_state(), midpoint_hazard),
		"same presenter restores scheduler tick, traversal progress, and hazard deadline")
	check(_event_count(gs) == events_before_repeat,
		"duplicate presenter attachment emits no synthetic gameplay command")
	var next_bite := float(midpoint_hazard.get("next_bite_tick", -1.0))
	var hp_at_restore := gs.get_stat("aster", "hp")
	_advance_scheduler(source, maxf(0.0, next_bite - midpoint_tick - EPSILON), 0.05)
	check(is_equal_approx(gs.get_stat("aster", "hp"), hp_at_restore),
		"restored HazardField cannot bite before its saved absolute deadline")
	_advance_scheduler(source, EPSILON * 1.1, EPSILON * 1.1)
	check(is_equal_approx(gs.get_stat("aster", "hp"),
			hp_at_restore - chunk.DIRECT_BLOOM_DAMAGE_PER_TICK),
		"restored HazardField bites once at the original deadline")
	var same_finish_before := int(finish_count.value)
	source.headless_advance(8.0, 0.05)
	check(str(chunk.get_preview_state().get("route_phase", "")) == "direct_route"
			and int(finish_count.value) == same_finish_before + 1,
		"same-presenter restored traversal consumes exactly one completion")

	var fresh = await _spawn_preview()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		fresh._active_chunk.on_game_state_snapshot_restored()
		var fresh_gs: GameState = fresh._game_state
		var fresh_chunk = fresh._active_chunk
		var fresh_hazard = fresh_chunk._direct_bloom_field
		var fresh_finish_count := {"value": 0}
		fresh_gs.external_traversal_finished.connect(
			func(id: String, traversal_id: StringName) -> void:
				if id == "aster" and traversal_id == fresh_chunk.DIRECT_TRAVERSAL_ID:
					fresh_finish_count.value = int(fresh_finish_count.value) + 1
		)
		var fresh_middle := fresh_gs.get_external_traversal_state("aster")
		check(str(fresh_chunk.get_preview_state().get("route_phase", "")) == "direct_crossing"
				and fresh_gs.get_position("aster").distance_to(midpoint_position) < 0.01
				and is_equal_approx(float(fresh_middle.get("progress", -1.0)),
					float(middle.get("progress", -2.0))),
			"fresh presenter reconstructs the same in-flight body and semantic phase")
		check(_hazard_equivalent(fresh_hazard.get_state(), midpoint_hazard)
				and _party_hp(fresh_gs) == midpoint_hp,
			"fresh presenter reconstructs hazard cadence and spatially selective damage")
		fresh.headless_advance(8.0, 0.05)
		check(str(fresh_chunk.get_preview_state().get("route_phase", "")) == "direct_route"
				and not fresh_gs.is_external_traversal_active("aster")
				and int(fresh_finish_count.value) == 1,
			"fresh presenter reaches the same far-side outcome exactly once")
		await _discard(fresh)

	# A save with no chunk/kit records is older than the interaction. It may reconstruct the authored
	# always-on bloom and closed grate, but may not retain any route, damage, or callback from the future.
	source.apply_save_snapshot(absent_snapshot)
	chunk.on_game_state_snapshot_restored()
	check(str(chunk.get_preview_state().get("route_phase", "")) == "junction"
			and str(chunk.get_preview_state().get("route_choice", "")) == ""
			and not bool(chunk.get_preview_state().get("danger_resolved", true))
			and not gs.is_external_traversal_active("aster"),
		"absent chunk record retracts every route fact to the pre-interaction baseline")
	check(gs.get_world_state(chunk.endo_authority_key(), null) == null
			and hazard.is_active() and gate.state == PartyGate3D.State.CLOSED
			and _gate_cells_blocked(gs.grid, gate),
		"absence stays absent semantically while authored mechanisms rebuild baseline truth")
	var absent_hp := _party_hp(gs)
	source.headless_advance(12.0, 0.05)
	check(str(chunk.get_preview_state().get("route_phase", "")) == "junction"
			and _party_hp(gs) == absent_hp,
		"discarded traversal/hazard callbacks cannot grant or damage anything after absence rollback")
	await _discard(source)


func _verify_gate_midpoint_and_topology() -> void:
	var source = await _spawn_preview()
	if source == null:
		return
	var chunk = source._active_chunk
	var gs: GameState = source._game_state
	var scheduler: EventScheduler = source._scheduler
	var gate: PartyGate3D = chunk._shortcut_gate
	var blocker := gate.get_node_or_null("RubbleBlocker/BlockerShape") as CollisionShape3D

	# Resolve one route to make the optional return latch available; the forward shelter path remains
	# usable on either gate phase, so this gate is a real shortcut rather than a disguised progress flag.
	check(_trigger_endo_control(source, chunk._junction_interactable, "endo", true),
		"gate fixture reads the junction through its exact source")
	check(_trigger_endo_control(source, chunk._route_interactable, "aster", true),
		"gate fixture marks the ledge through its exact source")
	check(_trigger_endo_control(source, chunk._safe_interactable, "endo", true),
		"gate fixture commits the ledge through its exact source")
	source.headless_advance(8.0, 0.05)
	check(str(chunk.get_preview_state().get("route_phase", "")) == "safe_route",
		"gate fixture reaches the far lip before touching the shortcut")

	var opened_count := {"value": 0}
	gate.opened.connect(func() -> void:
		opened_count.value = int(opened_count.value) + 1
	)
	check(_trigger_endo_control(source, chunk._shortcut_interactable, "endo", true),
		"Endo commits the return grate opening through its exact latch")
	var opening := gate.get_authority_state()
	var gate_deadline := float(opening.get("end_tick", -1.0))
	check(str(opening.get("phase", "")) == PartyGate3D.PHASE_OPENING
			and _gate_cells_blocked(gs.grid, gate)
			and blocker != null and not blocker.disabled,
		"OPENING retains collision and every dynamic topology blocker")
	check(not gate.commit_open(),
		"public gate seam cannot skip the saved opening interval")

	source.headless_advance(0.55, 0.05)
	var gate_midpoint := _json_round_trip(source.build_save_snapshot())
	var gate_midpoint_tick := float(scheduler.get_current_tick())
	var gate_midpoint_record := gate.get_authority_state()
	var grate_y: float = chunk._shortcut_grate_mesh.position.y
	for _frame in range(240):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	check(is_equal_approx(float(scheduler.get_current_tick()), gate_midpoint_tick)
			and gate.get_authority_state() == gate_midpoint_record
			and is_equal_approx(chunk._shortcut_grate_mesh.position.y, grate_y)
			and _gate_cells_blocked(gs.grid, gate),
		"render frames advance neither saved gate time, lift animation, nor topology")

	_advance_scheduler(source, maxf(0.0, gate_deadline - gate_midpoint_tick - EPSILON), 0.05)
	check(gate.state == PartyGate3D.State.OPENING and _gate_cells_blocked(gs.grid, gate),
		"return channel remains topologically closed immediately before its deadline")
	_advance_scheduler(source, EPSILON * 1.1, EPSILON * 1.1)
	await process_frame
	check(gate.state == PartyGate3D.State.OPEN and _gate_cells_open(gs.grid, gate)
			and blocker.disabled and int(opened_count.value) == 1,
		"deadline removes both collision and navigation blockers exactly once")

	# Same-presenter rollback of an already-open gate must put the blocker back at the midpoint.
	source.apply_save_snapshot(gate_midpoint)
	chunk.on_game_state_snapshot_restored()
	await process_frame
	check(gate.state == PartyGate3D.State.OPENING
			and is_equal_approx(float(gate.get_authority_state().get("end_tick", -1.0)), gate_deadline)
			and _gate_cells_blocked(gs.grid, gate) and not blocker.disabled,
		"same-presenter rollback retracts open collision/topology to saved OPENING")
	source.headless_advance(4.0, 0.05)
	await process_frame
	var same_open_count := int(opened_count.value)
	source.headless_advance(4.0, 0.05)
	check(gate.state == PartyGate3D.State.OPEN and _gate_cells_open(gs.grid, gate)
			and same_open_count == 2 and int(opened_count.value) == same_open_count,
		"same presenter consumes one restored gate deadline and leaves no duplicate callback")

	var fresh = await _spawn_preview()
	if fresh != null:
		fresh.apply_save_snapshot(gate_midpoint)
		fresh._active_chunk.on_game_state_snapshot_restored()
		await process_frame
		var fresh_gate: PartyGate3D = fresh._active_chunk._shortcut_gate
		var fresh_opened_count := {"value": 0}
		fresh_gate.opened.connect(func() -> void:
			fresh_opened_count.value = int(fresh_opened_count.value) + 1
		)
		check(fresh_gate.state == PartyGate3D.State.OPENING
				and _gate_cells_blocked(fresh._game_state.grid, fresh_gate),
			"fresh presenter reconstructs midpoint collision and topology")
		fresh.headless_advance(4.0, 0.05)
		await process_frame
		check(fresh_gate.state == PartyGate3D.State.OPEN
				and _gate_cells_open(fresh._game_state.grid, fresh_gate)
				and int(fresh_opened_count.value) == 1,
			"fresh presenter opens the same return throat once after only the saved remainder")
		await _discard(fresh)

	await _discard(source)


func _verify_shelter_preflight_atomicity() -> void:
	var preview = await _spawn_preview()
	if preview == null:
		return
	var chunk = preview._active_chunk
	var gs: GameState = preview._game_state
	check(_trigger_endo_control(preview, chunk._direct_interactable, "aster", true),
		"shelter fixture commits a route through its exact crossing control")
	preview.headless_advance(8.0, 0.05)
	for char_id in chunk.PARTY_IDS:
		preview.headless_set_character_position(char_id, chunk.SHELTER_POS)
	var atp_before := {
		"aster": gs.get_stat("aster", "atp"),
		"peris": gs.get_stat("peris", "atp"),
		"endo": gs.get_stat("endo", "atp"),
	}
	var peris_pos := gs.get_position("peris")
	check(gs.command_external_traversal(
		"peris", &"verify_shelter_busy", peris_pos + Vector3(0.1, 0.0, 0.0),
		peris_pos, peris_pos + Vector3(0.1, 0.0, 0.0), 2.0),
		"shelter fixture makes the final member unavailable without moving them out of range")
	chunk._shelter_interactable.set("active_character", "aster")
	check(not bool(chunk._shelter_interactable.call("_trigger", false))
			and gs.get_stat("aster", "atp") == float(atp_before["aster"])
			and gs.get_stat("peris", "atp") == float(atp_before["peris"])
			and gs.get_stat("endo", "atp") == float(atp_before["endo"])
			and not gs.is_resting("aster") and not gs.is_resting("peris")
			and not gs.is_resting("endo"),
		"party-rest preflight rejects one busy member before charging or resting anyone")
	check(gs.cancel_external_traversal("peris", &"verify_shelter_ready"),
		"shelter fixture releases the deliberately busy member")
	for char_id in chunk.PARTY_IDS:
		preview.headless_set_character_position(char_id, chunk.SHELTER_POS)
		gs.set_stat(
			char_id,
			"stamina",
			maxf(0.0, gs.get_stat_cap(char_id, "stamina") - 1.0))
	var paid_before := _party_atp(gs)
	var commit_day := gs.get_game_day()
	var signal_box := {"snapshot": {}}
	var signal_probe := func(_char_id: String, stat: String, _value: float) -> void:
		if stat == "atp" and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _json_round_trip(preview.build_save_snapshot())
	gs.stat_changed.connect(signal_probe)
	check(_trigger_endo_control(
			preview, chunk._shelter_interactable, "aster", false),
		"settled conscious trio commits one canonical party-rest command from the hearth")
	gs.stat_changed.disconnect(signal_probe)
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {})
	var signal_authority := _saved_endo_authority(signal_snapshot, chunk.endo_authority_key())
	check(not signal_snapshot.is_empty()
			and str(signal_authority.get("shelter_rest_phase", "")) == "committing"
			and _party_rest_effect_present(gs, paid_before, commit_day),
		"first ATP signal sees COMMITTING owner truth after the whole trio has one atomic rest effect")
	check(str(chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
			and str(chunk.get_preview_state().get("route_phase", "")) == "complete",
		"successful batch finalizes the authored shelter exactly once")

	var same_events_before := _party_rest_event_count(gs)
	preview.apply_save_snapshot(signal_snapshot)
	preview.headless_advance(0.001, 0.001)
	check(str(chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
			and _party_rest_event_count(gs) == same_events_before
			and _party_rest_effect_present(gs, paid_before, commit_day),
		"same-presenter signal-time restore reconciles the installed batch without repaying it")

	var fresh = await _spawn_preview()
	if fresh != null:
		var fresh_gs: GameState = fresh._game_state
		var fresh_chunk = fresh._active_chunk
		var fresh_events_before := _party_rest_event_count(fresh_gs)
		fresh.apply_save_snapshot(signal_snapshot)
		fresh.headless_advance(0.001, 0.001)
		check(str(fresh_chunk.get_preview_state().get("shelter_rest_phase", "")) == "rested"
				and _party_rest_event_count(fresh_gs) == fresh_events_before
				and _party_rest_effect_present(fresh_gs, paid_before, commit_day),
			"fresh signal-time restore reaches the same shelter outcome without a second command")
		await _discard(fresh)
	await _discard(preview)


func _verify_forage_claim_authority() -> void:
	var preview = await _spawn_preview()
	if preview == null:
		return
	var chunk = preview._active_chunk
	var gs: GameState = preview._game_state
	var baseline := _json_round_trip(preview.build_save_snapshot())
	var initial: Dictionary = chunk.get_preview_state()
	var exact_item := str(initial.get("cache_item", ""))
	var source_id := str(
		gs.get_world_state(chunk.endo_authority_key(), {}).get("cache_source_id", ""))
	check(exact_item != ""
			and bool(initial.get("cache_item_at_source", false))
			and _endo_cache_item_count(gs, source_id) == 1,
		"Endo's wall cache exposes one source-tagged physical lysate before interaction")

	preview.headless_select_character("peris")
	preview.headless_set_character_position(
		"peris", chunk.FORAGE_CACHE_POS + Vector3(5.0, 0.0, 0.0))
	chunk._cache_interactable.set("active_character", "peris")
	check(not bool(chunk._cache_interactable.call("_trigger", false))
			and str(chunk.get_preview_state().get("cache_item", "")) == exact_item
			and bool(chunk.get_preview_state().get("cache_item_at_source", false))
			and _endo_cache_item_count(gs, source_id) == 1
			and _control_is_rearmed(gs, chunk._cache_interactable),
		"out-of-range claim leaves the same exact source item untouched")

	preview.apply_save_snapshot(baseline)
	preview.headless_select_character("peris")
	preview.headless_set_character_position("peris", chunk.FORAGE_CACHE_POS)
	for slot_i in range(2):
		var filler := gs.spawn_item(
			"seed", chunk.FORAGE_CACHE_POS, {"display_name": "forage hand filler %d" % slot_i})
		check(gs.pick_up_item("peris", filler),
			"forage fixture fills Peris hand slot %d through canonical pickup" % slot_i)
	chunk._cache_interactable.set("active_character", "peris")
	check(not bool(chunk._cache_interactable.call("_trigger", false))
			and str(chunk.get_preview_state().get("cache_phase", "")) == "available"
			and bool(chunk.get_preview_state().get("cache_item_at_source", false))
			and _endo_cache_item_count(gs, source_id) == 1
			and _control_is_rearmed(gs, chunk._cache_interactable),
		"full hands block before reservation, movement, or reward cloning")

	preview.apply_save_snapshot(baseline)
	# Keep Aster selected while Peris is the exact source actor. UI focus cannot steal the claim.
	preview.headless_select_character("aster")
	_set_actor_at_control(preview, chunk._cache_interactable, "peris")
	exact_item = str(chunk.get_preview_state().get("cache_item", ""))
	var capture_box := {"snapshot": {}, "item_id": ""}
	var pickup_probe := func(char_id: String, item_id: String) -> void:
		if char_id == "peris" and item_id == exact_item \
				and (capture_box.get("snapshot", {}) as Dictionary).is_empty():
			capture_box["item_id"] = item_id
			capture_box["snapshot"] = _json_round_trip(preview.build_save_snapshot())
	gs.item_picked_up.connect(pickup_probe)
	chunk._cache_interactable.set("active_character", "peris")
	check(bool(chunk._cache_interactable.call("_trigger", false)),
		"source-bound Peris claims the cache while another portrait is selected")
	gs.item_picked_up.disconnect(pickup_probe)
	var signal_snapshot: Dictionary = capture_box.get("snapshot", {})
	var signal_authority := _saved_endo_authority(signal_snapshot, chunk.endo_authority_key())
	check(not signal_snapshot.is_empty()
			and str(signal_authority.get("cache_phase", "")) == "claiming"
			and str(signal_authority.get("cache_claimed_by", "")) == "peris"
			and str(signal_authority.get("cache_item_id", "")) == exact_item,
		"pickup signal save sees the published exact-item and exact-actor CLAIMING reservation")
	var completed: Dictionary = chunk.get_preview_state()
	check(str(completed.get("cache_phase", "")) == "claimed"
			and str(completed.get("cache_claimed_by", "")) == "peris"
			and str(completed.get("cache_item_holder", "")) == "peris"
			and int(completed.get("cache_claim_serial", 0)) == 1
			and _endo_cache_item_count(gs, source_id) == 1,
		"ordinary claim finalizes one physical item for its real carrier")

	preview.apply_save_snapshot(signal_snapshot)
	preview.apply_save_snapshot(signal_snapshot)
	var same_claim: Dictionary = chunk.get_preview_state()
	check(str(same_claim.get("cache_phase", "")) == "claimed"
			and str(same_claim.get("cache_item_holder", "")) == "peris"
			and int(same_claim.get("cache_claim_serial", 0)) == 1
			and _endo_cache_item_count(gs, source_id) == 1,
		"same-presenter signal-time restore reconciles once without replay or duplication")

	var fresh = await _spawn_preview()
	if fresh != null:
		fresh.apply_save_snapshot(signal_snapshot)
		var fresh_state: Dictionary = fresh._active_chunk.get_preview_state()
		check(str(fresh_state.get("cache_phase", "")) == "claimed"
				and str(fresh_state.get("cache_item_holder", "")) == "peris"
				and _endo_cache_item_count(fresh._game_state, source_id) == 1,
			"fresh signal-time restore preserves the same exact claimed item")
		await _discard(fresh)

	var wrong_holder := signal_snapshot.duplicate(true)
	var wrong_game_state: Dictionary = wrong_holder.get("game_state", {})
	var wrong_world: Dictionary = wrong_game_state.get("world_state", {})
	var wrong_authority: Dictionary = (
		wrong_world.get(chunk.endo_authority_key(), {}) as Dictionary).duplicate(true)
	wrong_authority["cache_claimed_by"] = "aster"
	wrong_world[chunk.endo_authority_key()] = wrong_authority
	wrong_game_state["world_state"] = wrong_world
	wrong_holder["game_state"] = wrong_game_state
	preview.apply_save_snapshot(wrong_holder)
	var rejected: Dictionary = chunk.get_preview_state()
	check(str(rejected.get("cache_phase", "")) == "claiming"
			and str(rejected.get("cache_claimed_by", "")) == "aster"
			and str(rejected.get("cache_item_holder", "")) == "peris"
			and not bool(rejected.get("cache_item_at_source", true))
			and _endo_cache_item_count(gs, source_id) == 1
			and not chunk.collect_forage(),
		"wrong holder remains unresolved CLAIMING and cannot retarget or mint a reward")
	await _discard(preview)


func _trigger_endo_control(
	preview: Node, control: Node, actor: String, snap_to_source := true
) -> bool:
	if preview == null or not is_instance_valid(control):
		return false
	if snap_to_source:
		_set_actor_at_control(preview, control, actor)
	control.set("active_character", actor)
	return bool(control.call("_trigger", false))


func _set_actor_at_control(preview: Node, control: Node, actor: String) -> void:
	var position := (control as Node3D).global_position \
		if control is Node3D else Vector3.ZERO
	var gs: GameState = preview._game_state
	var data_id := str(control.get("data_id"))
	if gs != null and data_id != "" and gs.has_interactable(data_id):
		var registered_position: Variant = gs.get_interactable(data_id).get(
			"position", position)
		if registered_position is Vector3:
			position = registered_position
	preview.headless_set_character_position(actor, position)


func _control_is_rearmed(gs: GameState, control: Node) -> bool:
	if gs == null or not is_instance_valid(control) \
			or bool(control.get("_used")) \
			or not bool(control.get("interaction_enabled")):
		return false
	var data_id := str(control.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	return bool(spec.get("one_shot", false)) \
		and not bool(spec.get("triggered", false)) \
		and gs.is_interactable_enabled(data_id)


func _control_is_unspent(gs: GameState, control: Node) -> bool:
	if gs == null or not is_instance_valid(control) or bool(control.get("_used")):
		return false
	var data_id := str(control.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	return bool(spec.get("one_shot", false)) \
		and not bool(spec.get("triggered", false))


func _spawn_preview():
	var preview = PreviewScene.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "endo_junction_stretch"
	preview.suppress_scene_change = true
	root.add_child(preview)
	for _frame in range(12):
		await process_frame
	check(preview._active_chunk != null, "Endo Junction preview boots its production chunk")
	if preview._active_chunk == null:
		await _discard(preview)
		return null
	return preview


func _advance_scheduler(preview: Node, seconds: float, step: float) -> void:
	if seconds <= 0.0:
		return
	preview.headless_advance(seconds, maxf(step, 0.000001))


func _gate_cells_blocked(grid: GridWorld, gate: PartyGate3D) -> bool:
	if grid == null or gate == null or gate.navigation_cells().is_empty():
		return false
	for cell in gate.navigation_cells():
		if grid.is_walkable(cell.x, cell.y):
			return false
	return true


func _gate_cells_open(grid: GridWorld, gate: PartyGate3D) -> bool:
	if grid == null or gate == null or gate.navigation_cells().is_empty():
		return false
	for cell in gate.navigation_cells():
		if not grid.is_walkable(cell.x, cell.y):
			return false
	return true


func _saved_endo_authority(snapshot: Dictionary, authority_key: String) -> Dictionary:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var authority: Variant = world_state.get(authority_key, {})
	return authority as Dictionary if authority is Dictionary else {}


func _party_atp(gs: GameState) -> Dictionary:
	return {
		"aster": gs.get_stat("aster", "atp"),
		"peris": gs.get_stat("peris", "atp"),
		"endo": gs.get_stat("endo", "atp"),
	}


func _party_paid_once(gs: GameState, before: Dictionary) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if not before.has(char_id) \
				or not is_equal_approx(
					gs.get_stat(char_id, "atp"), float(before[char_id]) - 1.0):
			return false
	return true


func _party_all_resting(gs: GameState) -> bool:
	for char_id in ["aster", "peris", "endo"]:
		if not gs.is_resting(char_id):
			return false
	return true


func _party_rest_effect_present(gs: GameState, before: Dictionary, commit_day: int) -> bool:
	if not _party_paid_once(gs, before):
		return false
	# At night a complete three-person roster advances atomically to dawn and
	# immediately consumes its transient rest records. During daytime the saved
	# effect is instead the installed trio of scheduled rest records.
	return gs.get_game_day() > commit_day or _party_all_resting(gs)


func _party_rest_event_count(gs: GameState) -> int:
	var count := 0
	if gs == null or gs.event_log == null:
		return count
	for event_v in gs.event_log.events:
		var event: Dictionary = event_v
		if str(event.get("kind", "")) == str(GameEvent.KIND_PARTY_REST):
			count += 1
	return count


func _endo_cache_item_count(gs: GameState, source_id: String) -> int:
	var count := 0
	if gs == null:
		return count
	for item_v in gs.items.values():
		var item: Dictionary = item_v
		var properties: Dictionary = item.get("properties", {})
		if str(properties.get("source_endo_forage_cache", "")) == source_id:
			count += 1
	return count


func _party_hp(gs: GameState) -> Dictionary:
	return {
		"aster": gs.get_stat("aster", "hp"),
		"peris": gs.get_stat("peris", "hp"),
		"endo": gs.get_stat("endo", "hp"),
	}


func _hazard_equivalent(actual: Dictionary, expected: Dictionary) -> bool:
	return str(actual.get("contract", "")) == str(expected.get("contract", "")) \
		and str(actual.get("tag", "")) == str(expected.get("tag", "")) \
		and bool(actual.get("active", false)) == bool(expected.get("active", false)) \
		and bool(actual.get("bite_armed", false)) == bool(expected.get("bite_armed", false)) \
		and is_equal_approx(float(actual.get("next_bite_tick", -1.0)),
			float(expected.get("next_bite_tick", -2.0))) \
		and is_equal_approx(float(actual.get("interval", -1.0)),
			float(expected.get("interval", -2.0))) \
		and is_equal_approx(float(actual.get("damage_per_bite", -1.0)),
			float(expected.get("damage_per_bite", -2.0)))


func _erase_world_records(snapshot: Dictionary, keys: Array) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	for key_v in keys:
		world_state.erase(str(key_v))
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


func _event_count(gs: GameState) -> int:
	return gs.event_log.size() if gs != null and gs.event_log != null else 0


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
