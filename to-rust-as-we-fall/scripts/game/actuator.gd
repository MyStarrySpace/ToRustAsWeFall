class_name Actuator
extends RefCounted

## Plain data: anything that physically influences a Mechanism in the world.
##
## Characters, items on the ground, and pushable physics objects are all
## actuators. The contract is intentionally minimal — position, weight, and
## a signature string for "what kind of thing this is". A Mechanism that
## reads more than these three fields has stopped being composition-blind
## and the lint should catch it.
##
## GameState.get_all_actuators() builds these on demand; nothing in the
## simulation persists Actuator instances long-term.

var position: Vector3
var weight: float
var signature: StringName

static func make(pos: Vector3, weight_value: float, sig: StringName) -> Actuator:
	var a := Actuator.new()
	a.position = pos
	a.weight = weight_value
	a.signature = sig
	return a
