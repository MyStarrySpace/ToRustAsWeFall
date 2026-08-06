class_name PersonaDecisionLibrary
extends RefCounted

## Conservative persona policy distillation.
##
## This code never invents a branch from prose. A decision record must carry an
## explicit machine-readable candidate, the candidate's observation predicate
## must match the recorded player-visible state, and the trace must pass the
## shipped-input evidence contract. Exact duplicate evidence is idempotent.
## Conflicting policies are retained as rejected provenance instead of silently
## replacing an existing node. The preview-only entry point has one fail-closed
## exception: a complete current cohort may stage a schema-declared monotonic
## target-binding refinement. Canonical/in-place distillation never takes it.

const Trace := preload("res://scripts/testing/persona_decision_trace.gd")
const ContentFingerprint := preload("res://scripts/testing/content_fingerprint.gd")
const LIBRARY_SCHEMA := "persona_decision_library_v3"
const TREE_SCHEMA := "persona_policy_tree_v1"
const DEFAULT_MINIMUM_SUPPORT := 2
const PREVIEW_SUPERSESSION_ARCHIVE_SCHEMA := \
	"persona_policy_supersession_archive_v1"
# Target selectors participate in preview supersession only through this
# schema. The relation is semantic rather than node-specific: a selector may
# replace another only inside the same intent family and anchor path, and only
# when it moves from an inferred proxy to an exact currently visible token.
# Future generated selectors extend this registry without adding node/rule/hash
# exceptions to the distiller.
const TARGET_REF_PRECISION_CONTRACTS := {
	"nearest_visible_ground_to_shelter_label": {
		"intent_family": "visible_semantic_destination",
		"binding_mode": "nearest_visible_proxy",
		"precision_rank": 1,
		"anchor_path": "visible_affordance_verbs",
		"target_kind": "move",
		"proxy": true,
		"exact_current_token": false,
		"removable_path_prefixes": ["viewport_bins."],
	},
	"matching_visible_shelter_surface": {
		"intent_family": "visible_semantic_destination",
		"binding_mode": "exact_visible_surface",
		"precision_rank": 2,
		"anchor_path": "visible_affordance_verbs",
		"target_kind": "interact",
		"proxy": false,
		"exact_current_token": true,
		"removable_path_prefixes": [],
	},
	"matching_visible_interaction": {
		"intent_family": "visible_semantic_destination",
		"binding_mode": "exact_visible_surface",
		"precision_rank": 2,
		"anchor_path": "visible_affordance_verbs",
		"target_kind": "interact",
		"proxy": false,
		"exact_current_token": true,
		"removable_path_prefixes": [],
	},
}
const TARGET_BINDING_MODE_CONTRACTS := {
	"nearest_visible_proxy": {
		"proxy": true,
		"exact_current_token": false,
		"target_kind": "move",
	},
	"exact_visible_surface": {
		"proxy": false,
		"exact_current_token": true,
		"target_kind": "interact",
	},
}
const EVIDENCE_COUNT_FIELDS := [
	"support_count",
	"contradiction_count",
	"distinct_run_count",
	"distinct_fragment_count",
	"distinct_persona_count",
	"distinct_content_count",
	"distinct_gameplay_build_count",
	"distinct_support_cohort_count",
	"max_support_cohort_count",
	"distinct_trace_count",
	"inadmissible_provenance_count",
]

const CONDITION_OPERATORS := [
	"eq",
	"neq",
	"lt",
	"lte",
	"gt",
	"gte",
	"contains",
	"exists",
]


static func distill_paths(existing_library: Dictionary, trace_paths: Array,
		minimum_support := DEFAULT_MINIMUM_SUPPORT) -> Dictionary:
	var documents: Array = []
	for path_value in trace_paths:
		documents.append(Trace.read_trace(str(path_value)))
	return distill(existing_library, documents, minimum_support)


static func distill(existing_library: Dictionary, trace_documents: Array,
		minimum_support := DEFAULT_MINIMUM_SUPPORT) -> Dictionary:
	return _distill(existing_library, trace_documents, minimum_support, false)


## Preview-only policy revision path. Unlike `distill()`, this may supersede an
## existing node when a complete current cohort proves a strictly more precise
## target binding. It mutates only the migrated deep copy returned to the caller;
## canonical/in-place promotion deliberately continues through `distill()`.
static func distill_preview(existing_library: Dictionary, trace_documents: Array,
		minimum_support := DEFAULT_MINIMUM_SUPPORT) -> Dictionary:
	return _distill(existing_library, trace_documents, minimum_support, true)


## Read-only verifier seam for adversarial cohort tests. It exposes the exact
## staged support envelope, not a way to install policy: callers still have to
## pass `distill_preview()`, whose shape and ambiguity checks are authoritative.
static func inspect_preview_support_entries(trace_documents: Array) -> Array:
	var result: Array = []
	var cohort_status := _classify_invocation_cohorts(trace_documents)
	for document_value in trace_documents:
		if not (document_value is Dictionary):
			continue
		var document := document_value as Dictionary
		var run_evidence := _classify_run_evidence(document,
			cohort_status.get(_document_key(document), {}) as Dictionary)
		for record_value in document.get("decisions", []):
			if not (record_value is Dictionary):
				continue
			var record := record_value as Dictionary
			if not (record.get("learning_candidate", null) is Dictionary):
				continue
			var candidate := record.get("learning_candidate", {}) as Dictionary
			var action := candidate.get("action", {}) as Dictionary
			var policy := {
				"condition": canonicalize_predicate(candidate.get("condition")),
				"action": action.duplicate(true),
				"expected": canonicalize_predicate(candidate.get("expected")),
				"scope": str(candidate.get("scope", "global")),
				"priority": clampi(int(candidate.get("priority", 50)), 0, 100),
			}
			var derived := Trace.derive_feedback_outcome(
				record.get("observation_before", {}) as Dictionary,
				record.get("observation_after", {}) as Dictionary,
				record.get("observation_samples", []) as Array,
				record.get("decision", {}) as Dictionary,
				record.get("input_receipt", {}) as Dictionary)
			result.append({
				"record": record.duplicate(true),
				"run_evidence": run_evidence.duplicate(true),
				"candidate": candidate.duplicate(true),
				"policy": policy,
				"policy_signature": canonical_hash(policy),
				"rule": str(candidate.get("rule", "")),
				"record_hash": str(record.get("record_hash", "")),
				"persona": str((record.get("run", {}) as Dictionary).get(
					"persona", "")),
				"supported": evaluate_predicate(candidate.get("expected"),
					derived.get("outcome", {})),
			})
	result.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as Dictionary).get("record_hash", "")) < str(
			(b as Dictionary).get("record_hash", "")))
	return result


static func _distill(existing_library: Dictionary, trace_documents: Array,
		minimum_support: int, allow_preview_supersession: bool) -> Dictionary:
	var library := _migrate_library(existing_library)
	var rejected := _rejected_index(library.get("rejected_evidence", []))
	var node_index := _node_index(library.get("nodes", []))
	var pending_supersessions := {}
	var cohort_status := _classify_invocation_cohorts(trace_documents)
	for raw_document in trace_documents:
		if not (raw_document is Dictionary):
			_add_rejection(rejected, {
				"key": "invalid_trace_document:%s" % canonical_hash(raw_document),
				"reason": "trace_document_not_an_object",
			})
			continue
		var document := raw_document as Dictionary
		if not bool(document.get("ok", false)):
			_add_rejection(rejected, {
				"key": "invalid_trace:%s" % canonical_hash({
					"path": str(document.get("path", "")),
					"errors": document.get("errors", []),
				}),
				"trace_id": str((document.get("run", {}) as Dictionary).get("trace_id", "")),
				"reason": "trace_integrity_failed",
				"details": document.get("errors", []),
			})
			continue
		var run_evidence := _classify_run_evidence(document,
			cohort_status.get(_document_key(document), {}) as Dictionary)
		if not bool(run_evidence.get("eligible_for_learning", false)):
			var run := document.get("run", {}) as Dictionary
			_add_rejection(rejected, {
				"key": "ineligible_run:%s" % canonical_hash({
					"path": str(document.get("path", "")),
					"run": run,
					"summary": document.get("summary", {}),
				}),
				"trace_id": str(run.get("trace_id", "")),
				"run_id": str(run.get("run_id", "")),
				"persona": str(run.get("persona", "")),
				"fragment_id": str(run.get("fragment_id", "")),
				"reason": "run_not_learning_complete",
				"details": run_evidence.get("rejection_reasons", []),
			})
			continue
		for raw_record in document.get("decisions", []):
			if raw_record is Dictionary:
				_consume_record(library, node_index, rejected,
					raw_record as Dictionary, run_evidence,
					allow_preview_supersession, pending_supersessions)
	if allow_preview_supersession:
		_apply_preview_supersessions(library, node_index, rejected,
			pending_supersessions, maxi(2, minimum_support))
	_recompute_nodes(library, maxi(1, minimum_support))
	library["trees"] = _build_trees(library.get("nodes", []))
	var nodes: Array = library.get("nodes", [])
	nodes.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as Dictionary).get("id", "")) < str((b as Dictionary).get("id", "")))
	library["nodes"] = nodes
	var rejected_values: Array = rejected.values()
	rejected_values.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as Dictionary).get("key", "")) < str((b as Dictionary).get("key", "")))
	library["rejected_evidence"] = rejected_values
	library["distillation"] = {
		"minimum_support": maxi(1, minimum_support),
		"eligible_node_count": _eligible_node_count(nodes),
		"rejected_evidence_count": rejected_values.size(),
	}
	return Trace.json_safe(library)


static func load_library(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


static func save_library(path: String, library: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot write %s (error %d)" % [
			path, FileAccess.get_open_error()]}
	file.store_string(JSON.stringify(Trace.json_safe(library), "\t", true, true) + "\n")
	file.close()
	return {"ok": true, "path": path}


## Normalize storage aliases before a preview tool decides whether writing is
## safe. In particular, `res://...`, a project-relative path, and the matching
## absolute Windows path must compare as the same file.
static func normalized_storage_path(path: String) -> String:
	var source := path.strip_edges()
	if source == "":
		return ""
	var absolute := source
	if source.begins_with("res://") or source.begins_with("user://"):
		absolute = ProjectSettings.globalize_path(source)
	elif not source.is_absolute_path():
		absolute = ProjectSettings.globalize_path("res://").path_join(source)
	absolute = absolute.replace("\\", "/").simplify_path()
	if OS.get_name() == "Windows":
		absolute = absolute.to_lower()
	return absolute


static func validate_preview_output_path(library_path: String,
		output_path: String, canonical_library_path: String) -> Array[String]:
	var reasons: Array[String] = []
	var normalized_output := normalized_storage_path(output_path)
	var normalized_input := normalized_storage_path(library_path)
	var normalized_canonical := normalized_storage_path(canonical_library_path)
	if normalized_output == "":
		reasons.append("preview_output_path_missing")
	if normalized_output != "" and normalized_output == normalized_input:
		reasons.append("preview_output_aliases_input_library")
	if normalized_output != "" and normalized_output == normalized_canonical:
		reasons.append("preview_output_aliases_canonical_library")
	reasons.sort()
	return reasons


static func choose_action(library: Dictionary, persona: String,
		player_observation: Dictionary) -> Dictionary:
	# Executable policy is versioned evidence, not a permissive data lookup.  Direct
	# callers must present the same complete player_observation_v1 boundary used to
	# train the tree; flat state dictionaries and stale libraries are diagnostic data.
	if str(library.get("schema", "")) != LIBRARY_SCHEMA:
		return {"matched": false, "reason": "library_schema_not_current"}
	if not Trace.canonical_equal(library.get("contract", {}),
			_current_library_contract()):
		return {"matched": false, "reason": "library_contract_not_current"}
	var observation_issues := Trace.validate_player_observation(player_observation)
	if not observation_issues.is_empty():
		return {
			"matched": false,
			"reason": "player_observation_invalid",
			"details": observation_issues,
		}
	var observation_root := player_observation.get("state", {}) as Dictionary
	var trees: Variant = library.get("trees", {})
	if not (trees is Dictionary) or not (trees as Dictionary).has(persona):
		return {"matched": false, "reason": "persona_tree_unavailable"}
	var tree: Variant = (trees as Dictionary).get(persona)
	if not (tree is Dictionary) or str((tree as Dictionary).get("schema", "")) != TREE_SCHEMA:
		return {"matched": false, "reason": "persona_tree_invalid"}
	var tree_nodes: Variant = (tree as Dictionary).get("nodes", {})
	if not (tree_nodes is Dictionary):
		return {"matched": false, "reason": "persona_tree_nodes_invalid"}
	for raw_node_id in (tree as Dictionary).get("evaluation_order", []):
		var node_id := str(raw_node_id)
		var raw_node: Variant = (tree_nodes as Dictionary).get(node_id)
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		if evaluate_predicate(node.get("when"), observation_root):
			return {
				"matched": true,
				"node_id": node_id,
				"action": (node.get("choose", {}) as Dictionary).duplicate(true),
				"expected": (node.get("expect", {}) as Dictionary).duplicate(true),
				"scope": str(node.get("scope", "global")),
			}
	return {"matched": false, "reason": "no_observation_predicate_matched"}


static func evaluate_predicate(predicate: Variant, root: Variant) -> bool:
	if not (predicate is Dictionary):
		return false
	var expression := predicate as Dictionary
	if expression.has("all"):
		if not (expression["all"] is Array):
			return false
		for child in expression["all"]:
			if not evaluate_predicate(child, root):
				return false
		return true
	if expression.has("any"):
		if not (expression["any"] is Array):
			return false
		for child in expression["any"]:
			if evaluate_predicate(child, root):
				return true
		return false
	if expression.has("not"):
		return not evaluate_predicate(expression["not"], root)
	var path := str(expression.get("path", ""))
	var operator := str(expression.get("op", ""))
	if path == "" or operator not in CONDITION_OPERATORS:
		return false
	var lookup := _lookup(root, path)
	if operator == "exists":
		return bool(lookup.get("found", false)) == bool(expression.get("value", true))
	if not bool(lookup.get("found", false)):
		return false
	var actual: Variant = lookup.get("value")
	var expected: Variant = expression.get("value")
	match operator:
		"eq":
			return _equivalent(actual, expected)
		"neq":
			return not _equivalent(actual, expected)
		"contains":
			if actual is Array:
				return (actual as Array).has(expected)
			if actual is Dictionary:
				return (actual as Dictionary).has(expected)
			return str(actual).contains(str(expected))
		"lt", "lte", "gt", "gte":
			if not (actual is int or actual is float) \
					or not (expected is int or expected is float):
				return false
			var a := float(actual)
			var b := float(expected)
			match operator:
				"lt": return a < b
				"lte": return a <= b
				"gt": return a > b
				"gte": return a >= b
	return false


static func validate_candidate(candidate: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var node_id := str(candidate.get("node_id", ""))
	if not _valid_node_id(node_id):
		issues.append("candidate.node_id must be lower_snake_case")
	if str(candidate.get("rule", "")).strip_edges() == "":
		issues.append("candidate.rule is required")
	if not (candidate.get("condition", null) is Dictionary) \
			or not _predicate_shape_valid(candidate.get("condition")):
		issues.append("candidate.condition is not a valid observation predicate")
	if not (candidate.get("action", null) is Dictionary) \
			or str((candidate.get("action", {}) as Dictionary).get("verb", "")) == "":
		issues.append("candidate.action.verb is required")
	if not (candidate.get("expected", null) is Dictionary) \
			or not _predicate_shape_valid(candidate.get("expected")):
		issues.append("candidate.expected is not a valid outcome predicate")
	if str(candidate.get("scope", "global")) not in ["fragment", "mechanic", "global"]:
		issues.append("candidate.scope must be fragment, mechanic, or global")
	return issues


static func canonical_hash(value: Variant) -> String:
	return Trace.canonical_hash(value)


static func canonicalize_predicate(predicate: Variant) -> Variant:
	# `all([P])`, `any([P])`, and P are semantically identical in the policy
	# evaluator. Native and Web are allowed to construct either representation;
	# collapse only singleton wrappers so their evidence shares one deterministic
	# signature while preserving every genuine multi-branch all/any decision.
	if not (predicate is Dictionary):
		return Trace.json_safe(predicate)
	var expression := predicate as Dictionary
	if expression.has("all") or expression.has("any"):
		var key := "all" if expression.has("all") else "any"
		if not (expression.get(key) is Array):
			return Trace.json_safe(expression)
		var children: Array = []
		for child in expression.get(key, []):
			children.append(canonicalize_predicate(child))
		if children.size() == 1:
			return children[0]
		return {key: children}
	if expression.has("not"):
		return {"not": canonicalize_predicate(expression.get("not"))}
	return Trace.json_safe(expression)


static func _document_key(document: Dictionary) -> String:
	var run := document.get("run", {}) as Dictionary
	return canonical_hash({
		"run_id": str(run.get("run_id", "")),
		"trace_id": str(run.get("trace_id", "")),
		"summary_record_hash": str(document.get("summary_record_hash", "")),
		"path": str(document.get("path", "")),
	})


static func _classify_invocation_cohorts(trace_documents: Array) -> Dictionary:
	var result := {}
	var groups := {}
	for document_value in trace_documents:
		if not (document_value is Dictionary):
			continue
		var document := document_value as Dictionary
		var document_key := _document_key(document)
		var validation_value: Variant = document.get("validation", null)
		if not (validation_value is Dictionary):
			result[document_key] = {
				"eligible": false,
				"rejection_reasons": ["invocation_cohort_validation_missing"],
			}
			continue
		var validation := validation_value as Dictionary
		var manifest_hash := str(validation.get("invocation_manifest_hash", ""))
		if manifest_hash == "":
			result[document_key] = {
				"eligible": false,
				"rejection_reasons": ["invocation_manifest_hash_missing"],
			}
			continue
		if not groups.has(manifest_hash):
			groups[manifest_hash] = []
		(groups[manifest_hash] as Array).append(document)
	for manifest_hash_value in groups.keys():
		var manifest_hash := str(manifest_hash_value)
		var documents := groups[manifest_hash] as Array
		var reasons: Array[String] = []
		var canonical_manifest := ""
		var manifest := {}
		var document_proof_counts := {}
		for document_value in documents:
			var document := document_value as Dictionary
			var validation := document.get("validation", {}) as Dictionary
			if not bool(validation.get("passed", false)):
				reasons.append("invocation_member_validation_not_passed")
			if int(validation.get("failure_count", -1)) != 0:
				reasons.append("invocation_member_validation_has_failures")
			if int(validation.get("check_count", 0)) < 1:
				reasons.append("invocation_member_validation_checks_missing")
			var manifest_value: Variant = validation.get("invocation_manifest", null)
			if not (manifest_value is Dictionary):
				reasons.append("invocation_manifest_missing")
				continue
			var current_manifest := manifest_value as Dictionary
			if Trace.canonical_hash(current_manifest) != manifest_hash:
				reasons.append("invocation_manifest_hash_mismatch")
			var encoded_manifest := Trace.canonical_hash(current_manifest)
			if canonical_manifest == "":
				canonical_manifest = encoded_manifest
				manifest = current_manifest.duplicate(true)
			elif canonical_manifest != encoded_manifest:
				reasons.append("invocation_manifest_payload_mismatch")
			var proof_key := Trace.canonical_hash(Trace.invocation_member_proof(document))
			document_proof_counts[proof_key] = int(document_proof_counts.get(proof_key, 0)) + 1
		if manifest.is_empty():
			reasons.append("invocation_manifest_unavailable")
		else:
			# The manifest is caller-authored data.  Rebuild it from the complete
			# document group before trusting its passed bit or member claims.  A
			# self-consistent rehash must not turn mixed content, duplicates, or a
			# filtered cohort into admissible evidence.
			var recomputed_manifest := Trace.make_invocation_manifest(
				documents, str(manifest.get("invocation_id", "")))
			if not Trace.canonical_equal(recomputed_manifest, manifest) \
					or Trace.canonical_hash(recomputed_manifest) != manifest_hash:
				reasons.append("invocation_manifest_not_recomputed_from_documents")
			if str(manifest.get("schema", "")) != Trace.INVOCATION_MANIFEST_SCHEMA:
				reasons.append("invocation_manifest_schema_not_current")
			if not bool(manifest.get("passed", false)):
				reasons.append("invocation_manifest_not_passed")
			if int(manifest.get("failure_count", -1)) != 0:
				reasons.append("invocation_manifest_has_failures")
			var members: Array = manifest.get("members", []) \
				if manifest.get("members", null) is Array else []
			if int(manifest.get("cohort_size", -1)) != members.size():
				reasons.append("invocation_manifest_cohort_size_mismatch")
			if documents.size() != members.size():
				reasons.append("invocation_cohort_document_count_mismatch")
			var manifest_proof_counts := {}
			for member_value in members:
				if not (member_value is Dictionary):
					reasons.append("invocation_manifest_member_not_an_object")
					continue
				var proof_key := Trace.canonical_hash(member_value)
				manifest_proof_counts[proof_key] = int(
					manifest_proof_counts.get(proof_key, 0)) + 1
			for proof_key_value in manifest_proof_counts.keys():
				var proof_key := str(proof_key_value)
				if int(manifest_proof_counts[proof_key]) != 1:
					reasons.append("invocation_manifest_duplicate_member")
				if int(document_proof_counts.get(proof_key, 0)) != 1:
					reasons.append("invocation_manifest_member_document_missing_or_duplicate")
			for proof_key_value in document_proof_counts.keys():
				if not manifest_proof_counts.has(str(proof_key_value)):
					reasons.append("invocation_cohort_contains_unlisted_document")
			var expected: Array = manifest.get("expected_members", []) \
				if manifest.get("expected_members", null) is Array else []
			var first_run := (documents[0] as Dictionary).get("run", {}) as Dictionary \
				if not documents.is_empty() else {}
			if not Trace.canonical_equal(expected,
					Trace.expected_validation_cohort(first_run)):
				reasons.append("invocation_expected_persona_repeat_matrix_not_current")
			for document_value in documents:
				var document := document_value as Dictionary
				var validation := document.get("validation", {}) as Dictionary
				if str(validation.get("invocation_id", "")) != str(
						manifest.get("invocation_id", "")):
					reasons.append("invocation_member_id_mismatch")
				if not Trace.canonical_equal(validation.get("cohort_member", {}),
						Trace.invocation_member_proof(document)):
					reasons.append("invocation_member_proof_mismatch")
		var unique_reasons := {}
		for reason in reasons:
			unique_reasons[reason] = true
		var sorted_reasons: Array[String] = []
		for reason in unique_reasons.keys():
			sorted_reasons.append(str(reason))
		sorted_reasons.sort()
		for document_value in documents:
			result[_document_key(document_value as Dictionary)] = {
				"eligible": sorted_reasons.is_empty(),
				"manifest_hash": manifest_hash,
				"cohort_size": documents.size(),
				"rejection_reasons": sorted_reasons.duplicate(),
			}
	return result


static func _classify_run_evidence(document: Dictionary,
		cohort_evidence: Dictionary = {}) -> Dictionary:
	var reasons: Array[String] = []
	if not bool(document.get("ok", false)):
		reasons.append("trace_integrity_failed")
	var summary_value: Variant = document.get("summary", null)
	var summary := summary_value as Dictionary if summary_value is Dictionary else {}
	if not (summary_value is Dictionary):
		reasons.append("trace_summary_missing")
	if str(document.get("summary_record_hash", "")).strip_edges() == "":
		reasons.append("summary_record_hash_missing")
	if not (summary.get("trace_complete", null) is bool) \
			or not bool(summary.get("trace_complete", false)):
		reasons.append("trace_not_complete")
	if not (summary.get("persona_goal_reached", null) is bool) \
			or not bool(summary.get("persona_goal_reached", false)):
		reasons.append("persona_goal_not_reached")
	var ineligible_decisions: Array[int] = []
	for raw_record in document.get("decisions", []):
		if not (raw_record is Dictionary):
			continue
		var record := raw_record as Dictionary
		if not bool(Trace.classify_evidence(record).get("eligible_for_learning", false)):
			ineligible_decisions.append(int(record.get("decision_index", -1)))
	if not ineligible_decisions.is_empty():
		reasons.append("run_contains_ineligible_decisions:%s" % str(ineligible_decisions))
	if not bool(cohort_evidence.get("eligible", false)):
		var cohort_reasons: Array = cohort_evidence.get("rejection_reasons", []) \
			if cohort_evidence.get("rejection_reasons", null) is Array else []
		if cohort_reasons.is_empty():
			reasons.append("invocation_cohort_not_verified")
		else:
			for reason in cohort_reasons:
				reasons.append("invocation_cohort:%s" % str(reason))
	var validation_value: Variant = document.get("validation", null)
	var validation := validation_value as Dictionary if validation_value is Dictionary else {}
	var run := document.get("run", {}) as Dictionary
	if not (validation_value is Dictionary) or validation.is_empty():
		reasons.append("strict_validation_missing")
	else:
		if str(document.get("validation_record_hash", "")).strip_edges() == "":
			reasons.append("strict_validation_record_hash_missing")
		if str(validation.get("schema", "")) != Trace.VALIDATION_SCHEMA:
			reasons.append("strict_validation_schema_not_current")
		if int(validation.get("contract_version", -1)) \
				!= Trace.CURRENT_VALIDATION_CONTRACT_VERSION:
			reasons.append("strict_validation_contract_version_not_current")
		if str(validation.get("contract_id", "")) \
				!= Trace.current_validation_contract_id(run):
			reasons.append("strict_validation_contract_not_current")
		if str(validation.get("validator_id", "")) \
				!= Trace.current_validation_validator_id(str(
					run.get("execution_platform", ""))):
			reasons.append("strict_validation_validator_not_current")
		if str(validation.get("execution_platform", "")) != str(
				run.get("execution_platform", "")):
			reasons.append("strict_validation_platform_mismatch")
		if str(validation.get("invocation_id", "")).strip_edges() == "":
			reasons.append("strict_validation_invocation_missing")
		if not (validation.get("passed", null) is bool) \
				or not bool(validation.get("passed", false)):
			reasons.append("strict_validation_not_passed")
		if int(validation.get("check_count", 0)) < 1:
			reasons.append("strict_validation_checks_missing")
		if int(validation.get("failure_count", -1)) != 0:
			reasons.append("strict_validation_has_failures")
		if int(validation.get("checked_decision_count", -1)) \
				!= (document.get("decisions", []) as Array).size():
			reasons.append("strict_validation_decision_count_mismatch")
	reasons.sort()
	return {
		"eligible_for_learning": reasons.is_empty(),
		"trace_integrity_verified": bool(document.get("ok", false)),
		"summary_record_hash": str(document.get("summary_record_hash", "")),
		"trace_complete": bool(summary.get("trace_complete", false)),
		"persona_goal_reached": bool(summary.get("persona_goal_reached", false)),
		"decision_count": (document.get("decisions", []) as Array).size(),
		"validation_record_hash": str(document.get("validation_record_hash", "")),
		"validation": validation.duplicate(true),
		"invocation_manifest_hash": str(cohort_evidence.get("manifest_hash", "")),
		"invocation_cohort_size": int(cohort_evidence.get("cohort_size", 0)),
		"ineligible_decision_indices": ineligible_decisions,
		"rejection_reasons": reasons,
	}


static func _consume_record(library: Dictionary, node_index: Dictionary,
		rejected: Dictionary, record: Dictionary, run_evidence: Dictionary,
		allow_preview_supersession := false,
		pending_supersessions: Dictionary = {}) -> void:
	var record_hash := str(record.get("record_hash", ""))
	var run := record.get("run", {}) as Dictionary
	var trace_id := str(run.get("trace_id", ""))
	var evidence := Trace.classify_evidence(record)
	if not bool(evidence.get("eligible_for_learning", false)):
		_add_rejection(rejected, _rejection_from_record(record, "ineligible_playthrough_evidence",
			evidence.get("rejection_reasons", [])))
		return
	if not (record.get("learning_candidate", null) is Dictionary):
		return
	var candidate := record.get("learning_candidate", {}) as Dictionary
	var candidate_issues := validate_candidate(candidate)
	if not candidate_issues.is_empty():
		_add_rejection(rejected, _rejection_from_record(record, "invalid_learning_candidate",
			candidate_issues))
		return
	var observation := record.get("observation_before", {}) as Dictionary
	if not evaluate_predicate(candidate.get("condition"), observation.get("state", {})):
		_add_rejection(rejected, _rejection_from_record(record,
			"candidate_condition_did_not_match_recorded_observation", []))
		return
	var decision := record.get("decision", {}) as Dictionary
	var candidate_action := candidate.get("action", {}) as Dictionary
	if str(candidate_action.get("verb", "")) != str(decision.get("verb", "")):
		_add_rejection(rejected, _rejection_from_record(record,
			"candidate_action_does_not_match_executed_verb", []))
		return
	var target_binding_issues := _candidate_target_binding_reasons(
		candidate, decision, observation)
	if not target_binding_issues.is_empty():
		_add_rejection(rejected, _rejection_from_record(record,
			"candidate_target_does_not_match_observation", target_binding_issues))
		return
	var node_id := str(candidate.get("node_id", ""))
	var policy := {
		"condition": canonicalize_predicate(candidate.get("condition")),
		"action": candidate_action,
		"expected": canonicalize_predicate(candidate.get("expected")),
		"scope": str(candidate.get("scope", "global")),
		"priority": clampi(int(candidate.get("priority", 50)), 0, 100),
	}
	var signature := canonical_hash(policy)
	var derived := Trace.derive_feedback_outcome(
		record.get("observation_before", {}) as Dictionary,
		record.get("observation_after", {}) as Dictionary,
		record.get("observation_samples", []) as Array,
		decision,
		record.get("input_receipt", {}) as Dictionary)
	var supported := evaluate_predicate(candidate.get("expected"),
		derived.get("outcome", {}))
	var node: Dictionary
	if node_index.has(node_id):
		node = node_index[node_id] as Dictionary
		var rule_conflict := str(node.get("rule", "")) != str(
			candidate.get("rule", ""))
		var policy_conflict := node.has("policy_signature") \
			and str(node.get("policy_signature", "")) != signature
		if (rule_conflict or policy_conflict) and allow_preview_supersession:
			var supersession_issues := _preview_supersession_shape_reasons(
				node, candidate, policy, run)
			for issue in _preview_supersession_entry_reasons(
					record, run_evidence, supported):
				supersession_issues.append(issue)
			supersession_issues.sort()
			if supersession_issues.is_empty():
				_stage_preview_supersession(pending_supersessions, node_id, {
					"record": record.duplicate(true),
					"run_evidence": run_evidence.duplicate(true),
					"candidate": candidate.duplicate(true),
					"policy": policy.duplicate(true),
					"policy_signature": signature,
					"rule": str(candidate.get("rule", "")),
					"record_hash": record_hash,
					"persona": str(run.get("persona", "")),
					"supported": supported,
				})
				return
			_add_rejection(rejected, _rejection_from_record(record,
				"candidate_policy_supersession_not_monotonic",
				supersession_issues))
			return
		if rule_conflict:
			_add_rejection(rejected, _rejection_from_record(record,
				"candidate_rule_conflicts_with_existing_node", []))
			return
		if policy_conflict:
			_add_rejection(rejected, _rejection_from_record(record,
				"policy_conflicts_with_existing_node", [
					"existing=%s" % str(node.get("policy_signature", "")),
					"candidate=%s" % signature,
				]))
			return
		if str(node.get("status", "")) == "retired":
			_add_rejection(rejected, _rejection_from_record(record,
				"retired_node_requires_explicit_reactivation", []))
			return
	else:
		node = {
			"id": node_id,
			"rule": str(candidate.get("rule", "")),
			"personas": [],
			"status": "candidate",
			"eligible_for_automation": false,
			"evidence": _empty_evidence(),
		}
		(library["nodes"] as Array).append(node)
		node_index[node_id] = node
	if not node.has("policy"):
		node["policy"] = policy
		node["policy_signature"] = signature
	if not node.has("evidence") or not (node["evidence"] is Dictionary):
		node["evidence"] = _empty_evidence()
	var node_evidence := node["evidence"] as Dictionary
	var provenance: Array = node_evidence.get("provenance", [])
	for source in provenance:
		if source is Dictionary and str((source as Dictionary).get("record_hash", "")) == record_hash:
			return
	var source := {
		"source_trace_schema": str(record.get("schema", "")),
		"record_hash": record_hash,
		"trace_id": trace_id,
		"run_id": str(run.get("run_id", "")),
		"decision_index": int(record.get("decision_index", -1)),
		"persona": str(run.get("persona", "")),
		"fragment_id": str(run.get("fragment_id", "")),
		"seed": int(run.get("seed", 0)),
		"repeat_index": int(run.get("repeat_index", -1)),
		"content_fingerprint_schema": str(run.get("content_fingerprint_schema", "")),
		"content_fingerprint": str(run.get("content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(run.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(run.get(
			"gameplay_build_fingerprint", "")),
		"execution_platform": str(run.get("execution_platform", "")),
		"trace_integrity_verified": bool(run_evidence.get(
			"trace_integrity_verified", false)),
		"summary_record_hash": str(run_evidence.get("summary_record_hash", "")),
		"trace_complete": bool(run_evidence.get("trace_complete", false)),
		"persona_goal_reached": bool(run_evidence.get(
			"persona_goal_reached", false)),
		"validation_record_hash": str(run_evidence.get(
			"validation_record_hash", "")),
		"validation_schema": str((run_evidence.get(
			"validation", {}) as Dictionary).get("schema", "")),
		"validation_contract_id": str((run_evidence.get(
			"validation", {}) as Dictionary).get("contract_id", "")),
		"validation_contract_version": int((run_evidence.get(
			"validation", {}) as Dictionary).get("contract_version", -1)),
		"validation_validator_id": str((run_evidence.get(
			"validation", {}) as Dictionary).get("validator_id", "")),
		"validation_execution_platform": str((run_evidence.get(
			"validation", {}) as Dictionary).get("execution_platform", "")),
		"validation_invocation_id": str((run_evidence.get(
			"validation", {}) as Dictionary).get("invocation_id", "")),
		"validation_passed": bool((run_evidence.get(
			"validation", {}) as Dictionary).get("passed", false)),
		"validation_failure_count": int((run_evidence.get(
			"validation", {}) as Dictionary).get("failure_count", -1)),
		"validation_check_count": int((run_evidence.get(
			"validation", {}) as Dictionary).get("check_count", -1)),
		"validation_checked_decision_count": int((run_evidence.get(
			"validation", {}) as Dictionary).get("checked_decision_count", -1)),
		"run_decision_count": int(run_evidence.get("decision_count", -1)),
		"invocation_manifest_hash": str(run_evidence.get(
			"invocation_manifest_hash", "")),
		"invocation_cohort_size": int(run_evidence.get(
			"invocation_cohort_size", 0)),
		"invocation_manifest_schema": str((((run_evidence.get(
			"validation", {}) as Dictionary).get(
			"invocation_manifest", {}) as Dictionary).get("schema", ""))),
		"invocation_manifest_passed": bool((((run_evidence.get(
			"validation", {}) as Dictionary).get(
			"invocation_manifest", {}) as Dictionary).get("passed", false))),
		"invocation_manifest_failure_count": int((((run_evidence.get(
			"validation", {}) as Dictionary).get(
			"invocation_manifest", {}) as Dictionary).get("failure_count", -1))),
		"verdict": "supports" if supported else "contradicts",
		"input_receipt_id": str((record.get("input_receipt", {}) as Dictionary).get(
			"receipt_id", "")),
	}
	provenance.append(source)
	node_evidence["provenance"] = provenance
	node["evidence"] = node_evidence
	var personas: Array = node.get("personas", [])
	var persona := str(run.get("persona", ""))
	if persona != "" and not personas.has(persona):
		personas.append(persona)
	personas.sort()
	node["personas"] = personas


## Pure validation seam used by the verifier. A preview replacement is about
## selector precision only; it cannot smuggle in a different trigger, outcome,
## priority, scope, persona, verb, or extra action parameter.
static func validate_preview_supersession_shape(existing_node: Dictionary,
		candidate: Dictionary, run: Dictionary) -> Array[String]:
	var candidate_action := candidate.get("action", {}) as Dictionary
	var policy := {
		"condition": canonicalize_predicate(candidate.get("condition")),
		"action": candidate_action.duplicate(true),
		"expected": canonicalize_predicate(candidate.get("expected")),
		"scope": str(candidate.get("scope", "global")),
		"priority": clampi(int(candidate.get("priority", 50)), 0, 100),
	}
	return _preview_supersession_shape_reasons(
		existing_node, candidate, policy, run)


static func _preview_supersession_shape_reasons(existing_node: Dictionary,
		candidate: Dictionary, candidate_policy: Dictionary,
		run: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	if str(existing_node.get("status", "")) != "validated" \
			or not bool(existing_node.get("eligible_for_automation", false)):
		reasons.append("existing_node_is_not_validated_and_eligible")
	if not (existing_node.get("policy", null) is Dictionary):
		reasons.append("existing_node_policy_missing")
		return reasons
	var old_policy := existing_node.get("policy", {}) as Dictionary
	var old_action := old_policy.get("action", {}) as Dictionary
	var new_action := candidate_policy.get("action", {}) as Dictionary
	var persona := str(run.get("persona", ""))
	var personas: Array = existing_node.get("personas", []) \
		if existing_node.get("personas", null) is Array else []
	if persona == "" or persona not in personas:
		reasons.append("candidate_persona_is_not_owned_by_existing_node")
	if personas.size() != 1 or persona == "" or str(personas[0]) != persona:
		reasons.append("existing_node_persona_ownership_not_exact_singleton")
	if str(old_action.get("verb", "")) != str(new_action.get("verb", "")):
		reasons.append("action_verb_changed")
	if not Trace.canonical_equal(_action_without_target_ref(old_action),
			_action_without_target_ref(new_action)):
		reasons.append("non_target_action_fields_changed")
	if not Trace.canonical_equal(canonicalize_predicate(old_policy.get("expected")),
			canonicalize_predicate(candidate_policy.get("expected"))):
		reasons.append("expected_outcome_changed")
	if str(old_policy.get("scope", "global")) != str(
			candidate_policy.get("scope", "global")):
		reasons.append("policy_scope_changed")
	if int(old_policy.get("priority", 50)) != int(
			candidate_policy.get("priority", 50)):
		reasons.append("policy_priority_changed")
	var old_target_ref := str(old_action.get("target_ref", ""))
	var new_target_ref := str(new_action.get("target_ref", ""))
	var old_contract := _target_ref_precision_contract(old_target_ref)
	var new_contract := _target_ref_precision_contract(new_target_ref)
	if old_contract.is_empty():
		reasons.append("existing_target_ref_has_no_precision_contract:%s" % old_target_ref)
	if new_contract.is_empty():
		reasons.append("candidate_target_ref_has_no_precision_contract:%s" % new_target_ref)
	if not old_contract.is_empty() and not new_contract.is_empty():
		if str(old_contract.get("intent_family", "")) != str(
				new_contract.get("intent_family", "")):
			reasons.append("target_intent_family_changed")
		if str(old_contract.get("anchor_path", "")) != str(
				new_contract.get("anchor_path", "")):
			reasons.append("target_semantic_anchor_path_changed")
		if not bool(old_contract.get("proxy", false)):
			reasons.append("existing_target_ref_is_not_a_proxy")
		if not bool(new_contract.get("exact_current_token", false)):
			reasons.append("candidate_target_ref_is_not_an_exact_current_token")
		if int(new_contract.get("precision_rank", -1)) <= int(
				old_contract.get("precision_rank", -1)):
			reasons.append("target_precision_did_not_strictly_increase")
		var anchor_path := str(old_contract.get("anchor_path", ""))
		var old_anchors := _predicate_contains_values(
			old_policy.get("condition"), anchor_path)
		var new_anchors := _predicate_contains_values(
			candidate_policy.get("condition"), anchor_path)
		if old_anchors.is_empty() or new_anchors.is_empty():
			reasons.append("semantic_target_anchor_missing")
		elif not Trace.canonical_equal(old_anchors, new_anchors):
			reasons.append("semantic_target_anchor_changed")
		var old_projection := _selector_proxy_projection(
			old_policy.get("condition"), old_contract)
		var new_projection := _selector_proxy_projection(
			candidate_policy.get("condition"), old_contract)
		var old_proxy_guards := old_projection.get("guards", []) as Array
		var new_proxy_guards := new_projection.get("guards", []) as Array
		if old_proxy_guards.is_empty():
			reasons.append("existing_proxy_selector_has_no_owned_structural_guard")
		if not new_proxy_guards.is_empty():
			reasons.append("candidate_retained_selector_owned_proxy_guard")
		if not Trace.canonical_equal(old_projection.get("condition"),
				new_projection.get("condition")):
			reasons.append("non_proxy_condition_predicates_changed")
		if not _guard_multiset_is_subset(
				new_proxy_guards, old_proxy_guards):
			reasons.append("candidate_added_or_changed_proxy_guard")
	if str(candidate_policy.get("scope", "global")) == "fragment":
		var fragment_id := str(run.get("fragment_id", ""))
		if fragment_id == "" or not _node_provenance_has_fragment(
				existing_node, fragment_id):
			reasons.append("fragment_scope_not_present_in_existing_provenance")
	var unique := {}
	for reason in reasons:
		unique[reason] = true
	var sorted: Array[String] = []
	for reason in unique.keys():
		sorted.append(str(reason))
	sorted.sort()
	return sorted


static func _preview_supersession_entry_reasons(record: Dictionary,
		run_evidence: Dictionary, supported: bool) -> Array[String]:
	var reasons: Array[String] = []
	var run := record.get("run", {}) as Dictionary
	if str(record.get("schema", "")) != Trace.TRACE_SCHEMA:
		reasons.append("candidate_record_trace_schema_not_current")
	if not bool(Trace.classify_evidence(record).get("eligible_for_learning", false)):
		reasons.append("candidate_record_is_not_human_input_evidence")
	if not bool(run_evidence.get("eligible_for_learning", false)):
		reasons.append("candidate_run_is_not_learning_complete")
	if not bool(run_evidence.get("trace_integrity_verified", false)):
		reasons.append("candidate_trace_integrity_not_verified")
	if not bool(run_evidence.get("trace_complete", false)):
		reasons.append("candidate_trace_not_complete")
	if not bool(run_evidence.get("persona_goal_reached", false)):
		reasons.append("candidate_persona_goal_not_reached")
	var validation := run_evidence.get("validation", {}) as Dictionary
	if str(validation.get("schema", "")) != Trace.VALIDATION_SCHEMA \
			or int(validation.get("contract_version", -1)) \
				!= Trace.CURRENT_VALIDATION_CONTRACT_VERSION \
			or not bool(validation.get("passed", false)) \
			or int(validation.get("failure_count", -1)) != 0:
		reasons.append("candidate_strict_validation_not_current_and_passed")
	var manifest := validation.get("invocation_manifest", {}) as Dictionary
	if not _valid_sha256_text(str(run_evidence.get(
			"invocation_manifest_hash", ""))) \
			or str(manifest.get("schema", "")) != Trace.INVOCATION_MANIFEST_SCHEMA \
			or not bool(manifest.get("passed", false)) \
			or int(manifest.get("failure_count", -1)) != 0 \
			or int(run_evidence.get("invocation_cohort_size", 0)) < 1:
		reasons.append("candidate_invocation_cohort_not_current_and_complete")
	if not _run_content_and_build_are_current(run):
		reasons.append("candidate_content_or_gameplay_build_not_current")
	if not supported:
		reasons.append("candidate_expected_outcome_not_derived")
	reasons.sort()
	return reasons


static func _run_content_and_build_are_current(run: Dictionary) -> bool:
	var current_build := ContentFingerprint.gameplay_build()
	if not bool(current_build.get("ok", false)) \
			or str(run.get("gameplay_build_fingerprint_schema", "")) != str(
				current_build.get("gameplay_build_fingerprint_schema", "")) \
			or str(run.get("gameplay_build_fingerprint", "")) != str(
				current_build.get("gameplay_build_fingerprint", "")):
		return false
	if str(run.get("content_fingerprint_schema", "")) \
			!= ContentFingerprint.AUTHORED_FRAGMENT_SCHEMA:
		# Generated specs cannot be reconstructed from trace metadata alone. A
		# preview replacement therefore refuses them instead of trusting a stale ID.
		return false
	var fragment_id := str(run.get("fragment_id", ""))
	if not _valid_node_id(fragment_id):
		return false
	var current_content := ContentFingerprint.authored_fragment_resource(
		"res://data/fragments/%s.tres" % fragment_id)
	return bool(current_content.get("ok", false)) \
		and str(run.get("content_fingerprint", "")) == str(
			current_content.get("content_fingerprint", ""))


static func _target_ref_precision_contract(target_ref: String) -> Dictionary:
	var value: Variant = TARGET_REF_PRECISION_CONTRACTS.get(target_ref, null)
	if not (value is Dictionary):
		return {}
	var contract := value as Dictionary
	return contract.duplicate(true) if _target_ref_precision_contract_reasons(
		target_ref, contract).is_empty() else {}


static func validate_target_ref_precision_registry() -> Array[String]:
	var reasons: Array[String] = []
	var target_refs: Array[String] = []
	for target_ref_value in TARGET_REF_PRECISION_CONTRACTS.keys():
		target_refs.append(str(target_ref_value))
	target_refs.sort()
	for target_ref in target_refs:
		for issue in _target_ref_precision_contract_reasons(target_ref,
				TARGET_REF_PRECISION_CONTRACTS[target_ref] as Dictionary):
			reasons.append("%s:%s" % [target_ref, issue])
	return reasons


static func validate_target_ref_precision_contract(target_ref: String,
		contract: Dictionary) -> Array[String]:
	return _target_ref_precision_contract_reasons(target_ref, contract)


static func _target_ref_precision_contract_reasons(target_ref: String,
		contract: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	for field in ["intent_family", "binding_mode", "anchor_path", "target_kind"]:
		if str(contract.get(field, "")).strip_edges() == "":
			reasons.append("%s_missing" % field)
	if int(contract.get("precision_rank", -1)) < 0:
		reasons.append("precision_rank_invalid")
	if not (contract.get("proxy", null) is bool) \
			or not (contract.get("exact_current_token", null) is bool) \
			or bool(contract.get("proxy", false)) \
				== bool(contract.get("exact_current_token", false)):
		reasons.append("proxy_exact_flags_invalid")
	if not (contract.get("removable_path_prefixes", null) is Array):
		reasons.append("removable_path_prefixes_invalid")
	var mode := str(contract.get("binding_mode", ""))
	var mode_value: Variant = TARGET_BINDING_MODE_CONTRACTS.get(mode, null)
	if not (mode_value is Dictionary):
		reasons.append("binding_mode_unrecognized")
	else:
		var mode_contract := mode_value as Dictionary
		for field in ["proxy", "exact_current_token", "target_kind"]:
			if not Trace.canonical_equal(contract.get(field), mode_contract.get(field)):
				reasons.append("binding_mode_%s_mismatch" % field)
	if not _target_ref_has_runtime_binder(target_ref):
		reasons.append("runtime_target_binder_missing")
	reasons.sort()
	return reasons


static func _target_ref_has_runtime_binder(target_ref: String) -> bool:
	# Keep this list adjacent to the executable match in
	# `_candidate_target_binding_reasons`. Registry metadata alone is never proof
	# that a player-visible target can actually be verified.
	return target_ref in [
		"matching_visible_interaction",
		"chosen_visible_ground",
		"matching_visible_ladder_route",
		"matching_visible_shelter_surface",
		"nearest_visible_ground_to_shelter_label",
		"advertised_visible_hide_control",
		"visible_hud_roster",
		"announced_visible_consequence",
	]


static func _action_without_target_ref(action: Dictionary) -> Dictionary:
	var result := action.duplicate(true)
	result.erase("target_ref")
	return result


static func _node_provenance_has_fragment(node: Dictionary,
		fragment_id: String) -> bool:
	var evidence := node.get("evidence", {}) as Dictionary
	for source_value in evidence.get("provenance", []):
		if source_value is Dictionary and str((source_value as Dictionary).get(
				"fragment_id", "")) == fragment_id:
			return true
	return false


static func _selector_proxy_projection(predicate: Variant,
		contract: Dictionary) -> Dictionary:
	var prefixes: Array = contract.get("removable_path_prefixes", []) \
		if contract.get("removable_path_prefixes", null) is Array else []
	var projection := _strip_selector_owned_proxy_groups(
		canonicalize_predicate(predicate), prefixes)
	var cleaned: Variant = projection.get("condition", null)
	if cleaned == null:
		cleaned = {}
	else:
		cleaned = canonicalize_predicate(cleaned)
	var guards: Array = projection.get("guards", [])
	guards.sort()
	return {"condition": cleaned, "guards": guards}


static func _strip_selector_owned_proxy_groups(predicate: Variant,
		prefixes: Array) -> Dictionary:
	if not (predicate is Dictionary):
		return {"condition": Trace.json_safe(predicate), "guards": [], "owned": false}
	var expression := predicate as Dictionary
	if not expression.has("all") and not expression.has("any") \
			and not expression.has("not"):
		var path := str(expression.get("path", ""))
		var owned := str(expression.get("op", "")) == "exists" \
			and _path_has_any_prefix(path, prefixes)
		return {
			"condition": null if owned else Trace.json_safe(expression),
			"guards": [canonical_hash(expression)] if owned else [],
			"owned": owned,
		}
	if expression.has("not"):
		# Negated viewport predicates are gameplay logic, never disposable
		# selector scaffolding.
		return {"condition": Trace.json_safe(expression), "guards": [], "owned": false}
	var operator := "all" if expression.has("all") else "any"
	var children: Array = expression.get(operator, []) \
		if expression.get(operator, null) is Array else []
	var projections: Array = []
	var every_child_owned := not children.is_empty()
	for child in children:
		var child_projection := _strip_selector_owned_proxy_groups(child, prefixes)
		projections.append(child_projection)
		every_child_owned = every_child_owned and bool(child_projection.get("owned", false))
	if operator == "any" and not every_child_owned:
		# Partially deleting an OR branch changes gameplay meaning. Keep the whole
		# subtree so the final residual comparison rejects that attempted rewrite.
		return {"condition": Trace.json_safe(expression), "guards": [], "owned": false}
	var kept: Array = []
	var guards: Array = []
	for projection_value in projections:
		var child_projection := projection_value as Dictionary
		guards.append_array(child_projection.get("guards", []) as Array)
		if not bool(child_projection.get("owned", false)):
			kept.append(child_projection.get("condition"))
	if every_child_owned:
		return {"condition": null, "guards": guards, "owned": true}
	var cleaned: Variant
	if kept.size() == 1:
		cleaned = kept[0]
	else:
		cleaned = {operator: kept}
	return {"condition": cleaned, "guards": guards, "owned": false}


static func _path_has_any_prefix(path: String, prefixes: Array) -> bool:
	for prefix_value in prefixes:
		if path.begins_with(str(prefix_value)):
			return true
	return false


static func _guard_multiset_is_subset(candidate_guards: Array,
		existing_guards: Array) -> bool:
	var available := {}
	for guard_value in existing_guards:
		var guard := str(guard_value)
		available[guard] = int(available.get(guard, 0)) + 1
	for guard_value in candidate_guards:
		var guard := str(guard_value)
		if int(available.get(guard, 0)) < 1:
			return false
		available[guard] = int(available.get(guard, 0)) - 1
	return true


static func _stage_preview_supersession(pending: Dictionary, node_id: String,
		entry: Dictionary) -> void:
	if not pending.has(node_id):
		pending[node_id] = []
	(pending[node_id] as Array).append(entry.duplicate(true))


## Pure cohort seam for the negative matrix. Entries are the staged dictionaries
## produced above; callers cannot qualify hand-waved support counts because every
## member must still carry the verified trace/run/manifest proof.
static func validate_preview_supersession_support_group(entries: Array,
		minimum_support := DEFAULT_MINIMUM_SUPPORT) -> Array[String]:
	return _preview_supersession_support_group_reasons(
		entries, maxi(2, minimum_support))


static func _preview_supersession_support_group_reasons(entries: Array,
		minimum_support: int) -> Array[String]:
	var reasons: Array[String] = []
	var records := {}
	var runs := {}
	var traces := {}
	var manifests := {}
	var contents := {}
	var builds := {}
	var personas := {}
	for entry_value in entries:
		if not (entry_value is Dictionary):
			reasons.append("support_entry_not_an_object")
			continue
		var entry := entry_value as Dictionary
		var record := entry.get("record", {}) as Dictionary
		var run := record.get("run", {}) as Dictionary
		var run_evidence := entry.get("run_evidence", {}) as Dictionary
		for issue in _preview_supersession_entry_reasons(
				record, run_evidence, bool(entry.get("supported", false))):
			reasons.append("entry:%s" % issue)
		var record_hash := str(entry.get("record_hash", record.get(
			"record_hash", "")))
		var run_id := str(run.get("run_id", ""))
		var trace_id := str(run.get("trace_id", ""))
		var manifest_hash := str(run_evidence.get("invocation_manifest_hash", ""))
		var content_identity := "%s:%s" % [
			str(run.get("content_fingerprint_schema", "")),
			str(run.get("content_fingerprint", "")),
		]
		var build_identity := "%s:%s" % [
			str(run.get("gameplay_build_fingerprint_schema", "")),
			str(run.get("gameplay_build_fingerprint", "")),
		]
		var persona := str(run.get("persona", ""))
		records[record_hash] = int(records.get(record_hash, 0)) + 1
		runs[run_id] = int(runs.get(run_id, 0)) + 1
		traces[trace_id] = int(traces.get(trace_id, 0)) + 1
		manifests[manifest_hash] = true
		contents[content_identity] = true
		builds[build_identity] = true
		personas[persona] = true
		var expected_cohort_size := Trace.expected_validation_cohort(run).size()
		if expected_cohort_size < 1 or int(run_evidence.get(
				"invocation_cohort_size", 0)) != expected_cohort_size:
			reasons.append("support_invocation_cohort_size_not_current")
	if entries.size() < minimum_support:
		reasons.append("support_count_below_minimum:%d<%d" % [
			entries.size(), minimum_support])
	if _nonempty_key_count(records) < minimum_support:
		reasons.append("distinct_record_count_below_minimum")
	if _nonempty_key_count(runs) < minimum_support:
		reasons.append("distinct_run_count_below_minimum")
	if _nonempty_key_count(traces) < minimum_support:
		reasons.append("distinct_trace_count_below_minimum")
	if _nonempty_key_count(records) != entries.size():
		reasons.append("duplicate_support_record")
	if _nonempty_key_count(runs) != entries.size():
		reasons.append("duplicate_support_run")
	if _nonempty_key_count(traces) != entries.size():
		reasons.append("duplicate_support_trace")
	if _nonempty_key_count(manifests) != 1:
		reasons.append("support_manifest_is_not_uniform")
	if _nonempty_key_count(contents) != 1:
		reasons.append("support_content_is_not_uniform")
	if _nonempty_key_count(builds) != 1:
		reasons.append("support_gameplay_build_is_not_uniform")
	if _nonempty_key_count(personas) != 1:
		reasons.append("support_persona_is_not_uniform")
	var unique := {}
	for reason in reasons:
		unique[reason] = true
	var sorted: Array[String] = []
	for reason in unique.keys():
		sorted.append(str(reason))
	sorted.sort()
	return sorted


static func _apply_preview_supersessions(library: Dictionary,
		node_index: Dictionary, rejected: Dictionary, pending: Dictionary,
		minimum_support: int) -> void:
	var node_ids: Array[String] = []
	for node_id_value in pending.keys():
		node_ids.append(str(node_id_value))
	node_ids.sort()
	for node_id in node_ids:
		if not node_index.has(node_id):
			continue
		var entries: Array = pending.get(node_id, []) \
			if pending.get(node_id, null) is Array else []
		entries.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str((a as Dictionary).get("record_hash", "")) < str(
				(b as Dictionary).get("record_hash", "")))
		var variants := {}
		for entry_value in entries:
			if not (entry_value is Dictionary):
				continue
			var entry := entry_value as Dictionary
			var variant_key := canonical_hash({
				"policy_signature": str(entry.get("policy_signature", "")),
				"rule": str(entry.get("rule", "")),
			})
			if not variants.has(variant_key):
				variants[variant_key] = []
			(variants[variant_key] as Array).append(entry)
		var variant_keys: Array[String] = []
		for variant_key_value in variants.keys():
			variant_keys.append(str(variant_key_value))
		variant_keys.sort()
		var qualified_variants: Array = []
		var variant_failures := {}
		for variant_key in variant_keys:
			var variant_entries := variants[variant_key] as Array
			var cohort_groups := {}
			for entry_value in variant_entries:
				var entry := entry_value as Dictionary
				var cohort_key := _preview_supersession_cohort_key(entry)
				if not cohort_groups.has(cohort_key):
					cohort_groups[cohort_key] = []
				(cohort_groups[cohort_key] as Array).append(entry)
			var cohort_keys: Array[String] = []
			for cohort_key_value in cohort_groups.keys():
				cohort_keys.append(str(cohort_key_value))
			cohort_keys.sort()
			var supported_entries: Array = []
			var supported_manifest_hashes := {}
			var failure_reasons: Array[String] = []
			for cohort_key in cohort_keys:
				var cohort_entries := cohort_groups[cohort_key] as Array
				cohort_entries.sort_custom(func(a: Variant, b: Variant) -> bool:
					return str((a as Dictionary).get("record_hash", "")) < str(
						(b as Dictionary).get("record_hash", "")))
				var cohort_reasons := _preview_supersession_support_group_reasons(
					cohort_entries, minimum_support)
				if cohort_reasons.is_empty():
					supported_entries.append_array(cohort_entries)
					var evidence := (cohort_entries[0] as Dictionary).get(
						"run_evidence", {}) as Dictionary
					supported_manifest_hashes[str(evidence.get(
						"invocation_manifest_hash", ""))] = true
				else:
					for reason in cohort_reasons:
						failure_reasons.append("cohort:%s" % reason)
			variant_failures[variant_key] = failure_reasons
			if not supported_entries.is_empty():
				var manifest_hashes: Array[String] = []
				for manifest_hash_value in supported_manifest_hashes.keys():
					manifest_hashes.append(str(manifest_hash_value))
				manifest_hashes.sort()
				qualified_variants.append({
					"variant_key": variant_key,
					"entries": supported_entries,
					"manifest_hashes": manifest_hashes,
				})
		if qualified_variants.is_empty():
			for variant_key in variant_keys:
				var details: Array = variant_failures.get(variant_key, [])
				if details.is_empty():
					details = ["no_current_complete_support_cohort"]
				for entry_value in variants[variant_key] as Array:
					_add_rejection(rejected, _rejection_from_record(
						(entry_value as Dictionary).get("record", {}) as Dictionary,
						"candidate_policy_supersession_support_insufficient", details))
			continue
		if qualified_variants.size() > 1:
			var ambiguity: Array[String] = []
			for qualified_value in qualified_variants:
				var qualified := qualified_value as Dictionary
				var first_entry := (qualified.get("entries", []) as Array)[0] as Dictionary
				ambiguity.append("%s:%s" % [
					str(first_entry.get("policy_signature", "")),
					str(first_entry.get("rule", "")),
				])
			ambiguity.sort()
			for variant_key in variant_keys:
				for entry_value in variants[variant_key] as Array:
					_add_rejection(rejected, _rejection_from_record(
						(entry_value as Dictionary).get("record", {}) as Dictionary,
						"candidate_policy_supersession_ambiguous", ambiguity))
			continue
		var winner := qualified_variants[0] as Dictionary
		var winner_key := str(winner.get("variant_key", ""))
		var selected_entries := winner.get("entries", []) as Array
		selected_entries.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str((a as Dictionary).get("record_hash", "")) < str(
				(b as Dictionary).get("record_hash", "")))
		var selected_hashes := {}
		for entry_value in selected_entries:
			selected_hashes[str((entry_value as Dictionary).get(
				"record_hash", ""))] = true
		for variant_key in variant_keys:
			for entry_value in variants[variant_key] as Array:
				var entry := entry_value as Dictionary
				if variant_key != winner_key or not selected_hashes.has(str(
						entry.get("record_hash", ""))):
					_add_rejection(rejected, _rejection_from_record(
						entry.get("record", {}) as Dictionary,
						"candidate_policy_supersession_support_not_selected", []))
		var existing_node := node_index[node_id] as Dictionary
		_install_preview_supersession(existing_node, selected_entries,
			winner.get("manifest_hashes", []) as Array)
		for entry_value in selected_entries:
			var entry := entry_value as Dictionary
			_consume_record(library, node_index, rejected,
				entry.get("record", {}) as Dictionary,
				entry.get("run_evidence", {}) as Dictionary, false, {})


static func _preview_supersession_cohort_key(entry: Dictionary) -> String:
	var record := entry.get("record", {}) as Dictionary
	var run := record.get("run", {}) as Dictionary
	var run_evidence := entry.get("run_evidence", {}) as Dictionary
	return canonical_hash({
		"invocation_manifest_hash": str(run_evidence.get(
			"invocation_manifest_hash", "")),
		"content_fingerprint_schema": str(run.get(
			"content_fingerprint_schema", "")),
		"content_fingerprint": str(run.get("content_fingerprint", "")),
		"gameplay_build_fingerprint_schema": str(run.get(
			"gameplay_build_fingerprint_schema", "")),
		"gameplay_build_fingerprint": str(run.get(
			"gameplay_build_fingerprint", "")),
		"execution_platform": str(run.get("execution_platform", "")),
		"persona": str(run.get("persona", "")),
	})


static func _install_preview_supersession(existing_node: Dictionary,
		selected_entries: Array, manifest_hashes: Array) -> void:
	var first_entry := selected_entries[0] as Dictionary
	var history: Array = existing_node.get("superseded_policy_history", []) \
		if existing_node.get("superseded_policy_history", null) is Array else []
	var archived_evidence := (existing_node.get(
		"evidence", {}) as Dictionary).duplicate(true)
	var archived_provenance: Array = archived_evidence.get("provenance", []) \
		if archived_evidence.get("provenance", null) is Array else []
	archived_provenance.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as Dictionary).get("record_hash", "")) < str(
			(b as Dictionary).get("record_hash", "")))
	archived_evidence["provenance"] = archived_provenance
	var archived_personas := (existing_node.get(
		"personas", []) as Array).duplicate(true)
	archived_personas.sort()
	var archive := {
		"schema": PREVIEW_SUPERSESSION_ARCHIVE_SCHEMA,
		"reason": "monotonic_target_precision",
		"rule": str(existing_node.get("rule", "")),
		"policy": (existing_node.get("policy", {}) as Dictionary).duplicate(true),
		"policy_signature": str(existing_node.get("policy_signature", "")),
		"status": str(existing_node.get("status", "")),
		"eligible_for_automation": bool(existing_node.get(
			"eligible_for_automation", false)),
		"personas": archived_personas,
		"evidence": archived_evidence,
		"successor_policy_signature": str(first_entry.get(
			"policy_signature", "")),
		"support_invocation_manifest_hashes": manifest_hashes.duplicate(true),
	}
	history.append(archive.duplicate(true))
	existing_node["superseded_policy_history"] = history.duplicate(true)
	existing_node["rule"] = str(first_entry.get("rule", ""))
	existing_node["policy"] = (first_entry.get("policy", {}) as Dictionary).duplicate(true)
	existing_node["policy_signature"] = str(first_entry.get(
		"policy_signature", ""))
	existing_node["status"] = "candidate"
	existing_node["eligible_for_automation"] = false
	existing_node["personas"] = []
	existing_node["evidence"] = _empty_evidence()


static func _candidate_target_binding_reasons(candidate: Dictionary,
		decision: Dictionary, observation: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	var action := candidate.get("action", {}) as Dictionary
	var target_ref := str(action.get("target_ref", ""))
	var target_value: Variant = decision.get("target", null)
	var target_token := str((target_value as Dictionary).get("token", "")) \
		if target_value is Dictionary else ""
	var state := observation.get("state", {}) as Dictionary
	var affordances: Array = state.get("affordances", []) \
		if state.get("affordances", null) is Array else []
	var target_affordance := _affordance_by_token(affordances, target_token)
	match target_ref:
		"matching_visible_interaction":
			if target_affordance.is_empty() \
					or str(target_affordance.get("kind", "")) != "interact":
				reasons.append("target is not the chosen visible interaction")
			else:
				var expected_verbs := _predicate_contains_values(
					candidate.get("condition"), "visible_affordance_verbs")
				if expected_verbs.is_empty() or str(target_affordance.get(
						"verb", "")) not in expected_verbs:
					reasons.append("interaction token does not match the candidate's exact visible verb")
		"chosen_visible_ground":
			if target_affordance.is_empty() \
					or str(target_affordance.get("kind", "")) != "move":
				reasons.append("target is not a chosen visible ground affordance")
		"matching_visible_ladder_route":
			if target_affordance.is_empty() \
					or str(target_affordance.get("kind", "")) != "move" \
					or not str(target_affordance.get("consequence", "")).to_upper().contains(
						"LADDER"):
				reasons.append("target is not the chosen visible ladder-annotated route")
		"matching_visible_shelter_surface":
			var expected_verbs := _predicate_contains_values(
				candidate.get("condition"), "visible_affordance_verbs")
			var visible_verb := str(target_affordance.get(
				"verb", "")).strip_edges()
			if target_affordance.is_empty() \
					or str(target_affordance.get("kind", "")) != "interact" \
					or visible_verb.to_upper() != "REST PARTY" \
					or visible_verb not in expected_verbs:
				reasons.append(
					"target is not the chosen exact visible REST PARTY shelter surface")
		"nearest_visible_ground_to_shelter_label":
			var exact_visible_verbs := _predicate_contains_values(
				candidate.get("condition"), "visible_affordance_verbs")
			var nearest_tokens := nearest_ground_tokens_to_visible_label(
				observation, ["SHELTER", "REST"], exact_visible_verbs)
			if target_token == "" or target_token not in nearest_tokens:
				reasons.append("target is not a nearest visible ground affordance to the shelter label")
		"advertised_visible_hide_control":
			if target_token != "visible_h_hide_control" \
					or not _has_visible_cue_text(observation, ["H", "HIDE"], "instruction"):
				reasons.append("target does not bind the advertised visible Hide control")
		"visible_hud_roster":
			var visible_portraits := _visible_portraits(observation)
			var has_unselected := false
			for portrait_value in visible_portraits:
				has_unselected = has_unselected or not bool(
					(portrait_value as Dictionary).get("selected", false))
			if target_token != "hud_portraits" or visible_portraits.is_empty() \
					or not has_unselected:
				reasons.append("target does not bind the visible selectable HUD roster")
		"announced_visible_consequence":
			if target_token != "visible_announced_mid_crossing" \
					or not _has_visible_cue_text(observation,
						["CROSSING STAGING", "CROSSING ARMED", "NEXT MID"]):
				reasons.append("target does not bind the visible announced consequence")
		_:
			reasons.append("candidate target_ref is unknown or unverifiable: %s" % target_ref)
	reasons.sort()
	return reasons


static func validate_candidate_target_binding(candidate: Dictionary,
		decision: Dictionary, observation_before: Dictionary) -> Array[String]:
	return _candidate_target_binding_reasons(candidate, decision, observation_before)


static func _affordance_by_token(affordances: Array, token: String) -> Dictionary:
	for value in affordances:
		if value is Dictionary and str((value as Dictionary).get("token", "")) == token:
			return value as Dictionary
	return {}


static func _predicate_contains_values(predicate: Variant, path: String) -> Array[String]:
	var values: Array[String] = []
	if not (predicate is Dictionary):
		return values
	var expression := predicate as Dictionary
	if str(expression.get("path", "")) == path \
			and str(expression.get("op", "")) == "contains" \
			and (expression.get("value", null) is String \
				or expression.get("value", null) is StringName):
		values.append(str(expression.get("value", "")))
	for key in ["all", "any"]:
		if expression.get(key, null) is Array:
			for child in expression.get(key, []):
				for value in _predicate_contains_values(child, path):
					if value not in values:
						values.append(value)
	if expression.has("not"):
		# A negated match cannot identify a concrete target.
		return []
	values.sort()
	return values


static func _visible_portraits(observation: Dictionary) -> Array:
	var state := observation.get("state", {}) as Dictionary
	var hud := state.get("hud", {}) as Dictionary
	var result: Array = []
	for value in hud.get("portraits", []):
		if value is Dictionary and bool((value as Dictionary).get("visible", false)):
			result.append(value)
	return result


static func _has_visible_cue_text(observation: Dictionary, markers: Array,
		required_kind := "") -> bool:
	var state := observation.get("state", {}) as Dictionary
	for value in state.get("cues", []):
		if not (value is Dictionary):
			continue
		var cue := value as Dictionary
		if not bool(cue.get("visible", false)) \
				or (required_kind != "" and str(cue.get("kind", "")) != required_kind):
			continue
		var text := "%s %s %s %s" % [
			str(cue.get("text", "")), str(cue.get("state", "")),
			str(cue.get("label", "")), str(cue.get("destination_label", "")),
		]
		var upper := text.to_upper()
		for marker_value in markers:
			if upper.contains(str(marker_value).to_upper()):
				return true
	return false


static func nearest_ground_tokens_to_visible_label(observation: Dictionary,
		markers: Array, exact_interaction_verbs: Array = []) -> Array[String]:
	var state := observation.get("state", {}) as Dictionary
	var label_screens: Array = []
	if exact_interaction_verbs.is_empty():
		for cue_value in state.get("cues", []):
			if not (cue_value is Dictionary) or not bool((cue_value as Dictionary).get(
					"visible", false)) or not _finite_screen((cue_value as Dictionary).get(
					"screen", null)):
				continue
			var text := "%s %s %s" % [
				str((cue_value as Dictionary).get("text", "")),
				str((cue_value as Dictionary).get("label", "")),
				str((cue_value as Dictionary).get("destination_label", "")),
			]
			for marker_value in markers:
				if text.to_upper().contains(str(marker_value).to_upper()):
					label_screens.append((cue_value as Dictionary).get("screen", []))
					break
	# A shipped interaction affordance is itself a visible, clickable world label.
	# The Basin shelter is presented this way (REST PARTY / Shelter) without a
	# duplicate screen-bearing cue, so excluding it would make the learned
	# "nearest" selector disagree with the exact frame the player chose from.
	for affordance_value in state.get("affordances", []):
		if not (affordance_value is Dictionary):
			continue
		var affordance := affordance_value as Dictionary
		if str(affordance.get("kind", "")) != "interact" \
				or not _finite_screen(affordance.get("screen", null)):
			continue
		var verb := str(affordance.get("verb", ""))
		if not exact_interaction_verbs.is_empty():
			if verb in exact_interaction_verbs:
				label_screens.append(affordance.get("screen", []))
			continue
		var text := "%s %s" % [verb, str(affordance.get("consequence", ""))]
		for marker_value in markers:
			if text.to_upper().contains(str(marker_value).to_upper()):
				label_screens.append(affordance.get("screen", []))
				break
	if label_screens.is_empty():
		return []
	var best_distance := INF
	var result: Array[String] = []
	for affordance_value in state.get("affordances", []):
		if not (affordance_value is Dictionary):
			continue
		var affordance := affordance_value as Dictionary
		if str(affordance.get("kind", "")) != "move" \
				or str(affordance.get("consequence", "")).to_upper().contains("NO ROUTE") \
				or not _finite_screen(affordance.get("screen", null)):
			continue
		var distance := _screen_distance_to_any(affordance.get("screen", []), label_screens)
		if distance < best_distance - 0.000001:
			best_distance = distance
			result = [str(affordance.get("token", ""))]
		elif absf(distance - best_distance) <= 0.000001:
			result.append(str(affordance.get("token", "")))
	result.sort()
	return result


static func _screen_distance_to_any(screen_value: Variant, targets: Array) -> float:
	if not _finite_screen(screen_value):
		return INF
	var screen := screen_value as Array
	var best := INF
	for target_value in targets:
		if not _finite_screen(target_value):
			continue
		var target := target_value as Array
		var dx := float(screen[0]) - float(target[0])
		var dy := float(screen[1]) - float(target[1])
		best = minf(best, sqrt(dx * dx + dy * dy))
	return best


static func _finite_screen(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 2:
		return false
	for coordinate in value as Array:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	return true


static func _recompute_nodes(library: Dictionary, minimum_support: int) -> void:
	for raw_node in library.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		if str(node.get("status", "")) == "retired" or bool(node.get("retired", false)):
			node["status"] = "retired"
			node["eligible_for_automation"] = false
			continue
		if not node.has("policy"):
			node["status"] = "legacy_unverified"
			node["eligible_for_automation"] = false
			continue
		var evidence := node.get("evidence", _empty_evidence()) as Dictionary
		var provenance: Array = evidence.get("provenance", [])
		provenance.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str((a as Dictionary).get("record_hash", "")) \
				< str((b as Dictionary).get("record_hash", "")))
		var support_count := 0
		var contradiction_count := 0
		var inadmissible_provenance_count := 0
		var runs := {}
		var fragments := {}
		var personas := {}
		var fingerprints := {}
		var gameplay_builds := {}
		var support_cohort_counts := {}
		var support_cohort_runs := {}
		var support_cohort_traces := {}
		var build_support_counts := {}
		var build_support_runs := {}
		var build_support_traces := {}
		var build_support_contents := {}
		var traces := {}
		for raw_source in provenance:
			if not (raw_source is Dictionary):
				continue
			var source := raw_source as Dictionary
			var source_run := {
				"execution_platform": str(source.get("execution_platform", "")),
				"fragment_id": str(source.get("fragment_id", "")),
				"persona": str(source.get("persona", "")),
				"repeat_index": int(source.get("repeat_index", -1)),
			}
			var expected_cohort_size := Trace.expected_validation_cohort(source_run).size()
			if str(source.get("source_trace_schema", "")) != Trace.TRACE_SCHEMA \
					or not ContentFingerprint.is_supported_schema(str(
						source.get("content_fingerprint_schema", ""))) \
					or not _valid_sha256_text(str(source.get("content_fingerprint", "")) \
					) \
					or not ContentFingerprint.is_supported_gameplay_build_schema(str(
						source.get("gameplay_build_fingerprint_schema", ""))) \
					or not _valid_sha256_text(str(source.get(
						"gameplay_build_fingerprint", ""))) \
					or int(source.get("repeat_index", -1)) < 0 \
					or not bool(source.get("trace_integrity_verified", false)) \
					or str(source.get("summary_record_hash", "")) == "" \
					or not bool(source.get("trace_complete", false)) \
					or not bool(source.get("persona_goal_reached", false)) \
					or str(source.get("validation_record_hash", "")) == "" \
					or str(source.get("validation_schema", "")) \
						!= Trace.VALIDATION_SCHEMA \
					or not bool(source.get("validation_passed", false)) \
					or int(source.get("validation_failure_count", -1)) != 0 \
					or int(source.get("validation_check_count", -1)) < 1 \
					or int(source.get("run_decision_count", -1)) < 1 \
					or int(source.get("validation_checked_decision_count", -1)) \
						!= int(source.get("run_decision_count", -1)) \
					or int(source.get("validation_contract_version", -1)) \
						!= Trace.CURRENT_VALIDATION_CONTRACT_VERSION \
					or str(source.get("validation_contract_id", "")) \
						!= Trace.current_validation_contract_id(source_run) \
					or str(source.get("validation_validator_id", "")) \
						!= Trace.current_validation_validator_id(str(
							source.get("execution_platform", ""))) \
					or str(source.get("validation_execution_platform", "")) \
						!= str(source.get("execution_platform", "")) \
					or str(source.get("validation_invocation_id", "")) == "":
				inadmissible_provenance_count += 1
				continue
			if str(source.get("invocation_manifest_hash", "")) == "" \
					or str(source.get("invocation_manifest_schema", "")) \
						!= Trace.INVOCATION_MANIFEST_SCHEMA \
					or not bool(source.get("invocation_manifest_passed", false)) \
					or int(source.get("invocation_manifest_failure_count", -1)) != 0 \
					or expected_cohort_size < 1 \
					or int(source.get("invocation_cohort_size", 0)) != expected_cohort_size:
				inadmissible_provenance_count += 1
				continue
			var content_key := "%s|%s" % [
				str(source.get("content_fingerprint_schema", "")),
				str(source.get("content_fingerprint", "")),
			]
			var build_key := "%s|%s" % [
				str(source.get("gameplay_build_fingerprint_schema", "")),
				str(source.get("gameplay_build_fingerprint", "")),
			]
			var support_cohort_key := "%s|%s" % [content_key, build_key]
			if str(source.get("verdict", "")) == "supports":
				support_count += 1
				support_cohort_counts[support_cohort_key] = int(
					support_cohort_counts.get(support_cohort_key, 0)) + 1
				if not support_cohort_runs.has(support_cohort_key):
					support_cohort_runs[support_cohort_key] = {}
				if not support_cohort_traces.has(support_cohort_key):
					support_cohort_traces[support_cohort_key] = {}
				(support_cohort_runs[support_cohort_key] as Dictionary)[str(
					source.get("run_id", ""))] = true
				(support_cohort_traces[support_cohort_key] as Dictionary)[str(
					source.get("trace_id", ""))] = true
				build_support_counts[build_key] = int(build_support_counts.get(
					build_key, 0)) + 1
				if not build_support_runs.has(build_key):
					build_support_runs[build_key] = {}
				if not build_support_traces.has(build_key):
					build_support_traces[build_key] = {}
				if not build_support_contents.has(build_key):
					build_support_contents[build_key] = {}
				(build_support_runs[build_key] as Dictionary)[str(
					source.get("run_id", ""))] = true
				(build_support_traces[build_key] as Dictionary)[str(
					source.get("trace_id", ""))] = true
				(build_support_contents[build_key] as Dictionary)[content_key] = true
			else:
				contradiction_count += 1
			runs[str(source.get("run_id", ""))] = true
			fragments[str(source.get("fragment_id", ""))] = true
			personas[str(source.get("persona", ""))] = true
			fingerprints[content_key] = true
			gameplay_builds[build_key] = true
			traces[str(source.get("trace_id", ""))] = true
		evidence["provenance"] = provenance
		evidence["support_count"] = support_count
		evidence["contradiction_count"] = contradiction_count
		evidence["distinct_run_count"] = _nonempty_key_count(runs)
		evidence["distinct_fragment_count"] = _nonempty_key_count(fragments)
		evidence["distinct_persona_count"] = _nonempty_key_count(personas)
		evidence["distinct_content_count"] = _nonempty_key_count(fingerprints)
		evidence["distinct_gameplay_build_count"] = _nonempty_key_count(
			gameplay_builds)
		evidence["distinct_support_cohort_count"] = support_cohort_counts.size()
		var max_support_cohort_count := 0
		for count_value in support_cohort_counts.values():
			max_support_cohort_count = maxi(max_support_cohort_count,
				int(count_value))
		evidence["max_support_cohort_count"] = max_support_cohort_count
		evidence["distinct_trace_count"] = _nonempty_key_count(traces)
		evidence["inadmissible_provenance_count"] = inadmissible_provenance_count
		node["evidence"] = evidence
		var scope := str((node.get("policy", {}) as Dictionary).get("scope", "global"))
		var same_build_support_qualified := false
		if scope == "global":
			for build_key_value in build_support_counts.keys():
				var build_key := str(build_key_value)
				if int(build_support_counts[build_key]) >= minimum_support \
						and _nonempty_key_count(build_support_runs.get(
							build_key, {}) as Dictionary) >= minimum_support \
						and _nonempty_key_count(build_support_traces.get(
							build_key, {}) as Dictionary) >= minimum_support \
						and _nonempty_key_count(build_support_contents.get(
							build_key, {}) as Dictionary) >= minimum_support:
					same_build_support_qualified = true
					break
		else:
			for cohort_key_value in support_cohort_counts.keys():
				var cohort_key := str(cohort_key_value)
				if int(support_cohort_counts[cohort_key]) >= minimum_support \
						and _nonempty_key_count(support_cohort_runs.get(
							cohort_key, {}) as Dictionary) >= minimum_support \
						and _nonempty_key_count(support_cohort_traces.get(
							cohort_key, {}) as Dictionary) >= minimum_support:
					same_build_support_qualified = true
					break
		var validated := same_build_support_qualified and contradiction_count == 0
		node["status"] = "validated" if validated else "candidate"
		node["eligible_for_automation"] = validated


static func _build_trees(nodes: Array) -> Dictionary:
	var by_persona := {}
	for raw_node in nodes:
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		if not bool(node.get("eligible_for_automation", false)) \
				or not (node.get("policy", null) is Dictionary):
			continue
		for raw_persona in node.get("personas", []):
			var persona := str(raw_persona)
			if persona == "":
				continue
			if not by_persona.has(persona):
				by_persona[persona] = []
			(by_persona[persona] as Array).append(node)
	var trees := {}
	var persona_ids: Array[String] = []
	for key in by_persona.keys():
		persona_ids.append(str(key))
	persona_ids.sort()
	for persona in persona_ids:
		var persona_nodes: Array = by_persona[persona]
		persona_nodes.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ap := int(((a as Dictionary).get("policy", {}) as Dictionary).get("priority", 50))
			var bp := int(((b as Dictionary).get("policy", {}) as Dictionary).get("priority", 50))
			if ap != bp:
				return ap > bp
			return str((a as Dictionary).get("id", "")) < str((b as Dictionary).get("id", "")))
		var ordered: Array = []
		var tree_nodes := {}
		for raw_node in persona_nodes:
			var node := raw_node as Dictionary
			var node_id := str(node.get("id", ""))
			ordered.append(node_id)
			tree_nodes[node_id] = {
				"when": (node.get("policy", {}) as Dictionary).get("condition", {}),
				"choose": (node.get("policy", {}) as Dictionary).get("action", {}),
				"expect": (node.get("policy", {}) as Dictionary).get("expected", {}),
				"scope": (node.get("policy", {}) as Dictionary).get("scope", "global"),
				"priority": (node.get("policy", {}) as Dictionary).get("priority", 50),
				"evidence": {
					"support_count": (node.get("evidence", {}) as Dictionary).get("support_count", 0),
					"distinct_run_count": (node.get("evidence", {}) as Dictionary).get(
						"distinct_run_count", 0),
				},
			}
		trees[persona] = {
			"schema": TREE_SCHEMA,
			"evaluation_order": ordered,
			"nodes": tree_nodes,
		}
	return trees


static func _migrate_library(existing_library: Dictionary) -> Dictionary:
	var library: Dictionary = Trace.json_safe(existing_library)
	if library.is_empty():
		library = {"nodes": []}
	if not (library.get("nodes", null) is Array):
		library["nodes"] = []
	library["schema"] = LIBRARY_SCHEMA
	library["contract"] = _current_library_contract()
	if not (library.get("rejected_evidence", null) is Array):
		library["rejected_evidence"] = []
	for raw_node in library["nodes"]:
		if not (raw_node is Dictionary):
			continue
		var node := raw_node as Dictionary
		if node.has("retired"):
			node["status"] = "retired"
		else:
			node["status"] = str(node.get("status", "legacy_unverified"))
		if node.get("policy", null) is Dictionary:
			var policy := node.get("policy", {}) as Dictionary
			var canonical_policy := policy.duplicate(true)
			canonical_policy["condition"] = canonicalize_predicate(
				policy.get("condition"))
			canonical_policy["expected"] = canonicalize_predicate(
				policy.get("expected"))
			node["policy"] = canonical_policy
			node["policy_signature"] = canonical_hash(canonical_policy)
		if not node.has("policy"):
			node["eligible_for_automation"] = false
		if not (node.get("evidence", null) is Dictionary):
			node["evidence"] = _empty_evidence()
		var evidence := node["evidence"] as Dictionary
		for evidence_key in _empty_evidence().keys():
			if not evidence.has(evidence_key):
				evidence[evidence_key] = _empty_evidence()[evidence_key]
		for count_key in EVIDENCE_COUNT_FIELDS:
			evidence[count_key] = int(evidence.get(count_key, 0))
		var provenance: Array = evidence.get("provenance", [])
		for raw_source in provenance:
			if raw_source is Dictionary:
				var source := raw_source as Dictionary
				source["decision_index"] = int(source.get("decision_index", -1))
				source["seed"] = int(source.get("seed", 0))
		if node.has("source") and not evidence.has("legacy_sources"):
			evidence["legacy_sources"] = [str(node.get("source", ""))]
		node["evidence"] = evidence
	return library


static func _current_library_contract() -> Dictionary:
	return {
		"source_trace_schema": Trace.TRACE_SCHEMA,
		"player_observation_schema": Trace.PLAYER_OBSERVATION_SCHEMA,
		"gameplay_build_fingerprint_schema": ContentFingerprint.GAMEPLAY_BUILD_SCHEMA,
		"learning_boundary": "shipped_player_input_with_observable_feedback",
		"activation": "repeated_support_from_distinct_hash_verified_trace_complete_derived_persona_goal_runs_in_a_complete_invocation_cohort_with_zero_contradictions",
		"legacy_policy": "older provenance remains visible but cannot execute until re-earned by v3 evidence",
	}


static func _empty_evidence() -> Dictionary:
	return {
		"support_count": 0,
		"contradiction_count": 0,
		"distinct_run_count": 0,
		"distinct_fragment_count": 0,
		"distinct_persona_count": 0,
		"distinct_content_count": 0,
		"distinct_gameplay_build_count": 0,
		"distinct_support_cohort_count": 0,
		"max_support_cohort_count": 0,
		"distinct_trace_count": 0,
		"inadmissible_provenance_count": 0,
		"provenance": [],
	}


static func _node_index(nodes: Array) -> Dictionary:
	var index := {}
	for raw_node in nodes:
		if raw_node is Dictionary:
			var node_id := str((raw_node as Dictionary).get("id", ""))
			if node_id != "":
				index[node_id] = raw_node
	return index


static func _rejected_index(items: Array) -> Dictionary:
	var index := {}
	for raw_item in items:
		if raw_item is Dictionary:
			var item := raw_item as Dictionary
			var key := str(item.get("key", canonical_hash(item)))
			item["key"] = key
			index[key] = item
	return index


static func _add_rejection(rejected: Dictionary, rejection: Dictionary) -> void:
	var key := str(rejection.get("key", canonical_hash(rejection)))
	rejection["key"] = key
	rejected[key] = Trace.json_safe(rejection)


static func _rejection_from_record(record: Dictionary, reason: String, details: Array) -> Dictionary:
	var run := record.get("run", {}) as Dictionary
	var record_hash := str(record.get("record_hash", ""))
	return {
		"key": "%s:%s" % [reason, record_hash],
		"reason": reason,
		"details": details,
		"record_hash": record_hash,
		"trace_id": str(run.get("trace_id", "")),
		"run_id": str(run.get("run_id", "")),
		"decision_index": int(record.get("decision_index", -1)),
		"persona": str(run.get("persona", "")),
		"fragment_id": str(run.get("fragment_id", "")),
	}


static func _predicate_shape_valid(predicate: Variant) -> bool:
	if not (predicate is Dictionary):
		return false
	var expression := predicate as Dictionary
	if expression.has("all") or expression.has("any"):
		var key := "all" if expression.has("all") else "any"
		if not (expression[key] is Array) or (expression[key] as Array).is_empty():
			return false
		for child in expression[key]:
			if not _predicate_shape_valid(child):
				return false
		return true
	if expression.has("not"):
		return _predicate_shape_valid(expression["not"])
	return str(expression.get("path", "")) != "" \
		and str(expression.get("op", "")) in CONDITION_OPERATORS \
		and (expression.has("value") or str(expression.get("op", "")) == "exists")


static func _lookup(root: Variant, path: String) -> Dictionary:
	var current: Variant = root
	for component in path.split(".", false):
		if current is Dictionary:
			if not (current as Dictionary).has(component):
				return {"found": false}
			current = (current as Dictionary)[component]
		elif current is Array and component.is_valid_int():
			var index := int(component)
			if index < 0 or index >= (current as Array).size():
				return {"found": false}
			current = (current as Array)[index]
		else:
			return {"found": false}
	return {"found": true, "value": current}


static func _equivalent(a: Variant, b: Variant) -> bool:
	return Trace.canonical_equal(a, b)


static func _valid_node_id(node_id: String) -> bool:
	if node_id == "" or node_id.begins_with("_") or node_id.ends_with("_"):
		return false
	for index in range(node_id.length()):
		var code := node_id.unicode_at(index)
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return not node_id.contains("__")


static func _valid_sha256_text(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


static func _nonempty_key_count(values: Dictionary) -> int:
	var count := 0
	for key in values.keys():
		if str(key) != "":
			count += 1
	return count


static func _eligible_node_count(nodes: Array) -> int:
	var count := 0
	for raw_node in nodes:
		if raw_node is Dictionary and bool((raw_node as Dictionary).get(
				"eligible_for_automation", false)):
			count += 1
	return count
