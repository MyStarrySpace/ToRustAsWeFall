@abstract
class_name StoryBeat
extends RefCounted

## Inheritable lifecycle contract for one narrative/gameplay beat.
##
## Override the protected `_on_*` hooks; callers and runners use the stable public
## methods. Mechanics should be composed into a beat rather than reimplemented by
## subclasses. This keeps the contract small enough that a future native-backed
## implementation can mirror it without coupling gameplay to a scene script.

signal entered(beat_id: StringName)
signal exited(beat_id: StringName, reason: StringName)
signal changed(beat_id: StringName)
signal completion_requested(beat_id: StringName, outcome: Dictionary)
signal transition_requested(from_beat: StringName, to_beat: StringName, payload: Dictionary)

var beat_id: StringName
var _context: StoryBeatContext
var _active := false
var _complete := false


func _init(id: StringName = &"") -> void:
	beat_id = id


func validation_errors(context: StoryBeatContext) -> PackedStringArray:
	var errors := PackedStringArray()
	if beat_id == &"":
		errors.append("Story beat id cannot be empty.")
	if context == null:
		errors.append("Story beat '%s' has no context." % beat_id)
	else:
		errors.append_array(_validation_errors(context))
	return errors


func enter(context: StoryBeatContext, payload: Dictionary = {}) -> bool:
	if _active or not validation_errors(context).is_empty():
		return false
	_context = context
	_active = true
	_on_entered(payload)
	entered.emit(beat_id)
	return true


func exit(reason: StringName = &"transition") -> void:
	if not _active:
		return
	_on_exiting(reason)
	_active = false
	exited.emit(beat_id, reason)
	_context = null


func update(delta: float) -> void:
	if _active:
		_on_updated(delta)


func handle_event(event_id: StringName, payload: Dictionary = {}) -> bool:
	return _on_event_received(event_id, payload) if _active else false


func is_active() -> bool:
	return _active


func is_complete() -> bool:
	return _complete


func complete(outcome: Dictionary = {}) -> void:
	if not _active or _complete:
		return
	_complete = true
	mark_changed()
	completion_requested.emit(beat_id, outcome.duplicate(true))


func request_transition(next_beat_id: StringName, payload: Dictionary = {}) -> void:
	if _active and next_beat_id != &"":
		transition_requested.emit(beat_id, next_beat_id, payload.duplicate(true))


func reset() -> void:
	if _active:
		exit(&"reset")
	_complete = false
	_on_reset()


func snapshot() -> Dictionary:
	return {
		"beat_id": str(beat_id),
		"active": _active,
		"complete": _complete,
		"state": _snapshot_state(),
	}


func restore(snapshot_data: Dictionary) -> void:
	_complete = bool(snapshot_data.get("complete", false))
	_restore_state(snapshot_data.get("state", {}))


func mark_changed() -> void:
	changed.emit(beat_id)


# Protected extension points. Subclasses override only what they need.
func _validation_errors(_candidate_context: StoryBeatContext) -> PackedStringArray:
	return PackedStringArray()


@abstract func _on_entered(payload: Dictionary) -> void


func _on_exiting(_reason: StringName) -> void:
	pass


func _on_updated(_delta: float) -> void:
	pass


func _on_event_received(_event_id: StringName, _payload: Dictionary) -> bool:
	return false


func _on_reset() -> void:
	pass


func _snapshot_state() -> Dictionary:
	return {}


func _restore_state(_state: Dictionary) -> void:
	pass
