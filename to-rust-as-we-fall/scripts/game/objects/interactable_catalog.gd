class_name InteractableCatalog
extends RefCounted

const CATALOG_PATH := "res://data/interactables/tutorial_interactables.json"
const CATALOG_PATHS := [
	CATALOG_PATH,
]

static var _specs: Dictionary = {}

static func get_spec(spec_id: String) -> Dictionary:
	_ensure_loaded()
	return (_specs.get(spec_id, {}) as Dictionary).duplicate(true)

static func has_spec(spec_id: String) -> bool:
	_ensure_loaded()
	return _specs.has(spec_id)

static func apply_spec(interactable: Node, spec_id: String) -> void:
	if interactable == null or spec_id == "":
		return
	var spec := get_spec(spec_id)
	if spec.is_empty():
		push_warning("Missing interactable spec: %s" % spec_id)
		return
	interactable.set("interactable_id", spec_id)
	if spec.has("interactable_type"):
		interactable.set("interactable_type", _parse_interactable_type(str(spec.interactable_type)))
	if spec.has("dwell_time"):
		interactable.set("dwell_time", float(spec.dwell_time))
	if spec.has("one_shot"):
		interactable.set("one_shot", bool(spec.one_shot))
	if spec.has("interaction_enabled"):
		interactable.set("interaction_enabled", bool(spec.interaction_enabled))
	if spec.has("tutorial_label_key"):
		interactable.set("tutorial_label", DialogueData.text(str(spec.tutorial_label_key)))
	elif spec.has("tutorial_label"):
		interactable.set("tutorial_label", str(spec.tutorial_label))

static func _parse_interactable_type(value: String) -> int:
	match value:
		"INSPECTION":
			return Interactable.InteractableType.INSPECTION
		"HOLD_ACTION":
			return Interactable.InteractableType.HOLD_ACTION
		_:
			push_warning("Unknown interactable type '%s'; using HOLD_ACTION" % value)
			return Interactable.InteractableType.HOLD_ACTION

static func _ensure_loaded() -> void:
	if not _specs.is_empty():
		return
	for path in CATALOG_PATHS:
		if not FileAccess.file_exists(path):
			push_warning("Interactable catalog not found: %s" % path)
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_specs.merge(parsed, true)
		else:
			push_warning("Interactable catalog is not a dictionary: %s" % path)
