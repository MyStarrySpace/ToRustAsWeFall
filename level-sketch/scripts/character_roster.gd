class_name CharacterRoster
extends RefCounted

## The six playable brain-cell characters (mirrors the game's CHARACTER_REGISTRY), and the
## ENABLE/DISABLE roster the player picks. Disabling a character removes its capabilities
## from the full-party solver, so combat-only beats fall to the Aster+Peris route — the pair
## always solves. Aster and Peris are permanent (the minimum pair) and can't be disabled.

const SAVE_PATH := "user://roster.json"
const ALWAYS_ON := ["aster", "peris"]

const CHARACTERS := [
	{
		"id": "aster", "name": "Aster", "cell": "astrocyte", "class": "AST", "color": Color(0.45, 0.85, 0.90),
		"role": "Data analyst / scout — reads infrastructure + data overlays; half the permanent pair.",
		"capabilities": ["data", "electrical", "overlay", "terminal", "scan", "timing", "signal", "ast_class"],
		"abilities": [{"name": "EMP Hack", "desc": "AoE stun pulse"}],
	},
	{
		"id": "peris", "name": "Peris", "cell": "pericyte", "class": "PCT", "color": Color(0.45, 0.82, 0.50),
		"role": "Support / social worker — flora, carries weight, reads people; half the permanent pair.",
		"capabilities": ["flora", "carry", "physical", "protect", "cover", "tend", "pct_class"],
		"abilities": [{"name": "Protect / Wrap", "desc": "Aura absorbs ally damage"}, {"name": "Harvest", "desc": "Flora heal + vision"}],
	},
	{
		"id": "endo", "name": "Endo", "cell": "endothelial", "class": "ENT", "color": Color(0.90, 0.74, 0.42),
		"role": "Silent barrier engineer — fastest; early survival guide (junctions, repair).",
		"capabilities": ["barrier", "junction", "repair", "gear", "carry", "endo", "ent_class"],
		"abilities": [{"name": "NO Pulse", "desc": "Slow enemies 40%"}, {"name": "Cloak", "desc": "Invisible 10s"}],
	},
	{
		"id": "myke", "name": "Myke", "cell": "microglia", "class": "MCG", "color": Color(0.86, 0.40, 0.36),
		"role": "Burst DPS — fire kit. THE combat specialist (the redirect/gauntlet primary).",
		"capabilities": ["combat", "impact", "force", "carry", "physical", "tend", "class_other"],
		"abilities": [{"name": "Inflame", "desc": "Fire zone, attracts Neutros"}, {"name": "Engulf", "desc": "Burn + ROS swarm"}],
	},
	{
		"id": "oli", "name": "Oli", "cell": "oligodendrocyte", "class": "OLG", "color": Color(0.75, 0.66, 0.92),
		"role": "Defensive support — insulation + shields; protected lanes through hazards.",
		"capabilities": ["barrier", "insulation", "terminal", "electrical", "cover", "class_other"],
		"abilities": [{"name": "Sheath", "desc": "Ally HP shield"}, {"name": "Conduct", "desc": "Ally speed buff"}],
	},
	{
		"id": "tyreg", "name": "Tyreg", "cell": "T-regulatory", "class": "TRG", "color": Color(0.92, 0.58, 0.42),
		"role": "Ranged enforcer — combat-pair with Myke (ranged force, suppression).",
		"capabilities": ["combat", "force", "scan", "timing", "class_tmc"],
		"abilities": [{"name": "Shoot", "desc": "Ranged 25 dmg"}, {"name": "Suppress", "desc": "Freeze enemy 5s"}],
	},
]


static func get_character(id: String) -> Dictionary:
	for c in CHARACTERS:
		if str(c["id"]) == id:
			return c
	return {}


## Display color for a character id (falls back to a neutral grey for unknown ids).
static func color_of(id: String) -> Color:
	var c := get_character(id)
	if c.is_empty():
		return Color(0.8, 0.8, 0.85)
	return c["color"]


static func default_enabled() -> Array:
	var ids := []
	for c in CHARACTERS:
		ids.append(str(c["id"]))
	return ids


static func always_on(id: String) -> bool:
	return ALWAYS_ON.has(str(id))


static func load_enabled() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return default_enabled()
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return default_enabled()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).get("enabled") is Array:
		var ids := []
		for id in (parsed as Dictionary)["enabled"]:
			ids.append(str(id))
		for id in ALWAYS_ON:
			if not ids.has(id):
				ids.append(id)
		return ids
	return default_enabled()


static func save_enabled(ids: Array) -> void:
	var clean := []
	for c in CHARACTERS:
		var cid := str(c["id"])
		if ids.has(cid) or ALWAYS_ON.has(cid):
			clean.append(cid)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"schema": "trawf_roster_v1", "enabled": clean}, "\t"))


## Capability tags the ENABLED set provides (mirrors the game's roster_capabilities).
static func enabled_capabilities(ids: Array) -> Dictionary:
	var caps := {}
	for c in CHARACTERS:
		if ids.has(str(c["id"])) or ALWAYS_ON.has(str(c["id"])):
			for cap in c["capabilities"]:
				caps[str(cap)] = true
	return caps


## Whether the enabled set fields a combat specialist (so redirect/gauntlet beats keep
## their full-party route instead of falling to the pair).
static func has_combat(ids: Array) -> bool:
	return enabled_capabilities(ids).has("combat")
