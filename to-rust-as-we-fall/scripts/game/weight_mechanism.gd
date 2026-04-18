class_name WeightMechanism
extends Mechanism

## Triggers when the sum of actuator weights in the zone meets or exceeds
## the threshold. Pressure plates, weight-sensitive switches, scales.
##
## Composition-blind: a single heavy actuator, two light actuators, an item
## plus a character — anything summing to threshold triggers identically.

var threshold: float = 1.0

func evaluate(actuators_in_zone: Array) -> bool:
	var total := 0.0
	for a in actuators_in_zone:
		total += a.weight
	return total >= threshold
