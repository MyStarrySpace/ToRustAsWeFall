extends SceneTree

const Trace := preload("res://scripts/testing/persona_decision_trace.gd")
const Distiller := preload("res://scripts/testing/persona_decision_library.gd")
const Fingerprint := preload("res://scripts/testing/content_fingerprint.gd")
const PersonaPlayer := preload("res://scripts/testing/persona_player_controller.gd")
const PlayerObservation := preload(
	"res://scripts/testing/player_observation_controller.gd")
const ConsequencePresentation := preload(
	"res://scripts/game/world/consequence_presentation_controller.gd")
const StretchPlaytestLoop := preload(
	"res://scripts/generation/stretch_generation_playtest_loop.gd")

var _checks := 0
var _failures := 0
var _scratch := ""
var _authored_identity := {}
var _gameplay_build_identity := {}


class _MovementRouteStateDouble:
	var characters := {"aster": {}}
	var position := Vector3.ZERO
	var route_active := true
	var moving := false
	var route_remaining := -1.0

	func is_moving(_id: String) -> bool:
		return moving

	func is_navigation_route_active(_id: String) -> bool:
		return route_active

	func get_position(_id: String) -> Vector3:
		return position

	func get_navigation_route_remaining_distance(_id: String) -> float:
		return route_remaining


func _init() -> void:
	_scratch = "user://persona_decision_pipeline_v3_%s" % str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_scratch))
	_authored_identity = Fingerprint.authored_fragment_resource(
		"res://data/fragments/basin_fill_proof.tres")
	_check(bool(_authored_identity.get("ok", false))
		and str(_authored_identity.get("content_fingerprint_schema", ""))
			== Fingerprint.AUTHORED_FRAGMENT_SCHEMA
		and str(_authored_identity.get("content_fingerprint", "")).length() == 64,
		"authored content identity hashes exact fragment resource bytes")
	_gameplay_build_identity = Fingerprint.gameplay_build()
	_check(bool(_gameplay_build_identity.get("ok", false))
		and str(_gameplay_build_identity.get(
			"gameplay_build_fingerprint_schema", "")) \
			== Fingerprint.GAMEPLAY_BUILD_SCHEMA
		and str(_gameplay_build_identity.get(
			"gameplay_build_fingerprint", "")).length() == 64,
		"gameplay build identity reads and hashes every fixed source byte resource")

	_test_content_fingerprints()
	_test_observation_and_raw_derivation_contract()
	_test_nonparty_consequence_observation_contract()
	_test_background_state_change_presentation_contract()
	_test_persona_consequence_wait_policy_contract()
	_test_camera_presentation_trace_contract()
	_test_goal_derivation_and_writer_sealing()
	_test_candidate_target_binding()
	_test_temporal_input_and_movement_adversaries()
	_test_movement_presentation_route_handoff()
	_test_exact_rally_progress_liveness_binding()

	var native_paths := _write_complete_cohort("native", "native_green")
	var native_documents := _seal_cohort(native_paths, "native_green_invocation")
	var web_paths := _write_complete_cohort("web", "web_green")
	var web_documents := _seal_cohort(web_paths, "web_green_invocation")
	_check(native_documents.size() == 4 and web_documents.size() == 4
		and _all_documents_ok(native_documents) and _all_documents_ok(web_documents),
		"Native and Web each seal the exact two-persona by two-repeat cohort")
	_test_preview_policy_supersession(native_documents)

	var combined: Array = []
	combined.append_array(native_documents)
	combined.append_array(web_documents)
	var distilled := Distiller.distill({}, combined, 2)
	var eazy_node := _node(distilled, "eazy_rest_visible_shelter")
	var dean_node := _node(distilled, "dean_rally_visible_ground")
	_check(not eazy_node.is_empty() and bool(eazy_node.get("eligible_for_automation", false))
		and int((eazy_node.get("evidence", {}) as Dictionary).get("support_count", 0)) == 4
		and int((eazy_node.get("evidence", {}) as Dictionary).get(
			"distinct_content_count", 0)) == 1,
		"Native and Web evidence for identical authored bytes counts as one content identity")
	_check(not dean_node.is_empty() and bool(dean_node.get("eligible_for_automation", false))
		and int((dean_node.get("evidence", {}) as Dictionary).get("support_count", 0)) == 4,
		"full derived-goal cohorts promote repeated Dean evidence")
	var mixed_build_library := distilled.duplicate(true)
	var mixed_eazy := _node(mixed_build_library, "eazy_rest_visible_shelter")
	var mixed_provenance := ((mixed_eazy.get("evidence", {}) as Dictionary).get(
		"provenance", []) as Array)
	for index in range(2, mixed_provenance.size()):
		if mixed_provenance[index] is Dictionary:
			(mixed_provenance[index] as Dictionary)["gameplay_build_fingerprint"] = \
				"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	mixed_build_library = Distiller.distill(mixed_build_library, [], 3)
	mixed_eazy = _node(mixed_build_library, "eazy_rest_visible_shelter")
	_check(not bool(mixed_eazy.get("eligible_for_automation", true))
		and int((mixed_eazy.get("evidence", {}) as Dictionary).get(
			"support_count", 0)) == 4
		and int((mixed_eazy.get("evidence", {}) as Dictionary).get(
			"max_support_cohort_count", 0)) == 2,
		"support from different gameplay builds cannot pool to meet minimum support")
	var executable_observation := _observation("baseline")
	var current_choice := Distiller.choose_action(
		distilled, "eazy_speezy", executable_observation)
	_check(bool(current_choice.get("matched", false))
		and str(current_choice.get("node_id", "")) == "eazy_rest_visible_shelter",
		"current v3 tree executes only against a complete valid player observation")
	var flat_choice := Distiller.choose_action(distilled, "eazy_speezy",
		(executable_observation.get("state", {}) as Dictionary).duplicate(true))
	_check(not bool(flat_choice.get("matched", true))
		and str(flat_choice.get("reason", "")) == "player_observation_invalid",
		"flat arbitrary state cannot execute a learned policy tree")
	var stale_library := distilled.duplicate(true)
	stale_library["schema"] = "persona_decision_library_v2"
	var stale_choice := Distiller.choose_action(
		stale_library, "eazy_speezy", executable_observation)
	_check(not bool(stale_choice.get("matched", true))
		and str(stale_choice.get("reason", "")) == "library_schema_not_current",
		"stale v2 library trees cannot execute directly")
	var wrong_contract_library := distilled.duplicate(true)
	(wrong_contract_library["contract"] as Dictionary)["player_observation_schema"] = \
		"player_observation_v0"
	var wrong_contract_choice := Distiller.choose_action(
		wrong_contract_library, "eazy_speezy", executable_observation)
	_check(not bool(wrong_contract_choice.get("matched", true))
		and str(wrong_contract_choice.get("reason", "")) == "library_contract_not_current",
		"current schema label cannot hide a stale executable library contract")
	_test_invocation_cohort_fail_closed(native_paths, native_documents)
	_test_forged_persisted_derivations(native_paths[1])
	_test_v2_library_provenance_is_inadmissible(distilled)

	_cleanup()
	print("[PERSONA_DECISION_PIPELINE] %s (%d checks)" % [
		"PASS" if _failures == 0 else "FAIL (%d)" % _failures,
		_checks,
	])
	quit(0 if _failures == 0 else 1)


func _test_nonparty_consequence_observation_contract() -> void:
	var observer := PlayerObservation.new()
	var raw_subject := "private_dweller_alpha"
	_check(str(observer.call(
		"validation_consequence_subject_token", raw_subject)) == "",
		"background validation cannot mint a nonparty token before rendered observation")

	var active_cues := observer.call("_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation(raw_subject, "active", true)) as Array
	var opaque_token := str((active_cues[0] as Dictionary).get(
		"source_token", "")) if active_cues.size() == 1 else ""
	var arrival_cues := observer.call("_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation(raw_subject, "arrival", true)) as Array
	var arrival_token := str((arrival_cues[0] as Dictionary).get(
		"source_token", "")) if arrival_cues.size() == 1 else ""
	var public_projection_json := Trace.canonical_json(
		{"active": active_cues, "arrival": arrival_cues}).to_lower()
	_check(active_cues.size() == 1 and arrival_cues.size() == 1
		and opaque_token.begins_with("consequence_")
		and arrival_token == opaque_token
		and str((active_cues[0] as Dictionary).get("phase", "")) == "active"
		and str((arrival_cues[0] as Dictionary).get("phase", "")) == "arrival"
		and str(observer.call(
			"validation_consequence_subject_token", raw_subject)) == opaque_token
		and not public_projection_json.contains(raw_subject)
		and not public_projection_json.contains("dweller"),
		"a rendered nonparty consequence keeps one session-opaque active-to-arrival token without exposing identity")
	var other_raw_subject := "private_dweller_beta"
	var other_active_cues := observer.call(
		"_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation(
			other_raw_subject, "active", true)) as Array
	var other_arrival_cues := observer.call(
		"_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation(
			other_raw_subject, "arrival", true)) as Array
	var other_token := str((other_active_cues[0] as Dictionary).get(
		"source_token", "")) if other_active_cues.size() == 1 else ""
	_check(other_active_cues.size() == 1 and other_arrival_cues.size() == 1
		and other_token != "" and other_token != opaque_token
		and str((other_arrival_cues[0] as Dictionary).get(
			"source_token", "")) == other_token
		and not Trace.canonical_json({
			"active": other_active_cues,
			"arrival": other_arrival_cues,
		}).to_lower().contains(other_raw_subject),
		"two same-label rendered nonparty subjects receive distinct opaque lineages without leaking either identity")

	var before := _observation_with_extra_cues([])
	var active := _observation_with_extra_cues(active_cues)
	var arrival := _observation_with_extra_cues(arrival_cues)
	_check(Trace.validate_player_observation(active).is_empty()
		and Trace.validate_player_observation(arrival).is_empty(),
		"opaque nonparty consequence cues remain valid player_observation_v1 records")
	var traversal_event := _background_traversal_event(raw_subject)
	var player := PersonaPlayer.new()
	player._observer = observer
	var valid := player.call("_validate_background_event_presentation",
		before, [active], arrival, [traversal_event]) as Dictionary
	var lineages := valid.get("subject_lineages", []) as Array
	var valid_json := Trace.canonical_json(valid).to_lower()
	_check(bool(valid.get("ok", false)) and lineages.size() == 1
		and (lineages[0] as Dictionary).get("source_tokens", []) == [opaque_token]
		and bool((lineages[0] as Dictionary).get("active_visible", false))
		and bool((lineages[0] as Dictionary).get("arrival_visible", false))
		and not valid_json.contains(raw_subject)
		and not valid_json.contains("private-event-id")
		and not valid_json.contains("private-traversal-id"),
		"post-hoc validation accepts the exact opaque nonparty active-to-arrival lineage and retains no private event data")

	var active_only := player.call("_validate_background_event_presentation",
		before, [active], active, [traversal_event]) as Dictionary
	_check(not bool(active_only.get("ok", true))
		and not (active_only.get("failures", []) as Array).has(
			"background_traversal_subject_token_missing")
		and not (active_only.get("failures", []) as Array).has(
			"background_traversal_active_cue_missing")
		and (active_only.get("failures", []) as Array).has(
			"background_traversal_arrival_cue_missing"),
		"an opaque nonparty active cue remains incomplete until the same token visibly arrives")
	var wrong_subject_arrival := _observation_with_extra_cues(
		other_arrival_cues)
	var crossed_lineage := player.call(
		"_validate_background_event_presentation", before, [active],
		wrong_subject_arrival, [traversal_event]) as Dictionary
	_check(not bool(crossed_lineage.get("ok", true))
		and not (crossed_lineage.get("failures", []) as Array).has(
			"background_traversal_active_cue_missing")
		and (crossed_lineage.get("failures", []) as Array).has(
			"background_traversal_arrival_cue_missing"),
		"a different opaque subject's same-label arrival cannot complete the active nonparty lineage")

	var unbound_subject := "private_dweller_unbound"
	var unrendered_cues := observer.call("_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation(
			unbound_subject, "active", false)) as Array
	var generic := _observation_with_extra_cues([{
		"kind": "hud",
		"text": "SWEPT BY RISING BASIN // START / CURRENT RETURN",
		"visible": true,
	}])
	var unbound := player.call("_validate_background_event_presentation",
		before, [generic], generic,
		[_background_traversal_event(unbound_subject)]) as Dictionary
	_check(unrendered_cues.is_empty()
		and str(observer.call(
			"validation_consequence_subject_token", unbound_subject)) == ""
		and not bool(unbound.get("ok", true))
		and (unbound.get("failures", []) as Array).has(
			"background_traversal_subject_token_missing")
		and (unbound.get("failures", []) as Array).has(
			"background_traversal_active_cue_missing")
		and (unbound.get("failures", []) as Array).has(
			"background_traversal_arrival_cue_missing"),
		"generic HUD text and an unrendered record cannot mint or substitute for a bound nonparty consequence")

	observer._known_party_subjects["aster"] = true
	var unbound_party_cues := observer.call(
		"_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation("aster", "active", true)) as Array
	observer._visible_portrait_subject_tokens["aster"] = "portrait_fixture"
	var bound_party_cues := observer.call(
		"_consequence_cues_from_presentation", {},
		_nonparty_consequence_presentation("aster", "active", true)) as Array
	_check(unbound_party_cues.is_empty()
		and str(observer.call(
			"validation_consequence_subject_token", "aster")) == ""
		and bound_party_cues.size() == 1
		and str((bound_party_cues[0] as Dictionary).get(
			"source_token", "")) == "portrait_fixture",
		"known party subjects still require their exact visible portrait/body binding and never receive a nonparty fallback")
	player.free()
	observer.free()


func _test_background_state_change_presentation_contract() -> void:
	var player := PersonaPlayer.new()
	var before := _opaque_party_observation("baseline")
	var active := _opaque_party_observation("active")
	var arrival := _opaque_party_observation("arrival")
	var traversal_event := {
		"kind": "begin_external_traversal",
		"event_id": "private-event-id",
		"payload": {
			"id": "aster",
			"traversal_id": "private-traversal-id",
			"presentation_receipt": {
				"scope": "player_facing",
				"effect_kind": "forced_movement",
				"label": "SWEPT",
				"destination_label": "RETURN SHELF",
			},
		},
	}
	var valid := player.call("_validate_background_event_presentation",
		before, [active], arrival, [traversal_event]) as Dictionary
	var valid_lineages := valid.get("subject_lineages", []) as Array
	var valid_json := Trace.canonical_json(valid).to_lower()
	_check(bool(valid.get("ok", false))
		and int(valid.get("event_count", 0)) == 1
		and bool(valid.get("causal_cue_delta_visible", false))
		and int(valid.get("player_facing_traversal_count", 0)) == 1
		and valid_lineages.size() == 1
		and bool((valid_lineages[0] as Dictionary).get("active_visible", false))
		and bool((valid_lineages[0] as Dictionary).get("arrival_visible", false)),
		"a passive interval accepts an authoritative traversal only with new rendered active and arrival cues")
	_check((valid_lineages[0] as Dictionary).get("source_tokens", []).has(
			"portrait_0001")
		and not valid_json.contains("aster")
		and not valid_json.contains("private-event-id")
		and not valid_json.contains("private-traversal-id"),
		"background validation binds the exact opaque portrait while keeping raw subject and event lineage private")

	var wait_decision := {
		"verb": "wait", "world_change": false, "group_verb": false,
		"intended_subjects": [], "target": {"token": "visible_announced_basin_sweep"},
	}
	var wait_receipt := {
		"receipt_id": "wait:background", "boundary": "player_command",
		"status": "observed", "player_reproducible": true, "verb": "wait",
		"atomic_group": false, "production_event_count": 0,
		"production_event_kinds": [], "input_issued": false,
		"input_event_count": 0, "input_events": [],
		"validation_background_event_count": 1,
		"validation_background_event_kinds": ["begin_external_traversal"],
		"validation_background_visual_lineage": valid.duplicate(true),
	}
	var wait_record := _decision_record(before, arrival, [active], wait_decision,
		wait_receipt, {})
	_check(Trace.validate_decision_record(wait_record).is_empty()
		and int((wait_record.get("input_receipt", {}) as Dictionary).get(
			"production_event_count", -1)) == 0
		and int((wait_record.get("input_receipt", {}) as Dictionary).get(
			"validation_background_event_count", 0)) == 1,
		"validation observes scheduler events without falsely claiming that a passive wait issued production input")

	var silent := player.call("_validate_background_event_presentation",
		before, [], before.duplicate(true), [traversal_event]) as Dictionary
	_check(not bool(silent.get("ok", true))
		and (silent.get("failures", []) as Array).has(
			"background_state_change_has_no_new_rendered_causal_cue")
		and (silent.get("failures", []) as Array).has(
			"background_traversal_active_cue_missing")
		and (silent.get("failures", []) as Array).has(
			"background_traversal_arrival_cue_missing"),
		"a silent background traversal fails even when its authoritative event exists")

	var active_only := player.call("_validate_background_event_presentation",
		before, [active], active, [traversal_event]) as Dictionary
	_check(not bool(active_only.get("ok", true))
		and not (active_only.get("failures", []) as Array).has(
			"background_traversal_active_cue_missing")
		and (active_only.get("failures", []) as Array).has(
			"background_traversal_arrival_cue_missing"),
		"an active-only background traversal fails without a rendered arrival")
	var failed_wait_receipt := wait_receipt.duplicate(true)
	failed_wait_receipt["validation_background_visual_lineage"] = \
		active_only.duplicate(true)
	var failed_wait_record := _decision_record(before, active, [active],
		wait_decision, failed_wait_receipt, {})
	_check((Trace.classify_evidence(failed_wait_record).get(
			"rejection_reasons", []) as Array).has(
			"background_presentation_validation_failed"),
		"a failed background presentation validation makes the persisted decision ineligible")
	var private_validation := valid.duplicate(true)
	private_validation["payload"] = {"id": "aster"}
	var private_wait_receipt := wait_receipt.duplicate(true)
	private_wait_receipt["validation_background_visual_lineage"] = \
		private_validation
	var private_wait_record := _decision_record(before, arrival, [active],
		wait_decision, private_wait_receipt, {})
	_check((Trace.classify_evidence(private_wait_record).get(
			"rejection_reasons", []) as Array).has(
			"background_validation_contains_private_event_data"),
		"raw payload/subject keys cannot enter an otherwise valid background trace receipt")

	var unrelated_active := active.duplicate(true)
	var unrelated_arrival := arrival.duplicate(true)
	_remove_cue_source(unrelated_active, "portrait_0001")
	_remove_cue_source(unrelated_arrival, "portrait_0001")
	var unrelated := player.call("_validate_background_event_presentation",
		before, [unrelated_active], unrelated_arrival,
		[traversal_event]) as Dictionary
	_check(not bool(unrelated.get("ok", true))
		and (unrelated.get("failures", []) as Array).has(
			"background_traversal_active_cue_missing")
		and (unrelated.get("failures", []) as Array).has(
			"background_traversal_arrival_cue_missing"),
		"same-label consequences on other portraits cannot attest Aster's background traversal")

	var unbound_before := before.duplicate(true)
	var unbound_active := active.duplicate(true)
	var unbound_arrival := arrival.duplicate(true)
	for observation in [unbound_before, unbound_active, unbound_arrival]:
		_remove_portrait_binding(observation as Dictionary, "portrait_0001")
	var unbound := player.call("_validate_background_event_presentation",
		unbound_before, [unbound_active], unbound_arrival,
		[traversal_event]) as Dictionary
	_check(not bool(unbound.get("ok", true))
		and (unbound.get("failures", []) as Array).has(
			"background_traversal_subject_token_missing"),
		"a matching label cannot substitute for the affected subject's visible portrait/body binding")
	player.free()


func _test_persona_consequence_wait_policy_contract() -> void:
	var player := PersonaPlayer.new()
	player._persona = "dean_takahashi"
	player._policy_phase = "fumble"
	player.call("_update_policy_memory", {
		"verb": "rally",
		"visible_consequence": "RISK: RISING BASIN SWEEP",
	}, true, {})
	var dean_wait := player.call("_choose_decision", {}, 2) as Dictionary
	_check(str(player._policy_phase) == "await_missed_rise"
		and str(dean_wait.get("verb", "")) == "wait"
		and str(dean_wait.get("wait_until", "")) == "dean_sweep_terminal"
		and float(dean_wait.get("wait_seconds", 0.0)) >= 18.0,
		"Dean observes the missed-rise consequence after an accepted whole-party Rally to visibly sweep-risky ground")

	player._policy_phase = "fumble"
	player.call("_update_policy_memory", {
		"verb": "rally",
		"visible_consequence": "RISK: RISING BASIN SWEEP",
	}, false, {})
	_check(str(player._policy_phase) == "fumble",
		"a refused risky-floor Rally cannot manufacture Dean's consequence-wait state")

	var lineages: Dictionary = {}
	player._sweep_warning_observed = true
	player._dean_roster_tokens.append("portrait_0001")
	player._sweep_phase_evidence = {
		"portrait_0001|SWEPT BY RISING BASIN|START / CURRENT RETURN": {
			"source_token": "portrait_0001",
			"phases": {"active": true, "arrival": true},
		},
	}
	var active := _observation_with_extra_cues([{
		"kind": "consequence",
		"source_token": "consequence_0001",
		"phase": "active",
		"label": "SWEPT BY RISING BASIN",
		"destination_label": "START / CURRENT RETURN",
		"text": "SWEPT BY RISING BASIN // START / CURRENT RETURN",
		"visible": true,
	}])
	player.call("_record_visible_forced_consequence_phases", active, lineages)
	_check(not bool(player.call(
		"_visible_forced_consequence_lineages_complete", lineages))
		and not bool(player.call("_dean_wait_can_seal", lineages)),
		"Dean cannot seal after the warning roster arrives while another newly visible consequence remains active-only")
	var wrong_arrival := _observation_with_extra_cues([{
		"kind": "consequence",
		"source_token": "consequence_0002",
		"phase": "arrival",
		"label": "SWEPT BY RISING BASIN",
		"destination_label": "START / CURRENT RETURN",
		"text": "ARRIVED // START / CURRENT RETURN",
		"visible": true,
	}])
	player.call("_record_visible_forced_consequence_phases", wrong_arrival, lineages)
	_check(not bool(player.call(
		"_visible_forced_consequence_lineages_complete", lineages))
		and not bool(player.call("_dean_wait_can_seal", lineages)),
		"another rendered subject's matching arrival cannot close Dean's active opaque consequence")
	var arrival := wrong_arrival.duplicate(true)
	var arrival_cue := (((arrival.get("state", {}) as Dictionary).get(
		"cues", []) as Array)[-1] as Dictionary)
	arrival_cue["source_token"] = "consequence_0001"
	player.call("_record_visible_forced_consequence_phases", arrival, lineages)
	_check(bool(player.call(
		"_visible_forced_consequence_lineages_complete", lineages))
		and bool(player.call("_dean_wait_can_seal", lineages)),
		"Dean's wait closes only after every newly visible active consequence reaches the same opaque token's arrival")
	player.free()


func _test_camera_presentation_trace_contract() -> void:
	var before := _observation("baseline")
	var after := before.duplicate(true)
	after["tick"] = float(before.get("tick", 0.0)) + 1.0
	var after_cues := ((after.get("state", {}) as Dictionary).get(
		"cues", []) as Array)
	for cue_v in after_cues:
		if not (cue_v is Dictionary) \
				or str((cue_v as Dictionary).get("kind", "")) != "party_body":
			continue
		var cue := cue_v as Dictionary
		var screen := cue.get("screen", []) as Array
		cue["screen"] = [float(screen[0]) + 12.0, float(screen[1]) + 4.0]
	var cases := [
		{"verb": "camera_pan", "events": _key_pair_events(0, "KeyW")},
		{"verb": "camera_recenter", "events": _key_pair_events(0, "Home")},
		{"verb": "camera_rotate", "events": _key_pair_events(0, "KeyQ")},
		{"verb": "camera_zoom", "events": _pointer_pair_events(0, 5)},
	]
	var valid_records: Array[Dictionary] = []
	for case_v in cases:
		var case := case_v as Dictionary
		var verb := str(case.get("verb", ""))
		var events := case.get("events", []) as Array
		var decision := {
			"verb": verb,
			"world_change": false,
			"group_verb": false,
			"intended_subjects": [],
			"target": {"kind": "visible_control", "token": verb},
		}
		var receipt := {
			"receipt_id": "fixture:%s" % verb,
			"boundary": "keyboard_pointer",
			"status": "accepted",
			"player_reproducible": true,
			"verb": verb,
			"atomic_group": false,
			"production_event_count": 0,
			"production_event_kinds": [],
			"input_issued": true,
			"input_event_count": events.size(),
			"input_sequence_before": 0,
			"input_sequence_after": events.size(),
			"input_events": events,
			"input_target_token": verb,
		}
		var record := _decision_record(
			before, after, [], decision, receipt, {})
		var evidence := Trace.classify_evidence(record)
		_check(Trace.validate_decision_record(record).is_empty()
			and bool(evidence.get("player_reproducible", false))
			and not bool(evidence.get("eligible_for_learning", true))
			and (evidence.get("rejection_reasons", []) as Array).has(
				"presentation_recovery_not_gameplay_learning_candidate")
			and not bool((record.get("outcome", {}) as Dictionary).get(
				"world_causal_evidence", true)),
			"%s proves its exact presentation packet without promoting a gameplay outcome"
				% verb)
		valid_records.append(record)

	var no_delta_decision := {
		"verb": "camera_recenter",
		"world_change": false,
		"group_verb": false,
		"intended_subjects": [],
		"target": {"kind": "visible_control", "token": "camera_recenter"},
	}
	var no_delta_events := _key_pair_events(0, "Home")
	var no_delta_receipt := {
		"receipt_id": "fixture:camera_recenter:no_delta",
		"boundary": "keyboard_pointer",
		"status": "accepted",
		"player_reproducible": true,
		"verb": "camera_recenter",
		"atomic_group": false,
		"production_event_count": 0,
		"production_event_kinds": [],
		"input_issued": true,
		"input_event_count": no_delta_events.size(),
		"input_sequence_before": 0,
		"input_sequence_after": no_delta_events.size(),
		"input_events": no_delta_events,
		"input_target_token": "camera_recenter",
	}
	var no_delta_record := _decision_record(
		before, before, [], no_delta_decision, no_delta_receipt, {})
	var no_delta_evidence := Trace.classify_evidence(no_delta_record)
	_check(Trace.validate_decision_record(no_delta_record).is_empty()
		and bool(no_delta_evidence.get("player_reproducible", false))
		and not bool(no_delta_evidence.get("eligible_for_learning", true))
		and not bool((no_delta_record.get("outcome", {}) as Dictionary).get(
			"visible_change", true)),
		"a mechanically exact no-op camera recovery remains recorded but cannot promote")

	var valid := valid_records[0]
	var legacy_before := valid.duplicate(true)
	legacy_before["observation"] = legacy_before.get(
		"observation_before", {}).duplicate(true)
	_check(Trace.validate_decision_record(legacy_before).has(
		"legacy observation is not valid v3 evidence"),
		"legacy top-level observation alias is rejected even beside intact v3 captures")
	var legacy_outcome := valid.duplicate(true)
	var outcome := (legacy_outcome.get("outcome", {}) as Dictionary).duplicate(true)
	outcome["observation"] = legacy_outcome.get(
		"observation_after", {}).duplicate(true)
	legacy_outcome["outcome"] = outcome
	_check(Trace.validate_decision_record(legacy_outcome).has(
		"outcome does not match the exact v3 derived outcome"),
		"legacy outcome.observation alias cannot pass exact writer derivation")


func _test_content_fingerprints() -> void:
	var first := Fingerprint.generated_spec({
		"id": "stretch", "nodes": [{"id": "a", "cost": 2}],
		"runtime_metadata": {"elapsed_ms": 10}, "platform": "native",
	})
	var reordered := Fingerprint.generated_spec({
		"platform": "web", "nodes": [{"cost": 2, "id": "a"}], "id": "stretch",
		"runtime_metadata": {"elapsed_ms": 999, "timestamp": 1234},
	})
	var changed := Fingerprint.generated_spec({
		"id": "stretch", "nodes": [{"id": "a", "cost": 3}],
		"runtime_metadata": {"elapsed_ms": 10}, "platform": "native",
	})
	_check(str(first.get("content_fingerprint_schema", ""))
			== Fingerprint.GENERATED_SPEC_SCHEMA
		and str(first.get("content_fingerprint", ""))
			== str(reordered.get("content_fingerprint", "")),
		"generated content identity ignores key order and runtime/platform metadata")
	_check(str(first.get("content_fingerprint", ""))
			!= str(changed.get("content_fingerprint", "")),
		"generated content identity changes when semantic payload changes")
	var build_again := Fingerprint.gameplay_build()
	var build_inventory: Array = _gameplay_build_identity.get(
		"gameplay_build_resource_inventory", [])
	var sorted_inventory := build_inventory.duplicate()
	sorted_inventory.sort()
	var unique_inventory := {}
	for path_value in build_inventory:
		unique_inventory[str(path_value)] = true
	var required_behavior_resources := [
		"res://scripts/fragments/chunks/data_fragment_chunk.gd",
		"res://scripts/fragments/preview_web_e2e_controller.gd",
		"res://scripts/game/characters/locomotion_juice.gd",
		"res://scripts/game/objects/crossing_assist.gd",
		"res://scripts/game/objects/interactable.gd",
		"res://scripts/game/world/causal_feedback_link.gd",
		"res://scripts/game/world/consequence_presentation_controller.gd",
		"res://scripts/game/world/grid_world.gd",
		"res://scripts/game/world/path_render_manager.gd",
		"res://scripts/system/core/fixed_cadence.gd",
		"res://scripts/system/core/game_event.gd",
		"res://scripts/testing/content_fingerprint.gd",
		"res://scripts/ui/game_hud.gd",
		"res://tools/agent_player_input_driver.gd",
	]
	var required_resources_present := true
	for required_path in required_behavior_resources:
		if not unique_inventory.has(required_path):
			required_resources_present = false
	_check(bool(build_again.get("ok", false))
		and str(build_again.get("gameplay_build_fingerprint", "")) \
			== str(_gameplay_build_identity.get(
				"gameplay_build_fingerprint", ""))
		and build_again.get("gameplay_build_resource_inventory", []) \
			== build_inventory
		and build_inventory == sorted_inventory
		and unique_inventory.size() == build_inventory.size()
		and build_inventory.size() == Fingerprint.GAMEPLAY_BUILD_RESOURCE_PATHS.size()
		and required_resources_present,
		"gameplay build identity is deterministic over the complete reviewed behavior inventory")

	var build_resource_bytes := {}
	for path_value in build_inventory:
		var path := str(path_value)
		build_resource_bytes[path] = FileAccess.get_file_as_bytes(path)
	var mutation_path := "res://scripts/game/objects/crossing_assist.gd"
	var mutated_resource_bytes := build_resource_bytes.duplicate(true)
	var changed_bytes: PackedByteArray = build_resource_bytes[mutation_path]
	changed_bytes = changed_bytes.duplicate()
	changed_bytes.append(0)
	mutated_resource_bytes[mutation_path] = changed_bytes
	var mutated_build := Fingerprint.gameplay_build_from_resource_bytes(
		mutated_resource_bytes)
	_check(bool(mutated_build.get("ok", false))
		and mutated_build.get("gameplay_build_resource_inventory", []) \
			== build_inventory
		and str(mutated_build.get("gameplay_build_fingerprint", "")) \
			!= str(_gameplay_build_identity.get(
				"gameplay_build_fingerprint", "")),
		"changing one reviewed behavior resource byte changes the gameplay build fingerprint")

	var reduced_resource_bytes := build_resource_bytes.duplicate(true)
	reduced_resource_bytes.erase(mutation_path)
	var reduced_build := Fingerprint.gameplay_build_from_resource_bytes(
		reduced_resource_bytes)
	_check(bool(reduced_build.get("ok", false))
		and not (mutation_path in reduced_build.get(
			"gameplay_build_resource_inventory", []))
		and str(reduced_build.get("gameplay_build_fingerprint", "")) \
			!= str(_gameplay_build_identity.get(
				"gameplay_build_fingerprint", "")),
		"changing the reviewed behavior inventory changes both inventory and build fingerprint")
	var deterministic_a := PersonaPlayer.deterministic_run_identity(
		"basin_fill_proof", "dean_takahashi", "native", 1, 41)
	var deterministic_b := PersonaPlayer.deterministic_run_identity(
		"basin_fill_proof", "dean_takahashi", "native", 1, 41)
	var deterministic_other := PersonaPlayer.deterministic_run_identity(
		"basin_fill_proof", "dean_takahashi", "native", 2, 41)
	_check(deterministic_a == deterministic_b and deterministic_a != deterministic_other
		and deterministic_a == "basin_fill_proof:dean_takahashi:native_1_41",
		"Native run identity is deterministic and repeat/seed collision resistant")


func _test_observation_and_raw_derivation_contract() -> void:
	var before := _observation("baseline")
	var after := _observation("eazy_success")
	_check(Trace.validate_player_observation(before).is_empty()
		and Trace.validate_player_observation(after).is_empty(),
		"current viewport, cue state/result/serial/label/destination fields validate")

	var reforming := _observation("baseline")
	var reforming_cue := _movement_result_cue(
		"ground_1", 4, "progress", true, "")
	reforming_cue["route_status"] = "reforming_route"
	reforming_cue["route_status_serial"] = 1
	reforming_cue["route_status_subjects"] = [
		"portrait_aster", "portrait_peris",
	]
	reforming_cue["route_status_remaining_seconds"] = 0.0
	_add_cue(reforming, reforming_cue)
	var cooperative_hold := _observation("baseline")
	var cooperative_hold_cue := reforming_cue.duplicate(true)
	cooperative_hold_cue["route_status"] = "cooperative_hold"
	cooperative_hold_cue["route_status_serial"] = 2
	cooperative_hold_cue["route_status_subjects"] = ["portrait_peris"]
	cooperative_hold_cue["route_status_remaining_seconds"] = 0.6
	_add_cue(cooperative_hold, cooperative_hold_cue)
	_check(Trace.validate_player_observation(reforming).is_empty()
		and Trace.validate_player_observation(cooperative_hold).is_empty(),
		("strict observations accept complete visible reforming-route and "
		+ "cooperative-hold cue bundles"))

	var raw_route_subject := cooperative_hold.duplicate(true)
	var raw_route_cue := (((raw_route_subject.get("state", {}) as Dictionary).get(
		"cues", []) as Array).back() as Dictionary)
	raw_route_cue["route_status_subjects"] = ["peris"]
	var raw_route_issues := Trace.validate_player_observation(raw_route_subject)
	_check(raw_route_issues.has(
		"observation.state.cues.3.route_status_subjects must be a subset of movement subjects")
		and raw_route_issues.has(
			"observation.state.cues.3.route_status_subjects must contain only visible portrait tokens"),
		("route status rejects raw character IDs that are neither movement "
		+ "portrait tokens nor visible HUD portrait tokens"))

	var partial_route_bundle := reforming.duplicate(true)
	var partial_route_cue := (((partial_route_bundle.get(
		"state", {}) as Dictionary).get("cues", []) as Array).back() as Dictionary)
	partial_route_cue.erase("route_status_remaining_seconds")
	_check(Trace.validate_player_observation(partial_route_bundle).has(
		"observation.state.cues.3 route-status fields must be present together"),
		"route-status presentation metadata is an atomic optional bundle")

	var invalid_route_time := cooperative_hold.duplicate(true)
	var invalid_route_time_cue := (((invalid_route_time.get(
		"state", {}) as Dictionary).get("cues", []) as Array).back() as Dictionary)
	invalid_route_time_cue["route_status_remaining_seconds"] = INF
	_check(Trace.validate_player_observation(invalid_route_time).has(
		("observation.state.cues.3.route_status_remaining_seconds must be "
		+ "finite and non-negative")),
		"route-status countdowns reject non-finite private scheduler values")

	var impossible_route_phases := reforming.duplicate(true)
	var impossible_reforming_cue := (((impossible_route_phases.get(
		"state", {}) as Dictionary).get("cues", []) as Array).back() as Dictionary)
	impossible_reforming_cue["route_status_remaining_seconds"] = 0.4
	var reforming_issues := Trace.validate_player_observation(
		impossible_route_phases)
	var impossible_hold := cooperative_hold.duplicate(true)
	var impossible_hold_cue := (((impossible_hold.get(
		"state", {}) as Dictionary).get("cues", []) as Array).back() as Dictionary)
	impossible_hold_cue["route_status_remaining_seconds"] = 0.0
	var hold_issues := Trace.validate_player_observation(impossible_hold)
	_check(reforming_issues.has(
		("observation.state.cues.3.route_status_remaining_seconds must be "
		+ "zero while reforming"))
		and hold_issues.has(
			("observation.state.cues.3.route_status_remaining_seconds must be "
			+ "positive during a cooperative hold")),
		"route-status countdown semantics match the two visible route phases")

	var misplaced_route_bundle := _observation("baseline")
	var hud_route_cue := {
		"kind": "hud", "text": "ROUTE", "visible": true,
		"route_status": "reforming_route", "route_status_serial": 1,
		"route_status_subjects": ["portrait_aster"],
		"route_status_remaining_seconds": 0.0,
	}
	_add_cue(misplaced_route_bundle, hud_route_cue)
	_check(Trace.validate_player_observation(misplaced_route_bundle).has(
		"observation.state.cues.3 route-status fields require a movement_result cue"),
		"route-status metadata cannot be smuggled through a generic cue")

	var private_observation := before.duplicate(true)
	(private_observation["state"] as Dictionary)["solution"] = {"target": "private"}
	_check(not Trace.validate_player_observation(private_observation).is_empty(),
		"private world/solution keys remain outside player_observation_v1")
	var missing_fingerprint_trace := Trace.new()
	var missing_fingerprint_run := _run_metadata(
		"native", "eazy_speezy", 0, "missing_fingerprint_schema")
	missing_fingerprint_run.erase("content_fingerprint_schema")
	var missing_fingerprint_begin := missing_fingerprint_trace.begin(
		_scratch.path_join("missing_fingerprint_schema.jsonl"), missing_fingerprint_run)
	_check(not bool(missing_fingerprint_begin.get("ok", true))
		and str(missing_fingerprint_begin.get("error", "")).contains(
			"content_fingerprint_schema"),
		"run headers without an explicit supported fingerprint schema fail closed")
	missing_fingerprint_trace.abort()
	var missing_build_trace := Trace.new()
	var missing_build_run := _run_metadata(
		"native", "eazy_speezy", 0, "missing_gameplay_build")
	missing_build_run.erase("gameplay_build_fingerprint")
	var missing_build_begin := missing_build_trace.begin(
		_scratch.path_join("missing_gameplay_build.jsonl"), missing_build_run)
	_check(not bool(missing_build_begin.get("ok", true))
		and str(missing_build_begin.get("error", "")).contains(
			"gameplay_build_fingerprint"),
		"run headers without an explicit gameplay build identity fail closed")
	missing_build_trace.abort()

	var missing_after_path := _scratch.path_join("missing_after.jsonl")
	var missing_after_trace := Trace.new()
	var begun := missing_after_trace.begin(missing_after_path,
		_run_metadata("native", "eazy_speezy", 0, "missing_after"))
	var missing_after_receipt := _interaction_receipt()
	missing_after_receipt["observation_before_capture_serial"] = 1
	missing_after_receipt["first_post_input_capture_serial"] = 2
	var missing_after := missing_after_trace.append_decision(
		before, {}, [], _rationale(), _eazy_decision(), missing_after_receipt,
		_context("missing_after"), _eazy_candidate())
	_check(bool(begun.get("ok", false)) and not bool(missing_after.get("ok", true))
		and str(missing_after.get("error", "")).contains("observation_after"),
		"append_decision rejects missing after-observation evidence")
	missing_after_trace.abort()

	var hidden_decision := _dean_decision()
	hidden_decision["world_change"] = false
	hidden_decision["group_verb"] = false
	var decomposed_receipt := _rally_receipt()
	decomposed_receipt["atomic_group"] = false
	decomposed_receipt["production_event_count"] = 3
	var hidden_record := _decision_record(
		_observation("baseline"), _observation("baseline"), [], hidden_decision,
		decomposed_receipt, _dean_candidate())
	var hidden_evidence := Trace.classify_evidence(hidden_record)
	var hidden_reasons := str(hidden_evidence.get("rejection_reasons", []))
	_check(hidden_reasons.contains("group_verb_was_decomposed")
		and hidden_reasons.contains("derived_visible_world_change_missing"),
		"rally and multi-subject intent infer hidden group/world-change flags fail-closed")

	var select_after := _observation("baseline")
	var select_portraits := (((select_after.get("state", {}) as Dictionary).get(
		"hud", {}) as Dictionary).get("portraits", [])) as Array
	for portrait_value in select_portraits:
		if portrait_value is Dictionary:
			(portrait_value as Dictionary)["selected"] = true
	var select_decision := {
		"verb": "select_party", "world_change": false, "group_verb": true,
		"intended_subjects": ["aster", "peris", "endo"],
		"target": {"token": "hud_portraits"},
	}
	var select_receipt := _select_party_receipt()
	var select_record := _decision_record(_observation("baseline"), select_after, [],
		select_decision, select_receipt, {})
	_check(bool(Trace.classify_evidence(select_record).get("eligible_for_learning", false)),
		"multi-subject select_party is presentation-only and need not forge one production event")
	var decomposed_interaction_receipt := _interaction_receipt()
	decomposed_interaction_receipt["atomic_group"] = false
	decomposed_interaction_receipt["production_event_count"] = 3
	var decomposed_interaction := _decision_record(
		_observation("baseline"), _observation("eazy_success"),
		[_observation("eazy_success")], _eazy_decision(),
		decomposed_interaction_receipt, {})
	_check(str(Trace.classify_evidence(decomposed_interaction).get(
		"rejection_reasons", [])).contains("group_verb_was_decomposed"),
		"multi-subject world-changing interact remains one atomic production action")

	var absent_record := _decision_record(before, before, [], _eazy_decision(),
		_interaction_receipt(), _eazy_candidate())
	_check(str(Trace.classify_evidence(absent_record).get("rejection_reasons", [])).contains(
		"interaction_target_result_missing"),
		"interaction evidence rejects an absent exact target result")
	var stale_before := _observation("baseline")
	_add_cue(stale_before, _interaction_result_cue("shelter_1", 2, "success"))
	var stale_after := stale_before.duplicate(true)
	var stale_record := _decision_record(stale_before, stale_after, [], _eazy_decision(),
		_interaction_receipt(), _eazy_candidate())
	_check(str(Trace.classify_evidence(stale_record).get("rejection_reasons", [])).contains(
		"interaction_target_result_not_new"),
		"interaction evidence rejects a stale presentation serial")
	var wrong_after := _observation("baseline")
	_add_cue(wrong_after, _interaction_result_cue("other_target", 3, "success"))
	var wrong_record := _decision_record(before, wrong_after, [], _eazy_decision(),
		_interaction_receipt(), _eazy_candidate())
	_check(str(Trace.classify_evidence(wrong_record).get("rejection_reasons", [])).contains(
		"interaction_target_result_source_mismatch"),
		"interaction evidence rejects a newer result from the wrong opaque token")

	var rejected_after := _observation("baseline")
	_add_cue(rejected_after, _interaction_result_cue("shelter_1", 4, "rejected"))
	var status_record := _decision_record(before, rejected_after, [], _eazy_decision(),
		_interaction_receipt(), _eazy_candidate())
	var status_derived := Trace.derive_feedback_outcome(before, rejected_after, [],
		_eazy_decision(), _interaction_receipt())
	_check(str((status_derived.get("outcome", {}) as Dictionary).get("status", ""))
			== "refused"
		and not bool((status_derived.get("outcome", {}) as Dictionary).get(
			"accepted", true))
		and str(Trace.classify_evidence(status_record).get("rejection_reasons", [])).contains(
			"interaction_target_result_status_mismatch"),
		"exact visible interaction result authors outcome and must agree with receipt status")

	var wait_decision := {
		"verb": "wait", "world_change": false, "group_verb": false,
		"intended_subjects": [], "target": {"token": "visible_announced_mid_crossing"},
	}
	var wait_receipt := {
		"receipt_id": "wait:0", "boundary": "player_command", "status": "observed",
		"player_reproducible": true, "verb": "wait", "atomic_group": false,
		"production_event_count": 0, "production_event_kinds": [],
		"input_issued": false, "input_event_count": 0, "input_events": [],
	}
	var wait_candidate := {
		"node_id": "no_progress_wait", "rule": "A no-progress wait must not teach policy.",
		"scope": "fragment", "condition": {"path": "cues", "op": "exists", "value": true},
		"action": {"verb": "wait", "target_ref": "announced_visible_consequence"},
		"expected": {"path": "accepted", "op": "eq", "value": false},
	}
	var wait_record := _decision_record(before, before, [], wait_decision,
		wait_receipt, wait_candidate)
	var wait_outcome := wait_record.get("outcome", {}) as Dictionary
	_check(str(wait_outcome.get("status", "")) == "observed"
		and not bool(wait_outcome.get("accepted", true))
		and str(Trace.classify_evidence(wait_record).get("rejection_reasons", [])).contains(
			"passive_wait_without_delta_cannot_support_candidate"),
		"passive no-delta wait is observed/false and cannot support a candidate")


func _test_goal_derivation_and_writer_sealing() -> void:
	var warning_only := _decision_record(_observation("baseline"),
		_observation("warning"), [_observation("warning")], _dean_decision(),
		_rally_receipt(), {})
	var dean_run := _run_metadata("native", "dean_takahashi", 0, "goal_fixture")
	_check(not bool(Trace.derive_persona_goal(dean_run, [warning_only]).get("reached", true)),
		"Dean warning-only evidence does not prove the Basin goal")
	var active_arrival := _decision_record(_observation("baseline"),
		_observation("arrival"), [_observation("active"), _observation("arrival")],
		_dean_decision(), _rally_receipt(), {})
	_check(not bool(Trace.derive_persona_goal(dean_run, [active_arrival]).get("reached", true)),
		"Dean active/arrival without an earlier visible warning does not prove the goal")
	var wrong_lineage_samples := [
		_observation("warning"), _observation("active"),
		_observation("arrival_other_destination"),
	]
	var wrong_lineage := _decision_record(_observation("baseline"),
		wrong_lineage_samples.back(), wrong_lineage_samples, _dean_decision(),
		_rally_receipt(), {})
	_check(not bool(Trace.derive_persona_goal(dean_run, [wrong_lineage]).get("reached", true)),
		"Dean mismatched destination lineage does not prove the full-roster goal")
	var full_dean := _decision_record(_observation("baseline"), _observation("arrival"),
		[_observation("warning"), _observation("active"), _observation("arrival")],
		_dean_decision(), _rally_receipt(), {})
	var dean_goal := Trace.derive_persona_goal(dean_run, [full_dean])
	_check(bool(dean_goal.get("reached", false))
		and (dean_goal.get("evidence", {}) as Dictionary).get("roster", []).size() == 3
		and (dean_goal.get("evidence", {}) as Dictionary).get(
			"per_token_phases", []).size() == 3,
		"Dean requires warning then common-lineage SWEPT active/arrival for all visible members")

	var eazy_run := _run_metadata("native", "eazy_speezy", 0, "eazy_goal_fixture")
	var no_settled := _decision_record(_observation("baseline"),
		_observation("interaction_success_only"), [_observation("interaction_success_only")],
		_eazy_decision(), _interaction_receipt(), {})
	_check(not bool(Trace.derive_persona_goal(eazy_run, [no_settled]).get("reached", true)),
		"Eazy exact shelter success without same-action settled cue is not a goal")
	var eazy_success := _decision_record(_observation("baseline"),
		_observation("eazy_success"), [_observation("eazy_success")],
		_eazy_decision(), _interaction_receipt(), {})
	_check(bool(Trace.derive_persona_goal(eazy_run, [eazy_success]).get("reached", false)),
		"Eazy exact newer REST target success plus same-action full-party cue proves goal")

	var false_goal_path := _scratch.path_join("false_goal.jsonl")
	var false_goal_trace := Trace.new()
	false_goal_trace.begin(false_goal_path,
		_run_metadata("native", "eazy_speezy", 0, "false_goal"))
	var false_goal_receipt := _interaction_receipt()
	false_goal_receipt["observation_before_capture_serial"] = 1
	false_goal_receipt["first_post_input_capture_serial"] = 2
	var appended := false_goal_trace.append_decision(
		_observation("baseline", 1), _observation("interaction_success_only", 3),
		[_observation("interaction_success_only", 2)], _rationale(), _eazy_decision(),
		false_goal_receipt, _context("false_goal"), {})
	var finished := false_goal_trace.finish({
		"trace_complete": true, "persona_goal_reached": true,
		"goal_evidence": {"claimed": true},
	})
	var sealed_summary := finished.get("summary", {}) as Dictionary
	_check(bool(appended.get("ok", false)) and bool(finished.get("ok", false))
		and not bool(sealed_summary.get("persona_goal_reached", true))
		and not bool(sealed_summary.get("trace_complete", true)),
		"finish overwrites a caller's false goal and forces the trace incomplete")
	var forged_goal_path := _scratch.path_join("forged_goal.jsonl")
	_copy_trace(false_goal_path, forged_goal_path)
	_rewrite_record(forged_goal_path, Trace.SUMMARY_RECORD, func(record: Dictionary) -> void:
		var summary := record.get("summary", {}) as Dictionary
		summary["persona_goal_reached"] = true
		summary["trace_complete"] = true
		summary["goal_evidence"] = {"forged": true})
	var forged_goal := Trace.read_trace(forged_goal_path)
	_check(not bool(forged_goal.get("ok", true))
		and str(forged_goal.get("errors", [])).contains(
			"persona goal does not match persisted observation proof"),
		"reader rejects a rehashed summary goal forged without raw proof")


func _test_temporal_input_and_movement_adversaries() -> void:
	var valid_rally := _decision_record(
		_observation("baseline"), _observation("arrival"),
		[_observation("warning"), _observation("active"),
			_observation("arrival")],
		_dean_decision(), _rally_receipt(), {})
	_check(bool(Trace.classify_evidence(valid_rally).get(
		"eligible_for_learning", false)),
		"accepted Rally requires and accepts exact full-roster accepted-progress-arrival proof")
	var interrupted_rally := _decision_record(
		_observation("baseline"), _observation("interrupted"),
		[_observation("warning"), _observation("active")],
		_dean_decision(), _rally_receipt(), {})
	var interrupted_evidence := Trace.classify_evidence(interrupted_rally)
	var interrupted_outcome := interrupted_rally.get("outcome", {}) as Dictionary
	var interrupted_result := interrupted_outcome.get(
		"movement_result", {}) as Dictionary
	_check(bool(interrupted_evidence.get("eligible_for_learning", false))
		and str(interrupted_outcome.get("status", "")) == "accepted"
		and bool(interrupted_result.get("accepted", false))
		and Trace.canonical_equal(interrupted_result.get("phases", []),
			["accepted", "progress", "interrupted"])
		and str(interrupted_result.get("reason", "")).contains("stopped before"),
		"an accepted Rally keeps acceptance through a distinct visible stopped-short terminal")
	var interrupted_then_arrival := _decision_record(
		_observation("baseline"), _observation("arrival"),
		[_observation("warning"), _observation("active"),
			_observation("interrupted")],
		_dean_decision(), _rally_receipt(), {})
	_check(_evidence_reasons(interrupted_then_arrival).contains(
		"movement_result_phase_sequence_invalid"),
		"an interrupted terminal lineage can never later claim arrival")
	var silent_interruption_observation := _observation("interrupted")
	for cue_value in ((silent_interruption_observation.get(
			"state", {}) as Dictionary).get("cues", []) as Array):
		if cue_value is Dictionary and str((cue_value as Dictionary).get(
				"kind", "")) == "movement_result":
			(cue_value as Dictionary)["reason"] = ""
	var silent_interruption := _decision_record(
		_observation("baseline"), silent_interruption_observation,
		[_observation("warning"), _observation("active")],
		_dean_decision(), _rally_receipt(), {})
	_check(_evidence_reasons(silent_interruption).contains(
		"interrupted_movement_visible_reason_missing"),
		"a stopped-short terminal without a player-facing reason fails closed")

	var reordered := valid_rally.duplicate(true)
	var reordered_samples := reordered.get("observation_samples", []) as Array
	(reordered_samples[1] as Dictionary)["capture_serial"] = 1
	_check(_evidence_reasons(reordered).contains("observation_capture_reordered"),
		"capture serial regression inside samples is rejected")
	var replayed := valid_rally.duplicate(true)
	var replayed_samples := replayed.get("observation_samples", []) as Array
	(replayed_samples[0] as Dictionary)["capture_serial"] = 1
	_check(_evidence_reasons(replayed).contains("observation_capture_replayed"),
		"replaying a pre-input observation as a post-input sample is rejected")
	var post_terminal := valid_rally.duplicate(true)
	(post_terminal["observation_after"] as Dictionary)["capture_serial"] = 3
	_check(_evidence_reasons(post_terminal).contains(
		"observation_sample_occurs_after_terminal_capture"),
		"sample capture after the claimed terminal observation is rejected")
	var tick_regression := valid_rally.duplicate(true)
	((tick_regression.get("observation_samples", []) as Array)[1] as Dictionary)["tick"] = 0
	_check(_evidence_reasons(tick_regression).contains("observation_tick_regressed"),
		"scheduler tick regression is rejected even when capture serial increases")
	var wrong_anchor := valid_rally.duplicate(true)
	(wrong_anchor["input_receipt"] as Dictionary)[
		"observation_before_capture_serial"] = 99
	_check(_evidence_reasons(wrong_anchor).contains(
		"input_before_capture_binding_mismatch"),
		"input receipt must bind the exact pre-input observation capture")

	var selected_after := _observation("baseline")
	for portrait_value in (((selected_after.get("state", {}) as Dictionary).get(
			"hud", {}) as Dictionary).get("portraits", []) as Array):
		if portrait_value is Dictionary:
			(portrait_value as Dictionary)["selected"] = true
	var select_record := _decision_record(_observation("baseline"), selected_after, [], {
		"verb": "select_party", "world_change": false, "group_verb": true,
		"intended_subjects": ["aster", "peris", "endo"],
		"target": {"token": "hud_portraits"},
	}, _select_party_receipt(), {})
	_check(bool(Trace.classify_evidence(select_record).get(
		"eligible_for_learning", false)),
		"full visible-roster select_party passes with the exact shipped digit chord")

	var multi_selected_before := _observation("baseline")
	for portrait_value in (((multi_selected_before.get(
			"state", {}) as Dictionary).get(
			"hud", {}) as Dictionary).get("portraits", []) as Array):
		if portrait_value is Dictionary:
			(portrait_value as Dictionary)["selected"] = true
	var aster_single_after := multi_selected_before.duplicate(true)
	for portrait_value in (((aster_single_after.get("state", {}) as Dictionary).get(
			"hud", {}) as Dictionary).get("portraits", []) as Array):
		if portrait_value is Dictionary:
			(portrait_value as Dictionary)["selected"] = \
				str((portrait_value as Dictionary).get("label", "")).to_lower() == "aster"
	var select_single_decision := {
		"verb": "select_single", "world_change": false, "group_verb": false,
		"intended_subjects": ["aster"],
		"target": {"token": "portrait_aster"},
	}
	var ctrl_off_receipt := _select_single_ctrl_off_receipt()
	var ctrl_off_record := _decision_record(
		multi_selected_before, aster_single_after, [],
		select_single_decision, ctrl_off_receipt, {})
	_check(bool(Trace.classify_evidence(ctrl_off_record).get(
		"eligible_for_learning", false)),
		"full-group to singleton selection accepts the human Ctrl-toggle-off sibling chord")

	var missing_sibling_receipt := ctrl_off_receipt.duplicate(true)
	var missing_sibling_events := missing_sibling_receipt.get(
		"input_events", []) as Array
	missing_sibling_events.resize(2)
	missing_sibling_receipt["input_event_count"] = missing_sibling_events.size()
	missing_sibling_receipt["input_sequence_after"] = missing_sibling_events.size()
	var missing_sibling_record := _decision_record(
		multi_selected_before, aster_single_after, [], select_single_decision,
		missing_sibling_receipt, {})
	_check(_evidence_reasons(missing_sibling_record).contains(
		"select_single_subject_key_pair_missing"),
		"singleton Ctrl-toggle proof rejects a missing selected-sibling key pair")

	var wrong_modifier_receipt := ctrl_off_receipt.duplicate(true)
	for event_index in [0, 1]:
		var event := (wrong_modifier_receipt.get(
			"input_events", []) as Array)[event_index] as Dictionary
		(event.get("modifiers", {}) as Dictionary)["ctrl"] = false
	var wrong_modifier_record := _decision_record(
		multi_selected_before, aster_single_after, [], select_single_decision,
		wrong_modifier_receipt, {})
	_check(_evidence_reasons(wrong_modifier_record).contains(
		"select_single_subject_key_pair_missing"),
		"singleton Ctrl-toggle proof rejects an unmodified sibling key pair")

	var extra_key_receipt := ctrl_off_receipt.duplicate(true)
	var extra_key_events := extra_key_receipt.get("input_events", []) as Array
	extra_key_events.append_array(_key_pair_events(
		int(extra_key_receipt.get("input_sequence_after", 0)), "Digit1"))
	extra_key_receipt["input_event_count"] = extra_key_events.size()
	extra_key_receipt["input_sequence_after"] = extra_key_events.size()
	var extra_key_record := _decision_record(
		multi_selected_before, aster_single_after, [], select_single_decision,
		extra_key_receipt, {})
	_check(_evidence_reasons(extra_key_record).contains(
		"select_single_subject_key_pair_missing"),
		"singleton Ctrl-toggle proof rejects an extra retained-target key pair")

	var wrong_single_after := aster_single_after.duplicate(true)
	for portrait_value in (((wrong_single_after.get("state", {}) as Dictionary).get(
			"hud", {}) as Dictionary).get("portraits", []) as Array):
		if portrait_value is Dictionary \
				and str((portrait_value as Dictionary).get(
					"label", "")).to_lower() == "peris":
			(portrait_value as Dictionary)["selected"] = true
	var wrong_after_record := _decision_record(
		multi_selected_before, wrong_single_after, [], select_single_decision,
		ctrl_off_receipt, {})
	_check(_evidence_reasons(wrong_after_record).contains(
		"select_single_subject_key_pair_missing"),
		"singleton Ctrl-toggle proof rejects a non-singleton visible result")

	var peris_single_after := _observation("baseline")
	for portrait_value in (((peris_single_after.get("state", {}) as Dictionary).get(
			"hud", {}) as Dictionary).get("portraits", []) as Array):
		if portrait_value is Dictionary:
			(portrait_value as Dictionary)["selected"] = \
				str((portrait_value as Dictionary).get("label", "")).to_lower() == "peris"
	var direct_single_record := _decision_record(
		_observation("baseline"), peris_single_after, [], {
			"verb": "select_single", "world_change": false, "group_verb": false,
			"intended_subjects": ["peris"],
			"target": {"token": "portrait_peris"},
		}, _select_single_direct_receipt("Digit2"), {})
	_check(bool(Trace.classify_evidence(direct_single_record).get(
		"eligible_for_learning", false)),
		"direct singleton selection still accepts one unmodified intended-subject key pair")

	var wait_decision := {
		"verb": "wait", "world_change": false, "group_verb": false,
		"intended_subjects": [],
		"target": {"token": "visible_announced_mid_crossing"},
	}
	var active_wait := _decision_record(_observation("announced_wait"),
		_observation("baseline"), [], wait_decision, _active_wait_receipt(), {})
	_check(bool(Trace.classify_evidence(active_wait).get(
		"eligible_for_learning", false)),
		"active held-F wait is valid keyboard_pointer input with zero production")
	var wrong_wait_key := _active_wait_receipt()
	for event_value in wrong_wait_key.get("input_events", []):
		if event_value is Dictionary:
			(event_value as Dictionary)["key"] = "KeyH"
	var wrong_wait := _decision_record(_observation("announced_wait"),
		_observation("baseline"), [], wait_decision, wrong_wait_key, {})
	_check(_evidence_reasons(wrong_wait).contains("active_wait_f_key_pair_missing")
		and _evidence_reasons(wrong_wait).contains("verb_unrelated_key_event"),
		"an unrelated key cannot forge active wait proof")
	var modified_wait_receipt := _active_wait_receipt()
	for event_value in modified_wait_receipt.get("input_events", []):
		if event_value is Dictionary:
			((event_value as Dictionary).get("modifiers", {}) as Dictionary)["ctrl"] = true
	var modified_wait := _decision_record(_observation("announced_wait"),
		_observation("baseline"), [], wait_decision, modified_wait_receipt, {})
	_check(_evidence_reasons(modified_wait).contains("verb_key_modifiers_invalid"),
		"Ctrl-modified F cannot forge the shipped unmodified wait gesture")
	var controller_wait_receipt := _active_wait_receipt()
	controller_wait_receipt["boundary"] = "controller"
	var controller_wait := _decision_record(_observation("announced_wait"),
		_observation("baseline"), [], wait_decision, controller_wait_receipt, {})
	_check(_evidence_reasons(controller_wait).contains(
		"active_action_boundary_must_be_keyboard_pointer"),
		"controller/touch claims cannot satisfy the shipped keyboard_pointer boundary")

	var extra_click_receipt := _rally_receipt()
	var extra_events := extra_click_receipt.get("input_events", []) as Array
	var second_pair := _pointer_pair_events(extra_events.size(), 2)
	extra_events.append_array(second_pair)
	extra_click_receipt["input_event_count"] = extra_events.size()
	extra_click_receipt["input_sequence_after"] = extra_events.size()
	var extra_click := _decision_record(_observation("baseline"),
		_observation("arrival"), [_observation("warning"), _observation("active")],
		_dean_decision(), extra_click_receipt, {})
	_check(_evidence_reasons(extra_click).contains(
		"rally_right_pointer_pair_must_be_exactly_one"),
		"a second RMB click cannot hide inside one Rally decision")

	var subset_rally := valid_rally.duplicate(true)
	_set_movement_subjects(subset_rally,
		["portrait_aster", "portrait_peris"])
	_check(_evidence_reasons(subset_rally).contains(
		"movement_result_subject_tokens_do_not_match_intent"),
		"movement feedback for a portrait subset cannot prove Rally All")
	var duplicate_rally := valid_rally.duplicate(true)
	_set_movement_subjects(duplicate_rally,
		["portrait_aster", "portrait_aster", "portrait_endo"])
	_check(_evidence_reasons(duplicate_rally).contains(
		"movement_result_subject_tokens_do_not_match_intent"),
		"duplicate movement subjects cannot replace the full unique roster")
	var extra_subject_rally := valid_rally.duplicate(true)
	_set_movement_subjects(extra_subject_rally,
		["portrait_aster", "portrait_peris", "portrait_endo", "portrait_other"])
	_check(_evidence_reasons(extra_subject_rally).contains(
		"movement_result_subject_tokens_do_not_match_intent"),
		"extra movement subjects cannot prove the exact visible roster")

	var wrong_target := valid_rally.duplicate(true)
	_set_movement_targets(wrong_target, "ground_2")
	_check(_evidence_reasons(wrong_target).contains("movement_result_target_mismatch"),
		"new movement lineage for a different visible target is rejected")
	var extra_target_serial := valid_rally.duplicate(true)
	_add_cue(((extra_target_serial.get("observation_samples", []) as Array)[0]
		as Dictionary), _movement_result_cue(
			"ground_2", 2, "accepted", true, ""))
	_check(_evidence_reasons(extra_target_serial).contains(
		"movement_result_multiple_new_serials"),
		"an additional new other-target movement serial invalidates exact lineage")
	var regression := _decision_record(_observation("baseline"),
		_observation("arrival"), [
			_observation("warning"), _observation("active"),
			_observation("warning")],
		_dean_decision(), _rally_receipt(), {})
	_check(_evidence_reasons(regression).contains(
		"movement_result_phase_regression_or_skip"),
		"accepted-progress-accepted phase regression is rejected")
	var phase_skip := _decision_record(_observation("baseline"),
		_observation("arrival"), [_observation("warning")],
		_dean_decision(), _rally_receipt(), {})
	_check(_evidence_reasons(phase_skip).contains(
		"movement_result_phase_regression_or_skip")
		or _evidence_reasons(phase_skip).contains(
			"movement_result_phase_sequence_invalid"),
		"accepted-to-arrival skip cannot prove movement completion")
	var generic_only := _decision_record(_observation("baseline"),
		_observation("baseline"), [], _dean_decision(), _rally_receipt(), {})
	_check(_evidence_reasons(generic_only).contains("movement_result_missing"),
		"generic cues/body or camera drift cannot prove a move without movement_result")

	var refused_after := _observation("baseline")
	_add_cue(refused_after, _movement_result_cue("ground_1", 1, "refused",
		false, "RALLY REFUSED // no complete route."))
	var refused_receipt := _rally_receipt()
	refused_receipt["status"] = "refused"
	refused_receipt["production_event_count"] = 0
	refused_receipt["production_event_kinds"] = []
	refused_receipt["member_results"] = {
		"aster": "refused", "peris": "refused", "endo": "refused"}
	var refused_record := _decision_record(_observation("baseline"), refused_after,
		[], _dean_decision(), refused_receipt, {})
	_check(bool(Trace.classify_evidence(refused_record).get(
		"eligible_for_learning", false)),
		"visible full-roster refusal with reason, zero production, and zero movement is valid")
	var produced_refusal := refused_record.duplicate(true)
	(produced_refusal["input_receipt"] as Dictionary)["production_event_count"] = 1
	_check(_evidence_reasons(produced_refusal).contains(
		"movement_refusal_production_event_count_not_zero"),
		"movement refusal cannot conceal a production movement event")
	var moved_refusal_after := refused_after.duplicate(true)
	for cue_value in ((moved_refusal_after.get("state", {}) as Dictionary).get(
			"cues", []) as Array):
		if cue_value is Dictionary and str((cue_value as Dictionary).get(
				"source_token", "")) == "body_aster":
			(cue_value as Dictionary)["screen"] = [620, 360]
	var moved_refusal := _decision_record(_observation("baseline"),
		moved_refusal_after, [], _dean_decision(), refused_receipt, {})
	var moved_refusal_derived := Trace.derive_feedback_outcome(
		moved_refusal.get("observation_before", {}) as Dictionary,
		moved_refusal.get("observation_after", {}) as Dictionary,
		moved_refusal.get("observation_samples", []) as Array,
		moved_refusal.get("decision", {}) as Dictionary,
		moved_refusal.get("input_receipt", {}) as Dictionary)
	_check(bool(Trace.classify_evidence(moved_refusal).get(
		"eligible_for_learning", false))
		and ((moved_refusal_derived.get("feedback", {}) as Dictionary).get(
			"party_body_movement", {}) as Dictionary).get(
				"classification", "") == "screen_space_presentation_only"
		and ((moved_refusal_derived.get("outcome", {}) as Dictionary).get(
			"moved_subjects", []) as Array).is_empty(),
		("camera-relative body drift remains descriptive presentation but cannot "
		+ "be attributed to an exact zero-production Rally refusal"))

	var subset_receipt_record := valid_rally.duplicate(true)
	(subset_receipt_record["input_receipt"] as Dictionary)["intended_members"] = [
		"aster", "peris"]
	_check(_evidence_reasons(subset_receipt_record).contains(
		"receipt_members_do_not_equal_full_visible_roster"),
		"receipt membership must equal the complete visible HUD roster")
	var duplicate_roster := valid_rally.duplicate(true)
	var duplicate_hud := (((duplicate_roster.get("observation_before", {}) as Dictionary).get(
		"state", {}) as Dictionary).get("hud", {}) as Dictionary)
	((((duplicate_hud.get("portraits", []) as Array)[1]) as Dictionary))["label"] = "ASTER"
	_check(_evidence_reasons(duplicate_roster).contains(
		"visible_hud_roster_not_unique_complete"),
		"duplicate normalized HUD labels invalidate full-roster evidence")

	_test_input_sequence_progression()


func _test_movement_presentation_route_handoff() -> void:
	var route_state := _MovementRouteStateDouble.new()
	var presenter := ConsequencePresentation.new()
	root.add_child(presenter)
	presenter._game_state = route_state
	presenter._on_movement_result_requested({
		"verb": "rally",
		"subject_ids": ["aster"],
		"target_screen": [400.0, 300.0],
		"data_target": Vector3(8.0, 4.0, 0.0),
		"subject_destinations": {"aster": Vector3(8.0, 4.0, 0.0)},
		"accepted": true,
		"reason": "",
	}, presenter)
	var movement_state := presenter.get_movement_presentation_state() as Dictionary
	var movement_records := movement_state.get("records", []) as Array
	_check(movement_records.size() == 1
		and int((movement_records[0] as Dictionary).get(
			"presentation_serial", 0)) == 1
		and is_zero_approx(float((movement_records[0] as Dictionary).get(
			"progress", -1.0)))
		and presenter._movement_label.text.contains("ROUTE 0%"),
		"an accepted route visibly begins at zero on its stable public serial")

	# A route may initially travel away from the destination or turn a right
	# angle. Its rendered percentage follows consumed path length, not a
	# straight-line heuristic that can remain at zero while bodies really move.
	var curved_state := _MovementRouteStateDouble.new()
	curved_state.route_remaining = 100.0
	var curved_presenter := ConsequencePresentation.new()
	root.add_child(curved_presenter)
	curved_presenter._game_state = curved_state
	curved_presenter._on_movement_result_requested({
		"verb": "rally",
		"subject_ids": ["aster"],
		"target_screen": [400.0, 300.0],
		"data_target": Vector3(8.0, 0.0, 0.0),
		"subject_destinations": {"aster": Vector3(8.0, 0.0, 0.0)},
		"accepted": true,
		"reason": "",
	}, curved_presenter)
	curved_state.position = Vector3(-5.0, 0.0, 0.0)
	curved_state.route_remaining = 80.0
	curved_presenter._sync_movement_entries_at(Time.get_ticks_msec())
	var curved_entry := curved_presenter._movement_entries[1] as Dictionary
	_check(is_equal_approx(float(curved_entry.get("progress", -1.0)), 0.2)
		and curved_presenter._movement_label.text.contains("ROUTE 20%"),
		"path-distance progress advances while a curved route initially moves away from its destination")

	# The camera may follow the primary portrait closely enough that its body has
	# little screen-space displacement. The production acknowledgement must still
	# expose monotonically changing route work from the same authority-owned plan.
	route_state.position = Vector3(2.0, 1.0, 0.0)
	var now := Time.get_ticks_msec()
	presenter._sync_movement_entries_at(now)
	movement_state = presenter.get_movement_presentation_state() as Dictionary
	movement_records = movement_state.get("records", []) as Array
	var advanced_progress := float((movement_records[0] as Dictionary).get(
		"progress", -1.0)) if movement_records.size() == 1 else -1.0
	_check(advanced_progress > 0.0 and advanced_progress < 1.0
		and presenter._movement_label.text.contains("ROUTE 25%"),
		"an accepted route renders changing human-visible progress before its terminal")
	route_state.position = Vector3(1.0, 0.5, 0.0)
	presenter._sync_movement_entries_at(now + 1)
	movement_state = presenter.get_movement_presentation_state() as Dictionary
	movement_records = movement_state.get("records", []) as Array
	_check(movement_records.size() == 1
		and is_equal_approx(float((movement_records[0] as Dictionary).get(
			"progress", -1.0)), advanced_progress)
		and int((movement_records[0] as Dictionary).get(
			"presentation_serial", 0)) == 1,
		"route progress never regresses when a curved path briefly increases straight-line distance")
	route_state.position = Vector3(2.0, 1.0, 0.0)
	var entry := presenter._movement_entries[1] as Dictionary
	entry["phase"] = "progress"
	entry["phase_started_msec"] = now \
		- ConsequencePresentation.MOVEMENT_PHASE_MIN_MSEC - 1
	presenter._movement_entries[1] = entry
	presenter._sync_movement_entries_at(now)
	entry = presenter._movement_entries[1] as Dictionary
	_check(str(entry.get("phase", "")) == "progress"
		and int(entry.get("stopped_short_since_msec", -1)) == 0,
		"an authority-owned route handoff cannot be presented as a terminal refusal")

	route_state.route_active = false
	now += 100
	presenter._sync_movement_entries_at(now)
	entry = presenter._movement_entries[1] as Dictionary
	_check(str(entry.get("phase", "")) == "progress"
		and int(entry.get("stopped_short_since_msec", 0)) > 0,
		"one idle off-target sample arms a grace interval instead of declaring refusal")
	entry["stopped_short_since_msec"] = now
	presenter._movement_entries[1] = entry
	now += ConsequencePresentation.MOVEMENT_STOPPED_SHORT_GRACE_MSEC + 1
	presenter._sync_movement_entries_at(now)
	entry = presenter._movement_entries[1] as Dictionary
	movement_state = presenter.get_movement_presentation_state() as Dictionary
	movement_records = movement_state.get("records", []) as Array
	_check(str(entry.get("phase", "")) == "interrupted"
		and bool(entry.get("accepted", false))
		and str(entry.get("reason", "")).contains("stopped before")
		and movement_records.size() == 1
		and str((movement_records[0] as Dictionary).get("phase", "")) == "interrupted"
		and bool((movement_records[0] as Dictionary).get("accepted", false))
		and presenter._movement_panel != null
		and presenter._movement_panel.visible
		and presenter._movement_label.text.contains("RALLY INTERRUPTED")
		and presenter._movement_label.modulate.is_equal_approx(
			ConsequencePresentation.WARNING_TINT),
		"a sustained authority-idle destination miss is a visible accepted-but-interrupted terminal")

	var observer := PlayerObservation.new()
	observer._ground_tokens["400:304"] = "ground_fixture"
	# SceneTree._init has no presented viewport yet, so the presenter's public
	# record correctly reports render_visible=false even though its real panel is
	# enabled above. Exercise the observation projection with that same public
	# record marked as it is on a completed draw; do not bypass target tokenization.
	var rendered_movement_state := movement_state.duplicate(true)
	var rendered_records := rendered_movement_state.get("records", []) as Array
	if rendered_records.size() == 1:
		(rendered_records[0] as Dictionary)["visible"] = true
		(rendered_records[0] as Dictionary)["render_visible"] = true
	var interruption_cues := observer._movement_result_cues({"portraits": [{
		"label": "ASTER", "token": "portrait_fixture", "visible": true,
	}]}, rendered_movement_state, [{
		"token": "ground_fixture", "kind": "move", "screen": [400, 304],
	}])
	_check(interruption_cues.size() == 1
		and str((interruption_cues[0] as Dictionary).get(
			"target_token", "")) == "ground_fixture"
		and (interruption_cues[0] as Dictionary).get(
			"subjects", []) == ["portrait_fixture"]
		and str((interruption_cues[0] as Dictionary).get(
			"phase", "")) == "interrupted"
		and int((interruption_cues[0] as Dictionary).get(
			"presentation_serial", 0)) == 1
		and is_equal_approx(float((interruption_cues[0] as Dictionary).get(
			"progress", -1.0)), advanced_progress)
		and bool((interruption_cues[0] as Dictionary).get("accepted", false))
		and str((interruption_cues[0] as Dictionary).get(
			"reason", "")).contains("stopped before"),
		"player observation exposes the exact visible interrupted target/subject lineage")
	observer.free()

	# Exercise the authoritative boundary that cancels an ordinary graph plan.
	# The accepted Rally acknowledgement must retain its historical acceptance,
	# while the simultaneous forced-movement presentation names the cause and the
	# original movement lineage terminates as interrupted after its required
	# progress frame. Typed ladder/ramp handoffs preserve their plan and must not
	# arm this latch.
	var forced_presenter := ConsequencePresentation.new()
	root.add_child(forced_presenter)
	route_state.position = Vector3.ZERO
	route_state.route_active = true
	route_state.moving = true
	forced_presenter._game_state = route_state
	forced_presenter._on_movement_result_requested({
		"verb": "rally",
		"subject_ids": ["aster"],
		"target_screen": [400.0, 300.0],
		"data_target": Vector3(8.0, 4.0, 0.0),
		"subject_destinations": {"aster": Vector3(8.0, 4.0, 0.0)},
		"accepted": true,
		"reason": "",
	}, forced_presenter)
	var forced_entry := forced_presenter._movement_entries[1] as Dictionary
	forced_entry["phase"] = "progress"
	forced_entry["phase_started_msec"] = now \
		- ConsequencePresentation.MOVEMENT_PHASE_MIN_MSEC - 1
	forced_presenter._movement_entries[1] = forced_entry
	forced_presenter._latch_nonpreserving_movement_override("aster", {
		"preserve_cross_level_plan": true,
		"presentation_receipt": {"label": "LADDER CLIMB"},
	})
	forced_entry = forced_presenter._movement_entries[1] as Dictionary
	_check(not bool(forced_entry.get("interruption_pending", false)),
		"a typed ladder/ramp traversal preserves the accepted graph route lineage")
	forced_presenter._on_external_traversal_started("aster", {
		"preserve_cross_level_plan": false,
		"presentation_receipt": {
			"label": "SWEPT BY RISING BASIN",
		},
	})
	forced_entry = forced_presenter._movement_entries[1] as Dictionary
	_check(str(forced_entry.get("phase", "")) == "progress"
		and bool(forced_entry.get("accepted", false))
		and bool(forced_entry.get("interruption_pending", false))
		and str(forced_entry.get("interruption_reason", "")).contains(
			"SWEPT BY RISING BASIN"),
		"the public non-preserving traversal boundary atomically latches the accepted route interruption")
	forced_presenter._sync_movement_entries_at(now)
	forced_entry = forced_presenter._movement_entries[1] as Dictionary
	_check(str(forced_entry.get("phase", "")) == "interrupted"
		and bool(forced_entry.get("accepted", false))
		and str(forced_entry.get("reason", "")).contains("SWEPT BY RISING BASIN"),
		"the latched movement lineage terminates as accepted-progress-interrupted with a visible cause")
	route_state.position = Vector3(8.0, 4.0, 0.0)
	forced_presenter._sync_movement_entries_at(now + 1)
	forced_entry = forced_presenter._movement_entries[1] as Dictionary
	_check(str(forced_entry.get("phase", "")) == "interrupted",
		"a forced interruption is terminal and can never be rewritten as arrival")

	var arrived_presenter := ConsequencePresentation.new()
	root.add_child(arrived_presenter)
	route_state.position = Vector3.ZERO
	route_state.route_active = true
	route_state.moving = true
	arrived_presenter._game_state = route_state
	arrived_presenter._on_movement_result_requested({
		"verb": "rally",
		"subject_ids": ["aster"],
		"target_screen": [400.0, 300.0],
		"data_target": Vector3(8.0, 4.0, 0.0),
		"subject_destinations": {"aster": Vector3(8.0, 4.0, 0.0)},
		"accepted": true,
		"reason": "",
	}, arrived_presenter)
	route_state.position = Vector3(4.0, 2.0, 0.0)
	arrived_presenter._sync_movement_entries_at(now)
	var arrived_state := arrived_presenter.get_movement_presentation_state() as Dictionary
	var arrived_records := arrived_state.get("records", []) as Array
	var in_flight_progress := float((arrived_records[0] as Dictionary).get(
		"progress", -1.0)) if arrived_records.size() == 1 else -1.0
	_check(in_flight_progress > 0.0 and in_flight_progress < 1.0
		and arrived_presenter._movement_label.text.contains("ROUTE 50%"),
		"a moving accepted route presents an intermediate progress value")
	entry = arrived_presenter._movement_entries[1] as Dictionary
	entry["phase"] = "progress"
	entry["phase_started_msec"] = now \
		- ConsequencePresentation.MOVEMENT_PHASE_MIN_MSEC - 1
	arrived_presenter._movement_entries[1] = entry
	route_state.position = Vector3(8.0, 4.0, 0.0)
	route_state.route_active = false
	route_state.moving = false
	arrived_presenter._sync_movement_entries_at(now)
	entry = arrived_presenter._movement_entries[1] as Dictionary
	arrived_state = arrived_presenter.get_movement_presentation_state() as Dictionary
	arrived_records = arrived_state.get("records", []) as Array
	_check(str(entry.get("phase", "")) == "arrival"
		and bool(entry.get("accepted", false))
		and str(entry.get("reason", "")) == ""
		and arrived_records.size() == 1
		and int((arrived_records[0] as Dictionary).get(
			"presentation_serial", 0)) == 1
		and is_equal_approx(float((arrived_records[0] as Dictionary).get(
			"progress", -1.0)), 1.0)
		and arrived_presenter._movement_label.text.contains("ROUTE 100%"),
		"an accepted route keeps one serial and reaches a visible 100% arrival terminal")

	presenter.free()
	forced_presenter.free()
	arrived_presenter.free()
	curved_presenter.free()


func _test_exact_rally_progress_liveness_binding() -> void:
	var loop := StretchPlaytestLoop.new()
	var observation := _observation("baseline")
	var cue := _movement_result_cue(
		"ground_1", 7, "progress", true, "")
	cue["progress"] = 0.4
	_add_cue(observation, cue)
	var subjects := ["portrait_aster", "portrait_peris", "portrait_endo"]
	var lineage := {
		"visible": true,
		"accepted": true,
		"presentation_serial": 7,
		"target_token": "ground_1",
		"subjects": subjects.duplicate(),
		"phase": "progress",
	}
	_check(is_equal_approx(loop._exact_visible_rally_progress(
		observation, lineage, "ground_1", subjects), 0.4),
		"Rally watchdog liveness reads the exact visible serial/target/subjects progress cue")
	var wrong_serial := lineage.duplicate(true)
	wrong_serial["presentation_serial"] = 8
	_check(loop._exact_visible_rally_progress(
		observation, wrong_serial, "ground_1", subjects) < 0.0,
		"an unrelated movement-result serial cannot renew Rally liveness")
	var wrong_subjects := subjects.duplicate()
	wrong_subjects.pop_back()
	_check(loop._exact_visible_rally_progress(
		observation, lineage, "ground_1", wrong_subjects) < 0.0,
		"a movement-result cue for a portrait subset cannot renew Rally All liveness")
	_add_cue(observation, cue.duplicate(true))
	_check(loop._exact_visible_rally_progress(
		observation, lineage, "ground_1", subjects) < 0.0,
		"duplicate exact movement-result cues are ambiguous and cannot renew Rally liveness")

	var accepted_lineage := lineage.duplicate(true)
	accepted_lineage["phase"] = "accepted"
	accepted_lineage["phases"] = ["accepted"]
	var phase_liveness := loop._exact_rally_phase_liveness_transition(
		{}, accepted_lineage, "ground_1", subjects)
	_check(not bool(phase_liveness.get("advanced", true))
		and int(phase_liveness.get("presentation_serial", 0)) == 7
		and int(phase_liveness.get("phase_rank", -1)) == 0,
		"the exact accepted phase establishes a lineage baseline without fabricating liveness")
	var foreign_progress := accepted_lineage.duplicate(true)
	foreign_progress["presentation_serial"] = 8
	foreign_progress["phase"] = "progress"
	foreign_progress["phases"] = ["accepted", "progress"]
	var foreign_result := loop._exact_rally_phase_liveness_transition(
		phase_liveness, foreign_progress, "ground_1", subjects)
	_check(not bool(foreign_result.get("advanced", true))
		and int(foreign_result.get("presentation_serial", 0)) == 7
		and int(foreign_result.get("phase_rank", -1)) == 0,
		"a different movement serial cannot renew accepted-route phase liveness")
	var progress_lineage := accepted_lineage.duplicate(true)
	progress_lineage["phase"] = "progress"
	progress_lineage["phases"] = ["accepted", "progress"]
	phase_liveness = loop._exact_rally_phase_liveness_transition(
		phase_liveness, progress_lineage, "ground_1", subjects)
	var last_physical_progress_msec := 900.0
	var progress_phase_msec := 1200.0
	var earliest_arrival_msec := 2401.0
	var stall_window_msec := \
		StretchPlaytestLoop.PLAYER_DISCOVERY_RALLY_INCOMPLETE_STABLE_SECONDS \
		* 1000.0
	var renewed_msec := progress_phase_msec \
		if bool(phase_liveness.get("advanced", false)) \
		else last_physical_progress_msec
	_check(bool(phase_liveness.get("advanced", false))
		and earliest_arrival_msec - last_physical_progress_msec \
			> stall_window_msec
		and earliest_arrival_msec - renewed_msec < stall_window_msec,
		"a sub-second Rally survives the presenter's 1.2s progress and 2.4s arrival timing")
	var repeated_progress := loop._exact_rally_phase_liveness_transition(
		phase_liveness, progress_lineage, "ground_1", subjects)
	_check(not bool(repeated_progress.get("advanced", true))
		and int(repeated_progress.get("phase_rank", -1)) == 1,
		"repeated same-phase presentation cannot indefinitely renew Rally liveness")
	var arrival_lineage := progress_lineage.duplicate(true)
	arrival_lineage["phase"] = "arrival"
	arrival_lineage["phases"] = ["accepted", "progress", "arrival"]
	phase_liveness = loop._exact_rally_phase_liveness_transition(
		phase_liveness, arrival_lineage, "ground_1", subjects)
	_check(bool(phase_liveness.get("advanced", false))
		and int(phase_liveness.get("phase_rank", -1)) == 2
		and str(phase_liveness.get("phase", "")) == "arrival",
		"only the same exact lineage advances from progress to the arrival terminal")

	var refused_lineage := {
		"visible": true,
		"accepted": false,
		"new_serial_count": 1,
		"presentation_serial": 9,
		"target_token": "ground_1",
		"subjects": subjects.duplicate(),
		"phase": "refused",
		"phases": ["refused"],
		"reason": "RALLY REFUSED // NO COMPLETE ROUTE FOR ASTER.",
	}
	var refusal_liveness := loop._exact_rally_phase_liveness_transition(
		{}, refused_lineage, "ground_1", subjects)
	var repeated_refusal := loop._exact_rally_phase_liveness_transition(
		refusal_liveness, refused_lineage, "ground_1", subjects)
	var refusal_renewals := loop._exact_rally_liveness_renewal_reasons(
		true, refusal_liveness, refused_lineage, "ground_1", subjects, false)
	var repeated_refusal_renewals := loop._exact_rally_liveness_renewal_reasons(
		true, repeated_refusal, refused_lineage, "ground_1", subjects, false)
	var accepted_baseline := loop._exact_rally_phase_liveness_transition(
		{}, accepted_lineage, "ground_1", subjects)
	var accepted_motion_renewals := loop._exact_rally_liveness_renewal_reasons(
		true, accepted_baseline, accepted_lineage, "ground_1", subjects, false)
	_check(bool(refusal_liveness.get("advanced", false))
		and str(refusal_liveness.get("phase", "")) == "refused"
		and int(refusal_liveness.get("presentation_serial", 0)) == 9
		and not bool(repeated_refusal.get("advanced", true))
		and refusal_renewals == ["rally_exact_phase_advance_refused"]
		and repeated_refusal_renewals.is_empty()
		and accepted_motion_renewals == ["rally_bound_body_motion"],
		("the first exact visible Rally refusal renews causal liveness once; "
		+ "camera drift cannot add a second credit, replaying the same serial is "
		+ "deduplicated, and exact accepted motion remains causal"))
	var unreasoned_refusal := refused_lineage.duplicate(true)
	unreasoned_refusal["reason"] = ""
	var wrong_target_refusal := refused_lineage.duplicate(true)
	wrong_target_refusal["target_token"] = "ground_2"
	_check(not bool(loop._exact_rally_phase_liveness_transition(
		{}, unreasoned_refusal, "ground_1", subjects).get("advanced", true))
		and not bool(loop._exact_rally_phase_liveness_transition(
			{}, wrong_target_refusal, "ground_1", subjects).get("advanced", true)),
		"only a reasoned refusal bound to the exact target can renew liveness")

	_check(not loop._rally_watchdog_may_preempt_next_capture(true)
		and loop._rally_watchdog_may_preempt_next_capture(false),
		("an already-rendered immediate Rally capture is consumed before watchdog "
		+ "abort; only future sampling may be preempted"))
	var refusal_settle := {
		"observation": _observation("baseline", 10),
		"observation_samples": [],
	}
	var sealed_refusal := loop._seal_refused_rally_terminal_capture(
		refusal_settle, _observation("baseline", 11))
	var stale_refusal := loop._seal_refused_rally_terminal_capture(
		refusal_settle, _observation("baseline", 10))
	_check(bool(sealed_refusal.get("refusal_terminal_capture_fresh", false))
		and int((sealed_refusal.get("observation", {}) as Dictionary).get(
			"capture_serial", 0)) == 11
		and (sealed_refusal.get("observation_samples", []) as Array).size() == 1
		and int(((sealed_refusal.get("observation_samples", []) as Array)[0]
			as Dictionary).get("capture_serial", 0)) == 10
		and not bool(stale_refusal.get(
			"refusal_terminal_capture_fresh", true)),
		("the exact refusal capture becomes a chronological sample and only a new "
		+ "post-park observation may seal the terminal"))
	var observed_drift := {"aster": true, "peris": true, "endo": true}
	var refused_causal_motion := loop._causal_rally_moved_members(
		observed_drift, refused_lineage)
	var accepted_transform_samples := {}
	for moved_member_v in observed_drift.keys():
		accepted_transform_samples[str(moved_member_v)] = {
			"logical_displacement": 1.0,
			"render_displacement": 1.0,
			"global_position_displacement": 1.0,
			"global_transform_displacement": 1.0,
		}
	var accepted_causal_motion := loop._causal_rally_moved_members(
		observed_drift, arrival_lineage, accepted_transform_samples)
	_check(refused_causal_motion.is_empty()
		and accepted_causal_motion.size() == observed_drift.size(),
		("a refusal reports zero causally moved members while an accepted lineage "
		+ "retains its observed body-motion roster"))
	var refused_members := ["aster", "peris", "endo"]
	var stationary_samples := loop._new_generated_in_flight_transform_samples(
		refused_members)
	var member_body_tokens := {}
	var member_index := 0
	for member_v in refused_members:
		var member := str(member_v)
		var entry := stationary_samples[member] as Dictionary
		var position := [float(member_index), 0.45, 0.0]
		entry["count"] = 2
		for endpoint_key in ["first_logical", "last_logical", "first_render",
				"last_render", "first_global_position", "last_global_position",
				"first_global_transform_origin", "last_global_transform_origin"]:
			entry[endpoint_key] = position.duplicate()
		member_body_tokens[member] = "body_%s" % member
		member_index += 1
	var refused_motion_evidence := {
		"visible": false,
		"intended_members": refused_members.duplicate(),
		"member_body_tokens": member_body_tokens,
		"moved_members": [],
		"presented_movement_members": [],
		"concealed_progress_members": [],
		"concealed_members": {},
		"concealed_portrait_tokens": [],
		"subjects": [],
		"transform_samples": stationary_samples,
	}
	var hidden_mutation_evidence := refused_motion_evidence.duplicate(true)
	var mutated_aster := ((hidden_mutation_evidence.get(
		"transform_samples", {}) as Dictionary).get("aster", {}) as Dictionary)
	mutated_aster["last_logical"] = [1.0, 0.45, 0.0]
	var refused_presence_before := _observation("baseline", 20)
	var refused_presence_after := _observation("baseline", 21)
	_check(loop._generated_refused_rally_motion_evidence_valid(
		refused_motion_evidence, refused_members,
		refused_presence_before, [], refused_presence_after)
		and not loop._generated_refused_rally_motion_evidence_valid(
			hidden_mutation_evidence, refused_members,
			refused_presence_before, [], refused_presence_after),
		("a zero-event refused Rally requires stationary full-XYZ presenter parity; "
		+ "a hidden terminal mutation is rejected even when its cached displacement "
		+ "dishonestly remains zero"))

	var rally_receipt := {
		"input_issued": true,
		"input_event_count": 3,
		"input_sequence_before": 0,
		"input_sequence_after": 3,
		"target_screen": [1278, 360],
		"input_events": [
			{"kind": "pointer_move", "issued": true, "sequence": 1},
			{"kind": "pointer_button", "issued": true, "sequence": 2},
			{"kind": "pointer_button", "issued": true, "sequence": 3},
		],
		"pointer_parked_after_gesture": true,
		"pointer_park_receipt": {
			"kind": "park_pointer",
			"accepted": true,
			"player_reproducible": true,
			"input_issued": true,
			"input_sequence_before": 3,
			"input_sequence_after": 4,
			"input_event_count": 1,
			"from_screen": [1278, 360],
			"to_screen": [640, 360],
			"input_events": [
				{
					"kind": "pointer_move",
					"issued": true,
					"sequence": 4,
					"button_mask": 0,
					"position": [640, 360],
				},
			],
		},
	}
	var merged_rally_receipt := loop._merge_generated_auxiliary_input_receipts(
		rally_receipt)
	var discontinuous_receipt := rally_receipt.duplicate(true)
	(discontinuous_receipt["pointer_park_receipt"] as Dictionary)[
		"input_sequence_before"] = 8
	var refused_merge := loop._merge_generated_auxiliary_input_receipts(
		discontinuous_receipt)
	var wrong_park_center := merged_rally_receipt.duplicate(true)
	(wrong_park_center["pointer_park_receipt"] as Dictionary)["to_screen"] = [1, 1]
	var wrong_park_range := merged_rally_receipt.duplicate(true)
	(wrong_park_range["pointer_park_receipt"] as Dictionary)[
		"input_sequence_before"] = 2
	var wrong_park_origin := merged_rally_receipt.duplicate(true)
	(wrong_park_origin["pointer_park_receipt"] as Dictionary)["from_screen"] = [12, 12]
	var wrong_event_position := merged_rally_receipt.duplicate(true)
	(((wrong_event_position["pointer_park_receipt"] as Dictionary).get(
		"input_events", []) as Array)[0] as Dictionary)["position"] = [1, 1]
	var unmerged_interaction_receipt := rally_receipt.duplicate(true)
	unmerged_interaction_receipt.erase("pointer_parked_after_gesture")
	unmerged_interaction_receipt["pointer_parked_after_click"] = true
	var merged_interaction_receipt := loop._merge_generated_auxiliary_input_receipts(
		unmerged_interaction_receipt)
	_check(int(merged_rally_receipt.get("input_event_count", 0)) == 4
		and int(merged_rally_receipt.get("input_sequence_after", 0)) == 4
		and (merged_rally_receipt.get("input_events", []) as Array).size() == 4
		and loop._generated_rally_pointer_park_valid(
			merged_rally_receipt, _observation("baseline"))
		and not loop._generated_rally_pointer_park_valid(
			wrong_park_center, _observation("baseline"))
		and not loop._generated_rally_pointer_park_valid(
			wrong_park_range, _observation("baseline"))
		and not loop._generated_rally_pointer_park_valid(
			wrong_park_origin, _observation("baseline"))
		and not loop._generated_rally_pointer_park_valid(
			wrong_event_position, _observation("baseline"))
		and not loop._generated_interaction_pointer_park_valid(
			unmerged_interaction_receipt, _observation("baseline"))
		and loop._generated_interaction_pointer_park_valid(
			merged_interaction_receipt, _observation("baseline"))
		and int(merged_interaction_receipt.get("input_event_count", 0)) == 4
		and int(merged_interaction_receipt.get(
			"input_sequence_after", 0)) == 4
		and int(refused_merge.get("input_event_count", 0)) == 3
		and int(refused_merge.get("input_sequence_after", 0)) == 3,
		("safe-centre MouseMotion is hash-covered by its Rally receipt and bound "
		+ "to the clicked target, nested sequence range, and actual event position; "
		+ "ordinary interactions must merge the same packet before trace emission, "
		+ "and a discontinuous auxiliary packet remains visibly unmerged"))


func _test_input_sequence_progression() -> void:
	var generated_loop := StretchPlaytestLoop.new()
	var generated_previous := {
		"input_receipt": {
			"boundary": "keyboard_pointer",
			"input_issued": true,
			"input_sequence_after": 3,
		},
		"observation_after": {"capture_serial": 8, "tick": 4.0},
	}
	var generated_contiguous := {
		"input_receipt": {
			"boundary": "keyboard_pointer",
			"input_issued": true,
			"input_sequence_before": 3,
		},
		"observation_before": {"capture_serial": 9, "tick": 4.0},
	}
	var generated_mutation := generated_contiguous.duplicate(true)
	(generated_mutation["input_receipt"] as Dictionary)[
		"input_sequence_before"] = 4
	generated_mutation["observation_before"] = {
		"capture_serial": 8,
		"tick": 3.0,
	}
	_check(generated_loop._generated_decision_progression_reasons(
		[generated_previous], generated_contiguous).is_empty()
		and generated_loop._generated_decision_progression_reasons(
			[generated_previous], generated_mutation) == [
				"input_event_sequence_gap_across_decisions",
				"observation_capture_not_monotonic_across_decisions",
				"observation_tick_regressed_across_decisions",
			],
		("the generated report verifier applies the canonical cross-decision input "
		+ "and observation ledger instead of validating records in isolation"))

	var first_gap_trace := Trace.new()
	first_gap_trace.begin(_scratch.path_join("first_input_gap.jsonl"),
		_run_metadata("native", "eazy_speezy", 0, "first_input_gap"))
	var first_gap := _append_eazy_fixture(first_gap_trace, 1, 4)
	_check(not bool(first_gap.get("ok", true)) and str(first_gap.get(
		"error", "")).contains("input_event_sequence_gap_across_decisions"),
		"first active input range must start at sequence zero")
	first_gap_trace.abort()

	var contiguous_trace := Trace.new()
	contiguous_trace.begin(_scratch.path_join("contiguous_input.jsonl"),
		_run_metadata("native", "eazy_speezy", 0, "contiguous_input"))
	var contiguous_first := _append_eazy_fixture(contiguous_trace, 1, 0)
	var contiguous_second := _append_eazy_fixture(contiguous_trace, 4, 3)
	_check(bool(contiguous_first.get("ok", false))
		and bool(contiguous_second.get("ok", false)),
		"consecutive active receipts accept exact prior-after to next-before continuity")
	contiguous_trace.abort()
	var reset_capture_trace := Trace.new()
	reset_capture_trace.begin(_scratch.path_join("reset_capture.jsonl"),
		_run_metadata("native", "eazy_speezy", 0, "reset_capture"))
	var reset_capture_first := _append_eazy_fixture(reset_capture_trace, 1, 0)
	var reset_capture_second := _append_eazy_fixture(reset_capture_trace, 1, 3)
	_check(bool(reset_capture_first.get("ok", false))
		and not bool(reset_capture_second.get("ok", true))
		and str(reset_capture_second.get("error", "")).contains(
			"observation_capture_not_monotonic_across_decisions"),
		"observation capture serial cannot reset or replay across decisions")
	reset_capture_trace.abort()

	var invalid_trace := Trace.new()
	invalid_trace.begin(_scratch.path_join("invalid_input_progression.jsonl"),
		_run_metadata("native", "eazy_speezy", 0, "invalid_input_progression"))
	var initial := _append_eazy_fixture(invalid_trace, 1, 0)
	var gap := _append_eazy_fixture(invalid_trace, 4, 4)
	var reused := _append_eazy_fixture(invalid_trace, 4, 2)
	_check(bool(initial.get("ok", false)) and not bool(gap.get("ok", true))
		and str(gap.get("error", "")).contains(
			"input_event_sequence_gap_across_decisions")
		and not bool(reused.get("ok", true)) and str(reused.get(
			"error", "")).contains("input_event_sequence_reused_across_decisions"),
		"input sequence gaps and reuse both fail across decisions")
	invalid_trace.abort()


func _append_eazy_fixture(trace, capture_start: int,
		sequence_before: int) -> Dictionary:
	var receipt := _interaction_receipt(sequence_before)
	receipt["observation_before_capture_serial"] = capture_start
	receipt["first_post_input_capture_serial"] = capture_start + 1
	return trace.append_decision(
		_observation("baseline", capture_start),
		_observation("eazy_success", capture_start + 2),
		[_observation("eazy_success", capture_start + 1)],
		_rationale(), _eazy_decision(), receipt, _context("sequence"), {})


func _evidence_reasons(record: Dictionary) -> String:
	return str(Trace.classify_evidence(record).get("rejection_reasons", []))


func _set_movement_subjects(record: Dictionary, subjects: Array) -> void:
	for observation_key in ["observation_before", "observation_samples",
			"observation_after"]:
		var observations: Array = record.get(observation_key, []) \
			if record.get(observation_key, null) is Array \
			else [record.get(observation_key, {})]
		for observation_value in observations:
			if not (observation_value is Dictionary):
				continue
			for cue_value in ((observation_value as Dictionary).get(
					"state", {}) as Dictionary).get("cues", []):
				if cue_value is Dictionary and str((cue_value as Dictionary).get(
						"kind", "")) == "movement_result":
					(cue_value as Dictionary)["subjects"] = subjects.duplicate()


func _set_movement_targets(record: Dictionary, target_token: String) -> void:
	for observation_key in ["observation_before", "observation_samples",
			"observation_after"]:
		var observations: Array = record.get(observation_key, []) \
			if record.get(observation_key, null) is Array \
			else [record.get(observation_key, {})]
		for observation_value in observations:
			if not (observation_value is Dictionary):
				continue
			for cue_value in ((observation_value as Dictionary).get(
					"state", {}) as Dictionary).get("cues", []):
				if cue_value is Dictionary and str((cue_value as Dictionary).get(
						"kind", "")) == "movement_result":
					(cue_value as Dictionary)["target_token"] = target_token


func _test_candidate_target_binding() -> void:
	var base := _observation("target_binding")
	var rally_decision := _dean_decision()
	var chosen := _dean_candidate()
	_check(Distiller.validate_candidate_target_binding(chosen, rally_decision, base).is_empty(),
		"chosen_visible_ground binds the executed visible ground token")
	var ladder_candidate := chosen.duplicate(true)
	(ladder_candidate["action"] as Dictionary)["target_ref"] = "matching_visible_ladder_route"
	_check(Distiller.validate_candidate_target_binding(ladder_candidate,
		rally_decision, base).is_empty(),
		"matching_visible_ladder_route recomputes the token's visible ladder annotation")
	var shelter_candidate := chosen.duplicate(true)
	(shelter_candidate["action"] as Dictionary)["target_ref"] = \
		"nearest_visible_ground_to_shelter_label"
	_check(Distiller.validate_candidate_target_binding(shelter_candidate,
		rally_decision, base).is_empty(),
		"nearest shelter ground target is recomputed from visible screens")
	var affordance_only_shelter := _observation("baseline")
	var affordance_state := affordance_only_shelter.get("state", {}) as Dictionary
	affordance_state["affordances"] = [
		{"token": "ground_far", "kind": "move", "verb": "MOVE",
			"consequence": "WALK ROUTE", "screen": [496, 216]},
		{"token": "ground_near", "kind": "move", "verb": "MOVE",
			"consequence": "WALK ROUTE", "screen": [496, 288]},
		{"token": "shelter_affordance", "kind": "interact",
			"verb": "REST PARTY", "consequence": "Shelter",
			"screen": [552, 320]},
		{"token": "unrelated_rest_affordance", "kind": "interact",
			"verb": "RESTORE ITEM", "consequence": "Repair carried gear",
			"screen": [496, 216]},
		{"token": "rest_notes_affordance", "kind": "interact",
			"verb": "READ REST NOTES", "consequence": "Read a maintenance log",
			"screen": [496, 288]},
	]
	affordance_state["viewport_bins"] = {
		"middle_center": ["ground_far", "ground_near"],
		"interact_visible": [
			"shelter_affordance", "unrelated_rest_affordance",
			"rest_notes_affordance"],
	}
	affordance_state["visible_affordance_verbs"] = [
		"MOVE", "READ REST NOTES", "REST PARTY", "RESTORE ITEM"]
	affordance_state["visible_affordance_consequences"] = [
		"Repair carried gear", "Shelter", "WALK ROUTE"]
	var nearest_tokens := Distiller.nearest_ground_tokens_to_visible_label(
		affordance_only_shelter, ["SHELTER", "REST"], ["REST PARTY"])
	var eazy_player := PersonaPlayer.new()
	eazy_player._persona = "eazy_speezy"
	var shelter_choice := eazy_player.call(
		"_choose_visible_shelter_formation_surface",
		affordance_only_shelter) as Dictionary
	var executed_shelter_decision := rally_decision.duplicate(true)
	(executed_shelter_decision["target"] as Dictionary)["token"] = str(
		shelter_choice.get("target_token", ""))
	var exact_shelter_candidate := shelter_choice.get(
		"learning_candidate", {}) as Dictionary
	_check(nearest_tokens == ["ground_near"]
		and str(shelter_choice.get("target_token", "")) == "shelter_affordance"
		and Distiller.validate_candidate_target_binding(
			exact_shelter_candidate, executed_shelter_decision,
			affordance_only_shelter).is_empty(),
		"the shelter Rally chooser and distiller bind the same exact visible REST PARTY interaction token despite REST-like decoys")
	(executed_shelter_decision["target"] as Dictionary)["token"] = "ground_near"
	_check(not Distiller.validate_candidate_target_binding(
		exact_shelter_candidate, executed_shelter_decision,
		affordance_only_shelter).is_empty(),
		"the exact shelter-surface selector rejects a co-visible ground token")
	var no_exact_anchor := affordance_only_shelter.duplicate(true)
	for affordance_value in ((no_exact_anchor.get("state", {}) as Dictionary).get(
			"affordances", []) as Array):
		if affordance_value is Dictionary and str((affordance_value as Dictionary).get(
				"token", "")) == "shelter_affordance":
			(affordance_value as Dictionary)["verb"] = "WAIT HERE"
			(affordance_value as Dictionary)["consequence"] = "Waiting point"
	_check(Distiller.nearest_ground_tokens_to_visible_label(
		no_exact_anchor, ["SHELTER", "REST"], ["REST PARTY"]).is_empty()
		and (eazy_player.call("_choose_visible_shelter_formation_surface",
			no_exact_anchor) as Dictionary).is_empty()
		and not Distiller.validate_candidate_target_binding(
			exact_shelter_candidate, {
				"verb": "rally", "target": {"token": "shelter_affordance"},
			}, no_exact_anchor).is_empty(),
		"an exact shelter selector fails closed when only unrelated REST-like affordances remain")
	var tied_shelter := affordance_only_shelter.duplicate(true)
	var tied_state := tied_shelter.get("state", {}) as Dictionary
	var tied_affordances := tied_state.get("affordances", []) as Array
	for affordance_value in tied_affordances:
		if affordance_value is Dictionary and str((affordance_value as Dictionary).get(
				"token", "")) == "ground_far":
			(affordance_value as Dictionary)["token"] = "ground_right"
			(affordance_value as Dictionary)["screen"] = [608, 288]
		elif affordance_value is Dictionary and str((affordance_value as Dictionary).get(
				"token", "")) == "ground_near":
			(affordance_value as Dictionary)["token"] = "ground_left"
	tied_affordances.reverse()
	tied_state["viewport_bins"] = {
		"middle_center": ["ground_right", "ground_left"],
		"interact_visible": [
			"rest_notes_affordance", "unrelated_rest_affordance",
			"shelter_affordance"],
	}
	var tied_tokens := Distiller.nearest_ground_tokens_to_visible_label(
		tied_shelter, ["SHELTER", "REST"], ["REST PARTY"])
	_check(tied_tokens == ["ground_left", "ground_right"],
		("The retained legacy nearest-ground verifier preserves strict equal-distance "
		+ "ties in stable token order after affordance reorder"))
	eazy_player.free()
	var hide_observation := _observation("hide_control")
	var hide_candidate := {
		"condition": {"path": "cues", "op": "exists", "value": true},
		"action": {"verb": "toggle_instructions",
			"target_ref": "advertised_visible_hide_control"},
	}
	var hide_decision := {"verb": "toggle_instructions", "intended_subjects": [],
		"target": {"token": "visible_h_hide_control"}}
	_check(Distiller.validate_candidate_target_binding(
		hide_candidate, hide_decision, hide_observation).is_empty(),
		"advertised Hide setup target binds a visible instruction control")
	var roster_candidate := {
		"condition": {"path": "hud.portraits", "op": "exists", "value": true},
		"action": {"verb": "select_party", "target_ref": "visible_hud_roster"},
	}
	var roster_decision := {"verb": "select_party", "intended_subjects": ["a", "p", "e"],
		"target": {"token": "hud_portraits"}}
	_check(Distiller.validate_candidate_target_binding(
		roster_candidate, roster_decision, base).is_empty(),
		"visible HUD roster setup target binds current unselected portraits")
	var wait_candidate := {
		"condition": {"path": "cues", "op": "exists", "value": true},
		"action": {"verb": "wait", "target_ref": "announced_visible_consequence"},
	}
	var wait_decision := {"verb": "wait", "intended_subjects": [],
		"target": {"token": "visible_announced_mid_crossing"}}
	_check(Distiller.validate_candidate_target_binding(wait_candidate,
		wait_decision, _observation("announced_wait")).is_empty(),
		"announced wait binds a currently visible consequence cue")
	var unknown := chosen.duplicate(true)
	(unknown["action"] as Dictionary)["target_ref"] = "trust_me_target"
	_check(not Distiller.validate_candidate_target_binding(unknown,
		rally_decision, base).is_empty(),
		"unknown candidate target references fail closed")
	var wrong_decision := rally_decision.duplicate(true)
	(wrong_decision["target"] as Dictionary)["token"] = "shelter_1"
	_check(not Distiller.validate_candidate_target_binding(ladder_candidate,
		wrong_decision, base).is_empty(),
		"verb equality cannot hide a target token that does not match the candidate")


func _write_complete_cohort(platform: String, suffix: String,
		eazy_candidate_override: Dictionary = {}) -> Array[String]:
	var paths: Array[String] = []
	for persona in ["dean_takahashi", "eazy_speezy"]:
		for repeat_index in [0, 1]:
			paths.append(_write_persona_trace(platform, persona, repeat_index,
				"%s_%s_%d" % [suffix, persona, repeat_index],
				eazy_candidate_override))
	return paths


func _write_persona_trace(platform: String, persona: String,
		repeat_index: int, trace_id: String,
		eazy_candidate_override: Dictionary = {}) -> String:
	var path := _scratch.path_join("%s.jsonl" % trace_id)
	var trace := Trace.new()
	var begun := trace.begin(path,
		_run_metadata(platform, persona, repeat_index, trace_id))
	if not bool(begun.get("ok", false)):
		push_error(str(begun.get("error", "trace begin failed")))
		return ""
	var appended := {}
	if persona == "dean_takahashi":
		var dean_receipt := _rally_receipt()
		dean_receipt["observation_before_capture_serial"] = 1
		dean_receipt["first_post_input_capture_serial"] = 2
		appended = trace.append_decision(
			_observation("baseline", 1), _observation("arrival", 5),
			[_observation("warning", 2), _observation("active", 3),
				_observation("arrival", 4)],
			_rationale(), _dean_decision(), dean_receipt,
			_context(trace_id), _dean_candidate())
	else:
		var eazy_receipt := _interaction_receipt()
		eazy_receipt["observation_before_capture_serial"] = 1
		eazy_receipt["first_post_input_capture_serial"] = 2
		var eazy_candidate := eazy_candidate_override.duplicate(true) \
			if not eazy_candidate_override.is_empty() else _eazy_candidate()
		appended = trace.append_decision(
			_observation("baseline", 1), _observation("eazy_success", 3),
			[_observation("eazy_success", 2)], _rationale(), _eazy_decision(),
			eazy_receipt, _context(trace_id), eazy_candidate)
	if not bool(appended.get("ok", false)):
		push_error(str(appended.get("error", "trace append failed")))
		trace.abort()
		return ""
	var finished := trace.finish({"trace_complete": true, "diagnostic": trace_id})
	if not bool(finished.get("ok", false)) \
			or not bool((finished.get("summary", {}) as Dictionary).get(
				"trace_complete", false)):
		push_error(str(finished.get("error", "trace finish failed")))
		return ""
	return path


func _seal_cohort(paths: Array, invocation_id: String,
		failed_member_index := -1) -> Array:
	var pre_documents: Array = []
	for path_value in paths:
		pre_documents.append(Trace.read_trace(str(path_value)))
	var manifest := Trace.make_invocation_manifest(pre_documents, invocation_id)
	for index in range(paths.size()):
		var passed := index != failed_member_index
		var receipt := Trace.make_validation_receipt(
			pre_documents[index] as Dictionary, invocation_id, passed, 7,
			0 if passed else 1, manifest)
		var sealed := Trace.append_validation(str(paths[index]), receipt)
		if not bool(sealed.get("ok", false)):
			push_error(str(sealed.get("error", "validation append failed")))
	var documents: Array = []
	for path_value in paths:
		documents.append(Trace.read_trace(str(path_value)))
	return documents


func _test_preview_policy_supersession(native_documents: Array) -> void:
	var canonical_library_path := "res://data/playthroughs/decision_library.json"
	var canonical_absolute := ProjectSettings.globalize_path(canonical_library_path)
	var custom_library_path := "res://data/playthroughs/custom_input.json"
	var custom_absolute := ProjectSettings.globalize_path(custom_library_path)
	var canonical_alias_reasons := Distiller.validate_preview_output_path(
		canonical_library_path, canonical_absolute, canonical_library_path)
	var input_alias_reasons := Distiller.validate_preview_output_path(
		custom_library_path, custom_absolute, canonical_library_path)
	var relative_alias_reasons := Distiller.validate_preview_output_path(
		custom_library_path, "data/playthroughs/decision_library.json",
		canonical_library_path)
	var safe_preview_reasons := Distiller.validate_preview_output_path(
		canonical_library_path, "user://decision_library.preview.json",
		canonical_library_path)
	var cli_source := FileAccess.get_file_as_string(
		"res://tools/distill_persona_decision_library.gd")
	_check(canonical_alias_reasons.has("preview_output_aliases_input_library")
		and canonical_alias_reasons.has(
			"preview_output_aliases_canonical_library")
		and input_alias_reasons.has("preview_output_aliases_input_library")
		and relative_alias_reasons.has(
			"preview_output_aliases_canonical_library")
		and safe_preview_reasons.is_empty()
		and cli_source.contains("Distiller.validate_preview_output_path(")
		and cli_source.contains("if bool(options.get(\"in_place\", false))")
		and cli_source.contains("else Distiller.distill_preview("),
		"preview CLI normalizes res, relative, and absolute aliases; only explicit in-place may target its input or canonical library")

	var input_library := _preview_old_proxy_library()
	var input_hash := Trace.canonical_hash(input_library)
	var ordinary := Distiller.distill(input_library, native_documents, 2)
	var ordinary_node := _node(ordinary, "eazy_rest_visible_shelter")
	_check(str(((ordinary_node.get("policy", {}) as Dictionary).get(
		"action", {}) as Dictionary).get("target_ref", "")) \
			== "nearest_visible_ground_to_shelter_label"
		and str(ordinary.get("rejected_evidence", [])).contains(
			"candidate_rule_conflicts_with_existing_node")
		and not ordinary_node.has("superseded_policy_history"),
		"ordinary distillation remains conflict-rejecting and cannot supersede a policy")

	var preview := Distiller.distill_preview(input_library, native_documents, 2)
	var preview_node := _node(preview, "eazy_rest_visible_shelter")
	var preview_policy := preview_node.get("policy", {}) as Dictionary
	var preview_evidence := preview_node.get("evidence", {}) as Dictionary
	var history: Array = preview_node.get("superseded_policy_history", []) \
		if preview_node.get("superseded_policy_history", null) is Array else []
	var archive := history[0] as Dictionary if history.size() == 1 else {}
	var archived_policy := archive.get("policy", {}) as Dictionary
	var archived_evidence := archive.get("evidence", {}) as Dictionary
	var archived_provenance: Array = archived_evidence.get("provenance", []) \
		if archived_evidence.get("provenance", null) is Array else []
	var current_manifest_hash := str((((_document_for_persona(
		native_documents, "eazy_speezy").get("validation", {}) as Dictionary).get(
		"invocation_manifest_hash", ""))))
	_check(str((preview_policy.get("action", {}) as Dictionary).get(
		"target_ref", "")) == "matching_visible_interaction"
		and str(preview_node.get("rule", "")) == str(_eazy_candidate().get("rule", ""))
		and str(preview_node.get("status", "")) == "validated"
		and bool(preview_node.get("eligible_for_automation", false))
		and int(preview_evidence.get("support_count", -1)) == 2
		and int(preview_evidence.get("distinct_run_count", -1)) == 2
		and int(preview_evidence.get("distinct_trace_count", -1)) == 2
		and not str(preview.get("rejected_evidence", [])).contains(
			"candidate_rule_conflicts_with_existing_node")
		and not str(preview.get("rejected_evidence", [])).contains(
			"policy_conflicts_with_existing_node"),
		"preview installs one exact visible target policy from two independent current runs without pooling old support")
	_check(history.size() == 1
		and str(archive.get("schema", "")) \
			== Distiller.PREVIEW_SUPERSESSION_ARCHIVE_SCHEMA
		and str(archive.get("reason", "")) == "monotonic_target_precision"
		and str((archived_policy.get("action", {}) as Dictionary).get(
			"target_ref", "")) == "nearest_visible_ground_to_shelter_label"
		and int(archived_evidence.get("support_count", -1)) == 11
		and archived_provenance.size() == 2
		and str((archived_provenance[0] as Dictionary).get("record_hash", "")) \
			< str((archived_provenance[1] as Dictionary).get("record_hash", ""))
		and archive.get("support_invocation_manifest_hashes", []) \
			== [current_manifest_hash],
		"preview deep-archives the prior rule, policy, status, personas, and canonically sorted provenance")
	_check(Trace.canonical_hash(input_library) == input_hash,
		"preview distillation does not mutate its input library")
	var reversed_documents := native_documents.duplicate()
	reversed_documents.reverse()
	var reversed_preview := Distiller.distill_preview(
		_preview_old_proxy_library(), reversed_documents, 2)
	_check(Trace.canonical_equal(preview, reversed_preview),
		"preview supersession and archived provenance are deterministic across trace input reorder")
	((input_library.get("nodes", []) as Array)[0] as Dictionary)["rule"] = \
		"mutated caller-owned rule"
	((preview_policy.get("action", {}) as Dictionary)["target_ref"]) = \
		"mutated active policy"
	_check(str(archive.get("rule", "")) == "Old nearest-ground shelter proxy."
		and str((archived_policy.get("action", {}) as Dictionary).get(
			"target_ref", "")) == "nearest_visible_ground_to_shelter_label",
		"archived policy state is deep-copied from both caller input and active successor")

	var registry_issues := Distiller.validate_target_ref_precision_registry()
	var exact_contract := (Distiller.TARGET_REF_PRECISION_CONTRACTS.get(
		"matching_visible_interaction", {}) as Dictionary).duplicate(true)
	var wrong_kind_contract := exact_contract.duplicate(true)
	wrong_kind_contract["target_kind"] = "move"
	var wrong_mode_contract := exact_contract.duplicate(true)
	wrong_mode_contract["binding_mode"] = "nearest_visible_proxy"
	var unknown_binder_issues := Distiller.validate_target_ref_precision_contract(
		"unrecognized_visible_target", exact_contract)
	_check(registry_issues.is_empty()
		and Distiller.validate_target_ref_precision_contract(
			"matching_visible_interaction", wrong_kind_contract).has(
				"binding_mode_target_kind_mismatch")
		and not Distiller.validate_target_ref_precision_contract(
			"matching_visible_interaction", wrong_mode_contract).is_empty()
		and unknown_binder_issues.has("runtime_target_binder_missing"),
		"target precision registry binding_mode and target_kind are executable contracts, not dead metadata")

	var old_node := ((_preview_old_proxy_library().get("nodes", []) as Array)[0]
		as Dictionary)
	var eazy_run := (_document_for_persona(
		native_documents, "eazy_speezy").get("run", {}) as Dictionary)
	var exact_candidate := _eazy_candidate()
	_check(Distiller.validate_preview_supersession_shape(
		old_node, exact_candidate, eazy_run).is_empty(),
		"exact visible interaction is a schema-verifiable monotonic refinement of the nearest-ground proxy")
	var changed_verb := exact_candidate.duplicate(true)
	(changed_verb["action"] as Dictionary)["verb"] = "rally"
	var changed_expected := exact_candidate.duplicate(true)
	(changed_expected["expected"] as Dictionary)["value"] = false
	var changed_scope := exact_candidate.duplicate(true)
	changed_scope["scope"] = "mechanic"
	var changed_priority := exact_candidate.duplicate(true)
	changed_priority["priority"] = 71
	var changed_persona_run := eazy_run.duplicate(true)
	changed_persona_run["persona"] = "dean_takahashi"
	var multi_owner_node := old_node.duplicate(true)
	multi_owner_node["personas"] = ["eazy_speezy", "dean_takahashi"]
	var changed_anchor := exact_candidate.duplicate(true)
	(changed_anchor["condition"] as Dictionary)["value"] = "LEAVE BASIN"
	var changed_predicate := exact_candidate.duplicate(true)
	changed_predicate["condition"] = {"all": [
		exact_candidate.get("condition", {}).duplicate(true),
		{"path": "hud.selected_count", "op": "eq", "value": 3},
	]}
	var equal_target := exact_candidate.duplicate(true)
	(equal_target["action"] as Dictionary)["target_ref"] = \
		"nearest_visible_ground_to_shelter_label"
	equal_target["condition"] = _preview_old_proxy_condition()
	var unknown_target := exact_candidate.duplicate(true)
	(unknown_target["action"] as Dictionary)["target_ref"] = \
		"schema_declared_but_not_executable"
	var added_proxy_guard := exact_candidate.duplicate(true)
	added_proxy_guard["condition"] = _preview_old_proxy_condition()
	((((added_proxy_guard["condition"] as Dictionary).get("all", []) as Array)[1]
		as Dictionary).get("any", []) as Array).append({
		"path": "viewport_bins.secret.0", "op": "exists", "value": true})
	var retained_proxy_guards := exact_candidate.duplicate(true)
	retained_proxy_guards["condition"] = _preview_old_proxy_condition()
	var partial_proxy_guard := exact_candidate.duplicate(true)
	partial_proxy_guard["condition"] = {"all": [
		exact_candidate.get("condition", {}).duplicate(true),
		{"path": "viewport_bins.top_center.0", "op": "exists", "value": true},
	]}
	var regrouped_proxy_guards := exact_candidate.duplicate(true)
	var regrouped_children: Array = [
		exact_candidate.get("condition", {}).duplicate(true)]
	for guard_value in ((_preview_old_proxy_condition().get(
			"all", []) as Array)[1] as Dictionary).get("any", []):
		regrouped_children.append((guard_value as Dictionary).duplicate(true))
	regrouped_proxy_guards["condition"] = {"all": regrouped_children}
	var guardless_old_node := old_node.duplicate(true)
	((guardless_old_node.get("policy", {}) as Dictionary)["condition"]) = \
		exact_candidate.get("condition", {}).duplicate(true)
	_check(Distiller.validate_preview_supersession_shape(
		old_node, changed_verb, eazy_run).has("action_verb_changed")
		and Distiller.validate_preview_supersession_shape(
			old_node, changed_expected, eazy_run).has("expected_outcome_changed")
		and Distiller.validate_preview_supersession_shape(
			old_node, changed_scope, eazy_run).has("policy_scope_changed")
		and Distiller.validate_preview_supersession_shape(
			old_node, changed_priority, eazy_run).has("policy_priority_changed")
		and Distiller.validate_preview_supersession_shape(
			old_node, exact_candidate, changed_persona_run).has(
				"candidate_persona_is_not_owned_by_existing_node")
		and Distiller.validate_preview_supersession_shape(
			multi_owner_node, exact_candidate, eazy_run).has(
				"existing_node_persona_ownership_not_exact_singleton")
		and Distiller.validate_preview_supersession_shape(
			old_node, changed_anchor, eazy_run).has("semantic_target_anchor_changed")
		and Distiller.validate_preview_supersession_shape(
			old_node, changed_predicate, eazy_run).has(
				"non_proxy_condition_predicates_changed")
		and Distiller.validate_preview_supersession_shape(
			old_node, equal_target, eazy_run).has(
				"target_precision_did_not_strictly_increase")
		and not Distiller.validate_preview_supersession_shape(
			old_node, unknown_target, eazy_run).is_empty()
		and Distiller.validate_preview_supersession_shape(
			old_node, added_proxy_guard, eazy_run).has(
				"candidate_added_or_changed_proxy_guard")
		and Distiller.validate_preview_supersession_shape(
			old_node, retained_proxy_guards, eazy_run).has(
				"candidate_retained_selector_owned_proxy_guard")
		and Distiller.validate_preview_supersession_shape(
			old_node, partial_proxy_guard, eazy_run).has(
				"candidate_retained_selector_owned_proxy_guard")
		and Distiller.validate_preview_supersession_shape(
			old_node, regrouped_proxy_guards, eazy_run).has(
				"candidate_retained_selector_owned_proxy_guard")
		and Distiller.validate_preview_supersession_shape(
			guardless_old_node, exact_candidate, eazy_run).has(
				"existing_proxy_selector_has_no_owned_structural_guard"),
		"preview rejects gameplay changes, multi-owner nodes, equal/unknown binders, added guards, retained/partial/regrouped guards, and guardless proxies")

	var support_entries: Array = []
	for entry_value in Distiller.inspect_preview_support_entries(native_documents):
		if entry_value is Dictionary and str((entry_value as Dictionary).get(
				"persona", "")) == "eazy_speezy":
			support_entries.append(entry_value)
	var duplicate_support := [support_entries[0], support_entries[0].duplicate(true)]
	var mixed_manifest := support_entries.duplicate(true)
	((mixed_manifest[1] as Dictionary).get(
		"run_evidence", {}) as Dictionary)["invocation_manifest_hash"] = \
		"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	var mixed_build := support_entries.duplicate(true)
	(((mixed_build[1] as Dictionary).get("record", {}) as Dictionary).get(
		"run", {}) as Dictionary)["gameplay_build_fingerprint"] = \
		"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	var mixed_content := support_entries.duplicate(true)
	(((mixed_content[1] as Dictionary).get("record", {}) as Dictionary).get(
		"run", {}) as Dictionary)["content_fingerprint"] = \
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var incomplete := support_entries.duplicate(true)
	((incomplete[1] as Dictionary).get(
		"run_evidence", {}) as Dictionary)["trace_complete"] = false
	var goal_failed := support_entries.duplicate(true)
	((goal_failed[1] as Dictionary).get(
		"run_evidence", {}) as Dictionary)["persona_goal_reached"] = false
	var validation_failed := support_entries.duplicate(true)
	var failed_validation := ((validation_failed[1] as Dictionary).get(
		"run_evidence", {}) as Dictionary).get("validation", {}) as Dictionary
	failed_validation["passed"] = false
	failed_validation["failure_count"] = 1
	_check(support_entries.size() == 2
		and Distiller.validate_preview_supersession_support_group(
			support_entries, 2).is_empty()
		and Distiller.validate_preview_supersession_support_group(
			[support_entries[0]], 2).has("support_count_below_minimum:1<2")
		and Distiller.validate_preview_supersession_support_group(
			duplicate_support, 2).has("duplicate_support_record")
		and Distiller.validate_preview_supersession_support_group(
			mixed_manifest, 2).has("support_manifest_is_not_uniform")
		and Distiller.validate_preview_supersession_support_group(
			mixed_build, 2).has("support_gameplay_build_is_not_uniform")
		and Distiller.validate_preview_supersession_support_group(
			mixed_content, 2).has("support_content_is_not_uniform")
		and str(Distiller.validate_preview_supersession_support_group(
			incomplete, 2)).contains("candidate_trace_not_complete")
		and str(Distiller.validate_preview_supersession_support_group(
			goal_failed, 2)).contains("candidate_persona_goal_not_reached")
		and str(Distiller.validate_preview_supersession_support_group(
			validation_failed, 2)).contains(
				"candidate_strict_validation_not_current_and_passed"),
		"preview support requires two distinct current run/trace/records from one complete manifest, content, build, goal, and strict validation")

	var subset_preview := Distiller.distill_preview(
		_preview_old_proxy_library(), [native_documents[2]], 2)
	var duplicate_documents := native_documents.duplicate()
	duplicate_documents.append(native_documents[2])
	var duplicate_preview := Distiller.distill_preview(
		_preview_old_proxy_library(), duplicate_documents, 2)
	_check(not _node(subset_preview, "eazy_rest_visible_shelter").has(
		"superseded_policy_history")
		and not _node(duplicate_preview, "eazy_rest_visible_shelter").has(
			"superseded_policy_history"),
		"a filtered member or duplicated invocation member cannot trigger preview supersession")

	var alternate_paths := _write_complete_cohort(
		"native", "native_preview_ambiguous", _eazy_exact_shelter_candidate())
	var alternate_documents := _seal_cohort(
		alternate_paths, "native_preview_ambiguous_invocation")
	var ambiguous_documents := native_documents.duplicate()
	ambiguous_documents.append_array(alternate_documents)
	var ambiguous_preview := Distiller.distill_preview(
		_preview_old_proxy_library(), ambiguous_documents, 2)
	var ambiguous_node := _node(ambiguous_preview, "eazy_rest_visible_shelter")
	_check(str(((ambiguous_node.get("policy", {}) as Dictionary).get(
		"action", {}) as Dictionary).get("target_ref", "")) \
			== "nearest_visible_ground_to_shelter_label"
		and not ambiguous_node.has("superseded_policy_history")
		and str(ambiguous_preview.get("rejected_evidence", [])).contains(
			"candidate_policy_supersession_ambiguous"),
		"two independently qualified exact-target successor variants reject as ambiguous")


func _preview_old_proxy_library() -> Dictionary:
	return {"nodes": [{
		"id": "eazy_rest_visible_shelter",
		"rule": "Old nearest-ground shelter proxy.",
		"personas": ["eazy_speezy"],
		"status": "validated",
		"eligible_for_automation": true,
		"policy": {
			"condition": _preview_old_proxy_condition(),
			"action": {"verb": "interact",
				"target_ref": "nearest_visible_ground_to_shelter_label"},
			"expected": {"path": "accepted", "op": "eq", "value": true},
			"scope": "fragment",
			"priority": 70,
		},
		"evidence": {
			"support_count": 11,
			"provenance": [
				{"record_hash": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
					"fragment_id": "basin_fill_proof"},
				{"record_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
					"fragment_id": "basin_fill_proof"},
			],
		},
	}]}


func _preview_old_proxy_condition() -> Dictionary:
	var guards: Array = []
	for bin_name in ["top_center", "top_left", "middle_center", "top_right",
			"middle_right", "middle_left", "bottom_center", "bottom_right",
			"bottom_left"]:
		guards.append({"path": "viewport_bins.%s.0" % bin_name,
			"op": "exists", "value": true})
	return {"all": [
		{"path": "visible_affordance_verbs", "op": "contains",
			"value": "REST PARTY"},
		{"any": guards},
	]}


func _eazy_exact_shelter_candidate() -> Dictionary:
	var candidate := _eazy_candidate()
	candidate["rule"] = "Eazy uses the exact visible REST PARTY shelter surface."
	(candidate["action"] as Dictionary)["target_ref"] = \
		"matching_visible_shelter_surface"
	return candidate


func _document_for_persona(documents: Array, persona: String) -> Dictionary:
	for document_value in documents:
		if document_value is Dictionary and str(((document_value as Dictionary).get(
				"run", {}) as Dictionary).get("persona", "")) == persona:
			return document_value as Dictionary
	return {}


func _test_invocation_cohort_fail_closed(native_paths: Array,
		native_documents: Array) -> void:
	var subset := Distiller.distill({}, [native_documents[0]], 1)
	_check(_node(subset, "dean_rally_visible_ground").is_empty()
		and str(subset.get("rejected_evidence", [])).contains(
			"invocation_cohort_document_count_mismatch"),
		"a valid member cannot promote from a subset of its invocation cohort")
	var duplicate_documents := native_documents.duplicate()
	duplicate_documents.append(native_documents[0])
	var duplicated := Distiller.distill({}, duplicate_documents, 1)
	_check(_node(duplicated, "dean_rally_visible_ground").is_empty()
		and str(duplicated.get("rejected_evidence", [])).contains(
			"missing_or_duplicate"),
		"duplicating one cohort member cannot replace another proof")

	var failed_paths := _write_complete_cohort("native", "native_failed")
	var failed_documents := _seal_cohort(
		failed_paths, "native_failed_invocation", 2)
	var failed := Distiller.distill({}, failed_documents, 1)
	_check(_node(failed, "dean_rally_visible_ground").is_empty()
		and _node(failed, "eazy_rest_visible_shelter").is_empty()
		and str(failed.get("rejected_evidence", [])).contains(
			"invocation_member_validation_not_passed"),
		"one failed validation receipt invalidates every member of the invocation")

	var pre_documents: Array = []
	for path_value in _write_complete_cohort("native", "native_bad_manifest"):
		pre_documents.append(Trace.read_trace(path_value))
	var subset_manifest := Trace.make_invocation_manifest(
		[pre_documents[0]], "subset_manifest_invocation")
	_check(not bool(subset_manifest.get("passed", true))
		and str(subset_manifest.get("failures", [])).contains(
			"expected_persona_repeat_matrix"),
		"manifest builder rejects a self-declared subset cohort")
	var duplicate_manifest := Trace.make_invocation_manifest([
		pre_documents[0], pre_documents[0], pre_documents[2], pre_documents[3],
	], "duplicate_manifest_invocation")
	_check(not bool(duplicate_manifest.get("passed", true))
		and str(duplicate_manifest.get("failures", [])).contains("duplicate_cohort_member"),
		"manifest builder rejects duplicate persona/repeat member proof")
	var content_mutated_documents := pre_documents.duplicate(true)
	var content_mutated_member := (content_mutated_documents[3] as Dictionary).duplicate(true)
	var content_mutated_run := (content_mutated_member.get("run", {}) as Dictionary).duplicate(true)
	content_mutated_run["content_fingerprint"] = \
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	content_mutated_member["run"] = content_mutated_run
	content_mutated_documents[3] = content_mutated_member
	var content_mutated_manifest := Trace.make_invocation_manifest(
		content_mutated_documents, "content_mutated_manifest_invocation")
	_check(not bool(content_mutated_manifest.get("passed", true))
		and str(content_mutated_manifest.get("failures", [])).contains(
			"cohort_content_identity_mismatch"),
		"manifest builder rejects one persona/repeat member with different content bytes")
	var build_mutated_documents := pre_documents.duplicate(true)
	var build_mutated_member := (build_mutated_documents[3] as Dictionary).duplicate(true)
	var build_mutated_run := (build_mutated_member.get("run", {}) as Dictionary).duplicate(true)
	build_mutated_run["gameplay_build_fingerprint"] = \
		"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	build_mutated_member["run"] = build_mutated_run
	build_mutated_documents[3] = build_mutated_member
	var build_mutated_manifest := Trace.make_invocation_manifest(
		build_mutated_documents, "build_mutated_manifest_invocation")
	_check(not bool(build_mutated_manifest.get("passed", true))
		and str(build_mutated_manifest.get("failures", [])).contains(
			"cohort_gameplay_build_identity_mismatch"),
		"manifest builder rejects one member from a different gameplay build")
	var forged_documents := content_mutated_documents.duplicate(true)
	var forged_manifest := Trace.make_invocation_manifest(
		pre_documents, "forged_rehashed_manifest_invocation")
	var forged_trace_id := str(((forged_documents[3] as Dictionary).get(
		"run", {}) as Dictionary).get("trace_id", ""))
	for member_value in forged_manifest.get("members", []):
		if member_value is Dictionary and str((member_value as Dictionary).get(
				"trace_id", "")) == forged_trace_id:
			(member_value as Dictionary)["content_fingerprint"] = \
				"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	for index in range(forged_documents.size()):
		var forged_document := forged_documents[index] as Dictionary
		var forged_receipt := Trace.make_validation_receipt(
			forged_document, "forged_rehashed_manifest_invocation", true, 1, 0,
			forged_manifest)
		forged_document["validation"] = forged_receipt
		forged_document["validation_record_hash"] = Trace.canonical_hash(forged_receipt)
		forged_documents[index] = forged_document
	var forged_distillation := Distiller.distill({}, forged_documents, 1)
	_check(_node(forged_distillation, "dean_rally_visible_ground").is_empty()
		and _node(forged_distillation, "eazy_rest_visible_shelter").is_empty()
		and str(forged_distillation.get("rejected_evidence", [])).contains(
			"invocation_manifest_not_recomputed_from_documents"),
		"distiller rejects a rehashed passed manifest forged over mixed content")

	var green_with_failure := Trace.make_validation_receipt(
		pre_documents[0], "green_with_failure_invocation", true, 1, 1,
		Trace.make_invocation_manifest(pre_documents, "green_with_failure_invocation"))
	var green_with_failure_document := Trace.document_with_validation(
		pre_documents[0], green_with_failure)
	var red_without_failure := Trace.make_validation_receipt(
		pre_documents[0], "red_without_failure_invocation", false, 1, 0,
		Trace.make_invocation_manifest(pre_documents, "red_without_failure_invocation"))
	var red_without_failure_document := Trace.document_with_validation(
		pre_documents[0], red_without_failure)
	_check(not bool(green_with_failure_document.get("ok", true))
		and str(green_with_failure_document.get("errors", [])).contains(
			"passed validation must have zero failures")
		and not bool(red_without_failure_document.get("ok", true))
		and str(red_without_failure_document.get("errors", [])).contains(
			"failed validation must report at least one failure"),
		"validation verdicts and failure counts cannot contradict each other")
	var wrong_manifest := Trace.make_invocation_manifest(pre_documents,
		"wrong_manifest_invocation")
	var wrong_receipt := Trace.make_validation_receipt(native_documents[0],
		"wrong_manifest_invocation", true, 1, 0, wrong_manifest)
	var wrong_append := Trace.append_validation(str(native_paths[0]), wrong_receipt)
	_check(not bool(wrong_append.get("ok", true)),
		"a mismatched cohort manifest cannot be appended to an unrelated trace")

	var missing_manifest_trace := Trace.read_trace(
		_write_persona_trace("native", "dean_takahashi", 0, "missing_manifest"))
	var missing_manifest := Distiller.distill({}, [missing_manifest_trace], 1)
	_check(_node(missing_manifest, "dean_rally_visible_ground").is_empty()
		and str(missing_manifest.get("rejected_evidence", [])).contains(
			"strict_validation_missing"),
		"missing invocation manifest/validation remains diagnostic-only")


func _test_forged_persisted_derivations(source_path: String) -> void:
	var forged_path := _scratch.path_join("forged_feedback_outcome.jsonl")
	_copy_trace(source_path, forged_path)
	_rewrite_record(forged_path, Trace.DECISION_RECORD, func(record: Dictionary) -> void:
		(record["feedback"] as Dictionary)["player_observable"] = false
		(record["outcome"] as Dictionary)["accepted"] = false)
	var forged := Trace.read_trace(forged_path)
	var errors := str(forged.get("errors", []))
	_check(not bool(forged.get("ok", true))
		and errors.contains("feedback does not match the exact v3 derived feedback")
		and errors.contains("outcome does not match the exact v3 derived outcome")
		and not errors.contains("invalid record hash"),
		"reader rejects rehashed forged feedback/outcome by exact recomputation")


func _test_v2_library_provenance_is_inadmissible(v3_library: Dictionary) -> void:
	var legacy := v3_library.duplicate(true)
	legacy["schema"] = "persona_decision_library_v2"
	for node_value in legacy.get("nodes", []):
		if not (node_value is Dictionary):
			continue
		var evidence := (node_value as Dictionary).get("evidence", {}) as Dictionary
		for source_value in evidence.get("provenance", []):
			if source_value is Dictionary:
				(source_value as Dictionary)["source_trace_schema"] = \
					"persona_decision_trace_v2"
				(source_value as Dictionary).erase("content_fingerprint_schema")
	var migrated := Distiller.distill(legacy, [], 2)
	var retained := _node(migrated, "eazy_rest_visible_shelter")
	_check(str(migrated.get("schema", "")) == Distiller.LIBRARY_SCHEMA
		and not retained.is_empty()
		and not bool(retained.get("eligible_for_automation", true))
		and int((retained.get("evidence", {}) as Dictionary).get("support_count", -1)) == 0
		and int((retained.get("evidence", {}) as Dictionary).get(
			"inadmissible_provenance_count", 0)) > 0,
		"v2 provenance is retained diagnostically but becomes inadmissible under v3")

	var mixed_current := v3_library.duplicate(true)
	var mixed_current_node := _node(mixed_current, "eazy_rest_visible_shelter")
	var mixed_current_evidence := mixed_current_node.get("evidence", {}) as Dictionary
	var mixed_current_provenance: Array = mixed_current_evidence.get("provenance", [])
	var current_support_count := int(mixed_current_evidence.get("support_count", 0))
	var current_inadmissible_count := int(mixed_current_evidence.get(
		"inadmissible_provenance_count", 0))
	if not mixed_current_provenance.is_empty() \
			and mixed_current_provenance[0] is Dictionary:
		var legacy_source := (mixed_current_provenance[0] as Dictionary).duplicate(true)
		legacy_source["source_trace_schema"] = "persona_decision_trace_v2"
		legacy_source["record_hash"] = \
			"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
		mixed_current_provenance.append(legacy_source)
	mixed_current_evidence["provenance"] = mixed_current_provenance
	mixed_current_node["evidence"] = mixed_current_evidence
	mixed_current = Distiller.distill(mixed_current, [], 2)
	mixed_current_node = _node(mixed_current, "eazy_rest_visible_shelter")
	mixed_current_evidence = mixed_current_node.get("evidence", {}) as Dictionary
	_check(not mixed_current_node.is_empty()
		and bool(mixed_current_node.get("eligible_for_automation", false))
		and int(mixed_current_evidence.get("support_count", -1)) \
			== current_support_count
		and int(mixed_current_evidence.get("inadmissible_provenance_count", -1)) \
			== current_inadmissible_count + 1,
		"legacy v2 provenance is ignored while independent current v3 support remains eligible")

	var tracked := Distiller.distill(Distiller.load_library(
		"res://data/playthroughs/decision_library.json"), [], 2)
	var tracked_eligible_node_count := 0
	var tracked_eligible_support_is_current := true
	var tracked_legacy_v2_source_count := 0
	var tracked_inadmissible_source_count := 0
	for node_value in tracked.get("nodes", []):
		if not (node_value is Dictionary):
			continue
		var node := node_value as Dictionary
		var evidence := node.get("evidence", {}) as Dictionary
		var current_v3_support_sources := 0
		for source_value in evidence.get("provenance", []):
			if not (source_value is Dictionary):
				continue
			var source := source_value as Dictionary
			if str(source.get("source_trace_schema", "")) \
					== "persona_decision_trace_v2":
				tracked_legacy_v2_source_count += 1
			if str(source.get("source_trace_schema", "")) == Trace.TRACE_SCHEMA \
					and str(source.get("verdict", "")) == "supports":
				current_v3_support_sources += 1
		tracked_inadmissible_source_count += int(evidence.get(
			"inadmissible_provenance_count", 0))
		if bool(node.get("eligible_for_automation", false)):
			tracked_eligible_node_count += 1
			var support_count := int(evidence.get("support_count", 0))
			if support_count < 2 or current_v3_support_sources < support_count:
				tracked_eligible_support_is_current = false
	_check(str(tracked.get("schema", "")) == Distiller.LIBRARY_SCHEMA
		and int((tracked.get("distillation", {}) as Dictionary).get(
			"eligible_node_count", -1)) == tracked_eligible_node_count
		and tracked_eligible_support_is_current
		and tracked_inadmissible_source_count >= tracked_legacy_v2_source_count,
		"tracked library quarantines legacy v2 provenance without erasing eligible current v3 nodes")


func _run_metadata(platform: String, persona: String,
		repeat_index: int, trace_id: String) -> Dictionary:
	return {
		"run_id": "%s:%s:%d:%s" % [platform, persona, repeat_index, trace_id],
		"trace_id": trace_id,
		"persona": persona,
		"fragment_id": "basin_fill_proof",
		"seed": repeat_index,
		"repeat_index": repeat_index,
		"content_fingerprint_schema": str(_authored_identity.get(
			"content_fingerprint_schema", "")),
		"content_fingerprint": str(_authored_identity.get("content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(_gameplay_build_identity.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(_gameplay_build_identity.get(
			"gameplay_build_fingerprint", "")),
		"execution_platform": platform,
		"authored_state": "authored_spawn",
		"evidence_baseline_id": "%s:baseline" % trace_id,
	}


func _rationale() -> Dictionary:
	return {"text": "Choose from only the visible player presentation.", "policy_nodes": []}


func _context(id: String) -> Dictionary:
	return {"authored_state": true, "fixture_quarantine": false,
		"evidence_baseline_id": "%s:baseline" % id}


func _dean_decision() -> Dictionary:
	return {
		"verb": "rally", "world_change": true, "group_verb": true,
		"intended_subjects": ["aster", "peris", "endo"],
		"target": {"kind": "visible_affordance", "token": "ground_1"},
	}


func _eazy_decision() -> Dictionary:
	return {
		"verb": "interact", "world_change": true, "group_verb": true,
		"intended_subjects": ["aster", "peris", "endo"],
		"target": {"kind": "visible_affordance", "token": "shelter_1"},
	}


func _rally_receipt(sequence_before := 0) -> Dictionary:
	var events := _pointer_pair_events(sequence_before, 2)
	return {
		"receipt_id": "rally:0", "boundary": "keyboard_pointer",
		"status": "accepted", "player_reproducible": true, "verb": "rally",
		"atomic_group": true, "production_event_count": 1,
		"production_event_kinds": ["rally_members"],
		"input_issued": true, "input_event_count": events.size(),
		"input_sequence_before": sequence_before,
		"input_sequence_after": sequence_before + events.size(),
		"input_events": events, "input_target_token": "ground_1",
		"intended_members": ["aster", "peris", "endo"],
		"member_results": {"aster": "accepted", "peris": "accepted", "endo": "accepted"},
	}


func _interaction_receipt(sequence_before := 0) -> Dictionary:
	var events := _pointer_pair_events(sequence_before, 2)
	return {
		"receipt_id": "interact:0", "boundary": "keyboard_pointer",
		"status": "accepted", "player_reproducible": true, "verb": "interact",
		"atomic_group": true, "production_event_count": 1,
		"production_event_kinds": ["rally_members"],
		"input_issued": true, "input_event_count": events.size(),
		"input_sequence_before": sequence_before,
		"input_sequence_after": sequence_before + events.size(),
		"input_events": events, "input_target_token": "shelter_1",
		"intended_members": ["aster", "peris", "endo"],
		"member_results": {"aster": "accepted", "peris": "accepted", "endo": "accepted"},
	}


func _pointer_pair_events(sequence_before: int, button: int) -> Array:
	return [
		{"sequence": sequence_before + 1, "kind": "pointer_move", "issued": true},
		{"sequence": sequence_before + 2, "kind": "pointer_button", "issued": true,
			"button": button, "pressed": true},
		{"sequence": sequence_before + 3, "kind": "pointer_button", "issued": true,
			"button": button, "pressed": false},
	]


func _key_pair_events(sequence_before: int, key: String,
		ctrl := false) -> Array:
	return [
		{"sequence": sequence_before + 1, "kind": "key", "issued": true,
			"key": key, "pressed": true, "modifiers": {
				"ctrl": ctrl, "shift": false, "alt": false, "meta": false}},
		{"sequence": sequence_before + 2, "kind": "key", "issued": true,
			"key": key, "pressed": false, "modifiers": {
				"ctrl": ctrl, "shift": false, "alt": false, "meta": false}},
	]


func _select_party_receipt(sequence_before := 0) -> Dictionary:
	var events: Array = []
	var next := sequence_before
	for spec in [["Digit1", false], ["Digit2", true], ["Digit3", true]]:
		var pair := _key_pair_events(next, str(spec[0]), bool(spec[1]))
		events.append_array(pair)
		next += pair.size()
	return {
		"receipt_id": "select_party:0", "boundary": "keyboard_pointer",
		"status": "accepted", "player_reproducible": true,
		"verb": "select_party", "atomic_group": false,
		"production_event_count": 0, "production_event_kinds": [],
		"input_issued": true, "input_event_count": events.size(),
		"input_sequence_before": sequence_before,
		"input_sequence_after": next, "input_events": events,
		"intended_members": ["aster", "peris", "endo"],
		"member_results": {
			"aster": "accepted", "peris": "accepted", "endo": "accepted"},
	}


func _select_single_ctrl_off_receipt(sequence_before := 0) -> Dictionary:
	var events: Array = []
	var next := sequence_before
	for key in ["Digit2", "Digit3"]:
		var pair := _key_pair_events(next, key, true)
		events.append_array(pair)
		next += pair.size()
	return {
		"receipt_id": "select_single_ctrl_off:0", "boundary": "keyboard_pointer",
		"status": "accepted", "player_reproducible": true,
		"verb": "select_single", "atomic_group": false,
		"production_event_count": 0, "production_event_kinds": [],
		"input_issued": true, "input_event_count": events.size(),
		"input_sequence_before": sequence_before,
		"input_sequence_after": next, "input_events": events,
	}


func _select_single_direct_receipt(key: String, sequence_before := 0) -> Dictionary:
	var events := _key_pair_events(sequence_before, key)
	return {
		"receipt_id": "select_single_direct:0", "boundary": "keyboard_pointer",
		"status": "accepted", "player_reproducible": true,
		"verb": "select_single", "atomic_group": false,
		"production_event_count": 0, "production_event_kinds": [],
		"input_issued": true, "input_event_count": events.size(),
		"input_sequence_before": sequence_before,
		"input_sequence_after": sequence_before + events.size(),
		"input_events": events,
	}


func _active_wait_receipt(sequence_before := 0) -> Dictionary:
	var events := _key_pair_events(sequence_before, "KeyF")
	return {
		"receipt_id": "wait:f", "boundary": "keyboard_pointer",
		"status": "observed", "player_reproducible": true, "verb": "wait",
		"atomic_group": false, "production_event_count": 0,
		"production_event_kinds": [], "input_issued": true,
		"input_event_count": events.size(), "input_sequence_before": sequence_before,
		"input_sequence_after": sequence_before + events.size(),
		"input_events": events,
	}


func _dean_candidate() -> Dictionary:
	return {
		"node_id": "dean_rally_visible_ground",
		"rule": "Dean issues a pointless whole-party Rally toward a chosen visible floor point.",
		"scope": "fragment", "priority": 40,
		"condition": {"path": "viewport_bins.middle_center.0", "op": "exists", "value": true},
		"action": {"verb": "rally", "target_ref": "chosen_visible_ground"},
		"expected": {"path": "accepted", "op": "eq", "value": true},
	}


func _eazy_candidate() -> Dictionary:
	return {
		"node_id": "eazy_rest_visible_shelter",
		"rule": "Eazy uses the exact visible REST PARTY shelter interaction.",
		"scope": "fragment", "priority": 70,
		"condition": {"path": "visible_affordance_verbs", "op": "contains",
			"value": "REST PARTY"},
		"action": {"verb": "interact", "target_ref": "matching_visible_interaction"},
		"expected": {"path": "accepted", "op": "eq", "value": true},
	}


func _decision_record(before: Dictionary, after: Dictionary, samples: Array,
		decision: Dictionary, receipt: Dictionary, candidate: Dictionary) -> Dictionary:
	var stamped_before := before.duplicate(true)
	stamped_before["capture_serial"] = 1
	var stamped_samples: Array = []
	var next_capture_serial := 2
	for sample_value in samples:
		if sample_value is Dictionary:
			var stamped_sample := (sample_value as Dictionary).duplicate(true)
			stamped_sample["capture_serial"] = next_capture_serial
			next_capture_serial += 1
			stamped_samples.append(stamped_sample)
	var stamped_after := after.duplicate(true)
	stamped_after["capture_serial"] = next_capture_serial
	var stamped_receipt := receipt.duplicate(true)
	if str(stamped_receipt.get("boundary", "")) == "keyboard_pointer" \
			and bool(stamped_receipt.get("input_issued", false)):
		stamped_receipt["observation_before_capture_serial"] = 1
		stamped_receipt["first_post_input_capture_serial"] = 2
	var deduplicated := Trace.deduplicate_observations(stamped_samples)
	var derived := Trace.derive_feedback_outcome(
		stamped_before, stamped_after, deduplicated, decision, stamped_receipt)
	var record := {
		"schema": Trace.TRACE_SCHEMA, "record_type": Trace.DECISION_RECORD,
		"run": {}, "decision_index": 0,
		"observation_before": stamped_before,
		"observation_after": stamped_after,
		"observation_samples": deduplicated,
		"rationale": _rationale(), "decision": decision.duplicate(true),
		"input_receipt": stamped_receipt,
		"feedback": (derived.get("feedback", {}) as Dictionary).duplicate(true),
		"outcome": (derived.get("outcome", {}) as Dictionary).duplicate(true),
		"evidence_context": _context("fixture"),
	}
	if not candidate.is_empty():
		record["learning_candidate"] = candidate.duplicate(true)
	record["evidence"] = Trace.classify_evidence(record)
	return record


func _opaque_party_observation(mode: String) -> Dictionary:
	var observation := _observation(mode)
	var token_map := {
		"portrait_aster": "portrait_0001",
		"portrait_peris": "portrait_0002",
		"portrait_endo": "portrait_0003",
		"body_aster": "body_0001",
		"body_peris": "body_0002",
		"body_endo": "body_0003",
	}
	var state := observation.get("state", {}) as Dictionary
	var hud := state.get("hud", {}) as Dictionary
	for portrait_v in hud.get("portraits", []):
		if portrait_v is Dictionary:
			var portrait := portrait_v as Dictionary
			var token := str(portrait.get("token", ""))
			portrait["token"] = str(token_map.get(token, token))
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		for field in ["source_token", "binding"]:
			var token := str(cue.get(field, ""))
			if token_map.has(token):
				cue[field] = str(token_map[token])
		if cue.get("subjects", null) is Array:
			var opaque_subjects: Array = []
			for subject_v in cue.get("subjects", []):
				var subject := str(subject_v)
				opaque_subjects.append(str(token_map.get(subject, subject)))
			cue["subjects"] = opaque_subjects
	return observation


func _nonparty_consequence_presentation(subject_id: String,
		phase: String, render_visible: bool) -> Dictionary:
	var presentation := {
		"warning": [],
		"active": [],
		"recent": [],
	}
	var record := {
		"phase": phase,
		"visible": render_visible,
		"render_visible": render_visible,
		"subject_id": subject_id,
		"subjects": [subject_id],
		"label": "SWEPT BY RISING BASIN",
		"destination_label": "START / CURRENT RETURN",
		"progress": 1.0 if phase == "arrival" else 0.5,
	}
	var bucket := "recent" if phase == "arrival" else "active"
	(presentation[bucket] as Array).append(record)
	return presentation


func _observation_with_extra_cues(extra_cues: Array) -> Dictionary:
	var observation := _observation("baseline")
	var state := observation.get("state", {}) as Dictionary
	var cues := (state.get("cues", []) as Array).duplicate(true)
	for cue_v in extra_cues:
		if cue_v is Dictionary:
			cues.append((cue_v as Dictionary).duplicate(true))
	state["cues"] = cues
	return observation


func _background_traversal_event(subject_id: String) -> Dictionary:
	return {
		"kind": "begin_external_traversal",
		"event_id": "private-event-id",
		"payload": {
			"id": subject_id,
			"traversal_id": "private-traversal-id",
			"presentation_receipt": {
				"scope": "player_facing",
				"effect_kind": "forced_movement",
				"label": "SWEPT BY RISING BASIN",
				"destination_label": "START / CURRENT RETURN",
			},
		},
	}


func _remove_cue_source(observation: Dictionary, source_token: String) -> void:
	var state := observation.get("state", {}) as Dictionary
	var filtered: Array = []
	for cue_v in state.get("cues", []):
		if cue_v is Dictionary and str((cue_v as Dictionary).get(
				"source_token", "")) == source_token:
			continue
		filtered.append(cue_v)
	state["cues"] = filtered


func _remove_portrait_binding(observation: Dictionary,
		portrait_token: String) -> void:
	var state := observation.get("state", {}) as Dictionary
	var hud := state.get("hud", {}) as Dictionary
	var portraits: Array = []
	for portrait_v in hud.get("portraits", []):
		if portrait_v is Dictionary and str((portrait_v as Dictionary).get(
				"token", "")) == portrait_token:
			continue
		portraits.append(portrait_v)
	hud["portraits"] = portraits
	var cues: Array = []
	for cue_v in state.get("cues", []):
		if cue_v is Dictionary and str((cue_v as Dictionary).get(
				"kind", "")) == "party_body" \
				and str((cue_v as Dictionary).get("binding", "")) == portrait_token:
			continue
		cues.append(cue_v)
	state["cues"] = cues


func _observation(mode: String, capture_serial := 1) -> Dictionary:
	var portraits := [
		{"token": "portrait_aster", "label": "ASTER", "screen": [100, 700],
			"selected": true, "active": true, "visible": true, "bars": {"hp": 100,
			"sta": 100, "atp": 8}, "status": "READY", "alert": ""},
		{"token": "portrait_peris", "label": "PERIS", "screen": [220, 700],
			"selected": false, "active": false, "visible": true, "bars": {"hp": 100,
			"sta": 100, "atp": 8}, "status": "READY", "alert": ""},
		{"token": "portrait_endo", "label": "ENDO", "screen": [340, 700],
			"selected": false, "active": false, "visible": true, "bars": {"hp": 100,
			"sta": 100, "atp": 8}, "status": "READY", "alert": ""},
	]
	var cues: Array = [
		{"kind": "party_body", "source_token": "body_aster", "binding": "portrait_aster",
			"screen": [500, 360], "visible": true},
		{"kind": "party_body", "source_token": "body_peris", "binding": "portrait_peris",
			"screen": [530, 360], "visible": true},
		{"kind": "party_body", "source_token": "body_endo", "binding": "portrait_endo",
			"screen": [560, 360], "visible": true},
	]
	match mode:
		"warning":
			cues.append(_movement_result_cue(
				"ground_1", 1, "accepted", true, ""))
			cues.append({"kind": "hud",
				"text": "BASIN RISING // CURRENT RETURNS TO START", "visible": true})
		"active":
			cues.append(_movement_result_cue(
				"ground_1", 1, "progress", true, ""))
			for token in ["portrait_aster", "portrait_peris", "portrait_endo"]:
				cues.append(_sweep_cue(token, "active", "RETURN SHELF"))
		"arrival":
			cues.append(_movement_result_cue(
				"ground_1", 1, "arrival", true, ""))
			for token in ["portrait_aster", "portrait_peris", "portrait_endo"]:
				cues.append(_sweep_cue(token, "arrival", "RETURN SHELF"))
		"interrupted":
			cues.append(_movement_result_cue(
				"ground_1", 1, "interrupted", true,
				"RALLY INTERRUPTED // movement stopped before the shown destination."))
		"arrival_other_destination":
			cues.append(_movement_result_cue(
				"ground_1", 1, "arrival", true, ""))
			for token in ["portrait_aster", "portrait_peris", "portrait_endo"]:
				cues.append(_sweep_cue(token, "arrival", "OTHER SHELF"))
		"interaction_success_only":
			cues.append(_interaction_result_cue("shelter_1", 1, "success"))
		"eazy_success":
			cues.append(_interaction_result_cue("shelter_1", 1, "success"))
			cues.append({"kind": "hud", "text": "SECURED THE SHELTER // FULL PARTY SETTLED",
				"state": "settled", "visible": true})
		"hide_control":
			cues.append({"kind": "instruction", "text": "H HIDE INSTRUCTIONS", "visible": true})
		"announced_wait":
			cues.append({"kind": "hud", "text": "CROSSING STAGING // NEXT MID", "visible": true})
		"target_binding":
			cues.append({"kind": "hud", "text": "SHELTER", "screen": [640, 360],
				"visible": true})
	var affordances := [
		{"token": "ground_1", "kind": "move", "verb": "MOVE",
			"consequence": "ROUTE VIA LADDER", "screen": [640, 360]},
		{"token": "ground_2", "kind": "move", "verb": "MOVE",
			"consequence": "", "screen": [900, 500]},
		{"token": "shelter_1", "kind": "interact", "verb": "REST PARTY",
			"consequence": "Secure the shelter.", "screen": [680, 360]},
	]
	var verbs := ["MOVE", "REST PARTY"]
	var consequences := ["ROUTE VIA LADDER", "Secure the shelter."]
	return {
		"schema": Trace.PLAYER_OBSERVATION_SCHEMA, "source": "player_observable",
		"capture_serial": capture_serial, "tick": 1,
		"state": {
			"hud": {"portraits": portraits, "run_label": "WALK", "routing_label": "DIRECT"},
			"viewport": {"origin": [0, 0], "size": [1280, 720]},
			"affordances": affordances,
			"visible_affordance_verbs": verbs,
			"visible_affordance_consequences": consequences,
			"cues": cues,
			"viewport_bins": {"middle_center": ["ground_1", "shelter_1"],
				"middle_right": ["ground_2"]},
		},
	}


func _sweep_cue(token: String, phase: String, destination: String) -> Dictionary:
	return {"kind": "consequence", "source_token": token, "phase": phase,
		"label": "SWEPT", "destination_label": destination,
		"text": "SWEPT // %s" % destination, "progress": 0.5 if phase == "active" else 1.0,
		"visible": true}


func _interaction_result_cue(token: String, serial: int, result: String) -> Dictionary:
	return {"kind": "interaction_result", "source_token": token,
		"presentation_serial": serial, "result": result, "screen": [680, 360],
		"visible": true}


func _movement_result_cue(target_token: String, serial: int, phase: String,
		accepted: bool, reason: String,
		subjects: Array = ["portrait_aster", "portrait_peris", "portrait_endo"]
	) -> Dictionary:
	return {
		"kind": "movement_result", "target_token": target_token,
		"subjects": subjects.duplicate(), "phase": phase, "accepted": accepted,
		"reason": reason, "presentation_serial": serial, "visible": true,
	}


func _add_cue(observation: Dictionary, cue: Dictionary) -> void:
	(((observation.get("state", {}) as Dictionary).get("cues", [])) as Array).append(cue)


func _rewrite_record(path: String, record_type: String, mutate: Callable) -> void:
	var records: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	while file != null and not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			records.append(parsed)
	if file != null:
		file.close()
	var mutated := false
	for record_value in records:
		var record := record_value as Dictionary
		if not mutated and str(record.get("record_type", "")) == record_type:
			mutate.call(record)
			mutated = true
	var previous_hash := ""
	var output := FileAccess.open(path, FileAccess.WRITE)
	for record_value in records:
		var record := record_value as Dictionary
		record["previous_hash"] = previous_hash
		record.erase("record_hash")
		record["record_hash"] = Trace.canonical_hash(record)
		previous_hash = str(record.get("record_hash", ""))
		output.store_line(Trace.canonical_json(record))
	output.close()


func _copy_trace(source: String, destination: String) -> void:
	var output := FileAccess.open(destination, FileAccess.WRITE)
	output.store_string(FileAccess.get_file_as_string(source))
	output.close()


func _all_documents_ok(documents: Array) -> bool:
	for document_value in documents:
		if not (document_value is Dictionary) or not bool((document_value as Dictionary).get(
				"ok", false)):
			return false
	return true


func _node(library: Dictionary, node_id: String) -> Dictionary:
	for node_value in library.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("id", "")) == node_id:
			return node_value as Dictionary
	return {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(_scratch)
	var directory := DirAccess.open(absolute)
	if directory != null:
		directory.list_dir_begin()
		var entry := directory.get_next()
		while entry != "":
			if not directory.current_is_dir():
				DirAccess.remove_absolute(absolute.path_join(entry))
			entry = directory.get_next()
		directory.list_dir_end()
	DirAccess.remove_absolute(absolute)
