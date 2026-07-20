class_name EvidenceDecisionSequence
extends RefCounted

## Data-driven causal puzzle model: gather evidence, choose a response, execute
## the consequence, then advance to the next protocol.
##
## Scenes provide authored protocol/site data and own presentation. This class owns
## only deterministic rules and state, so the same loop can drive terminals,
## environmental surveys, repairs, investigations, or dialogue encounters.

signal progress_changed
signal protocol_changed(from_protocol: String, to_protocol: String)
signal completed

const COMPLETE_PROTOCOL := "complete"

var _protocol_order: Array[String] = []
var _protocols: Dictionary = {}
var _sites: Dictionary = {}
var _current_protocol := ""
var _evidence: Dictionary = {}
var _choices: Dictionary = {}
var _completed_protocols: Dictionary = {}
var _findings: Array[String] = []


func _init(protocol_order: Array = [], protocols: Dictionary = {}, sites: Dictionary = {}) -> void:
	configure(protocol_order, protocols, sites)


func configure(protocol_order: Array, protocols: Dictionary, sites: Dictionary) -> void:
	_protocol_order.clear()
	for protocol_id_variant in protocol_order:
		var protocol_id := str(protocol_id_variant)
		if protocol_id != "" and not _protocol_order.has(protocol_id):
			_protocol_order.append(protocol_id)
	_protocols = protocols.duplicate(true)
	_sites = sites.duplicate(true)
	reset()


func reset() -> void:
	_current_protocol = ""
	_evidence.clear()
	_choices.clear()
	_completed_protocols.clear()
	_findings.clear()


func start(protocol_id := "") -> bool:
	if _current_protocol != "" and _current_protocol != COMPLETE_PROTOCOL:
		return false
	var first_protocol := protocol_id
	if first_protocol == "" and not _protocol_order.is_empty():
		first_protocol = _protocol_order[0]
	if not _protocols.has(first_protocol):
		return false
	var previous := _current_protocol
	_current_protocol = first_protocol
	_ensure_evidence_bucket(first_protocol)
	protocol_changed.emit(previous, _current_protocol)
	progress_changed.emit()
	return true


func current_protocol() -> String:
	return _current_protocol


func is_complete() -> bool:
	return not _protocol_order.is_empty() \
		and _completed_protocols.size() >= _protocol_order.size()


func completed_count() -> int:
	return _completed_protocols.size()


func evidence_count(protocol_id := "") -> int:
	var resolved_protocol := protocol_id if protocol_id != "" else _current_protocol
	return (_evidence.get(resolved_protocol, {}) as Dictionary).size()


func required_evidence_count(protocol_id := "") -> int:
	var resolved_protocol := protocol_id if protocol_id != "" else _current_protocol
	var protocol: Dictionary = _protocols.get(resolved_protocol, {})
	return (protocol.get("evidence", []) as Array).size()


func is_site_available(site_id: String, actor_id := "") -> bool:
	if _current_protocol == "" or _current_protocol == COMPLETE_PROTOCOL:
		return false
	var site: Dictionary = _sites.get(site_id, {})
	if site.is_empty() or str(site.get("protocol", "")) != _current_protocol:
		return false
	var required_actor := str(site.get("role", ""))
	if actor_id != "" and required_actor != "" and actor_id != required_actor:
		return false
	var protocol: Dictionary = _protocols.get(_current_protocol, {})
	var kind := str(site.get("kind", ""))
	match kind:
		"evidence":
			return (protocol.get("evidence", []) as Array).has(site_id) \
				and not bool((_evidence.get(_current_protocol, {}) as Dictionary).get(site_id, false))
		"choice":
			return (protocol.get("choices", []) as Array).has(site_id) \
				and evidence_count() >= required_evidence_count() \
				and not _choices.has(_current_protocol)
		"resolution":
			var choice_id := str(_choices.get(_current_protocol, ""))
			var resolutions: Dictionary = protocol.get("resolution_sites", {})
			return choice_id != "" and str(resolutions.get(choice_id, "")) == site_id \
				and not bool(_completed_protocols.get(_current_protocol, false))
	return false


## Attempts one site action and returns a structured result suitable for UI,
## logging, tests, or networking. Rejected actions never mutate state.
func submit(site_id: String, actor_id := "") -> Dictionary:
	var result := {
		"accepted": false,
		"reason": "site_unavailable",
		"site_id": site_id,
		"protocol": _current_protocol,
		"kind": "",
		"protocol_completed": "",
		"sequence_completed": is_complete(),
	}
	if not _sites.has(site_id):
		result["reason"] = "unknown_site"
		return result
	var site: Dictionary = _sites[site_id]
	result["kind"] = str(site.get("kind", ""))
	var required_actor := str(site.get("role", ""))
	if required_actor != "" and actor_id != required_actor:
		result["reason"] = "wrong_actor"
		return result
	if not is_site_available(site_id, actor_id):
		return result

	var protocol_id := _current_protocol
	match str(result["kind"]):
		"evidence":
			var protocol_evidence := _ensure_evidence_bucket(protocol_id)
			protocol_evidence[site_id] = true
			_evidence[protocol_id] = protocol_evidence
		"choice":
			_choices[protocol_id] = site_id
		"resolution":
			_completed_protocols[protocol_id] = true
			result["protocol_completed"] = protocol_id
	_findings.append(site_id)
	result["accepted"] = true
	result["reason"] = ""

	if str(result["kind"]) == "resolution":
		_advance_after(protocol_id)
	result["sequence_completed"] = is_complete()
	progress_changed.emit()
	return result


func available_site_ids(actor_id := "") -> Array[String]:
	var available: Array[String] = []
	for site_id_variant in _sites.keys():
		var site_id := str(site_id_variant)
		if is_site_available(site_id, actor_id):
			available.append(site_id)
	return available


func evidence_snapshot() -> Dictionary:
	return _evidence.duplicate(true)


func choices_snapshot() -> Dictionary:
	return _choices.duplicate()


func completed_protocols_snapshot() -> Dictionary:
	return _completed_protocols.duplicate()


func findings() -> Array[String]:
	return _findings.duplicate()


func snapshot() -> Dictionary:
	return {
		"current_protocol": _current_protocol,
		"evidence": evidence_snapshot(),
		"choices": choices_snapshot(),
		"completed_protocols": completed_protocols_snapshot(),
		"completed_count": completed_count(),
		"findings": findings(),
		"available_site_ids": available_site_ids(),
		"complete": is_complete(),
	}


## Restores progress into an already configured sequence. Authored definitions stay
## code/asset-owned; save data contains only deterministic runtime state.
func restore(snapshot_data: Dictionary) -> void:
	_current_protocol = str(snapshot_data.get("current_protocol", ""))
	_evidence = (snapshot_data.get("evidence", {}) as Dictionary).duplicate(true)
	_choices = (snapshot_data.get("choices", {}) as Dictionary).duplicate()
	_completed_protocols = (
		snapshot_data.get("completed_protocols", {}) as Dictionary
	).duplicate()
	_findings.clear()
	for finding_variant in snapshot_data.get("findings", []):
		_findings.append(str(finding_variant))
	if _current_protocol != "" and _current_protocol != COMPLETE_PROTOCOL:
		_ensure_evidence_bucket(_current_protocol)


## Returns authoring errors without mutating play state. Scene import checks and
## editor tooling can surface these before a player reaches an impossible puzzle.
func configuration_errors() -> Array[String]:
	var errors: Array[String] = []
	for protocol_id in _protocol_order:
		if not _protocols.has(protocol_id):
			errors.append("Missing protocol '%s'." % protocol_id)
			continue
		var protocol: Dictionary = _protocols[protocol_id]
		for evidence_id_variant in protocol.get("evidence", []):
			_validate_site(errors, protocol_id, str(evidence_id_variant), "evidence")
		for choice_id_variant in protocol.get("choices", []):
			var choice_id := str(choice_id_variant)
			_validate_site(errors, protocol_id, choice_id, "choice")
			var resolution_id := str((protocol.get("resolution_sites", {}) as Dictionary).get(choice_id, ""))
			if resolution_id == "":
				errors.append("Protocol '%s' has no resolution for choice '%s'." % [protocol_id, choice_id])
			else:
				_validate_site(errors, protocol_id, resolution_id, "resolution")
	return errors


func _ensure_evidence_bucket(protocol_id: String) -> Dictionary:
	if not _evidence.has(protocol_id):
		_evidence[protocol_id] = {}
	return _evidence[protocol_id]


func _advance_after(protocol_id: String) -> void:
	var previous := protocol_id
	var protocol_index := _protocol_order.find(protocol_id)
	if protocol_index >= 0 and protocol_index + 1 < _protocol_order.size():
		_current_protocol = _protocol_order[protocol_index + 1]
		_ensure_evidence_bucket(_current_protocol)
	else:
		_current_protocol = COMPLETE_PROTOCOL
	protocol_changed.emit(previous, _current_protocol)
	if _current_protocol == COMPLETE_PROTOCOL:
		completed.emit()


func _validate_site(errors: Array[String], protocol_id: String, site_id: String, expected_kind: String) -> void:
	if not _sites.has(site_id):
		errors.append("Protocol '%s' references missing site '%s'." % [protocol_id, site_id])
		return
	var site: Dictionary = _sites[site_id]
	if str(site.get("protocol", "")) != protocol_id:
		errors.append("Site '%s' belongs to '%s', expected '%s'." % [
			site_id, str(site.get("protocol", "")), protocol_id,
		])
	if str(site.get("kind", "")) != expected_kind:
		errors.append("Site '%s' is '%s', expected '%s'." % [
			site_id, str(site.get("kind", "")), expected_kind,
		])
