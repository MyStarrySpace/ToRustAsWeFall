class_name PuzzleFragmentCatalog
extends RefCounted

const Schema = preload("res://scripts/fragments/puzzle_fragment_schema.gd")

const DEFAULT_CATALOG_PATH := "res://data/puzzles/showcase_fragments.json"

var source_path := ""
var data: Dictionary = {}

func _init(path := DEFAULT_CATALOG_PATH) -> void:
	if path != "":
		load_from_file(path)

func load_from_file(path: String) -> bool:
	source_path = path
	data.clear()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	data = parsed
	return true

func get_scene_path() -> String:
	return str(data.get(Schema.KEY_SCENE, ""))

func get_fragments() -> Array:
	var resolved: Array = []
	for raw_fragment in data.get(Schema.KEY_FRAGMENTS, []):
		if typeof(raw_fragment) != TYPE_DICTIONARY:
			continue
		var fragment: Dictionary = raw_fragment.duplicate(true)
		if not fragment.has(Schema.KEY_SCENE):
			fragment[Schema.KEY_SCENE] = get_scene_path()
		resolved.append(fragment)
	return resolved

func find_fragment(fragment_id: String) -> Dictionary:
	for fragment in get_fragments():
		if str(fragment.get(Schema.KEY_ID, "")) == fragment_id:
			return fragment
	return {}
