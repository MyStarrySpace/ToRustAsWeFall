class_name StoryBeatRunner
extends RefCounted

## Owns registration and lifecycle transitions for StoryBeat instances.
## It deliberately knows nothing about dialogue, cameras, levels, or actors.

signal beat_changed(from_beat: StringName, to_beat: StringName)
signal beat_completed(beat_id: StringName, outcome: Dictionary)
signal beat_rejected(beat_id: StringName, errors: PackedStringArray)

var _context: StoryBeatContext
var _beats: Dictionary = {}
var _active_beat: StoryBeat


func setup(context: StoryBeatContext) -> void:
	_context = context


func register_beat(beat: StoryBeat) -> bool:
	if beat == null or beat.beat_id == &"" or _beats.has(beat.beat_id):
		return false
	_beats[beat.beat_id] = beat
	beat.completion_requested.connect(_on_beat_completion_requested)
	beat.transition_requested.connect(_on_beat_transition_requested)
	return true


func unregister_beat(beat_id: StringName) -> void:
	var beat := _beats.get(beat_id) as StoryBeat
	if beat == null:
		return
	if beat == _active_beat:
		deactivate(&"unregistered")
	if beat.completion_requested.is_connected(_on_beat_completion_requested):
		beat.completion_requested.disconnect(_on_beat_completion_requested)
	if beat.transition_requested.is_connected(_on_beat_transition_requested):
		beat.transition_requested.disconnect(_on_beat_transition_requested)
	_beats.erase(beat_id)


func has_beat(beat_id: StringName) -> bool:
	return _beats.has(beat_id)


func beat(beat_id: StringName) -> StoryBeat:
	return _beats.get(beat_id) as StoryBeat


func active_beat() -> StoryBeat:
	return _active_beat


func active_beat_id() -> StringName:
	return _active_beat.beat_id if _active_beat != null else &""


func transition_to(beat_id: StringName, payload: Dictionary = {}) -> bool:
	var next_beat := beat(beat_id)
	if next_beat == null:
		return false
	if next_beat == _active_beat:
		return true
	var errors := next_beat.validation_errors(_context)
	if not errors.is_empty():
		beat_rejected.emit(beat_id, errors)
		return false
	var previous_id := active_beat_id()
	if _active_beat != null:
		_active_beat.exit(&"transition")
	_active_beat = next_beat
	if not _active_beat.enter(_context, payload):
		_active_beat = null
		return false
	beat_changed.emit(previous_id, beat_id)
	return true


func deactivate(reason: StringName = &"step_changed") -> void:
	if _active_beat == null:
		return
	var previous_id := _active_beat.beat_id
	_active_beat.exit(reason)
	_active_beat = null
	beat_changed.emit(previous_id, &"")


func update(delta: float) -> void:
	if _active_beat != null:
		_active_beat.update(delta)


func handle_event(event_id: StringName, payload: Dictionary = {}) -> bool:
	return _active_beat.handle_event(event_id, payload) if _active_beat != null else false


func reset_all() -> void:
	deactivate(&"reset")
	for registered_beat in _beats.values():
		(registered_beat as StoryBeat).reset()


func snapshot() -> Dictionary:
	var beat_snapshots := {}
	for beat_id_variant in _beats.keys():
		var registered_beat := _beats[beat_id_variant] as StoryBeat
		beat_snapshots[str(beat_id_variant)] = registered_beat.snapshot()
	return {
		"active_beat_id": str(active_beat_id()),
		"beats": beat_snapshots,
	}


func _on_beat_completion_requested(beat_id: StringName, outcome: Dictionary) -> void:
	if _active_beat != null and _active_beat.beat_id == beat_id:
		beat_completed.emit(beat_id, outcome)


func _on_beat_transition_requested(
		from_beat: StringName,
		to_beat: StringName,
		payload: Dictionary
	) -> void:
	if _active_beat != null and _active_beat.beat_id == from_beat:
		transition_to(to_beat, payload)
