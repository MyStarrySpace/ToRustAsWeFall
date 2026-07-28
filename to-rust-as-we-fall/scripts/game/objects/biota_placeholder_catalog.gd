class_name BiotaPlaceholderCatalog
extends RefCounted

## Stable discovery point for intentionally replaceable world-biota models. These scenes are
## art presenters only: gameplay objects retain collision, authority, animation, and interaction.
## That keeps a future final creature or plant model swap from changing mechanic code.

const CONTRACT_ID := "biota_placeholder_catalog_v1"

const RECORDS := {
	"flora/seefern": {
		"scene": "res://scenes/props/biota/placeholder_seefern.tscn",
		"visual_identity": "placeholder_seefern_v1",
		"category": "flora",
		"species": "seefern",
		"signal_part": "Signal",
	},
	"flora/hushbloom": {
		"scene": "res://scenes/props/biota/placeholder_hushbloom.tscn",
		"visual_identity": "placeholder_hushbloom_v1",
		"category": "flora",
		"species": "hushbloom",
		"signal_part": "Signal",
	},
	"flora/scarpet": {
		"scene": "res://scenes/props/biota/placeholder_scarpet.tscn",
		"visual_identity": "placeholder_scarpet_v1",
		"category": "flora",
		"species": "scarpet",
		"signal_part": "",
	},
	"fauna/sapscrap": {
		"scene": "res://scenes/props/biota/placeholder_sapscrap.tscn",
		"visual_identity": "placeholder_sapscrap_v1",
		"category": "fauna",
		"species": "sapscrap",
		"signal_part": "Signal",
	},
}


static func keys() -> Array[String]:
	var out: Array[String] = []
	for key_v in RECORDS.keys():
		out.append(str(key_v))
	out.sort()
	return out


static func has(key: String) -> bool:
	return RECORDS.has(key.strip_edges().to_lower())


static func record(key: String) -> Dictionary:
	var normalized := key.strip_edges().to_lower()
	if not RECORDS.has(normalized):
		return {}
	return (RECORDS[normalized] as Dictionary).duplicate(true)


static func scene_path(key: String) -> String:
	return str(record(key).get("scene", ""))


static func instantiate(key: String) -> Node3D:
	var path := scene_path(key)
	if path == "":
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D
