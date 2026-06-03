class_name CameraRig
extends Camera2D

## Pan/zoom camera for the sketch canvas. Pan moves the view; zoom keeps the point
## under the gesture fixed. Used by both touch (two-finger) and desktop (wheel/middle).
##
## screen<->world is computed directly from the camera's own state (centre anchor +
## zoom) rather than get_canvas_transform(), which can lag a frame right after the
## zoom changes and make pinch-zoom drift.

const ZOOM_MIN := 0.15
const ZOOM_MAX := 6.0

func pan_screen(delta_screen: Vector2) -> void:
	# Move the world opposite the drag; divide by zoom so a screen-px drag maps to the
	# same on-screen distance whatever the zoom level.
	global_position -= delta_screen / zoom.x

func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	var z := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	var after := screen_to_world(screen_pos)
	global_position += before - after

## Default Camera2D anchor is DRAG_CENTER, so global_position maps to the viewport
## centre; the rest scales by zoom.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return global_position + screen_pos
	var half := viewport.get_visible_rect().size * 0.5
	return global_position + (screen_pos - half) / zoom
