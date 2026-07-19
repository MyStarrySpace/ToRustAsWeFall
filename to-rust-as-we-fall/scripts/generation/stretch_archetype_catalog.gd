class_name StretchArchetypeCatalog
extends RefCounted

const DEFAULT_ARCHETYPE_PATH := "res://data/generation/archetype_catalog.json"
const DEFAULT_PALETTE_PATH := "res://data/generation/content_palette.json"

var archetype_path := DEFAULT_ARCHETYPE_PATH
var palette_path := DEFAULT_PALETTE_PATH
var archetype_data: Dictionary = {}
var palette_data: Dictionary = {}
var errors: Array[String] = []

func _init(load_default := true) -> void:
	if load_default:
		load_from_files()

func load_from_files(next_archetype_path := DEFAULT_ARCHETYPE_PATH, next_palette_path := DEFAULT_PALETTE_PATH) -> bool:
	archetype_path = next_archetype_path
	palette_path = next_palette_path
	errors.clear()
	archetype_data = _load_json_dict(archetype_path)
	palette_data = _load_json_dict(palette_path)
	if archetype_data.is_empty():
		errors.append("Missing or invalid archetype catalog: %s" % archetype_path)
	if palette_data.is_empty():
		errors.append("Missing or invalid content palette: %s" % palette_path)
	var validation := validate()
	return bool(validation.get("valid", false))

func validate() -> Dictionary:
	var local_errors: Array[String] = []
	var archetypes: Dictionary = archetype_data.get("archetypes", {})
	var spatial_affordance_count := 0
	for id in range(1, 12):
		if not archetypes.has(str(id)):
			local_errors.append("Missing archetype %d" % id)
	for id in archetypes.keys():
		if not (archetypes[id] is Dictionary):
			continue
		var archetype := archetypes[id] as Dictionary
		var affordances: Variant = archetype.get("spatial_affordances", [])
		if not (affordances is Array):
			local_errors.append("Archetype %s spatial_affordances must be an array" % str(id))
			continue
		for raw_affordance in affordances as Array:
			spatial_affordance_count += 1
			if not (raw_affordance is Dictionary):
				local_errors.append("Archetype %s has a non-dictionary spatial affordance" % str(id))
				continue
			var affordance := raw_affordance as Dictionary
			for required_key in ["id", "feature_kind", "primary_insight", "leverage"]:
				if str(affordance.get(required_key, "")).strip_edges() == "":
					local_errors.append("Archetype %s spatial affordance requires %s" % [str(id), required_key])
			if (affordance.get("emergent_inputs", []) as Array).size() < 3:
				local_errors.append("Archetype %s spatial affordance needs at least three emergent inputs" % str(id))
			for variant in affordance.get("variants", []):
				if not (archetype.get("variants", []) as Array).has(str(variant)):
					local_errors.append("Archetype %s spatial affordance names unknown variant %s" % [str(id), str(variant)])
	for category in ["flora", "enemies", "structures"]:
		if not (palette_data.get(category, {}) is Dictionary):
			local_errors.append("Missing palette category %s" % category)
	if not local_errors.is_empty():
		errors.append_array(local_errors)
	return {
		"valid": local_errors.is_empty() and errors.is_empty(),
		"errors": errors.duplicate(),
		"archetype_count": archetypes.size(),
		"spatial_affordance_count": spatial_affordance_count,
		"flora_count": get_content_keys("flora").size(),
		"enemy_count": get_content_keys("enemies").size(),
		"structure_count": get_content_keys("structures").size(),
	}

func get_archetype_ids() -> Array[String]:
	var ids: Array[String] = []
	var archetypes: Dictionary = archetype_data.get("archetypes", {})
	for key in archetypes.keys():
		ids.append(str(key))
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return ids

func get_archetype(id: Variant) -> Dictionary:
	var archetypes: Dictionary = archetype_data.get("archetypes", {})
	var key := str(id)
	if archetypes.has(key) and archetypes[key] is Dictionary:
		return (archetypes[key] as Dictionary).duplicate(true)
	return {}

func has_archetype(id: Variant) -> bool:
	return not get_archetype(id).is_empty()

func get_content_keys(category: String) -> Array[String]:
	var keys: Array[String] = []
	var section: Variant = palette_data.get(category, {})
	if section is Dictionary:
		for key in (section as Dictionary).keys():
			keys.append(str(key))
	keys.sort()
	return keys

func get_content(category: String, key: String) -> Dictionary:
	var section: Variant = palette_data.get(category, {})
	if section is Dictionary and (section as Dictionary).has(key):
		var entry: Variant = (section as Dictionary)[key]
		if entry is Dictionary:
			return (entry as Dictionary).duplicate(true)
	return {}

func has_content(category: String, key: String) -> bool:
	return not get_content(category, key).is_empty()

func support_level(category: String, key: String) -> String:
	return str(get_content(category, key).get("support", "placeholder"))

static func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
