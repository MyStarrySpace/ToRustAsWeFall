class_name CleanstreetsSpikeLane
extends Node3D

## Authored Cleanstreets hostile architecture. The fixture is instanced from a scene; this script only carries
## its flat-space gameplay contract because the rendered root may later be wrapped onto a helix. Generated
## stretches place it exclusively on navigation risk cells, so SAFE preview and continuous damage describe the
## same consequence before and after commitment.

@export var half_size := Vector2(0.46, 0.46)
@export var damage_per_second := 4.0

var flat_position := Vector3.ZERO
var flat_rotation_y := 0.0


func configure(setpiece: Dictionary) -> void:
	flat_position = _vec3(setpiece.get("position", []), position)
	flat_rotation_y = float(setpiece.get("rotation_y", 0.0))
	position = flat_position
	rotation.y = flat_rotation_y
	var raw_half: Variant = setpiece.get("half_size", [])
	if raw_half is Array and (raw_half as Array).size() >= 2:
		half_size = Vector2(float(raw_half[0]), float(raw_half[1]))
	damage_per_second = maxf(0.0, float(setpiece.get("damage_per_second", damage_per_second)))
	var label := get_node_or_null("Feedback/WarningLabel") as Label3D
	if label != null:
		label.visible = bool(setpiece.get("show_label", false))


func covers_flat(world_position: Vector3) -> bool:
	var relative := Vector2(world_position.x - flat_position.x, world_position.z - flat_position.z)
	var local := relative.rotated(flat_rotation_y)
	return absf(local.x) <= half_size.x and absf(local.y) <= half_size.y


func _vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback
