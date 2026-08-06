class_name PersonaPlayerController
extends Node

## Observation-driven persona executor. Policy reads only player_observation_v1;
## execution uses only AgentPlayerInputDriver's shipped keyboard/pointer events.

const ObservationControllerScript := preload(
	"res://scripts/testing/player_observation_controller.gd")
const DecisionTraceScript := preload(
	"res://scripts/testing/persona_decision_trace.gd")
const DecisionLibraryScript := preload(
	"res://scripts/testing/persona_decision_library.gd")
const ContentFingerprint := preload(
	"res://scripts/testing/content_fingerprint.gd")
const InputDriverScript := preload("res://tools/agent_player_input_driver.gd")

const ACTION_SAMPLE_SECONDS := 0.25
const ACTION_SETTLE_LIMIT_SECONDS := 7.0
const INTERACTION_RESULT_ABSOLUTE_LIMIT_SECONDS := 45.0
const INTERACTION_RESULT_VISIBLE_STALL_SECONDS := 7.0
const INTERACTION_RESULT_EMPTY_GRACE_SECONDS := 3.0
const STABLE_SAMPLE_COUNT := 3
const RALLY_SETTLE_LIMIT_SECONDS := 14.0
const SHELTER_VISIBLE_SAMPLE_COUNT := 2
const ANNOUNCED_TRANSITION_CONSEQUENCE_GRACE_SECONDS := 2.0
# At the Basin camera scale, the complete on-pad formation spans 72 px from the
# REST PARTY affordance. One 8 px observation-quantization step is human-scale
# tolerance; 80 px rejects Endo's later 82 px and earlier 146 px stacked-floor
# separations that the old 180 px radius collapsed into false arrival.
const SHELTER_BODY_NEAR_RADIUS_PIXELS := 80.0
const GROUND_BIN_ORDER := [
	"top_center", "top_left", "middle_center", "top_right",
	"middle_right", "middle_left", "bottom_center", "bottom_right", "bottom_left",
]
# A crossing can visibly fail after its announcement has already advanced the
# policy into the shelter leg. Keep those phases eligible for the same
# portrait-bound recovery; otherwise a late carry/lowering cue is ignored and
# the persona hammers REST while the named member is visibly elsewhere.
const EAZY_CROSSING_RECOVERY_PHASES := [
	"await_crossing",
	"settle_after_crossing",
	"rally_shelter",
	"select_party_for_shelter",
	"seek_shelter",
	"await_shelter_retry",
	"complete",
	"shelter_rally_blocked",
	"recover_crossing_route",
]

var _host: Node
var _persona := ""
var _fragment_id := ""
var _run_index := 0
var _observer: Node
var _driver: Node
var _trace
var _trace_path := ""
var _baseline_id := ""
var _used_interactions := {}
var _used_ground := {}
var _read_attempted := false
var _policy_phase := ""
var _idle_decision_count := 0
var _sweep_phase_evidence: Dictionary = {}
var _dean_roster_tokens: Array[String] = []
var _sweep_warning_observed := false
var _shelter_full_party_selection_observed := false
var _shelter_completion_observed := false
var _crossing_failure_evidence: Dictionary = {}
var _wait_receipt_serial := 0
var _learning_candidate_nodes_recorded: Dictionary = {}
# Validation-only runtime receipts. These are deliberately excluded from every
# observation, policy state, trace record, and learning-candidate payload.
var _validation_navigation_edge_traversals: Array = []
var _validation_action_context: Dictionary = {}


static func deterministic_run_identity(fragment_id: String, persona: String,
		execution_platform: String, repeat_index: int, seed: int) -> String:
	return "%s:%s:%s_%d_%d" % [
		fragment_id.to_lower().replace(" ", "_"),
		persona.to_lower().replace(" ", "_"),
		execution_platform.to_lower(),
		repeat_index,
		seed,
	]


func setup(host: Node, persona: String, fragment_id: String, run_index := 0) -> Dictionary:
	_host = host
	_persona = persona
	_fragment_id = fragment_id
	_run_index = run_index
	_policy_phase = "clear_view" if _persona == "eazy_speezy" else "fumble"
	_idle_decision_count = 0
	_sweep_phase_evidence.clear()
	_dean_roster_tokens.clear()
	_sweep_warning_observed = false
	_shelter_full_party_selection_observed = false
	_shelter_completion_observed = false
	_crossing_failure_evidence.clear()
	_wait_receipt_serial = 0
	_learning_candidate_nodes_recorded.clear()
	_validation_navigation_edge_traversals.clear()
	_validation_action_context.clear()
	if _host == null or not is_instance_valid(_host):
		return {"ok": false, "error": "missing live preview host"}
	_observer = ObservationControllerScript.new()
	_observer.name = "PlayerObservationController"
	_host.add_child(_observer)
	_observer.call("setup", _host)
	_driver = _host.get_node_or_null("AgentPlayerInputDriver")
	if _driver == null:
		_driver = InputDriverScript.new()
		_driver.name = "AgentPlayerInputDriver"
		_host.add_child(_driver)
		_driver.call("setup", _host)
	_driver.call("clear_receipts")
	var trace_dir := "user://persona_decision_traces"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trace_dir))
	var safe_persona := _persona.to_lower().replace(" ", "_")
	var safe_fragment := _fragment_id.to_lower().replace(" ", "_")
	var run_id := deterministic_run_identity(
		safe_fragment, safe_persona, "native", run_index, run_index)
	_baseline_id = "%s:authored_input_baseline" % run_id
	var fingerprint: Dictionary = ContentFingerprint.authored_fragment_resource(
		"res://data/fragments/%s.tres" % safe_fragment)
	if not bool(fingerprint.get("ok", false)):
		return {
			"ok": false,
			"error": "authored content fingerprint failed closed: %s" % str(
				fingerprint.get("error", "unknown fingerprint error")),
		}
	var gameplay_build: Dictionary = ContentFingerprint.gameplay_build()
	if not bool(gameplay_build.get("ok", false)):
		return {
			"ok": false,
			"error": "gameplay build fingerprint failed closed: %s" % str(
				gameplay_build.get("error", "unknown fingerprint error")),
		}
	_trace_path = trace_dir.path_join("%s__%s__native_%d_%d.jsonl" % [
		safe_persona, safe_fragment, run_index, run_index])
	_trace = DecisionTraceScript.new()
	var begun: Dictionary = _trace.begin(_trace_path, {
		"run_id": run_id,
		"trace_id": run_id,
		"persona": safe_persona,
		"fragment_id": safe_fragment,
		"seed": run_index,
		"repeat_index": run_index,
		"content_fingerprint_schema": str(fingerprint.get(
			"content_fingerprint_schema", "")),
		"content_fingerprint": str(fingerprint.get("content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(gameplay_build.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(gameplay_build.get(
			"gameplay_build_fingerprint", "")),
		"execution_platform": "native",
		"authored_state": "authored_spawn",
		"evidence_baseline_id": _baseline_id,
	})
	if not bool(begun.get("ok", false)):
		return begun
	return {"ok": true, "path": _trace_path, "baseline_id": _baseline_id}


func play(max_decisions := 12) -> Dictionary:
	var report := {
		"ok": true,
		"persona": _persona,
		"fragment_id": _fragment_id,
		"trace_path": _trace_path,
		"decision_count": 0,
		"accepted_count": 0,
		"refused_count": 0,
		"visual_feedback_failures": [],
		"trace_failures": [],
		"evidence_failures": [],
		"actions": [],
		"observed_preconditions": [],
		"persona_goal_reached": false,
		"goal_evidence": {},
		"validation_navigation_edge_traversals": [],
	}
	if _trace == null or not _trace.is_open():
		report["ok"] = false
		(report["trace_failures"] as Array).append("trace was not opened")
		return report
	_validation_set_navigation_edge_receipt_connection(true)
	for decision_index in range(maxi(1, max_decisions)):
		var before: Dictionary = await _presented_snapshot()
		_record_party_sweep_phases(before)
		if _policy_should_stop(before):
			break
		var policy_state_before := _policy_state_snapshot()
		var choice := _choose_decision(before, decision_index)
		choice["_policy_state_before"] = policy_state_before
		choice["_policy_state_chosen"] = _policy_state_snapshot()
		choice["_observation_samples"] = []
		var validation_event_cursor := int(_driver.call(
			"validation_event_cursor")) if _driver.has_method(
				"validation_event_cursor") else 0
		_validation_action_context = {
			"decision_index": decision_index,
			"verb": str(choice.get("verb", "")),
			"intended_subjects": choice.get(
				"intended_subjects", []).duplicate(),
		}
		var receipt: Dictionary = await _execute_choice(choice)
		if str(choice.get("verb", "")) == "interact":
			# Preserve what the shipped pointer boundary reported before any later
			# group-effect or exact-result evidence finalizer rewrites acceptance.
			# Otherwise a delayed evidence failure can falsify the historical input
			# receipt and make an accepted click look as though it never landed.
			receipt["initial_command_accepted"] = bool(
				receipt.get("accepted", false))
		# Capture the first rendered state immediately after the shipped gesture
		# returns. Waiting for the ordinary settle timer can skip a short ACCEPTED
		# phase and leave only PROGRESS/ARRIVAL, which cannot prove the causal
		# lineage. This is a fresh observation, never a replay of presenter history.
		await _record_immediate_post_input_sample(before, choice, receipt)
		# A click near the viewport edge leaves the physical pointer in the shipped
		# edge-scroll band. A human naturally moves it back onto the board while the
		# routed interaction walk completes. Record that real MouseMotion as part of
		# the originating gesture so the camera cannot silently pan the exact target
		# (and its eventual green/red result pulse) out of view.
		if str(choice.get("verb", "")) == "interact" \
				and bool(receipt.get("accepted", false)) \
				and _driver.has_method("park_pointer"):
			var park_receipt_v: Variant = await _driver.call("park_pointer")
			var park_receipt := (park_receipt_v as Dictionary).duplicate(true) \
				if park_receipt_v is Dictionary else {}
			receipt["pointer_park_receipt"] = park_receipt
			receipt["pointer_parked_after_click"] = bool(
				park_receipt.get("accepted", false)) \
				and bool(park_receipt.get("input_issued", false))
		var settled_observation: Dictionary = await _wait_for_presented_settle(before, choice)
		var observation_samples: Array = choice.get(
			"_observation_samples", []).duplicate(true)
		# The terminal observation is a fresh capture, never the last sample under
		# a second name. This makes before < samples < after mechanically auditable.
		var after: Dictionary = await _presented_snapshot()
		_record_party_sweep_phases(settled_observation)
		_record_party_sweep_phases(after)
		if str(choice.get("verb", "")) in ["select_party", "select_single"] \
				and not bool(receipt.get("input_issued", false)):
			(report["observed_preconditions"] as Array).append({
				"kind": "selection_already_visible",
				"desired": choice.get("intended_subjects", []).duplicate(),
			})
		var visible_acceptance := _visible_interaction_acceptance(
			choice, before, after, observation_samples)
		var target_presentation: Dictionary = visible_acceptance.get(
			"target_presentation", {})
		# Selected-party consoles can emit their one authoritative Rally only after the ordinary
		# click-to-walk interaction reaches the visible source. Attach that delayed production event to
		# the originating decision after its visible result, never by invoking or accelerating it.
		if bool(choice.get("group_verb", false)) \
				and str(receipt.get("kind", "")) == "interact" \
				and _driver.has_method("finalize_group_rally_receipt"):
			receipt = _driver.call("finalize_group_rally_receipt", receipt,
				choice.get("intended_subjects", []).duplicate())
		if str(receipt.get("kind", "")) == "interact" \
				and _driver.has_method("finalize_interaction_receipt"):
			var expected_target_token := str(choice.get("target_token", ""))
			var baseline_target_result := _target_interaction_result(
				before, expected_target_token)
			receipt = _driver.call("finalize_interaction_receipt", receipt,
				target_presentation,
				str(visible_acceptance.get("reason", "")),
				expected_target_token,
				int(baseline_target_result.get("presentation_serial", 0)))
		var world_change := bool(choice.get("world_change", true))
		var background_events: Array = []
		if str(choice.get("verb", "")) == "wait" \
				and not world_change \
				and _driver.has_method("validation_events_since"):
			var background_events_v: Variant = _driver.call(
				"validation_events_since", validation_event_cursor)
			if background_events_v is Array:
				background_events = (background_events_v as Array).duplicate(true)
		var background_validation := _validate_background_event_presentation(
			before, observation_samples, after, background_events)
		# A shipped gesture receipt proves only that real input was issued. World
		# movement advances policy from the exact player-visible result lineage, so
		# an accepted click followed by a rendered refusal cannot masquerade as a
		# successful Rally.
		var policy_accepted := _policy_acceptance_from_visible_result(
			choice, before, after, observation_samples, receipt,
			visible_acceptance)
		var policy_demonstrated := _choice_demonstrated(
			choice, policy_accepted, after, observation_samples, before, receipt)
		_update_policy_memory(choice, policy_demonstrated, after)
		var policy_state_after := _policy_state_snapshot()
		var intended_subjects: Array = choice.get("intended_subjects", []).duplicate()
		if str(choice.get("verb", "")) == "rally":
			intended_subjects = receipt.get(
				"intended_members", intended_subjects).duplicate()
		var decision := {
			"verb": str(choice.get("verb", "")),
			"world_change": world_change,
			"group_verb": str(choice.get("verb", "")) == "rally" \
				or bool(choice.get("group_verb", false)),
			"intended_subjects": intended_subjects,
			"target": {
				"kind": "visible_affordance",
				"token": str(choice.get("target_token", "")),
			},
		}
		var input_receipt := _trace_receipt(
			receipt, choice, before, observation_samples, after)
		input_receipt["validation_background_event_count"] = background_events.size()
		input_receipt["validation_background_event_kinds"] = \
			background_validation.get("event_kinds", []).duplicate()
		input_receipt["validation_background_visual_lineage"] = \
			background_validation.duplicate(true)
		if str(choice.get("verb", "")) == "interact" \
				and bool(receipt.get("initial_command_accepted",
					receipt.get("accepted", false))) \
				and not bool(receipt.get("pointer_parked_after_click", false)):
			(report["evidence_failures"] as Array).append({
				"decision_index": decision_index,
				"verb": "interact",
				"rejection_reasons": ["pointer_park_input_missing"],
			})
		var learning_candidate := _learning_candidate_for_append(
			choice, before, after, observation_samples, receipt,
			policy_demonstrated)
		var appended: Dictionary = _trace.append_decision(
			before,
			after,
			observation_samples,
			{
				"text": str(choice.get("rationale", "")),
				"policy_nodes": choice.get("policy_nodes", []),
				"policy_state_before": choice.get(
					"_policy_state_before", {}).duplicate(true),
				"policy_state_chosen": choice.get(
					"_policy_state_chosen", {}).duplicate(true),
				"policy_state_after": policy_state_after,
			},
			decision,
			input_receipt,
			{
				"authored_state": true,
				"fixture_quarantine": false,
				"evidence_baseline_id": _baseline_id,
			},
			learning_candidate,
		)
		if not bool(appended.get("ok", false)):
			(report["trace_failures"] as Array).append({
				"decision_index": decision_index,
				"error": str(appended.get("error", "trace append failed")),
			})
		var feedback := appended.get("feedback", {}) as Dictionary
		var outcome := appended.get("outcome", {}) as Dictionary
		var evidence := appended.get("evidence", {}) as Dictionary
		var accepted := bool(outcome.get("accepted", false))
		if str(outcome.get("status", "")) == "accepted":
			report["accepted_count"] = int(report["accepted_count"]) + 1
		elif str(outcome.get("status", "")) == "refused":
			report["refused_count"] = int(report["refused_count"]) + 1
		if bool(appended.get("ok", false)) \
				and not bool(evidence.get("eligible_for_learning", false)):
			(report["evidence_failures"] as Array).append({
				"decision_index": decision_index,
				"verb": str(choice.get("verb", "")),
				"rejection_reasons": evidence.get("rejection_reasons", []).duplicate(),
			})
		if bool(appended.get("ok", false)) and world_change \
				and not bool(feedback.get("player_observable", false)):
			(report["visual_feedback_failures"] as Array).append({
				"decision_index": decision_index,
				"verb": str(choice.get("verb", "")),
				"accepted": accepted,
				"status": str(outcome.get("status", "")),
			})
		if bool(appended.get("ok", false)) and not bool(
				background_validation.get("ok", true)):
			(report["visual_feedback_failures"] as Array).append({
				"decision_index": decision_index,
				"verb": str(choice.get("verb", "")),
				"accepted": accepted,
				"status": str(outcome.get("status", "")),
				"background_event_kinds": background_validation.get(
					"event_kinds", []).duplicate(),
				"background_presentation_failures": background_validation.get(
					"failures", []).duplicate(),
			})
		var demonstrated := _writer_choice_demonstrated(
			choice, outcome, feedback, after, observation_samples)
		(report["actions"] as Array).append({
			"decision_index": decision_index,
			"verb": str(choice.get("verb", "")),
			"target_token": str(choice.get("target_token", "")),
			"visible_verb": str(choice.get("visible_verb", "")),
			"full_party_selection_already_visible": bool(choice.get(
				"full_party_selection_already_visible", false)),
			"accepted": accepted,
			"demonstrated": demonstrated,
			"reason": str(outcome.get("reason", "")),
			"production_event_count": int(input_receipt.get(
				"production_event_count", 0)),
			"new_event_kinds": receipt.get("new_event_kinds", []).duplicate(),
			"background_event_count": background_events.size(),
			"background_event_kinds": background_validation.get(
				"event_kinds", []).duplicate(),
			"background_visual_lineage": background_validation.duplicate(true),
			"intended_subjects": intended_subjects.duplicate(),
			"intended_members": receipt.get("intended_members", []).duplicate(),
			"member_results": receipt.get("member_results", {}).duplicate(true),
			"visible_cues": int(outcome.get("cue_count", 0)),
			"observation_sample_count": observation_samples.size(),
			"pointer_parked_after_click": bool(receipt.get(
				"pointer_parked_after_click", false)),
			"pointer_park_receipt": (receipt.get(
				"pointer_park_receipt", {}) as Dictionary).duplicate(true),
			"evidence": evidence,
		})
		_validation_action_context.clear()
		report["decision_count"] = int(report["decision_count"]) + 1
		if _policy_should_stop(after):
			break
	var final_observation: Dictionary = await _presented_snapshot()
	_record_party_sweep_phases(final_observation)
	_validation_set_navigation_edge_receipt_connection(false)
	_validation_action_context.clear()
	report["validation_navigation_edge_traversals"] = \
		_validation_navigation_edge_traversals.duplicate(true)
	var run_trace_complete := (report["trace_failures"] as Array).is_empty() \
		and (report["visual_feedback_failures"] as Array).is_empty() \
		and (report["evidence_failures"] as Array).is_empty()
	var finished: Dictionary = _trace.finish({
		"trace_complete": run_trace_complete,
		"diagnostics": {
			"trace_failure_count": (report["trace_failures"] as Array).size(),
			"visual_feedback_failure_count": (
				report["visual_feedback_failures"] as Array).size(),
			"evidence_failure_count": (report["evidence_failures"] as Array).size(),
		},
	})
	if not bool(finished.get("ok", false)):
		(report["trace_failures"] as Array).append(
			str(finished.get("error", "trace finish failed")))
	var trace_document := DecisionTraceScript.read_trace(_trace_path)
	if not bool(trace_document.get("ok", false)):
		(report["trace_failures"] as Array).append({
			"error": "sealed trace read-back failed",
			"details": trace_document.get("errors", []).duplicate(),
		})
	else:
		var sealed_summary := trace_document.get("summary", {}) as Dictionary
		report["persona_goal_reached"] = bool(sealed_summary.get(
			"persona_goal_reached", false))
		report["goal_evidence"] = (sealed_summary.get(
			"goal_evidence", {}) as Dictionary).duplicate(true)
		report["party_sweep_observed"] = _persona == "dean_takahashi" \
			and bool(sealed_summary.get("persona_goal_reached", false))
		var sealed_decisions: Array = trace_document.get("decisions", [])
		report["decision_count"] = sealed_decisions.size()
		report["accepted_count"] = 0
		report["refused_count"] = 0
		for record_v in sealed_decisions:
			if not (record_v is Dictionary):
				continue
			var sealed_outcome := (record_v as Dictionary).get(
				"outcome", {}) as Dictionary
			if str(sealed_outcome.get("status", "")) == "accepted":
				report["accepted_count"] = int(report["accepted_count"]) + 1
			elif str(sealed_outcome.get("status", "")) == "refused":
				report["refused_count"] = int(report["refused_count"]) + 1
	report["final_observation"] = final_observation
	report["finish_result"] = finished.duplicate(true)
	report["ok"] = (report["trace_failures"] as Array).is_empty() \
		and (report["visual_feedback_failures"] as Array).is_empty() \
		and (report["evidence_failures"] as Array).is_empty() \
		and bool((trace_document.get("summary", {}) as Dictionary).get(
			"trace_complete", false))
	print("[PERSONA_TRACE] %s" % ProjectSettings.globalize_path(_trace_path))
	return report


func _on_validation_external_traversal_started(
		character_id: String, state: Dictionary) -> void:
	if _validation_action_context.is_empty():
		return
	var edge_value: Variant = state.get("navigation_edge", {})
	if not (edge_value is Dictionary):
		return
	var edge := edge_value as Dictionary
	if edge.is_empty() \
			or str(edge.get("category", "")) != "connector" \
			or str(edge.get("kind", "")).strip_edges().is_empty() \
			or str(edge.get("type", "")).strip_edges().is_empty() \
			or not (edge.get("from_cell") is Vector2i) \
			or not (edge.get("to_cell") is Vector2i) \
			or not edge.has("from_level") or int(edge.get("from_level", -1)) < 0 \
			or not edge.has("to_level") or int(edge.get("to_level", -1)) < 0:
		return
	_validation_navigation_edge_traversals.append({
		"validation_only": true,
		"source_signal": "external_traversal_started",
		"decision_index": int(_validation_action_context.get(
			"decision_index", -1)),
		"decision_verb": str(_validation_action_context.get("verb", "")),
		"intended_subjects": (_validation_action_context.get(
			"intended_subjects", []) as Array).duplicate(),
		"character_id": character_id,
		"traversal_id": str(state.get("traversal_id", "")),
		"navigation_edge": edge.duplicate(true),
	})


func _validation_set_navigation_edge_receipt_connection(enabled: bool) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	var validation_game_state = _host.get("_game_state")
	if validation_game_state == null \
			or not validation_game_state.has_signal("external_traversal_started"):
		return
	var callback := Callable(self, "_on_validation_external_traversal_started")
	var connected: bool = validation_game_state.is_connected(
		"external_traversal_started", callback)
	if enabled and not connected:
		validation_game_state.connect("external_traversal_started", callback)
	elif not enabled and connected:
		validation_game_state.disconnect("external_traversal_started", callback)


func _choose_decision(observation: Dictionary, decision_index: int) -> Dictionary:
	if _persona == "dean_takahashi" \
			and _policy_phase == "await_missed_rise":
		return {
			"verb": "wait",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "visible_rising_basin_sweep_risk",
			"wait_seconds": 20.0,
			"wait_until": "dean_sweep_terminal",
			"rationale": "Dean watches what happens after committing the full party to a floor point whose shipped hover annotation warned RISK: RISING BASIN SWEEP.",
			"policy_nodes": ["dean_takahashi_watch_visible_risk_fumble_resolve"],
		}
	if _persona == "dean_takahashi" \
			and _observation_has_announced_sweep(observation):
		return {
			"verb": "wait",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "visible_announced_basin_sweep",
			"wait_seconds": 8.0,
			"wait_until": "dean_sweep_terminal",
			"rationale": "Dean stops mashing unrelated controls long enough to watch the explicitly announced Basin current resolve.",
			"policy_nodes": ["dean_takahashi_wait_for_visible_announced_sweep"],
		}
	if _persona == "eazy_speezy" and _policy_phase == "clear_view":
		return {
			"verb": "toggle_instructions",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "visible_h_hide_control",
			"rationale": "Eazy uses the advertised H Hide control so the instruction card does not cover the marked upper-deck route.",
			"policy_nodes": ["hide_instructions_when_they_occlude_the_board"],
			"learning_candidate": _hide_instructions_candidate(observation),
		}
	if _persona == "eazy_speezy" and _policy_phase == "orient_start":
		# Hiding the briefing can reveal the complete marked route immediately. A
		# human speedrunner does not press Home as a ritual when the current frame
		# already advertises ROUTE VIA LADDER; that unnecessary camera mutation was
		# hiding the route and sending the policy into a recenter loop.
		if _observation_has_ladder_route(observation):
			_policy_phase = "seek_deck"
		else:
			return {
				"verb": "recenter",
				"world_change": false,
				"intended_subjects": [],
				"target_token": "camera_center",
				"rationale": "Eazy moves the pointer out of the edge-scroll band and uses the advertised Home control because the marked ladder route is not visible.",
				"policy_nodes": ["recenter_before_reading_visible_route"],
			}
	if _persona == "eazy_speezy" and _policy_phase == "frame_level":
		if _observation_has_ladder_route(observation):
			_policy_phase = "seek_deck"
		else:
			if not _observation_has_party_body(observation) \
					or not _observation_has_deck_landmark(observation):
				return {
					"verb": "recenter",
					"world_change": false,
					"intended_subjects": [],
					"target_token": "camera_center",
					"rationale": "Eazy uses the advertised Home control because the visible party or DECK ACCESS marker has left the frame.",
					"policy_nodes": ["recenter_when_visible_route_information_is_lost"],
				}
			return {
				"verb": "zoom_out",
				"world_change": false,
				"intended_subjects": [],
				"target_token": "camera_zoom_out",
				"rationale": "Eazy zooms out with the shipped mouse wheel because no ladder-annotated hover route is currently visible.",
				"policy_nodes": ["zoom_out_to_read_multi_level_structure"],
			}
	if _persona == "eazy_speezy" \
			and _policy_phase in EAZY_CROSSING_RECOVERY_PHASES \
			and not _crossing_failure_evidence.is_empty():
		if not _crossing_failure_has_arrival():
			return {
				"verb": "wait",
				"world_change": false,
				"intended_subjects": [],
				"target_token": "visible_crossing_failure_resolution",
				"wait_seconds": 8.0,
				"wait_until": "crossing_failure_arrival",
				"wait_lineage_signature": _crossing_failure_lineage_signature(
					_crossing_failure_evidence),
				"rationale": (
					"Eazy waits for the visible %s carry bound to %s to reach its matching shown destination before choosing another route."
					% [
						str(_crossing_failure_evidence.get(
							"label", "crossing failure")),
						str(_crossing_failure_evidence.get(
							"portrait_label", "party portrait")),
					]),
				"policy_nodes": [
					"wait_for_visible_crossing_failure_arrival"],
			}
		# Only a consequence explicitly bound to a visible party portrait can
		# falsify the console's "full group" promise. Ambient SWEPT/ARRIVED HUD
		# text may belong to a dweller and is deliberately insufficient.
		_policy_phase = "recover_crossing_route"
		_shelter_completion_observed = false
		var recovery := _choose_ground(observation, decision_index)
		if not recovery.is_empty():
			recovery["rationale"] = (
				"Eazy saw %s visibly bound to %s instead of a shelter arrival, so returns the party to a marked ladder route before trying the crossing again."
				% [
					str(_crossing_failure_evidence.get(
						"label", "a crossing failure")),
					str(_crossing_failure_evidence.get(
						"portrait_label", "a party portrait")),
				]
			)
			recovery["policy_nodes"] = [
				"eazy_speezy_recover_visible_crossing_failure"]
			# The evidence was visible in an earlier wait sample, not necessarily
			# the next pre-action frame. Do not emit a candidate whose public
			# predicate cannot match that pre-action observation.
			recovery.erase("learning_candidate")
			return recovery
		return {
			"verb": "recenter",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "camera_center",
			"rationale": "Eazy saw a portrait-bound crossing failure and uses the advertised Home control to find the marked ladder route again.",
			"policy_nodes": [
				"eazy_speezy_reframe_after_visible_crossing_failure"],
		}
	if _persona == "eazy_speezy" and _policy_phase == "await_crossing" \
			and _party_visibly_near_label(observation, "SHELTER"):
		# The rendered bodies already attest that the announced crossing finished.
		# Do not manufacture a redundant pause as another successful "action";
		# continue with the next decision a player can actually make.
		_policy_phase = "rally_shelter"
	if _persona == "eazy_speezy" and _policy_phase == "await_crossing":
		var announced_wait_candidate := _announced_wait_candidate(observation)
		if not announced_wait_candidate.is_empty():
			# Prefer observing a currently rendered consequence over moving the
			# camera because a body or destination has left frame. The wait ends on
			# the public STAGING -> ARMED -> LAUNCHED transition; it never relies on
			# private assist phase or stale policy memory.
			return {
				"verb": "wait",
				"world_change": false,
				"intended_subjects": [],
				"target_token": "visible_announced_mid_crossing",
				"wait_seconds": 18.0,
				"wait_until": "announced_crossing_transition",
				"wait_cue_signature":
					_visible_announced_crossing_cue_signature(observation),
				"rationale": "Eazy watches the currently visible crossing announcement until its next rendered state transition.",
				"policy_nodes": ["wait_for_visible_announced_mid_crossing"],
				"learning_candidate": announced_wait_candidate,
			}
		if not _observation_has_party_body(observation) \
				or _visible_landmark_screens(observation, "SHELTER").is_empty():
			return {
				"verb": "recenter",
				"world_change": false,
				"intended_subjects": [],
				"target_token": "camera_center",
				"rationale": "Eazy uses the advertised Home control because the party or SHELTER marker left the frame during the announced crossing.",
				"policy_nodes": [
					"recenter_while_visible_crossing_information_is_lost"],
			}
		return {
			"verb": "wait",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "visible_announced_mid_crossing",
			"wait_seconds": 18.0,
			"wait_until": "party_near_shelter",
			"rationale": "Eazy waits on the live render clock for the announced next MID launch, watching the party move toward the visible SHELTER.",
			"policy_nodes": ["wait_for_visible_announced_mid_crossing"],
			"learning_candidate": _announced_wait_candidate(observation),
		}
	if _persona == "eazy_speezy" and _policy_phase == "await_shelter_retry":
		return {
			"verb": "wait",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "visible_shelter_waiting_receipt",
			"wait_seconds": 4.0,
			"rationale": "Eazy obeys the visible SHELTER WAITING receipt and lets the committed party movement finish before retrying.",
			"policy_nodes": ["wait_after_visible_shelter_refusal"],
		}
	if _persona == "eazy_speezy" and _policy_phase == "rally_shelter":
		var shelter_rally := _choose_visible_shelter_formation_surface(
			observation)
		if not shelter_rally.is_empty():
			return shelter_rally
		return _idle_choice()
	if _persona == "eazy_speezy" and _policy_phase == "select_party_for_shelter":
		if _all_visible_party_portraits_selected(observation):
			# The first group interaction intentionally preserves the full portrait
			# selection. A human sees that state and does not click the same portraits
			# again as a ritual; retain the visible precondition on the shelter action.
			_shelter_full_party_selection_observed = true
			_policy_phase = "seek_shelter"
		else:
			var visible_roster := _visible_party_member_ids(observation)
			return {
				"verb": "select_party",
				"world_change": false,
				"intended_subjects": visible_roster,
				"target_token": "hud_portraits",
				"rationale": "Eazy selects the complete visible portrait roster after Rally gathers everyone on the shelter pad.",
				"policy_nodes": ["eazy_speezy_select_full_party_for_shelter"],
				"learning_candidate": _select_visible_roster_candidate(observation),
			}
	if _persona == "eazy_speezy" and _policy_phase == "select_party":
		if _all_visible_party_portraits_selected(observation):
			_policy_phase = "seek_console"
		else:
			var visible_roster := _visible_party_member_ids(observation)
			return {
				"verb": "select_party",
				"world_change": false,
				"intended_subjects": visible_roster,
				"target_token": "hud_portraits",
				"rationale": "Eazy selects the complete visible portrait roster because the console says the group is launched together.",
				"policy_nodes": ["eazy_speezy_select_full_party_for_group_control"],
				"learning_candidate": _select_visible_roster_candidate(observation),
			}
	var state := observation.get("state", {}) as Dictionary
	var affordances: Array = state.get("affordances", [])
	var bins := state.get("viewport_bins", {}) as Dictionary
	var interaction := _choose_interaction(observation, decision_index)
	if not interaction.is_empty():
		if _persona == "eazy_speezy" and _policy_phase == "seek_shelter" \
				and _shelter_full_party_selection_observed:
			interaction["full_party_selection_already_visible"] = true
		return interaction
	if _persona == "eazy_speezy" and _policy_phase != "seek_deck":
		return _idle_choice()
	var ground_choice := _choose_ground(observation, decision_index)
	if not ground_choice.is_empty():
		return ground_choice
	return _idle_choice()


func _choose_interaction(observation: Dictionary,
		decision_index: int) -> Dictionary:
	var state := observation.get("state", {}) as Dictionary
	var affordances: Array = state.get("affordances", [])
	var bins := state.get("viewport_bins", {}) as Dictionary
	var visible_tokens: Array = bins.get("interact_visible", [])
	if visible_tokens.is_empty():
		return {}
	var candidates: Array[Dictionary] = []
	for token_v in visible_tokens:
		var candidate := _affordance(affordances, str(token_v))
		if candidate.is_empty():
			continue
		var verb := str(candidate.get("verb", "")).to_upper()
		var score := 30
		if _persona == "eazy_speezy":
			if _policy_phase == "seek_console":
				if not (verb.contains("ARM NEXT MID") or verb.contains("UPPER DECK")):
					continue
				score = 200
			elif _policy_phase == "seek_shelter":
				if not (verb.contains("SHELTER") or verb.contains("REST")):
					continue
				score = 200
			else:
				continue
		if verb.contains("READ"):
			score = maxi(score, 100)
		elif verb.contains("OPERATE") or verb.contains("USE") or verb.contains("OPEN"):
			score = maxi(score, 90)
		elif verb.contains("REST") or verb.contains("SHELTER") or verb.contains("EXIT"):
			score = maxi(score, 80 if _read_attempted else 10)
		if _used_interactions.has(str(candidate.get("token", ""))):
			score -= 60
		candidate = candidate.duplicate(true)
		candidate["score"] = score
		candidates.append(candidate)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score", 0)) != int(b.get("score", 0)):
			return int(a.get("score", 0)) > int(b.get("score", 0))
		return str(a.get("token", "")) < str(b.get("token", "")))
	var choose_interaction := _persona == "eazy_speezy" \
		or (_persona == "dean_takahashi" and decision_index % 4 == 2)
	if not choose_interaction:
		return {}
	var selected := candidates[0]
	var token := str(selected.get("token", ""))
	var actor_id := _visible_primary_actor_id(observation)
	var is_selected_party_group := str(selected.get(
		"verb", "")).to_upper().contains("ARM NEXT MID")
	# Build the typed roster explicitly. A ternary whose singleton branch is an
	# untyped Array raises at runtime when GDScript assigns it to Array[String].
	var intended_subjects: Array[String] = []
	if is_selected_party_group:
		intended_subjects = _visible_party_member_ids(observation)
	elif actor_id != "":
		intended_subjects.append(actor_id)
	if str(selected.get("verb", "")).to_upper().contains("READ"):
		_read_attempted = true
	var learning_candidate := _interaction_candidate(str(selected.get("verb", "")))
	# Dean's occasional interaction is deliberately exploratory/fumbling behavior,
	# not a recommendation that later generated-level agents should learn. Keep the
	# decision and its exact visible outcome in the trace without proposing a tree node.
	if _persona == "dean_takahashi":
		learning_candidate.clear()
	return {
		"verb": "interact",
		"world_change": true,
		"group_verb": is_selected_party_group,
		"intended_subjects": intended_subjects,
		"actor_id": actor_id,
		"preserve_visible_selection": _persona == "eazy_speezy",
		"target_token": token,
		"screen": selected.get("screen", []),
		"visible_verb": str(selected.get("verb", "")),
		"rationale": _interaction_rationale(str(selected.get("verb", ""))),
		"policy_nodes": ["%s_prioritize_visible_interaction" % _persona],
		"learning_candidate": learning_candidate,
	}


func _choose_ground(observation: Dictionary, decision_index: int) -> Dictionary:
	var state := observation.get("state", {}) as Dictionary
	var affordances: Array = state.get("affordances", [])
	var bins := state.get("viewport_bins", {}) as Dictionary
	var available: Array[Dictionary] = []
	for bin_name in GROUND_BIN_ORDER:
		for token_v in bins.get(bin_name, []):
			var candidate := _affordance(affordances, str(token_v))
			if not candidate.is_empty():
				candidate = candidate.duplicate(true)
				candidate["bin"] = bin_name
				available.append(candidate)
	if available.is_empty():
		return {}
	var selected: Dictionary = {}
	if _persona == "dean_takahashi":
		# Dean's fumble may be strategically foolish, but the test cannot secretly
		# infer which pixels belong to the catch basin. Prefer the shipped vertex
		# annotation that openly says a rise will sweep this floor, then hash among
		# those visible points to retain his arbitrary Rally behavior.
		var visible_sweep_risk: Array[Dictionary] = []
		for candidate in available:
			if str(candidate.get("consequence", "")).to_upper().contains(
					"RISING BASIN SWEEP"):
				visible_sweep_risk.append(candidate)
		if not visible_sweep_risk.is_empty():
			available = visible_sweep_risk
		else:
			# If the dangerous floor has left frame, retain a visibly arbitrary
			# unmarked-floor attempt. The subsequent outcome remains evidence only
			# if the production feedback proves what actually happened.
			var unmarked: Array[Dictionary] = []
			var access_screens := _cue_screens(observation, "DECK ACCESS")
			for candidate in available:
				if _screen_distance_to_any(
						candidate.get("screen", []), access_screens) > 144.0:
					unmarked.append(candidate)
			if not unmarked.is_empty():
				available = unmarked
		var index := absi(hash("%s:%d:%d" % [_persona, _run_index, decision_index])) \
			% available.size()
		selected = available[index]
	else:
		# Eazy may choose only a point whose shipped hover annotation visibly says the
		# route traverses a ladder. A nearby label alone is ambiguous on stacked decks:
		# its screen-space ray can land on an unrelated floor beneath it.
		var ladder_routes: Array[Dictionary] = []
		for candidate in available:
			if str(candidate.get("consequence", "")).to_upper().contains("LADDER"):
				ladder_routes.append(candidate)
		if ladder_routes.is_empty():
			return {}
		available = ladder_routes
		# A human who receives the rendered red whole-party refusal does not hold on
		# the exact same floor sample forever. Prefer another currently visible
		# ladder-annotated point while one remains; every attempt is still chosen
		# solely from the live player observation.
		var untried_routes: Array[Dictionary] = []
		for candidate in available:
			if not _used_ground.has(str(candidate.get("token", ""))):
				untried_routes.append(candidate)
		if not untried_routes.is_empty():
			available = untried_routes
		var access_screens := _cue_screens(observation, "DECK ACCESS")
		var best_distance := INF
		for candidate in available:
			var distance := _screen_distance_to_any(
				candidate.get("screen", []), access_screens)
			if distance < best_distance:
				best_distance = distance
				selected = candidate
		# If the authored marker is outside the camera, fall back to a fresh visible floor
		# sample; a subsequent Home-key recenter can reveal the label without hidden geometry.
		if selected.is_empty():
			for candidate in available:
				if not _used_ground.has(str(candidate.get("token", ""))):
					selected = candidate
					break
		if selected.is_empty():
			selected = available[decision_index % available.size()]
	var token := str(selected.get("token", ""))
	_used_ground[token] = true
	return {
		"verb": "rally",
		"world_change": true,
		"intended_subjects": _visible_party_member_ids(observation),
		"target_token": token,
		"screen": selected.get("screen", []),
		"visible_consequence": str(selected.get("consequence", "")),
		"rationale": _ground_rationale(str(selected.get("bin", ""))),
		"policy_nodes": [_rally_node_id()],
		"learning_candidate": _rally_candidate(selected),
	}


func _choose_visible_shelter_formation_surface(
		observation: Dictionary
	) -> Dictionary:
	var state := observation.get("state", {}) as Dictionary
	var affordances: Array = state.get("affordances", [])
	var bins := state.get("viewport_bins", {}) as Dictionary
	var visible_tokens: Array = bins.get("interact_visible", [])
	var selected: Dictionary = {}
	for token_v in visible_tokens:
		var candidate := _affordance(affordances, str(token_v))
		if candidate.is_empty():
			continue
		# The learned predicate is exact array membership for REST PARTY. Bind
		# execution to that same public verb; incidental SHELTER prose on another
		# visible interaction must never redirect a whole-party Rally.
		if str(candidate.get("kind", "")) == "interact" \
				and str(candidate.get("verb", "")).strip_edges().to_upper() \
					== "REST PARTY":
			selected = candidate
			break
	if selected.is_empty():
		return {}
	var shelter_verb := str(selected.get("verb", ""))
	return {
		"verb": "rally",
		"world_change": true,
		"intended_subjects": _visible_party_member_ids(observation),
		"target_token": str(selected.get("token", "")),
		"screen": selected.get("screen", []),
		"rationale": "Eazy holds Rally on the visible REST PARTY shelter surface, whose shown parking region gathers the complete roster before the interaction.",
		"policy_nodes": ["eazy_speezy_rally_full_party_to_visible_shelter"],
		"learning_candidate": _shelter_rally_candidate(shelter_verb),
	}


func _execute_choice(choice: Dictionary) -> Dictionary:
	var verb := str(choice.get("verb", ""))
	var screen: Array = choice.get("screen", [])
	var point := Vector2(float(screen[0]), float(screen[1])) \
		if screen.size() >= 2 else Vector2.INF
	match verb:
		"rally":
			return await _driver.call("rally_screen", point)
		"interact":
			var actor_id := str(choice.get("actor_id", ""))
			if bool(choice.get("group_verb", false)) \
					or bool(choice.get("preserve_visible_selection", false)):
				return await _driver.call(
					"interact_selected_screen", actor_id, point)
			return await _driver.call("interact_screen", actor_id, point)
		"move":
			return await _driver.call(
				"move_screen", str(choice.get("actor_id", "")), point)
		"select_party":
			return await _driver.call("select_party")
		"recenter":
			return await _driver.call("recenter")
		"toggle_instructions":
			return await _driver.call("toggle_instructions")
		"zoom_out":
			return await _driver.call("zoom_out", 6)
		"wait":
			var wait_seconds := maxf(0.1, float(choice.get("wait_seconds", 1.0)))
			var initial: Dictionary = await _presented_snapshot()
			var initial_signature := _visible_wait_progress_signature(initial)
			var announced_cue_signature := str(choice.get(
				"wait_cue_signature", ""))
			if announced_cue_signature == "":
				announced_cue_signature = \
					_visible_announced_crossing_cue_signature(initial)
			var announced_transition_seen := announced_cue_signature != "" \
				and _visible_announced_crossing_cue_signature(initial) \
					!= announced_cue_signature
			var announced_transition_elapsed := 0.0
			var announced_consequence_lineages: Dictionary = {}
			var dean_consequence_lineages: Dictionary = {}
			var wait_until := str(choice.get("wait_until", ""))
			var crossing_failure_wait_signature := str(choice.get(
				"wait_lineage_signature", ""))
			if wait_until == "dean_sweep_terminal":
				# The party goal tracks the warning roster, but the same Basin beat can
				# visibly carry other subjects. A human watching the consequence does
				# not stop on the first three arrivals while another visible body is
				# still in flight, so retain every active opaque lineage seen by this
				# wait until that exact token renders its arrival.
				_record_visible_forced_consequence_phases(
					initial, dean_consequence_lineages)
			var visible_progress := false
			var elapsed := 0.0
			var near_shelter_visible_samples := 0
			var party_stable_samples := 0
			var last_party_signature := ""
			while elapsed < wait_seconds:
				var step := minf(0.25, wait_seconds - elapsed)
				await get_tree().create_timer(step, true, false, false).timeout
				elapsed += step
				var presented: Dictionary = await _presented_snapshot()
				_record_presented_action_sample(presented, choice)
				visible_progress = visible_progress \
					or _visible_wait_progress_signature(presented) != initial_signature
				if wait_until == "announced_crossing_transition":
					announced_transition_seen = announced_transition_seen \
						or (announced_cue_signature != "" \
							and _visible_announced_crossing_cue_signature(presented) \
								!= announced_cue_signature)
					if announced_transition_seen:
						announced_transition_elapsed += step
						_record_visible_forced_consequence_phases(
							presented, announced_consequence_lineages)
						# A public ARMED -> LAUNCHED label is only the start of the
						# consequence interval. Keep observing any forced movement
						# that becomes visible immediately afterward through its
						# matching arrival. If no forced consequence appears, two
						# seconds of presented frames is a bounded human-scale grace
						# period before the next camera/route decision.
						if _visible_forced_consequence_lineages_complete(
								announced_consequence_lineages) \
								and (not announced_consequence_lineages.is_empty() \
									or announced_transition_elapsed \
										>= ANNOUNCED_TRANSITION_CONSEQUENCE_GRACE_SECONDS):
							break
				elif wait_until == "party_stable":
					if _presented_camera_ready(presented):
						var signature := _body_signature(presented)
						if signature == last_party_signature:
							party_stable_samples += 1
						else:
							party_stable_samples = 0
						last_party_signature = signature
						if party_stable_samples >= 4:
							break
					else:
						party_stable_samples = 0
						last_party_signature = ""
				elif wait_until == "party_near_shelter":
					if not _crossing_failure_evidence.is_empty():
						break
					near_shelter_visible_samples = \
						_next_party_near_label_sample_count(
							presented, "SHELTER", near_shelter_visible_samples)
					if near_shelter_visible_samples >= SHELTER_VISIBLE_SAMPLE_COUNT:
						break
				elif wait_until == "dean_sweep_terminal":
					_record_visible_forced_consequence_phases(
						presented, dean_consequence_lineages)
					if _dean_wait_can_seal(dean_consequence_lineages):
						break
				elif wait_until == "crossing_failure_arrival":
					# _record_presented_action_sample above updates only the exact
					# portrait/source/label/destination lineage. A vanished cue or an
					# unrelated arrival therefore consumes the bounded wait and fails
					# closed instead of granting a recovery Rally.
					if crossing_failure_wait_signature != "" \
							and _crossing_failure_has_arrival() \
							and _crossing_failure_lineage_signature(
								_crossing_failure_evidence) \
								== crossing_failure_wait_signature:
						break
			_wait_receipt_serial += 1
			visible_progress = visible_progress or announced_transition_seen
			return {
				"id": "wait_%d" % _wait_receipt_serial,
				"kind": "wait",
				# Waiting is an observation, not an automatically accepted command.
				# It can support a decision tree only when the shipped presentation
				# visibly changed while the player waited.
				"accepted": visible_progress,
				"visible_progress": visible_progress,
				"reason": "" if visible_progress else (
					"No visible presentation progress occurred during the bounded wait."),
				"player_reproducible": true,
			}
	return _driver.call("unavailable_action", verb, "No shipped gesture exists.")


func _wait_for_presented_settle(before: Dictionary, choice: Dictionary) -> Dictionary:
	if str(choice.get("verb", "")) == "wait":
		var waited: Dictionary = await _presented_snapshot()
		_record_presented_action_sample(waited, choice)
		return waited
	if str(choice.get("verb", "")) in ["recenter", "zoom_out"]:
		return await _wait_for_camera_settle(before, choice)
	if not bool(choice.get("world_change", true)):
		# Camera, HUD, and portrait gestures settle on rendered frames. Waiting for a
		# world-state delta here used to burn the Basin timer while a human-equivalent
		# H/Home/wheel action had already visibly completed.
		await get_tree().create_timer(0.35, true, false, false).timeout
		var presented: Dictionary = await _presented_snapshot()
		_record_presented_action_sample(presented, choice)
		return presented
	if _choice_requires_visible_result(choice):
		# A click-to-interact gesture queues an ordinary routed walk. The input receipt
		# proves only that the click was accepted; it does not prove that the character
		# reached the object or that the object accepted the interaction. Keep watching
		# the same presentation until the shipped UI shows the semantic result. Re-clicking
		# here cancels and restarts the committed walk, which no patient human player would
		# do while the queued path/glow is still visibly in progress.
		return await _wait_for_visible_interaction_result(before, choice)
	if str(choice.get("verb", "")) == "rally":
		return await _wait_for_visible_rally_terminal(before, choice)
	var before_bodies := _body_signature(before)
	var last_signature := before_bodies
	var stable_samples := 0
	var saw_change := false
	var elapsed := 0.0
	var current: Dictionary = before
	while elapsed < ACTION_SETTLE_LIMIT_SECONDS:
		await get_tree().create_timer(
			ACTION_SAMPLE_SECONDS, true, false, false).timeout
		elapsed += ACTION_SAMPLE_SECONDS
		current = await _presented_snapshot()
		_record_presented_action_sample(current, choice)
		var signature := _body_signature(current)
		saw_change = saw_change or signature != before_bodies \
			or not _new_visible_cues(before, current).is_empty()
		if signature == last_signature:
			stable_samples += 1
		else:
			stable_samples = 0
		last_signature = signature
		if saw_change and stable_samples >= STABLE_SAMPLE_COUNT:
			break
	return current


func _wait_for_visible_rally_terminal(before: Dictionary,
		choice: Dictionary) -> Dictionary:
	var current := before
	var samples_v: Variant = choice.get("_observation_samples", [])
	var samples: Array = samples_v as Array if samples_v is Array else []
	if not _new_exact_rally_terminal_result(before, choice, samples).is_empty():
		if not samples.is_empty() and samples[-1] is Dictionary:
			return (samples[-1] as Dictionary).duplicate(true)
		return current
	var elapsed := 0.0
	while elapsed < RALLY_SETTLE_LIMIT_SECONDS:
		await get_tree().create_timer(
			ACTION_SAMPLE_SECONDS, true, false, false).timeout
		elapsed += ACTION_SAMPLE_SECONDS
		current = await _presented_snapshot()
		_record_presented_action_sample(current, choice)
		samples_v = choice.get("_observation_samples", [])
		samples = samples_v as Array if samples_v is Array else []
		if not _new_exact_rally_terminal_result(
				before, choice, samples).is_empty():
			break
	# Fail closed at the fixed deadline. Generic screen-body stability is not a
	# movement result and therefore can never release the next policy action.
	return current


func _wait_for_camera_settle(before: Dictionary, choice: Dictionary) -> Dictionary:
	var current := before
	var last_signature := _body_signature(before)
	var stable_samples := 0
	var elapsed := 0.0
	while elapsed < 3.0:
		await get_tree().create_timer(
			ACTION_SAMPLE_SECONDS, true, false, false).timeout
		elapsed += ACTION_SAMPLE_SECONDS
		current = await _presented_snapshot()
		_record_presented_action_sample(current, choice)
		if not _presented_camera_ready(current):
			stable_samples = 0
			last_signature = ""
			continue
		var signature := _body_signature(current)
		if signature == last_signature:
			stable_samples += 1
		else:
			stable_samples = 0
		last_signature = signature
		if stable_samples >= STABLE_SAMPLE_COUNT:
			break
	return current


func _wait_for_visible_interaction_result(before: Dictionary,
		choice: Dictionary) -> Dictionary:
	var current := before
	var elapsed := 0.0
	var visible_stall_elapsed := 0.0
	var empty_elapsed := 0.0
	var last_progress_signature := _interaction_progress_signature(before)
	while elapsed < INTERACTION_RESULT_ABSOLUTE_LIMIT_SECONDS:
		await get_tree().create_timer(
			ACTION_SAMPLE_SECONDS, true, false, false).timeout
		elapsed += ACTION_SAMPLE_SECONDS
		current = await _presented_snapshot()
		_record_presented_action_sample(current, choice)
		if _visible_interaction_result(choice, before, current,
				choice.get("_observation_samples", [])):
			break

		# A routed interaction can include a long ordinary walk and multi-phase
		# consequence presentation. Keep waiting while a human can see either the
		# party or the presentation advance. A temporarily empty render sample is
		# granted a short grace period; a permanently empty or frozen presentation
		# still stops at the bounded stall window and hard ceiling.
		if _interaction_has_progress_signal(current):
			empty_elapsed = 0.0
			var signature := _interaction_progress_signature(current)
			if signature != last_progress_signature:
				visible_stall_elapsed = 0.0
				last_progress_signature = signature
			else:
				visible_stall_elapsed += ACTION_SAMPLE_SECONDS
		else:
			empty_elapsed += ACTION_SAMPLE_SECONDS
			if empty_elapsed > INTERACTION_RESULT_EMPTY_GRACE_SECONDS:
				visible_stall_elapsed += ACTION_SAMPLE_SECONDS
		if visible_stall_elapsed >= INTERACTION_RESULT_VISIBLE_STALL_SECONDS:
			break
	return current


func _interaction_progress_signature(observation: Dictionary) -> String:
	var presented_cues: Array = []
	var state := observation.get("state", {}) as Dictionary
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if not bool(cue.get("visible", false)) or str(cue.get("kind", "")) \
				not in ["hud", "consequence", "interaction_result", "rally"]:
			continue
		presented_cues.append(cue.duplicate(true))
	return DecisionTraceScript.canonical_json({
		"party_bodies": _body_positions(observation),
		"presented_cues": presented_cues,
	})


func _interaction_has_progress_signal(observation: Dictionary) -> bool:
	if not _body_positions(observation).is_empty():
		return true
	var state := observation.get("state", {}) as Dictionary
	for cue_v in state.get("cues", []):
		if cue_v is Dictionary and bool((cue_v as Dictionary).get("visible", false)) \
				and str((cue_v as Dictionary).get("kind", "")) \
					in ["hud", "consequence", "interaction_result", "rally"]:
			return true
	return false


func _choice_requires_visible_result(choice: Dictionary) -> bool:
	return str(choice.get("verb", "")) == "interact"


func _visible_interaction_result(choice: Dictionary, before: Dictionary,
		observation: Dictionary, observation_samples: Array = []) -> bool:
	return not _new_target_interaction_result(
		choice, before, observation, observation_samples).is_empty()


func _visible_interaction_acceptance(
		choice: Dictionary,
		before: Dictionary,
		observation: Dictionary,
		observation_samples: Array = []
	) -> Dictionary:
	if str(choice.get("verb", "")) != "interact":
		return {"accepted": true, "reason": "", "target_presentation": {}}
	var target_presentation := _new_target_interaction_result(
		choice, before, observation, observation_samples)
	var accepted := not target_presentation.is_empty() \
		and str(target_presentation.get("result", "")) == "success"
	var reason := ""
	if not accepted:
		reason = (
			"The exact visible target rendered a rejected interaction receipt."
			if str(target_presentation.get("result", "")) == "rejected"
			else "The exact visible target did not render a new interaction receipt."
		)
	return {
		"accepted": accepted,
		"reason": reason,
		"target_presentation": target_presentation,
	}


func _policy_acceptance_from_visible_result(choice: Dictionary,
		before: Dictionary, after: Dictionary, observation_samples: Array,
		receipt: Dictionary, visible_interaction_acceptance: Dictionary) -> bool:
	var verb := str(choice.get("verb", ""))
	if verb == "rally":
		if not bool(receipt.get("accepted", false)) \
				or not bool(receipt.get("input_issued", false)):
			return false
		var observations := observation_samples.duplicate(true)
		observations.append(after.duplicate(true))
		var movement_result := _new_exact_rally_terminal_result(
			before, choice, observations)
		return not movement_result.is_empty() \
			and bool(movement_result.get("accepted", false)) \
			and str(movement_result.get("phase", "")) == "arrival"
	if verb == "interact":
		return bool(visible_interaction_acceptance.get("accepted", false))
	return bool(receipt.get("accepted", false))


func _new_exact_rally_terminal_result(before: Dictionary,
		choice: Dictionary, post_observations: Array) -> Dictionary:
	if str(choice.get("verb", "")) != "rally":
		return {}
	var target_token := str(choice.get("target_token", ""))
	var expected_subjects := _visible_party_portrait_tokens(before)
	var expected_member_ids := _visible_party_member_ids(before)
	expected_member_ids.sort()
	var intended_member_ids := _sorted_unique_strings(
		choice.get("intended_subjects", []))
	if target_token == "" or expected_subjects.is_empty() \
			or not DecisionTraceScript.canonical_equal(
				expected_member_ids, intended_member_ids):
		return {}

	var baseline_serial := _highest_visible_movement_result_serial(before)
	var before_capture_serial := int(before.get("capture_serial", 0))
	var previous_capture_serial := before_capture_serial
	var lineages := {}
	for observation_v in post_observations:
		if not (observation_v is Dictionary):
			return {}
		var observation := observation_v as Dictionary
		if str(observation.get("schema", "")) != "player_observation_v1" \
				or str(observation.get("source", "")) != "player_observable":
			return {}
		var capture_serial := int(observation.get("capture_serial", 0))
		if capture_serial <= previous_capture_serial:
			return {}
		previous_capture_serial = capture_serial
		var state_v: Variant = observation.get("state", {})
		if not (state_v is Dictionary):
			return {}
		for cue_v in (state_v as Dictionary).get("cues", []):
			if not (cue_v is Dictionary):
				continue
			var cue := cue_v as Dictionary
			if str(cue.get("kind", "")) != "movement_result" \
					or not bool(cue.get("visible", false)):
				continue
			var serial := int(cue.get("presentation_serial", 0))
			if serial <= baseline_serial:
				continue
			var cue_subjects_v: Variant = cue.get("subjects", null)
			if not (cue_subjects_v is Array):
				return {}
			var cue_subjects := _sorted_unique_strings(cue_subjects_v)
			if cue_subjects.size() != (cue_subjects_v as Array).size():
				return {}
			var lineage: Dictionary = lineages.get(serial, {
				"presentation_serial": serial,
				"target_token": str(cue.get("target_token", "")),
				"subjects": cue_subjects,
				"accepted": bool(cue.get("accepted", false)),
				"reason": "",
				"phases": [],
				"phase_capture_serials": {},
				"last_phase_rank": -1,
				"consistent": true,
			})
			if str(lineage.get("target_token", "")) \
					!= str(cue.get("target_token", "")) \
					or not DecisionTraceScript.canonical_equal(
						lineage.get("subjects", []), cue_subjects) \
					or bool(lineage.get("accepted", false)) \
						!= bool(cue.get("accepted", false)):
				lineage["consistent"] = false
			var phase := str(cue.get("phase", "")).to_lower()
			var phase_rank := int({
				"accepted": 0,
				"progress": 1,
				"arrival": 2,
				"interrupted": 2,
				"refused": 0,
			}.get(phase, -1))
			var last_phase_rank := int(lineage.get("last_phase_rank", -1))
			if phase_rank < 0 or (last_phase_rank >= 0 \
					and (phase_rank < last_phase_rank \
						or phase_rank > last_phase_rank + 1)):
				lineage["consistent"] = false
			lineage["last_phase_rank"] = maxi(last_phase_rank, phase_rank)
			var phases := lineage.get("phases", []) as Array
			var phase_capture_serials := lineage.get(
				"phase_capture_serials", {}) as Dictionary
			if not phases.has(phase):
				phases.append(phase)
				phase_capture_serials[phase] = capture_serial
			elif phase in ["arrival", "interrupted"]:
				phase_capture_serials[phase] = capture_serial
			lineage["phases"] = phases
			lineage["phase_capture_serials"] = phase_capture_serials
			var reason := str(cue.get("reason", "")).strip_edges()
			if reason != "":
				lineage["reason"] = reason
			lineage["phase"] = phase
			lineages[serial] = lineage

	# A gesture owns one new public movement presentation lineage. Multiple new
	# serials, a wrong target, a partial roster, or a skipped phase all fail closed.
	if lineages.size() != 1:
		return {}
	var lineage := (lineages.values()[0] as Dictionary).duplicate(true)
	if not bool(lineage.get("consistent", false)) \
			or str(lineage.get("target_token", "")) != target_token \
			or not DecisionTraceScript.canonical_equal(
				lineage.get("subjects", []), expected_subjects):
		return {}
	var phases := lineage.get("phases", []) as Array
	var phase_capture_serials := lineage.get(
		"phase_capture_serials", {}) as Dictionary
	if bool(lineage.get("accepted", false)):
		var terminal_phase := ""
		if DecisionTraceScript.canonical_equal(
				phases, ["accepted", "progress", "arrival"]):
			terminal_phase = "arrival"
		elif DecisionTraceScript.canonical_equal(
				phases, ["accepted", "progress", "interrupted"]):
			terminal_phase = "interrupted"
		var reason := str(lineage.get("reason", "")).strip_edges()
		if terminal_phase == "" \
				or (terminal_phase == "arrival" and reason != "") \
				or (terminal_phase == "interrupted" and reason == "") \
				or not (int(phase_capture_serials.get("accepted", 0)) \
					< int(phase_capture_serials.get("progress", 0)) \
					and int(phase_capture_serials.get("progress", 0)) \
					< int(phase_capture_serials.get(terminal_phase, 0))):
			return {}
		lineage["phase"] = terminal_phase
		return lineage
	if not DecisionTraceScript.canonical_equal(phases, ["refused"]) \
			or str(lineage.get("reason", "")).strip_edges() == "":
		return {}
	lineage["phase"] = "refused"
	return lineage


func _highest_visible_movement_result_serial(observation: Dictionary) -> int:
	var highest := 0
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return highest
	for cue_v in (state_v as Dictionary).get("cues", []):
		if cue_v is Dictionary \
				and str((cue_v as Dictionary).get("kind", "")) == "movement_result" \
				and bool((cue_v as Dictionary).get("visible", false)):
			highest = maxi(highest, int((cue_v as Dictionary).get(
				"presentation_serial", 0)))
	return highest


func _sorted_unique_strings(values_v: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (values_v is Array):
		return result
	for value_v in values_v as Array:
		var value := str(value_v)
		if value != "" and not result.has(value):
			result.append(value)
	result.sort()
	return result


func _new_target_interaction_result(
		choice: Dictionary,
		before: Dictionary,
		after: Dictionary,
		observation_samples: Array = []
	) -> Dictionary:
	var target_token := str(choice.get("target_token", ""))
	if target_token == "":
		return {}
	var baseline := _target_interaction_result(before, target_token)
	var candidate: Dictionary = {}
	var observations: Array = observation_samples.duplicate()
	observations.append(after)
	for observation_v in observations:
		if not (observation_v is Dictionary):
			continue
		var presented := _target_interaction_result(
			observation_v as Dictionary, target_token)
		if int(presented.get("presentation_serial", 0)) \
				> int(candidate.get("presentation_serial", 0)):
			candidate = presented
	if int(candidate.get("presentation_serial", 0)) \
			<= int(baseline.get("presentation_serial", 0)):
		return {}
	return candidate


func _target_interaction_result(
		observation: Dictionary, target_token: String
	) -> Dictionary:
	var newest: Dictionary = {}
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return newest
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "interaction_result" \
				or str(cue.get("source_token", "")) != target_token \
				or not bool(cue.get("visible", false)) \
				or str(cue.get("result", "")) not in ["success", "rejected"]:
			continue
		if int(cue.get("presentation_serial", 0)) \
				> int(newest.get("presentation_serial", 0)):
			newest = cue.duplicate(true)
	return newest


func _record_immediate_post_input_sample(before: Dictionary,
		choice: Dictionary, receipt: Dictionary) -> Dictionary:
	if str(choice.get("verb", "")) == "wait" \
			or not bool(receipt.get("input_issued", false)):
		return {}
	var immediate: Dictionary = await _presented_snapshot()
	_record_presented_action_sample(immediate, choice)
	var capture_serial := int(immediate.get("capture_serial", 0))
	receipt["first_post_input_capture_serial"] = capture_serial
	# Do not repair or synthesize a bad observer sequence. The trace validator
	# will fail closed if this fresh post-input capture is not newer than before.
	return immediate


func _presented_snapshot() -> Dictionary:
	# Observation is visual evidence, so a rendered run must sample only after the
	# frame containing the latest shipped input/state transition has actually been
	# presented. Timers and process callbacks can otherwise see new HUD text while
	# the framebuffer still contains the preceding world cue. Headless fixtures
	# have no draw signal and retain the immediate deterministic snapshot path.
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		await RenderingServer.frame_post_draw
	if _observer == null or not is_instance_valid(_observer):
		return {}
	var observed_v: Variant = _observer.call("snapshot")
	return (observed_v as Dictionary).duplicate(true) \
		if observed_v is Dictionary else {}


func _record_presented_action_sample(current: Dictionary,
		choice: Dictionary) -> void:
	# Persist the complete public observation for every bounded wait/settle
	# sample. Result pulses and Basin warning/carry/arrival frames are transient;
	# reducing them to hand-picked cues would let caller code forge the evidence
	# the v3 writer is required to derive independently. The writer performs the
	# canonical exact de-duplication before hashing the record.
	_record_party_sweep_phases(current)
	var samples: Array = choice.get("_observation_samples", [])
	samples.append(current.duplicate(true))
	choice["_observation_samples"] = samples


func _selected_portrait_tokens(observation: Dictionary) -> Dictionary:
	var selected := {}
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return selected
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return selected
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if bool(portrait.get("selected", false)):
			var label := str(portrait.get("label", "")).strip_edges().to_lower()
			var token := str(portrait.get("token", ""))
			if label != "" and token != "":
				selected[label] = token
	return selected


func _visible_party_member_ids(observation: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return result
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return result
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("visible", false)):
			continue
		var subject_id := str(portrait.get("label", "")).strip_edges() \
			.to_snake_case().to_lower()
		if subject_id != "" and not result.has(subject_id):
			result.append(subject_id)
	return result


func _visible_party_portrait_tokens(observation: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return result
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return result
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		var token := str(portrait.get("token", ""))
		if bool(portrait.get("visible", false)) and token != "" \
				and not result.has(token):
			result.append(token)
	result.sort()
	return result


func _visible_primary_actor_id(observation: Dictionary) -> String:
	var state := observation.get("state", {}) as Dictionary
	var hud := state.get("hud", {}) as Dictionary
	var first_visible := ""
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("visible", false)):
			continue
		var subject_id := str(portrait.get("label", "")).strip_edges() \
			.to_snake_case().to_lower()
		if subject_id == "":
			continue
		if first_visible == "":
			first_visible = subject_id
		if bool(portrait.get("active", false)) \
				or bool(portrait.get("selected", false)):
			return subject_id
	return first_visible


func _all_visible_party_portraits_selected(observation: Dictionary) -> bool:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return false
	var hud_v: Variant = (state_v as Dictionary).get("hud", {})
	if not (hud_v is Dictionary):
		return false
	var visible_count := 0
	var selected_count := 0
	for portrait_v in (hud_v as Dictionary).get("portraits", []):
		if not (portrait_v is Dictionary) \
				or not bool((portrait_v as Dictionary).get("visible", false)):
			continue
		visible_count += 1
		if bool((portrait_v as Dictionary).get("selected", false)):
			selected_count += 1
	return visible_count > 0 and selected_count == visible_count


func _new_visible_cues(before: Dictionary, after: Dictionary) -> Array:
	var before_keys := {}
	for cue_v in ((before.get("state", {}) as Dictionary).get("cues", []) as Array):
		before_keys[DecisionTraceScript.canonical_json(cue_v)] = true
	var result: Array = []
	for cue_v in ((after.get("state", {}) as Dictionary).get("cues", []) as Array):
		if not before_keys.has(DecisionTraceScript.canonical_json(cue_v)):
			result.append((cue_v as Dictionary).duplicate(true) if cue_v is Dictionary else cue_v)
	return result


func _body_positions(observation: Dictionary) -> Dictionary:
	var result := {}
	for cue_v in ((observation.get("state", {}) as Dictionary).get("cues", []) as Array):
		if cue_v is Dictionary and str((cue_v as Dictionary).get("kind", "")) == "party_body":
			result[str((cue_v as Dictionary).get("source_token", ""))] = \
				(cue_v as Dictionary).get("screen", []).duplicate()
	return result


func _body_signature(observation: Dictionary) -> String:
	return DecisionTraceScript.canonical_json(_body_positions(observation))


func _presented_camera_ready(observation: Dictionary) -> bool:
	var body_count := 0
	var move_count := 0
	var state := observation.get("state", {}) as Dictionary
	for cue_v in state.get("cues", []):
		if cue_v is Dictionary \
				and str((cue_v as Dictionary).get("kind", "")) == "party_body":
			body_count += 1
	for affordance_v in state.get("affordances", []):
		if affordance_v is Dictionary \
				and str((affordance_v as Dictionary).get("kind", "")) == "move":
			move_count += 1
	var visible_roster_size := _visible_party_member_ids(observation).size()
	return visible_roster_size > 0 and body_count >= visible_roster_size \
		and move_count > 0


func _trace_receipt(receipt: Dictionary, choice: Dictionary,
		observation_before: Dictionary, observation_samples: Array,
		observation_after: Dictionary) -> Dictionary:
	var verb := str(choice.get("verb", ""))
	var first_post_capture_serial := int(receipt.get(
		"first_post_input_capture_serial", 0))
	if first_post_capture_serial <= 0 and not observation_samples.is_empty() \
			and observation_samples[0] is Dictionary:
		first_post_capture_serial = int((observation_samples[0] as Dictionary).get(
			"capture_serial", 0))
	if first_post_capture_serial <= 0:
		first_post_capture_serial = int(observation_after.get("capture_serial", 0))
	if verb != "wait" or bool(receipt.get("input_issued", false)):
		receipt = _merge_auxiliary_input_receipts(receipt)
		var lifted := DecisionTraceScript.shipped_input_receipt(
			receipt, "keyboard_pointer")
		lifted["verb"] = verb
		lifted["observation_before_capture_serial"] = int(
			observation_before.get("capture_serial", 0))
		lifted["first_post_input_capture_serial"] = first_post_capture_serial
		lifted["input_target_token"] = str(choice.get("target_token", ""))
		return lifted
	return {
		"receipt_id": str(receipt.get("id", "wait")),
		"boundary": "player_command",
		"status": "observed",
		"player_reproducible": true,
		"verb": "wait",
		"atomic_group": false,
		"production_event_count": 0,
		"production_event_kinds": [],
		"input_issued": false,
		"input_event_count": 0,
		"input_events": [],
		"visible_progress": bool(receipt.get("visible_progress", false)),
	}


func _merge_auxiliary_input_receipts(receipt: Dictionary) -> Dictionary:
	var merged := receipt.duplicate(true)
	for auxiliary_key in ["pointer_park_receipt"]:
		var auxiliary_value: Variant = merged.get(auxiliary_key, null)
		if not (auxiliary_value is Dictionary):
			continue
		var auxiliary := auxiliary_value as Dictionary
		if not bool(auxiliary.get("input_issued", false)):
			continue
		var merged_after := int(merged.get("input_sequence_after", -1))
		var auxiliary_before := int(auxiliary.get("input_sequence_before", -2))
		if merged_after < 0 or auxiliary_before != merged_after:
			# Leave the discontinuity intact. The trace ledger will fail closed
			# instead of papering over an unrecorded input gap.
			continue
		var merged_events: Array = merged.get("input_events", []).duplicate(true) \
			if merged.get("input_events", null) is Array else []
		if auxiliary.get("input_events", null) is Array:
			merged_events.append_array(auxiliary.get("input_events", []))
		merged["input_events"] = merged_events
		merged["input_event_count"] = merged_events.size()
		merged["input_sequence_after"] = int(auxiliary.get(
			"input_sequence_after", merged_after))
		merged["input_issued"] = not merged_events.is_empty()
	return merged


func _affordance(affordances: Array, token: String) -> Dictionary:
	for raw in affordances:
		if raw is Dictionary and str((raw as Dictionary).get("token", "")) == token:
			return raw as Dictionary
	return {}


func _matching_visible_interaction_verb(affordances: Array,
		markers: Array) -> String:
	var matches: Array[String] = []
	var requires_shelter := false
	for raw_marker in markers:
		requires_shelter = requires_shelter \
			or str(raw_marker).strip_edges().to_upper() == "SHELTER"
	for raw_affordance in affordances:
		if not (raw_affordance is Dictionary):
			continue
		var affordance := raw_affordance as Dictionary
		if str(affordance.get("kind", "")) != "interact":
			continue
		var verb := str(affordance.get("verb", "")).strip_edges()
		var verb_upper := verb.to_upper()
		var upper := ("%s %s" % [
			verb, str(affordance.get("consequence", "")),
		]).strip_edges().to_upper()
		if requires_shelter:
			# The shelter route binds either the production REST PARTY phrase or an
			# affordance explicitly labelled SHELTER. Incidental prose such as READ
			# REST NOTES is not the party-rest verb and cannot win by lexical order.
			if verb_upper == "REST PARTY" or upper.contains("SHELTER"):
				matches.append(verb)
			continue
		for raw_marker in markers:
			var marker := str(raw_marker).to_upper()
			# A generic exact-word match remains available to non-shelter callers.
			var marker_matches := upper.contains(marker)
			if marker == "REST":
				marker_matches = upper == marker or upper.begins_with("%s " % marker) \
					or upper.contains(" %s " % marker) \
					or upper.ends_with(" %s" % marker)
			if marker_matches:
				matches.append(verb)
				break
	matches.sort()
	return "" if matches.is_empty() else matches[0]


func _interaction_rationale(verb: String) -> String:
	if _persona == "dean_takahashi":
		return "Dean clicks the visible %s prompt without checking whether it advances the puzzle." % verb
	return "Eazy prioritizes the visible %s prompt before wandering to another floor target." % verb


func _ground_rationale(bin_name: String) -> String:
	if _persona == "dean_takahashi":
		return "Dean ignores the visible DECK ACCESS marker and issues a pointless Rally toward an arbitrary %s floor target." % bin_name
	return "Eazy reads the visible instructions and rallies the full party toward the marked DECK ACCESS target in %s." % bin_name


func _rally_node_id() -> String:
	return "dean_takahashi_rally_unmarked_visible_floor" \
		if _persona == "dean_takahashi" \
		else "eazy_speezy_rally_marked_deck_access"


func _rally_candidate(selected_affordance: Dictionary = {}) -> Dictionary:
	var conditions := _visible_ground_conditions()
	var target_ref := "chosen_visible_ground"
	var expected := {"path": "accepted", "op": "eq", "value": true}
	if _persona == "eazy_speezy":
		conditions = _visible_ladder_route_conditions(str(
			selected_affordance.get("consequence", "")))
		target_ref = "matching_visible_ladder_route"
	else:
		expected = {"any": [
			{"path": "accepted", "op": "eq", "value": true},
			{"path": "status", "op": "eq", "value": "refused"},
		]}
	if conditions.is_empty():
		return {}
	return {
		"node_id": _rally_node_id(),
		"rule": _ground_rationale("screen-space"),
		"scope": "fragment",
		"priority": 40 if _persona == "dean_takahashi" else 60,
		"condition": {"any": conditions},
		"action": {"verb": "rally", "target_ref": target_ref},
		"expected": expected,
	}


func _shelter_rally_candidate(visible_shelter_verb: String) -> Dictionary:
	if visible_shelter_verb.strip_edges() == "":
		return {}
	return {
		"node_id": "eazy_speezy_rally_full_party_to_visible_shelter",
		"rule": "When REST PARTY is visible, hold Rally on that exact shelter surface so its shown formation region gathers the full party before interacting.",
		"scope": "fragment",
		"priority": 68,
		"condition": {"path": "visible_affordance_verbs", "op": "contains",
			"value": visible_shelter_verb},
		"action": {
			"verb": "rally",
			"target_ref": "matching_visible_shelter_surface",
		},
		"expected": {"path": "accepted", "op": "eq", "value": true},
	}


func _idle_choice() -> Dictionary:
	_idle_decision_count += 1
	if _idle_decision_count % 2 == 1:
		return {
			"verb": "recenter",
			"world_change": false,
			"intended_subjects": [],
			"target_token": "camera_center",
			"rationale": "%s uses the visible Home-camera control to find the party and the next rendered cue."
				% _persona,
			"policy_nodes": ["recenter_when_visible_route_information_is_lost"],
		}
	return {
		"verb": "wait",
		"world_change": false,
		"intended_subjects": [],
		"target_token": "",
		"rationale": "%s waits for the announced movement or consequence to finish before choosing again."
			% _persona,
		"policy_nodes": ["wait_for_visible_information"],
	}


func _cue_screens(observation: Dictionary, text_fragment: String) -> Array[Vector2]:
	var screens: Array[Vector2] = []
	var needle := text_fragment.to_upper()
	for cue_v in ((observation.get("state", {}) as Dictionary).get("cues", []) as Array):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if not str(cue.get("text", "")).to_upper().contains(needle):
			continue
		var screen: Array = cue.get("screen", [])
		if screen.size() >= 2:
			screens.append(Vector2(float(screen[0]), float(screen[1])))
	return screens


func _visible_landmark_screens(observation: Dictionary,
		label_text: String) -> Array[Vector2]:
	var screens := _cue_screens(observation, label_text)
	var markers: Array[String] = [label_text.to_upper()]
	if label_text.to_upper().contains("SHELTER"):
		markers.append("REST")
	var state := observation.get("state", {}) as Dictionary
	for affordance_v in state.get("affordances", []):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		if str(affordance.get("kind", "")) != "interact":
			continue
		var presented_text := "%s %s" % [
			str(affordance.get("verb", "")),
			str(affordance.get("consequence", "")),
		]
		var matches := false
		for marker in markers:
			if presented_text.to_upper().contains(marker):
				matches = true
				break
		if not matches:
			continue
		var screen: Array = affordance.get("screen", [])
		if screen.size() < 2:
			continue
		var point := Vector2(float(screen[0]), float(screen[1]))
		if not screens.has(point):
			screens.append(point)
	return screens


func _visible_wait_progress_signature(observation: Dictionary) -> String:
	# Ignore trace provenance tick. This signature contains only presentation a
	# waiting player can see change: body pixels, visible cues, and affordances.
	var state := observation.get("state", {}) as Dictionary
	return DecisionTraceScript.canonical_json({
		"party_bodies": _body_positions(observation),
		"cues": state.get("cues", []).duplicate(true),
		"affordances": state.get("affordances", []).duplicate(true),
	})


func _visible_announced_crossing_cue_signature(observation: Dictionary) -> String:
	var announced_text: Array[String] = []
	for cue_v in ((observation.get("state", {}) as Dictionary).get(
			"cues", []) as Array):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		var text := ("%s %s" % [
			str(cue.get("text", "")), str(cue.get("label", "")),
		]).strip_edges().to_upper()
		if not bool(cue.get("visible", false)) \
				or not (text.contains("CROSSING STAGING") \
					or text.contains("CROSSING ARMED") \
					or text.contains("NEXT MID")):
			continue
		if not announced_text.has(text):
			announced_text.append(text)
	announced_text.sort()
	return DecisionTraceScript.canonical_json(announced_text) \
		if not announced_text.is_empty() else ""


func _record_visible_forced_consequence_phases(observation: Dictionary,
		lineages: Dictionary) -> void:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		var phase := str(cue.get("phase", "")).to_lower()
		var source_token := str(cue.get("source_token", ""))
		var label := str(cue.get("label", cue.get("text", ""))).strip_edges()
		var destination := str(cue.get("destination_label", "")).strip_edges()
		if str(cue.get("kind", "")) != "consequence" \
				or not bool(cue.get("visible", false)) \
				or phase not in ["active", "arrival"] \
				or source_token == "" or label == "":
			continue
		var lineage_key := "%s|%s|%s" % [
			source_token, label.to_upper(), destination.to_upper(),
		]
		# This bounded wait owns only consequences whose active phase it actually
		# saw. An arrival from an older lineage must not create a new obligation or
		# let a same-label subject close somebody else's movement.
		if phase == "arrival" and not lineages.has(lineage_key):
			continue
		var phases_v: Variant = lineages.get(lineage_key, {})
		var phases: Dictionary = (phases_v as Dictionary).duplicate(true) \
			if phases_v is Dictionary else {}
		phases[phase] = true
		lineages[lineage_key] = phases


func _visible_forced_consequence_lineages_complete(lineages: Dictionary) -> bool:
	if lineages.is_empty():
		return true
	for phases_v in lineages.values():
		if not (phases_v is Dictionary):
			return false
		var phases := phases_v as Dictionary
		if not bool(phases.get("active", false)) \
				or not bool(phases.get("arrival", false)):
			return false
	return true


func _dean_wait_can_seal(visible_consequence_lineages: Dictionary) -> bool:
	# Dean's persona goal names the visible warning roster. The passive-wait
	# evidence boundary is broader: any additional active consequence that a
	# player can see during the same wait must reach its own same-token arrival
	# before the interval is sealed and handed to post-hoc validation.
	return _dean_sweep_goal_reached() \
		and _visible_forced_consequence_lineages_complete(
			visible_consequence_lineages)


func _screen_distance_to_any(screen_value: Variant, targets: Array[Vector2]) -> float:
	if not (screen_value is Array) or (screen_value as Array).size() < 2 \
			or targets.is_empty():
		return INF
	var screen := screen_value as Array
	var point := Vector2(float(screen[0]), float(screen[1]))
	var best := INF
	for target in targets:
		best = minf(best, point.distance_to(target))
	return best


func _policy_state_snapshot() -> Dictionary:
	return {
		"phase": _policy_phase,
		"idle_decision_count": _idle_decision_count,
		"shelter_completion_observed": _shelter_completion_observed,
		"crossing_failure_evidence": _crossing_failure_evidence.duplicate(true),
	}


func _learning_candidate_for_append(choice: Dictionary, before: Dictionary,
		after: Dictionary, observation_samples: Array,
		receipt: Dictionary, demonstrated: bool) -> Dictionary:
	var candidate_v: Variant = choice.get("learning_candidate", {})
	if not (candidate_v is Dictionary) or (candidate_v as Dictionary).is_empty():
		return {}
	# Keep failed/interrupted human decisions in the trace, but harvest only the
	# candidate whose expected visible result was actually demonstrated. Crucially,
	# return before reserving its node id so a later successful retry in this same
	# run can provide the one admissible candidate.
	if not demonstrated:
		return {}
	var verb := str(choice.get("verb", ""))
	# An already-complete portrait selection is a visible precondition, not an
	# executed tree branch. Never harvest a no-input/no-delta pseudo-decision.
	if verb in ["select_party", "select_single"] \
			and not bool(receipt.get("input_issued", false)):
		return {}
	# A bounded wait is learnable only when the persisted public frames actually
	# contain presentation progress. Scheduler time alone is not information.
	if verb == "wait" and not _observation_sequence_has_visible_delta(
			before, observation_samples, after):
		return {}
	var candidate := (candidate_v as Dictionary).duplicate(true)
	var node_id := str(candidate.get("node_id", ""))
	# A trace records every human-equivalent decision, but promotion provenance is
	# one observation per proposed node per independent run. Repeated fumbles or
	# retries must not weight one run as multiple supporting playthroughs.
	if node_id != "":
		if _learning_candidate_nodes_recorded.has(node_id):
			return {}
		_learning_candidate_nodes_recorded[node_id] = true
	return candidate


func _observation_sequence_has_visible_delta(before: Dictionary,
		observation_samples: Array, after: Dictionary) -> bool:
	var baseline := _visible_wait_progress_signature(before)
	for observation_v in observation_samples:
		if observation_v is Dictionary and _visible_wait_progress_signature(
				observation_v as Dictionary) != baseline:
			return true
	return _visible_wait_progress_signature(after) != baseline


## Post-hoc release validation for scheduler/background mutations. These EventLog
## records never enter persona policy; they only tell the gate whether an interval
## that looked like a passive wait actually contained authoritative work. The trace
## keeps this lineage separate from production_event_count, which remains zero for
## a human's no-input wait.
func _validate_background_event_presentation(before: Dictionary,
		observation_samples: Array, after: Dictionary,
		background_events: Array) -> Dictionary:
	var event_kinds: Array[String] = []
	for event_v in background_events:
		if event_v is Dictionary:
			event_kinds.append(str((event_v as Dictionary).get("kind", "")))
	var observations: Array = [before]
	observations.append_array(observation_samples)
	observations.append(after)
	var result := {
		"ok": true,
		"event_count": background_events.size(),
		"event_kinds": event_kinds,
		"causal_cue_delta_visible": true,
		"player_facing_traversal_count": 0,
		"subject_lineages": [],
		"failures": [],
	}
	if background_events.is_empty():
		return result
	var baseline_cues := _visible_causal_cue_signatures(before)
	var cue_delta_visible := false
	for observation_v in observations.slice(1):
		if observation_v is Dictionary:
			for signature_v in _visible_causal_cue_signatures(
					observation_v as Dictionary):
				if not baseline_cues.has(signature_v):
					cue_delta_visible = true
					break
		if cue_delta_visible:
			break
	result["causal_cue_delta_visible"] = cue_delta_visible
	if not cue_delta_visible:
		(result["failures"] as Array).append(
			"background_state_change_has_no_new_rendered_causal_cue")

	for event_v in background_events:
		if not (event_v is Dictionary) or str((event_v as Dictionary).get(
				"kind", "")) != "begin_external_traversal":
			continue
		var payload_v: Variant = (event_v as Dictionary).get("payload", {})
		if not (payload_v is Dictionary):
			continue
		var payload := payload_v as Dictionary
		var presentation_v: Variant = payload.get("presentation_receipt", {})
		if not (presentation_v is Dictionary) or str((presentation_v as Dictionary).get(
				"scope", "")) != "player_facing":
			continue
		result["player_facing_traversal_count"] = int(
			result["player_facing_traversal_count"]) + 1
		var presentation := presentation_v as Dictionary
		var subject_id := str(payload.get("id", "")).strip_edges().to_lower()
		var subject_tokens := _validation_subject_tokens(observations, subject_id)
		if subject_tokens.is_empty():
			(result["failures"] as Array).append(
				"background_traversal_subject_token_missing")
		var active_visible := false
		var arrival_visible := false
		for observation_v in observations:
			if not (observation_v is Dictionary):
				continue
			for cue_v in (((observation_v as Dictionary).get(
					"state", {}) as Dictionary).get("cues", []) as Array):
				if not (cue_v is Dictionary):
					continue
				var cue := cue_v as Dictionary
				if str(cue.get("kind", "")) != "consequence" \
						or not bool(cue.get("visible", false)):
					continue
				if subject_tokens.is_empty() or not subject_tokens.has(
						str(cue.get("source_token", ""))):
					continue
				var expected_label := str(presentation.get("label", "")).to_upper()
				var shown_text := "%s %s" % [
					str(cue.get("text", "")), str(cue.get("label", "")),
				]
				if expected_label != "" and not shown_text.to_upper().contains(
						expected_label):
					continue
				var phase := str(cue.get("phase", "")).to_lower()
				active_visible = active_visible or phase == "active"
				arrival_visible = arrival_visible or phase == "arrival"
		var lineage := {
			"source_tokens": subject_tokens.duplicate(),
			"label": str(presentation.get("label", "")),
			"destination_label": str(presentation.get("destination_label", "")),
			"active_visible": active_visible,
			"arrival_visible": arrival_visible,
		}
		(result["subject_lineages"] as Array).append(lineage)
		if not active_visible:
			(result["failures"] as Array).append(
				"background_traversal_active_cue_missing")
		if not arrival_visible:
			(result["failures"] as Array).append(
				"background_traversal_arrival_cue_missing")
	result["ok"] = (result["failures"] as Array).is_empty()
	return result


func _visible_causal_cue_signatures(observation: Dictionary) -> Array[String]:
	var signatures: Array[String] = []
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return signatures
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary) or not bool((cue_v as Dictionary).get(
				"visible", false)):
			continue
		var cue := cue_v as Dictionary
		var kind := str(cue.get("kind", ""))
		if kind in ["party_body", "rally"]:
			continue
		var signature := DecisionTraceScript.canonical_json({
			"kind": kind,
			"source_token": str(cue.get("source_token", "")),
			"phase": str(cue.get("phase", "")),
			"text": str(cue.get("text", "")),
			"label": str(cue.get("label", "")),
			"destination_label": str(cue.get("destination_label", "")),
		})
		if not signatures.has(signature):
			signatures.append(signature)
	signatures.sort()
	return signatures


func _validation_subject_tokens(observations: Array,
		subject_id: String) -> Array[String]:
	var result: Array[String] = []
	var portrait_tokens: Array[String] = []
	for observation_v in observations:
		if not (observation_v is Dictionary):
			continue
		var state := (observation_v as Dictionary).get("state", {}) as Dictionary
		var hud := state.get("hud", {}) as Dictionary
		for portrait_v in hud.get("portraits", []):
			if not (portrait_v is Dictionary) or not bool((portrait_v as Dictionary).get(
					"visible", false)):
				continue
			var portrait := portrait_v as Dictionary
			var shown_words := str(portrait.get("label", "")).strip_edges() \
				.to_lower().split(" ", false)
			var shown_subject := str(shown_words[0]) \
				if not shown_words.is_empty() else ""
			var portrait_token := str(portrait.get("token", ""))
			if shown_subject == subject_id and portrait_token != "" \
					and not portrait_tokens.has(portrait_token):
				portrait_tokens.append(portrait_token)
		for cue_v in state.get("cues", []):
			if not (cue_v is Dictionary):
				continue
			var cue := cue_v as Dictionary
			if str(cue.get("kind", "")) == "party_body" \
					and portrait_tokens.has(str(cue.get("binding", ""))):
				var body_token := str(cue.get("source_token", ""))
				if body_token != "" and not result.has(body_token):
					result.append(body_token)
	for portrait_token in portrait_tokens:
		if not result.has(portrait_token):
			result.append(portrait_token)
	# A rendered nonparty subject has no party portrait/body binding. The
	# observation adapter may expose only the already-minted session-opaque token
	# to this post-hoc validator; it never allocates here and the raw ID never
	# enters policy input or the persisted validation receipt.
	if result.is_empty() and _observer != null and is_instance_valid(_observer) \
			and _observer.has_method("validation_consequence_subject_token"):
		var consequence_token := str(_observer.call(
			"validation_consequence_subject_token", subject_id))
		if consequence_token != "":
			result.append(consequence_token)
	result.sort()
	return result


func _writer_choice_demonstrated(choice: Dictionary, outcome: Dictionary,
		feedback: Dictionary, after: Dictionary,
		observation_samples: Array) -> bool:
	var accepted := bool(outcome.get("accepted", false))
	var verb := str(choice.get("verb", ""))
	if not accepted:
		return _persona == "dean_takahashi" and verb == "rally" \
			and str(outcome.get("status", "")) == "refused" \
			and bool(feedback.get("player_observable", false))
	if verb != "interact" or _persona != "eazy_speezy":
		return true
	var target_token := str(choice.get("target_token", ""))
	var result := outcome.get("interaction_result", {}) as Dictionary
	if target_token == "" or str(result.get("source_token", "")) != target_token \
			or str(result.get("result", "")) != "success" \
			or int(result.get("presentation_serial", 0)) <= 0:
		return false
	var visible_verb := str(choice.get("visible_verb", "")).to_upper()
	if visible_verb.contains("ARM NEXT MID"):
		return _observation_sequence_text_contains(
			observation_samples, after, "CROSSING STAGING") \
			or _observation_sequence_text_contains(
				observation_samples, after, "CROSSING ARMED")
	if visible_verb.contains("SHELTER") or visible_verb.contains("REST"):
		return _observation_sequence_text_contains(
			observation_samples, after, "SECURED THE SHELTER") \
			or _observation_sequence_text_contains(
				observation_samples, after, "FULL PARTY SETTLED")
	return true


func _update_policy_memory(choice: Dictionary, accepted: bool, after: Dictionary) -> void:
	_record_party_sweep_phases(after)
	if _persona == "eazy_speezy" \
			and _policy_phase in EAZY_CROSSING_RECOVERY_PHASES \
			and not _crossing_failure_evidence.is_empty():
		if _policy_phase == "recover_crossing_route" \
				and str(choice.get("verb", "")) == "rally":
			if accepted:
				_policy_phase = "select_party"
				_crossing_failure_evidence.clear()
			else:
				# One exact marked-ladder attempt is a complete human decision. Its
				# rendered refusal is a blocker, not permission to spray alternate
				# floor samples until one happens to mutate state.
				_policy_phase = "recovery_blocked"
			return
		# The visible portrait-bound carry/lowering is stronger evidence than the
		# phase transition the just-finished action would normally cause. Preserve
		# the phase until the next decision can choose a visible ladder recovery.
		return
	if _persona == "eazy_speezy" and _policy_phase == "seek_console" \
			and (_observation_text_contains(after, "ASSIST WAITING") \
			or _observation_has_party_sweep(after)):
		# Follow the console's rendered refusal literally: regroup on a marked ladder
		# route, then select the full party and try the console once more.
		_policy_phase = "seek_deck"
		return
	if _persona == "eazy_speezy" and _policy_phase == "seek_shelter" \
			and _observation_text_contains(after, "SHELTER WAITING"):
		# A visible refusal is a direction to wait, not permission to hammer the same
		# control. Preserve it as evidence, then retry only after the receipt clears.
		_policy_phase = "await_shelter_retry"
		return
	if _persona == "eazy_speezy" and _policy_phase == "rally_shelter" \
			and str(choice.get("verb", "")) == "rally":
		# One exact visible shelter Rally is one complete human decision. Advance
		# only from its demonstrated rendered terminal lineage; a refusal or missing
		# lineage blocks the branch instead of authorizing repeated right-holds.
		_policy_phase = "select_party_for_shelter" \
			if accepted else "shelter_rally_blocked"
		return
	if not accepted:
		return
	var verb := str(choice.get("verb", ""))
	if _persona == "dean_takahashi" and verb == "rally" \
			and str(choice.get("visible_consequence", "")).to_upper().contains(
				"RISING BASIN SWEEP"):
		# This memory is derived only from the annotation Dean chose and the
		# exact visible whole-party Rally result. It does not inspect the Basin
		# timer or mechanism state, and prevents an unrelated console fumble
		# from interrupting the consequence he just invited.
		_policy_phase = "await_missed_rise"
	if verb == "interact":
		_used_interactions[str(choice.get("target_token", ""))] = true
	if _persona != "eazy_speezy":
		return
	match _policy_phase:
		"clear_view":
			if verb == "toggle_instructions":
				_policy_phase = "orient_start"
		"orient_start":
			if verb == "recenter":
				_policy_phase = "frame_level"
		"seek_deck":
			if verb == "rally":
				_policy_phase = "select_party"
				_crossing_failure_evidence.clear()
		"select_party":
			if verb == "select_party":
				_policy_phase = "seek_console"
		"settle_after_crossing":
			if verb == "wait":
				_policy_phase = "rally_shelter"
		"select_party_for_shelter":
			if verb == "select_party":
				_policy_phase = "seek_shelter"
		"seek_console":
			if verb == "interact" and str(choice.get(
					"visible_verb", "")).to_upper().contains("ARM NEXT MID"):
				_policy_phase = "await_crossing"
		"seek_shelter":
			if verb == "interact" and (str(choice.get(
					"visible_verb", "")).to_upper().contains("SHELTER") \
					or str(choice.get("visible_verb", "")).to_upper().contains("REST")):
				_shelter_completion_observed = true
				_policy_phase = "complete"
		"await_shelter_retry":
			if verb == "wait":
				_policy_phase = "seek_shelter"


func _choice_demonstrated(choice: Dictionary, input_accepted: bool,
		after: Dictionary, observation_samples: Array = [],
		before: Dictionary = {}, receipt: Dictionary = {}) -> bool:
	if not input_accepted:
		# Dean's policy may learn a genuinely refused fumble, but never an accepted
		# route that was later interrupted by a sweep or carry. Prove the former from
		# the same exact-target, exact-roster visible lineage used by normal Rally
		# settlement plus the atomic zero-event input receipt.
		if _persona != "dean_takahashi" \
				or str(choice.get("verb", "")) != "rally" \
				or before.is_empty() \
				or not bool(receipt.get("input_issued", false)) \
				or bool(receipt.get("accepted", true)) \
				or not bool(receipt.get("atomic_group", false)) \
				or int(receipt.get("production_event_count", 0)) != 0:
			return false
		var observations := observation_samples.duplicate(true)
		observations.append(after.duplicate(true))
		var movement_result := _new_exact_rally_terminal_result(
			before, choice, observations)
		return not movement_result.is_empty() \
			and not bool(movement_result.get("accepted", true)) \
			and str(movement_result.get("phase", "")) == "refused"
	if _persona != "eazy_speezy" or str(choice.get("verb", "")) != "interact":
		return true
	var visible_verb := str(choice.get("visible_verb", "")).to_upper()
	if visible_verb.contains("ARM NEXT MID"):
		return _observation_sequence_text_contains(
			observation_samples, after, "CROSSING STAGING") \
			or _observation_sequence_text_contains(
				observation_samples, after, "CROSSING ARMED")
	if visible_verb.contains("SHELTER") or visible_verb.contains("REST"):
		return _observation_sequence_text_contains(
			observation_samples, after, "SECURED THE SHELTER") \
			or _observation_sequence_text_contains(
				observation_samples, after, "FULL PARTY SETTLED")
	return true


func _observation_sequence_text_contains(observation_samples: Array,
		after: Dictionary, needle: String) -> bool:
	for observation_v in observation_samples:
		if observation_v is Dictionary \
				and _observation_text_contains(observation_v as Dictionary, needle):
			return true
	return _observation_text_contains(after, needle)


func _observation_text_contains(observation: Dictionary, needle: String) -> bool:
	var expected := needle.to_upper()
	for cue_v in ((observation.get("state", {}) as Dictionary).get("cues", []) as Array):
		if cue_v is Dictionary and str((cue_v as Dictionary).get(
				"text", "")).to_upper().contains(expected):
			return true
	return false


func _party_visibly_near_label(observation: Dictionary, label_text: String) -> bool:
	var targets := _visible_landmark_screens(observation, label_text)
	if targets.is_empty():
		return false
	var expected_portraits := _visible_party_portrait_tokens(observation)
	if expected_portraits.is_empty():
		return false
	var nearby_portraits := {}
	for cue_v in ((observation.get("state", {}) as Dictionary).get("cues", []) as Array):
		if not (cue_v is Dictionary) \
				or str((cue_v as Dictionary).get("kind", "")) != "party_body" \
				or not bool((cue_v as Dictionary).get("visible", false)):
			continue
		var portrait_token := str((cue_v as Dictionary).get("binding", ""))
		if expected_portraits.has(portrait_token) \
				and _screen_distance_to_any(
					(cue_v as Dictionary).get("screen", []), targets) \
						<= SHELTER_BODY_NEAR_RADIUS_PIXELS:
			nearby_portraits[portrait_token] = true
	return nearby_portraits.size() == expected_portraits.size()


func _next_party_near_label_sample_count(observation: Dictionary,
		label_text: String, previous_count: int) -> int:
	return previous_count + 1 \
		if _party_visibly_near_label(observation, label_text) else 0


func _observation_has_sweep(observation: Dictionary) -> bool:
	for cue_v in ((observation.get("state", {}) as Dictionary).get("cues", []) as Array):
		if cue_v is Dictionary \
				and str((cue_v as Dictionary).get("text", "")).to_upper().contains("SWEPT"):
			return true
	return false


func _observation_has_announced_sweep(observation: Dictionary) -> bool:
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return false
	for cue_v in (state_v as Dictionary).get("cues", []):
		if not (cue_v is Dictionary) \
				or not bool((cue_v as Dictionary).get("visible", false)):
			continue
		var cue := cue_v as Dictionary
		var text := "%s %s" % [
			str(cue.get("text", "")), str(cue.get("label", "")),
		]
		if text.to_upper().contains("BASIN RISING"):
			return true
		if str(cue.get("kind", "")) == "consequence" \
				and str(cue.get("phase", "")).to_lower() in ["active", "arrival"] \
				and text.to_upper().contains("SWEPT"):
			return true
	return false


func _observation_has_party_sweep(observation: Dictionary) -> bool:
	var state := observation.get("state", {}) as Dictionary
	var party_tokens := {}
	var hud := state.get("hud", {}) as Dictionary
	for portrait_v in hud.get("portraits", []):
		if portrait_v is Dictionary:
			party_tokens[str((portrait_v as Dictionary).get("token", ""))] = true
	for cue_v in state.get("cues", []):
		if cue_v is Dictionary and str((cue_v as Dictionary).get(
				"kind", "")) == "party_body":
			party_tokens[str((cue_v as Dictionary).get("source_token", ""))] = true
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) == "consequence" \
				and str(cue.get("text", "")).to_upper().contains("SWEPT") \
				and party_tokens.has(str(cue.get("source_token", ""))):
			return true
	return false


func _record_eazy_crossing_failure(observation: Dictionary) -> void:
	if _persona != "eazy_speezy" \
			or _policy_phase not in EAZY_CROSSING_RECOVERY_PHASES:
		return
	var state_v: Variant = observation.get("state", {})
	if not (state_v is Dictionary):
		return
	var state := state_v as Dictionary
	var portrait_labels := {}
	var hud_v: Variant = state.get("hud", {})
	if hud_v is Dictionary:
		for portrait_v in (hud_v as Dictionary).get("portraits", []):
			if not (portrait_v is Dictionary):
				continue
			var portrait := portrait_v as Dictionary
			var token := str(portrait.get("token", ""))
			if bool(portrait.get("visible", false)) and token != "":
				portrait_labels[token] = str(portrait.get("label", "")).strip_edges()
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		var source_token := str(cue.get("source_token", ""))
		if str(cue.get("kind", "")) != "consequence" \
				or not bool(cue.get("visible", false)) \
				or not portrait_labels.has(source_token) \
				or str(cue.get("phase", "")).to_lower() \
					not in ["active", "arrival"]:
			continue
		var label := str(cue.get("label", cue.get("text", ""))).strip_edges()
		var destination := str(cue.get("destination_label", "")).strip_edges()
		var label_upper := label.to_upper()
		var destination_upper := destination.to_upper()
		var swept_to_start := label_upper.contains("SWEPT") \
			and (destination_upper.contains("START") \
				or destination_upper.contains("CURRENT RETURN"))
		var lowered_to_bowl := label_upper.contains("LOWERED BY DRAINING BASIN") \
			and destination_upper.contains("BOWL FLOOR")
		if not swept_to_start and not lowered_to_bowl:
			continue
		var phase := str(cue.get("phase", "")).to_lower()
		var presented_evidence := {
			"source_token": source_token,
			"portrait_label": str(portrait_labels[source_token]),
			"label": label,
			"destination_label": destination,
			"phase": phase,
			"phases": {phase: true},
		}
		if _crossing_failure_evidence.is_empty():
			# Arrival is a consequence terminal, not proof that this persona saw
			# the movement begin. Seed recovery only from an active portrait-bound
			# cue; a sampled arrival on its own cannot authorize another Rally.
			if phase != "active":
				continue
			_crossing_failure_evidence = presented_evidence
			continue
		# Once a public active lineage has been named, only its exact visible
		# arrival may advance recovery. Another portrait, label, or destination
		# remains a separate event and cannot authorize movement for this one.
		if _crossing_failure_lineage_signature(presented_evidence) \
				!= _crossing_failure_lineage_signature(
					_crossing_failure_evidence):
			continue
		var phases := _crossing_failure_evidence.get(
			"phases", {}) as Dictionary
		phases[phase] = true
		_crossing_failure_evidence["phases"] = phases
		_crossing_failure_evidence["phase"] = phase


func _crossing_failure_lineage_signature(evidence: Dictionary) -> String:
	return DecisionTraceScript.canonical_json({
		"source_token": str(evidence.get("source_token", "")),
		"portrait_label": str(evidence.get("portrait_label", "")),
		"label": str(evidence.get("label", "")),
		"destination_label": str(evidence.get("destination_label", "")),
	})


func _crossing_failure_has_arrival() -> bool:
	return bool((_crossing_failure_evidence.get(
		"phases", {}) as Dictionary).get("arrival", false))


func _record_party_sweep_phases(observation: Dictionary) -> void:
	_record_eazy_crossing_failure(observation)
	var state := observation.get("state", {}) as Dictionary
	var party_tokens := {}
	var hud := state.get("hud", {}) as Dictionary
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		var portrait_token := str(portrait.get("token", ""))
		if bool(portrait.get("visible", false)) and portrait_token != "":
			party_tokens[portrait_token] = true
			if not bool(portrait.get("downed", false)) \
					and not _dean_roster_tokens.has(portrait_token):
				_dean_roster_tokens.append(portrait_token)
	_dean_roster_tokens.sort()
	for cue_v in state.get("cues", []):
		if cue_v is Dictionary and str((cue_v as Dictionary).get(
				"kind", "")) == "party_body":
			party_tokens[str((cue_v as Dictionary).get("source_token", ""))] = true
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if bool(cue.get("visible", false)):
			var warning_text := "%s %s %s" % [
				str(cue.get("text", "")), str(cue.get("label", "")),
				str(cue.get("destination_label", "")),
			]
			var warning_upper := warning_text.to_upper()
			if warning_upper.contains("BASIN RISING") \
					or warning_upper.contains("CURRENT RETURNS TO START"):
				_sweep_warning_observed = true
		var source_token := str(cue.get("source_token", ""))
		var phase := str(cue.get("phase", "")).to_lower()
		var label := str(cue.get("label", cue.get("text", ""))).strip_edges()
		var destination_label := str(cue.get("destination_label", "")).strip_edges()
		if str(cue.get("kind", "")) != "consequence" \
				or not bool(cue.get("visible", false)) \
				or not party_tokens.has(source_token) \
				or not label.to_upper().contains("SWEPT") \
				or phase not in ["active", "arrival"] \
				or not (destination_label.to_upper().contains("START") \
					or destination_label.to_upper().contains("CURRENT RETURN") \
					or str(cue.get("text", "")).to_upper().contains(
						"CURRENT RETURN")):
			continue
		# The source token is stable for the visible portrait/body within this run;
		# label + destination keep unrelated consequences from satisfying the same
		# proof without exposing a private event ID.
		var lineage_key := "%s|%s|%s" % [
			source_token, label.to_upper(), destination_label.to_upper(),
		]
		var evidence: Dictionary = _sweep_phase_evidence.get(lineage_key, {
			"source_token": source_token,
			"label": label,
			"destination_label": destination_label,
			"phases": {},
		})
		var phases := evidence.get("phases", {}) as Dictionary
		phases[phase] = true
		evidence["phases"] = phases
		_sweep_phase_evidence[lineage_key] = evidence


func _dean_sweep_goal_reached() -> bool:
	if not _sweep_warning_observed or _dean_roster_tokens.is_empty():
		return false
	for roster_token in _dean_roster_tokens:
		var subject_complete := false
		for evidence_v in _sweep_phase_evidence.values():
			if not (evidence_v is Dictionary) \
					or str((evidence_v as Dictionary).get(
						"source_token", "")) != roster_token:
				continue
			var phases := (evidence_v as Dictionary).get(
				"phases", {}) as Dictionary
			if bool(phases.get("active", false)) \
					and bool(phases.get("arrival", false)):
				subject_complete = true
				break
		if not subject_complete:
			return false
	return true


func _observation_has_party_body(observation: Dictionary) -> bool:
	for cue_v in ((observation.get("state", {}) as Dictionary).get("cues", []) as Array):
		if cue_v is Dictionary \
				and str((cue_v as Dictionary).get("kind", "")) == "party_body":
			return true
	return false


func _observation_has_ladder_route(observation: Dictionary) -> bool:
	for affordance_v in ((observation.get("state", {}) as Dictionary).get(
			"affordances", []) as Array):
		if affordance_v is Dictionary and str((affordance_v as Dictionary).get(
				"consequence", "")).to_upper().contains("LADDER"):
			return true
	return false


func _observation_has_deck_landmark(observation: Dictionary) -> bool:
	# Different camera framings expose the same authored landmark through either
	# its world label or the pointer affordance attached to that visible surface.
	# Both are presentation-only player_observation_v1 evidence.
	if _observation_text_contains(observation, "DECK ACCESS"):
		return true
	for affordance_v in ((observation.get("state", {}) as Dictionary).get(
			"affordances", []) as Array):
		if not (affordance_v is Dictionary):
			continue
		var affordance := affordance_v as Dictionary
		var verb := str(affordance.get("verb", "")).to_upper()
		var consequence := str(affordance.get("consequence", "")).to_upper()
		if verb.contains("UPPER DECK") or verb.contains("ARM NEXT MID") \
				or consequence.contains("UPPER DECK"):
			return true
	return false


func _policy_should_stop(observation: Dictionary) -> bool:
	if _persona == "eazy_speezy":
		if _policy_phase == "shelter_rally_blocked" \
				and _crossing_failure_evidence.is_empty():
			# The one visible shelter Rally did not produce a demonstrable terminal
			# result. Stop issuing input; only a separately visible portrait-bound
			# crossing failure may reopen the exact recovery branch.
			return true
		# A late, visible party-member carry can arrive on the frame after REST.
		# Do not seal a false completion before the observation-first recovery path
		# has a chance to act.
		return _policy_phase == "complete" \
			and _shelter_completion_observed \
			and _crossing_failure_evidence.is_empty()
	if _persona == "dean_takahashi":
		_record_party_sweep_phases(observation)
		return _dean_sweep_goal_reached()
	return false


func _hide_instructions_candidate(observation: Dictionary) -> Dictionary:
	var state := observation.get("state", {}) as Dictionary
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		if str(cue.get("kind", "")) != "instruction" \
				or not bool(cue.get("visible", false)) \
				or str(cue.get("text", "")).strip_edges() == "":
			continue
		return {
			"node_id": "hide_instructions_when_they_occlude_the_board",
			"rule": "Hide a visible instruction panel when it occludes the board needed for the next route decision.",
			"scope": "global",
			"priority": 90,
			"condition": {
				"path": "cues", "op": "contains", "value": cue.duplicate(true),
			},
			"action": {
				"verb": "toggle_instructions",
				"target_ref": "advertised_visible_hide_control",
			},
			"expected": {"path": "visible_change", "op": "eq", "value": true},
		}
	return {}


func _select_visible_roster_candidate(observation: Dictionary) -> Dictionary:
	var state := observation.get("state", {}) as Dictionary
	var hud := state.get("hud", {}) as Dictionary
	var visible_portraits: Array = []
	var has_unselected := false
	for portrait_v in hud.get("portraits", []):
		if not (portrait_v is Dictionary) \
				or not bool((portrait_v as Dictionary).get("visible", false)):
			continue
		var portrait := (portrait_v as Dictionary).duplicate(true)
		visible_portraits.append(portrait)
		has_unselected = has_unselected or not bool(portrait.get("selected", false))
	if visible_portraits.is_empty() or not has_unselected:
		return {}
	var conditions: Array = []
	for portrait_v in visible_portraits:
		conditions.append({
			"path": "hud.portraits", "op": "contains",
			"value": (portrait_v as Dictionary).duplicate(true),
		})
	return {
		"node_id": "eazy_speezy_select_full_visible_roster",
		"rule": "Select every currently visible party portrait before an advertised selected-party interaction.",
		"scope": "global",
		"priority": 80,
		"condition": {"all": conditions},
		"action": {"verb": "select_party", "target_ref": "visible_hud_roster"},
		"expected": {"path": "visible_change", "op": "eq", "value": true},
	}


func _announced_wait_candidate(observation: Dictionary) -> Dictionary:
	var state := observation.get("state", {}) as Dictionary
	for cue_v in state.get("cues", []):
		if not (cue_v is Dictionary):
			continue
		var cue := cue_v as Dictionary
		var text := "%s %s" % [
			str(cue.get("text", "")), str(cue.get("label", "")),
		]
		var upper := text.to_upper()
		if not bool(cue.get("visible", false)) \
				or not (upper.contains("CROSSING STAGING") \
					or upper.contains("CROSSING ARMED") \
					or upper.contains("NEXT MID")):
			continue
		return {
			"node_id": "wait_for_visible_announced_mid_crossing",
			"rule": "Wait on the rendered clock while an announced selected-party consequence is visibly in progress.",
			"scope": "fragment",
			"priority": 75,
			"condition": {
				"path": "cues", "op": "contains", "value": cue.duplicate(true),
			},
			"action": {
				"verb": "wait", "target_ref": "announced_visible_consequence",
			},
			"expected": {"path": "visible_change", "op": "eq", "value": true},
		}
	return {}


func _interaction_candidate(visible_verb: String) -> Dictionary:
	var exact_verb := visible_verb.strip_edges()
	var verb_upper := exact_verb.to_upper()
	var node_suffix := ""
	if verb_upper.contains("ARM NEXT MID"):
		node_suffix = "arm_visible_mid_console"
	elif verb_upper.contains("REST") or verb_upper.contains("SHELTER"):
		node_suffix = "use_visible_exit_shelter"
	else:
		# READ ROTA CHART and future unknown interactions remain useful trace
		# evidence, but they do not inherit an unrelated fallback policy node.
		return {}
	return {
		"node_id": "%s_%s" % [_persona, node_suffix],
		"rule": _interaction_rationale(visible_verb),
		"scope": "fragment",
		"priority": 70,
		"condition": {"path": "visible_affordance_verbs", "op": "contains",
			"value": exact_verb},
		"action": {"verb": "interact", "target_ref": "matching_visible_interaction"},
		"expected": {"path": "accepted", "op": "eq", "value": true},
	}


func _visible_ground_conditions() -> Array:
	var conditions: Array = []
	for bin_name in GROUND_BIN_ORDER:
		conditions.append({
			"path": "viewport_bins.%s.0" % bin_name,
			"op": "exists",
			"value": true,
		})
	return conditions


func _visible_ladder_route_conditions(exact_consequence: String) -> Array:
	var consequence := exact_consequence.strip_edges()
	if consequence == "" or not consequence.to_upper().contains("LADDER"):
		return []
	return [{
		"path": "visible_affordance_consequences",
		"op": "contains",
		"value": consequence,
	}]
