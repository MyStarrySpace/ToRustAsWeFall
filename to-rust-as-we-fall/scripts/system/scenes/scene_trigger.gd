class_name SceneTrigger
extends RefCounted

## Stateless scene-fire condition evaluated against a context dictionary.
## Higher priority wins; ties keep registration order.

var scene_id: StringName = &""
## Higher runs first.
var priority: int = 0
## True for one-shot scenes; false for repeatable ambient beats.
var one_shot: bool = true

func evaluate(_context: Dictionary) -> bool:
	return false
