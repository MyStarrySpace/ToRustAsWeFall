class_name ItemData

## Item type definitions. Maps type string to default properties and
## endocytosis behavior. Items are instances with unique IDs tracked
## in GameState.items — this class provides the template data.

const TYPES := {
	"lysate": {
		"display_name": "Lysate",
		"scent": true,
		"scent_radius": 6.0,
		"endocytosis_effect": "digest",
		"endocytosis_duration": 2.0,
		"atp_restore": 30.0,
	},
	"cure_component": {
		"display_name": "Cure Component",
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_duration": 2.0,
		"adds_to_collection": true,
	},
	"seed": {
		"display_name": "Seed",
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_duration": 1.5,
	},
	"hushcap": {
		"display_name": "Hushcap",
		"scent": false,
		"endocytosis_effect": "stun_self",
		"endocytosis_duration": 1.5,
		"stun_duration": 4.0,
		"stun_radius": 3.0,
	},
	"ferrolure_seed": {
		"display_name": "Ferrolure Seed",
		"scent": true,
		"scent_radius": 12.0,
		"endocytosis_effect": "scent_broadcast",
		"endocytosis_duration": 2.0,
		"broadcast_duration": 15.0,
	},
	"fire_fruit": {
		"display_name": "Fire Fruit",
		"scent": false,
		"endocytosis_effect": "self_damage",
		"endocytosis_duration": 1.5,
		"damage": 20.0,
	},
	"fragment": {
		"display_name": "Fragment",
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_duration": 2.5,
		"slows_carrier": true,
		"speed_multiplier": 0.5,
	},
}

static func get_type_data(type: String) -> Dictionary:
	if TYPES.has(type):
		return TYPES[type].duplicate()
	return {}

static func get_display_name(type: String) -> String:
	if TYPES.has(type):
		return TYPES[type].display_name
	return type

static func has_scent(type: String) -> bool:
	if TYPES.has(type):
		return TYPES[type].get("scent", false)
	return false

static func get_endocytosis_effect(type: String) -> String:
	if TYPES.has(type):
		return TYPES[type].get("endocytosis_effect", "store")
	return "store"
