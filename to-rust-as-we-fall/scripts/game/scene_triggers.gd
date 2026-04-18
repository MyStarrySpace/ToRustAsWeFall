## Concrete SceneTrigger subclasses. Bundled together because they're small
## data classes that share the trigger contract — splitting them across
## files adds noise without improving navigability.

class_name SceneTriggers
extends RefCounted

class OnSpokeComplete extends SceneTrigger:
	var spoke_id: StringName = &""
	func _init(p_scene_id: StringName, p_spoke_id: StringName, p_priority: int = 10) -> void:
		scene_id = p_scene_id
		spoke_id = p_spoke_id
		priority = p_priority
	func evaluate(context: Dictionary) -> bool:
		return (StringName(context.get("kind", &"")) == &"spoke_completed"
			and StringName(context.get("spoke_id", &"")) == spoke_id)

class OnGatePass extends SceneTrigger:
	var gate_id: StringName = &""
	func _init(p_scene_id: StringName, p_gate_id: StringName, p_priority: int = 30) -> void:
		scene_id = p_scene_id
		gate_id = p_gate_id
		priority = p_priority
	func evaluate(context: Dictionary) -> bool:
		return (StringName(context.get("kind", &"")) == &"gate_passed"
			and StringName(context.get("gate_id", &"")) == gate_id)

class OnMilestone extends SceneTrigger:
	var milestone_id: StringName = &""
	func _init(p_scene_id: StringName, p_milestone_id: StringName, p_priority: int = 20) -> void:
		scene_id = p_scene_id
		milestone_id = p_milestone_id
		priority = p_priority
	func evaluate(context: Dictionary) -> bool:
		return (StringName(context.get("kind", &"")) == &"milestone"
			and StringName(context.get("milestone_id", &"")) == milestone_id)

class OnTimeOfDay extends SceneTrigger:
	var time_of_day: StringName = &""
	func _init(p_scene_id: StringName, p_time_of_day: StringName, p_priority: int = 0) -> void:
		scene_id = p_scene_id
		time_of_day = p_time_of_day
		priority = p_priority
		# Time-of-day scenes default to repeating each cycle
		one_shot = false
	func evaluate(context: Dictionary) -> bool:
		return (StringName(context.get("kind", &"")) == &"time_of_day"
			and StringName(context.get("time_of_day", &"")) == time_of_day)
