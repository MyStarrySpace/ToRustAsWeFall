class_name Mechanism
extends RefCounted

## Base class for world-physical mechanisms (pressure plates, weight sensors,
## area triggers). Mechanisms evaluate a condition over the actuators
## currently in their zone of influence and emit transitions.
##
## A Mechanism never inspects character identifiers, character lists, or
## item types — only the Actuator fields (position, weight, signature).
## The --test-actuator-no-id-checks lint enforces this by greping for
## forbidden identifiers in mechanism source files.
##
## Lifecycle:
##   var m := WeightMechanism.new()
##   m.id = &"hub_door_plate"
##   m.position = Vector3(4, 0, 2)
##   m.radius = 0.6
##   m.threshold = 2.0
##   game_state.register_mechanism(m)
##   m.triggered.connect(...)
##   # Then any time actuators may have moved:
##   game_state.evaluate_mechanisms()

signal triggered
signal untriggered

var id: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius: float = 1.0
var _is_triggered: bool = false

func is_triggered() -> bool:
	return _is_triggered

# Subclasses override. Receives the actuators already filtered to the zone.
# Return value is the new triggered state.
func evaluate(_actuators_in_zone: Array) -> bool:
	return false

# Filter to the zone, evaluate, emit transitions. Idempotent — safe to call
# every frame or on demand.
func update(actuators: Array) -> void:
	var in_zone := _filter_in_zone(actuators)
	var new_state := evaluate(in_zone)
	if new_state and not _is_triggered:
		_is_triggered = true
		triggered.emit()
	elif not new_state and _is_triggered:
		_is_triggered = false
		untriggered.emit()

func _filter_in_zone(actuators: Array) -> Array:
	var result: Array = []
	var r2: float = radius * radius
	for a in actuators:
		var dx: float = a.position.x - position.x
		var dz: float = a.position.z - position.z
		if dx * dx + dz * dz <= r2:
			result.append(a)
	return result
