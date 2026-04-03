extends Node3D

## Visual representation of a physics object registered in GameState.
## Reads position from GameState each frame. Handles collision feedback.

var game_state: GameState
var obj_id := ""
var _spin_speed := 0.0

func _process(_delta: float) -> void:
	if not game_state or obj_id == "":
		return
	var pos := game_state.get_physics_position(obj_id)
	global_position = Vector3(pos.x, global_position.y, pos.z)

	if game_state.is_physics_moving(obj_id) and _spin_speed > 0:
		rotate_y(_spin_speed * _delta)

func on_collision(_collider_id: String, _impulse: Vector3) -> void:
	_spin_speed = _impulse.length() * 2.0
	var tween := create_tween()
	tween.tween_property(self, "position:y", global_position.y + 0.15, 0.1)
	tween.tween_property(self, "position:y", global_position.y, 0.15)
	tween.tween_callback(func(): _spin_speed = 0.0).set_delay(0.5)
