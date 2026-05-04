class_name FloraSpecies

## Flora taxonomy data layer. Six tendable species + the network property.
##
## Source: data/flora_taxonomy.md. The GDD's flora taxonomy lives in
## Section 8 (function-indexed); this class adds Peris's worker vocabulary,
## sensory signatures, hiding-tier mapping, and ambient-flora references.
##
## Used by: dialogue lookup (when Peris speaks vs Aster's overlay), flora
## render passes that vary visuals by species + state, hide-encounter logic
## that consults tier mapping, late-game memory layer that pulls from the
## tended network.
##
## Add gameplay mechanics (Seefern reveal radius, Doma close-on-pursuit,
## Snapbloom popcorn, etc.) in their own systems referencing these names.
## This file is the canonical source of names, vocab, and tier metadata,
## not the implementation.

## Hiding tier per `survival_gameplay_feel.md`. Loosest = positional
## attention-misdirection; medium = scent-masked safe zones; tight = full
## pursuit-break enclosure. Seefern is counter-stealth, not cover.
enum Tier { NONE, LOOSEST, MEDIUM, TIGHT }

## Health-state register. Sensory presentation differs per state per species;
## the dying-stress signature is recognizable cross-species (the smell of
## losing) and is what Peris flags in the Mother Flure chamber.
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
		"old_name": "Ferrolure",
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

## Cut species kept here so legacy dialogue / save files referencing them can
## resolve to their replacements without crashing. Every entry here is gone
## from gameplay; the key just maps to the species that absorbed it (or
## empty string if absorbed into the network property).
const LEGACY_REDIRECT := {
	"lumivine": "seefern",
	"rustmoss": "scarpet",
	"ferrolure": "flure",
	"hushcap": "hushbloom",
	"veilcap": "",  # cut entirely, no replacement
	"rootwall": "scarpet",
	"stormcap": "",  # absorbed into network
	"threadweave": "",
	"pando": "",
	"siphonbloom": "",  # cut entirely
}

## Ambient flora — non-tendable, non-functional, atmospheric. Forget-me-nots
## are the only named entry; everything else is unnamed texture (moss,
## wild cluster flowers, vine skeletons). See data/flora_taxonomy.md
## "Ambient flora" section.
const AMBIENT := {
	"forget_me_nots": {
		"display_name": "Forget-me-nots",
		"function": "atmospheric_emotional_signal",
		"locations": ["shelters", "residential_rings", "mother_flure_chamber_edges"],
		"tending_required": false,
		"scent": "blue, faint, slightly sweet, layered with iron-neutralization",
	},
}

## Puzzle-only flora that does not enter the player's general toolkit.
## Resolution Roots pacify Chelators in the Inflammashunt puzzle through
## evolved symbiosis; not transplantable elsewhere by design.
const PUZZLE_ONLY := {
	"resolution_roots": {
		"display_name": "Resolution Roots",
		"appears_in": ["inflammashunt_puzzle"],
		"sensory": "warm hum (not scent or visual marker)",
	},
}


## Lookup the species record for a key, walking LEGACY_REDIRECT once if the
## key has been retired. Returns empty Dictionary on unknown.
static func get_species(key: String) -> Dictionary:
	var k := key.to_lower()
	if SPECIES.has(k):
		return (SPECIES[k] as Dictionary).duplicate(true)
	if LEGACY_REDIRECT.has(k) and LEGACY_REDIRECT[k] != "":
		return (SPECIES[LEGACY_REDIRECT[k]] as Dictionary).duplicate(true)
	return {}

## Display name for either current or legacy keys. Falls back to the input
## if no record exists.
static func display_name(key: String) -> String:
	var rec := get_species(key)
	if not rec.is_empty():
		return str(rec.get("display_name", key))
	return key

## Hiding tier per `survival_gameplay_feel.md`. Returns Tier.NONE for
## non-cover species (Seefern, Hushbloom, Snapbloom).
static func tier(key: String) -> int:
	var rec := get_species(key)
	if rec.is_empty():
		return Tier.NONE
	return int(rec.get("tier", Tier.NONE))

## Peris's worker vocabulary for a species. Picks the first word in the list
## (the most common one she reaches for); callers wanting variety can read
## the full list from get_species().
static func peris_word(key: String) -> String:
	var rec := get_species(key)
	if rec.is_empty():
		return ""
	var words: Array = rec.get("peris_words", [])
	return str(words[0]) if not words.is_empty() else ""
