extends Camera3D

## Orbit camera for the level editor.
## Middle-mouse drag to orbit, scroll to zoom, Shift+middle to pan.

@export var target: Vector3 = Vector3.ZERO
@export var distance: float = 20.0
@export var min_distance: float = 3.0
@export var max_distance: float = 80.0
@export var orbit_speed: float = 0.005
@export var pan_speed: float = 0.02
@export var zoom_speed: float = 1.5

var _yaw: float = -PI / 4.0
var _pitch: float = -PI / 5.0
var _dragging_orbit: bool = false
var _dragging_pan: bool = false

func _ready() -> void:
	_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.shift_pressed:
				_dragging_pan = mb.pressed
				_dragging_orbit = false
			else:
				_dragging_orbit = mb.pressed
				_dragging_pan = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_orbit = mb.pressed
			_dragging_pan = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - zoom_speed)
			_update_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + zoom_speed)
			_update_transform()

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			_yaw -= mm.relative.x * orbit_speed
			_pitch -= mm.relative.y * orbit_speed
			_pitch = clamp(_pitch, -PI / 2.0 + 0.05, -0.05)
			_update_transform()
		elif _dragging_pan:
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			target -= right * mm.relative.x * pan_speed * (distance * 0.01)
			target += up * mm.relative.y * pan_speed * (distance * 0.01)
			_update_transform()

func _update_transform() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * distance
	global_position = target - offset
	look_at(target, Vector3.UP)
