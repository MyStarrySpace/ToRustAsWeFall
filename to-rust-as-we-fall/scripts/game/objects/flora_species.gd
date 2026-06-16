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
		"reveals": ["hidra", "crust_early", "nosoma"],
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
	"doma": {
		"display_name": "Doma",
		"primary_function": "tight_cover_enclosure",
		"secondary_function": "",
		"tier": Tier.TIGHT,
		"name_etymology": "shortened from 'domatia' (real botanical term)",
		"peris_words": ["the blooms", "my blooms", "the safeholds"],
		"scent_healthy": "faintly sweet, like honey or overripe fruit",
		"scent_dying": "loss-register over the honey",
		"capacity_default": 1,
		"capacity_rare_max": 3,
		"hum_signal": "steady when comfortable, agitated when threats near, silent when stressed",
	},
	"snapbloom": {
		"display_name": "Snapbloom",
		"primary_function": "repellent_burst_camouflaged",
		"secondary_function": "fire_reactive_hazard",
		"tier": Tier.NONE,
		"repellent_targets": ["chain", "tangler", "nosoma"],
		"repellent_immune": ["naturalizer"],
		"peris_words": ["the snappers", "the popcorns", "the loud ones"],
		"scent_healthy": "sharper than Hushbloom, slightly sweet, ready-to-react",
		"scent_dying": "sharp loss-register",
		"popcorn_projectile_count": 4,  # range 3-5; deterministic anchor
	},
}

## Retired keys preserved for dialogue/save compatibility.
const LEGACY_REDIRECT := {
	"lumivine": "seefern",
	"rustmoss": "scarpet",
	"flure": "flure",
	"hushcap": "hushbloom",
	"veilcap": "",  # cut entirely, no replacement
	"rootwall": "scarpet",
	"stormcap": "",  # absorbed into network
	"threadweave": "",
	"pando": "",
	"siphonbloom": "",  # cut entirely
}

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
	var k := key.to_lower()
	if SPECIES.has(k):
		return (SPECIES[k] as Dictionary).duplicate(true)
	if LEGACY_REDIRECT.has(k) and LEGACY_REDIRECT[k] != "":
		return (SPECIES[LEGACY_REDIRECT[k]] as Dictionary).duplicate(true)
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
