class_name SceneManager
extends RefCounted

## Dispatches registered SceneTriggers and emits the highest-priority match.

signal scene_fired(scene_id: StringName, context: Dictionary)

var _triggers: Array = []
var _played: Dictionary = {}  # scene_id → true

func register_trigger(t: SceneTrigger) -> void:
	_triggers.append(t)

func dispatch(context: Dictionary) -> StringName:
	var best: SceneTrigger = null
	var best_index := -1
	for i in range(_triggers.size()):
		var t: SceneTrigger = _triggers[i]
		if t.one_shot and _played.has(t.scene_id):
			continue
		if not t.evaluate(context):
			continue
		if best == null:
			best = t
			best_index = i
		elif t.priority > best.priority:
			best = t
			best_index = i
		elif t.priority == best.priority and i < best_index:
			best = t
			best_index = i
	if best == null:
		return &""
	if best.one_shot:
		_played[best.scene_id] = true
	scene_fired.emit(best.scene_id, context)
	return best.scene_id

func is_played(scene_id: StringName) -> bool:
	return _played.has(scene_id)

func reset_played(scene_id: StringName = &"") -> void:
	if scene_id == &"":
		_played.clear()
	else:
		_played.erase(scene_id)

## Connect ZoneManager signals to dispatch().
func bind_zone_manager(zm: ZoneManager) -> void:
	zm.spoke_completed.connect(func(id: StringName):
		dispatch({"kind": &"spoke_completed", "spoke_id": id}))
	zm.gate_passed.connect(func(id: StringName):
		dispatch({"kind": &"gate_passed", "gate_id": id}))
