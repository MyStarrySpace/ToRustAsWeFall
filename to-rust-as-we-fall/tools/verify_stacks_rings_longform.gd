extends Node

## Focused regression for the restored Stacks and Rings causal cores.
## The filename is retained so existing CI entry points keep working.

const ACT1_SCENE := preload("res://scenes/tutorial/act1.tscn")
const ACT1_SOURCE_PATH := "res://scripts/tutorial/act1_sequence.gd"
const StacksBankEvidence := preload("res://scripts/game/mechanics/stacks_bank_evidence.gd")
const RINGS_AMBIENT_TRACES := ["client_bloom", "forget_me_not", "doorvine"]

var _failures: Array[String] = []


func _ready() -> void:
	EventLog.print_events = false
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("  FAIL: %s" % message)


func _run() -> void:
	_verify_retired_padding_absent()
	var stacks := await _spawn_act1("stacks")
	if stacks != null:
		_verify_stacks_structure(stacks)
		_verify_stacks_causal_route(stacks)
		await _dispose(stacks)
	else:
		_failures.append("Stacks boots")
	var rings := await _spawn_act1("rings")
	if rings != null:
		_verify_rings_structure(rings)
		_verify_rings_causal_route(rings)
		await _dispose(rings)
	else:
		_failures.append("Rings boots")
	_finish()


func _spawn_act1(district: String) -> Node:
	var act1 := ACT1_SCENE.instantiate()
	act1.set("start_chunk", district)
	act1.set("suppress_scene_change", true)
	get_tree().root.add_child(act1)
	for _frame in range(12):
		await get_tree().process_frame
	return act1


func _verify_retired_padding_absent() -> void:
	print("\n=== Retired Stacks/Rings padding ===")
	var source := FileAccess.get_file_as_string(ACT1_SOURCE_PATH)
	for token in [
		"STACKS_FIELD_OPERATIONS", "STACKS_FIELD_SITES",
		"RINGS_FIELD_OPERATIONS", "RINGS_FIELD_SITES",
		"_start_district_field_operation", "_build_district_fieldwork",
		"get_stacks_playtime_contract", "get_rings_playtime_contract",
		"ring.marco.warn.c_suite",
	]:
		_check(not source.contains(token), "retired token is absent: %s" % token)


func _verify_stacks_structure(act1: Node) -> void:
	print("\n=== Stacks authored structure ===")
	_check(act1.find_child("StacksFieldwork", true, false) == null,
		"Stacks builds no appended fieldwork layer")
	_check(act1.find_children("StacksField_*", "Interactable", true, false).is_empty(),
		"Stacks builds no appended checklist interactables")
	_check(act1.find_child("DataTerminal", true, false) != null,
		"support terminal remains authored")
	_check(act1.find_child("SignalWall", true, false) != null,
		"custom signal wall remains authored")
	_check(act1.find_children("StacksAudit_*", "Interactable", true, false).size() == 3,
		"three comparable audit banks remain authored")
	var target_text := act1.find_child("StacksAuditTargetText", true, false) as Label3D
	_check(target_text != null and target_text.text == StacksBankEvidence.target_text(),
		"a visible target panel states the trace that the bank probes must explain")
	var neutral_bank_labels: Array[String] = []
	var neutral_emission := -1.0
	var banks_are_neutral := true
	for bank_id_v in StacksBankEvidence.BANK_IDS:
		var bank_id := str(bank_id_v)
		var label := act1.find_child(
			"StacksAuditLabel_%s" % bank_id, true, false) as Label3D
		var display := act1.find_child(
			"StacksAuditDisplay_%s" % bank_id, true, false) as MeshInstance3D
		banks_are_neutral = banks_are_neutral and label != null and display != null
		if label == null or display == null:
			continue
		neutral_bank_labels.append(label.text)
		var display_material := display.material_override as StandardMaterial3D
		banks_are_neutral = banks_are_neutral and display_material != null
		if display_material == null:
			continue
		var emission := display_material.emission_energy_multiplier
		if neutral_emission < 0.0:
			neutral_emission = emission
		banks_are_neutral = banks_are_neutral and is_equal_approx(emission, neutral_emission)
	_check(banks_are_neutral
		and neutral_bank_labels == ["BANK A", "BANK B", "BANK C"],
		"bank names and display brightness are neutral rather than answer-coded")
	_check(act1.find_child("SupportWorkspace", true, false) != null,
		"Myke's workspace remains optional authored worldbuilding")
	_check(act1.find_child("StacksShelterRest", true, false) != null,
		"the named Stacks shelter-rest beat has a real shelter interaction")
	_check(not act1.has_method("get_stacks_playtime_contract"),
		"Stacks exposes no synthetic playtime contract")


func _verify_stacks_causal_route(act1: Node) -> void:
	print("\n=== Stacks causal route ===")
	act1.prepare_stacks_fragment("bank")
	_check(str(act1._current_step) == "stacks_bank_audit",
		"Stacks begins on the meaningful three-bank deduction")
	# Optional records can be inspected, but none of them can advance or reorder the route.
	_check(not bool(act1.trigger_stacks_terminal(false))
		and not bool(act1.trigger_stacks_signal(false))
		and not bool(act1.trigger_stacks_archive(false)),
		"retired optional-read helpers cannot manufacture observations")
	_check(_interact_act1_optional(
			act1, act1._stacks_terminal_interactable, "aster"),
		"Aster reads the maintenance terminal through its real world control")
	act1._dialogue.clear()
	act1._finish_stacks_terminal_dialogue()
	_check(_interact_act1_optional(
			act1, act1._stacks_signal_interactable, "aster"),
		"Aster parses the signal wall through its real world control")
	act1._dialogue.clear()
	act1._finish_stacks_signal_dialogue()
	_check(_interact_act1_optional(
			act1, act1._stacks_workspace_interactable, "aster"),
		"Aster traces the support workspace through its real world control")
	act1._dialogue.clear()
	act1._finish_stacks_archive_dialogue()
	_check(bool(act1.trigger_stacks_support_log()),
		"the journal viewer opens only after the physical terminal acquired its entry")
	act1.close_stacks_engram_overlay()
	_check(str(act1._current_step) == "stacks_bank_audit"
		and act1._stacks_bank_samples.is_empty(),
		"support-log/terminal/signal/archive reads are optional and never gate or reorder")

	_check(not bool(act1.trigger_stacks_bank("bank_a"))
			and act1._stacks_bank_samples.is_empty(),
		"the retired bank helper cannot manufacture Stacks evidence")
	var bank_a = act1._stacks_bank_interactables.get("bank_a")
	act1._on_act1_stacks_bank_interacted(bank_a, "bank_a")
	_check(act1._stacks_bank_samples.is_empty(),
		"a direct bank callback cannot impersonate an accepted world interaction")
	_check(_interact_act1_stacks_bank(act1, "bank_a"),
		"physical Aster samples Bank A through its real control")
	var bank_a_readout := act1.find_child(
		"StacksAuditReadout_bank_a", true, false) as Label3D
	_check(not act1._stacks_bank_resolved
		and act1._stacks_bank_samples.size() == 1
		and bank_a_readout != null
		and bank_a_readout.visible
		and bank_a_readout.text == StacksBankEvidence.observation_text("bank_a"),
		"first interaction samples a bank and leaves its complete probe result visible")
	_check(_interact_act1_stacks_bank(act1, "bank_a"),
		"physical Aster commits the sampled Bank A prediction")
	_check(not act1._stacks_bank_resolved
		and act1._stacks_last_commit == "bank_a"
		and act1._stacks_failed_commits == ["bank_a"],
		"a wrong sampled-bank commit records a falsified prediction and remains retryable")
	var failed_snapshot: Dictionary = act1.build_save_snapshot()
	act1._stacks_last_commit = ""
	act1._stacks_failed_commits.clear()
	bank_a_readout.visible = false
	act1.apply_save_snapshot(failed_snapshot)
	_check(act1._stacks_last_commit == "bank_a"
		and act1._stacks_failed_commits == ["bank_a"]
		and bank_a_readout.visible
		and bank_a_readout.text == StacksBankEvidence.observation_text("bank_a"),
		"save restore preserves the failed commit and its persistent observation")

	_check(_interact_act1_stacks_bank(act1, "bank_b"),
		"physical Aster samples Bank B through its real control")
	_check(not act1._stacks_bank_resolved and act1._stacks_bank_samples.size() == 2,
		"first Bank B interaction records evidence instead of treating the answer as a button")
	_check(_interact_act1_stacks_bank(act1, "bank_b"),
		"physical Aster commits the evidenced Bank B prediction")
	_check(act1._stacks_bank_resolved
		and act1._stacks_last_commit == StacksBankEvidence.solution_bank()
		and act1._stacks_bank_samples.size() == 2,
		"the evidence-derived prediction resolves without an all-banks checklist")
	_check(str(act1._current_step) == "stacks_shelter",
		"a correct commit synchronously opens the named shelter-rest beat")
	for char_id in ["aster", "peris", "endo"]:
		act1._game_state.command_stop(char_id)
		act1.headless_set_character_position(char_id, act1.STACKS_SHELTER_POS)
		act1._game_state.set_stat(char_id, "hp", 90.0)
	_check(not bool(act1.trigger_stacks_shelter_rest(false)),
		"the retired shelter helper cannot manufacture the anxiety beat")
	var shelter = act1._stacks_shelter_interactable
	act1._on_act1_stacks_shelter_interacted(shelter, false)
	_check(not act1._stacks_anxiety_seen,
		"a direct shelter callback cannot impersonate its accepted one-shot")
	act1._select_character("aster")
	shelter.active_character = "aster"
	_check(bool(shelter._trigger(false)),
		"the gathered party commits Stacks through the real shelter control")
	_check(str(act1._current_step) == "stacks_shelter"
		and act1._stacks_anxiety_seen and act1._dialogue.is_active(),
		"shelter rest starts Peris's direct question before releasing exploration")
	_check(act1._game_state.is_resting("aster") and act1._game_state.is_resting("peris"),
		"the story beat uses GameState's real shelter-rest path")
	# This causal-core verifier does not simulate reader clicks. Exercise the named completion seam
	# after proving that the conversation, rather than the interaction callback, holds the transition.
	act1._dialogue.clear()
	act1._queue_stacks_explore()
	act1.headless_advance(0.21, 0.05)
	_check(str(act1._current_step) == "stacks_explore",
		"finishing the shelter conversation releases Stacks exploration")

	var state: Dictionary = act1.headless_get_state().get("stacks", {})
	_check(bool(state.get("bank_resolved", false))
		and bool(state.get("anxiety_seen", false))
		and (state.get("bank_samples", []) as Array).size() == 2
		and (state.get("failed_commits", []) as Array) == ["bank_a"],
		"Stacks state preserves observations, falsified predictions, and the result")
	var act1_snapshot: Dictionary = act1.build_save_snapshot().get("act1", {})
	var snapshot: Dictionary = act1_snapshot.get("stacks_state", {})
	_check(str(snapshot.get("last_commit", "")) == StacksBankEvidence.solution_bank()
		and (snapshot.get("failed_commits", []) as Array) == ["bank_a"]
		and not snapshot.has("field_choices") and not snapshot.has("field_effects"),
		"save data retains prediction history without retired field-operation outcomes")


func _verify_rings_structure(act1: Node) -> void:
	print("\n=== Rings authored structure ===")
	_check(act1.find_child("RingsFieldwork", true, false) == null,
		"Rings builds no appended fieldwork layer")
	_check(act1.find_children("RingsField_*", "Interactable", true, false).is_empty(),
		"Rings builds no appended checklist interactables")
	_check(act1.find_child("ClientNPC", true, false) != null,
		"Marco/former-client interaction remains authored")
	_check(act1.find_child("RingsEndoJunctionLabel", true, false) != null
		and act1.find_child("RingsEndoJunctionLight", true, false) != null,
		"Endo's outbound junction is an authored, readable world endpoint")
	for trace_id in RINGS_AMBIENT_TRACES:
		_check(act1.find_child("RingsTrace_%s" % trace_id, true, false) != null,
			"optional residential trace remains: %s" % trace_id)
	_check(not act1.has_method("get_rings_playtime_contract"),
		"Rings exposes no synthetic playtime contract")


func _verify_rings_causal_route(act1: Node) -> void:
	print("\n=== Rings causal route ===")
	act1.prepare_rings_fragment("client")
	_check(not bool(act1.trigger_rings_trace("doorvine")),
		"the retired Rings trace helper cannot manufacture ambient knowledge")
	for trace_id in ["doorvine", "client_bloom", "forget_me_not"]:
		_check(_interact_act1_optional(
				act1, act1._rings_trace_interactables.get(trace_id), "peris"),
			"Peris reads %s through its authored world control" % trace_id)
	var state: Dictionary = act1.headless_get_state().get("rings", {})
	_check(int(state.get("trace_count", -1)) == RINGS_AMBIENT_TRACES.size()
		and str(act1._current_step) == "rings_client",
		"all three ambient reads work in any order without skipping the Marco question")
	var anchors: Dictionary = act1.headless_get_anchor_positions()
	var marco_position: Vector3 = anchors.get("rings_marco", act1.RINGS_START)
	act1.headless_set_character_position(
		"endo", marco_position + Vector3(-2.0, 0.0, 1.0))
	act1.headless_set_character_position(
		"peris", marco_position + Vector3(-1.0, 0.0, -0.6))
	act1._game_state.set_party(["aster", "peris", "endo"])
	act1._rings_client_interactable.active_character = "peris"
	_check(act1._rings_client_interactable._trigger(false),
		"the gathered party enters Rings progression through the real Marco interaction")
	var traversal: Dictionary = act1._game_state.get_external_traversal_state("endo")
	var authority: Dictionary = act1._game_state.get_world_state(
		act1.rings_endo_departure_authority_key(), {})
	_check(str(act1._current_step) == "endo_departs"
		and str(act1._rings_endo_phase) == act1.RINGS_ENDO_PHASE_DEPARTING
		and act1._game_state.characters.has("endo")
		and act1._game_state.get_party().has("endo")
		and act1._endo.visible
		and not traversal.is_empty(),
		"Marco commits a visible, locked Endo traversal while roster truth remains present")
	_check(int(authority.get("version", 0)) == act1.RINGS_ENDO_AUTHORITY_VERSION
		and is_equal_approx(
			float(authority.get("deadline", -1.0)),
			float(traversal.get("end_tick", -2.0))),
		"the campaign record and external traversal share one saved deadline")
	act1.headless_advance(float(traversal.get("remaining", 0.0)) + 0.01, 0.1)
	_check(str(act1._current_step) == "rings_explore"
		and str(act1._rings_endo_phase) == act1.RINGS_ENDO_PHASE_DEPARTED
		and not act1._game_state.characters.has("endo")
		and not act1._game_state.get_party().has("endo")
		and not act1._endo.visible,
		"only physical arrival retires Endo and releases Rings exploration")
	_check(not _interact_act1_optional(
			act1, act1._rings_trace_interactables.get("client_bloom"), "peris"),
		"a consumed ambient source cannot be replayed after Endo departs")
	state = act1.headless_get_state().get("rings", {})
	_check(str(act1._current_step) == "rings_explore"
		and int(state.get("trace_count", 0)) == RINGS_AMBIENT_TRACES.size(),
		"ambient reads neither gate nor reorder exploration, even when revisited")
	_check(not state.has("fieldwork"),
		"runtime state contains no retired field-operation ladder")
	var act1_snapshot: Dictionary = act1.build_save_snapshot().get("act1", {})
	var snapshot: Dictionary = act1_snapshot.get("rings_state", {})
	_check(not snapshot.has("field_choices") and not snapshot.has("field_effects"),
		"save data contains no retired Rings branch outcomes")


func _interact_act1_stacks_bank(act1: Node, bank_id: String) -> bool:
	var bank = act1._stacks_bank_interactables.get(bank_id)
	if not is_instance_valid(bank):
		return false
	act1._game_state.command_stop("aster")
	act1.headless_set_character_position("aster", bank.global_position)
	act1._select_character("aster")
	bank.active_character = "aster"
	return bool(bank._trigger(false))


func _interact_act1_optional(act1: Node, interactable: Node, actor: String) -> bool:
	if not is_instance_valid(interactable):
		return false
	act1._game_state.command_stop(actor)
	act1.headless_set_character_position(actor, (interactable as Node3D).global_position)
	act1._select_character(actor)
	interactable.set("active_character", actor)
	return bool(interactable.call("_trigger", false))


func _dispose(act1: Node) -> void:
	if act1 != null and is_instance_valid(act1):
		act1.set_process(false)
		act1.set_physics_process(false)
		if act1.has_method("_teardown_sequence"):
			act1._teardown_sequence()
		act1.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("\nStacks/Rings causal-core verification: ALL PASSED")
		get_tree().quit(0)
	else:
		print("\nStacks/Rings causal-core verification: %d FAILED" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		get_tree().quit(1)
