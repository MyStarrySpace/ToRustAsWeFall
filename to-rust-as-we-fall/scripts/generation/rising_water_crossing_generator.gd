class_name RisingWaterCrossingGenerator
extends RefCounted

## Procedural-generation boundary for the reusable rising-water archetype.
## Layout chooses bowl and float-road cells; this module returns the exact
## runtime object consumed by DataFragmentChunk.

const CONTRACT := "generated_rising_water_crossing/v1"
const RisingWaterCrossingSpecScript := preload(
	"res://scripts/game/objects/rising_water_crossing_spec.gd")


static func build(params: Dictionary) -> Dictionary:
	var spec := RisingWaterCrossingSpecScript.from_grid_rect(params)
	spec["generation_contract"] = CONTRACT
	return spec


static func validate_candidate(params: Dictionary, party_size := 0) -> Dictionary:
	return RisingWaterCrossingSpecScript.validate(build(params), party_size)
