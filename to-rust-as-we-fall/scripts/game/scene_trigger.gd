class_name SceneTrigger
extends RefCounted

## Base class for scene-firing conditions. A SceneTrigger matches a context
## dictionary (the "what just happened" payload) and, if matched, asks the
## SceneManager to fire its scene.
##
## Subclasses override evaluate(). The manager handles priority and
## one-shot tracking; triggers stay stateless so the same instance can be
## registered in multiple places without interference.
##
## Ordering (when multiple triggers match the same dispatch):
##   1. higher priority wins
##   2. ties broken by registration order (stable)

var scene_id: StringName = &""
## Higher runs first. The doc's four trigger types have a natural priority:
##   gate_pass    = 30  (gated narrative beats — story-critical)
##   milestone    = 20  (cure components, zone landmarks)
##   spoke_done   = 10  (processing beats between spokes)
##   time_of_day  =  0  (ambient flavor, lowest)
var priority: int = 0
## If true, the SceneManager marks this scene as played after firing and
## won't fire it again. The only case for false is ambient / time-of-day
## scenes that repeat each cycle.
var one_shot: bool = true

func evaluate(_context: Dictionary) -> bool:
	return false
