extends SceneTree

## Gallery concealment must be world truth, not selection truth: each body gets only the cover it is
## physically inside. Saved positions reconstruct the tiers even when serialized stat mirrors are stale.

const PreviewScene := preload("res://scenes/fragments/fragment_preview.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source = await _spawn_gallery()
	if source == null:
		_finish()
		return
	var chunk = source._active_chunk
	var gs: GameState = source._game_state
	var exposed: Vector3 = chunk.HIDE_PADS[0]["pos"]
	var medium: Vector3 = chunk.HIDE_PADS[1]["pos"]
	var full: Vector3 = chunk.HIDE_PADS[2]["pos"]
	var authority_key: String = str(chunk.gallery_authority_key())
	var initial_authority: Dictionary = gs.get_world_state(authority_key, {})
	check(int(initial_authority.get("version", 0)) == chunk.GALLERY_AUTHORITY_VERSION
			and str(initial_authority.get("phase", "")) == chunk.GALLERY_PHASE_TOURING,
		"Gallery boots with versioned causal-survey authority")
	var baseline_snapshot := _json_round_trip(source.build_save_snapshot())
	var absent_snapshot := _json_round_trip(baseline_snapshot)
	_erase_authority(absent_snapshot, authority_key)

	check(chunk.find_child("GalleryScarpet", true, false) is Scarpet
			and chunk.find_child("GalleryCapbage", true, false) is Capbage,
		"SCARPET and CAPBAGE exhibits are their reusable gameplay objects, not effect-only plinths")
	check(chunk.find_child("GalleryFloraScarpet", true, false) is Scarpet
			and chunk.find_child("GalleryFloraCapbage", true, false) is Capbage
			and chunk.find_child("GalleryFloraFlure", true, false) is Flure
			and chunk.find_child("GalleryFloraHushbloom", true, false) is Hushbloom,
		"flora bay contains four shipped target-owned mechanics, not six recoloured copies")
	check(int(chunk.get_preview_state().get("flora_count", -1)) == 4
			and not chunk.FLORA_ORDER.has("seefern")
			and not chunk.FLORA_ORDER.has("gasafoetida"),
		"unbuilt Seefern/Gasafoetida verbs are honestly omitted instead of impersonated")

	_place_party(source, {"aster": exposed, "peris": medium, "endo": full})
	source.headless_set_selected_characters(["peris"])
	chunk.headless_process(0.0)
	check(_tiers(gs) == {"aster": GameState.CONCEAL_NONE,
			"peris": GameState.CONCEAL_MEDIUM, "endo": GameState.CONCEAL_FULL},
		"three simultaneous bodies receive three independent spatial concealment tiers")
	check(int(chunk.get_preview_state().get("active_tier", -1)) == GameState.CONCEAL_MEDIUM
			and str(chunk.get_preview_state().get("on_pad", "")) == "SCARPET",
		"active readout describes selected Peris's physical cover")

	source.headless_set_selected_characters(["aster"])
	chunk.headless_process(0.0)
	check(_tiers(gs) == {"aster": GameState.CONCEAL_NONE,
			"peris": GameState.CONCEAL_MEDIUM, "endo": GameState.CONCEAL_FULL},
		"switching portraits changes no character's world concealment")
	check(int(chunk.get_preview_state().get("active_tier", -1)) == GameState.CONCEAL_NONE
			and str(chunk.get_preview_state().get("on_pad", "")) == "EXPOSED",
		"active readout follows Aster without concealing off-character bodies")

	source.headless_set_selected_characters(["endo"])
	chunk.headless_process(0.0)
	check(_tiers(gs) == {"aster": GameState.CONCEAL_NONE,
			"peris": GameState.CONCEAL_MEDIUM, "endo": GameState.CONCEAL_FULL}
			and int(chunk.get_preview_state().get("active_tier", -1)) == GameState.CONCEAL_FULL,
		"selecting Endo reports his CAPBAGE while leaving Aster exposed and Peris medium-hidden")

	# Moving one unselected body changes only that body; no active-character branch grants party immunity.
	source.headless_set_character_position("peris", Vector3(25.0, 0.5, -6.0))
	chunk.headless_process(0.0)
	check(_tiers(gs) == {"aster": GameState.CONCEAL_NONE,
			"peris": GameState.CONCEAL_NONE, "endo": GameState.CONCEAL_FULL},
		"an unselected member loses cover immediately on physically leaving it")
	source.headless_set_character_position("peris", medium)
	chunk.headless_process(0.0)

	var spatial_snapshot := _json_round_trip(source.build_save_snapshot())
	_place_party(source, {
		"aster": Vector3(4.0, 0.5, 0.0),
		"peris": Vector3(5.0, 0.5, 0.0),
		"endo": Vector3(6.0, 0.5, 0.0),
	})
	chunk.headless_process(0.0)
	check(_tiers(gs) == {"aster": 0, "peris": 0, "endo": 0},
		"fixture creates a later all-exposed presenter before rollback")

	source.apply_save_snapshot(spatial_snapshot)
	var events_before_repeat := _event_count(gs)
	chunk.on_game_state_snapshot_restored()
	check(_tiers(gs) == {"aster": 0, "peris": 1, "endo": 2},
		"same-presenter load derives all concealment from restored body positions")
	check(_event_count(gs) == events_before_repeat,
		"repeated concealment attachment emits no synthetic gameplay command")

	var fresh = await _spawn_gallery()
	if fresh != null:
		fresh.apply_save_snapshot(spatial_snapshot)
		fresh._active_chunk.on_game_state_snapshot_restored()
		check(_tiers(fresh._game_state) == {"aster": 0, "peris": 1, "endo": 2},
			"fresh presenter derives the same three tiers from the same saved positions")
		await _discard(fresh)

	# Stats are mirrors, not authority. Forge the opposite concealment values into an otherwise valid
	# save; the attachment seam must immediately retract them to the physical predicates.
	var stale_stats_snapshot := _json_round_trip(spatial_snapshot)
	_set_saved_tier(stale_stats_snapshot, "aster", GameState.CONCEAL_FULL)
	_set_saved_tier(stale_stats_snapshot, "peris", GameState.CONCEAL_NONE)
	_set_saved_tier(stale_stats_snapshot, "endo", GameState.CONCEAL_NONE)
	var stale = await _spawn_gallery()
	if stale != null:
		stale.apply_save_snapshot(stale_stats_snapshot)
		stale._active_chunk.on_game_state_snapshot_restored()
		check(_tiers(stale._game_state) == {"aster": 0, "peris": 1, "endo": 2},
			"restore rejects stale/forged concealment mirrors in favor of saved spatial truth")
		await _discard(stale)

	# An off-character exposed body remains a legal enemy target while the selected member is safe.
	# Use a clean sentry FSM: the rollback fixture above may correctly restore a later alert state.
	var acquisition = await _spawn_gallery()
	if acquisition != null:
		var acquisition_chunk = acquisition._active_chunk
		_place_party(acquisition,
			{"aster": exposed, "peris": full, "endo": Vector3(3.0, 0.5, 0.0)})
		acquisition.headless_set_selected_characters(["endo"])
		acquisition_chunk.headless_process(0.0)
		var demo = acquisition_chunk.find_child("GalleryDemoSentry", true, false)
		check(demo != null and not demo.engage_target("peris"),
			"CAPBAGE physically blocks enemy acquisition even when its occupant is unselected")
		check(demo != null and demo.engage_target("aster")
				and str(demo._current_target_id) == "aster",
			"enemy can acquire an exposed off-character; portrait selection grants no immunity")
		await _discard(acquisition)

	# A clean Gallery cannot be cleared by crossing the threshold, even if every body is teleported
	# there. The causal survey is the gate; the exit is the final regroup condition.
	var survey = await _spawn_gallery()
	if survey != null:
		var survey_chunk = survey._active_chunk
		var survey_gs: GameState = survey._game_state
		var survey_key := str(survey_chunk.gallery_authority_key())
		survey.headless_set_character_position("aster", Vector3(survey_chunk.EXIT_X + 1.0, 0.5, 0.0))
		survey_chunk.headless_process(0.0)
		check(not bool(survey_chunk.get_preview_state().get("complete", true)),
			"one body at the exit cannot clear an unsurveyed Gallery")
		for cid in survey_chunk.PARTY_IDS:
			survey.headless_set_character_position(cid, Vector3(survey_chunk.EXIT_X + 1.0, 0.5, 0.0))
		survey_chunk.headless_process(0.0)
		check(not bool(survey_chunk.get_preview_state().get("complete", true))
				and int(survey_chunk.get_preview_state().get("evidence_count", -1)) == 0,
			"the whole party at the exit still cannot spoof missing physical responses")

		survey.apply_save_snapshot(baseline_snapshot)
		survey_chunk.on_game_state_snapshot_restored()
		var survey_anchors: Dictionary = survey_chunk.get_preview_anchors()

		# Drive the actual verbs through ordinary movement and the semantic interaction coordinator.
		check(_ordinary_move_until_evidence(survey, "peris",
				survey_anchors["pad_medium"], "hide_scarpet_occupied", 8.0),
			"ordinary movement into the hiding Scarpet records its medium-cover response")
		check(_ordinary_interact_until_evidence(survey, "peris",
				"hide_capbage", "hide_capbage_tucked", 10.0),
			"ordinary Capbage interaction records a physical full-hide tuck")
		check(_ordinary_move_until_evidence(survey, "peris",
				survey_anchors["pad_exposed"], "hide_exposed_spotted", 14.0),
			"ordinary movement onto EXPOSED lets the real pacing sentry spot the body")
		survey_chunk._demo_enemy.re_post(Vector3(16.0, 0.5, survey_chunk.SENTRY_PACE_Z))
		survey.headless_set_character_position("peris", survey_anchors["entry"])

		check(_ordinary_move_until_evidence(survey, "aster",
				survey_anchors["standard_pen"], "enemy_standard_engaged", 14.0),
			"ordinary entry wakes the real standard-sentry zone")
		survey_chunk._standard_enemy.re_post(survey_chunk.STANDARD_ANCHOR)
		survey.headless_set_character_position("aster", survey_anchors["entry"])
		check(_ordinary_move_until_evidence(survey, "endo",
				survey_anchors["chain_pen"], "enemy_chain_engaged", 18.0),
			"ordinary entry wakes the real chain-seam zone")
		survey_chunk._chain_enemy.re_post(survey_chunk.CHAIN_ANCHOR)
		survey.headless_set_character_position("endo", survey_anchors["entry"])

		check(_ordinary_move_until_evidence(survey, "peris",
				survey_anchors["flora_scarpet"], "flora_scarpet_occupied", 14.0),
			"ordinary movement tries the flora-bay Scarpet object")
		check(survey_gs.get_character_concealment("peris") == GameState.CONCEAL_MEDIUM,
			"flora-bay Scarpet applies its real medium concealment")
		check(_ordinary_interact_until_evidence(survey, "peris",
				"flora_capbage", "flora_capbage_tucked", 10.0),
			"ordinary interaction tries the flora-bay Capbage object")
		check(survey_gs.get_character_concealment("peris") == GameState.CONCEAL_FULL,
			"flora-bay Capbage applies its real full concealment")
		check(_ordinary_interact_until_evidence(survey, "peris",
				"flora_flure", "flora_flure_lured", 12.0),
			"Peris lights the real Flure and its target-owned effect moves the response sentry")
		check(_ordinary_move_until_evidence(survey, "peris",
				survey_anchors["flora_hushbloom"], "flora_hushbloom_stunned", 12.0),
			"crossing the real Hushbloom stuns the same response sentry")

		var surveyed_state: Dictionary = survey_chunk.get_preview_state()
		check(int(surveyed_state.get("evidence_count", -1))
				== int(surveyed_state.get("required_evidence_count", -2))
				and (surveyed_state.get("remaining_evidence", []) as Array).is_empty()
				and not bool(surveyed_state.get("complete", true)),
			"all nine causal responses persist while completion still waits for the party")
		var surveyed_snapshot := _json_round_trip(survey.build_save_snapshot())

		# Same-presenter rollback and replay must retract/reconstruct every record without invoking
		# interactables or manufacturing events.
		survey.apply_save_snapshot(baseline_snapshot)
		survey_chunk.on_game_state_snapshot_restored()
		check(int(survey_chunk.get_preview_state().get("evidence_count", -1)) == 0,
			"same-presenter rollback retracts later survey evidence")
		var events_before_evidence_restore := _event_count(survey_gs)
		survey.apply_save_snapshot(surveyed_snapshot)
		survey_chunk.on_game_state_snapshot_restored()
		check(int(survey_chunk.get_preview_state().get("evidence_count", -1))
				== survey_chunk.REQUIRED_EVIDENCE.size(),
			"same-presenter load restores exact source evidence, including flora-owned effects")
		check(_event_count(survey_gs) == events_before_evidence_restore,
			"survey attachment emits no synthetic gameplay interaction")

		var fresh_surveyed = await _spawn_gallery()
		if fresh_surveyed != null:
			fresh_surveyed.apply_save_snapshot(surveyed_snapshot)
			fresh_surveyed._active_chunk.on_game_state_snapshot_restored()
			check(int(fresh_surveyed._active_chunk.get_preview_state().get("evidence_count", -1))
					== fresh_surveyed._active_chunk.REQUIRED_EVIDENCE.size()
					and not bool(fresh_surveyed._active_chunk.get_preview_state().get("complete", true)),
				"fresh presenter reconstructs surveyed-but-not-regrouped truth")
			await _discard(fresh_surveyed)

		# Render frames cannot commit even when all three saved bodies are beyond the threshold.
		for cid in survey_chunk.PARTY_IDS:
			survey.headless_set_character_position(cid,
				Vector3(survey_chunk.EXIT_X + 1.0, 0.5, float(survey_chunk.PARTY_IDS.find(cid))))
		var authority_before_render: Dictionary = survey_gs.get_world_state(survey_key, {}).duplicate(true)
		for _frame in range(240):
			survey_chunk._process(1.0 / 60.0)
		check(not bool(survey_chunk.get_preview_state().get("complete", true))
				and survey_gs.get_world_state(survey_key, {}) == authority_before_render,
			"render frames cannot commit a surveyed three-body exit")

		# Put each body just before the threshold, then cross using ordinary GameState movement.
		for i in range(survey_chunk.PARTY_IDS.size()):
			survey.headless_set_character_position(survey_chunk.PARTY_IDS[i],
				Vector3(survey_chunk.EXIT_X - 1.0, 0.5, float(i)))
		check(_ordinary_move_to(survey, "aster", Vector3(survey_chunk.EXIT_X + 1.0, 0.5, 0.0), 4.0)
				and not bool(survey_chunk.get_preview_state().get("complete", true)),
			"Aster crossing alone cannot complete a fully surveyed Gallery")
		check(_ordinary_move_to(survey, "peris", Vector3(survey_chunk.EXIT_X + 1.0, 0.5, 1.0), 4.0)
				and not bool(survey_chunk.get_preview_state().get("complete", true)),
			"two of three bodies across still cannot complete")
		check(_ordinary_move_to(survey, "endo", Vector3(survey_chunk.EXIT_X + 1.0, 0.5, 2.0), 4.0)
				and bool(survey_chunk.get_preview_state().get("complete", false)),
			"the final ordinary arrival commits only after every response and all three bodies")

		var completed_state: Dictionary = survey_chunk.get_preview_state()
		var completed_authority: Dictionary = survey_gs.get_world_state(survey_key, {})
		check((completed_state.get("completion_party", []) as Array) == survey_chunk.PARTY_IDS
				and str((completed_authority.get("completion", {}) as Dictionary).get(
					"contract", "")) == survey_chunk.GALLERY_COMPLETION_CONTRACT,
			"completion saves the exact required party and their threshold positions")
		var events_after_completion := _event_count(survey_gs)
		for _repeat in range(10):
			survey_chunk.headless_process(0.0)
		check(_event_count(survey_gs) == events_after_completion,
			"repeated exit checks cannot recommit completion")
		var completed_snapshot := _json_round_trip(survey.build_save_snapshot())

		survey.apply_save_snapshot(baseline_snapshot)
		var events_before_phase_repeat := _event_count(survey_gs)
		survey_chunk.on_game_state_snapshot_restored()
		check(not bool(survey_chunk.get_preview_state().get("complete", true))
				and int(survey_chunk.get_preview_state().get("evidence_count", -1)) == 0
				and str(survey._current_step) == "showcase_touring",
			"same-presenter rollback retracts completion, evidence, and completed UI step")
		check(_event_count(survey_gs) == events_before_phase_repeat,
			"repeated Gallery phase attachment is idempotent")

		var fresh_completed = await _spawn_gallery()
		if fresh_completed != null:
			fresh_completed.apply_save_snapshot(completed_snapshot)
			fresh_completed._active_chunk.on_game_state_snapshot_restored()
			var fresh_completed_state: Dictionary = fresh_completed._active_chunk.get_preview_state()
			check(bool(fresh_completed_state.get("complete", false))
					and (fresh_completed_state.get("completion_party", []) as Array)
						== fresh_completed._active_chunk.PARTY_IDS
					and str(fresh_completed._current_step) == "showcase_complete",
				"fresh presenter reconstructs completed causal survey and regroup truth")
			await _discard(fresh_completed)

		# A forged aggregate/checklist count has no authority; only whitelisted source records do.
		var forged_snapshot := _json_round_trip(baseline_snapshot)
		_set_authority(forged_snapshot, survey_key, {
			"version": survey_chunk.GALLERY_AUTHORITY_VERSION,
			"authority_id": survey_key,
			"phase": survey_chunk.GALLERY_PHASE_COMPLETE,
			"survey_count": survey_chunk.REQUIRED_EVIDENCE.size(),
			"evidence": {},
			"completion": {},
		})
		var forged = await _spawn_gallery()
		if forged != null:
			forged.apply_save_snapshot(forged_snapshot)
			forged._active_chunk.on_game_state_snapshot_restored()
			check(not bool(forged._active_chunk.get_preview_state().get("complete", true))
					and int(forged._active_chunk.get_preview_state().get("evidence_count", -1)) == 0,
				"forged survey counters cannot stand in for target-owned evidence")
			var legacy_false_completion := _json_round_trip(baseline_snapshot)
			_set_authority(legacy_false_completion, survey_key, {
				"version": 1,
				"authority_id": survey_key,
				"phase": survey_chunk.GALLERY_PHASE_COMPLETE,
				"exit_reached_by": "peris",
				"completion_tick": 0.0,
			})
			forged.apply_save_snapshot(legacy_false_completion)
			forged._active_chunk.on_game_state_snapshot_restored()
			check(not bool(forged._active_chunk.get_preview_state().get("complete", true)),
				"legacy any-one-body completion records are deliberately invalidated")
			await _discard(forged)

		# A snapshot predating the Gallery record restores construction truth without publishing a
		# replacement key or retaining future callbacks.
		survey.apply_save_snapshot(absent_snapshot)
		survey_chunk.on_game_state_snapshot_restored()
		check(not bool(survey_chunk.get_preview_state().get("complete", true))
				and str(survey_chunk.get_preview_state().get("phase", ""))
					== survey_chunk.GALLERY_PHASE_TOURING
				and str(survey._current_step) == "showcase_touring",
			"missing Gallery authority restores construction-baseline touring truth")
		check(survey_gs.get_world_state(survey_key, null) == null,
			"absence remains absent during Gallery presenter attachment")
		survey.headless_advance(4.0, 0.25)
		check(not bool(survey_chunk.get_preview_state().get("complete", true))
				and survey_gs.get_world_state(survey_key, null) == null,
			"advancing after absence rollback cannot grant discarded survey outcomes")
		await _discard(survey)

	await _discard(source)
	_finish()


func _place_party(preview: Node, positions: Dictionary) -> void:
	for char_id_v in positions.keys():
		preview.headless_set_character_position(str(char_id_v), positions[char_id_v])


func _ordinary_move_until_evidence(
		preview: Node,
		char_id: String,
		target: Vector3,
		mechanic_id: String,
		timeout: float
	) -> bool:
	preview.headless_select_character(char_id)
	if not preview.headless_move_character(char_id, target, true):
		return false
	var elapsed := 0.0
	while elapsed < timeout:
		preview.headless_advance(0.1, 0.1)
		var evidence: Dictionary = preview._active_chunk.get_preview_state().get("evidence", {})
		if evidence.has(mechanic_id):
			return true
		elapsed += 0.1
	return false


func _ordinary_interact_until_evidence(
		preview: Node,
		char_id: String,
		target_id: String,
		mechanic_id: String,
		timeout: float
	) -> bool:
	preview.headless_select_character(char_id)
	# Push the newly active body into every interactable exactly as an ordinary frame does.
	preview.headless_advance(0.1, 0.1)
	var event := InputEventAction.new()
	event.action = StringName("qa_world_interaction/%s" % target_id)
	event.pressed = true
	preview._input(event)
	var elapsed := 0.0
	while elapsed < timeout:
		preview.headless_advance(0.1, 0.1)
		var evidence: Dictionary = preview._active_chunk.get_preview_state().get("evidence", {})
		if evidence.has(mechanic_id):
			return true
		elapsed += 0.1
	return false


func _ordinary_move_to(
		preview: Node,
		char_id: String,
		target: Vector3,
		timeout: float
	) -> bool:
	preview.headless_select_character(char_id)
	if not preview.headless_move_character(char_id, target, false):
		return false
	var elapsed := 0.0
	while elapsed < timeout:
		preview.headless_advance(0.1, 0.1)
		var position: Vector3 = preview._game_state.get_position(char_id)
		if Vector2(position.x - target.x, position.z - target.z).length() <= 0.12:
			return true
		elapsed += 0.1
	return false


func _tiers(gs: GameState) -> Dictionary:
	return {
		"aster": gs.get_character_concealment("aster"),
		"peris": gs.get_character_concealment("peris"),
		"endo": gs.get_character_concealment("endo"),
	}


func _set_saved_tier(snapshot: Dictionary, char_id: String, tier: int) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var characters: Dictionary = game_state.get("characters", {})
	var character: Dictionary = characters.get(char_id, {})
	var stats: Dictionary = character.get("stats", {})
	stats["concealment"] = tier
	character["stats"] = stats
	characters[char_id] = character
	game_state["characters"] = characters
	snapshot["game_state"] = game_state


func _erase_authority(snapshot: Dictionary, key: String) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	world_state.erase(key)
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


func _set_authority(snapshot: Dictionary, key: String, value: Dictionary) -> void:
	var game_state: Dictionary = snapshot.get("game_state", {})
	var world_state: Dictionary = game_state.get("world_state", {})
	world_state[key] = value.duplicate(true)
	game_state["world_state"] = world_state
	snapshot["game_state"] = game_state


func _spawn_gallery():
	var preview = PreviewScene.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "showcase_gallery"
	preview.suppress_scene_change = true
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	check(preview._active_chunk != null, "Showcase Gallery boots its production chunk")
	if preview._active_chunk == null:
		await _discard(preview)
		return null
	return preview


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
	print("SHOWCASE GALLERY SPATIAL CONCEALMENT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
