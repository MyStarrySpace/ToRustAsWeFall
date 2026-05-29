class_name FauxPhysicsSensor
extends Mechanism

## Authored puzzle sensor for simple faux-physics conditions.

enum SensorMode {
	TOTAL_WEIGHT,
	ACTUATOR_COUNT,
	SIGNATURE_PRESENT,
	SIGNATURE_WEIGHT,
}

var mode := SensorMode.TOTAL_WEIGHT
var required_weight: float = 1.0
var required_count: int = 1
var required_signature: StringName = &""

func evaluate(actuators_in_zone: Array) -> bool:
	match mode:
		SensorMode.TOTAL_WEIGHT:
			return total_weight(actuators_in_zone) >= required_weight
		SensorMode.ACTUATOR_COUNT:
			return actuators_in_zone.size() >= required_count
		SensorMode.SIGNATURE_PRESENT:
			return has_signature(actuators_in_zone, required_signature)
		SensorMode.SIGNATURE_WEIGHT:
			return signature_weight(actuators_in_zone, required_signature) >= required_weight
	return false

func total_weight(actuators_in_zone: Array) -> float:
	var total := 0.0
	for actuator in actuators_in_zone:
		total += float(actuator.weight)
	return total

func signature_weight(actuators_in_zone: Array, signature: StringName) -> float:
	var total := 0.0
	for actuator in actuators_in_zone:
		if actuator.signature == signature:
			total += float(actuator.weight)
	return total

func has_signature(actuators_in_zone: Array, signature: StringName) -> bool:
	for actuator in actuators_in_zone:
		if actuator.signature == signature:
			return true
	return false
