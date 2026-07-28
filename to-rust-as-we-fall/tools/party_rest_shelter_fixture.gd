extends "res://scripts/scene_chunks/scene_chunk.gd"

const SHELTER_CENTER := Vector3(8.0, 0.0, 4.0)
const SHELTER_SIZE := Vector2(6.0, 6.0)
const REQUIRED_MEMBERS := ["aster", "peris"]

var rest_interactable


func _build_chunk() -> void:
	rest_interactable = _add_rest_point(
		self,
		SHELTER_CENTER,
		SHELTER_SIZE,
		REQUIRED_MEMBERS)

