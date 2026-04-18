class_name RngRegistry
extends RefCounted

## Per-system registry of SeededRng instances, keyed by system name.
##
## Each system (AI, loot, ambient, weather, ...) gets its own RNG so calls
## from one system don't shift the output of another. Adding a new system
## later does not invalidate existing replays of older systems.
##
## Seeds derive from a base seed plus a stable hash of the system name and
## a per-instance birth_id (the event-log index where the system was born).
## This makes seeds deterministic from the event stream alone, so two
## replays of the same log produce identical RNG outputs.

var base_seed: int
var _instances: Dictionary = {}  # key (String) -> SeededRng

func _init(base_seed_value: int = 0) -> void:
	base_seed = base_seed_value

## Get-or-create the RNG for a (system, birth_id) pair. birth_id is 0 for
## singleton systems (loot, ambient) and the event-stream index for
## per-spawn systems (a Techo born at event 4712 uses birth_id=4712).
func get_rng(system_name: StringName, birth_id: int = 0) -> SeededRng:
	var key := "%s#%d" % [system_name, birth_id]
	if _instances.has(key):
		return _instances[key]
	var derived := _derive_seed(system_name, birth_id)
	var rng := SeededRng.new(derived)
	_instances[key] = rng
	return rng

# Pure function: stable seed derivation. Same inputs → same output, always.
func _derive_seed(system_name: StringName, birth_id: int) -> int:
	var name_hash := int(hash(String(system_name)))
	# Mix the three components. XOR alone is too prone to collisions when
	# two systems share a hash bit pattern; multiply by a large odd prime
	# to scramble bits before mixing.
	var mixed: int = base_seed
	mixed = (mixed * 1000003) ^ name_hash
	mixed = (mixed * 1000003) ^ birth_id
	# Mask to 64-bit unsigned range. RandomNumberGenerator accepts any int.
	return mixed

## How many RNG instances are alive. Useful for tests.
func instance_count() -> int:
	return _instances.size()

func clear() -> void:
	_instances.clear()
