class_name FloraSpecies

## Canonical flora names, vocabulary, sensory data, and hiding tiers.
## Mechanics live in systems that reference these keys.

## Hiding tier from `survival_gameplay_feel.md`.
enum Tier { NONE, LOOSEST, MEDIUM, TIGHT }

## Health-state register.
enum State { HEALTHY, DORMANT, STRESSED, DYING, DEAD }

const SPECIES := {
	"seefern": {
		"display_name": "Seefern",
		"old_name": "Lumivine",  # workers may still use it; recognized in dialogue
		"primary_function": "light_vision_extension",
		"secondary_function": "reveal_camouflaged",
		"tier": Tier.NONE,
		"reveals": ["hidra", "crust_early", "redactor"],
		"peris_words": ["the vines", "the glow-vines", "the little ones"],
		"scent_healthy": "faint sweet, moist, like rain on warm rock",
		"scent_dying": "standing water; loss-register",
		"glow_color": Color(0.4, 0.85, 0.6),
		"glow_color_dead_zone": Color(0.6, 0.75, 1.0),  # blue-white when stressed
		"dead_zone_lifespan_seconds": 86400.0,  # ~one in-game day
	},
	"scarpet": {
		"display_name": "Scarpet",
		"old_name": "Rustmoss",
		"primary_function": "biofilm_removal",
		"secondary_function": "scent_masking",
		"tier": Tier.MEDIUM,
		"absorbs": ["rootwall_anti_candid"],  # absorbed function from old design pass
		"peris_words": ["the spread", "the low cover", "the clearing stuff"],
		"scent_healthy": "neutral, mineral, faint dry-earth",
		"scent_dying": "calcified-dust residue",
		"contest_visual": "yellow leaves and pale stems while battling Candids",
	},
	"flure": {
		"display_name": "Flure",
		"old_name": "Flure",
		"primary_function": "iron_decoy",
		"secondary_function": "",
		"tier": Tier.LOOSEST,
		"peris_words": ["the flures", "the lures", "the iron flowers"],
		"individual_specimens": ["mother_flure"],  # outliers, not separate species
		"scent_healthy": "metallic-sweet, wet iron",
		"scent_dying": "metallic with decay underneath; sweetness drops, metal stays",
	},
	"hushbloom": {
		"display_name": "Hushbloom",
		"old_name": "Hushcap",
		"primary_function": "stun_burst",
		"secondary_function": "regenerates_after_use",
		"tier": Tier.NONE,
		"biology_basis": "thigmonastic plant (Mimosa pudica analog)",
		"peris_words": ["the quiet-blooms", "the silencers"],
		"scent_healthy": "faintly sweet when charged",
		"scent_dying": "sharply of damp stone",
		"regen_seconds": 7200.0,  # ~couple corridor traversals
	},
	"capbage": {
		"display_name": "Capbage",
		"primary_function": "tight_cover_enclosure",
		"secondary_function": "general_cache",
		"tier": Tier.TIGHT,
		"biology_basis": "self-sealing cabbage-like leaf head with a mutualist cavity",
		"peris_words": ["the heads", "my heads", "the safeholds"],
		"scent_healthy": "faintly sweet and vegetal, like fresh-cut cabbage with a honey undertone",
		"capacity_default": 1,
		"capacity_rare_max": 3,
		"hide_rest_atp_cost": 0,
		"hide_rest_restores_hp": false,
		"hide_rest_tiredness": "major",
		"hum_signal": "steady when comfortable, agitated when threats near, silent when stressed",
	},
	"gasafoetida": {
		"display_name": "Gasafoetida",
		"primary_function": "carried_repellent_gas_pod",
		"secondary_function": "fire_reactive_combustible_projectile_cluster",
		"tier": Tier.NONE,
		"biology_basis": "asafoetida sulfur chemistry with serotinous-cone fire dispersal",
		"repellent_scope": "all_enemy_classes",
		"held_pod_duration_seconds": [30.0, 45.0],
		"peris_words": ["the stinkers", "the pods", "the smelly ones"],
		"fire_reaction_worker_phrase": "the popcorn going off",
		"scent_healthy": "sharp sulfurous asafoetida resin, eye-watering and ready to react",
		"serotinous_projectile_count_default": 4,  # authored range is 3-5
	},
}

## Retired keys preserved only at load/save compatibility boundaries.
const LEGACY_REDIRECT := {
	"lumivine": "seefern",
	"rustmoss": "scarpet",
	"hushcap": "hushbloom",
	"doma": "capbage",
	"snapbloom": "gasafoetida",
	"veilcap": "",  # cut entirely, no replacement
	"rootwall": "scarpet",
	"stormcap": "",  # absorbed into network
	"threadweave": "",
	"pando": "",
	"siphonbloom": "",  # cut entirely
}

## Convert a current or persisted retired key to the runtime species key.
## Unknown keys stay normalized so callers can report them without inventing a species.
static func canonical_key(key: String) -> String:
	var normalized := key.strip_edges().to_lower()
	if SPECIES.has(normalized):
		return normalized
	if LEGACY_REDIRECT.has(normalized):
		return str(LEGACY_REDIRECT[normalized])
	return normalized

static func is_legacy_key(key: String) -> bool:
	return LEGACY_REDIRECT.has(key.strip_edges().to_lower())

## Non-tendable atmospheric flora.
const AMBIENT := {
	"forget_me_nots": {
		"display_name": "Forget-me-nots",
		"function": "atmospheric_emotional_signal",
		"locations": ["shelters", "residential_rings", "mother_flure_chamber_edges"],
		"tending_required": false,
		"scent": "blue, faint, slightly sweet, layered with iron-neutralization",
	},
}

## Puzzle-only flora outside the general toolkit.
const PUZZLE_ONLY := {
	"resolution_roots": {
		"display_name": "Resolution Roots",
		"appears_in": ["inflammashunt_puzzle"],
		"sensory": "warm hum (not scent or visual marker)",
	},
}


## Lookup a current or retired species key.
static func get_species(key: String) -> Dictionary:
	var k := canonical_key(key)
	if SPECIES.has(k):
		return (SPECIES[k] as Dictionary).duplicate(true)
	return {}

## Display name for current or retired keys.
static func display_name(key: String) -> String:
	var rec := get_species(key)
	if not rec.is_empty():
		return str(rec.get("display_name", key))
	return key

## Hiding tier, or Tier.NONE.
static func tier(key: String) -> int:
	var rec := get_species(key)
	if rec.is_empty():
		return Tier.NONE
	return int(rec.get("tier", Tier.NONE))

## Peris's default worker word for a species.
static func peris_word(key: String) -> String:
	var rec := get_species(key)
	if rec.is_empty():
		return ""
	var words: Array = rec.get("peris_words", [])
	return str(words[0]) if not words.is_empty() else ""
