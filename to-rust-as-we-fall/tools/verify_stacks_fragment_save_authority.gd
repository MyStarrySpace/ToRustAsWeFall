extends SceneTree

## The Stacks comparison used to live only in scene-local booleans. A save could therefore keep
## later bank/shelter presenters while losing the evidence that made them legal (or a fresh scene
## could forget solved evidence entirely). This verifies that the comparison record is authority,
## while interactable availability and preview steps are reconstructible projections.

const PreviewScene := preload("res://scenes/fragments/fragment_preview.tscn")

var _checks := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	EventLog.print_events = false
	var source = await _spawn_stacks_preview()
	if source == null:
		_finish()
		return
	var chunk = source._active_chunk
	var gs: GameState = source._game_state
	var authority_key: String = str(chunk.stacks_authority_key())

	var initial_authority: Dictionary = gs.get_world_state(authority_key, {})
	check(int(initial_authority.get("version", 0)) == chunk.STACKS_AUTHORITY_VERSION
			and str(initial_authority.get("authority_id", "")) == authority_key,
		"Stacks boots with a versioned comparison authority record")
	check(chunk._terminal_interactable.is_interaction_enabled()
			and _bank_enabled_count(chunk) == 0
			and not chunk._shelter_interactable.is_interaction_enabled(),
		"baseline presenter exposes the cleaned intake and keeps later consequences locked")
	check(str(chunk._bank_readout_labels["bank_a"].text).contains("READ INTAKE FIRST")
			and str(chunk._bank_readout_labels["bank_b"].text).contains("READ INTAKE FIRST")
			and str(chunk._bank_readout_labels["bank_c"].text).contains("READ INTAKE FIRST"),
		"baseline banks reveal neither evidence nor an answer before the GDD-required report")
	var terminal_target: Node = chunk.get_playthrough_interaction_target("cleaned_terminal")
	var bank_a_target: Node = chunk.get_playthrough_interaction_target("bank_a")
	var bank_b_target: Node = chunk.get_playthrough_interaction_target("bank_b")
	var bank_c_target: Node = chunk.get_playthrough_interaction_target("bank_c")
	var shelter_target: Node = chunk.get_playthrough_interaction_target("stacks_shelter_rest")
	check(terminal_target == chunk._terminal_interactable
			and bank_a_target == chunk._bank_interactables["bank_a"]
			and bank_b_target == chunk._bank_interactables["bank_b"]
			and bank_c_target == chunk._bank_interactables["bank_c"]
			and shelter_target == chunk._shelter_interactable,
		"Stacks exposes stable semantic ids for its canonical report, banks, and shelter")

	var absent_snapshot := _json_round_trip(source.build_save_snapshot())
	_erase_authority(absent_snapshot, authority_key)

	# Retired story helpers and direct callbacks cannot stand in for the world controls.
	var baseline_state: Dictionary = chunk.get_preview_state().duplicate(true)
	check(not bool(chunk.trigger_stacks_bank("bank_b"))
			and not bool(chunk.trigger_stacks_shelter_rest())
			and chunk.get_preview_state() == baseline_state,
		"legacy Stacks helper calls are inert compatibility probes")
	bank_a_target.active_character = "peris"
	source.headless_set_character_position("peris", chunk.BANK_POSITIONS["bank_a"])
	check(not bool(bank_a_target.call("_trigger", false))
			and not bool(bank_a_target.get("_used"))
			and chunk.get_preview_state() == baseline_state,
		"a physically near wrong actor cannot consume or sample an Aster-only bank")
	bank_a_target.active_character = "aster"
	source.headless_set_character_position("aster", chunk.SPAWNS["aster"])
	check(not bool(bank_a_target.call("_trigger", false))
			and not bool(bank_a_target.get("_used"))
			and chunk.get_preview_state() == baseline_state,
		"a remote Aster cannot invoke a bank through the Interactable API")
	source.headless_set_character_position("aster", chunk.BANK_POSITIONS["bank_a"])
	chunk._on_bank_interacted(bank_a_target, "bank_a")
	check(chunk.get_preview_state() == baseline_state,
		"calling the bank callback directly cannot manufacture an accepted trigger receipt")
	terminal_target.active_character = "aster"
	source.headless_set_character_position("aster", chunk.SPAWNS["aster"])
	chunk._on_terminal_interacted(terminal_target)
	check(chunk.get_preview_state() == baseline_state,
		"calling the cleaned-report callback directly cannot manufacture its trigger receipt")
	check(await _ordinary_terminal_interaction(source),
		"ordinary movement and the canonical intake control expose the cleaned report")
	check(bool(chunk.get_preview_state().get("terminal_seen", false))
			and not chunk._terminal_interactable.is_interaction_enabled()
			and _bank_enabled_count(chunk) == 3,
		"the accepted report receipt opens the quiet bank comparison")
	check(str(chunk._bank_readout_labels["bank_a"].text).contains("NO PROBE")
			and str(chunk._bank_readout_labels["bank_b"].text).contains("NO PROBE")
			and str(chunk._bank_readout_labels["bank_c"].text).contains("NO PROBE"),
		"all three policy consoles begin neutral after the report frames the question")

	# Sampling and committing are distinct actions, but there is no hidden 3/3 checklist. The player
	# chooses when the model is strong enough; a wrong prediction must falsify itself specifically.
	var ordinary_comparison_results: Array[bool] = []
	ordinary_comparison_results.append(
		await _ordinary_bank_interaction(source, "bank_b", 1))
	ordinary_comparison_results.append(
		await _ordinary_bank_interaction(source, "bank_a", 2))
	ordinary_comparison_results.append(
		await _ordinary_bank_interaction(source, "bank_c", 3))
	ordinary_comparison_results.append(
		await _ordinary_bank_interaction(source, "bank_a", 4))
	check(not ordinary_comparison_results.has(false),
		"ordinary movement and canonical bank interactions drive the comparison")
	var compared: Dictionary = chunk.get_preview_state()
	check(_sorted(compared.get("bank_samples", [])) == ["bank_a", "bank_b", "bank_c"]
			and not bool(compared.get("bank_resolved", true))
			and int(compared.get("bank_attempts", 0)) == 4
			and int(compared.get("failed_commits", 0)) == 1
			and str(compared.get("last_commit", "")) == "bank_a",
		"a wrong sampled-bank commit stays retryable and records the falsified prediction")
	check(_bank_enabled_count(chunk) == 3
			and not chunk._shelter_interactable.is_interaction_enabled(),
		"comparison state keeps the banks actionable for the evidenced BANK B revisit")
	var comparison_snapshot := _json_round_trip(source.build_save_snapshot())

	check(await _ordinary_bank_interaction(source, "bank_b", 5),
		"ordinary BANK B revisit reaches the evidenced prediction")
	var resolved: Dictionary = chunk.get_preview_state()
	var resolved_authority: Dictionary = gs.get_world_state(authority_key, {})
	check(bool(resolved.get("bank_resolved", false))
			and int(resolved.get("bank_attempts", 0)) == 5
			and int(resolved.get("failed_commits", 0)) == 1
			and str(resolved.get("last_commit", "")) == "bank_b"
			and str(resolved.get("last_bank", "")) == "bank_b",
		"evidenced BANK B revisit commits the comparison outcome")
	check(bool(resolved_authority.get("bank_resolved", false))
			and _sorted(resolved_authority.get("bank_samples", []))
				== ["bank_a", "bank_b", "bank_c"],
		"the committed outcome and its evidence are saved together")
	check(_bank_enabled_count(chunk) == 0
			and chunk._shelter_interactable.is_interaction_enabled(),
		"resolved authority closes comparison controls and exposes its shelter consequence")
	var resolved_snapshot := _json_round_trip(source.build_save_snapshot())

	var before_rest_atp := _party_atp(gs)
	shelter_target.active_character = "peris"
	source.headless_set_character_position(
		"peris", chunk.SHELTER_POS + Vector3(0.4, 0.0, 0.0))
	check(not bool(shelter_target.call("_trigger", false))
			and not bool(shelter_target.get("_used")),
		"the canonical shelter rejects its valid local actor while another required body is remote")
	check(not bool(chunk.get_preview_state().get("complete", true))
			and str(chunk.get_preview_state().get("shelter_phase", "")) == "ready"
			and _party_atp(gs) == before_rest_atp,
		"a solved bank cannot remotely complete from the active portrait outside the shelter")
	_gather_stacks_party(source, chunk)
	shelter_target.active_character = "intruder"
	check(not bool(shelter_target.call("_trigger", false))
			and not bool(shelter_target.get("_used")),
		"an unregistered wrong actor cannot consume the gathered party's shelter one-shot")
	shelter_target.active_character = "aster"
	chunk._on_shelter_interacted(shelter_target)
	check(not bool(chunk.get_preview_state().get("complete", true))
			and not bool(shelter_target.get("_used")),
		"calling the shelter callback directly cannot manufacture its trigger receipt")
	source.headless_set_preview_time(1, 0.82)
	gs.set_game_clock(1, 0.82)
	var signal_seam := {"capture": {}}
	var capture_signal_seam := func(_char_id: String, stat_name: String, _value: float) -> void:
		if stat_name != "atp" or not (signal_seam["capture"] as Dictionary).is_empty():
			return
		var authority: Dictionary = gs.get_world_state(authority_key, {})
		if str(authority.get("shelter_phase", "")) == "committing":
			signal_seam["capture"] = _json_round_trip(source.build_save_snapshot())
	gs.stat_changed.connect(capture_signal_seam)
	check(await _ordinary_shelter_interaction(source),
		"ordinary movement into the canonical shelter commits the exact party rest")
	if gs.stat_changed.is_connected(capture_signal_seam):
		gs.stat_changed.disconnect(capture_signal_seam)
	var completed: Dictionary = chunk.get_preview_state()
	var committing_snapshot: Dictionary = signal_seam["capture"] as Dictionary
	check(bool(completed.get("anxiety_seen", false)) and bool(completed.get("complete", false))
			and str(completed.get("shelter_phase", "")) == "rested",
		"the gathered conscious trio commits the fragment's completed shelter state")
	check(not committing_snapshot.is_empty()
			and _party_atp(gs) == _offset_stats(before_rest_atp, -1.0),
		"Stacks publishes COMMITTING before one atomic three-member ATP transaction")
	check(_bank_enabled_count(chunk) == 0
			and not chunk._shelter_interactable.is_interaction_enabled(),
		"completed authority consumes the shelter presenter instead of leaving a dead action live")
	var completed_authority_once: Dictionary = gs.get_world_state(authority_key, {}).duplicate(true)
	var completed_atp_once := _party_atp(gs)
	shelter_target.active_character = "aster"
	check(not bool(shelter_target.call("_trigger", false))
			and gs.get_world_state(authority_key, {}) == completed_authority_once
			and _party_atp(gs) == completed_atp_once,
		"the consumed shelter one-shot cannot replay story or ATP consequences")
	var completed_snapshot := _json_round_trip(source.build_save_snapshot())

	_verify_presentation_invariance(source, chunk, completed)
	source.apply_save_snapshot(committing_snapshot)
	chunk.on_game_state_snapshot_restored()
	chunk.on_game_state_snapshot_restored()
	var paid_signal_atp := _party_atp(gs)
	check(str(chunk.get_preview_state().get("shelter_phase", "")) == "committing"
			and not bool(chunk.get_preview_state().get("complete", true)),
		"same-presenter restore preserves the paid shelter signal seam without completing in restore")
	source._scheduler.advance_ticks(0.001)
	check(bool(chunk.get_preview_state().get("complete", false))
			and _party_atp(gs) == paid_signal_atp,
		"the derived Stacks callback completes once without charging the party twice")

	var fresh_committing = await _spawn_stacks_preview()
	if fresh_committing != null:
		fresh_committing.apply_save_snapshot(committing_snapshot)
		fresh_committing._active_chunk.on_game_state_snapshot_restored()
		var fresh_paid_atp := _party_atp(fresh_committing._game_state)
		check(str(fresh_committing._active_chunk.get_preview_state().get(
				"shelter_phase", "")) == "committing",
			"a fresh presenter reconstructs the exact saved party-rest signal seam")
		fresh_committing._scheduler.advance_ticks(0.001)
		check(bool(fresh_committing._active_chunk.get_preview_state().get("complete", false))
				and _party_atp(fresh_committing._game_state) == fresh_paid_atp,
			"fresh Stacks restore finalizes once without replaying the ATP transaction")
		await _discard(fresh_committing)

	# Same-presenter rewind must remove both future booleans and future collision/interaction gates.
	source.apply_save_snapshot(comparison_snapshot)
	var events_before_repeat := _event_count(gs)
	chunk.on_game_state_snapshot_restored()
	var rewound: Dictionary = chunk.get_preview_state()
	check(not bool(rewound.get("bank_resolved", true))
			and not bool(rewound.get("anxiety_seen", true))
			and int(rewound.get("bank_attempts", 0)) == 4
			and int(rewound.get("failed_commits", 0)) == 1,
		"same-presenter rollback retracts the solved and completed future")
	check(_bank_enabled_count(chunk) == 3
			and not chunk._shelter_interactable.is_interaction_enabled(),
		"same-presenter rollback reconstructs comparison and shelter gates")
	check(_event_count(gs) == events_before_repeat,
		"repeated Stacks attachment emits no synthetic gameplay command")
	check(await _ordinary_bank_interaction(source, "bank_b", 5),
		"restored evidence remains actionable through the canonical BANK B target")
	check(bool(chunk.get_preview_state().get("bank_resolved", false)),
		"the restored comparison can be solved normally from its saved evidence")

	var fresh_comparison = await _spawn_stacks_preview()
	if fresh_comparison != null:
		fresh_comparison.apply_save_snapshot(comparison_snapshot)
		fresh_comparison._active_chunk.on_game_state_snapshot_restored()
		var fresh_state: Dictionary = fresh_comparison._active_chunk.get_preview_state()
		check(not bool(fresh_state.get("bank_resolved", true))
				and _sorted(fresh_state.get("bank_samples", []))
					== ["bank_a", "bank_b", "bank_c"],
			"fresh presenter reconstructs the all-evidence/uncommitted comparison")
		check(_bank_enabled_count(fresh_comparison._active_chunk) == 3
				and not fresh_comparison._active_chunk._shelter_interactable.is_interaction_enabled(),
			"fresh uncommitted presenter derives the same available actions")
		await _discard(fresh_comparison)

	var fresh_resolved = await _spawn_stacks_preview()
	if fresh_resolved != null:
		fresh_resolved.apply_save_snapshot(resolved_snapshot)
		fresh_resolved._active_chunk.on_game_state_snapshot_restored()
		var fresh_resolved_state: Dictionary = fresh_resolved._active_chunk.get_preview_state()
		check(bool(fresh_resolved_state.get("bank_resolved", false))
				and not bool(fresh_resolved_state.get("anxiety_seen", true)),
			"fresh presenter reconstructs a solved comparison without granting the later story beat")
		check(_bank_enabled_count(fresh_resolved._active_chunk) == 0
				and fresh_resolved._active_chunk._shelter_interactable.is_interaction_enabled(),
			"fresh solved presenter exposes exactly the pending shelter consequence")
		_gather_stacks_party(fresh_resolved, fresh_resolved._active_chunk)
		fresh_resolved.headless_set_preview_time(1, 0.82)
		fresh_resolved._game_state.set_game_clock(1, 0.82)
		check(await _ordinary_shelter_interaction(fresh_resolved),
			"fresh solved save retains its canonical pending shelter interaction")
		check(bool(fresh_resolved._active_chunk.get_preview_state().get("complete", false)),
			"fresh solved save can consume its pending consequence normally")
		await _discard(fresh_resolved)

	var fresh_completed = await _spawn_stacks_preview()
	if fresh_completed != null:
		fresh_completed.apply_save_snapshot(completed_snapshot)
		fresh_completed._active_chunk.on_game_state_snapshot_restored()
		check(bool(fresh_completed._active_chunk.get_preview_state().get("complete", false))
				and _bank_enabled_count(fresh_completed._active_chunk) == 0
				and not fresh_completed._active_chunk._shelter_interactable.is_interaction_enabled(),
			"fresh completed presenter preserves completion with every consumed control closed")
		await _discard(fresh_completed)

	var fast_reasoner = await _spawn_stacks_preview()
	if fast_reasoner != null:
		var fast_report := await _ordinary_terminal_interaction(fast_reasoner)
		var fast_probe := await _ordinary_bank_interaction(fast_reasoner, "bank_b", 1)
		var fast_commit := await _ordinary_bank_interaction(fast_reasoner, "bank_b", 2)
		check(fast_report and fast_probe and fast_commit,
			"the canonical report and BANK B target support a probe followed by a prediction")
		var fast_state: Dictionary = fast_reasoner._active_chunk.get_preview_state()
		check(bool(fast_state.get("bank_resolved", false))
				and (fast_state.get("bank_samples", []) as Array).size() == 1,
			"a supported prediction can solve early without paying a hidden three-bank checklist")
		await _discard(fast_reasoner)

	# Absence means pre-interaction truth. It must not copy the current scene's future back into the
	# snapshot or leave a scheduled/dwell callback capable of granting that future later.
	source.apply_save_snapshot(absent_snapshot)
	chunk.on_game_state_snapshot_restored()
	var absent: Dictionary = chunk.get_preview_state()
	check(_sorted(absent.get("bank_samples", [] as Array)).is_empty()
			and not bool(absent.get("terminal_seen", true))
			and not bool(absent.get("bank_resolved", true))
			and not bool(absent.get("anxiety_seen", true))
			and int(absent.get("bank_attempts", -1)) == 0
			and int(absent.get("failed_commits", -1)) == 0
			and str(absent.get("last_commit", "future")) == ""
			and str(absent.get("shelter_phase", "")) == "locked",
		"missing Stacks authority retracts every comparison fact to baseline")
	check(gs.get_world_state(authority_key, null) == null
			and chunk._terminal_interactable.is_interaction_enabled()
			and _bank_enabled_count(chunk) == 0
			and not chunk._shelter_interactable.is_interaction_enabled(),
		"absence stays absent and derives only baseline presenters")
	source.headless_advance(8.0, 0.25)
	check(not bool(chunk.get_preview_state().get("complete", true))
			and gs.get_world_state(authority_key, null) == null,
		"advancing after absence rollback cannot grant a discarded comparison outcome")

	await _discard(source)
	_finish()


func _ordinary_bank_interaction(
	preview: Node,
	bank_id: String,
	expected_attempts: int,
	timeout := 12.0
) -> bool:
	var chunk = preview._active_chunk
	var target: Node = chunk.get_playthrough_interaction_target(bank_id)
	if target == null or not target.has_signal("interaction_requested") \
			or not bool(target.call("is_interaction_enabled")):
		return false
	preview.headless_select_character(chunk.STACKS_BANK_ACTOR)
	preview.headless_advance(0.1, 0.1)
	var event := InputEventAction.new()
	event.action = StringName("qa_world_interaction/%s" % bank_id)
	event.pressed = true
	preview._input(event)
	var elapsed := 0.0
	while elapsed < timeout:
		preview.headless_advance(0.1, 0.1)
		var state: Dictionary = chunk.get_preview_state()
		if int(state.get("bank_attempts", -1)) >= expected_attempts:
			return true
		elapsed += 0.1
	return false


func _ordinary_terminal_interaction(preview: Node, timeout := 14.0) -> bool:
	var chunk = preview._active_chunk
	var target: Node = chunk.get_playthrough_interaction_target("cleaned_terminal")
	if target == null or not target.has_signal("interaction_requested") \
			or not bool(target.call("is_interaction_enabled")):
		return false
	preview.headless_select_character(chunk.STACKS_BANK_ACTOR)
	preview.headless_advance(0.1, 0.1)
	var event := InputEventAction.new()
	event.action = &"qa_world_interaction/cleaned_terminal"
	event.pressed = true
	preview._input(event)
	var elapsed := 0.0
	while elapsed < timeout:
		preview.headless_advance(0.1, 0.1)
		if bool(chunk.get_preview_state().get("terminal_seen", false)):
			return true
		elapsed += 0.1
	return false


func _ordinary_shelter_interaction(preview: Node, timeout := 8.0) -> bool:
	var chunk = preview._active_chunk
	var target: Node = chunk.get_playthrough_interaction_target("stacks_shelter_rest")
	if target == null or not target.has_signal("interaction_requested") \
			or not bool(target.call("is_interaction_enabled")):
		return false
	for char_id in chunk.STACKS_PARTY_IDS:
		preview._game_state.command_stop(char_id)
	preview.headless_select_character("aster")
	preview.headless_advance(0.1, 0.1)
	target.set("active_character", "aster")
	if not bool(target.call("_trigger", false)):
		return false
	var elapsed := 0.0
	while elapsed < timeout:
		preview.headless_advance(0.1, 0.1)
		if bool(chunk.get_preview_state().get("complete", false)):
			return true
		elapsed += 0.1
	return false


func _verify_presentation_invariance(preview: Node, chunk: Node, expected: Dictionary) -> void:
	var gs: GameState = preview._game_state
	var authority: Variant = gs.get_world_state(chunk.stacks_authority_key(), null)
	var tick_before := float(preview._scheduler.get_current_tick())
	for _frame in range(240):
		chunk.headless_process(1.0 / 60.0)
	check(chunk.get_preview_state() == expected
			and gs.get_world_state(chunk.stacks_authority_key(), null) == authority
			and is_equal_approx(float(preview._scheduler.get_current_tick()), tick_before),
		"presentation/headless calls cannot advance or rewrite the Stacks comparison")


func _bank_enabled_count(chunk: Node) -> int:
	var count := 0
	for interactable_v in chunk._bank_interactables.values():
		var interactable = interactable_v
		if is_instance_valid(interactable) and interactable.is_interaction_enabled():
			count += 1
	return count


func _gather_stacks_party(preview: Node, chunk: Node) -> void:
	for i in range(chunk.STACKS_PARTY_IDS.size()):
		var char_id := str(chunk.STACKS_PARTY_IDS[i])
		preview.headless_set_character_position(
			char_id,
			chunk.SHELTER_POS + Vector3(float(i) - 1.0, 0.0, 0.0))


func _party_atp(gs: GameState) -> Dictionary:
	return {
		"aster": gs.get_stat("aster", "atp"),
		"peris": gs.get_stat("peris", "atp"),
		"endo": gs.get_stat("endo", "atp"),
	}


func _offset_stats(values: Dictionary, offset: float) -> Dictionary:
	var out := {}
	for key_v in values.keys():
		var key := str(key_v)
		out[key] = float(values[key]) + offset
	return out


func _sorted(values: Variant) -> Array:
	var out: Array = (values as Array).duplicate() if values is Array else []
	out.sort()
	return out


func _spawn_stacks_preview():
	var preview = PreviewScene.instantiate()
	preview.preview_menu = false
	preview.preview_chunk = "stacks"
	preview.suppress_scene_change = true
	root.add_child(preview)
	for _frame in range(10):
		await process_frame
	check(preview._active_chunk != null, "Stacks preview boots its production chunk")
	if preview._active_chunk == null:
		await _discard(preview)
		return null
	return preview


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
	print("STACKS FRAGMENT SAVE AUTHORITY: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
