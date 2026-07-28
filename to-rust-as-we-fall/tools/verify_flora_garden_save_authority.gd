extends SceneTree

## Flora Garden save-authority regression. The causal split is deliberate: GameState.flora owns
## growth/tending, while the garden's portable world-state record owns finite crate stock and the
## pad->growth relationship. Stable per-pad presenters must never become a second source of truth.

const HostScript := preload("res://scripts/fragments/chunk_host_stub.gd")
const FloraGardenScript := preload("res://scripts/fragments/chunks/flora_garden_chunk.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	await _verify_site_identity_boundary()
	await _verify_exact_physical_source_receipts()
	await _verify_accepted_before_callback_seams()
	await _verify_seed_claim_authority()
	await _verify_plant_signal_authority()
	await _verify_legacy_source_migration()
	await _verify_garden_rollback_and_reconstruction()
	print("FLORA GARDEN SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _verify_site_identity_boundary() -> void:
	var grid := GridWorld.new()
	grid.create_room(16, 12, true)
	var scheduler := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = grid
	gs.scheduler = scheduler
	gs.register_character("peris", Vector3(4.0, 0.0, 4.0), 3.0)
	var first_seed := gs.spawn_item("flora_seed", gs.get_position("peris"))
	gs.pick_up_item("peris", first_seed)
	var first_flora := gs.command_plant_flora("peris", Vector3(4.5, 0.0, 4.5))
	check(first_flora != "", "GameState plants the first flora at an empty physical site")

	var second_seed := gs.spawn_item("flora_seed", gs.get_position("peris"))
	gs.pick_up_item("peris", second_seed)
	var overlap := gs.command_plant_flora("peris", Vector3(4.55, 0.0, 4.5))
	check(overlap == "" and gs.flora.size() == 1,
		"a forged caller cannot stack a second flora inside the site tolerance")
	check(gs.find_carried_item("peris", "flora_seed") == second_seed and gs.items.has(second_seed),
		"rejecting an occupied site does not consume the caller's second seed")
	var nearby := gs.command_plant_flora("peris", Vector3(4.75, 0.0, 4.5))
	check(nearby != "" and gs.flora.size() == 2,
		"a genuinely distinct nearby site remains legal outside the 0.1-unit identity tolerance")


func _verify_exact_physical_source_receipts() -> void:
	var pair := await _boot_garden()
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	var crate: Node = chunk._seed_crate_interactable
	var crate_action: String = str(chunk.ACTION_SEED_CRATE)
	var all_sources_exact := bool(crate.get("one_shot"))
	for pad_index in range(chunk.PAD_POSITIONS.size()):
		all_sources_exact = all_sources_exact \
			and bool(chunk._pad_interactables[pad_index].get("one_shot")) \
			and bool(chunk._tend_interactables[pad_index].get("one_shot"))
	check(all_sources_exact
			and (chunk.get_preview_state().source_committed_counts as Dictionary).size() == 7,
		"crate, all three planting pads, and all three tend controls own one-shot receipt edges")

	var baseline_stock := int(chunk.get_preview_state().seed_stock)
	check(not chunk._on_seed_taken()
			and int(chunk.get_preview_state().seed_stock) == baseline_stock,
		"the callback-shaped crate helper is inert without a physical source receipt")
	crate.interacted.emit()
	check(int(chunk.get_preview_state().seed_stock) == baseline_stock
			and _source_trigger_count(gs, crate) == 0,
		"manually emitting the crate signal cannot issue or consume a seed")

	gs.snap_character_to("peris", Vector3(19.0, 0.0, 10.0))
	check(not _trigger_source_without_reposition(crate, "peris")
			and _source_trigger_count(gs, crate) == 0,
		"a selected but remote Peris cannot impersonate the body at the crate")
	gs.snap_character_to("aster", chunk._garden_source_data_position(crate))
	check(not _trigger_source_without_reposition(crate, "aster")
			and _source_trigger_count(gs, crate) == 0,
		"Aster standing at the crate cannot substitute for canonical Peris")

	var crate_position: Vector3 = chunk._garden_source_data_position(crate)
	gs.snap_character_to("peris", crate_position)
	check(gs.command_move_to_pos("peris", crate_position + Vector3(2.5, 0.0, 0.0)),
		"busy-source fixture starts a real Peris movement")
	check(not _trigger_source_without_reposition(crate, "peris")
			and _source_trigger_count(gs, crate) == 0,
		"a moving Peris cannot commit garden work")
	gs.command_stop("peris")
	gs.snap_character_to("peris", crate_position)
	gs.down_character("peris")
	check(not _trigger_source_without_reposition(crate, "peris")
			and _source_trigger_count(gs, crate) == 0,
		"a downed Peris cannot commit garden work")
	gs.restore_character("peris")

	host.grid.set_level_count(2)
	gs.set_character_level("peris", 1)
	check(not _trigger_source_without_reposition(crate, "peris")
			and _source_trigger_count(gs, crate) == 0,
		"matching x/z on the wrong navigation floor cannot service the crate")
	gs.set_character_level("peris", 0)
	check(_trigger_garden_source(gs, crate, "peris")
			and _source_trigger_count(gs, crate) == 1
			and int((chunk.get_preview_state().source_committed_counts as Dictionary).get(
				crate_action, 0)) == 1,
		"nearby ready Peris consumes the crate's exact first receipt")
	var stock_after_claim := int(chunk.get_preview_state().seed_stock)
	check(not chunk._on_seed_taken(crate)
			and int(chunk.get_preview_state().seed_stock) == stock_after_claim,
		"a stale consumed crate receipt cannot issue a second seed")

	var pad: Node = chunk._pad_interactables[0]
	check(not chunk._on_pad_planted()
			and not chunk._on_pad_planted(pad) and gs.flora.is_empty(),
		"planting helpers are inert without their pad's newly accepted receipt")
	pad.interacted.emit()
	check(gs.flora.is_empty() and _source_trigger_count(gs, pad) == 0,
		"manually emitting a planting-pad signal cannot consume the carried seed")
	gs.snap_character_to("peris", Vector3(19.0, 0.0, 10.0))
	check(not _trigger_source_without_reposition(pad, "peris")
			and _source_trigger_count(gs, pad) == 0,
		"a remote portrait cannot plant at a pad")
	check(_trigger_garden_source(gs, pad, "peris") and gs.flora.size() == 1
			and _source_trigger_count(gs, pad) == 1,
		"the exact nearby planting pad consumes one seed into one physical growth")
	var flora_id := str(chunk._pad_flora_ids[0])
	check(not chunk._on_pad_planted(pad) and gs.flora.size() == 1,
		"a stale planting receipt cannot stack another growth on the occupied pad")

	host.scheduler.advance_ticks(76.0)
	chunk.headless_process(0.0)
	var tend: Node = chunk._tend_interactables[0]
	check(not chunk._on_pad_tended(0)
			and not chunk._on_pad_tended(0, tend)
			and not bool((gs.flora[flora_id] as Dictionary).get("tended_today", false)),
		"tending helpers are inert without the FloraPad receipt")
	tend.interacted.emit()
	check(not bool((gs.flora[flora_id] as Dictionary).get("tended_today", false))
			and _source_trigger_count(gs, tend) == 0,
		"manually emitting the tend signal cannot tend the growth")
	gs.snap_character_to("peris", Vector3(19.0, 0.0, 10.0))
	check(not _trigger_source_without_reposition(tend, "peris")
			and _source_trigger_count(gs, tend) == 0,
		"a remote Peris cannot tend through her portrait")
	check(_trigger_garden_source(gs, tend, "peris")
			and bool((gs.flora[flora_id] as Dictionary).get("tended_today", false))
			and _source_trigger_count(gs, tend) == 1,
		"the exact nearby tend control commits the day's canonical growth care")
	check(not chunk._on_pad_tended(0, tend)
			and not chunk._on_flora_tended(flora_id, "peris")
			and _source_trigger_count(gs, tend) == 1,
		"stale tend and retired direct-flora callbacks cannot repeat the day's work")

	await _discard(host)


func _verify_accepted_before_callback_seams() -> void:
	# Crate acceptance: source trigger exists, but neither stock nor exact item transaction has begun.
	var crate_pair := await _boot_garden()
	var crate_host = crate_pair.host
	var crate_chunk = crate_pair.chunk
	var crate_gs = crate_host.game_state
	var crate: Node = crate_chunk._seed_crate_interactable
	var crate_box := {"snapshot": {}}
	var crate_capture := func(data_id: String, _actor: String) -> void:
		if data_id == str(crate.get("data_id")) \
				and (crate_box.get("snapshot", {}) as Dictionary).is_empty():
			crate_box["snapshot"] = _capture(crate_host)
	crate_gs.interactable_triggered.connect(crate_capture, CONNECT_ONE_SHOT)
	check(_trigger_garden_source(crate_gs, crate, "peris"),
		"crate seam fixture completes normally after the captured source edge")
	var crate_accept: Dictionary = crate_box.get("snapshot", {}) as Dictionary
	var crate_accept_record := _garden_record(crate_accept, crate_chunk)
	check(not crate_accept.is_empty()
			and int(crate_accept_record.get("seed_stock", -1)) == 3
			and int((crate_accept_record.get("source_committed_counts", {}) as Dictionary).get(
				crate_chunk.ACTION_SEED_CRATE, -1)) == 0,
		"accepted-before-callback crate save contains no free seed consequence")
	_apply_capture(crate_host, crate_chunk, crate_accept)
	check(int(crate_chunk.get_preview_state().seed_stock) == 3
			and crate_chunk._find_carried_garden_seed("peris") == ""
			and crate.is_interaction_enabled()
			and _source_trigger_count(crate_gs, crate) == 1,
		"same presenter burns the stale crate receipt and rearms its exact source")
	check(not crate_chunk._on_seed_taken(crate)
			and _trigger_garden_source(crate_gs, crate, "peris")
			and _source_trigger_count(crate_gs, crate) == 2
			and int(crate_chunk.get_preview_state().seed_stock) == 2,
		"only a second physical crate receipt can issue the seed after same restore")
	var fresh_crate := await _boot_garden()
	_apply_capture(fresh_crate.host, fresh_crate.chunk, crate_accept)
	check(int(fresh_crate.chunk.get_preview_state().seed_stock) == 3
			and fresh_crate.chunk._seed_crate_interactable.is_interaction_enabled()
			and not fresh_crate.chunk._on_seed_taken(
				fresh_crate.chunk._seed_crate_interactable)
			and _trigger_garden_source(
				fresh_crate.host.game_state,
				fresh_crate.chunk._seed_crate_interactable, "peris"),
		"fresh presenter also requires a new physical crate receipt")

	# Plant acceptance: the exact seed remains in Peris's hand until the owner callback publishes
	# PLANTING and GameState atomically consumes it into a growth.
	var plant_pair := await _boot_garden()
	var plant_host = plant_pair.host
	var plant_chunk = plant_pair.chunk
	var plant_gs = plant_host.game_state
	check(_trigger_garden_source(
			plant_gs, plant_chunk._seed_crate_interactable, "peris"),
		"plant seam fixture first claims one exact source seed")
	var plant_seed: String = plant_chunk._find_carried_garden_seed("peris")
	var pad: Node = plant_chunk._pad_interactables[0]
	var plant_box := {"snapshot": {}}
	var plant_capture := func(data_id: String, _actor: String) -> void:
		if data_id == str(pad.get("data_id")) \
				and (plant_box.get("snapshot", {}) as Dictionary).is_empty():
			plant_box["snapshot"] = _capture(plant_host)
	plant_gs.interactable_triggered.connect(plant_capture, CONNECT_ONE_SHOT)
	check(_trigger_garden_source(plant_gs, pad, "peris"),
		"plant seam fixture completes normally after its captured pad edge")
	var plant_accept: Dictionary = plant_box.get("snapshot", {}) as Dictionary
	check(not plant_accept.is_empty()
			and str(_garden_record(plant_accept, plant_chunk).get(
				"plant_phase", "")) == plant_chunk.PLANT_IDLE,
		"accepted-before-callback planting save has not begun a fake growth transaction")
	_apply_capture(plant_host, plant_chunk, plant_accept)
	check(plant_gs.flora.is_empty() and plant_gs.items.has(plant_seed)
			and plant_chunk._find_carried_garden_seed("peris") == plant_seed
			and pad.is_interaction_enabled(),
		"same presenter restores the exact seed in hand and rearms the empty pad")
	check(not plant_chunk._on_pad_planted(pad)
			and _trigger_garden_source(plant_gs, pad, "peris")
			and plant_gs.flora.size() == 1
			and _source_trigger_count(plant_gs, pad) == 2,
		"only a new physical pad receipt consumes the seed after same restore")
	var fresh_plant := await _boot_garden()
	_apply_capture(fresh_plant.host, fresh_plant.chunk, plant_accept)
	check(fresh_plant.host.game_state.flora.is_empty()
			and fresh_plant.chunk._pad_interactables[0].is_interaction_enabled()
			and _trigger_garden_source(
				fresh_plant.host.game_state,
				fresh_plant.chunk._pad_interactables[0], "peris"),
		"fresh presenter likewise restores the seed rather than granting a growth")

	# Tend acceptance: the source edge alone cannot set tended_today. Both presenter lifecycles
	# restore the untended growth and require the next exact FloraPad edge.
	var tend_pair := await _boot_garden()
	var tend_host = tend_pair.host
	var tend_chunk = tend_pair.chunk
	var tend_gs = tend_host.game_state
	var tend_flora := _take_and_plant(tend_host, tend_chunk, 0)
	tend_host.scheduler.advance_ticks(76.0)
	tend_chunk.headless_process(0.0)
	var tend: Node = tend_chunk._tend_interactables[0]
	var tend_box := {"snapshot": {}}
	var tend_capture := func(data_id: String, _actor: String) -> void:
		if data_id == str(tend.get("data_id")) \
				and (tend_box.get("snapshot", {}) as Dictionary).is_empty():
			tend_box["snapshot"] = _capture(tend_host)
	tend_gs.interactable_triggered.connect(tend_capture, CONNECT_ONE_SHOT)
	check(_trigger_garden_source(tend_gs, tend, "peris"),
		"tend seam fixture completes normally after its captured source edge")
	var tend_accept: Dictionary = tend_box.get("snapshot", {}) as Dictionary
	var tend_saved_flora: Dictionary = (
		tend_accept.get("game_state", {}) as Dictionary).get("flora", {})
	check(not tend_accept.is_empty() and tend_saved_flora.has(tend_flora)
			and not bool((tend_saved_flora[tend_flora] as Dictionary).get(
				"tended_today", false)),
		"accepted-before-callback tend save contains no free daily care")
	_apply_capture(tend_host, tend_chunk, tend_accept)
	check(not bool((tend_gs.flora[tend_flora] as Dictionary).get(
				"tended_today", false))
			and tend.is_interaction_enabled()
			and not tend_chunk._on_pad_tended(0, tend)
			and _trigger_garden_source(tend_gs, tend, "peris")
			and _source_trigger_count(tend_gs, tend) == 2,
		"same presenter rearms untended growth and rejects the stale tend callback")
	var fresh_tend := await _boot_garden()
	_apply_capture(fresh_tend.host, fresh_tend.chunk, tend_accept)
	var fresh_tend_flora := str(fresh_tend.chunk._pad_flora_ids[0])
	check(fresh_tend_flora == tend_flora
			and not bool((fresh_tend.host.game_state.flora[fresh_tend_flora] as Dictionary).get(
				"tended_today", false))
			and fresh_tend.chunk._tend_interactables[0].is_interaction_enabled()
			and _trigger_garden_source(
				fresh_tend.host.game_state,
				fresh_tend.chunk._tend_interactables[0], "peris"),
		"fresh presenter also requires a new FloraPad receipt for daily care")

	for disposable in [
		crate_host, fresh_crate.host, plant_host, fresh_plant.host,
		tend_host, fresh_tend.host,
	]:
		await _discard(disposable)


func _verify_seed_claim_authority() -> void:
	var pair := await _boot_garden()
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	var initial := _capture(host)
	var initial_state: Dictionary = chunk.get_preview_state()
	var source_ids: Array = initial_state.get("source_seed_ids", [])
	var source_id := str(source_ids[0]) if not source_ids.is_empty() else ""
	check(source_ids.size() == chunk.INITIAL_SEED_STOCK
			and int(initial_state.get("available_source_seed_count", 0)) == chunk.INITIAL_SEED_STOCK,
		"all finite crate stock exists as three physical source identities before pickup")

	gs.snap_character_to("peris", Vector3(18.0, 0.0, 10.0))
	check(not _trigger_source_without_reposition(
			chunk._seed_crate_interactable, "peris")
			and int(chunk.get_preview_state().seed_stock) == chunk.INITIAL_SEED_STOCK
			and str((chunk.get_preview_state().source_seed_ids as Array)[0]) == source_id,
		"an out-of-range crate request cannot replace or consume its first source seed")

	gs.snap_character_to("peris", chunk.SEED_CRATE_POS + Vector3(0.2, 0.0, 0.0))
	var blocker_id: String = gs.spawn_item("garden_authority_blocker", gs.get_position("peris"), {
		"hand_slots": 2,
		"endocytosis_allowed": false,
	})
	check(gs.pick_up_item("peris", blocker_id), "fixture fills both of Peris's physical hands")
	check(not _trigger_source_without_reposition(
			chunk._seed_crate_interactable, "peris")
			and int(chunk.get_preview_state().available_source_seed_count) == chunk.INITIAL_SEED_STOCK,
		"full hands leave every crate seed at its original source")
	gs.remove_item(blocker_id)

	var signal_box := {"snapshot": {}}
	var pickup_capture := func(char_id: String, item_id: String) -> void:
		if char_id == "peris" and item_id == source_id \
				and (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _capture(host)
	gs.item_picked_up.connect(pickup_capture, CONNECT_ONE_SHOT)
	check(_trigger_garden_source(gs, chunk._seed_crate_interactable, "peris"),
		"the nearby free-handed tender can claim the first exact seed")
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {}) as Dictionary
	var signal_record := _garden_record(signal_snapshot, chunk)
	check(not signal_snapshot.is_empty()
			and str(signal_record.get("seed_claim_phase", "")) == chunk.SEED_CLAIMING
			and str(signal_record.get("seed_claim_item_id", "")) == source_id
			and str(signal_record.get("seed_claimed_by", "")) == "peris",
		"pickup-signal snapshot carries an exact item/actor CLAIMING reservation")

	_apply_capture(host, chunk, signal_snapshot)
	var restored: Dictionary = chunk.get_preview_state()
	check(str(restored.get("seed_claim_phase", "")) == chunk.SEED_CLAIM_IDLE
			and int(restored.get("seed_stock", -1)) == 2
			and chunk._seed_holder(source_id) == "peris",
		"same-presenter signal restore completes that exact seed claim once")

	var fresh_pair := await _boot_garden()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, signal_snapshot)
	var fresh_state: Dictionary = fresh_pair.chunk.get_preview_state()
	check(str(fresh_state.get("seed_claim_phase", "")) == fresh_pair.chunk.SEED_CLAIM_IDLE
			and fresh_pair.chunk._seed_holder(source_id) == "peris"
			and int(fresh_state.get("available_source_seed_count", -1)) == 2,
		"fresh-presenter signal restore preserves the same holder and remaining source pile")

	var wrong_holder := _json_round_trip(signal_snapshot)
	var wrong_record := _garden_record(wrong_holder, chunk)
	wrong_record["seed_claimed_by"] = "aster"
	_set_garden_record(wrong_holder, chunk, wrong_record)
	_apply_capture(fresh_pair.host, fresh_pair.chunk, wrong_holder)
	var wrong_state: Dictionary = fresh_pair.chunk.get_preview_state()
	check(str(wrong_state.get("seed_claim_phase", "")) == fresh_pair.chunk.SEED_CLAIMING
			and str(wrong_state.get("seed_claimed_by", "")) == "aster"
			and fresh_pair.chunk._seed_holder(source_id) == "peris"
			and not fresh_pair.chunk._seed_crate_interactable.is_interaction_enabled()
			and _enabled_count(fresh_pair.chunk._pad_interactables) == 0,
		"wrong-holder injection remains unresolved and cannot retarget or plant the seed")

	_apply_capture(host, chunk, initial)
	await _discard(host)
	await _discard(fresh_pair.host)


func _verify_plant_signal_authority() -> void:
	var pair := await _boot_garden()
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	gs.snap_character_to("peris", chunk.SEED_CRATE_POS + Vector3(0.2, 0.0, 0.0))
	check(_trigger_garden_source(gs, chunk._seed_crate_interactable, "peris"),
		"plant fixture carries one exact crate seed")
	var seed_id: String = chunk._find_carried_garden_seed("peris")
	gs.snap_character_to("peris", chunk.PAD_POSITIONS[0] + Vector3(0.2, 0.0, 0.0))

	var pre_box := {"snapshot": {}}
	var pre_capture := func(key: String, value: Variant) -> void:
		if key != chunk.flora_garden_authority_key() or not value is Dictionary \
				or str((value as Dictionary).get("plant_phase", "")) != chunk.PLANTING \
				or not (pre_box.get("snapshot", {}) as Dictionary).is_empty():
			return
		if gs.items.has(seed_id):
			pre_box["snapshot"] = _capture(host)
	var signal_box := {"snapshot": {}}
	var flora_capture := func(_flora_id: String) -> void:
		if (signal_box.get("snapshot", {}) as Dictionary).is_empty():
			signal_box["snapshot"] = _capture(host)
	gs.world_state_changed.connect(pre_capture)
	gs.flora_planted.connect(flora_capture, CONNECT_ONE_SHOT)
	check(_trigger_garden_source(gs, chunk._pad_interactables[0], "peris"),
		"ordinary planting consumes the reserved seed into one physical growth")
	gs.world_state_changed.disconnect(pre_capture)
	var pre_snapshot: Dictionary = pre_box.get("snapshot", {}) as Dictionary
	var signal_snapshot: Dictionary = signal_box.get("snapshot", {}) as Dictionary
	check(not pre_snapshot.is_empty() and not signal_snapshot.is_empty()
			and str(_garden_record(pre_snapshot, chunk).get("plant_phase", "")) == chunk.PLANTING
			and str(_garden_record(signal_snapshot, chunk).get("plant_phase", "")) == chunk.PLANTING,
		"both sides of the consume/growth signal boundary retain the PLANTING reservation")

	_apply_capture(host, chunk, pre_snapshot)
	check(host.game_state.flora.is_empty() and host.game_state.items.has(seed_id)
			and str(chunk.get_preview_state().get("plant_phase", "")) == chunk.PLANT_IDLE
			and str((chunk.get_preview_state().pad_flora_ids as Array)[0]) == "",
		"pre-consume restore keeps the seed in hand and grants no planted pad")
	_apply_capture(host, chunk, signal_snapshot)
	var restored: Dictionary = chunk.get_preview_state()
	var flora_id := str((restored.get("pad_flora_ids", []) as Array)[0])
	check(flora_id != "" and host.game_state.flora.has(flora_id)
			and str((host.game_state.flora[flora_id] as Dictionary).get("source_seed_id", "")) == seed_id
			and not host.game_state.items.has(seed_id)
			and str(restored.get("plant_phase", "")) == chunk.PLANT_IDLE,
		"signal-time restore binds the consumed exact seed to one growth and one pad")

	var fresh_pair := await _boot_garden()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, signal_snapshot)
	var fresh_state: Dictionary = fresh_pair.chunk.get_preview_state()
	check(int(fresh_state.get("visible_growth_count", 0)) == 1
			and str((fresh_state.get("pad_flora_ids", []) as Array)[0]) == flora_id
			and not fresh_pair.host.game_state.items.has(seed_id),
		"fresh-presenter planting-signal restore cannot duplicate the seed or growth")

	await _discard(host)
	await _discard(fresh_pair.host)


func _verify_legacy_source_migration() -> void:
	var pair := await _boot_garden()
	var host = pair.host
	var chunk = pair.chunk
	var flora_id := _take_and_plant(host, chunk, 0)
	var version_two := _capture(host)
	var version_two_record := _garden_record(version_two, chunk)
	version_two_record["version"] = 2
	version_two_record.erase("source_committed_counts")
	_set_garden_record(version_two, chunk, version_two_record)
	var version_two_pair := await _boot_garden()
	_apply_capture(version_two_pair.host, version_two_pair.chunk, version_two)
	var version_two_state: Dictionary = version_two_pair.chunk.get_preview_state()
	var migrated_v2_record: Dictionary = version_two_pair.host.game_state.get_world_state(
		version_two_pair.chunk.flora_garden_authority_key(), {})
	check(int(migrated_v2_record.get("version", 0)) \
			== version_two_pair.chunk.GARDEN_AUTHORITY_VERSION
			and int((version_two_state.get("source_committed_counts", {}) as Dictionary).get(
				version_two_pair.chunk.ACTION_SEED_CRATE, -1)) \
				== _source_trigger_count(
					version_two_pair.host.game_state,
					version_two_pair.chunk._seed_crate_interactable)
			and bool(version_two_pair.chunk._seed_crate_interactable.get("one_shot")),
		"v2 physical-stock saves burn legacy receipt history and migrate to exact one-shots")
	var legacy := _capture(host)
	var record := _garden_record(legacy, chunk)
	var source_ids: Array = record.get("source_seed_ids", [])
	var issued_ids: Array = record.get("issued_seed_ids", [])
	var legacy_record := {
		"version": 1,
		"authority_id": chunk.flora_garden_authority_key(),
		"seed_stock": record.get("seed_stock", 2),
		"issued_seed_ids": issued_ids.duplicate(),
		"pad_flora_ids": (record.get("pad_flora_ids", []) as Array).duplicate(),
		"pad_seed_ids": (record.get("pad_seed_ids", []) as Array).duplicate(),
	}
	_set_garden_record(legacy, chunk, legacy_record)
	var legacy_gs: Dictionary = legacy.get("game_state", {})
	var legacy_items: Dictionary = legacy_gs.get("items", {})
	for source_id_v in source_ids:
		var source_id := str(source_id_v)
		if not issued_ids.has(source_id):
			legacy_items.erase(source_id)
	legacy_gs["items"] = legacy_items
	var legacy_flora: Dictionary = legacy_gs.get("flora", {})
	if legacy_flora.has(flora_id):
		var growth: Dictionary = legacy_flora[flora_id]
		growth.erase("source_seed_id")
		legacy_flora[flora_id] = growth
	legacy_gs["flora"] = legacy_flora
	legacy["game_state"] = legacy_gs

	var fresh_pair := await _boot_garden()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, legacy)
	var migrated: Dictionary = fresh_pair.chunk.get_preview_state()
	var migrated_record: Dictionary = fresh_pair.host.game_state.get_world_state(
		fresh_pair.chunk.flora_garden_authority_key(), {})
	check(int(migrated_record.get("version", 0)) == fresh_pair.chunk.GARDEN_AUTHORITY_VERSION
			and int(migrated.get("source_seed_count", 0)) == fresh_pair.chunk.INITIAL_SEED_STOCK
			and int(migrated.get("available_source_seed_count", 0)) == 2
			and int(migrated.get("visible_growth_count", 0)) == 1,
		"v1 counter-only saves preserve the planted seed and expose remaining stock physically")
	check(str((fresh_pair.host.game_state.flora[flora_id] as Dictionary).get(
			"source_seed_id", "")) == str(issued_ids[0])
			and _carried_garden_seed_count(
				fresh_pair.host.game_state, fresh_pair.chunk, "peris") == 0,
		"legacy migration attaches exact growth provenance without minting a carrier")

	await _discard(host)
	await _discard(fresh_pair.host)
	await _discard(version_two_pair.host)


func _verify_garden_rollback_and_reconstruction() -> void:
	var pair := await _boot_garden()
	var host = pair.host
	var chunk = pair.chunk
	var gs = host.game_state
	var baseline := _capture(host)
	check(_baseline_truth(chunk),
		"construction projects three seeds, three empty pads, and no solved growth presenters")

	var first_flora := _take_and_plant(host, chunk, 0)
	check(first_flora != "" and gs.flora.size() == 1,
		"the first crate seed becomes one real GameState growth")
	check(int(chunk.get_preview_state().seed_stock) == 2
			and int(chunk.get_preview_state().issued_seed_count) == 1,
		"finite crate stock commits alongside the first issued seed")
	check(_enabled_count(chunk._pad_interactables) == 0
			and not chunk._tend_interactables[0].is_interaction_enabled(),
		"empty-pad actions wait for a physically carried seed and tending derives from growth truth")
	var first_capture := _capture(host)

	var second_flora := _take_and_plant(host, chunk, 1)
	check(second_flora != "" and gs.flora.size() == 2,
		"a discarded future can occupy a second distinct pad")
	_apply_capture(host, chunk, first_capture)
	var rolled: Dictionary = chunk.get_preview_state()
	check(gs.flora.size() == 1 and int(rolled.seed_stock) == 2
			and int(rolled.visible_growth_count) == 1,
		"same-instance rollback retracts the future growth and restores exact seed stock")
	check(str(rolled.pad_flora_ids[0]) == first_flora and str(rolled.pad_flora_ids[1]) == ""
			and _enabled_count(chunk._pad_interactables) == 0,
		"same-instance rollback cannot retain the discarded pad's solved flag")
	check(chunk._pad_visuals.size() == 3 and chunk._tend_interactables.size() == 3,
		"rollback reuses the three authored presentation slots instead of appending nodes")

	gs.snap_character_to("peris", chunk.SEED_CRATE_POS + Vector3(0.2, 0.0, 0.0))
	_trigger_garden_source(gs, chunk._seed_crate_interactable, "peris")
	_trigger_garden_source(gs, chunk._seed_crate_interactable, "peris")
	check(int(chunk.get_preview_state().seed_stock) == 1
			and int(chunk.get_preview_state().available_source_seed_count) == 1
			and _carried_garden_seed_count(gs, chunk, "peris") == 1
			and _flora_seed_item_count(gs) == 2,
		"re-triggering while a seed is carried cannot duplicate finite crate stock")
	_apply_capture(host, chunk, first_capture)
	check(int(chunk.get_preview_state().seed_stock) == 2
			and int(chunk.get_preview_state().available_source_seed_count) == 2
			and _carried_garden_seed_count(gs, chunk, "peris") == 0
			and _flora_seed_item_count(gs) == 2,
		"rollback returns the discarded future to two exact source seeds at the crate")

	var fresh_pair := await _boot_garden()
	_apply_capture(fresh_pair.host, fresh_pair.chunk, first_capture)
	var fresh_state: Dictionary = fresh_pair.chunk.get_preview_state()
	check(fresh_pair.host.game_state.flora.size() == 1
			and int(fresh_state.visible_growth_count) == 1 and int(fresh_state.seed_stock) == 2,
		"fresh reconstruction creates exactly the saved growth without reissuing a seed")
	check(fresh_pair.chunk._pad_visuals.size() == 3
			and fresh_pair.chunk._flora_visuals.size() == 1,
		"fresh reconstruction keeps a fixed three-slot presenter topology")

	# Complete all three pads, then grow them to flourishing so a completed save exercises both the
	# garden ownership record and the independent GameState.flora lifecycle.
	_apply_capture(host, chunk, first_capture)
	for pad_index in [1, 2]:
		check(_take_and_plant(host, chunk, pad_index) != "",
			"remaining authored pad %d accepts one remaining crate seed" % (pad_index + 1))
	for cycle in range(3):
		host.scheduler.advance_ticks(76.0)
		chunk.headless_process(0.0)
		for flora_id_v in chunk._pad_flora_ids:
			var flora_id := str(flora_id_v)
			if flora_id == "" or gs.get_flora_stage(flora_id) >= GameState.FLORA_STAGES.size() - 1:
				continue
			_trigger_garden_source(
				gs, chunk._tend_interactables[
					chunk._pad_flora_ids.find(flora_id)], "peris")
		chunk.headless_process(0.0)
	var completed := _capture(host)
	var tend_counts_monotonic := true
	for pad_index in range(chunk._tend_interactables.size()):
		var action_id: String = chunk._tend_action_id(pad_index)
		tend_counts_monotonic = tend_counts_monotonic \
			and _source_trigger_count(gs, chunk._tend_interactables[pad_index]) == 2 \
			and int((chunk.get_preview_state().source_committed_counts as Dictionary).get(
				action_id, -1)) == 2
	check(tend_counts_monotonic,
		"daily tend one-shots rearm while their source counts remain monotonic")
	check(int(chunk.get_preview_state().seed_stock) == 0 and _flora_seed_item_count(gs) == 0,
		"completed garden has exhausted—not duplicated—its three-seed stock")

	var completed_pair := await _boot_garden()
	_apply_capture(completed_pair.host, completed_pair.chunk, completed)
	var completed_state: Dictionary = completed_pair.chunk.get_preview_state()
	var all_flourishing := true
	for stage_v in completed_state.stages.values():
		all_flourishing = all_flourishing and int(stage_v) == GameState.FLORA_STAGES.size() - 1
	check(completed_pair.host.game_state.flora.size() == 3
			and int(completed_state.visible_growth_count) == 3 and all_flourishing,
		"completed restore reconstructs all three flourishing GameState growths")
	check(not completed_pair.chunk._seed_crate_interactable.is_interaction_enabled()
			and _enabled_count(completed_pair.chunk._pad_interactables) == 0
			and _enabled_count(completed_pair.chunk._tend_interactables) == 0,
		"completed restore derives exhausted crate, occupied pads, and finished tending affordances")

	# A snapshot with no garden authority is explicitly the pre-interaction construction baseline.
	var absent := baseline.duplicate(true)
	(absent.game_state.world_state as Dictionary).erase(chunk.flora_garden_authority_key())
	_apply_capture(host, chunk, absent)
	check(not host.game_state.world_state.has(chunk.flora_garden_authority_key())
			and _baseline_truth(chunk),
		"absent authority retracts later solved flags without manufacturing a replacement save event")
	_trigger_garden_source(gs, chunk._seed_crate_interactable, "peris")
	check(int(chunk.get_preview_state().seed_stock) == 2
			and int(chunk.get_preview_state().available_source_seed_count) == 2
			and _carried_garden_seed_count(gs, chunk, "peris") == 1
			and _flora_seed_item_count(gs) == 3,
		"the absent-record baseline can issue one seed exactly once after reconstruction")

	await _discard(host)
	await _discard(fresh_pair.host)
	await _discard(completed_pair.host)


func _boot_garden() -> Dictionary:
	var host = HostScript.new()
	host.setup()
	root.add_child(host)
	var chunk = FloraGardenScript.new()
	chunk.attach_chunk_host(host, "flora_garden")
	host.register_party(chunk.get_spawn_positions())
	host.add_child(chunk)
	await process_frame
	await process_frame
	host.grid = GridWorld.from_data(chunk.get_grid_data())
	host.game_state.grid = host.grid
	chunk.reset_preview_state()
	chunk.headless_process(0.0)
	return {"host": host, "chunk": chunk}


func _take_and_plant(host, chunk, pad_index: int) -> String:
	var gs = host.game_state
	gs.snap_character_to("peris", chunk.SEED_CRATE_POS + Vector3(0.2, 0.0, 0.0))
	_trigger_garden_source(gs, chunk._seed_crate_interactable, "peris")
	gs.snap_character_to("peris", chunk.PAD_POSITIONS[pad_index] + Vector3(0.2, 0.0, 0.0))
	_trigger_garden_source(gs, chunk._pad_interactables[pad_index], "peris")
	chunk.headless_process(0.0)
	return str(chunk._pad_flora_ids[pad_index])


func _trigger_garden_source(gs, source: Node, actor: String) -> bool:
	if gs == null or not is_instance_valid(source) or not gs.characters.has(actor):
		return false
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return false
	var source_position: Vector3 = gs.get_interactable(data_id).get(
		"position", Vector3.INF)
	if not source_position.is_finite():
		return false
	gs.command_stop(actor)
	gs.snap_character_to(actor, source_position)
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _trigger_source_without_reposition(source: Node, actor: String) -> bool:
	if not is_instance_valid(source):
		return false
	source.set("active_character", actor)
	return bool(source.call("_trigger", false))


func _source_trigger_count(gs, source: Node) -> int:
	if gs == null or not is_instance_valid(source):
		return -1
	var data_id := str(source.get("data_id"))
	if data_id == "" or not gs.has_interactable(data_id):
		return -1
	return int(gs.get_interactable(data_id).get("trigger_count", -1))


func _baseline_truth(chunk) -> bool:
	var state: Dictionary = chunk.get_preview_state()
	return int(state.get("seed_stock", -1)) == chunk.INITIAL_SEED_STOCK \
		and int(state.get("source_seed_count", -1)) == chunk.INITIAL_SEED_STOCK \
		and int(state.get("available_source_seed_count", -1)) == chunk.INITIAL_SEED_STOCK \
		and int(state.get("issued_seed_count", -1)) == 0 \
		and int(state.get("visible_growth_count", -1)) == 0 \
		and _enabled_count(chunk._pad_interactables) == 0 \
		and _enabled_count(chunk._tend_interactables) == 0 \
		and chunk._seed_crate_interactable.is_interaction_enabled()


func _flora_seed_item_count(gs) -> int:
	var count := 0
	for item_v in gs.items.values():
		if str((item_v as Dictionary).get("type", "")) == "flora_seed":
			count += 1
	return count


func _carried_garden_seed_count(gs, chunk, char_id: String) -> int:
	var count := 0
	for item_id_v in gs.get_hand_items(char_id) + gs.get_internal_items(char_id):
		if chunk._is_garden_seed(str(item_id_v)):
			count += 1
	return count


func _enabled_count(interactables: Array) -> int:
	var count := 0
	for interactable in interactables:
		if interactable != null and interactable.is_interaction_enabled():
			count += 1
	return count


func _capture(host) -> Dictionary:
	return _json_round_trip({
		"scheduler": host.scheduler.serialize(),
		"game_state": host.game_state.serialize(),
	})


func _garden_record(snapshot: Dictionary, chunk) -> Dictionary:
	var gs: Dictionary = snapshot.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	var raw: Variant = world.get(chunk.flora_garden_authority_key(), {})
	return raw as Dictionary if raw is Dictionary else {}


func _set_garden_record(snapshot: Dictionary, chunk, record: Dictionary) -> void:
	var gs: Dictionary = snapshot.get("game_state", {})
	var world: Dictionary = gs.get("world_state", {})
	world[chunk.flora_garden_authority_key()] = record
	gs["world_state"] = world
	snapshot["game_state"] = gs


func _apply_capture(host, chunk, capture: Dictionary) -> void:
	host.scheduler.clear()
	host.scheduler.deserialize(capture.get("scheduler", {}))
	host.game_state.deserialize(capture.get("game_state", {}))
	chunk.on_game_state_snapshot_restored()
	var pending: Array[Node] = []
	for child in chunk.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node.has_method("on_game_state_snapshot_restored"):
			node.call("on_game_state_snapshot_restored")
	chunk.headless_process(0.0)


func _json_round_trip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	return parsed as Dictionary if parsed is Dictionary else {}


func _discard(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if "scheduler" in node and node.get("scheduler") != null:
			node.get("scheduler").clear()
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
