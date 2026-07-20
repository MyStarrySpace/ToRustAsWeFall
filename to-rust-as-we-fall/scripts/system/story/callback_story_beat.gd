class_name CallbackStoryBeat
extends StoryBeat

## Concrete StoryBeat adapter for small beats whose behavior is best expressed as
## injected functions. Larger or stateful beats should subclass StoryBeat directly.

var on_enter := Callable()
var on_exit := Callable()
var on_update := Callable()
var on_event := Callable()
var on_validate := Callable()


func configure_callbacks(callbacks: Dictionary) -> CallbackStoryBeat:
	on_enter = callbacks.get("enter", Callable())
	on_exit = callbacks.get("exit", Callable())
	on_update = callbacks.get("update", Callable())
	on_event = callbacks.get("event", Callable())
	on_validate = callbacks.get("validate", Callable())
	return self


func _validation_errors(candidate_context: StoryBeatContext) -> PackedStringArray:
	if not on_validate.is_valid():
		return PackedStringArray()
	var result: Variant = on_validate.call(candidate_context)
	if result is PackedStringArray:
		return result
	var errors := PackedStringArray()
	if result is Array:
		for error_variant in result:
			errors.append(str(error_variant))
	return errors


func _on_entered(payload: Dictionary) -> void:
	if on_enter.is_valid():
		on_enter.call(payload)


func _on_exiting(reason: StringName) -> void:
	if on_exit.is_valid():
		on_exit.call(reason)


func _on_updated(delta: float) -> void:
	if on_update.is_valid():
		on_update.call(delta)


func _on_event_received(event_id: StringName, payload: Dictionary) -> bool:
	return bool(on_event.call(event_id, payload)) if on_event.is_valid() else false
