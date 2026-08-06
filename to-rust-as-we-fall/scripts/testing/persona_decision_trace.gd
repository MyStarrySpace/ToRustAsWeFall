class_name PersonaDecisionTrace
extends RefCounted

const ContentFingerprint := preload("res://scripts/testing/content_fingerprint.gd")

## Append-only, hash-chained persona decision evidence.
##
## A decision line is deliberately wider than an action log. It records the
## player-observable state that informed the choice, the persona's rationale,
## the public verb it chose, the shipped-input receipt, the feedback a player
## could see, and the resulting state. The distiller independently recomputes
## evidence eligibility; a trace cannot make itself admissible by setting a
## boolean.

const TRACE_SCHEMA := "persona_decision_trace_v3"
const PLAYER_OBSERVATION_SCHEMA := "player_observation_v1"
const RUN_RECORD := "run"
const DECISION_RECORD := "decision"
const SUMMARY_RECORD := "summary"
const VALIDATION_RECORD := "validation"
const VALIDATION_SCHEMA := "persona_strict_validation_v1"
const INVOCATION_MANIFEST_SCHEMA := "persona_strict_invocation_manifest_v1"
const CURRENT_VALIDATION_CONTRACT_VERSION := 3
const VALIDATION_VALIDATORS := {
	"native": "godot_windowed_persona_probe",
	"web": "playwright_persona_probe",
}
const FLOAT_QUANTUM := 0.000001

const PLAYER_BOUNDARIES := [
	"keyboard_pointer",
	"controller",
	"touch",
	"player_command",
]

const FORBIDDEN_VERBS := [
	"complete",
	"debug",
	"fixture",
	"set_level",
	"set_position",
	"set_stat",
	"snap",
	"teleport",
	"trigger",
]

const OBSERVATION_KEYS := ["schema", "source", "capture_serial", "tick", "state"]
const OBSERVATION_STATE_KEYS := [
	"hud",
	"viewport",
	"affordances",
	"visible_affordance_verbs",
	"visible_affordance_consequences",
	"cues",
	"viewport_bins",
]
const HUD_PRESENTATION_KEYS := [
	"portraits", "portrait", "token", "bars", "hp", "stamina", "atp",
	"hp_percent", "stamina_percent", "atp_percent", "current", "maximum",
	"percent", "status", "statuses", "selection", "selected", "available",
	"downed", "conscious", "visible", "kind", "text", "value", "label",
	"screen", "active", "sta", "alert", "hold_label", "hold_locked",
	"run_label", "routing_label", "message", "hands", "hold", "locked",
]
const AFFORDANCE_PRESENTATION_KEYS := [
	"token", "kind", "verb", "consequence", "screen",
]
const CUE_PRESENTATION_KEYS := [
	"kind", "text", "token", "source_token", "target_token", "subjects",
	"phase", "state", "progress", "accepted", "reason", "visible", "direction",
	"destination", "destination_label", "label", "screen", "duration", "binding",
	"result", "presentation_serial", "route_status", "route_status_serial",
	"route_status_subjects", "route_status_remaining_seconds",
]
const MOVEMENT_ROUTE_STATUS_KEYS := [
	"route_status", "route_status_serial", "route_status_subjects",
	"route_status_remaining_seconds",
]
const MOVEMENT_ROUTE_STATUSES := ["", "reforming_route", "cooperative_hold"]
const VIEWPORT_PRESENTATION_KEYS := ["origin", "size"]
const KNOWN_WORLD_CHANGING_VERBS := ["interact", "move", "push", "rally", "use"]
const KNOWN_PASSIVE_OR_PRESENTATION_VERBS := [
	"camera_pan",
	"camera_recenter",
	"camera_rotate",
	"camera_zoom",
	"focus",
	"hover",
	"pause",
	"recenter",
	"select_party",
	"select_single",
	"toggle_instructions",
	"toggle_run",
	"wait",
	"zoom_out",
]
const FORBIDDEN_OBSERVATION_KEYS := [
	"name", "node", "node_path", "position", "world_position",
	"global_position", "transform", "level", "cell", "grid", "detection",
	"detection_range", "fsm", "private", "internal", "solution", "anchor",
	"complete", "completion", "preflight", "validator", "event_log",
	"action_receipts", "content_fingerprint", "gameplay_build_fingerprint",
	"gameplay_build_fingerprint_schema", "seed",
]

var _file: FileAccess
var _path := ""
var _run: Dictionary = {}
var _previous_hash := ""
var _next_decision_index := 0
var _open := false
var _decisions: Array[Dictionary] = []
var _has_ineligible_decision := false


func begin(path: String, run_metadata: Dictionary) -> Dictionary:
	if _open:
		return _failure("a decision trace is already open")
	var run: Dictionary = json_safe(run_metadata) as Dictionary
	var issues := validate_run_metadata(run)
	if not issues.is_empty():
		return _failure("invalid run metadata: %s" % "; ".join(issues))
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return _failure("cannot open %s for writing (error %d)" % [path, FileAccess.get_open_error()])
	_path = path
	_run = run
	_previous_hash = ""
	_next_decision_index = 0
	_decisions.clear()
	_has_ineligible_decision = false
	_open = true
	var header := {
		"schema": TRACE_SCHEMA,
		"record_type": RUN_RECORD,
		"run": _run,
	}
	var written := _append_hashed(header)
	return {
		"ok": true,
		"path": _path,
		"run_id": str(_run.get("run_id", "")),
		"record_hash": str(written.get("record_hash", "")),
	}


func append_decision(
		observation_before: Dictionary,
		observation_after: Dictionary,
		observation_samples: Array,
		rationale: Dictionary,
		decision: Dictionary,
		input_receipt: Dictionary,
		evidence_context: Dictionary,
		learning_candidate: Dictionary = {},
	) -> Dictionary:
	## Append one decision from raw player-visible presentation only.
	##
	## Callers cannot supply feedback or outcome.  Both are derived here from
	## the before/after observations and the de-duplicated in-action samples,
	## then independently recomputed by read_trace().
	if not _open or _file == null:
		return _failure("begin() must succeed before appending a decision")
	var deduplicated_samples := deduplicate_observations(observation_samples)
	var derived := derive_feedback_outcome(
		observation_before, observation_after, deduplicated_samples,
		decision, input_receipt)
	var record := {
		"schema": TRACE_SCHEMA,
		"record_type": DECISION_RECORD,
		"run": _decision_run_identity(_run),
		"decision_index": _next_decision_index,
		"observation_before": json_safe(observation_before),
		"observation_after": json_safe(observation_after),
		"observation_samples": json_safe(deduplicated_samples),
		"rationale": json_safe(rationale),
		"decision": json_safe(decision),
		"input_receipt": json_safe(input_receipt),
		"feedback": derived.get("feedback", {}).duplicate(true),
		"outcome": derived.get("outcome", {}).duplicate(true),
		"evidence_context": json_safe(evidence_context),
	}
	if not learning_candidate.is_empty():
		record["learning_candidate"] = json_safe(learning_candidate)
	var classification := classify_evidence(record)
	record["evidence"] = classification
	var structural_issues := validate_decision_record(record)
	structural_issues.append_array(decision_progression_reasons(
		_decisions, record))
	structural_issues.sort()
	if not structural_issues.is_empty():
		return _failure("invalid decision record: %s" % "; ".join(structural_issues))
	var written := _append_hashed(record)
	_decisions.append(written.duplicate(true))
	if not bool((written.get("evidence", {}) as Dictionary).get(
			"eligible_for_learning", false)):
		_has_ineligible_decision = true
	_next_decision_index += 1
	return {
		"ok": true,
		"decision_index": int(written.get("decision_index", -1)),
		"record_hash": str(written.get("record_hash", "")),
		"feedback": (written.get("feedback", {}) as Dictionary).duplicate(true),
		"outcome": (written.get("outcome", {}) as Dictionary).duplicate(true),
		"evidence": written.get("evidence", {}).duplicate(true),
	}


func finish(summary: Dictionary = {}) -> Dictionary:
	## Seal the run.  Persona goal state is never caller authority.
	##
	## Basin Eazy and Dean goals are derived from the persisted raw observation
	## history.  A caller may request trace_complete=true, but the writer forces
	## it false when any decision is ineligible or the derived persona goal lacks
	## proof.
	if not _open or _file == null:
		return _failure("no decision trace is open")
	var sealed_summary: Dictionary = json_safe(summary) as Dictionary
	sealed_summary.erase("persona_goal_reached")
	sealed_summary.erase("goal_evidence")
	var goal := derive_persona_goal(_run, _decisions)
	var requested_complete := sealed_summary.get("trace_complete", null) is bool \
		and bool(sealed_summary.get("trace_complete", false))
	sealed_summary["persona_goal_reached"] = bool(goal.get("reached", false))
	sealed_summary["goal_evidence"] = goal.get("evidence", {}).duplicate(true)
	sealed_summary["trace_complete"] = requested_complete \
		and not _has_ineligible_decision \
		and bool(goal.get("reached", false))
	var footer := {
		"schema": TRACE_SCHEMA,
		"record_type": SUMMARY_RECORD,
		"run": _decision_run_identity(_run),
		"decision_count": _next_decision_index,
		"summary": sealed_summary,
	}
	var written := _append_hashed(footer)
	_file.close()
	_file = null
	_open = false
	_decisions.clear()
	_has_ineligible_decision = false
	return {
		"ok": true,
		"path": _path,
		"decision_count": _next_decision_index,
		"record_hash": str(written.get("record_hash", "")),
		"summary": (written.get("summary", {}) as Dictionary).duplicate(true),
	}


func abort() -> void:
	if _file != null:
		_file.close()
	_file = null
	_open = false


func is_open() -> bool:
	return _open


func _append_hashed(unhashed_record: Dictionary) -> Dictionary:
	var record: Dictionary = json_safe(unhashed_record) as Dictionary
	record["previous_hash"] = _previous_hash
	var hash_payload: Dictionary = record.duplicate(true)
	hash_payload.erase("record_hash")
	record["record_hash"] = canonical_hash(hash_payload)
	_file.store_line(canonical_json(record))
	_file.flush()
	_previous_hash = str(record["record_hash"])
	return record


static func read_trace(path: String) -> Dictionary:
	var result := {
		"ok": false,
		"path": path,
		"run": {},
		"summary": {},
		"summary_record_hash": "",
		"validation": {},
		"validation_record_hash": "",
		"validations": [],
		"records": [],
		"decisions": [],
		"errors": [],
	}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		(result["errors"] as Array).append(
			"cannot open trace (error %d)" % FileAccess.get_open_error())
		return result
	var previous_hash := ""
	var expected_decision_index := 0
	var prior_decisions: Array[Dictionary] = []
	var saw_run := false
	var saw_summary := false
	var saw_validation := false
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		line_number += 1
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not (parsed is Dictionary):
			(result["errors"] as Array).append("line %d is not a JSON object" % line_number)
			continue
		var record := parsed as Dictionary
		if str(record.get("schema", "")) != TRACE_SCHEMA:
			(result["errors"] as Array).append("line %d has the wrong schema" % line_number)
		if str(record.get("previous_hash", "")) != previous_hash:
			(result["errors"] as Array).append("line %d breaks the hash chain" % line_number)
		var claimed_hash := str(record.get("record_hash", ""))
		var hash_payload := record.duplicate(true)
		hash_payload.erase("record_hash")
		var actual_hash := canonical_hash(hash_payload)
		if claimed_hash == "" or claimed_hash != actual_hash:
			(result["errors"] as Array).append("line %d has an invalid record hash" % line_number)
		previous_hash = claimed_hash
		var record_type := str(record.get("record_type", ""))
		match record_type:
			RUN_RECORD:
				if saw_run or not (result["records"] as Array).is_empty():
					(result["errors"] as Array).append("line %d has a misplaced run header" % line_number)
				saw_run = true
				result["run"] = (record.get("run", {}) as Dictionary).duplicate(true)
				for issue in validate_run_metadata(result["run"]):
					(result["errors"] as Array).append("line %d: %s" % [line_number, issue])
			DECISION_RECORD:
				if not saw_run or saw_summary or saw_validation:
					(result["errors"] as Array).append("line %d has a decision outside the run" % line_number)
				if not canonical_equal(record.get("run", {}),
						_decision_run_identity(result.get("run", {}) as Dictionary)):
					(result["errors"] as Array).append(
						"line %d decision identity does not match the run header" % line_number)
				if int(record.get("decision_index", -1)) != expected_decision_index:
					(result["errors"] as Array).append(
						"line %d has decision index %d, expected %d" % [
							line_number, int(record.get("decision_index", -1)), expected_decision_index])
				expected_decision_index += 1
				for issue in validate_decision_record(record):
					(result["errors"] as Array).append("line %d: %s" % [line_number, issue])
				for issue in decision_progression_reasons(prior_decisions, record):
					(result["errors"] as Array).append("line %d: %s" % [line_number, issue])
				(result["decisions"] as Array).append(record)
				prior_decisions.append(record)
			SUMMARY_RECORD:
				if not saw_run or saw_summary or saw_validation:
					(result["errors"] as Array).append("line %d has a misplaced summary" % line_number)
				saw_summary = true
				var summary_value: Variant = record.get("summary", null)
				if not (summary_value is Dictionary):
					(result["errors"] as Array).append(
						"line %d summary payload is not an object" % line_number)
				else:
					result["summary"] = (summary_value as Dictionary).duplicate(true)
				result["summary_record_hash"] = claimed_hash
				if not canonical_equal(record.get("run", {}),
						_decision_run_identity(result.get("run", {}) as Dictionary)):
					(result["errors"] as Array).append(
						"line %d summary identity does not match the run header" % line_number)
				if int(record.get("decision_count", -1)) != expected_decision_index:
					(result["errors"] as Array).append(
						"line %d summary count does not match the decision records" % line_number)
			VALIDATION_RECORD:
				if not saw_run or not saw_summary:
					(result["errors"] as Array).append(
						"line %d has validation before the run summary" % line_number)
				saw_validation = true
				if not canonical_equal(record.get("run", {}),
						_decision_run_identity(result.get("run", {}) as Dictionary)):
					(result["errors"] as Array).append(
						"line %d validation identity does not match the run header" % line_number)
				if str(record.get("summary_record_hash", "")) != str(
						result.get("summary_record_hash", "")):
					(result["errors"] as Array).append(
						"line %d validation does not bind the run summary" % line_number)
				var validation_value: Variant = record.get("validation", null)
				if not (validation_value is Dictionary):
					(result["errors"] as Array).append(
						"line %d validation payload is not an object" % line_number)
				else:
					var validation := validation_value as Dictionary
					for issue in validate_validation_receipt_shape(validation,
							result.get("run", {}) as Dictionary, expected_decision_index,
							str(result.get("summary_record_hash", "")),
							result.get("summary", {}) as Dictionary):
						(result["errors"] as Array).append(
							"line %d: %s" % [line_number, issue])
					result["validation"] = validation.duplicate(true)
					result["validation_record_hash"] = claimed_hash
					(result["validations"] as Array).append(validation.duplicate(true))
			_:
				(result["errors"] as Array).append("line %d has unknown record_type '%s'" % [
					line_number, record_type])
		(result["records"] as Array).append(record)
	file.close()
	if not saw_run:
		(result["errors"] as Array).append("trace has no run header")
	if not saw_summary:
		(result["errors"] as Array).append("trace has no summary")
	elif saw_run:
		var summary := result.get("summary", {}) as Dictionary
		var derived_goal := derive_persona_goal(
			result.get("run", {}) as Dictionary, result.get("decisions", []) as Array)
		if not (summary.get("persona_goal_reached", null) is bool) \
				or bool(summary.get("persona_goal_reached", false)) \
					!= bool(derived_goal.get("reached", false)):
			(result["errors"] as Array).append(
				"summary persona goal does not match persisted observation proof")
		if not canonical_equal(summary.get("goal_evidence", {}),
				derived_goal.get("evidence", {})):
			(result["errors"] as Array).append(
				"summary goal evidence does not match persisted observation proof")
		if not (summary.get("trace_complete", null) is bool):
			(result["errors"] as Array).append("summary trace_complete must be explicit")
		elif bool(summary.get("trace_complete", false)):
			if not bool(derived_goal.get("reached", false)):
				(result["errors"] as Array).append(
					"a trace without derived persona goal proof cannot be complete")
			for decision_value in result.get("decisions", []):
				if decision_value is Dictionary and not bool(classify_evidence(
						decision_value as Dictionary).get("eligible_for_learning", false)):
					(result["errors"] as Array).append(
						"a trace with ineligible decisions cannot be complete")
					break
	result["ok"] = (result["errors"] as Array).is_empty()
	return result


static func current_validation_contract_id(run: Dictionary) -> String:
	var platform := str(run.get("execution_platform", "")).to_lower()
	var fragment_id := str(run.get("fragment_id", "")).to_lower()
	var persona := str(run.get("persona", "")).to_lower()
	if platform not in VALIDATION_VALIDATORS or fragment_id == "" or persona == "":
		return ""
	return "%s_%s_%s_v%d" % [
		platform, fragment_id, persona, CURRENT_VALIDATION_CONTRACT_VERSION,
	]


static func current_validation_validator_id(execution_platform: String) -> String:
	return str(VALIDATION_VALIDATORS.get(execution_platform.to_lower(), ""))


static func expected_validation_cohort(run: Dictionary) -> Array:
	## The release-critical Basin contract is exactly two personas by two fresh
	## authored boots on each execution platform.  Keeping this matrix in the
	## validator prevents a filtered or single-persona invocation from declaring
	## its own smaller cohort complete.
	var platform := str(run.get("execution_platform", ""))
	var fragment_id := str(run.get("fragment_id", ""))
	if fragment_id == "basin_fill_proof" and platform in ["native", "web"]:
		var expected: Array = []
		for persona in ["dean_takahashi", "eazy_speezy"]:
			for repeat_index in [0, 1]:
				expected.append({
					"execution_platform": platform,
					"fragment_id": fragment_id,
					"persona": persona,
					"repeat_index": repeat_index,
				})
		return _sorted_cohort_identities(expected)
	return []


static func invocation_member_proof(document: Dictionary) -> Dictionary:
	var run := document.get("run", {}) as Dictionary
	var summary := document.get("summary", {}) as Dictionary
	return json_safe({
		"run_id": str(run.get("run_id", "")),
		"trace_id": str(run.get("trace_id", "")),
		"persona": str(run.get("persona", "")),
		"fragment_id": str(run.get("fragment_id", "")),
		"execution_platform": str(run.get("execution_platform", "")),
		"repeat_index": int(run.get("repeat_index", -1)),
		"content_fingerprint_schema": str(run.get("content_fingerprint_schema", "")),
		"content_fingerprint": str(run.get("content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(run.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(run.get(
			"gameplay_build_fingerprint", "")),
		"summary_record_hash": str(document.get("summary_record_hash", "")),
		"decision_count": (document.get("decisions", []) as Array).size(),
		"trace_complete": bool(summary.get("trace_complete", false)),
		"persona_goal_reached": bool(summary.get("persona_goal_reached", false)),
	}) as Dictionary


static func make_invocation_manifest(documents: Array, invocation_id: String,
		expected_members: Array = []) -> Dictionary:
	var members: Array = []
	var failures: Array[String] = []
	var first_run := {}
	for document_value in documents:
		if not (document_value is Dictionary):
			failures.append("cohort_document_not_an_object")
			continue
		var document := document_value as Dictionary
		if first_run.is_empty():
			first_run = (document.get("run", {}) as Dictionary).duplicate(true)
		if not bool(document.get("ok", false)):
			failures.append("cohort_document_invalid:%s" % str(
				(document.get("run", {}) as Dictionary).get("trace_id", "")))
		members.append(invocation_member_proof(document))
	var expected := _sorted_cohort_identities(expected_members)
	if expected.is_empty() and not first_run.is_empty():
		expected = expected_validation_cohort(first_run)
	if invocation_id.strip_edges() == "":
		failures.append("invocation_id_missing")
	var seen_member_proofs := {}
	var content_identities := {}
	var gameplay_build_identities := {}
	var actual_identities: Array = []
	for member_value in members:
		var member := member_value as Dictionary
		var proof_key := _cohort_member_proof_key(member)
		if seen_member_proofs.has(proof_key):
			failures.append("duplicate_cohort_member:%s" % proof_key)
		seen_member_proofs[proof_key] = true
		actual_identities.append(_cohort_identity(member))
		if str(member.get("summary_record_hash", "")) == "":
			failures.append("cohort_member_summary_hash_missing:%s" % proof_key)
		if int(member.get("decision_count", 0)) < 1:
			failures.append("cohort_member_decisions_missing:%s" % proof_key)
		if not bool(member.get("trace_complete", false)):
			failures.append("cohort_member_trace_incomplete:%s" % proof_key)
		if not bool(member.get("persona_goal_reached", false)):
			failures.append("cohort_member_goal_unproven:%s" % proof_key)
		if not ContentFingerprint.is_supported_schema(str(
				member.get("content_fingerprint_schema", ""))):
			failures.append("cohort_member_fingerprint_schema_invalid:%s" % proof_key)
		if not _valid_sha256_text(str(member.get("content_fingerprint", ""))):
			failures.append("cohort_member_fingerprint_invalid:%s" % proof_key)
		content_identities["%s|%s" % [
			str(member.get("content_fingerprint_schema", "")),
			str(member.get("content_fingerprint", "")),
		]] = true
		if not ContentFingerprint.is_supported_gameplay_build_schema(str(
				member.get("gameplay_build_fingerprint_schema", ""))):
			failures.append(
				"cohort_member_gameplay_build_fingerprint_schema_invalid:%s" % proof_key)
		if not _valid_sha256_text(str(member.get(
				"gameplay_build_fingerprint", ""))):
			failures.append(
				"cohort_member_gameplay_build_fingerprint_invalid:%s" % proof_key)
		gameplay_build_identities["%s|%s" % [
			str(member.get("gameplay_build_fingerprint_schema", "")),
			str(member.get("gameplay_build_fingerprint", "")),
		]] = true
	actual_identities = _sorted_cohort_identities(actual_identities)
	if not canonical_equal(actual_identities, expected):
		failures.append("cohort_does_not_match_expected_persona_repeat_matrix")
	if content_identities.size() != 1:
		failures.append("cohort_content_identity_mismatch")
	if gameplay_build_identities.size() != 1:
		failures.append("cohort_gameplay_build_identity_mismatch")
	var sorted_members := members.duplicate(true)
	sorted_members.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _cohort_member_proof_key(a as Dictionary) \
			< _cohort_member_proof_key(b as Dictionary))
	failures.sort()
	return json_safe({
		"schema": INVOCATION_MANIFEST_SCHEMA,
		"invocation_id": invocation_id,
		"execution_platform": str(first_run.get("execution_platform", "")),
		"fragment_id": str(first_run.get("fragment_id", "")),
		"expected_members": expected,
		"members": sorted_members,
		"cohort_size": sorted_members.size(),
		"passed": failures.is_empty(),
		"failure_count": failures.size(),
		"failures": failures,
	}) as Dictionary


static func _cohort_identity(value: Dictionary) -> Dictionary:
	return {
		"execution_platform": str(value.get("execution_platform", "")),
		"fragment_id": str(value.get("fragment_id", "")),
		"persona": str(value.get("persona", "")),
		"repeat_index": int(value.get("repeat_index", -1)),
	}


static func _cohort_identity_key(value: Dictionary) -> String:
	return canonical_json(_cohort_identity(value))


static func _cohort_member_proof_key(value: Dictionary) -> String:
	return "%s|%s|%s" % [
		_cohort_identity_key(value),
		str(value.get("run_id", "")),
		str(value.get("trace_id", "")),
	]


static func _sorted_cohort_identities(values: Array) -> Array:
	var result: Array = []
	var seen := {}
	for value in values:
		if not (value is Dictionary):
			continue
		var identity := _cohort_identity(value as Dictionary)
		var key := _cohort_identity_key(identity)
		if seen.has(key):
			# Preserve duplicate expected identities so validation can diagnose a
			# malformed matrix rather than silently normalizing it away.
			result.append(identity)
		else:
			seen[key] = true
			result.append(identity)
	result.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _cohort_identity_key(a as Dictionary) \
			< _cohort_identity_key(b as Dictionary))
	return result


static func make_validation_receipt(document: Dictionary, invocation_id: String,
		passed: bool, check_count: int, failure_count: int,
		invocation_manifest: Dictionary = {}) -> Dictionary:
	var run := document.get("run", {}) as Dictionary
	var member_proof := invocation_member_proof(document)
	return {
		"schema": VALIDATION_SCHEMA,
		"contract_id": current_validation_contract_id(run),
		"contract_version": CURRENT_VALIDATION_CONTRACT_VERSION,
		"validator_id": current_validation_validator_id(str(
			run.get("execution_platform", ""))),
		"execution_platform": str(run.get("execution_platform", "")),
		"invocation_id": invocation_id,
		"passed": passed,
		"check_count": maxi(0, check_count),
		"failure_count": maxi(0, failure_count),
		"checked_decision_count": (document.get("decisions", []) as Array).size(),
		"invocation_manifest": json_safe(invocation_manifest),
		"invocation_manifest_hash": canonical_hash(invocation_manifest),
		"cohort_size": int(invocation_manifest.get("cohort_size", 0)),
		"cohort_member": member_proof,
	}


static func validate_validation_receipt_shape(validation: Dictionary, run: Dictionary,
		decision_count: int, summary_record_hash := "",
		summary: Dictionary = {}) -> Array[String]:
	var issues: Array[String] = []
	for key in ["schema", "contract_id", "validator_id", "execution_platform",
			"invocation_id", "invocation_manifest_hash"]:
		if str(validation.get(key, "")).strip_edges() == "":
			issues.append("validation.%s is required" % key)
	var contract_version_value: Variant = validation.get("contract_version", null)
	if not (contract_version_value is int or contract_version_value is float) \
			or not is_finite(float(contract_version_value)) \
			or float(contract_version_value) != float(int(contract_version_value)):
		issues.append("validation.contract_version must be an integer")
	if not (validation.get("passed", null) is bool):
		issues.append("validation.passed must be explicit")
	for key in ["check_count", "failure_count", "checked_decision_count", "cohort_size"]:
		var count_value: Variant = validation.get(key, null)
		if not (count_value is int or count_value is float) \
				or not is_finite(float(count_value)) \
				or float(count_value) != float(int(count_value)) \
				or int(count_value) < 0:
			issues.append("validation.%s must be a non-negative integer" % key)
	if validation.get("passed", null) is bool:
		if bool(validation.get("passed", false)):
			if int(validation.get("failure_count", -1)) != 0:
				issues.append("passed validation must have zero failures")
			if int(validation.get("check_count", 0)) < 1:
				issues.append("passed validation must report at least one check")
		elif int(validation.get("failure_count", 0)) < 1:
			issues.append("failed validation must report at least one failure")
	if str(validation.get("execution_platform", "")) != str(
			run.get("execution_platform", "")):
		issues.append("validation.execution_platform does not match the run")
	if int(validation.get("checked_decision_count", -1)) != decision_count:
		issues.append("validation.checked_decision_count does not match the decisions")
	var manifest_value: Variant = validation.get("invocation_manifest", null)
	if not (manifest_value is Dictionary) or (manifest_value as Dictionary).is_empty():
		issues.append("validation.invocation_manifest is required")
	else:
		var manifest := manifest_value as Dictionary
		if str(manifest.get("schema", "")) != INVOCATION_MANIFEST_SCHEMA:
			issues.append("validation invocation manifest schema is not current")
		if str(manifest.get("invocation_id", "")) != str(
				validation.get("invocation_id", "")):
			issues.append("validation invocation manifest ID does not match")
		if str(validation.get("invocation_manifest_hash", "")) != canonical_hash(manifest):
			issues.append("validation invocation manifest hash does not match")
		if not (manifest.get("members", null) is Array):
			issues.append("validation invocation manifest members must be an array")
		if not (manifest.get("expected_members", null) is Array):
			issues.append("validation invocation manifest expected_members must be an array")
		if int(manifest.get("cohort_size", -1)) != (manifest.get("members", []) as Array).size():
			issues.append("validation invocation manifest cohort_size does not match members")
		var manifest_content_identities := {}
		var manifest_gameplay_build_identities := {}
		for member_value in manifest.get("members", []):
			if not (member_value is Dictionary):
				continue
			var member := member_value as Dictionary
			var member_schema := str(member.get("content_fingerprint_schema", ""))
			var member_fingerprint := str(member.get("content_fingerprint", ""))
			if ContentFingerprint.is_supported_schema(member_schema) \
					and _valid_sha256_text(member_fingerprint):
				manifest_content_identities["%s|%s" % [
					member_schema, member_fingerprint,
				]] = true
			else:
				issues.append("validation invocation manifest member content identity is invalid")
			var member_build_schema := str(member.get(
				"gameplay_build_fingerprint_schema", ""))
			var member_build_fingerprint := str(member.get(
				"gameplay_build_fingerprint", ""))
			if ContentFingerprint.is_supported_gameplay_build_schema(
					member_build_schema) and _valid_sha256_text(
						member_build_fingerprint):
				manifest_gameplay_build_identities["%s|%s" % [
					member_build_schema, member_build_fingerprint,
				]] = true
			else:
				issues.append(
					"validation invocation manifest member gameplay build identity is invalid")
		if manifest_content_identities.size() != 1:
			issues.append("validation invocation manifest content identity is not uniform")
		if manifest_gameplay_build_identities.size() != 1:
			issues.append(
				"validation invocation manifest gameplay build identity is not uniform")
		if int(validation.get("cohort_size", -1)) != int(manifest.get("cohort_size", -2)):
			issues.append("validation cohort_size does not match the invocation manifest")
		if not (manifest.get("passed", null) is bool):
			issues.append("validation invocation manifest passed must be explicit")
		if not (manifest.get("failures", null) is Array):
			issues.append("validation invocation manifest failures must be an array")
		elif int(manifest.get("failure_count", -1)) != (
				manifest.get("failures", []) as Array).size():
			issues.append("validation invocation manifest failure_count does not match failures")
		if manifest.get("passed", null) is bool:
			var manifest_passed := bool(manifest.get("passed", false))
			var manifest_failure_count := int(manifest.get("failure_count", -1))
			if manifest_passed and manifest_failure_count != 0:
				issues.append("passed invocation manifest must have zero failures")
			elif not manifest_passed and manifest_failure_count < 1:
				issues.append("failed invocation manifest must report at least one failure")
		var cohort_member_value: Variant = validation.get("cohort_member", null)
		if not (cohort_member_value is Dictionary):
			issues.append("validation.cohort_member is required")
		else:
			var cohort_member := cohort_member_value as Dictionary
			if not canonical_equal(_cohort_identity(cohort_member),
					_cohort_identity(run)) \
					or str(cohort_member.get("run_id", "")) != str(run.get("run_id", "")) \
					or str(cohort_member.get("trace_id", "")) != str(run.get("trace_id", "")) \
					or int(cohort_member.get("decision_count", -1)) != decision_count:
				issues.append("validation cohort member does not match this run")
			if str(cohort_member.get("summary_record_hash", "")) != summary_record_hash:
				issues.append("validation cohort member summary hash does not match this run")
			if str(cohort_member.get("content_fingerprint_schema", "")) != str(
					run.get("content_fingerprint_schema", "")) \
					or str(cohort_member.get("content_fingerprint", "")) != str(
						run.get("content_fingerprint", "")):
				issues.append("validation cohort member content identity does not match this run")
			if str(cohort_member.get(
					"gameplay_build_fingerprint_schema", "")) != str(run.get(
						"gameplay_build_fingerprint_schema", "")) \
					or str(cohort_member.get(
						"gameplay_build_fingerprint", "")) != str(run.get(
							"gameplay_build_fingerprint", "")):
				issues.append(
					"validation cohort member gameplay build identity does not match this run")
			if bool(cohort_member.get("trace_complete", false)) != bool(
					summary.get("trace_complete", false)) \
					or bool(cohort_member.get("persona_goal_reached", false)) != bool(
						summary.get("persona_goal_reached", false)):
				issues.append("validation cohort member summary verdict does not match this run")
			var matching_member_count := 0
			for member_value in manifest.get("members", []):
				if member_value is Dictionary and canonical_equal(member_value,
						cohort_member):
					matching_member_count += 1
			if matching_member_count != 1:
				issues.append("validation cohort member must appear exactly once in manifest")
		if bool(manifest.get("passed", false)):
			var expected := expected_validation_cohort(run)
			if expected.is_empty() or not canonical_equal(manifest.get(
					"expected_members", []), expected):
				issues.append("validation invocation manifest expected matrix is not current")
			if int(manifest.get("failure_count", -1)) != 0 \
					or not (manifest.get("failures", null) is Array) \
					or not (manifest.get("failures", []) as Array).is_empty():
				issues.append("passed invocation manifest contains failures")
		elif bool(validation.get("passed", false)):
			issues.append("a passed validation cannot bind a failed invocation manifest")
	issues.sort()
	return issues


static func document_with_validation(document: Dictionary,
		validation_receipt: Dictionary) -> Dictionary:
	var result := document.duplicate(true)
	if not bool(result.get("ok", false)):
		return result
	var records := result.get("records", []) as Array
	if records.is_empty() or str(result.get("summary_record_hash", "")) == "":
		(result["errors"] as Array).append("trace cannot bind validation without a summary")
		result["ok"] = false
		return result
	var shape_issues := validate_validation_receipt_shape(validation_receipt,
		result.get("run", {}) as Dictionary,
		(result.get("decisions", []) as Array).size(),
		str(result.get("summary_record_hash", "")),
		result.get("summary", {}) as Dictionary)
	if not shape_issues.is_empty():
		(result["errors"] as Array).append_array(shape_issues)
		result["ok"] = false
		return result
	var validation_record: Dictionary = json_safe({
		"schema": TRACE_SCHEMA,
		"record_type": VALIDATION_RECORD,
		"run": _decision_run_identity(result.get("run", {}) as Dictionary),
		"summary_record_hash": str(result.get("summary_record_hash", "")),
		"validation": validation_receipt,
		"previous_hash": str((records.back() as Dictionary).get("record_hash", "")),
	}) as Dictionary
	var hash_payload := validation_record.duplicate(true)
	hash_payload.erase("record_hash")
	validation_record["record_hash"] = canonical_hash(hash_payload)
	records.append(validation_record)
	result["records"] = records
	result["validation"] = (validation_record.get("validation", {}) as Dictionary).duplicate(true)
	result["validation_record_hash"] = str(validation_record.get("record_hash", ""))
	var validations: Array = result.get("validations", [])
	validations.append(result["validation"])
	result["validations"] = validations
	return result


static func append_validation(path: String, validation_receipt: Dictionary) -> Dictionary:
	var document := read_trace(path)
	if not bool(document.get("ok", false)):
		return _failure("cannot append validation to an invalid trace: %s" % str(
			document.get("errors", [])))
	var prospective := document_with_validation(document, validation_receipt)
	if not bool(prospective.get("ok", false)):
		return _failure("invalid validation receipt: %s" % str(
			prospective.get("errors", [])))
	var records := prospective.get("records", []) as Array
	var validation_record := records.back() as Dictionary
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return _failure("cannot append validation to %s (error %d)" % [
			path, FileAccess.get_open_error()])
	file.seek_end()
	file.store_line(canonical_json(validation_record))
	file.close()
	var verified := read_trace(path)
	if not bool(verified.get("ok", false)) \
			or str(verified.get("validation_record_hash", "")) != str(
				validation_record.get("record_hash", "")):
		return _failure("appended validation did not survive trace verification: %s" % str(
			verified.get("errors", [])))
	return {
		"ok": true,
		"path": path,
		"record_hash": str(validation_record.get("record_hash", "")),
		"document": verified,
	}


static func validate_run_metadata(run: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	for key in ["run_id", "trace_id", "persona", "fragment_id", "content_fingerprint",
			"content_fingerprint_schema", "gameplay_build_fingerprint",
			"gameplay_build_fingerprint_schema", "execution_platform",
			"evidence_baseline_id"]:
		if str(run.get(key, "")).strip_edges() == "":
			issues.append("run.%s is required" % key)
	if not run.has("seed") or not (run["seed"] is int or run["seed"] is float):
		issues.append("run.seed must be numeric")
	var repeat_value: Variant = run.get("repeat_index", null)
	if not (repeat_value is int or repeat_value is float) \
			or not is_finite(float(repeat_value)) \
			or float(repeat_value) != floorf(float(repeat_value)) \
			or int(repeat_value) < 0:
		issues.append("run.repeat_index must be a non-negative integer")
	if str(run.get("execution_platform", "")) not in ["native", "web"]:
		issues.append("run.execution_platform must be native or web")
	if str(run.get("authored_state", "")) not in ["authored_spawn", "player_reached"]:
		issues.append("run.authored_state must be authored_spawn or player_reached")
	if not ContentFingerprint.is_supported_schema(str(
			run.get("content_fingerprint_schema", ""))):
		issues.append("run.content_fingerprint_schema is not a supported version")
	if not _valid_sha256_text(str(run.get("content_fingerprint", ""))):
		issues.append("run.content_fingerprint must be a lowercase SHA-256 digest")
	if not ContentFingerprint.is_supported_gameplay_build_schema(str(
			run.get("gameplay_build_fingerprint_schema", ""))):
		issues.append(
			"run.gameplay_build_fingerprint_schema is not a supported version")
	if not _valid_sha256_text(str(run.get("gameplay_build_fingerprint", ""))):
		issues.append(
			"run.gameplay_build_fingerprint must be a lowercase SHA-256 digest")
	return issues


static func validate_decision_record(record: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	for key in ["observation_before", "observation_after", "rationale", "decision",
			"input_receipt", "feedback", "outcome", "evidence_context"]:
		if not (record.get(key, null) is Dictionary):
			issues.append("%s must be an object" % key)
	if record.has("observation"):
		issues.append("legacy observation is not valid v3 evidence")
	if not (record.get("observation_samples", null) is Array):
		issues.append("observation_samples must be an array")
	var observation_before := record.get("observation_before", {}) as Dictionary
	var observation_after := record.get("observation_after", {}) as Dictionary
	for issue in validate_player_observation(observation_before):
		issues.append("observation_before:%s" % issue)
	for issue in validate_player_observation(observation_after):
		issues.append("observation_after:%s" % issue)
	var samples: Array = record.get("observation_samples", []) \
		if record.get("observation_samples", null) is Array else []
	for sample_index in range(samples.size()):
		if not (samples[sample_index] is Dictionary):
			issues.append("observation_samples.%d must be an object" % sample_index)
			continue
		for issue in validate_player_observation(samples[sample_index] as Dictionary):
			issues.append("observation_samples.%d:%s" % [sample_index, issue])
	if not canonical_equal(samples, deduplicate_observations(samples)):
		issues.append("observation_samples must be canonical-exact de-duplicated observations")
	for issue in _observation_sequence_reasons(
			observation_before, samples, observation_after):
		issues.append("observation_sequence:%s" % issue)
	var rationale := record.get("rationale", {}) as Dictionary
	if str(rationale.get("text", "")).strip_edges() == "":
		issues.append("rationale.text is required")
	var decision := record.get("decision", {}) as Dictionary
	if str(decision.get("verb", "")).strip_edges() == "":
		issues.append("decision.verb is required")
	if not (decision.get("intended_subjects", null) is Array):
		issues.append("decision.intended_subjects must be an array")
	elif _infer_world_change(decision) \
			and (decision.get("intended_subjects", []) as Array).is_empty():
		issues.append("a world-changing decision needs at least one intended subject")
	var receipt := record.get("input_receipt", {}) as Dictionary
	if str(receipt.get("receipt_id", "")).strip_edges() == "":
		issues.append("input_receipt.receipt_id is required")
	if str(receipt.get("verb", "")).strip_edges() == "":
		issues.append("input_receipt.verb is required")
	if str(receipt.get("status", "")) not in ["accepted", "refused", "observed"]:
		issues.append("input_receipt.status must be accepted, refused, or observed")
	var outcome := record.get("outcome", {}) as Dictionary
	if str(outcome.get("status", "")).strip_edges() == "":
		issues.append("outcome.status is required")
	var derived := derive_feedback_outcome(
		observation_before, observation_after, samples, decision, receipt)
	if not canonical_equal(record.get("feedback", {}),
			derived.get("feedback", {})):
		issues.append("feedback does not match the exact v3 derived feedback")
	if not canonical_equal(record.get("outcome", {}),
			derived.get("outcome", {})):
		issues.append("outcome does not match the exact v3 derived outcome")
	issues.sort()
	return issues


static func classify_evidence(record: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	var observation_before := record.get("observation_before", {}) as Dictionary
	var observation_after := record.get("observation_after", {}) as Dictionary
	var samples: Array = record.get("observation_samples", []) \
		if record.get("observation_samples", null) is Array else []
	var decision := record.get("decision", {}) as Dictionary
	var receipt := record.get("input_receipt", {}) as Dictionary
	var context := record.get("evidence_context", {}) as Dictionary
	for issue in validate_player_observation(observation_before):
		reasons.append("observation_before_schema:%s" % issue)
	for issue in validate_player_observation(observation_after):
		reasons.append("observation_after_schema:%s" % issue)
	for sample_index in range(samples.size()):
		if not (samples[sample_index] is Dictionary):
			reasons.append("observation_sample_not_an_object:%d" % sample_index)
			continue
		for issue in validate_player_observation(samples[sample_index] as Dictionary):
			reasons.append("observation_sample_schema:%d:%s" % [sample_index, issue])
	if not canonical_equal(samples, deduplicate_observations(samples)):
		reasons.append("observation_samples_not_deduplicated")
	reasons.append_array(_observation_sequence_reasons(
		observation_before, samples, observation_after))
	var derived := derive_feedback_outcome(
		observation_before, observation_after, samples, decision, receipt)
	var feedback := derived.get("feedback", {}) as Dictionary
	var outcome := derived.get("outcome", {}) as Dictionary
	if not canonical_equal(record.get("feedback", {}), feedback):
		reasons.append("forged_or_stale_derived_feedback")
	if not canonical_equal(record.get("outcome", {}), outcome):
		reasons.append("forged_or_stale_derived_outcome")
	reasons.append_array(_receipt_input_proof_reasons(
		decision, receipt, observation_before, samples, observation_after))
	if not bool(receipt.get("player_reproducible", false)):
		reasons.append("receipt_not_player_reproducible")
	if str(receipt.get("status", "")) not in ["accepted", "refused", "observed"]:
		reasons.append("receipt_status_missing")
	if str(receipt.get("verb", "")) != str(decision.get("verb", "")):
		reasons.append("receipt_verb_does_not_match_decision")
	if not bool(context.get("authored_state", false)):
		reasons.append("not_from_authored_or_player_reached_state")
	if bool(context.get("fixture_quarantine", false)):
		reasons.append("fixture_quarantine")
	if str(context.get("evidence_baseline_id", "")).strip_edges() == "":
		reasons.append("evidence_baseline_missing")
	var verb := str(decision.get("verb", "")).to_lower()
	if verb in FORBIDDEN_VERBS or verb.begins_with("qa_") \
			or verb.begins_with("debug_") or verb.begins_with("fixture_"):
		reasons.append("forbidden_internal_or_mutating_verb")
	if verb == "interact":
		reasons.append_array(_interaction_target_result_reasons(
			observation_before, observation_after, samples,
			decision, receipt, outcome))
	elif verb in ["move", "rally"]:
		reasons.append_array(_movement_result_reasons(
			observation_before, observation_after, samples,
			decision, receipt, feedback, outcome))
	if verb == "rally":
		reasons.append_array(_full_roster_action_reasons(
			observation_before, decision, receipt, outcome, true))
	elif verb == "select_party" \
			and record.get("learning_candidate", null) is Dictionary \
			and not (record.get("learning_candidate", {}) as Dictionary).is_empty():
		reasons.append_array(_full_roster_action_reasons(
			observation_before, decision, receipt, outcome, false))
	var world_change := _infer_world_change(decision)
	if world_change and str(receipt.get("status", "")) == "observed":
		reasons.append("world_change_has_no_accepted_or_refused_receipt")
	if world_change:
		if not bool(outcome.get("world_causal_evidence", false)):
			reasons.append("derived_visible_world_change_missing")
	elif verb not in ["wait", "hover", "camera_pan", "camera_recenter", "camera_rotate", "camera_zoom"] \
			and str(receipt.get("status", "")) in ["accepted", "refused"] \
			and not bool(outcome.get("visible_change", false)):
		reasons.append("presentation_action_visible_delta_missing")
	if verb == "wait" and bool(outcome.get("passive_no_delta", false)) \
			and record.get("learning_candidate", null) is Dictionary \
			and not (record.get("learning_candidate", {}) as Dictionary).is_empty():
		reasons.append("passive_wait_without_delta_cannot_support_candidate")
	if _infer_group_action(decision):
		if not bool(receipt.get("atomic_group", false)):
			reasons.append("group_verb_was_decomposed")
		var receipt_status := str(receipt.get("status", ""))
		var expected_event_count := 1 if receipt_status == "accepted" else 0
		if receipt_status in ["accepted", "refused"] \
				and int(receipt.get("production_event_count", 0)) != expected_event_count:
			reasons.append("group_verb_production_event_count_does_not_match_receipt")
		var member_results: Variant = receipt.get("member_results", null)
		var intended_members: Variant = receipt.get("intended_members", null)
		if not (intended_members is Array) or not _same_unique_string_members(
				intended_members as Array, decision.get("intended_subjects", []) as Array):
			reasons.append("group_intended_members_do_not_match_decision")
		if not (member_results is Dictionary):
			reasons.append("group_member_results_missing")
		else:
			if intended_members is Array \
					and (member_results as Dictionary).size() != (intended_members as Array).size():
				reasons.append("group_member_result_count_does_not_match_intent")
			var expected_member_result := "accepted" if receipt_status == "accepted" \
				else ("refused" if receipt_status == "refused" else "")
			for raw_subject in decision.get("intended_subjects", []):
				var subject := str(raw_subject)
				if not (member_results as Dictionary).has(subject) \
						or str((member_results as Dictionary).get(subject, "")) \
							not in ["accepted", "refused"]:
					reasons.append("group_member_result_missing:%s" % subject)
				elif expected_member_result != "" \
						and str((member_results as Dictionary).get(subject, "")) \
							!= expected_member_result:
					reasons.append("group_member_result_not_atomic:%s" % subject)
	var unique_reasons := {}
	for reason in reasons:
		unique_reasons[str(reason)] = true
	var sorted_reasons: Array[String] = []
	for reason in unique_reasons.keys():
		sorted_reasons.append(str(reason))
	sorted_reasons.sort()
	var player_reproducible := sorted_reasons.is_empty()
	if verb == "hover":
		sorted_reasons.append("presentation_hover_not_gameplay_learning_candidate")
		sorted_reasons.sort()
	elif verb in ["camera_pan", "camera_recenter", "camera_rotate", "camera_zoom"]:
		sorted_reasons.append("presentation_recovery_not_gameplay_learning_candidate")
		sorted_reasons.sort()
	return {
		"player_reproducible": player_reproducible,
		"eligible_for_learning": sorted_reasons.is_empty(),
		"rejection_reasons": sorted_reasons,
	}


static func validate_player_observation(observation: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	_append_unknown_key_issues(issues, observation, OBSERVATION_KEYS, "observation")
	if str(observation.get("schema", "")) != PLAYER_OBSERVATION_SCHEMA:
		issues.append("observation.schema must be %s" % PLAYER_OBSERVATION_SCHEMA)
	if str(observation.get("source", "")) != "player_observable":
		issues.append("observation.source must be player_observable")
	if not (observation.get("tick", null) is int or observation.get("tick", null) is float) \
			or not is_finite(float(observation.get("tick", NAN))) \
			or float(observation.get("tick", -1.0)) < 0.0:
		issues.append("observation.tick must be a finite non-negative scheduler tick")
	if not _positive_integral_number(observation.get("capture_serial", null)):
		issues.append("observation.capture_serial must be a positive monotonic integer")
	if not (observation.get("state", null) is Dictionary):
		issues.append("observation.state must be an object")
		return issues
	var state := observation.get("state", {}) as Dictionary
	_append_unknown_key_issues(issues, state, OBSERVATION_STATE_KEYS, "observation.state")
	if not (state.get("hud", null) is Dictionary):
		issues.append("observation.state.hud must be an object")
	else:
		_validate_safe_hud(issues, state.get("hud"), "observation.state.hud", 0)
		for roster_issue in (_visible_hud_roster(observation).get(
				"reasons", []) as Array):
			issues.append("observation.state.hud.%s" % str(roster_issue))
	if not (state.get("viewport", null) is Dictionary):
		issues.append("observation.state.viewport must be an object")
	else:
		var viewport := state.get("viewport", {}) as Dictionary
		_append_unknown_key_issues(issues, viewport, VIEWPORT_PRESENTATION_KEYS,
			"observation.state.viewport")
		_validate_screen(issues, viewport.get("origin"),
			"observation.state.viewport.origin", false)
		_validate_screen(issues, viewport.get("size"),
			"observation.state.viewport.size", false)
		if viewport.get("size", null) is Array \
				and (viewport.get("size", []) as Array).size() == 2:
			for coordinate in viewport.get("size", []):
				if (coordinate is int or coordinate is float) and float(coordinate) < 0.0:
					issues.append("observation.state.viewport.size must be non-negative")
					break
	if not (state.get("affordances", null) is Array):
		issues.append("observation.state.affordances must be an array")
	else:
		var affordance_index := 0
		for raw_affordance in state.get("affordances", []):
			var prefix := "observation.state.affordances.%d" % affordance_index
			affordance_index += 1
			if not (raw_affordance is Dictionary):
				issues.append("%s must be an object" % prefix)
				continue
			var affordance := raw_affordance as Dictionary
			_append_unknown_key_issues(issues, affordance,
				AFFORDANCE_PRESENTATION_KEYS, prefix)
			for text_key in ["token", "kind", "verb"]:
				if str(affordance.get(text_key, "")).strip_edges() == "":
					issues.append("%s.%s is required" % [prefix, text_key])
			if not affordance.has("consequence") or not (affordance["consequence"] is String):
				issues.append("%s.consequence must be presented text (empty is allowed)" % prefix)
			_validate_screen(issues, affordance.get("screen"), "%s.screen" % prefix, false)
		for field_spec in [
				["visible_affordance_verbs", "verb"],
				["visible_affordance_consequences", "consequence"],
			]:
			var state_key := str(field_spec[0])
			var affordance_key := str(field_spec[1])
			var list_value: Variant = state.get(state_key, null)
			if not (list_value is Array):
				issues.append("observation.state.%s must be an array" % state_key)
				continue
			var strings_only := true
			for raw_text in (list_value as Array):
				if not (raw_text is String or raw_text is StringName):
					strings_only = false
					break
			if not strings_only:
				issues.append("observation.state.%s must contain only strings" % state_key)
				continue
			var expected_values := _visible_affordance_texts(
				state.get("affordances", []) as Array, affordance_key)
			if not canonical_equal(list_value, expected_values):
				issues.append("observation.state.%s must be the sorted exact visible %s list" % [
					state_key, affordance_key])
	if not (state.get("cues", null) is Array):
		issues.append("observation.state.cues must be an array")
	else:
		var cue_index := 0
		for raw_cue in state.get("cues", []):
			var prefix := "observation.state.cues.%d" % cue_index
			cue_index += 1
			if not (raw_cue is Dictionary):
				issues.append("%s must be an object" % prefix)
				continue
			var cue := raw_cue as Dictionary
			_append_unknown_key_issues(issues, cue, CUE_PRESENTATION_KEYS, prefix)
			if str(cue.get("kind", "")).strip_edges() == "":
				issues.append("%s.kind is required" % prefix)
			_validate_safe_cue_values(issues, cue, prefix)
			if str(cue.get("kind", "")) == "movement_result":
				if str(cue.get("target_token", "")).strip_edges() == "":
					issues.append("%s.target_token is required" % prefix)
				if not (cue.get("subjects", null) is Array) \
						or (cue.get("subjects", []) as Array).is_empty():
					issues.append("%s.subjects must be a nonempty portrait-token array" % prefix)
				elif not _same_unique_string_members(
						cue.get("subjects", []) as Array,
						cue.get("subjects", []) as Array):
					issues.append("%s.subjects must be unique nonempty tokens" % prefix)
				if str(cue.get("phase", "")) not in [
						"accepted", "progress", "arrival", "interrupted", "refused"]:
					issues.append("%s.phase is not a movement-result phase" % prefix)
				if not (cue.get("accepted", null) is bool):
					issues.append("%s.accepted must be explicit" % prefix)
				if not (cue.get("reason", null) is String):
					issues.append("%s.reason must be presented text" % prefix)
				if not _positive_integral_number(cue.get("presentation_serial", null)):
					issues.append("%s.presentation_serial must be positive" % prefix)
				_validate_movement_route_status_cue(
					issues, observation, cue, prefix)
			elif _cue_has_movement_route_status(cue):
				issues.append(
					"%s route-status fields require a movement_result cue" % prefix)
	if not (state.get("viewport_bins", null) is Dictionary):
		issues.append("observation.state.viewport_bins must be an object")
	else:
		_validate_viewport_bins(issues, state.get("viewport_bins", {}) as Dictionary,
			"observation.state.viewport_bins")
	_append_forbidden_observation_key_issues(issues, state, "observation.state")
	issues.sort()
	return issues


static func _visible_affordance_texts(affordances: Array, key: String) -> Array[String]:
	var unique := {}
	for raw_affordance in affordances:
		if not (raw_affordance is Dictionary):
			continue
		var value := str((raw_affordance as Dictionary).get(key, "")).strip_edges()
		if value != "":
			unique[value] = true
	var result: Array[String] = []
	for raw_value in unique.keys():
		result.append(str(raw_value))
	result.sort()
	return result


static func _append_unknown_key_issues(issues: Array[String], value: Dictionary,
		allowed_keys: Array, prefix: String) -> void:
	for raw_key in value.keys():
		var key := str(raw_key)
		if key not in allowed_keys:
			issues.append("%s.%s is not player_observation_v1" % [prefix, key])


static func _validate_safe_hud(issues: Array[String], value: Variant, path: String,
		depth: int) -> void:
	if depth > 6:
		issues.append("%s exceeds the HUD presentation depth limit" % path)
		return
	if value is Dictionary:
		for raw_key in (value as Dictionary).keys():
			var key := str(raw_key)
			if key not in HUD_PRESENTATION_KEYS:
				issues.append("%s.%s is not a HUD presentation field" % [path, key])
				continue
			if key == "screen":
				_validate_screen(issues, (value as Dictionary)[raw_key],
					"%s.screen" % path, true)
			else:
				_validate_safe_hud(issues, (value as Dictionary)[raw_key],
					"%s.%s" % [path, key], depth + 1)
	elif value is Array:
		var index := 0
		for item in value:
			_validate_safe_hud(issues, item, "%s.%d" % [path, index], depth + 1)
			index += 1
	elif value is float:
		if not is_finite(float(value)):
			issues.append("%s must be finite" % path)
	elif not (value is String or value is StringName or value is bool or value is int \
			or value == null):
		issues.append("%s is not a safe HUD presentation value" % path)


static func _validate_safe_cue_values(issues: Array[String], cue: Dictionary,
		path: String) -> void:
	for raw_key in cue.keys():
		var key := str(raw_key)
		var value: Variant = cue[raw_key]
		if key == "screen":
			_validate_screen(issues, value, "%s.screen" % path, false)
			continue
		if value is Array:
			for item in value:
				if not (item is String or item is StringName or item is int or item is float \
						or item is bool) or (item is float and not is_finite(float(item))):
					issues.append("%s.%s contains a non-presentation value" % [path, key])
					break
		elif value is float and not is_finite(float(value)):
			issues.append("%s.%s must be finite" % [path, key])
		elif not (value is String or value is StringName or value is bool or value is int \
				or value is float or value == null):
			issues.append("%s.%s is not a presentation value" % [path, key])


static func _cue_has_movement_route_status(cue: Dictionary) -> bool:
	for key in MOVEMENT_ROUTE_STATUS_KEYS:
		if cue.has(key):
			return true
	return false


static func _validate_movement_route_status_cue(
		issues: Array[String],
		observation: Dictionary,
		cue: Dictionary,
		path: String
	) -> void:
	var present_count := 0
	for key in MOVEMENT_ROUTE_STATUS_KEYS:
		if cue.has(key):
			present_count += 1
	if present_count == 0:
		return
	if present_count != MOVEMENT_ROUTE_STATUS_KEYS.size():
		issues.append("%s route-status fields must be present together" % path)

	var status_value: Variant = cue.get("route_status", null)
	var status := str(status_value) \
		if status_value is String or status_value is StringName else ""
	if not (status_value is String or status_value is StringName) \
			or status not in MOVEMENT_ROUTE_STATUSES:
		issues.append("%s.route_status is not a visible movement route status" % path)

	var serial_value: Variant = cue.get("route_status_serial", null)
	if not _nonnegative_integral_number(serial_value):
		issues.append("%s.route_status_serial must be a non-negative integer" % path)

	var remaining_value: Variant = cue.get(
		"route_status_remaining_seconds", null)
	var remaining_valid := (remaining_value is int or remaining_value is float) \
		and is_finite(float(remaining_value)) and float(remaining_value) >= 0.0
	var remaining := float(remaining_value) if remaining_valid else 0.0
	if not remaining_valid:
		issues.append(
			"%s.route_status_remaining_seconds must be finite and non-negative" % path)

	var status_subjects_value: Variant = cue.get("route_status_subjects", null)
	var status_subjects: Array = status_subjects_value \
		if status_subjects_value is Array else []
	var status_subjects_are_tokens := status_subjects_value is Array
	for subject_value in status_subjects:
		if not (subject_value is String or subject_value is StringName) \
				or str(subject_value).strip_edges() == "":
			status_subjects_are_tokens = false
			break
	var status_subjects_valid := status_subjects_are_tokens \
		and _same_unique_string_members(status_subjects, status_subjects)
	if not status_subjects_valid:
		issues.append(
			"%s.route_status_subjects must be a unique portrait-token array" % path)

	if status == "":
		if status_subjects_value is Array and not status_subjects.is_empty():
			issues.append(
				"%s.route_status_subjects must be empty without an active route status" \
				% path)
		if remaining_valid and remaining != 0.0:
			issues.append(
				"%s.route_status_remaining_seconds must be zero without an active route status" \
				% path)
		return

	if not _positive_integral_number(serial_value):
		issues.append(
			"%s.route_status_serial must be positive for an active route status" % path)
	if status_subjects_value is Array and status_subjects.is_empty():
		issues.append(
			"%s.route_status_subjects must be nonempty for an active route status" \
			% path)
	if status_subjects_valid:
		var movement_subjects: Array = cue.get("subjects", []) \
			if cue.get("subjects", null) is Array else []
		var portrait_tokens := (_visible_hud_roster(observation).get(
			"portrait_tokens", []) as Array)
		for subject_value in status_subjects:
			var subject_token := str(subject_value)
			if not movement_subjects.has(subject_token):
				issues.append(
					"%s.route_status_subjects must be a subset of movement subjects" \
					% path)
				break
		for subject_value in status_subjects:
			if not portrait_tokens.has(str(subject_value)):
				issues.append(
					"%s.route_status_subjects must contain only visible portrait tokens" \
					% path)
				break
	if status == "reforming_route" and remaining_valid and remaining != 0.0:
		issues.append(
			"%s.route_status_remaining_seconds must be zero while reforming" % path)
	elif status == "cooperative_hold" and remaining_valid and remaining <= 0.0:
		issues.append(
			"%s.route_status_remaining_seconds must be positive during a cooperative hold" \
			% path)


static func _validate_viewport_bins(issues: Array[String], bins: Dictionary,
		path: String) -> void:
	for raw_bin in bins.keys():
		var bin_name := str(raw_bin)
		if not _valid_lower_snake(bin_name):
			issues.append("%s.%s is not a semantic viewport bin" % [path, bin_name])
			continue
		var contents: Variant = bins[raw_bin]
		if not (contents is Array):
			issues.append("%s.%s must be an array of presentation tokens" % [path, bin_name])
			continue
		for token in contents:
			if not (token is String or token is StringName) or str(token).strip_edges() == "":
				issues.append("%s.%s contains an invalid presentation token" % [path, bin_name])
				break


static func _append_forbidden_observation_key_issues(issues: Array[String], value: Variant,
		path: String) -> void:
	if value is Dictionary:
		for raw_key in (value as Dictionary).keys():
			var key := str(raw_key)
			if key in FORBIDDEN_OBSERVATION_KEYS:
				issues.append("%s.%s is forbidden internal or world data" % [path, key])
			_append_forbidden_observation_key_issues(issues,
				(value as Dictionary)[raw_key], "%s.%s" % [path, key])
	elif value is Array:
		var index := 0
		for item in value:
			_append_forbidden_observation_key_issues(issues, item,
				"%s.%d" % [path, index])
			index += 1


static func _valid_lower_snake(value: String) -> bool:
	if value == "" or value.begins_with("_") or value.ends_with("_"):
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) \
				and code != 95:
			return false
	return not value.contains("__")


static func _valid_sha256_text(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


static func _same_string_members(a: Array, b: Array) -> bool:
	var left: Array[String] = []
	var right: Array[String] = []
	for value in a:
		left.append(str(value))
	for value in b:
		right.append(str(value))
	left.sort()
	right.sort()
	return left == right


static func _same_unique_string_members(a: Array, b: Array) -> bool:
	var left: Array[String] = []
	var right: Array[String] = []
	for value in a:
		var text := str(value)
		if text == "" or left.has(text):
			return false
		left.append(text)
	for value in b:
		var text := str(value)
		if text == "" or right.has(text):
			return false
		right.append(text)
	left.sort()
	right.sort()
	return left == right


static func _receipt_input_proof_reasons(decision: Dictionary, receipt: Dictionary,
		observation_before: Dictionary, observation_samples: Array,
		observation_after: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	reasons.append_array(_background_validation_receipt_reasons(receipt))
	var verb := str(decision.get("verb", "")).to_lower()
	var boundary := str(receipt.get("boundary", ""))
	var input_events: Array = receipt.get("input_events", []) \
		if receipt.get("input_events", null) is Array else []
	var input_event_count := int(receipt.get("input_event_count", -1))
	var production_kinds: Array = receipt.get("production_event_kinds", []) \
		if receipt.get("production_event_kinds", null) is Array else []
	if not (receipt.get("production_event_kinds", null) is Array) \
			or int(receipt.get("production_event_count", -1)) < 0:
		reasons.append("production_event_proof_fields_invalid")
	if verb == "wait" and boundary == "player_command":
		if boundary != "player_command":
			reasons.append("passive_wait_boundary_must_be_player_command")
		if bool(receipt.get("input_issued", true)) or input_event_count != 0 \
				or not input_events.is_empty():
			reasons.append("passive_wait_must_not_issue_input")
		if int(receipt.get("production_event_count", -1)) != 0 \
				or not production_kinds.is_empty():
			reasons.append("passive_wait_must_not_emit_production_events")
		if receipt.has("input_sequence_before") or receipt.has("input_sequence_after"):
			reasons.append("passive_wait_must_not_claim_input_sequence")
		return reasons
	if verb == "wait" and boundary != "keyboard_pointer":
		reasons.append("wait_boundary_must_be_passive_or_keyboard_pointer")
	if verb == "hover" and (int(receipt.get("production_event_count", -1)) != 0 \
			or not production_kinds.is_empty()):
		reasons.append("presentation_hover_must_not_emit_production_events")
	if boundary != "keyboard_pointer":
		reasons.append("active_action_boundary_must_be_keyboard_pointer")
	if not bool(receipt.get("input_issued", false)):
		reasons.append("active_action_driver_input_missing")
	if input_event_count < 1 or input_event_count != input_events.size():
		reasons.append("active_action_input_event_count_invalid")
	var sequence_before_value: Variant = receipt.get("input_sequence_before", null)
	var sequence_after_value: Variant = receipt.get("input_sequence_after", null)
	var sequence_before := -1
	var sequence_after := -1
	if not _nonnegative_integral_number(sequence_before_value) \
			or not _nonnegative_integral_number(sequence_after_value):
		reasons.append("active_action_input_sequence_bounds_invalid")
	else:
		sequence_before = int(sequence_before_value)
		sequence_after = int(sequence_after_value)
		if sequence_after <= sequence_before \
				or sequence_after - sequence_before != input_event_count:
			reasons.append("active_action_input_sequence_range_invalid")
	var previous_sequence := sequence_before
	var saw_key := false
	var key_down := {}
	var key_pairs := {}
	var pointer_down := {}
	var pointer_pairs := {}
	var event_keys: Array[String] = []
	var selection_press_events: Array[Dictionary] = []
	for event_index in range(input_events.size()):
		var event_value: Variant = input_events[event_index]
		if not (event_value is Dictionary):
			reasons.append("active_action_input_event_not_an_object")
			continue
		var event := event_value as Dictionary
		if event.get("issued", null) is not bool \
				or not bool(event.get("issued", false)):
			reasons.append("active_action_input_event_not_issued")
		var sequence_value: Variant = event.get("sequence", null)
		var expected_sequence := sequence_before + event_index + 1
		if not _positive_integral_number(sequence_value) \
				or int(sequence_value) != expected_sequence \
				or int(sequence_value) <= previous_sequence:
			reasons.append("active_action_input_event_sequence_invalid")
		else:
			previous_sequence = int(sequence_value)
		var kind := str(event.get("kind", ""))
		if kind == "key":
			saw_key = true
			var key := str(event.get("key", "")).strip_edges()
			if key == "" \
					or not (event.get("pressed", null) is bool) \
					or not (event.get("modifiers", null) is Dictionary):
				reasons.append("active_action_key_event_shape_invalid")
			else:
				var modifiers := event.get("modifiers", {}) as Dictionary
				for modifier in ["ctrl", "shift", "alt", "meta"]:
					if not (modifiers.get(modifier, null) is bool):
						reasons.append("active_action_key_modifiers_invalid")
						break
				if key != "" and not event_keys.has(key):
					event_keys.append(key)
				if bool(event.get("pressed", false)):
					if key_down.has(key):
						reasons.append("active_action_key_pressed_twice:%s" % key)
					key_down[key] = modifiers.duplicate(true)
					if key in ["Digit1", "Digit2", "Digit3"]:
						selection_press_events.append({
							"key": key,
							"modifiers": modifiers.duplicate(true),
						})
				elif not key_down.has(key):
					reasons.append("active_action_key_release_without_press:%s" % key)
				else:
					if not canonical_equal(key_down.get(key, {}), modifiers):
						reasons.append(
							"active_action_key_pair_modifiers_mismatch:%s" % key)
					key_down.erase(key)
					key_pairs[key] = int(key_pairs.get(key, 0)) + 1
		elif kind == "pointer_button":
			var raw_button: Variant = event.get("button", null)
			if not _positive_integral_number(raw_button) \
					or not (event.get("pressed", null) is bool):
				reasons.append("active_action_pointer_button_shape_invalid")
			else:
				var button := int(raw_button)
				if bool(event.get("pressed", false)):
					if bool(pointer_down.get(button, false)):
						reasons.append(
							"active_action_pointer_pressed_twice:%d" % button)
					pointer_down[button] = true
				elif not bool(pointer_down.get(button, false)):
					reasons.append(
						"active_action_pointer_release_without_press:%d" % button)
				else:
					pointer_down[button] = false
					pointer_pairs[button] = int(pointer_pairs.get(button, 0)) + 1
		elif kind != "pointer_move":
			reasons.append("active_action_input_event_kind_invalid:%s" % kind)
	if sequence_after >= 0 and previous_sequence != sequence_after:
		reasons.append("active_action_input_sequence_after_mismatch")
	for key_value in key_down.keys():
		reasons.append("active_action_key_left_pressed:%s" % str(key_value))
	for button_value in pointer_down.keys():
		if bool(pointer_down[button_value]):
			reasons.append("active_action_pointer_left_pressed:%s" % str(button_value))
	reasons.append_array(_verb_gesture_reasons(
		verb, decision, event_keys, key_pairs, pointer_pairs,
		selection_press_events, input_events,
		observation_before, observation_after))
	if verb in ["move", "rally", "interact"]:
		var target_value: Variant = decision.get("target", null)
		var target_token := str((target_value as Dictionary).get("token", "")) \
			if target_value is Dictionary else ""
		if str(receipt.get("input_target_token", "")) != target_token:
			reasons.append("world_action_input_target_binding_mismatch")
	if verb in ["camera_pan", "camera_recenter", "camera_rotate", "select_party",
			"select_single", "recenter",
			"toggle_instructions", "toggle_run"] and not saw_key:
		reasons.append("keyboard_action_gesture_unproven")
	if verb == "wait" and not saw_key:
		reasons.append("active_wait_keyboard_gesture_unproven")
	if verb == "wait" and (int(receipt.get("production_event_count", -1)) != 0 \
			or not production_kinds.is_empty()):
		reasons.append("active_wait_must_not_emit_production_events")
	var before_serial := int(observation_before.get("capture_serial", 0))
	var first_post_serial := int(observation_after.get("capture_serial", 0))
	if not observation_samples.is_empty() and observation_samples[0] is Dictionary:
		first_post_serial = int((observation_samples[0] as Dictionary).get(
			"capture_serial", 0))
	if int(receipt.get("observation_before_capture_serial", -1)) != before_serial:
		reasons.append("input_before_capture_binding_mismatch")
	if int(receipt.get("first_post_input_capture_serial", -1)) != first_post_serial \
			or first_post_serial <= before_serial:
		reasons.append("input_post_capture_binding_mismatch")
	return reasons


static func _background_validation_receipt_reasons(
		receipt: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	var fields := [
		"validation_background_event_count",
		"validation_background_event_kinds",
		"validation_background_visual_lineage",
	]
	var present_count := 0
	for field in fields:
		if receipt.has(field):
			present_count += 1
	if present_count == 0:
		return reasons
	if present_count != fields.size():
		reasons.append("background_validation_receipt_fields_incomplete")
		return reasons
	var count_value: Variant = receipt.get(
		"validation_background_event_count", null)
	var kinds_value: Variant = receipt.get(
		"validation_background_event_kinds", null)
	var lineage_value: Variant = receipt.get(
		"validation_background_visual_lineage", null)
	if not _nonnegative_integral_number(count_value) or not (kinds_value is Array) \
			or not (lineage_value is Dictionary):
		reasons.append("background_validation_receipt_fields_invalid")
		return reasons
	var event_count := int(count_value)
	var event_kinds := kinds_value as Array
	var lineage := lineage_value as Dictionary
	if event_kinds.size() != event_count \
			or int(lineage.get("event_count", -1)) != event_count \
			or not canonical_equal(lineage.get("event_kinds", []), event_kinds):
		reasons.append("background_validation_event_proof_mismatch")
	if not bool(lineage.get("ok", false)) \
			or not (lineage.get("failures", null) is Array) \
			or not (lineage.get("failures", []) as Array).is_empty():
		reasons.append("background_presentation_validation_failed")
	if _background_validation_has_private_key(lineage):
		reasons.append("background_validation_contains_private_event_data")
	return reasons


static func _background_validation_has_private_key(value: Variant) -> bool:
	if value is Array:
		for child in value as Array:
			if _background_validation_has_private_key(child):
				return true
		return false
	if not (value is Dictionary):
		return false
	var forbidden := [
		"id", "character_id", "subject_id", "event_id", "traversal_id",
		"message", "payload",
	]
	for key_v in (value as Dictionary).keys():
		if str(key_v) in forbidden \
				or _background_validation_has_private_key((value as Dictionary)[key_v]):
			return true
	return false


static func _verb_gesture_reasons(verb: String, decision: Dictionary,
		event_keys: Array[String], key_pairs: Dictionary,
		pointer_pairs: Dictionary, selection_press_events: Array[Dictionary],
		input_events: Array, observation_before: Dictionary,
		observation_after: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	var allowed_keys: Array[String] = []
	var allowed_buttons: Array[int] = []
	match verb:
		"move", "interact", "use":
			allowed_keys = ["Digit1", "Digit2", "Digit3"]
			allowed_buttons = [2]
			if int(pointer_pairs.get(2, 0)) != 1:
				reasons.append(
					"world_action_right_pointer_pair_must_be_exactly_one")
		"rally":
			allowed_buttons = [2]
			if int(pointer_pairs.get(2, 0)) != 1:
				reasons.append("rally_right_pointer_pair_must_be_exactly_one")
		"push":
			allowed_keys = ["Digit1", "Digit2", "Digit3"]
			allowed_buttons = [1, 2]
			if int(pointer_pairs.get(1, 0)) < 1 \
					or int(pointer_pairs.get(2, 0)) < 1:
				reasons.append("push_pointer_plan_commit_pairs_missing")
		"select_party":
			allowed_keys = ["Digit1", "Digit2", "Digit3"]
			var expected_keys: Array[String] = []
			for subject_value in decision.get("intended_subjects", []):
				var mapped_key := _selection_key_for_subject(str(subject_value))
				if mapped_key != "" and not expected_keys.has(mapped_key):
					expected_keys.append(mapped_key)
			if expected_keys.is_empty():
				reasons.append("select_party_subject_key_mapping_missing")
			for expected_key in expected_keys:
				if int(key_pairs.get(expected_key, 0)) != 1:
					reasons.append(
					"select_party_subject_key_pair_missing:%s" % expected_key)
			if selection_press_events.size() != expected_keys.size():
				reasons.append("select_party_selection_chord_size_mismatch")
			else:
				for press_index in range(selection_press_events.size()):
					var modifiers := (selection_press_events[press_index] as Dictionary).get(
						"modifiers", {}) as Dictionary
					var expected_ctrl := press_index > 0
					if bool(modifiers.get("ctrl", false)) != expected_ctrl \
							or bool(modifiers.get("shift", false)) \
							or bool(modifiers.get("alt", false)) \
							or bool(modifiers.get("meta", false)):
						reasons.append("select_party_selection_chord_invalid")
						break
		"select_single":
			allowed_keys = ["Digit1", "Digit2", "Digit3"]
			# A human has two shipped ways to establish a singleton: press that
			# portrait's number when it is not selected, or keep an already-selected
			# portrait and Ctrl-toggle every selected sibling off. The latter must not
			# be rejected merely because the retained subject's key is a deliberate
			# no-op and therefore never pressed.
			if not _select_single_gesture_is_exact(
					decision, key_pairs, selection_press_events,
					observation_before, observation_after):
				reasons.append("select_single_subject_key_pair_missing")
		"camera_pan":
			allowed_keys = ["KeyW", "KeyA", "KeyS", "KeyD"]
			var pan_pair_count := 0
			for pan_key in allowed_keys:
				pan_pair_count += int(key_pairs.get(pan_key, 0))
			if event_keys.size() != 1 or pan_pair_count < 1:
				reasons.append("camera_pan_wasd_key_pairs_missing_or_ambiguous")
		"camera_rotate":
			allowed_keys = ["KeyQ", "KeyE"]
			var rotate_pair_count := int(key_pairs.get("KeyQ", 0)) \
				+ int(key_pairs.get("KeyE", 0))
			if event_keys.size() != 1 or rotate_pair_count != 1:
				reasons.append("camera_rotate_qe_key_pair_missing_or_ambiguous")
		"recenter", "camera_recenter":
			allowed_keys = ["Home"]
			if int(key_pairs.get("Home", 0)) != 1:
				reasons.append("recenter_home_key_pair_missing")
		"toggle_instructions":
			allowed_keys = ["KeyH"]
			if int(key_pairs.get("KeyH", 0)) != 1:
				reasons.append("toggle_instructions_h_key_pair_missing")
		"toggle_run":
			allowed_keys = ["Digit1", "Digit2", "Digit3", "KeyR"]
			if int(key_pairs.get("KeyR", 0)) != 1:
				reasons.append("toggle_run_r_key_pair_missing")
		"zoom_out", "camera_zoom":
			allowed_buttons = [5]
			if int(pointer_pairs.get(5, 0)) < 1:
				reasons.append("zoom_out_wheel_down_pair_missing")
		"hover":
			var pointer_move_count := 0
			for event_value in input_events:
				if not (event_value is Dictionary) \
						or str((event_value as Dictionary).get("kind", "")) \
							!= "pointer_move":
					continue
				pointer_move_count += 1
				var pointer_move := event_value as Dictionary
				if not _finite_screen(pointer_move.get("position", null)):
					reasons.append("presentation_hover_pointer_position_invalid")
				var button_mask_value: Variant = pointer_move.get("button_mask", null)
				if not _nonnegative_integral_number(button_mask_value) \
						or int(button_mask_value) != 0:
					reasons.append("presentation_hover_pointer_button_mask_must_be_clear")
			if pointer_move_count != 1:
				reasons.append("presentation_hover_pointer_move_must_be_exactly_one")
		"wait", "focus":
			allowed_keys = ["KeyF"]
			if int(key_pairs.get("KeyF", 0)) != 1:
				reasons.append("active_wait_f_key_pair_missing")
		"pause":
			allowed_keys = ["Space"]
			if int(key_pairs.get("Space", 0)) != 1:
				reasons.append("pause_space_key_pair_missing")
		_:
			reasons.append("active_action_verb_gesture_unrecognized:%s" % verb)
	for key in event_keys:
		if key not in allowed_keys:
			reasons.append("verb_unrelated_key_event:%s:%s" % [verb, key])
	for event_value in input_events:
		if not (event_value is Dictionary) \
				or str((event_value as Dictionary).get("kind", "")) != "key" \
				or not ((event_value as Dictionary).get("modifiers", null) is Dictionary):
			continue
		var key_event := event_value as Dictionary
		var key := str(key_event.get("key", ""))
		var modifiers := key_event.get("modifiers", {}) as Dictionary
		# Digit selection may use Ctrl. No shipped gesture here uses
		# Shift/Alt/Meta, and semantic action keys are always unmodified.
		if bool(modifiers.get("shift", false)) or bool(modifiers.get("alt", false)) \
				or bool(modifiers.get("meta", false)) \
				or (not key.begins_with("Digit") \
					and bool(modifiers.get("ctrl", false))):
			reasons.append("verb_key_modifiers_invalid:%s:%s" % [verb, key])
	for button_value in pointer_pairs.keys():
		if int(button_value) not in allowed_buttons:
			reasons.append("verb_unrelated_pointer_button:%s:%s" % [
				verb, str(button_value)])
	# A completed pair dictionary is deliberately used above. This final scan
	# rejects a button that never completed even when another allowed button did.
	for event_value in input_events:
		if event_value is Dictionary \
				and str((event_value as Dictionary).get("kind", "")) == "pointer_button":
			var button := int((event_value as Dictionary).get("button", 0))
			if button not in allowed_buttons:
				continue
			if not pointer_pairs.has(button):
				reasons.append("verb_pointer_button_pair_incomplete:%s:%d" % [verb, button])
	return reasons


static func _selection_key_for_subject(subject_value: String) -> String:
	match subject_value.strip_edges().to_snake_case().to_lower():
		"aster": return "Digit1"
		"peris": return "Digit2"
		"endo": return "Digit3"
	return ""


static func _visible_selected_subject_ids(observation: Dictionary) -> Array[String]:
	var selected: Array[String] = []
	var state_v: Variant = observation.get("state", null)
	if not (state_v is Dictionary):
		return selected
	var hud_v: Variant = (state_v as Dictionary).get("hud", null)
	if not (hud_v is Dictionary):
		return selected
	var portraits_v: Variant = (hud_v as Dictionary).get("portraits", null)
	if not (portraits_v is Array):
		return selected
	for portrait_v in portraits_v as Array:
		if not (portrait_v is Dictionary):
			continue
		var portrait := portrait_v as Dictionary
		if not bool(portrait.get("visible", false)) \
				or not bool(portrait.get("selected", false)):
			continue
		var subject_id := _normalize_subject_label(str(portrait.get("label", "")))
		if subject_id != "" and not selected.has(subject_id):
			selected.append(subject_id)
	selected.sort()
	return selected


static func _selection_press_has_modifiers(
		event: Dictionary, ctrl: bool
	) -> bool:
	var modifiers_v: Variant = event.get("modifiers", null)
	if not (modifiers_v is Dictionary):
		return false
	var modifiers := modifiers_v as Dictionary
	return bool(modifiers.get("ctrl", not ctrl)) == ctrl \
		and not bool(modifiers.get("shift", true)) \
		and not bool(modifiers.get("alt", true)) \
		and not bool(modifiers.get("meta", true))


static func _select_single_gesture_is_exact(
		decision: Dictionary,
		key_pairs: Dictionary,
		selection_press_events: Array[Dictionary],
		observation_before: Dictionary,
		observation_after: Dictionary
	) -> bool:
	var intended_v: Variant = decision.get("intended_subjects", null)
	if not (intended_v is Array) or (intended_v as Array).size() != 1:
		return false
	var target_id := _normalize_subject_label(str((intended_v as Array)[0]))
	var target_key := _selection_key_for_subject(target_id)
	if target_id == "" or target_key == "" \
			or _visible_selected_subject_ids(observation_after) != [target_id]:
		return false

	# Direct singleton selection: one unmodified pair for the intended portrait.
	if selection_press_events.size() == 1 \
			and int(key_pairs.get(target_key, 0)) == 1:
		var direct_press := selection_press_events[0] as Dictionary
		if str(direct_press.get("key", "")) == target_key \
				and _selection_press_has_modifiers(direct_press, false):
			return true

	# Group -> singleton selection: the retained target was visibly selected and
	# every other visibly selected portrait is removed with exactly one Ctrl pair.
	var selected_before := _visible_selected_subject_ids(observation_before)
	if selected_before.size() <= 1 or not selected_before.has(target_id):
		return false
	var sibling_keys: Array[String] = []
	for subject_id in selected_before:
		if subject_id == target_id:
			continue
		var sibling_key := _selection_key_for_subject(subject_id)
		if sibling_key == "" or sibling_keys.has(sibling_key):
			return false
		sibling_keys.append(sibling_key)
	sibling_keys.sort()
	if sibling_keys.is_empty() \
			or selection_press_events.size() != sibling_keys.size():
		return false
	var pressed_keys: Array[String] = []
	for press_event in selection_press_events:
		var pressed_key := str(press_event.get("key", ""))
		if not sibling_keys.has(pressed_key) or pressed_keys.has(pressed_key) \
				or int(key_pairs.get(pressed_key, 0)) != 1 \
				or not _selection_press_has_modifiers(press_event, true):
			return false
		pressed_keys.append(pressed_key)
	pressed_keys.sort()
	return pressed_keys == sibling_keys


static func decision_progression_reasons(previous_decisions: Array,
		current_record: Dictionary) -> Array[String]:
	## Canonical cross-decision ledger validation shared by the writer, reader,
	## and generated-strategy verifier. Per-record validation cannot detect an
	## input gap or a replayed observation boundary on its own.
	var reasons: Array[String] = []
	reasons.append_array(_input_sequence_progression_reasons(
		previous_decisions, current_record))
	reasons.append_array(_observation_progression_reasons(
		previous_decisions, current_record))
	reasons.sort()
	return reasons


static func _input_sequence_progression_reasons(previous_decisions: Array,
		current_record: Dictionary) -> Array[String]:
	var current_receipt_value: Variant = current_record.get("input_receipt", null)
	if not (current_receipt_value is Dictionary):
		return []
	var current_receipt := current_receipt_value as Dictionary
	if str(current_receipt.get("boundary", "")) != "keyboard_pointer" \
			or not bool(current_receipt.get("input_issued", false)):
		return []
	var current_before := int(current_receipt.get("input_sequence_before", -1))
	var previous_after := 0
	for index in range(previous_decisions.size() - 1, -1, -1):
		var previous_value: Variant = previous_decisions[index]
		if not (previous_value is Dictionary):
			continue
		var receipt_value: Variant = (previous_value as Dictionary).get(
			"input_receipt", null)
		if not (receipt_value is Dictionary):
			continue
		var receipt := receipt_value as Dictionary
		if str(receipt.get("boundary", "")) == "keyboard_pointer" \
				and bool(receipt.get("input_issued", false)):
			previous_after = int(receipt.get("input_sequence_after", -1))
			break
	if current_before < previous_after:
		return ["input_event_sequence_reused_across_decisions"]
	if current_before > previous_after:
		return ["input_event_sequence_gap_across_decisions"]
	return []


static func _observation_progression_reasons(previous_decisions: Array,
		current_record: Dictionary) -> Array[String]:
	if previous_decisions.is_empty():
		return []
	var previous_value: Variant = previous_decisions.back()
	if not (previous_value is Dictionary):
		return []
	var previous_after_value: Variant = (previous_value as Dictionary).get(
		"observation_after", null)
	var current_before_value: Variant = current_record.get(
		"observation_before", null)
	if not (previous_after_value is Dictionary) \
			or not (current_before_value is Dictionary):
		return []
	var previous_after := previous_after_value as Dictionary
	var current_before := current_before_value as Dictionary
	var reasons: Array[String] = []
	if int(current_before.get("capture_serial", 0)) <= int(
			previous_after.get("capture_serial", 0)):
		reasons.append("observation_capture_not_monotonic_across_decisions")
	if float(current_before.get("tick", 0.0)) < float(
			previous_after.get("tick", 0.0)):
		reasons.append("observation_tick_regressed_across_decisions")
	return reasons


static func deduplicate_observations(observation_samples: Array) -> Array:
	var result: Array = []
	var seen := {}
	for sample in observation_samples:
		var signature := canonical_json(sample)
		if seen.has(signature):
			continue
		seen[signature] = true
		result.append(json_safe(sample))
	return result


static func _observation_sequence_reasons(observation_before: Dictionary,
		observation_samples: Array, observation_after: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	var before_serial_value: Variant = observation_before.get("capture_serial", null)
	var after_serial_value: Variant = observation_after.get("capture_serial", null)
	if not _positive_integral_number(before_serial_value) \
			or not _positive_integral_number(after_serial_value):
		return ["observation_capture_serial_missing"]
	var previous_serial := int(before_serial_value)
	var previous_tick := float(observation_before.get("tick", 0.0))
	for sample_index in range(observation_samples.size()):
		var sample_value: Variant = observation_samples[sample_index]
		if not (sample_value is Dictionary) or not _positive_integral_number(
				(sample_value as Dictionary).get("capture_serial", null)):
			reasons.append("observation_sample_capture_serial_missing:%d" % sample_index)
			continue
		var sample_serial := int((sample_value as Dictionary).get("capture_serial", 0))
		var sample_tick := float((sample_value as Dictionary).get("tick", 0.0))
		if sample_tick < previous_tick:
			reasons.append("observation_tick_regressed_at_sample:%d" % sample_index)
		previous_tick = maxf(previous_tick, sample_tick)
		if sample_serial == previous_serial:
			reasons.append("observation_capture_replayed:%d" % sample_serial)
		elif sample_serial < previous_serial:
			reasons.append("observation_capture_reordered:%d" % sample_serial)
		previous_serial = maxi(previous_serial, sample_serial)
	var after_serial := int(after_serial_value)
	if float(observation_after.get("tick", 0.0)) < previous_tick:
		reasons.append("observation_tick_regressed_at_terminal_capture")
	if after_serial == previous_serial:
		reasons.append("observation_after_replays_prior_capture")
	elif after_serial < previous_serial:
		reasons.append("observation_sample_occurs_after_terminal_capture")
	var unique := {}
	for reason in reasons:
		unique[reason] = true
	var result: Array[String] = []
	for reason in unique.keys():
		result.append(str(reason))
	result.sort()
	return result


static func derive_feedback_outcome(
		observation_before: Dictionary,
		observation_after: Dictionary,
		observation_samples: Array,
		decision: Dictionary,
		input_receipt: Dictionary
	) -> Dictionary:
	## Canonical v3 derivation shared conceptually with the Web reporter.
	## Nothing in this result trusts caller-authored feedback/outcome flags.
	var post_observations := _post_observations(observation_samples, observation_after)
	var new_cues := _new_public_cues(observation_before, post_observations)
	var removed_cues := _removed_public_cues(observation_before, post_observations)
	var moved_subjects := _visible_party_body_movement(
		observation_before, post_observations)
	var presentation_delta := _public_presentation_delta(
		observation_before, post_observations, new_cues, removed_cues)
	var visible_change := bool(presentation_delta.get("observed", false))
	var verb := str(decision.get("verb", "")).to_lower()
	var receipt_status := str(input_receipt.get("status", ""))
	var passive_no_delta := verb == "wait" and not visible_change
	var interaction_result := _derived_interaction_result(
		observation_before, post_observations, decision) if verb == "interact" else {}
	var movement_result := _derived_movement_result(
		observation_before, post_observations, decision) \
		if verb in ["move", "rally"] else {}
	var causal_moved_subjects: Array[String] = moved_subjects.duplicate()
	if verb in ["move", "rally"] and not movement_result.is_empty() \
			and not bool(movement_result.get("accepted", false)):
		# Party-body pixels are camera-relative presentation. Once the exact new
		# command lineage says REFUSED, that drift cannot truthfully be attributed
		# to this action (the production receipt separately proves zero events).
		causal_moved_subjects.clear()
	var status := "observed" if passive_no_delta else receipt_status
	if verb == "interact":
		match str(interaction_result.get("result", "")):
			"success": status = "accepted"
			"rejected": status = "refused"
			_: status = "unproven"
	elif verb in ["move", "rally"]:
		if movement_result.is_empty():
			status = "unproven"
		else:
			status = "accepted" if bool(movement_result.get("accepted", false)) \
				else "refused"
	var accepted := status == "accepted" and not passive_no_delta
	var world_causal_evidence := not new_cues.is_empty() or not moved_subjects.is_empty()
	if verb == "interact":
		world_causal_evidence = not interaction_result.is_empty()
	elif verb in ["move", "rally"]:
		# Screen-relative body drift and generic cues remain useful description,
		# but cannot attest which shipped command moved which roster to which target.
		world_causal_evidence = not movement_result.is_empty()
	elif verb in ["camera_pan", "camera_recenter", "camera_rotate", "camera_zoom"]:
		# Camera-relative body drift is presentation evidence for the recovery input,
		# never evidence that the world or a gameplay objective changed.
		world_causal_evidence = false
	elif verb == "hover":
		# Hover feedback is presentation evidence for a human pointer gesture, never
		# evidence that the world or a gameplay objective changed.
		world_causal_evidence = false
	return json_safe({
		"feedback": {
			"player_observable": visible_change,
			"cues": new_cues,
			"removed_cues": removed_cues,
			"presentation_delta": presentation_delta,
			"party_body_movement": {
				"observed": not moved_subjects.is_empty(),
				"subjects": moved_subjects,
				"classification": "screen_space_presentation_only",
			},
			"movement_result": movement_result,
		},
		"outcome": {
			"status": status,
			"accepted": accepted,
			"visible_change": visible_change,
			"cue_count": new_cues.size(),
			"moved_subjects": causal_moved_subjects,
			"interaction_result": interaction_result,
			"movement_result": movement_result,
			"passive_no_delta": passive_no_delta,
			"world_causal_evidence": world_causal_evidence,
		},
	}) as Dictionary


static func derive_persona_goal(run: Dictionary, decisions: Array) -> Dictionary:
	if str(run.get("fragment_id", "")) != "basin_fill_proof":
		return {"reached": false, "evidence": {
			"kind": "unsupported_fragment", "fragment_id": str(run.get("fragment_id", "")),
		}}
	match str(run.get("persona", "")):
		"eazy_speezy":
			return _derive_eazy_basin_goal(decisions)
		"dean_takahashi":
			return _derive_dean_basin_goal(decisions)
	return {"reached": false, "evidence": {
		"kind": "unsupported_persona", "persona": str(run.get("persona", "")),
	}}


static func _infer_world_change(decision: Dictionary) -> bool:
	var verb := str(decision.get("verb", "")).to_lower()
	if verb in KNOWN_WORLD_CHANGING_VERBS:
		return true
	if verb in KNOWN_PASSIVE_OR_PRESENTATION_VERBS:
		return false
	# Unknown actions fail closed.  A caller cannot make an unrecognized verb
	# promotable by attaching world_change=false.
	return true


static func _infer_group_action(decision: Dictionary) -> bool:
	var verb := str(decision.get("verb", "")).to_lower()
	var intended_count := (decision.get("intended_subjects", []) as Array).size() \
		if decision.get("intended_subjects", null) is Array else 0
	return verb == "rally" or (_infer_world_change(decision) and intended_count > 1)


static func _post_observations(samples: Array, observation_after: Dictionary) -> Array:
	var result: Array = deduplicate_observations(samples)
	var after_signature := canonical_hash(observation_after)
	for existing in result:
		if canonical_hash(existing) == after_signature:
			return result
	result.append(json_safe(observation_after))
	return result


static func _observation_cues(observation: Variant) -> Array:
	if not (observation is Dictionary):
		return []
	var state: Variant = (observation as Dictionary).get("state", null)
	if not (state is Dictionary) or not ((state as Dictionary).get("cues", null) is Array):
		return []
	return (state as Dictionary).get("cues", []) as Array


static func _new_public_cues(observation_before: Dictionary,
		post_observations: Array) -> Array:
	var before := {}
	for cue in _observation_cues(observation_before):
		if cue is Dictionary and str((cue as Dictionary).get("kind", "")) != "party_body":
			before[canonical_json(cue)] = true
	var seen := {}
	var result: Array = []
	for observation in post_observations:
		for cue in _observation_cues(observation):
			if not (cue is Dictionary) \
					or str((cue as Dictionary).get("kind", "")) == "party_body" \
					or not bool((cue as Dictionary).get("visible", false)):
				continue
			var signature := canonical_json(cue)
			if before.has(signature) or seen.has(signature):
				continue
			seen[signature] = true
			result.append(json_safe(cue))
	return result


static func _removed_public_cues(observation_before: Dictionary,
		post_observations: Array) -> Array:
	var final_observation: Variant = post_observations.back() \
		if not post_observations.is_empty() else {}
	var final_signatures := {}
	for cue in _observation_cues(final_observation):
		if cue is Dictionary and str((cue as Dictionary).get("kind", "")) != "party_body" \
				and bool((cue as Dictionary).get("visible", false)):
			final_signatures[canonical_json(cue)] = true
	var seen := {}
	var result: Array = []
	for cue in _observation_cues(observation_before):
		if not (cue is Dictionary) \
				or str((cue as Dictionary).get("kind", "")) == "party_body" \
				or not bool((cue as Dictionary).get("visible", false)):
			continue
		var signature := canonical_json(cue)
		if final_signatures.has(signature) or seen.has(signature):
			continue
		seen[signature] = true
		result.append(json_safe(cue))
	return result


static func _public_presentation_delta(observation_before: Dictionary,
		post_observations: Array, added_cues: Array, removed_cues: Array) -> Dictionary:
	var changed := {}
	var before_state := observation_before.get("state", {}) as Dictionary
	for observation_value in post_observations:
		if not (observation_value is Dictionary):
			continue
		var state_value: Variant = (observation_value as Dictionary).get("state", null)
		if not (state_value is Dictionary):
			continue
		var state := state_value as Dictionary
		for field in OBSERVATION_STATE_KEYS:
			if not canonical_equal(before_state.get(field), state.get(field)):
				changed[field] = true
	var changed_fields: Array[String] = []
	for field in changed.keys():
		changed_fields.append(str(field))
	changed_fields.sort()
	return {
		"observed": not changed_fields.is_empty(),
		"changed_fields": changed_fields,
		"added_cue_count": added_cues.size(),
		"removed_cue_count": removed_cues.size(),
	}


static func _party_body_screen_index(observation: Variant) -> Dictionary:
	var result := {}
	for cue in _observation_cues(observation):
		if not (cue is Dictionary) \
				or str((cue as Dictionary).get("kind", "")) != "party_body" \
				or not bool((cue as Dictionary).get("visible", false)):
			continue
		var token := str((cue as Dictionary).get("source_token", ""))
		var screen: Variant = (cue as Dictionary).get("screen", null)
		if token != "" and _finite_screen(screen):
			result[token] = json_safe(screen)
	return result


static func _visible_party_body_movement(observation_before: Dictionary,
		post_observations: Array) -> Array[String]:
	var before := _party_body_screen_index(observation_before)
	var moved := {}
	for observation in post_observations:
		var current := _party_body_screen_index(observation)
		for token_value in before.keys():
			var token := str(token_value)
			if current.has(token) and not canonical_equal(current[token], before[token]):
				moved[token] = true
	var result: Array[String] = []
	for token in moved.keys():
		result.append(str(token))
	result.sort()
	return result


static func _finite_screen(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 2:
		return false
	for coordinate in value as Array:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	return true


static func _derived_interaction_result(observation_before: Dictionary,
		post_observations: Array, decision: Dictionary) -> Dictionary:
	var target_value: Variant = decision.get("target", null)
	var target_token := str((target_value as Dictionary).get("token", "")) \
		if target_value is Dictionary else ""
	if target_token == "":
		return {}
	var before_serial := _highest_visible_interaction_result_serial(
		observation_before, target_token)
	var newest := {}
	for observation in post_observations:
		for cue_value in _observation_cues(observation):
			if not (cue_value is Dictionary):
				continue
			var cue := cue_value as Dictionary
			if str(cue.get("kind", "")) != "interaction_result" \
					or str(cue.get("source_token", "")) != target_token \
					or not bool(cue.get("visible", false)) \
					or str(cue.get("result", "")) not in ["success", "rejected"]:
				continue
			var serial_value: Variant = cue.get("presentation_serial", null)
			if not _positive_integral_number(serial_value) \
					or int(serial_value) <= before_serial \
					or int(serial_value) <= int(newest.get("presentation_serial", 0)):
				continue
			newest = {
				"source_token": target_token,
				"presentation_serial": int(serial_value),
				"result": str(cue.get("result", "")),
				"visible": true,
			}
	return newest


static func _derived_movement_result(observation_before: Dictionary,
		post_observations: Array, decision: Dictionary) -> Dictionary:
	var target_value: Variant = decision.get("target", null)
	var target_token := str((target_value as Dictionary).get("token", "")) \
		if target_value is Dictionary else ""
	if target_token == "":
		return {}
	var before_serial := _highest_visible_movement_result_serial(
		observation_before, "")
	var lineages := {}
	for observation_index in range(post_observations.size()):
		var observation_value: Variant = post_observations[observation_index]
		if not (observation_value is Dictionary):
			continue
		var capture_serial := int((observation_value as Dictionary).get(
			"capture_serial", 0))
		for cue_value in _observation_cues(observation_value):
			if not (cue_value is Dictionary):
				continue
			var cue := cue_value as Dictionary
			if str(cue.get("kind", "")) != "movement_result" \
					or not bool(cue.get("visible", false)) \
					or not _positive_integral_number(cue.get(
						"presentation_serial", null)) \
					or int(cue.get("presentation_serial", 0)) <= before_serial:
				continue
			var serial := int(cue.get("presentation_serial", 0))
			var cue_target_token := str(cue.get("target_token", ""))
			var lineage: Dictionary = lineages.get(serial, {
				"target_token": cue_target_token,
				"subjects": [],
				"presentation_serial": serial,
				"phases": [],
				"phase_capture_serials": {},
				"accepted": bool(cue.get("accepted", false)),
				"reason": "",
				"visible": true,
				"subjects_consistent": true,
				"accepted_consistent": true,
				"target_consistent": true,
				"phase_order_valid": true,
				"last_phase_rank": -1,
			})
			if str(lineage.get("target_token", "")) != cue_target_token:
				lineage["target_consistent"] = false
			var subjects: Array[String] = []
			for subject_value in cue.get("subjects", []):
				subjects.append(str(subject_value))
			subjects.sort()
			if (lineage.get("subjects", []) as Array).is_empty():
				lineage["subjects"] = subjects
			elif not canonical_equal(lineage.get("subjects", []), subjects):
				lineage["subjects_consistent"] = false
			if bool(lineage.get("accepted", false)) != bool(cue.get("accepted", false)):
				lineage["accepted_consistent"] = false
			var phase := str(cue.get("phase", "")).to_lower()
			var phase_rank := {"accepted": 0, "progress": 1, "arrival": 2,
				"interrupted": 2, "refused": 0}.get(phase, -1) as int
			var last_phase_rank := int(lineage.get("last_phase_rank", -1))
			if phase_rank >= 0:
				if last_phase_rank >= 0 and (phase_rank < last_phase_rank \
						or phase_rank > last_phase_rank + 1):
					lineage["phase_order_valid"] = false
				lineage["last_phase_rank"] = maxi(last_phase_rank, phase_rank)
			if phase != "" and not (lineage.get("phases", []) as Array).has(phase):
				(lineage["phases"] as Array).append(phase)
				(lineage["phase_capture_serials"] as Dictionary)[phase] = capture_serial
			elif phase in ["arrival", "interrupted"]:
				# Terminal movement phases remain visibly presented for a short
				# acknowledgement window. Preserve the latest capture so the fresh
				# terminal observation, not merely an earlier sample, proves the result.
				(lineage["phase_capture_serials"] as Dictionary)[phase] = capture_serial
			var reason := str(cue.get("reason", "")).strip_edges()
			if reason != "":
				lineage["reason"] = reason
			lineage["last_observation_index"] = observation_index
			lineages[serial] = lineage
	if lineages.is_empty():
		return {}
	var serials: Array[int] = []
	for serial_value in lineages.keys():
		serials.append(int(serial_value))
	serials.sort()
	var result := (lineages[serials[0]] as Dictionary).duplicate(true)
	result["new_serial_count"] = serials.size()
	return json_safe(result) as Dictionary


static func _interaction_target_result_reasons(
		observation_before: Dictionary,
		observation_after: Dictionary,
		observation_samples: Array,
		decision: Dictionary,
		receipt: Dictionary,
		derived_outcome: Dictionary
	) -> Array[String]:
	var reasons: Array[String] = []
	var target_value: Variant = decision.get("target", null)
	var target_token := str((target_value as Dictionary).get("token", "")) \
		if target_value is Dictionary else ""
	if target_token == "":
		reasons.append("interaction_target_token_missing")
		return reasons
	if not _visible_affordance_token(observation_before, target_token):
		reasons.append("interaction_target_not_visible_before")
	var result_value: Variant = derived_outcome.get("interaction_result", null)
	if not (result_value is Dictionary) or (result_value as Dictionary).is_empty():
		var before_serial := _highest_visible_interaction_result_serial(
			observation_before, target_token)
		var saw_stale_exact := false
		var saw_other_target := false
		var saw_invalid_exact := false
		for observation in _post_observations(observation_samples, observation_after):
			for cue_value in _observation_cues(observation):
				if not (cue_value is Dictionary):
					continue
				var cue := cue_value as Dictionary
				if str(cue.get("kind", "")) != "interaction_result" \
						or not bool(cue.get("visible", false)):
					continue
				if str(cue.get("source_token", "")) != target_token:
					saw_other_target = true
					continue
				if not _positive_integral_number(cue.get("presentation_serial", null)):
					saw_invalid_exact = true
				elif int(cue.get("presentation_serial", 0)) <= before_serial:
					saw_stale_exact = true
		if saw_invalid_exact:
			reasons.append("interaction_target_result_serial_invalid")
		elif saw_stale_exact:
			reasons.append("interaction_target_result_not_new")
		elif saw_other_target:
			reasons.append("interaction_target_result_source_mismatch")
		else:
			reasons.append("interaction_target_result_missing")
		return reasons
	var result := result_value as Dictionary
	if str(result.get("source_token", "")) != target_token:
		reasons.append("interaction_target_result_source_mismatch")
	if not bool(result.get("visible", false)):
		reasons.append("interaction_target_result_not_visible")
	if not _positive_integral_number(result.get("presentation_serial", null)):
		reasons.append("interaction_target_result_serial_invalid")
	elif int(result.get("presentation_serial", 0)) <= _highest_visible_interaction_result_serial(
			observation_before, target_token):
		reasons.append("interaction_target_result_not_new")
	var expected_result := "success" if str(receipt.get("status", "")) == "accepted" \
		else ("rejected" if str(receipt.get("status", "")) == "refused" else "")
	if expected_result == "" or str(result.get("result", "")) != expected_result:
		reasons.append("interaction_target_result_status_mismatch")
	return reasons


static func _movement_result_reasons(
		observation_before: Dictionary,
		observation_after: Dictionary,
		observation_samples: Array,
		decision: Dictionary,
		receipt: Dictionary,
		derived_feedback: Dictionary,
		derived_outcome: Dictionary
	) -> Array[String]:
	var reasons: Array[String] = []
	var target_value: Variant = decision.get("target", null)
	var target_token := str((target_value as Dictionary).get("token", "")) \
		if target_value is Dictionary else ""
	if target_token == "":
		return ["movement_target_token_missing"]
	reasons.append_array(movement_target_affordance_reasons(
		observation_before, decision))
	var roster := _visible_hud_roster(observation_before)
	var expected_tokens: Array[String] = []
	var verb := str(decision.get("verb", "")).to_lower()
	if verb == "rally":
		expected_tokens = (roster.get("portrait_tokens", []) as Array).duplicate()
	else:
		var token_by_subject := roster.get("token_by_subject", {}) as Dictionary
		for subject_value in decision.get("intended_subjects", []):
			var subject := str(subject_value)
			if token_by_subject.has(subject):
				expected_tokens.append(str(token_by_subject[subject]))
		expected_tokens.sort()
	var result_value: Variant = derived_outcome.get("movement_result", null)
	if not (result_value is Dictionary) or (result_value as Dictionary).is_empty():
		var before_serial := _highest_visible_movement_result_serial(
			observation_before, target_token)
		var saw_stale_exact := false
		var saw_wrong_target := false
		var saw_invalid_serial := false
		for observation in _post_observations(observation_samples, observation_after):
			for cue_value in _observation_cues(observation):
				if not (cue_value is Dictionary):
					continue
				var cue := cue_value as Dictionary
				if str(cue.get("kind", "")) != "movement_result" \
						or not bool(cue.get("visible", false)):
					continue
				if str(cue.get("target_token", "")) != target_token:
					saw_wrong_target = true
					continue
				if not _positive_integral_number(cue.get("presentation_serial", null)):
					saw_invalid_serial = true
				elif int(cue.get("presentation_serial", 0)) <= before_serial:
					saw_stale_exact = true
		if saw_invalid_serial:
			reasons.append("movement_result_serial_invalid")
		elif saw_stale_exact:
			reasons.append("movement_result_not_new")
		elif saw_wrong_target:
			reasons.append("movement_result_target_mismatch")
		else:
			reasons.append("movement_result_missing")
		return reasons
	var result := result_value as Dictionary
	if int(result.get("new_serial_count", 0)) != 1:
		reasons.append("movement_result_multiple_new_serials")
	if not bool(result.get("subjects_consistent", false)):
		reasons.append("movement_result_subjects_changed_within_lineage")
	if not bool(result.get("accepted_consistent", false)):
		reasons.append("movement_result_acceptance_changed_within_lineage")
	if not bool(result.get("target_consistent", false)):
		reasons.append("movement_result_target_changed_within_lineage")
	if not bool(result.get("phase_order_valid", false)):
		reasons.append("movement_result_phase_regression_or_skip")
	if str(result.get("target_token", "")) != target_token:
		reasons.append("movement_result_target_mismatch")
	if not _same_unique_string_members(
			result.get("subjects", []) as Array, expected_tokens):
		reasons.append("movement_result_subject_tokens_do_not_match_intent")
	var receipt_accepted := str(receipt.get("status", "")) == "accepted"
	if bool(result.get("accepted", false)) != receipt_accepted:
		reasons.append("movement_result_status_mismatch")
	var phases := result.get("phases", []) as Array
	var phase_serials := result.get("phase_capture_serials", {}) as Dictionary
	if receipt_accepted:
		var terminal_phase := ""
		if canonical_equal(phases, ["accepted", "progress", "arrival"]):
			terminal_phase = "arrival"
		elif canonical_equal(phases, ["accepted", "progress", "interrupted"]):
			terminal_phase = "interrupted"
		if terminal_phase == "":
			reasons.append("movement_result_phase_sequence_invalid")
		else:
			var accepted_serial := int(phase_serials.get("accepted", 0))
			var progress_serial := int(phase_serials.get("progress", 0))
			var terminal_serial := int(phase_serials.get(terminal_phase, 0))
			if not (accepted_serial < progress_serial and progress_serial < terminal_serial):
				reasons.append("movement_result_phase_order_invalid")
			var sample_serials := {}
			for sample_value in observation_samples:
				if sample_value is Dictionary:
					sample_serials[int((sample_value as Dictionary).get(
						"capture_serial", 0))] = true
			if not sample_serials.has(progress_serial):
				reasons.append("accepted_movement_progress_sample_missing")
			if terminal_serial != int(observation_after.get("capture_serial", 0)):
				reasons.append("accepted_movement_terminal_arrival_missing" \
					if terminal_phase == "arrival" \
					else "accepted_movement_terminal_interruption_missing")
		var result_reason := str(result.get("reason", "")).strip_edges()
		if terminal_phase == "arrival" and result_reason != "":
			reasons.append("accepted_movement_result_has_refusal_reason")
		elif terminal_phase == "interrupted" and result_reason == "":
			reasons.append("interrupted_movement_visible_reason_missing")
	else:
		if not canonical_equal(phases, ["refused"]):
			reasons.append("movement_refusal_phase_invalid")
		if str(result.get("reason", "")).strip_edges() == "":
			reasons.append("movement_refusal_visible_reason_missing")
		if int(receipt.get("production_event_count", -1)) != 0:
			reasons.append("movement_refusal_production_event_count_not_zero")
	# This exact result, not generic new cues or screen-space body drift, is the
	# mechanically bound movement feedback exposed to the policy layer.
	if not canonical_equal(derived_feedback.get("movement_result", {}), result):
		reasons.append("movement_feedback_lineage_mismatch")
	return reasons


static func movement_target_affordance_reasons(
		observation_before: Dictionary, decision: Dictionary) -> Array[String]:
	var target_value: Variant = decision.get("target", null)
	var target_token := str((target_value as Dictionary).get("token", "")) \
		if target_value is Dictionary else ""
	if target_token == "":
		return ["movement_target_token_missing"]
	var target_affordance := _visible_affordance(
		observation_before, target_token)
	var kind := str(target_affordance.get("kind", ""))
	var verb := str(decision.get("verb", "")).to_lower()
	# A Move is playable only on a visible move affordance. Rally is a right-hold
	# gesture and can legitimately use either a visible ground point or a visible
	# interaction surface as its destination; no other affordance kind is accepted.
	if kind == "move" or (verb == "rally" and kind == "interact"):
		return []
	return ["movement_target_not_visible_move_affordance_before"]


static func _body_tokens_for_portraits(observation: Dictionary,
		portrait_tokens: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for cue_value in _observation_cues(observation):
		if not (cue_value is Dictionary):
			continue
		var cue := cue_value as Dictionary
		if str(cue.get("kind", "")) != "party_body" \
				or not bool(cue.get("visible", false)) \
				or not portrait_tokens.has(str(cue.get("binding", ""))):
			continue
		var body_token := str(cue.get("source_token", ""))
		if body_token != "" and not result.has(body_token):
			result.append(body_token)
	result.sort()
	return result


static func _full_roster_action_reasons(observation_before: Dictionary,
		decision: Dictionary, receipt: Dictionary, derived_outcome: Dictionary,
		require_movement_tokens: bool) -> Array[String]:
	var reasons: Array[String] = []
	var roster := _visible_hud_roster(observation_before)
	if not bool(roster.get("valid", false)):
		reasons.append("visible_hud_roster_not_unique_complete")
		return reasons
	var expected_subjects := roster.get("subject_ids", []) as Array
	if not _same_unique_string_members(
			decision.get("intended_subjects", []) as Array, expected_subjects):
		reasons.append("decision_subjects_do_not_equal_full_visible_roster")
	var intended_members: Array = receipt.get("intended_members", []) \
		if receipt.get("intended_members", null) is Array else []
	if not _same_unique_string_members(intended_members, expected_subjects):
		reasons.append("receipt_members_do_not_equal_full_visible_roster")
	var member_results: Variant = receipt.get("member_results", null)
	if not (member_results is Dictionary) \
			or not _same_unique_string_members(
				(member_results as Dictionary).keys(), expected_subjects):
		reasons.append("receipt_result_keys_do_not_equal_full_visible_roster")
	elif str(receipt.get("status", "")) in ["accepted", "refused"]:
		var expected_result := str(receipt.get("status", ""))
		for subject in expected_subjects:
			if str((member_results as Dictionary).get(subject, "")) != expected_result:
				reasons.append("receipt_result_not_atomic_for_full_roster:%s" % subject)
	if require_movement_tokens:
		var result := derived_outcome.get("movement_result", {}) as Dictionary
		if not _same_unique_string_members(result.get("subjects", []) as Array,
				roster.get("portrait_tokens", []) as Array):
			reasons.append("movement_feedback_tokens_do_not_equal_full_visible_roster")
	return reasons


static func _derive_eazy_basin_goal(decisions: Array) -> Dictionary:
	for record_value in decisions:
		if not (record_value is Dictionary):
			continue
		var record := record_value as Dictionary
		var decision := record.get("decision", {}) as Dictionary
		if str(decision.get("verb", "")).to_lower() != "interact":
			continue
		var target_value: Variant = decision.get("target", null)
		var target_token := str((target_value as Dictionary).get("token", "")) \
			if target_value is Dictionary else ""
		var before := record.get("observation_before", {}) as Dictionary
		var target_affordance := _visible_affordance(before, target_token)
		var visible_verb := str(target_affordance.get("verb", "")).to_upper()
		if target_token == "" or not (visible_verb.contains("REST") \
				or visible_verb.contains("SHELTER")):
			continue
		var outcome := record.get("outcome", {}) as Dictionary
		var interaction_result := outcome.get("interaction_result", {}) as Dictionary
		if not bool(outcome.get("accepted", false)) \
				or str(interaction_result.get("source_token", "")) != target_token \
				or str(interaction_result.get("result", "")) != "success" \
				or not bool(interaction_result.get("visible", false)) \
				or not _positive_integral_number(interaction_result.get(
					"presentation_serial", null)):
			continue
		var samples: Array = record.get("observation_samples", []) \
			if record.get("observation_samples", null) is Array else []
		var after := record.get("observation_after", {}) as Dictionary
		for observation in _post_observations(samples, after):
			for cue_value in _observation_cues(observation):
				if not (cue_value is Dictionary):
					continue
				var cue := cue_value as Dictionary
				if not bool(cue.get("visible", false)):
					continue
				var cue_text := _cue_search_text(cue)
				if not (cue_text.contains("SECURED THE SHELTER") \
						or cue_text.contains("FULL PARTY SETTLED")):
					continue
				return {"reached": true, "evidence": {
					"kind": "eazy_basin_rest_and_full_party_settled_v1",
					"decision_index": int(record.get("decision_index", -1)),
					"source_token": target_token,
					"presentation_serial": int(interaction_result.get(
						"presentation_serial", 0)),
					"visible_verb": str(target_affordance.get("verb", "")),
					"settled_cue": json_safe(cue),
				}}
	return {"reached": false, "evidence": {
		"kind": "eazy_basin_goal_unproven_v1",
		"required": "exact REST/SHELTER success and same-action visible full-party secured/settled cue",
	}}


static func _derive_dean_basin_goal(decisions: Array) -> Dictionary:
	var lineages := {}
	var warnings: Array = []
	var observation_index := 0
	for record_value in decisions:
		if not (record_value is Dictionary):
			continue
		var record := record_value as Dictionary
		var observations: Array = []
		observations.append(record.get("observation_before", {}))
		for sample in record.get("observation_samples", []):
			observations.append(sample)
		observations.append(record.get("observation_after", {}))
		for observation in observations:
			var party_tokens := _visible_party_tokens(observation)
			for cue_value in _observation_cues(observation):
				if not (cue_value is Dictionary):
					continue
				var cue := cue_value as Dictionary
				var warning_text := _cue_search_text(cue)
				if bool(cue.get("visible", false)) \
						and str(cue.get("kind", "")) in ["hud", "consequence"] \
						and (warning_text.contains("BASIN RISING") \
							or warning_text.contains("MISSED RISE")):
					var warning_roster := _visible_roster_tokens(observation)
					if not warning_roster.is_empty():
						warnings.append({
							"observation_index": observation_index,
							"cue": json_safe(cue),
							"roster": warning_roster,
						})
				var source_token := str(cue.get("source_token", ""))
				var phase := str(cue.get("phase", "")).to_lower()
				var label := str(cue.get("label", cue.get("text", ""))).strip_edges()
				var destination_label := str(cue.get("destination_label", "")).strip_edges()
				if str(cue.get("kind", "")) != "consequence" \
						or not bool(cue.get("visible", false)) \
						or source_token == "" or not party_tokens.has(source_token) \
						or not label.to_upper().contains("SWEPT") \
						or destination_label == "" \
						or phase not in ["active", "arrival"]:
					continue
				var lineage_key := "%s|%s|%s" % [
					source_token, label.to_upper(), destination_label.to_upper(),
				]
				var lineage: Dictionary = lineages.get(lineage_key, {
					"source_token": source_token,
					"label": label,
					"destination_label": destination_label,
					"phase_indices": {},
				})
				var phase_indices := lineage.get("phase_indices", {}) as Dictionary
				if not phase_indices.has(phase):
					phase_indices[phase] = observation_index
				lineage["phase_indices"] = phase_indices
				lineages[lineage_key] = lineage
			observation_index += 1
	var lineage_suffixes := {}
	for lineage_value in lineages.values():
		var lineage := lineage_value as Dictionary
		var suffix := "%s|%s" % [
			str(lineage.get("label", "")).to_upper(),
			str(lineage.get("destination_label", "")).to_upper(),
		]
		lineage_suffixes[suffix] = true
	var sorted_suffixes: Array[String] = []
	for suffix in lineage_suffixes.keys():
		sorted_suffixes.append(str(suffix))
	sorted_suffixes.sort()
	for warning_value in warnings:
		var warning := warning_value as Dictionary
		var warning_index := int(warning.get("observation_index", -1))
		var roster: Array = warning.get("roster", [])
		for suffix in sorted_suffixes:
			var per_token: Array = []
			var full_roster_proven := not roster.is_empty()
			for token_value in roster:
				var token := str(token_value)
				var lineage_key := "%s|%s" % [token, suffix]
				if not lineages.has(lineage_key):
					full_roster_proven = false
					break
				var lineage := lineages[lineage_key] as Dictionary
				var phase_indices := lineage.get("phase_indices", {}) as Dictionary
				var active_index := int(phase_indices.get("active", -1))
				var arrival_index := int(phase_indices.get("arrival", -1))
				if active_index <= warning_index or arrival_index <= active_index:
					full_roster_proven = false
					break
				per_token.append({
					"source_token": token,
					"active_observation_index": active_index,
					"arrival_observation_index": arrival_index,
				})
			if full_roster_proven:
				var suffix_parts := suffix.split("|", true, 1)
				return {"reached": true, "evidence": {
					"kind": "dean_basin_full_roster_warning_swept_active_arrival_v1",
					"warning_observation_index": warning_index,
					"warning_cue": warning.get("cue", {}).duplicate(true),
					"roster": roster.duplicate(),
					"label": str(suffix_parts[0]) if suffix_parts.size() > 0 else "",
					"destination_label": str(suffix_parts[1]) if suffix_parts.size() > 1 else "",
					"per_token_phases": per_token,
				}}
	return {"reached": false, "evidence": {
		"kind": "dean_basin_goal_unproven_v1",
		"required": "visible Basin-rise warning followed by same-lineage SWEPT active and arrival for the full warning roster",
	}}


static func _visible_party_tokens(observation: Variant) -> Dictionary:
	var tokens := {}
	if not (observation is Dictionary):
		return tokens
	var state_value: Variant = (observation as Dictionary).get("state", null)
	if state_value is Dictionary:
		var hud_value: Variant = (state_value as Dictionary).get("hud", null)
		if hud_value is Dictionary:
			for portrait_value in (hud_value as Dictionary).get("portraits", []):
				if portrait_value is Dictionary and bool((portrait_value as Dictionary).get(
						"visible", false)):
					var portrait_token := str((portrait_value as Dictionary).get("token", ""))
					if portrait_token != "":
						tokens[portrait_token] = true
	for cue_value in _observation_cues(observation):
		if not (cue_value is Dictionary) \
				or str((cue_value as Dictionary).get("kind", "")) != "party_body" \
				or not bool((cue_value as Dictionary).get("visible", false)):
			continue
		for key in ["source_token", "binding"]:
			var token := str((cue_value as Dictionary).get(key, ""))
			if token != "":
				tokens[token] = true
	return tokens


static func _visible_roster_tokens(observation: Variant) -> Array[String]:
	var roster_tokens: Array[String] = []
	var portrait_token_set := {}
	if observation is Dictionary:
		var state_value: Variant = (observation as Dictionary).get("state", null)
		if state_value is Dictionary:
			var hud_value: Variant = (state_value as Dictionary).get("hud", null)
			if hud_value is Dictionary:
				for portrait_value in (hud_value as Dictionary).get("portraits", []):
					if portrait_value is Dictionary \
							and bool((portrait_value as Dictionary).get("visible", false)):
						var token := str((portrait_value as Dictionary).get("token", ""))
						if token != "" and not roster_tokens.has(token):
							portrait_token_set[token] = true
							roster_tokens.append(token)
	# Consequence projection uses a visible portrait token when that binding is
	# present, and falls back to a body token only for an unbound body.
	for cue_value in _observation_cues(observation):
		if cue_value is Dictionary \
				and str((cue_value as Dictionary).get("kind", "")) == "party_body" \
				and bool((cue_value as Dictionary).get("visible", false)):
			var body_token := str((cue_value as Dictionary).get("source_token", ""))
			var binding := str((cue_value as Dictionary).get("binding", ""))
			if body_token != "" and (binding == "" or not portrait_token_set.has(binding)) \
					and not roster_tokens.has(body_token):
				roster_tokens.append(body_token)
	roster_tokens.sort()
	return roster_tokens


static func _visible_hud_roster(observation: Dictionary) -> Dictionary:
	var subject_ids: Array[String] = []
	var portrait_tokens: Array[String] = []
	var token_by_subject := {}
	var reasons: Array[String] = []
	var state_value: Variant = observation.get("state", null)
	if not (state_value is Dictionary):
		return {"valid": false, "subject_ids": subject_ids,
			"portrait_tokens": portrait_tokens, "token_by_subject": token_by_subject,
			"reasons": ["portraits_missing"]}
	var hud_value: Variant = (state_value as Dictionary).get("hud", null)
	if not (hud_value is Dictionary) \
			or not ((hud_value as Dictionary).get("portraits", null) is Array):
		return {"valid": false, "subject_ids": subject_ids,
			"portrait_tokens": portrait_tokens, "token_by_subject": token_by_subject,
			"reasons": ["portraits_missing"]}
	var seen_subjects := {}
	var seen_tokens := {}
	var portrait_index := 0
	for portrait_value in (hud_value as Dictionary).get("portraits", []):
		if not (portrait_value is Dictionary):
			portrait_index += 1
			continue
		var portrait := portrait_value as Dictionary
		if not (portrait.get("visible", null) is bool):
			reasons.append("portraits.%d.visible_must_be_explicit" % portrait_index)
		if not bool(portrait.get("visible", false)):
			portrait_index += 1
			continue
		var subject_id := _normalize_subject_label(str(portrait.get("label", "")))
		var token := str(portrait.get("token", "")).strip_edges()
		if subject_id == "":
			reasons.append("portraits.%d.visible_label_missing" % portrait_index)
		elif seen_subjects.has(subject_id):
			reasons.append("visible_label_duplicate:%s" % subject_id)
		if token == "":
			reasons.append("portraits.%d.visible_token_missing" % portrait_index)
		elif seen_tokens.has(token):
			reasons.append("visible_token_duplicate:%s" % token)
		if subject_id != "" and token != "" \
				and not seen_subjects.has(subject_id) and not seen_tokens.has(token):
			seen_subjects[subject_id] = true
			seen_tokens[token] = true
			subject_ids.append(subject_id)
			portrait_tokens.append(token)
			token_by_subject[subject_id] = token
		portrait_index += 1
	subject_ids.sort()
	portrait_tokens.sort()
	reasons.sort()
	return {
		"valid": reasons.is_empty() and not subject_ids.is_empty(),
		"subject_ids": subject_ids,
		"portrait_tokens": portrait_tokens,
		"token_by_subject": token_by_subject,
		"reasons": reasons,
	}


static func _normalize_subject_label(value: String) -> String:
	return value.strip_edges().to_snake_case().to_lower()


static func _visible_affordance(observation: Dictionary, token: String) -> Dictionary:
	var state_value: Variant = observation.get("state", null)
	if not (state_value is Dictionary):
		return {}
	for affordance_value in (state_value as Dictionary).get("affordances", []):
		if affordance_value is Dictionary \
				and str((affordance_value as Dictionary).get("token", "")) == token:
			return affordance_value as Dictionary
	return {}


static func _visible_affordance_token(observation: Dictionary, token: String) -> bool:
	return token != "" and not _visible_affordance(observation, token).is_empty()


static func _cue_search_text(cue: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["text", "state", "result", "label", "destination_label"]:
		var part := str(cue.get(key, "")).strip_edges()
		if part != "":
			parts.append(part.to_upper())
	return " ".join(parts)


static func _positive_integral_number(value: Variant) -> bool:
	return (value is int or value is float) \
		and is_finite(float(value)) \
		and float(value) > 0.0 \
		and float(value) == floorf(float(value))


static func _nonnegative_integral_number(value: Variant) -> bool:
	return (value is int or value is float) \
		and is_finite(float(value)) \
		and float(value) >= 0.0 \
		and float(value) == floorf(float(value))


static func _highest_visible_interaction_result_serial(
		observation: Dictionary,
		target_token: String
	) -> int:
	if target_token == "":
		return 0
	var state_value: Variant = observation.get("state", null)
	if not (state_value is Dictionary):
		return 0
	var highest := 0
	for cue_value in (state_value as Dictionary).get("cues", []):
		if not (cue_value is Dictionary):
			continue
		var cue := cue_value as Dictionary
		if str(cue.get("kind", "")) != "interaction_result" \
				or str(cue.get("source_token", "")) != target_token \
				or not bool(cue.get("visible", false)) \
				or str(cue.get("result", "")) not in ["success", "rejected"]:
			continue
		var serial_value: Variant = cue.get("presentation_serial", null)
		if not (serial_value is int or serial_value is float) \
				or not is_finite(float(serial_value)) \
				or float(serial_value) <= 0.0 \
				or float(serial_value) != floorf(float(serial_value)):
			continue
		highest = maxi(highest, int(serial_value))
	return highest


static func _highest_visible_movement_result_serial(
		observation: Dictionary, target_token: String) -> int:
	var highest := 0
	for cue_value in _observation_cues(observation):
		if not (cue_value is Dictionary):
			continue
		var cue := cue_value as Dictionary
		if str(cue.get("kind", "")) != "movement_result" \
				or (target_token != "" \
					and str(cue.get("target_token", "")) != target_token) \
				or not bool(cue.get("visible", false)) \
				or not _positive_integral_number(cue.get(
					"presentation_serial", null)):
			continue
		highest = maxi(highest, int(cue.get("presentation_serial", 0)))
	return highest


static func _validate_screen(issues: Array[String], value: Variant, path: String,
		allow_empty: bool) -> void:
	if not (value is Array):
		issues.append("%s must be a screen-coordinate array" % path)
		return
	var screen := value as Array
	if allow_empty and screen.is_empty():
		return
	if screen.size() != 2:
		issues.append("%s must contain exactly two screen coordinates" % path)
		return
	for coordinate in screen:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			issues.append("%s coordinates must be finite numbers" % path)
			return


static func shipped_input_receipt(driver_receipt: Dictionary,
		boundary := "keyboard_pointer") -> Dictionary:
	var accepted := bool(driver_receipt.get("accepted", false))
	var kind := str(driver_receipt.get("kind", ""))
	var trace_verb := "hover" if kind == "hover_pointer" else kind
	# A selected-party console may first enqueue an ordinary approach and emit its authoritative
	# Rally only on arrival. When group membership was annotated, count that one production group
	# event rather than unrelated approach bookkeeping in the same input receipt.
	var event_count := int(driver_receipt.get("rally_event_count", 0)) \
		if driver_receipt.has("rally_event_count") else maxi(0,
			int(driver_receipt.get("event_count_after", 0))
			- int(driver_receipt.get("event_count_before", 0)))
	var lifted := {
		"receipt_id": str(driver_receipt.get("id", "")),
		"boundary": boundary,
		"status": "accepted" if accepted else "refused",
		"player_reproducible": bool(driver_receipt.get("player_reproducible", false)),
		"verb": trace_verb,
		"atomic_group": bool(driver_receipt.get("atomic_group",
			kind != "rally" or int(driver_receipt.get("rally_event_count", 0)) == 1)),
		"production_event_count": event_count,
		"production_event_kinds": driver_receipt.get(
			"new_event_kinds", []).duplicate(true) \
			if driver_receipt.get("new_event_kinds", null) is Array else [],
		"input_issued": bool(driver_receipt.get("input_issued", false)),
		"input_event_count": int(driver_receipt.get("input_event_count", 0)),
		"input_sequence_before": int(driver_receipt.get(
			"input_sequence_before", -1)),
		"input_sequence_after": int(driver_receipt.get(
			"input_sequence_after", -1)),
		"input_events": driver_receipt.get("input_events", []).duplicate(true) \
			if driver_receipt.get("input_events", null) is Array else [],
		"driver_receipt": driver_receipt,
	}
	if driver_receipt.get("intended_members", null) is Array:
		lifted["intended_members"] = driver_receipt.get("intended_members", []).duplicate(true)
	if driver_receipt.get("member_results", null) is Dictionary:
		lifted["member_results"] = driver_receipt.get("member_results", {}).duplicate(true)
	return json_safe(lifted)


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(json_safe(value), "", true, true)


static func canonical_hash(value: Variant) -> String:
	# Godot's JSON parser represents every JSON number as a float. Hash the
	# parser-normalized form so an in-memory int and its on-disk 1.0 round-trip
	# to the same digest without changing the human-facing JSON representation.
	var reparsed: Variant = JSON.parse_string(canonical_json(value))
	return canonical_json(reparsed).sha256_text()


static func canonical_equal(a: Variant, b: Variant) -> bool:
	return canonical_hash(a) == canonical_hash(b)


static func json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number):
				return null
			return snappedf(number, FLOAT_QUANTUM)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2:
			var vector := value as Vector2
			return [json_safe(vector.x), json_safe(vector.y)]
		TYPE_VECTOR2I:
			var vector := value as Vector2i
			return [vector.x, vector.y]
		TYPE_VECTOR3:
			var vector := value as Vector3
			return [json_safe(vector.x), json_safe(vector.y), json_safe(vector.z)]
		TYPE_VECTOR3I:
			var vector := value as Vector3i
			return [vector.x, vector.y, vector.z]
		TYPE_VECTOR4:
			var vector := value as Vector4
			return [json_safe(vector.x), json_safe(vector.y),
				json_safe(vector.z), json_safe(vector.w)]
		TYPE_VECTOR4I:
			var vector := value as Vector4i
			return [vector.x, vector.y, vector.z, vector.w]
		TYPE_COLOR:
			var color := value as Color
			return [json_safe(color.r), json_safe(color.g),
				json_safe(color.b), json_safe(color.a)]
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var safe_array: Array = []
			for item in value:
				safe_array.append(json_safe(item))
			return safe_array
		TYPE_DICTIONARY:
			var safe_dictionary := {}
			var keys: Array[String] = []
			for raw_key in (value as Dictionary).keys():
				keys.append(str(raw_key))
			keys.sort()
			for key in keys:
				safe_dictionary[key] = json_safe((value as Dictionary).get(key))
			return safe_dictionary
		_:
			return str(value)


static func _decision_run_identity(run: Dictionary) -> Dictionary:
	return {
		"run_id": str(run.get("run_id", "")),
		"trace_id": str(run.get("trace_id", "")),
		"persona": str(run.get("persona", "")),
		"fragment_id": str(run.get("fragment_id", "")),
		"seed": run.get("seed", 0),
		"repeat_index": run.get("repeat_index", -1),
		"content_fingerprint_schema": str(run.get("content_fingerprint_schema", "")),
		"content_fingerprint": str(run.get("content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(run.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(run.get(
			"gameplay_build_fingerprint", "")),
		"execution_platform": str(run.get("execution_platform", "")),
	}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
