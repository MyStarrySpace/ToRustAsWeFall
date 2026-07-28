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

## Save every consumed stream, not just the root seed. Restoring only the seed would let a player
## reroll the next deterministic outcome by loading because each stream would restart at draw zero.
func serialize() -> Dictionary:
	var streams := {}
	var keys := _instances.keys()
	keys.sort()
	for key_v in keys:
		var key := str(key_v)
		var rng := _instances[key_v] as SeededRng
		streams[key] = {"seed": rng.get_seed(), "state": rng.get_state()}
	return {"base_seed": base_seed, "streams": streams}

func deserialize(snapshot: Dictionary) -> void:
	base_seed = int(snapshot.get("base_seed", 0))
	_instances.clear()
	var streams := snapshot.get("streams", {}) as Dictionary
	for key_v in streams.keys():
		var key := str(key_v)
		var state := streams[key_v] as Dictionary
		var rng := SeededRng.new(int(state.get("seed", 0)))
		rng.set_state(int(state.get("state", rng.get_state())))
		_instances[key] = rng

func clear() -> void:
	_instances.clear()
