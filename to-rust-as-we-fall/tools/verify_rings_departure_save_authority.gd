extends SceneTree

## Rings authority regression. The optional flora memories consume their exact physical Peris
## source receipts without becoming route gates. Marco's required beat gathers Peris and Endo, then
## the visible departure traversal remains saved truth rather than an endpoint callback.

const PreviewScene := preload("res://scenes/fragments/fragment_preview.tscn")
const MIDPOINT_SECONDS := 1.25
const DEADLINE_EPSILON := 0.001

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_optional_read_exact_sources()
	var source = await _spawn_rings_preview()
	if source == null:
		_finish()
		return
	var chunk = source._active_chunk
	var gs: GameState = source._game_state
	var scheduler: EventScheduler = source._scheduler

	var absent_snapshot := _json_round_trip(source.build_save_snapshot())
	_erase_rings_authority(absent_snapshot, chunk.rings_authority_key())
	check(gs.characters.has("endo") and source.is_preview_character_present("endo"),
		"Rings begins with Endo in canonical and presented roster truth")
	var marco: Node = chunk.get_playthrough_interaction_target("marco_reassignment")
	check(marco == chunk._marco_interactable
			and marco != null and marco.has_signal("interaction_requested"),
		"Rings exposes the real Marco interaction as its semantic playthrough target")
	check(not chunk.trigger_rings_reassignment_beat()
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not gs.is_external_traversal_active("endo"),
		"the retired endpoint helper cannot bypass Marco's ordinary interaction")

	# A real click walks Peris over, but Endo begins far from Marco. The one-shot
	# must re-arm after the scenario-level group guard rejects this prediction.
	check(_right_click_marco(source),
		"the far-party probe enters through right-click, coordinator, walk, and arrival")
	check(str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not bool(chunk.get_preview_state().get("marco_seen", true))
			and not gs.is_external_traversal_active("endo")
			and _marco_is_canonically_armed(gs, marco),
		"nearby Peris cannot remotely reassign a far-away Endo or consume Marco")
	var rejected_snapshot := _json_round_trip(source.build_save_snapshot())

	# Both bodies are physically beside Marco, but an incapacitated Endo cannot
	# become a dialogue prop and then leave through the canonical traversal.
	_place_reassignment_party(source, chunk)
	gs.set_stat("endo", "hp", 0.0, "rings_reassignment_probe")
	check(gs.is_downed("endo"), "fixture downs Endo through canonical HP authority")
	check(_right_click_marco(source)
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not gs.is_external_traversal_active("endo")
			and _marco_is_canonically_armed(gs, marco),
		"a downed Endo is rejected before Marco's canonical trigger is consumed")
	check(source.restore_preview_character_for_restart("endo", gs.get_position("endo")),
		"fixture restores Endo's canonical and presented availability")
	_place_reassignment_party(source, chunk)

	var busy_origin := gs.get_position("endo")
	check(gs.command_external_traversal(
			"endo",
			&"rings_unavailable_probe",
			busy_origin + Vector3(0.4, 0.0, 0.0),
			gs.get_render_position("endo"),
			gs.get_render_position("endo") + Vector3(0.4, 0.0, 0.0),
			8.0,
			&"locked"),
		"fixture gives nearby Endo a canonical conflicting action")
	check(_right_click_marco(source)
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and StringName(str(gs.get_external_traversal_state("endo").get(
				"traversal_id", ""))) == &"rings_unavailable_probe"
			and _marco_is_canonically_armed(gs, marco),
		"action-committed Endo blocks Marco without replacing either authority")
	gs.cancel_external_traversal("endo", &"rings_probe_complete")
	_place_reassignment_party(source, chunk)

	source.headless_set_selected_characters(["aster"])
	gs.set_stat("peris", "hp", 0.0, "rings_reassignment_probe")
	check(_right_click_marco(source)
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not gs.is_external_traversal_active("endo")
			and _marco_is_canonically_armed(gs, marco),
		"a downed Peris cannot be replaced by another actor or consume Marco")
	check(source.restore_preview_character_for_restart("peris", gs.get_position("peris")),
		"fixture restores Peris's canonical and presented availability")
	_place_reassignment_party(source, chunk)

	# Registration alone is not party availability. A removed-but-near body cannot
	# be silently enlisted by the conversation.
	gs.set_party(["aster", "peris"])
	source.headless_set_selected_characters(["peris"])
	check(_right_click_marco(source)
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not gs.is_external_traversal_active("endo")
			and _marco_is_canonically_armed(gs, marco),
		"a conscious registered Endo outside the available party cannot consume Marco")
	gs.set_party(["aster", "endo"])
	source.headless_set_selected_characters(["aster"])
	check(_right_click_marco(source)
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not gs.is_external_traversal_active("endo")
			and _marco_is_canonically_armed(gs, marco),
		"a conscious registered Peris outside the available party cannot be substituted")
	gs.set_party(["aster", "peris", "endo"])
	_place_reassignment_party(source, chunk)

	marco.set("active_character", "peris")
	var events_before_direct := _event_count(gs)
	chunk._on_marco_interacted(marco)
	check(str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not gs.is_external_traversal_active("endo")
			and _event_count(gs) == events_before_direct,
		"calling the chunk callback directly has no semantic trigger receipt and emits no command")

	source.headless_set_selected_characters(["endo", "peris"])
	check(source.get_preview_active_character() == "endo"
			and source.get_preview_selected_characters().has("endo")
			and gs.get_party().has("endo"),
		"fixture selects Endo so departure must clean active selection and GameState party")

	check(_right_click_marco(source),
		"a right-click while Endo is active delegates the real Marco interaction to Peris")
	var committed := gs.get_external_traversal_state("endo")
	var authority: Dictionary = gs.get_world_state(chunk.rings_authority_key(), {})
	var evidence: Dictionary = authority.get("reassignment_positions", {})
	check(str(chunk.get_preview_state().get("endo_phase", "")) == "departing"
			and gs.is_external_traversal_active("endo")
			and StringName(str(committed.get("traversal_id", "")))
				== chunk.ENDO_DEPARTURE_TRAVERSAL_ID,
		"Marco commits a locked external traversal instead of the departed endpoint")
	check(int(authority.get("version", 0)) == chunk.RINGS_AUTHORITY_VERSION
			and str(authority.get("authority_id", "")) == chunk.rings_authority_key()
			and is_equal_approx(float(authority.get("endo_departure_deadline", -1.0)),
				float(committed.get("end_tick", -2.0))),
		"departure phase and absolute deadline are carried by a versioned chunk record")
	check(str(authority.get("reassignment_actor", "")) == "peris"
			and evidence.has("peris") and evidence.has("endo")
			and is_equal_approx(
				float(authority.get("reassignment_commit_tick", -1.0)),
				float(committed.get("start_tick", -2.0))),
		"saved departure authority carries Peris plus both nearby physical commitment bodies")
	check(not bool(chunk.get_preview_state().get("complete", true))
			and gs.characters.has("endo") and source.is_preview_character_present("endo"),
		"Endo remains present and selectable while the visible exit is in flight")
	check(not gs.command_move_to_pos("endo", Vector3(12.0, 0.5, 0.0)),
		"ordinary movement cannot interrupt or skip the locked departure state")

	_verify_render_frame_invariance(source, chunk, committed, authority)
	source.headless_advance(MIDPOINT_SECONDS, 0.25)
	var middle := gs.get_external_traversal_state("endo")
	var midpoint_position := gs.get_position("endo")
	var midpoint_snapshot := _json_round_trip(source.build_save_snapshot())
	var midpoint_tick := float(scheduler.get_current_tick())
	var deadline := float(middle.get("end_tick", -1.0))
	check(float(middle.get("progress", 0.0)) > 0.0
			and float(middle.get("progress", 1.0)) < 1.0
			and midpoint_position.distance_to(chunk.SPAWNS["endo"]) > 0.1,
		"midpoint save observes Endo between authored endpoints")

	var completion_count := {"value": 0}
	gs.external_traversal_finished.connect(func(char_id: String, traversal_id: StringName) -> void:
		if char_id == "endo" and traversal_id == chunk.ENDO_DEPARTURE_TRAVERSAL_ID:
			completion_count.value = int(completion_count.value) + 1
	)
	source.headless_advance(chunk.ENDO_DEPARTURE_DURATION, 0.25)
	_verify_departed_truth(source, chunk, completion_count, "uninterrupted")
	var completed_snapshot := _json_round_trip(source.build_save_snapshot())

	source.apply_save_snapshot(midpoint_snapshot)
	var events_before_repeat := _event_count(gs)
	chunk.on_game_state_snapshot_restored()
	var restored := gs.get_external_traversal_state("endo")
	check(str(chunk.get_preview_state().get("endo_phase", "")) == "departing"
			and gs.characters.has("endo") and source.is_preview_character_present("endo")
			and gs.is_external_traversal_active("endo"),
		"same-presenter rollback retracts the departed future and restores Endo in flight")
	check(is_equal_approx(float(scheduler.get_current_tick()), midpoint_tick)
			and is_equal_approx(float(restored.get("progress", -1.0)),
				float(middle.get("progress", -2.0)))
			and gs.get_position("endo").distance_to(midpoint_position) < 0.01,
		"same-presenter rollback restores exact tick, traversal progress, and midpoint position")
	check(_event_count(gs) == events_before_repeat,
		"repeated departure attachment emits no synthetic gameplay command")
	var restored_count_before := int(completion_count.value)
	_advance_across_deadline(source, deadline)
	check(int(completion_count.value) == restored_count_before + 1,
		"repeated same-presenter attachment consumes the saved departure exactly once")
	_verify_departed_truth(source, chunk, completion_count, "same-presenter")

	var fresh = await _spawn_rings_preview()
	if fresh != null:
		fresh.apply_save_snapshot(midpoint_snapshot)
		fresh._active_chunk.on_game_state_snapshot_restored()
		var fresh_gs: GameState = fresh._game_state
		var fresh_middle := fresh_gs.get_external_traversal_state("endo")
		check(fresh_gs.is_external_traversal_active("endo")
				and fresh.is_preview_character_present("endo")
				and is_equal_approx(float(fresh_middle.get("progress", -1.0)),
					float(middle.get("progress", -2.0))),
			"fresh presenter attaches to the same saved in-flight Endo")
		var fresh_count := {"value": 0}
		fresh_gs.external_traversal_finished.connect(
			func(char_id: String, traversal_id: StringName) -> void:
				if char_id == "endo" \
						and traversal_id == fresh._active_chunk.ENDO_DEPARTURE_TRAVERSAL_ID:
					fresh_count.value = int(fresh_count.value) + 1
		)
		_advance_across_deadline(fresh, deadline)
		_verify_departed_truth(fresh, fresh._active_chunk, fresh_count, "fresh-presenter")
		check(int(fresh_count.value) == 1,
			"fresh presenter commits exactly one departure completion")
		await _discard(fresh)

	var completed = await _spawn_rings_preview()
	if completed != null:
		completed.apply_save_snapshot(completed_snapshot)
		_verify_departed_truth(completed, completed._active_chunk, {}, "completed-save")
		check(not completed._game_state.is_external_traversal_active("endo"),
			"completed save cannot resurrect a traversal or Endo's roster record")
		await _discard(completed)

	var rejected = await _spawn_rings_preview()
	if rejected != null:
		rejected.apply_save_snapshot(rejected_snapshot)
		rejected._active_chunk.on_game_state_snapshot_restored()
		var rejected_chunk = rejected._active_chunk
		var rejected_gs: GameState = rejected._game_state
		check(str(rejected_chunk.get_preview_state().get("endo_phase", "")) == "present"
				and not rejected_gs.is_external_traversal_active("endo")
				and _marco_is_canonically_armed(
					rejected_gs, rejected_chunk._marco_interactable),
			"fresh load reconstructs the rejected far-party attempt as an armed baseline")
		check(_right_click_marco(rejected)
				and str(rejected_chunk.get_preview_state().get("endo_phase", "")) == "present"
				and not rejected_gs.is_external_traversal_active("endo")
				and _marco_is_canonically_armed(
					rejected_gs, rejected_chunk._marco_interactable),
			"fresh-loaded far Endo still cannot consume Marco or be reassigned")
		await _discard(rejected)

	source.apply_save_snapshot(absent_snapshot)
	chunk.on_game_state_snapshot_restored()
	check(str(chunk.get_preview_state().get("endo_phase", "")) == "present"
			and not bool(chunk.get_preview_state().get("marco_seen", true))
			and gs.characters.has("endo") and source.is_preview_character_present("endo"),
		"missing chunk record retracts every departure fact to the pre-interaction baseline")
	check(gs.get_world_state(chunk.rings_authority_key(), null) == null
			and not gs.is_external_traversal_active("endo"),
		"absence stays absent during load and retains no callback from the discarded future")
	source.headless_advance(chunk.ENDO_DEPARTURE_DURATION * 2.0, 0.25)
	check(gs.characters.has("endo") and source.is_preview_character_present("endo")
			and not bool(chunk.get_preview_state().get("complete", true)),
		"advancing after an absent-record rollback cannot grant the discarded endpoint")

	await _discard(source)
	_finish()


func _verify_optional_read_exact_sources() -> void:
	var preview = await _spawn_rings_preview()
	if preview == null:
		return
	var chunk = preview._active_chunk
	var gs: GameState = preview._game_state
	var sources := {
		chunk.OPTIONAL_READ_CLIENT_BLOOM:
			chunk.get_playthrough_interaction_target("client_bloom"),
		chunk.OPTIONAL_READ_PROPAGATION:
			chunk.get_playthrough_interaction_target("propagation"),
		chunk.OPTIONAL_READ_FORGET_ME_NOT:
			chunk.get_playthrough_interaction_target("forget_me_not"),
	}
	var source_contracts_ok := true
	for action_id in chunk.OPTIONAL_READ_ACTION_IDS:
		var source: Node = sources.get(action_id)
		source_contracts_ok = source_contracts_ok and source != null \
			and bool(source.get("one_shot")) \
			and str(source.get("required_character")) == "peris"
	check(source_contracts_ok and sources.size() == 3,
		"all three ambient reads expose distinct one-shot Peris world sources")
	check(not bool(chunk.get_preview_state().get("complete", true))
			and int(chunk.get_preview_state().get("ambient_read_count", -1)) == 0,
		"optional memory state begins empty and does not define route completion")

	var client: Node = sources[chunk.OPTIONAL_READ_CLIENT_BLOOM]
	var propagation: Node = sources[chunk.OPTIONAL_READ_PROPAGATION]
	check(not chunk._on_client_bloom_interacted()
			and not chunk._on_client_bloom_interacted(propagation),
		"source-less and wrong-source Client Bloom callbacks are inert")
	client.interacted.emit()
	check(not bool(chunk.get_preview_state().get("client_seen", true))
			and _source_trigger_count(gs, client) == 0,
		"manually emitting Client Bloom's signal cannot manufacture a receipt")

	var client_position: Vector3 = chunk._optional_read_source_data_position(client)
	gs.snap_character_to("peris", client_position + Vector3(9.0, 0.0, 0.0))
	check(not _trigger_source_without_reposition(client, "peris")
			and _source_trigger_count(gs, client) == 0,
		"a remote selected Peris cannot read Client Bloom")
	gs.snap_character_to("aster", client_position)
	check(not _trigger_source_without_reposition(client, "aster")
			and _source_trigger_count(gs, client) == 0,
		"Aster at Client Bloom cannot substitute for canonical Peris")

	gs.set_party(["aster", "endo"])
	gs.snap_character_to("peris", client_position)
	check(not _trigger_source_without_reposition(client, "peris")
			and _source_trigger_count(gs, client) == 0,
		"a registered Peris outside the real party cannot obtain the memory")
	gs.set_party(["aster", "peris", "endo"])
	gs.down_character("peris")
	check(not _trigger_source_without_reposition(client, "peris")
			and _source_trigger_count(gs, client) == 0,
		"a downed Peris cannot obtain an ambient read")
	gs.restore_character("peris")
	gs.snap_character_to("peris", client_position)
	check(gs.command_move_to_pos("peris", client_position + Vector3(2.5, 0.0, 0.0)),
		"busy-read fixture commits Peris to a real movement")
	check(not _trigger_source_without_reposition(client, "peris")
			and _source_trigger_count(gs, client) == 0,
		"a moving Peris cannot overlap reading with another action")
	gs.command_stop("peris")
	gs.snap_character_to("peris", client_position)

	var layered_grid := GridWorld.new()
	layered_grid.origin = Vector3(-16.0, 0.0, -20.0)
	layered_grid.create_room(96, 48, false)
	layered_grid.set_level_count(2)
	gs.grid = layered_grid
	gs.set_character_level("peris", 1)
	check(not _trigger_source_without_reposition(client, "peris")
			and _source_trigger_count(gs, client) == 0,
		"matching x/z on another navigation floor cannot read Client Bloom")
	gs.set_character_level("peris", 0)
	gs.snap_character_to("peris", client_position)

	preview.headless_set_selected_characters(["aster"])
	# The preview's group-control adapter mirrors selection into GameState.party. Restore the
	# scenario roster after selecting Aster so this specifically varies portrait focus while
	# retaining the required physical-party truth.
	gs.set_party(["aster", "peris", "endo"])
	check(preview.get_preview_active_character() == "aster"
			and _trigger_source_without_reposition(client, "peris"),
		"nearby ready Peris owns the read even while Aster is the active portrait")
	var counts: Dictionary = chunk.get_preview_state().get(
		"optional_read_consumed_counts", {})
	check(bool(chunk.get_preview_state().get("client_seen", false))
			and _source_trigger_count(gs, client) == 1
			and int(counts.get(chunk.OPTIONAL_READ_CLIENT_BLOOM, 0)) == 1,
		"Client Bloom commits its exact first monotonic source receipt")
	check(not chunk._on_client_bloom_interacted(client),
		"a stale consumed Client Bloom callback cannot replay the information")
	client.interacted.emit()
	check(_source_trigger_count(gs, client) == 1
			and int(chunk.get_preview_state().get("ambient_read_count", 0)) == 1,
		"manual signal spam after the read cannot increment or duplicate it")

	check(_trigger_exact_optional_read(
			preview, propagation, "peris"),
		"Propagation can be read second through its own physical source")
	var forget: Node = sources[chunk.OPTIONAL_READ_FORGET_ME_NOT]
	check(_trigger_exact_optional_read(preview, forget, "peris"),
		"Forget-Me-Not can be read last through its own physical source")
	counts = chunk.get_preview_state().get("optional_read_consumed_counts", {})
	var all_counts_one := true
	for action_id in chunk.OPTIONAL_READ_ACTION_IDS:
		all_counts_one = all_counts_one \
			and int(counts.get(action_id, 0)) == 1 \
			and _source_trigger_count(gs, sources[action_id]) == 1
	check(all_counts_one
			and int(chunk.get_preview_state().get("ambient_read_count", 0)) == 3,
		"the three order-free reads retain independent monotonic receipts")
	check(not bool(chunk.get_preview_state().get("complete", true))
			and str(chunk.get_preview_state().get("endo_phase", "")) == "present",
		"reading every optional memory neither completes nor gates the Marco route")
	var completed_reads_snapshot := _json_round_trip(preview.build_save_snapshot())

	var fresh_reads = await _spawn_rings_preview()
	if fresh_reads != null:
		fresh_reads.apply_save_snapshot(completed_reads_snapshot)
		var fresh_chunk = fresh_reads._active_chunk
		var fresh_counts: Dictionary = fresh_chunk.get_preview_state().get(
			"optional_read_consumed_counts", {})
		var fresh_spent := true
		for action_id in fresh_chunk.OPTIONAL_READ_ACTION_IDS:
			var fresh_source: Node = fresh_chunk.get_playthrough_interaction_target(
				action_id)
			fresh_spent = fresh_spent \
				and int(fresh_counts.get(action_id, 0)) == 1 \
				and not _source_is_armed(fresh_reads._game_state, fresh_source)
		check(fresh_spent
				and int(fresh_chunk.get_preview_state().get(
					"ambient_read_count", 0)) == 3,
			"a fresh presenter restores each acquired memory and its spent exact source")
		check(not bool(fresh_chunk.get_preview_state().get("complete", true)),
			"fresh restore keeps all optional reads information-only")
		await _discard(fresh_reads)
	await _discard(preview)

	await _verify_optional_read_accepted_seam()
	await _verify_optional_read_v2_migration()


func _verify_optional_read_accepted_seam() -> void:
	var preview = await _spawn_rings_preview()
	if preview == null:
		return
	var chunk = preview._active_chunk
	var gs: GameState = preview._game_state
	var action_id: String = chunk.OPTIONAL_READ_CLIENT_BLOOM
	var source: Node = chunk.get_playthrough_interaction_target(action_id)
	var owner_callback := Callable(
		chunk, "_on_client_bloom_interacted").bind(source)
	check(source.interacted.is_connected(owner_callback),
		"accepted-seam fixture identifies Client Bloom's bound owner callback")
	source.interacted.disconnect(owner_callback)
	check(_trigger_exact_optional_read(preview, source, "peris")
			and not bool(chunk.get_preview_state().get("client_seen", true))
			and _source_trigger_count(gs, source) == 1,
		"fixture captures the real edge after Interactable acceptance but before owner callback")
	var authority_before: Dictionary = gs.get_world_state(
		chunk.rings_authority_key(), {})
	check(int((authority_before.get(
				"optional_read_consumed_counts", {}) as Dictionary).get(
					action_id, -1)) == 0,
		"accepted-edge snapshot still has the owner's pre-read receipt count")
	var accepted_snapshot := _json_round_trip(preview.build_save_snapshot())
	source.interacted.connect(owner_callback)

	check(chunk._on_client_bloom_interacted(source)
			and bool(chunk.get_preview_state().get("client_seen", false)),
		"fixture advances beyond the accepted edge before same-presenter rollback")
	preview.apply_save_snapshot(accepted_snapshot)
	chunk.on_game_state_snapshot_restored()
	chunk.on_game_state_snapshot_restored()
	var restored_counts: Dictionary = chunk.get_preview_state().get(
		"optional_read_consumed_counts", {})
	check(not bool(chunk.get_preview_state().get("client_seen", true))
			and int(restored_counts.get(action_id, 0)) == 1 \
			and _source_is_armed(gs, source),
		"same-presenter restore burns but does not grant the unowned receipt and rearms the source")
	check(_trigger_exact_optional_read(preview, source, "peris")
			and _source_trigger_count(gs, source) == 2
			and int((chunk.get_preview_state().get(
				"optional_read_consumed_counts", {}) as Dictionary).get(
					action_id, 0)) == 2,
		"retry after same-presenter reconciliation commits exactly the next source identity")

	var fresh = await _spawn_rings_preview()
	if fresh != null:
		fresh.apply_save_snapshot(accepted_snapshot)
		fresh._active_chunk.on_game_state_snapshot_restored()
		var fresh_chunk = fresh._active_chunk
		var fresh_source: Node = fresh_chunk.get_playthrough_interaction_target(
			action_id)
		var fresh_counts: Dictionary = fresh_chunk.get_preview_state().get(
			"optional_read_consumed_counts", {})
		check(not bool(fresh_chunk.get_preview_state().get("client_seen", true))
				and int(fresh_counts.get(action_id, 0)) == 1 \
				and _source_is_armed(fresh._game_state, fresh_source),
			"fresh presenter reconciles the same accepted edge without inventing the memory")
		check(_trigger_exact_optional_read(fresh, fresh_source, "peris")
				and _source_trigger_count(fresh._game_state, fresh_source) == 2,
			"fresh-presenter retry also consumes exactly one newer receipt")
		await _discard(fresh)
	await _discard(preview)


func _verify_optional_read_v2_migration() -> void:
	var preview = await _spawn_rings_preview()
	if preview == null:
		return
	var chunk = preview._active_chunk
	var propagation: Node = chunk.get_playthrough_interaction_target(
		chunk.OPTIONAL_READ_PROPAGATION)
	check(_trigger_exact_optional_read(preview, propagation, "peris"),
		"v2 migration fixture acquires one optional memory physically")
	var legacy_snapshot := _json_round_trip(preview.build_save_snapshot())
	var game_state: Dictionary = legacy_snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	var legacy_authority: Dictionary = world_state.get(
		chunk.rings_authority_key(), {})
	legacy_authority["version"] = 2
	legacy_authority.erase("optional_read_consumed_counts")
	world_state[chunk.rings_authority_key()] = legacy_authority
	game_state["world_state"] = world_state
	legacy_snapshot["game_state"] = game_state

	var fresh = await _spawn_rings_preview()
	if fresh != null:
		fresh.apply_save_snapshot(legacy_snapshot)
		var fresh_chunk = fresh._active_chunk
		var migrated: Dictionary = fresh._game_state.get_world_state(
			fresh_chunk.rings_authority_key(), {})
		var migrated_counts: Dictionary = migrated.get(
			"optional_read_consumed_counts", {})
		check(int(migrated.get("version", 0)) == fresh_chunk.RINGS_AUTHORITY_VERSION
				and bool(fresh_chunk.get_preview_state().get(
					"propagation_seen", false))
				and int(migrated_counts.get(
					fresh_chunk.OPTIONAL_READ_PROPAGATION, 0)) == 1,
			"v2 Rings save migrates its acquired memory onto v3 exact receipt authority")
		check(not bool(fresh_chunk.get_preview_state().get("client_seen", true))
				and _source_is_armed(
					fresh._game_state,
					fresh_chunk.get_playthrough_interaction_target(
						fresh_chunk.OPTIONAL_READ_CLIENT_BLOOM)),
			"v2 migration keeps every unobserved optional source available and order-free")
		await _discard(fresh)
	await _discard(preview)


func _trigger_source_without_reposition(source: Node, actor: String) -> bool:
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _trigger_exact_optional_read(
		preview: Node, source: Node, actor: String
	) -> bool:
	var gs: GameState = preview._game_state
	gs.command_stop(actor)
	var position: Vector3 = preview._active_chunk._optional_read_source_data_position(
		source)
	gs.snap_character_to(actor, position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _source_trigger_count(gs: GameState, source: Node) -> int:
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _source_is_armed(gs: GameState, source: Node) -> bool:
	if not is_instance_valid(source):
		return false
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return false
	var spec: Dictionary = gs.get_interactable(data_id)
	return bool(spec.get("one_shot", false)) \
		and not bool(spec.get("triggered", true)) \
		and bool(spec.get("enabled", false)) \
		and not bool(source.get("_used")) \
		and bool(source.get("interaction_enabled"))


func _right_click_marco(preview: Node, max_seconds := 12.0) -> bool:
	var chunk = preview._active_chunk
	var target: Node = chunk.get_playthrough_interaction_target("marco_reassignment")
	if target == null or not target.has_method("_on_input_event") \
			or not bool(target.call("is_interaction_enabled")):
		return false
	var active_character: Node = preview.get_preview_character_node(
		preview.get_preview_active_character())
	var controller: Node = active_character.get_node_or_null(
		"CharacterInteractionController") if active_character != null else null
	if controller == null:
		return false
	var requested := {"seen": false}
	var observe_request := func(_target: Node, _position: Vector3) -> void:
		requested["seen"] = true
	target.connect("interaction_requested", observe_request, CONNECT_ONE_SHOT)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	target.call(
		"_on_input_event",
		null,
		event,
		(target as Node3D).global_position,
		Vector3.UP,
		0)
	var elapsed := 0.0
	while controller.get("active_target") != null and elapsed < max_seconds:
		preview.headless_advance(0.05, 0.05)
		controller.call("sync_scheduler_visuals")
		elapsed += 0.05
	if target.is_connected("interaction_requested", observe_request):
		target.disconnect("interaction_requested", observe_request)
	return bool(requested["seen"]) and controller.get("active_target") == null


func _place_reassignment_party(preview: Node, chunk: Node) -> void:
	var marco_position: Vector3 = chunk.MARCO_POS + Vector3(0.0, 0.5, 0.0)
	preview.headless_set_character_position(
		"peris", marco_position + Vector3(-1.1, 0.0, 0.4))
	preview.headless_set_character_position(
		"endo", marco_position + Vector3(1.1, 0.0, -0.4))


func _marco_is_canonically_armed(gs: GameState, target: Node) -> bool:
	var data_id := str(target.get("data_id"))
	if data_id.is_empty() or not gs.interactables.has(data_id):
		return false
	var spec: Dictionary = gs.interactables[data_id]
	return not bool(spec.get("triggered", true)) \
		and bool(spec.get("enabled", false)) \
		and not bool(target.get("_used")) \
		and bool(target.call("is_interaction_enabled"))


func _verify_render_frame_invariance(
		preview: Node, chunk: Node, committed: Dictionary, authority: Dictionary
	) -> void:
	var gs: GameState = preview._game_state
	var tick_before := float(preview._scheduler.get_current_tick())
	var position_before := gs.get_position("endo")
	var progress_before := float(committed.get("progress", -1.0))
	for _frame in range(240):
		chunk._process(1.0 / 60.0)
		chunk.headless_process(1.0 / 60.0)
	var after := gs.get_external_traversal_state("endo")
	check(is_equal_approx(float(preview._scheduler.get_current_tick()), tick_before)
			and is_equal_approx(float(after.get("progress", -2.0)), progress_before)
			and gs.get_position("endo").distance_to(position_before) < 0.0001,
		"480 render/headless presentation calls cannot advance Endo without scheduler time")
	check(gs.get_world_state(chunk.rings_authority_key(), {}) == authority
			and gs.characters.has("endo"),
		"presentation frames mutate neither departure authority nor roster truth")


func _advance_across_deadline(preview: Node, deadline: float) -> void:
	var remaining := deadline - float(preview._scheduler.get_current_tick())
	preview.headless_advance(maxf(0.0, remaining - DEADLINE_EPSILON), 0.25)
	check(preview._game_state.is_external_traversal_active("endo")
			and preview._game_state.characters.has("endo"),
		"saved departure cannot retire Endo before its exact deadline")
	preview.headless_advance(DEADLINE_EPSILON * 1.1, DEADLINE_EPSILON * 1.1)


func _verify_departed_truth(
		preview: Node, chunk: Node, completion_count: Dictionary, label: String
	) -> void:
	var gs: GameState = preview._game_state
	var node: Node3D = preview.get_preview_character_node("endo")
	var selected: Array = preview.get_preview_selected_characters()
	check(str(chunk.get_preview_state().get("endo_phase", "")) == "departed"
			and bool(chunk.get_preview_state().get("complete", false)),
		"%s completion commits the semantic departed phase" % label)
	check(not gs.characters.has("endo") and not gs.get_party().has("endo"),
		"%s completion removes Endo from canonical roster and party" % label)
	check(not preview.is_preview_character_present("endo")
			and node != null and not node.visible,
		"%s completion removes Endo from presence and visibility truth" % label)
	check(not selected.has("endo") and preview.get_preview_active_character() != "endo",
		"%s completion removes Endo from selected and active control truth" % label)
	if not completion_count.is_empty():
		check(int(completion_count.get("value", 0)) >= 1,
			"%s completion crossed the external-traversal callback" % label)


func _spawn_rings_preview():
	var preview = PreviewScene.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "rings"
	preview.suppress_scene_change = true
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	check(preview._active_chunk != null, "Rings preview boots its production chunk")
	if preview._active_chunk == null:
		await _discard(preview)
		return null
	return preview


func _erase_rings_authority(snapshot: Dictionary, key: String) -> void:
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


func _finish() -> void:
	print("RINGS DEPARTURE SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
