class_name ODESolver
extends RefCounted

## Lightweight Runge-Kutta helpers for deterministic headless sims.

static func rk4_scalar(value: float, dt: float, derivative: Callable) -> float:
	var k1: float = derivative.call(value, 0.0)
	var k2: float = derivative.call(value + 0.5 * dt * k1, 0.5 * dt)
	var k3: float = derivative.call(value + 0.5 * dt * k2, 0.5 * dt)
	var k4: float = derivative.call(value + dt * k3, dt)
	return value + (dt / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4)

static func rk4_vector(values: PackedFloat64Array, dt: float, derivative: Callable) -> PackedFloat64Array:
	var k1: PackedFloat64Array = derivative.call(values, 0.0)
	var k2: PackedFloat64Array = derivative.call(_offset(values, k1, 0.5 * dt), 0.5 * dt)
	var k3: PackedFloat64Array = derivative.call(_offset(values, k2, 0.5 * dt), 0.5 * dt)
	var k4: PackedFloat64Array = derivative.call(_offset(values, k3, dt), dt)
	var result := PackedFloat64Array()
	result.resize(values.size())
	for i in range(values.size()):
		result[i] = values[i] + (dt / 6.0) * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return result

static func _offset(values: PackedFloat64Array, delta: PackedFloat64Array, scale: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(values.size())
	for i in range(values.size()):
		result[i] = values[i] + delta[i] * scale
	return result
