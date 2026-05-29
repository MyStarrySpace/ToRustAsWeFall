class_name RngRegistry
extends RefCounted

## Per-system deterministic RNG registry.

var base_seed: int
var _instances: Dictionary = {}  # key (String) -> SeededRng

func _init(base_seed_value: int = 0) -> void:
	base_seed = base_seed_value

## Get or create RNG for a system instance.
func get_rng(system_name: StringName, birth_id: int = 0) -> SeededRng:
	var key := "%s#%d" % [system_name, birth_id]
	if _instances.has(key):
		return _instances[key]
	var derived := _derive_seed(system_name, birth_id)
	var rng := SeededRng.new(derived)
	_instances[key] = rng
	return rng

# Stable seed derivation.
func _derive_seed(system_name: StringName, birth_id: int) -> int:
	var name_hash := int(hash(String(system_name)))
	# Prime mixing avoids simple XOR collisions.
	var mixed: int = base_seed
	mixed = (mixed * 1000003) ^ name_hash
	mixed = (mixed * 1000003) ^ birth_id
	return mixed

## Count live RNG instances.
func instance_count() -> int:
	return _instances.size()

func clear() -> void:
	_instances.clear()
