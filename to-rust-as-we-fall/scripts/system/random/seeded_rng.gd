class_name SeededRng
extends RefCounted

## Deterministic RandomNumberGenerator wrapper with explicit seed.

var _rng: RandomNumberGenerator
var _seed: int

func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_seed = seed_value
	_rng.seed = seed_value

func get_seed() -> int:
	return _seed

func get_state() -> int:
	return int(_rng.state)

func set_state(state_value: int) -> void:
	_rng.state = state_value

# --- Generators ---

func randi() -> int:
	return int(_rng.randi())

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func randfn(mean: float = 0.0, deviation: float = 1.0) -> float:
	return _rng.randfn(mean, deviation)

# Pick one element from an array.
func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

# Fisher-Yates in place. Returns the same array for chaining.
func shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
