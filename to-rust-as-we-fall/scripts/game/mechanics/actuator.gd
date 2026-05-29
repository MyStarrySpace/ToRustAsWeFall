class_name Actuator
extends RefCounted

## Plain data for anything that can trigger a Mechanism.
## GameState builds Actuators on demand.

var position: Vector3
var weight: float
var signature: StringName

static func make(pos: Vector3, weight_value: float, sig: StringName) -> Actuator:
	var a := Actuator.new()
	a.position = pos
	a.weight = weight_value
	a.signature = sig
	return a
