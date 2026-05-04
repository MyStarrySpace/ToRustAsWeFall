class_name ItemData

## Item type definitions. Maps type string to default properties and
## endocytosis behavior. Items are instances with unique IDs tracked
## in GameState.items — this class provides the template data.

const TYPES := {
	"lysate": {
		"display_name": "Lysate",
		"hand_slots": 1,
		"scent": true,
		"scent_radius": 6.0,
		"endocytosis_effect": "digest",
		"endocytosis_duration": 2.0,
		"atp_restore": 2.0,
	},
	"cure_component": {
		"display_name": "Cure Component",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_duration": 2.0,
		"adds_to_collection": true,
	},
	"seed": {
		"display_name": "Seed",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_duration": 1.5,
	},
	"hushbloom": {
		"display_name": "Hushbloom",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "stun_self",
		"endocytosis_duration": 1.5,
		"stun_duration": 4.0,
		"stun_radius": 3.0,
	},
	"flure_seed": {
		"display_name": "Flure Seed",
		"hand_slots": 1,
		"scent": true,
		"scent_radius": 12.0,
		"endocytosis_effect": "scent_broadcast",
		"endocytosis_duration": 2.0,
		"broadcast_duration": 15.0,
	},
	"fire_fruit": {
		"display_name": "Fire Fruit",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "self_damage",
		"endocytosis_duration": 1.5,
		"damage": 20.0,
	},
	"fragment": {
		"display_name": "Fragment",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_duration": 2.5,
		"slows_carrier": true,
		"speed_multiplier": 0.5,
	},
	"mother_gear": {
		"display_name": "Mother Gear",
		"hand_slots": 2,
		"scent": false,
		"endocytosis_effect": "store",
		"endocytosis_allowed": false,
	},

	# --- Permanent upgrade items ---
	# These produce persistent stat/capability changes when consumed. Effect
	# handler (stat_upgrade) is registered with GameState; payload describes
	# which stat moves and by how much. Universal upgrades work on any party
	# member; character-locked upgrades (Solfloraphane) bind to one cell type.

	"curecumin": {
		"display_name": "Curecumin",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "stat_upgrade",
		"endocytosis_duration": 2.0,
		"upgrade_stat": "hp_max",
		"upgrade_amount": 10.0,
		"register": "institutional_elite",
	},
	"laughterferrin": {
		"display_name": "Laughterferrin",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "stat_upgrade",
		"endocytosis_duration": 1.5,
		"upgrade_stat": "stamina_max",
		"upgrade_amount": 10.0,
		"register": "consumer_institutional",
	},
	"nommega3": {
		"display_name": "Nommega 3",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "stat_upgrade",
		"endocytosis_duration": 1.5,
		"upgrade_stat": "atp_max",
		"upgrade_amount": 1.0,
		"register": "worker_consumer",
	},
	"solfloraphane": {
		"display_name": "Solfloraphane",
		"hand_slots": 1,
		"scent": false,
		"endocytosis_effect": "stat_upgrade",
		"endocytosis_duration": 2.0,
		"upgrade_stat": "tending_speed",
		"upgrade_amount": 0.15,
		"locked_to": "peris",
		"register": "pre_collapse_research",
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

static func get_hand_slots(type: String) -> int:
	if TYPES.has(type):
		return int(TYPES[type].get("hand_slots", 1))
	return 1

static func can_endocytose(type: String) -> bool:
	if TYPES.has(type):
		return bool(TYPES[type].get("endocytosis_allowed", true))
	return true

static func get_endocytosis_effect(type: String) -> String:
	if TYPES.has(type):
		return TYPES[type].get("endocytosis_effect", "store")
	return "store"

## True for upgrade items that grant a permanent capability or stat change.
static func is_upgrade(type: String) -> bool:
	return get_endocytosis_effect(type) == "stat_upgrade"

## Returns the upgrade payload for stat-upgrade items. Empty for non-upgrades.
## Keys: stat (e.g. "hp_max"), amount (float), locked_to (optional char_id).
static func get_upgrade_payload(type: String) -> Dictionary:
	if not is_upgrade(type):
		return {}
	var data := get_type_data(type)
	return {
		"stat": str(data.get("upgrade_stat", "")),
		"amount": float(data.get("upgrade_amount", 0.0)),
		"locked_to": str(data.get("locked_to", "")),
	}
