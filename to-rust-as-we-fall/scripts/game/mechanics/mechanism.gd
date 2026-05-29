class_name Mechanism
extends RefCounted

## Base class for actuator-driven puzzle mechanisms.
## Reads only Actuator fields: position, weight, and signature.

signal triggered
signal untriggered

var id: StringName = &""
var position: Vector3 = Vector3.ZERO
var radius: float = 1.0
var _is_triggered: bool = false

func is_triggered() -> bool:
	return _is_triggered

# Subclasses receive actuators already filtered to the zone.
func evaluate(_actuators_in_zone: Array) -> bool:
	return false

# Idempotent; safe to call every frame or on demand.
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
