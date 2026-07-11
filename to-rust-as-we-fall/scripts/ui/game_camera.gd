extends Camera3D
# @rendering_only_file: camera shake is visual-only; safe to use Godot's
# wall-clock RNG (does not affect game state or replay determinism).

## Isometric-style follow camera with pan. Follows a target by default.
## Player can pan with right-drag or edge scroll. Snaps back on movement input.
## During scripted sequences, can be locked or guided.

@export var target: Node3D
@export var follow_offset := Vector3(0, 12, 8)

# Player camera controls: Q/E orbit the view around the target; the wheel zooms by scaling the
# follow offset. Mobile later maps pinch to zoom and two-finger drag/twist to pan/rotate.
const CAMERA_ROTATE_SPEED := 1.6   # rad/sec while Q/E held
const CAMERA_ZOOM_STEP := 0.9      # wheel notch multiplier
const CAMERA_ZOOM_MIN := 0.45
const CAMERA_ZOOM_MAX := 2.2
var _view_yaw := 0.0
var _view_zoom := 1.0
@export var follow_speed := 4.0
@export var pan_speed := 0.03
## Edge-scroll fires only when the cursor is hard against the screen edge. A wide margin (this was 40)
## catches ordinary cursor travel toward a click target and silently pans the view mid-play.
@export var edge_scroll_margin := 6.0
@export var edge_scroll_speed := 8.0
@export var max_pan_distance := 15.0
@export var wasd_pan_speed := 10.0

var _pan_offset := Vector3.ZERO
var _panning := false
var _pan_enabled := true
# Optional world-space clamp on the look-at point (X/Z), so pan/edge-scroll can't
# push the view outside a confined room (e.g. the elevator). Inactive by default.
var _look_bounds_active := false
var _look_bounds_min := Vector3.ZERO
var _look_bounds_max := Vector3.ZERO
var _following := true
var _locked := false
var _lock_position := Vector3.ZERO
var _lock_offset_override = null  # Vector3 to frame the lock from a fixed direction; null = gameplay offset
var _wasd_pan_enabled := false

# Screen shake state
var _shake_intensity := 0.0
var _shake_decay := 5.0
var _shake_offset := Vector3.ZERO

# Touch (Android): TWO fingers pan + pinch-zoom the view. One finger stays gameplay (move/select).
var _touches := {}
var _cam_fingers: Array = []
var _cam_last_mid := Vector2.ZERO
var _cam_last_dist := 1.0

# Pan hint for off-screen targets.
signal pan_hint_triggered(direction: Vector2)

func _ready() -> void:
	_update_immediate()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_view_zoom = clampf(_view_zoom * CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
		return
	if event.is_action_pressed("camera_zoom_out"):
		_view_zoom = clampf(_view_zoom / CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
		return
	if _locked:
		return

	if event is InputEventScreenTouch:
		_on_cam_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_on_cam_drag(event as InputEventScreenDrag)
		return

	if event is InputEventMouseButton:
		# `camera_pan` (middle mouse) drags the view (RTS-style). `command` (right) and `select` (left)
		# are gameplay, not camera. WASD + edge-scroll stay the primary pan affordances (RimWorld-like).
		if event.is_action_pressed("camera_pan"):
			_panning = true
		elif event.is_action_released("camera_pan"):
			_panning = false

	if event is InputEventMouseMotion and _panning and _pan_enabled:
		pan_by((event as InputEventMouseMotion).relative)

## Drag the view by a screen-space delta — the shared pan math (middle-mouse drag, the two-finger
## gesture, and the mobile camera-mode one-finger drag all route here).
func pan_by(rel: Vector2) -> void:
	if _locked or not _pan_enabled:
		return
	var right := global_transform.basis.x.normalized()
	var forward := Vector3(-global_transform.basis.z.x, 0, -global_transform.basis.z.z).normalized()
	_pan_offset += right * -rel.x * pan_speed
	_pan_offset += forward * rel.y * pan_speed
	if _pan_offset.length() > max_pan_distance:
		_pan_offset = _pan_offset.normalized() * max_pan_distance

func _on_cam_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
	else:
		_touches.erase(t.index)
	if _touches.size() >= 2:
		_cam_fingers = _touches.keys().slice(0, 2)
		_reseed_cam()
	else:
		_cam_fingers = []

func _on_cam_drag(d: InputEventScreenDrag) -> void:
	_touches[d.index] = d.position
	if _touches.size() >= 2 and _cam_pair():
		_update_cam_gesture()

func _cam_pair() -> bool:
	return _cam_fingers.size() >= 2 and _touches.has(_cam_fingers[0]) and _touches.has(_cam_fingers[1])

func _reseed_cam() -> void:
	if not _cam_pair():
		return
	var p0: Vector2 = _touches[_cam_fingers[0]]
	var p1: Vector2 = _touches[_cam_fingers[1]]
	_cam_last_mid = (p0 + p1) * 0.5
	_cam_last_dist = maxf(1.0, p0.distance_to(p1))

## Two-finger drag pans (same right/forward mapping as the middle-mouse pan) + pinch zooms (spread = zoom in).
func _update_cam_gesture() -> void:
	var p0: Vector2 = _touches[_cam_fingers[0]]
	var p1: Vector2 = _touches[_cam_fingers[1]]
	var mid := (p0 + p1) * 0.5
	var dist := maxf(1.0, p0.distance_to(p1))
	pan_by(mid - _cam_last_mid)
	_view_zoom = clampf(_view_zoom / (dist / _cam_last_dist), CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	_cam_last_mid = mid
	_cam_last_dist = dist

func _view_offset() -> Vector3:
	return Basis(Vector3.UP, _view_yaw) * (follow_offset * _view_zoom)

func _process(delta: float) -> void:
	if Input.is_action_pressed("camera_rotate_left"):
		_view_yaw += CAMERA_ROTATE_SPEED * delta
	if Input.is_action_pressed("camera_rotate_right"):
		_view_yaw -= CAMERA_ROTATE_SPEED * delta
	if _locked:
		var off: Vector3 = _lock_offset_override if _lock_offset_override != null else _view_offset()
		var goal := _lock_position + off
		global_position = global_position.lerp(goal, follow_speed * delta)
		# Apply shake even when locked
		if _shake_intensity > 0.001:
			_shake_offset = Vector3(
				randf_range(-_shake_intensity, _shake_intensity),
				randf_range(-_shake_intensity * 0.5, _shake_intensity * 0.5),
				randf_range(-_shake_intensity, _shake_intensity)
			)
			_shake_intensity = lerpf(_shake_intensity, 0.0, _shake_decay * delta)
			global_position += _shake_offset
		else:
			_shake_offset = Vector3.ZERO
			_shake_intensity = 0.0
		look_at(_lock_position, Vector3.UP)
		return

	if not target:
		return

	# Edge scrolling (when not dragging)
	if _pan_enabled and not _panning:
		var vp := get_viewport()
		if vp:
			var mouse := vp.get_mouse_position()
			var size := vp.get_visible_rect().size
			var edge_pan := Vector3.ZERO
			var right := global_transform.basis.x.normalized()
			var forward := Vector3(-global_transform.basis.z.x, 0, -global_transform.basis.z.z).normalized()
			if mouse.x < edge_scroll_margin:
				edge_pan -= right * edge_scroll_speed * delta
			elif mouse.x > size.x - edge_scroll_margin:
				edge_pan += right * edge_scroll_speed * delta
			if mouse.y < edge_scroll_margin:
				edge_pan += forward * edge_scroll_speed * delta
			elif mouse.y > size.y - edge_scroll_margin:
				edge_pan -= forward * edge_scroll_speed * delta
			if edge_pan.length() > 0:
				_pan_offset += edge_pan
				if _pan_offset.length() > max_pan_distance:
					_pan_offset = _pan_offset.normalized() * max_pan_distance

	# WASD pan (keyboard-driven, used during corridor sequences)
	if _wasd_pan_enabled and _pan_enabled and not _locked:
		var wasd_dir := Vector3.ZERO
		var right := global_transform.basis.x.normalized()
		var forward := Vector3(-global_transform.basis.z.x, 0, -global_transform.basis.z.z).normalized()
		if Input.is_key_pressed(KEY_W):
			wasd_dir += forward
		if Input.is_key_pressed(KEY_S):
			wasd_dir -= forward
		if Input.is_key_pressed(KEY_A):
			wasd_dir -= right
		if Input.is_key_pressed(KEY_D):
			wasd_dir += right
		if wasd_dir.length() > 0:
			_pan_offset += wasd_dir.normalized() * wasd_pan_speed * delta
			if _pan_offset.length() > max_pan_distance:
				_pan_offset = _pan_offset.normalized() * max_pan_distance

	# Shake decay
	if _shake_intensity > 0.001:
		_shake_offset = Vector3(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity * 0.5, _shake_intensity * 0.5),
			randf_range(-_shake_intensity, _shake_intensity)
		)
		_shake_intensity = lerpf(_shake_intensity, 0.0, _shake_decay * delta)
	else:
		_shake_offset = Vector3.ZERO
		_shake_intensity = 0.0

	var look := _clamp_look(target.global_position + _pan_offset)
	var goal := look + _view_offset()
	global_position = global_position.lerp(goal, follow_speed * delta) + _shake_offset
	# CONSTANT orientation: always aim along -follow_offset (the steady-state view direction), never at
	# the live look point. Aiming at the look point while the position is still lerping toward it makes
	# the camera visibly ROTATE during every follow/pan catch-up (the "rotates itself at an odd angle"
	# wobble); with a fixed orientation the catch-up is a pure glide.
	look_at(global_position - _view_offset(), Vector3.UP)

func _update_immediate() -> void:
	if target:
		var look := _clamp_look(target.global_position)
		global_position = look + follow_offset
		look_at(look, Vector3.UP)

## Clamp a look-at point to the active bounds (X/Z), keeping the view inside a
## confined room. Y and the point are unchanged when no bounds are set.
func _clamp_look(point: Vector3) -> Vector3:
	if not _look_bounds_active:
		return point
	return Vector3(
		clampf(point.x, _look_bounds_min.x, _look_bounds_max.x),
		point.y,
		clampf(point.z, _look_bounds_min.z, _look_bounds_max.z)
	)

## Constrain the look-at point to a world-space X/Z box (e.g. a room interior).
func set_look_bounds(min_corner: Vector3, max_corner: Vector3) -> void:
	_look_bounds_active = true
	_look_bounds_min = min_corner
	_look_bounds_max = max_corner

func clear_look_bounds() -> void:
	_look_bounds_active = false

## Lock camera to a world position (for scripted sequences). An optional `offset_override` frames the
## lock from a FIXED direction (camera sits at pos + offset, ignoring the gameplay view yaw/zoom) — use
## it to look at a screen head-on instead of from whatever angle the player left the camera at. Pass
## null to keep the normal gameplay offset.
func lock_to(pos: Vector3, offset_override = null) -> void:
	_locked = true
	_lock_position = pos
	_lock_offset_override = offset_override

## Unlock camera back to following the target
func unlock() -> void:
	_locked = false
	_lock_offset_override = null
	_pan_offset = Vector3.ZERO

func is_locked() -> bool:
	return _locked

func get_lock_position() -> Vector3:
	return _lock_position

## Frame the view on a world point (e.g. the party centroid) WITHOUT locking — steer the follow pan
## so the look point lands on `world_point`, then let the normal glide + look-bounds carry it there.
## No-ops while locked so it can't fight a scripted focus (exploration-focus owns the lock).
func recenter_on(world_point: Vector3) -> void:
	if _locked or target == null:
		return
	_panning = false
	var d := world_point - target.global_position
	_pan_offset = Vector3(d.x, 0.0, d.z)   # keep the look on the floor plane
	if _pan_offset.length() > max_pan_distance:
		_pan_offset = _pan_offset.normalized() * max_pan_distance

## Recenter on the current follow target, discarding any manual WASD/edge/drag pan.
func recenter() -> void:
	if _locked:
		return
	_panning = false
	_pan_offset = Vector3.ZERO

## Enable/disable player pan control
func set_pan_enabled(enabled: bool) -> void:
	_pan_enabled = enabled
	if not enabled:
		_pan_offset = Vector3.ZERO

## Enable/disable WASD keyboard pan
func set_wasd_pan_enabled(enabled: bool) -> void:
	_wasd_pan_enabled = enabled
	if not enabled:
		_pan_offset = Vector3.ZERO

## Free-look mode: the full "move the camera around" control set in one call — WASD pan + right-drag pan +
## edge-scroll, with a generous pan radius. A left click still recenters on the target, so it never blocks
## click-to-move. Modular replacement for the per-scene set_pan_enabled / set_wasd_pan_enabled / max_pan
## triple — use this anywhere the player should be able to look around (the chunk preview, free-cam testing).
func enable_free_look(max_distance := 40.0) -> void:
	max_pan_distance = max_distance
	set_pan_enabled(true)
	set_wasd_pan_enabled(true)

## Turn free-look off and snap the view back to the target (e.g. when a scripted/locked beat takes over).
func disable_free_look(reset_max_distance := 15.0) -> void:
	set_wasd_pan_enabled(false)
	set_pan_enabled(false)
	max_pan_distance = reset_max_distance

func is_free_look() -> bool:
	return _pan_enabled and _wasd_pan_enabled

## Trigger screen shake. Intensity is the max offset in world units.
## Decay rate controls how fast it fades (higher = faster).
func shake(intensity: float = 0.3, decay: float = 5.0) -> void:
	_shake_intensity = intensity
	_shake_decay = decay

## Check if a world position is visible on screen (for pan hints)
func is_position_on_screen(world_pos: Vector3) -> bool:
	if not is_position_behind(world_pos):
		var screen := unproject_position(world_pos)
		var rect := get_viewport().get_visible_rect()
		return rect.has_point(screen)
	return false
