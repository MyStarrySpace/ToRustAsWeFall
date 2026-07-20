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
var _preparation_was_unlocked := false
var _objectives_complete := false


func configure(
		required_observation_count: int,
		required_actor_ids: Array,
		valid_preparation_choices: Array,
		protocol_order: Array,
		protocol_definitions: Dictionary,
		site_definitions: Dictionary
	) -> void:
	survey.configure(required_observation_count, required_actor_ids)
	protocols.configure(protocol_order, protocol_definitions, site_definitions)
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
	if not protocols.start():
		return false
	selected_preparation = choice_id
	preparation_selected.emit(choice_id)
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
	pass


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
		"preparation_unlocked": _preparation_was_unlocked,
		"protocols": protocols.snapshot(),
		"objectives_complete": _objectives_complete,
	}


func _restore_state(state: Dictionary) -> void:
	survey.restore(state.get("survey", {}))
	selected_preparation = str(state.get("selected_preparation", ""))
	_preparation_was_unlocked = bool(state.get("preparation_unlocked", survey.is_complete()))
	protocols.restore(state.get("protocols", {}))
	_objectives_complete = bool(state.get("objectives_complete", protocols.is_complete()))
