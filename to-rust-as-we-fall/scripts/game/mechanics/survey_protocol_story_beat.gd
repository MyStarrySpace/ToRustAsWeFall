class_name SurveyProtocolStoryBeat
extends StoryBeat

## Reusable story beat composed from a multi-actor survey and an
## evidence -> decision -> execution protocol sequence.

signal survey_progressed
signal preparation_unlocked
signal preparation_selected(choice_id: String)
signal protocol_action_resolved(result: Dictionary)
signal objectives_completed

var survey := MultiActorSurvey.new()
var protocols := EvidenceDecisionSequence.new()
var preparation_choices: Array[String] = []
var selected_preparation := ""
var _preparation_only := false
var _preparation_was_unlocked := false
var _objectives_complete := false


func configure(
		required_observation_count: int,
		required_actor_ids: Array,
		valid_preparation_choices: Array,
		protocol_order: Array,
		protocol_definitions: Dictionary,
		site_definitions: Dictionary,
		preparation_only := false
	) -> void:
	survey.configure(required_observation_count, required_actor_ids)
	protocols.configure(protocol_order, protocol_definitions, site_definitions)
	_preparation_only = preparation_only
	preparation_choices.clear()
	for choice_id_variant in valid_preparation_choices:
		var choice_id := str(choice_id_variant)
		if choice_id != "" and not preparation_choices.has(choice_id):
			preparation_choices.append(choice_id)
	selected_preparation = ""
	_preparation_was_unlocked = false
	_objectives_complete = false


func record_observation(observation_id: String, actor_id: String) -> bool:
	if not is_active():
		return false
	var changed_progress := survey.record(observation_id, actor_id)
	if not changed_progress:
		return false
	survey_progressed.emit()
	if survey.is_complete() and not _preparation_was_unlocked:
		_preparation_was_unlocked = true
		preparation_unlocked.emit()
	mark_changed()
	return true


func choose_preparation(choice_id: String) -> bool:
	if not is_active() or selected_preparation != "" or not survey.is_complete() \
			or not preparation_choices.has(choice_id):
		return false
	if not _preparation_only and not protocols.start():
		return false
	selected_preparation = choice_id
	preparation_selected.emit(choice_id)
	# Some beats need one informed physical choice, not a mandatory evidence
	# currency loop. With no protocols configured, that choice is the objective.
	if _preparation_only:
		_objectives_complete = true
		objectives_completed.emit()
	mark_changed()
	return true


func submit_protocol_site(site_id: String, actor_id := "") -> Dictionary:
	if not is_active() or selected_preparation == "":
		return {
			"accepted": false,
			"reason": "beat_unavailable",
			"site_id": site_id,
		}
	var result := protocols.submit(site_id, actor_id)
	if not bool(result.get("accepted", false)):
		return result
	protocol_action_resolved.emit(result.duplicate(true))
	if protocols.is_complete() and not _objectives_complete:
		_objectives_complete = true
		objectives_completed.emit()
	mark_changed()
	return result


func survey_ready() -> bool:
	return survey.is_complete()


func preparation_ready() -> bool:
	return survey.is_complete() and selected_preparation == ""


func objectives_are_complete() -> bool:
	return _objectives_complete


func is_protocol_site_available(site_id: String, actor_id := "") -> bool:
	return protocols.is_site_available(site_id, actor_id)


func _on_entered(_payload: Dictionary) -> void:
	# A zero-requirement survey means optional observations. Surface the real
	# decision immediately while those world-building reads remain available.
	if survey.is_complete() and not _preparation_was_unlocked:
		_preparation_was_unlocked = true
		preparation_unlocked.emit()


func _validation_errors(_candidate_context: StoryBeatContext) -> PackedStringArray:
	var errors := PackedStringArray()
	for protocol_error in protocols.configuration_errors():
		errors.append(protocol_error)
	if _preparation_only:
		if protocols.has_protocols() or protocols.authored_definition_count() > 0 \
				or protocols.authored_site_count() > 0:
			errors.append("Preparation-only beat '%s' cannot contain protocol or site definitions." % beat_id)
	elif not protocols.has_protocols():
		errors.append("Story beat '%s' requires a protocol order unless preparation_only is explicit." % beat_id)
	return errors


func _on_reset() -> void:
	survey.reset()
	protocols.reset()
	selected_preparation = ""
	_preparation_was_unlocked = false
	_objectives_complete = false


func _snapshot_state() -> Dictionary:
	return {
		"survey": survey.snapshot(),
		"selected_preparation": selected_preparation,
		"preparation_only": _preparation_only,
		"preparation_unlocked": _preparation_was_unlocked,
		"protocols": protocols.snapshot(),
		"objectives_complete": _objectives_complete,
	}


func _restore_state(state: Dictionary) -> void:
	survey.restore(state.get("survey", {}))
	selected_preparation = str(state.get("selected_preparation", ""))
	_preparation_only = bool(state.get("preparation_only", _preparation_only))
	_preparation_was_unlocked = bool(state.get("preparation_unlocked", survey.is_complete()))
	protocols.restore(state.get("protocols", {}))
	_objectives_complete = bool(state.get(
		"objectives_complete",
		protocols.is_complete() or (selected_preparation != "" and _preparation_only)
	))
