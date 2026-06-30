class_name Biomes
extends RefCounted

## BIOMES are named CONTENT presets — a coherent slice of the flora/fauna/structure palette that gives a stretch
## its character (the flooded Channels vs the vertical Stacks vs an overgrown Garden vs a failed dead zone). A
## biome is realized purely through the generator's EXISTING `limitations.allowed` machinery (no new generation
## logic): `settings.biome` restricts content to that biome's lists. The roster/solver invariants are unaffected
## — specialist capabilities ride the party, and the bare pair's base capabilities don't depend on placed content.
## All ids are canonical content_palette.json keys (fauna use the renamed roster: Sapscraps/Aembers/Flares/Redactors).

const BIOMES := {
	"channels": {
		"display": "The Channels",
		"flora": ["scarpet", "flure", "capbage", "seefern"],
		"enemies": ["hidras", "naturalizers", "redactors", "aembers", "flares"],
		"structures": ["shelter", "water_control", "pipe", "terminal", "shortcut_gate", "hide_slot"],
	},
	"stacks": {
		"display": "The Stacks",
		"flora": ["climbvine", "flure", "hushbloom", "doma"],
		"enemies": ["spikers", "tanglers", "gnawers", "sapscraps"],
		"structures": ["shelter", "junction", "barrier", "carry_gear", "terminal"],
	},
	"garden": {
		"display": "The Garden",
		"flora": ["seefern", "scarpet", "capbage", "hushbloom", "gasafoetida", "snapbloom"],
		"enemies": ["meebs", "candids", "toxos", "gnawers"],
		"structures": ["shelter", "forage_cache", "terminal", "root_slide"],
	},
	"deadzone": {
		"display": "The Dead Zone",
		"flora": ["scarpet", "forget_me_nots", "resolution_roots"],
		"enemies": ["toxos", "crusts", "candids", "redactors"],
		"structures": ["shelter", "terminal", "membrane"],
	},
}

static func biome_ids() -> Array:
	return BIOMES.keys()

static func has_biome(id: String) -> bool:
	return BIOMES.has(id)

static func display_name(id: String) -> String:
	return str(BIOMES.get(id, {}).get("display", id.capitalize()))

## The generator `limitations` block for a biome — restricts content to the biome's lists via `allowed`.
static func limitations_for(id: String) -> Dictionary:
	var b: Dictionary = BIOMES.get(id, {})
	if b.is_empty():
		return {}
	return {"allowed": {
		"flora": (b.get("flora", []) as Array).duplicate(),
		"enemies": (b.get("enemies", []) as Array).duplicate(),
		"structures": (b.get("structures", []) as Array).duplicate(),
	}}

## Pick a biome deterministically from an arbitrary string key (the roguelike keys on run-seed/depth/branch so a
## descent rotates biomes and two forks can lead to different regions).
static func for_key(key: String) -> String:
	var ids: Array = biome_ids()
	if ids.is_empty():
		return ""
	return str(ids[abs(int(hash("biome:" + key))) % ids.size()])

## Pick a biome for a run DEPTH deterministically (the roguelike rotates biomes as it descends).
static func for_depth(seed: int, depth: int) -> String:
	return for_key("%d:%d" % [seed, depth])
