extends Camera3D
# @rendering_only_file: camera shake is visual-only; safe to use Godot's
# wall-clock RNG (does not affect game state or replay determinism).

## Isometric-style follow camera with pan. Follows a target by default.
## Player can pan with middle-drag or edge scroll. Snaps back on movement input.
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
var _zoom_min := CAMERA_ZOOM_MIN
var _zoom_max := CAMERA_ZOOM_MAX
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
## Ambient desktop cursor state is not deterministic. Autonomous recordings/replays disable
## mouse-owned camera navigation while retaining keyboard, touch, scripted focus, and recentering.
var _mouse_camera_controls_enabled := true
var _playthrough_input_policy_source: Node
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

# --- Monument-Valley ORTHO ORBIT (the Paranucleus register, director 2026-07-11) ---
# In this mode the level reads as a FLAT IMAGE: perspective is disabled (orthographic), the camera
# orbits a fixed pivot between authored SNAP yaws (Q/E steps to the next vantage, easing there),
# zoom scales the ortho size, and panning stops being spatial movement — with no parallax it is
# simply looking closer at the image (pan slides along the IMAGE plane, camera right + screen up).
# The point of the register: at a given snap angle + ring phase, gaps far apart in 3D can ALIGN in
# the projection — the alignment IS the path (the Monument Valley trick the wheel puzzles build on).
var _ortho_orbit_active := false
var _orbit_pivot := Vector3.ZERO
var _orbit_snaps: Array = []          # authored snap yaws (radians)
var _orbit_yaw := 0.0
var _orbit_target_yaw := 0.0
var _orbit_elev := 0.55               # rad above the horizon
var _orbit_dist := 34.0               # position only — ortho framing comes from `size`
var _orbit_base_size := 20.0          # ortho vertical extent at zoom 1
var _orbit_pan := Vector2.ZERO        # the image pan (view-plane), clamped
var _orbit_pan_max := 10.0
const ORBIT_EASE := 5.0               # snap easing rate (cosmetic, wall-clock)
# When an ORBIT AUTHORITY is installed, the vantage is DATA (a logged world state): Q/E requests a
# step through the level's commit callable instead of turning the camera, and the orbit follows
# the authority's index — the camera is the VIEW of the vantage, never its owner.
var _orbit_authority: Callable = Callable()      # -> int (the data-layer vantage index)
var _orbit_step_request: Callable = Callable()   # (dir: int) -> void (commit a vantage step)

# Touch (Android): TWO fingers pan + pinch-zoom the view. One finger stays gameplay (move/select).
var _touches := {}
var _cam_fingers: Array = []
var _cam_last_mid := Vector2.ZERO
var _cam_last_dist := 1.0

# Pan hint for off-screen targets.
signal pan_hint_triggered(direction: Vector2)

func _ready() -> void:
	sync_playthrough_input_policy()
	_update_immediate()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and not _mouse_camera_controls_enabled:
		_panning = false
		return
	if event.is_action_pressed("camera_zoom_in"):
		_view_zoom = clampf(_view_zoom * CAMERA_ZOOM_STEP, _zoom_min, _zoom_max)
		return
	if event.is_action_pressed("camera_zoom_out"):
		_view_zoom = clampf(_view_zoom / CAMERA_ZOOM_STEP, _zoom_min, _zoom_max)
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
## gesture, and the mobile camera-mode one-finger drag all route here). In ORTHO ORBIT the pan is
## an IMAGE pan (view-plane, no parallax — looking closer at the picture), not spatial movement.
func pan_by(rel: Vector2) -> void:
	if _locked or not _pan_enabled:
		return
	if _ortho_orbit_active:
		_orbit_pan += Vector2(-rel.x, rel.y) * pan_speed * 0.6
		_orbit_pan = _orbit_pan.limit_length(_orbit_pan_max)
		return
	var right := global_transform.basis.x.normalized()
	var forward := Vector3(-global_transform.basis.z.x, 0, -global_transform.basis.z.z).normalized()
	_pan_offset += right * -rel.x * pan_speed
	_pan_offset += forward * rel.y * pan_speed
	if _pan_offset.length() > max_pan_distance:
		_pan_offset = _pan_offset.normalized() * max_pan_distance

# --- Ortho orbit API (region-triggered by the level: enter near the aggregate, exit on leaving) ---

## Switch to the flat-image orbit register around `pivot`, snapping between `snap_yaws`.
## opts: elev / dist / base_size / pan_max override the defaults.
func enter_ortho_orbit(pivot: Vector3, snap_yaws: Array, opts: Dictionary = {}) -> void:
	_orbit_pivot = pivot
	_orbit_snaps = snap_yaws.duplicate() if not snap_yaws.is_empty() else [0.0, PI * 0.5, PI, PI * 1.5]
	_orbit_elev = float(opts.get("elev", _orbit_elev))
	_orbit_dist = float(opts.get("dist", _orbit_dist))
	_orbit_base_size = float(opts.get("base_size", _orbit_base_size))
	_orbit_pan_max = float(opts.get("pan_max", _orbit_pan_max))
	_orbit_pan = Vector2.ZERO
	# start at the snap nearest the current gameplay view, so entry never whips the world around
	# (with a data authority installed, start AT the committed vantage instead)
	_orbit_target_yaw = _nearest_snap(_view_yaw)
	_sync_orbit_to_authority()
	_orbit_yaw = _orbit_target_yaw
	_ortho_orbit_active = true
	projection = PROJECTION_ORTHOGONAL
	size = _orbit_base_size * _view_zoom

## Back to the gameplay follow camera (perspective restored).
func exit_ortho_orbit() -> void:
	_ortho_orbit_active = false
	projection = PROJECTION_PERSPECTIVE

func is_ortho_orbit() -> bool:
	return _ortho_orbit_active

## Bind the orbit to a DATA-LAYER vantage: `authority()` reads the committed index, `step_request(dir)`
## commits a step. Installed by the level that owns the vantage (the Paranucleus register).
func set_orbit_authority(authority: Callable, step_request: Callable) -> void:
	_orbit_authority = authority
	_orbit_step_request = step_request

func _sync_orbit_to_authority() -> void:
	if not _orbit_authority.is_valid() or _orbit_snaps.is_empty():
		return
	var idx := posmod(int(_orbit_authority.call()), _orbit_snaps.size())
	_orbit_target_yaw = float(_orbit_snaps[idx])

## Step to the next authored vantage in `dir` (+1 / -1); the orbit EASES there (cosmetic motion).
## With an authority installed, the step COMMITS through the data layer and the view follows.
func orbit_snap_step(dir: int) -> void:
	if _orbit_step_request.is_valid():
		_orbit_step_request.call(dir)
		_sync_orbit_to_authority()
		return
	if _orbit_snaps.is_empty():
		return
	var idx := 0
	var best := INF
	for i in range(_orbit_snaps.size()):
		var d := absf(wrapf(float(_orbit_snaps[i]) - _orbit_target_yaw, -PI, PI))
		if d < best:
			best = d
			idx = i
	idx = posmod(idx + dir, _orbit_snaps.size())
	_orbit_target_yaw = float(_orbit_snaps[idx])

func orbit_yaw() -> float:
	return _orbit_yaw

func orbit_target_yaw() -> float:
	return _orbit_target_yaw

func _nearest_snap(yaw: float) -> float:
	var best_yaw := yaw
	var best := INF
	for s in _orbit_snaps:
		var d := absf(wrapf(float(s) - yaw, -PI, PI))
		if d < best:
			best = d
			best_yaw = float(s)
	return best_yaw

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
	_view_zoom = clampf(_view_zoom / (dist / _cam_last_dist), _zoom_min, _zoom_max)
	_cam_last_mid = mid
	_cam_last_dist = dist

## Apply a level-authored follow profile without making camera policy global. This is used by
## vertically stacked spaces whose adjacent floors impose a stricter height/zoom envelope than
## ordinary rooms. Snapping after the target is selected avoids an entry lerp through intervening
## geometry, which is especially disorienting on a helix.
func apply_follow_profile(profile: Dictionary, snap_immediately := true) -> void:
	follow_offset = profile.get("follow_offset", follow_offset) as Vector3
	var requested_min := float(profile.get("min_zoom", CAMERA_ZOOM_MIN))
	var requested_max := float(profile.get("max_zoom", CAMERA_ZOOM_MAX))
	_zoom_min = maxf(0.05, minf(requested_min, requested_max))
	_zoom_max = maxf(_zoom_min, maxf(requested_min, requested_max))
	_view_zoom = clampf(float(profile.get("initial_zoom", 1.0)), _zoom_min, _zoom_max)
	if bool(profile.get("reset_yaw", false)):
		_view_yaw = 0.0
	_pan_offset = Vector3.ZERO
	_panning = false
	if snap_immediately:
		_update_immediate()


func _view_offset() -> Vector3:
	return Basis(Vector3.UP, _view_yaw) * (follow_offset * _view_zoom)

func _process(delta: float) -> void:
	if _ortho_orbit_active and not _locked:
		# The flat-image register: Q/E STEP between authored vantages (never free-spin), the yaw
		# eases to its snap, zoom rides the ortho size, and the image pan slides the view plane.
		if Input.is_action_just_pressed("camera_rotate_left"):
			orbit_snap_step(1)
		if Input.is_action_just_pressed("camera_rotate_right"):
			orbit_snap_step(-1)
		_sync_orbit_to_authority()
		_orbit_yaw = lerp_angle(_orbit_yaw, _orbit_target_yaw, minf(1.0, ORBIT_EASE * delta))
		size = _orbit_base_size * _view_zoom
		var dir := Basis(Vector3.UP, _orbit_yaw) * Vector3(0, sin(_orbit_elev), cos(_orbit_elev))
		global_position = _orbit_pivot + dir * _orbit_dist
		look_at(_orbit_pivot, Vector3.UP)
		# the image pan: shift along the view plane AFTER framing — pure 2D, no parallax
		global_position += global_transform.basis.x * _orbit_pan.x + global_transform.basis.y * _orbit_pan.y
		return
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
	if _mouse_camera_controls_enabled and _pan_enabled and not _panning and edge_scroll_margin > 0.0:
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
		if Input.is_action_pressed("camera_pan_forward"):
			wasd_dir += forward
		if Input.is_action_pressed("camera_pan_back"):
			wasd_dir -= forward
		if Input.is_action_pressed("camera_pan_left"):
			wasd_dir -= right
		if Input.is_action_pressed("camera_pan_right"):
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
		global_position = look + _view_offset()
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


## Scripted focus beats must be reversible: preserve the player's deliberate board framing,
## including pan/orbit/zoom, instead of merely restoring the followed character.
func capture_view_state() -> Dictionary:
	return {
		"target": target,
		"follow_offset": follow_offset,
		"pan_offset": _pan_offset,
		"view_yaw": _view_yaw,
		"view_zoom": _view_zoom,
		"global_transform": global_transform,
		"locked": _locked,
		"lock_position": _lock_position,
		"lock_offset_override": _lock_offset_override,
	}


func restore_view_state(state: Dictionary) -> void:
	var was_locked := bool(state.get("locked", false))
	if was_locked:
		_locked = true
		_lock_position = state.get("lock_position", _lock_position) as Vector3
		_lock_offset_override = state.get("lock_offset_override", null)
	else:
		unlock()
	var previous_target = state.get("target", null)
	target = previous_target if previous_target == null or is_instance_valid(previous_target) else null
	follow_offset = state.get("follow_offset", follow_offset) as Vector3
	_pan_offset = state.get("pan_offset", Vector3.ZERO) as Vector3
	_view_yaw = float(state.get("view_yaw", _view_yaw))
	_view_zoom = float(state.get("view_zoom", _view_zoom))
	# A focus shot is presentation-only. Restore the exact prior transform so leaving an
	# inspection cannot produce a one-frame zoom/position jump before normal follow resumes.
	if state.has("global_transform"):
		global_transform = state["global_transform"]


## Frame an inspected object from the already-visible room side. Authored FocusAnchor children win;
## otherwise candidates are rejected when level collision lies between the camera and the object.
## This is deliberately a camera service, not tutorial-scene geometry math, so every story scene gets
## the same wall-safe behavior.
func focus_on(focus_point: Vector3, focus_node: Node3D = null, options: Dictionary = {}) -> Dictionary:
	var chosen := _choose_focus_position(focus_point, focus_node, options)
	var camera_position: Vector3 = chosen.get("position", focus_point + Vector3(0.0, 4.2, 3.2))
	lock_to(focus_point, camera_position - focus_point)
	# Snap directly to the validated side. Lerping through a wall is just as unreadable as
	# choosing a final position behind one.
	global_position = camera_position
	look_at(focus_point, Vector3.UP)
	return chosen


func _choose_focus_position(focus_point: Vector3, focus_node: Node3D, options: Dictionary) -> Dictionary:
	var candidates: Array[Vector3] = []
	var anchor := focus_node.find_child("FocusAnchor", true, false) as Node3D if focus_node != null else null
	if anchor != null:
		candidates.append(anchor.global_position)
	if focus_node != null and focus_node.has_meta("focus_camera_position"):
		var authored_position = focus_node.get_meta("focus_camera_position")
		if authored_position is Vector3:
			candidates.append(authored_position)

	# The current camera is known to be on the player's readable side of the room. Pull that
	# direction inward to inspection distance instead of switching to one global +Z offset.
	var horizontal_distance := maxf(3.6, float(options.get("horizontal_distance", 4.8)))
	var height := maxf(2.4, float(options.get("height", 3.8)))
	var current_flat := global_position - focus_point
	current_flat.y = 0.0
	if current_flat.length_squared() > 0.01:
		candidates.append(focus_point + current_flat.normalized() * horizontal_distance + Vector3.UP * height)

	var preferred_position = options.get("preferred_world_position", Vector3.INF)
	if preferred_position is Vector3 and preferred_position != Vector3.INF:
		var preferred_flat: Vector3 = preferred_position - focus_point
		preferred_flat.y = 0.0
		if preferred_flat.length_squared() > 0.01:
			candidates.append(focus_point + preferred_flat.normalized() * horizontal_distance + Vector3.UP * height)

	# Fallbacks cover rooms entered from unusual angles and targets mounted on different walls.
	for direction in [
		Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT,
		(Vector3.FORWARD + Vector3.LEFT).normalized(),
		(Vector3.FORWARD + Vector3.RIGHT).normalized(),
		(Vector3.BACK + Vector3.LEFT).normalized(),
		(Vector3.BACK + Vector3.RIGHT).normalized(),
	]:
		candidates.append(focus_point + direction * horizontal_distance + Vector3.UP * height)

	for candidate in candidates:
		if _focus_candidate_clear(focus_point, candidate):
			return {"position": candidate, "occlusion_clear": true}
	var fallback := candidates[0] if not candidates.is_empty() else focus_point + Vector3(0.0, height, horizontal_distance)
	return {"position": fallback, "occlusion_clear": false}


func _focus_candidate_clear(focus_point: Vector3, camera_position: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var direction := camera_position - focus_point
	if direction.length_squared() <= 0.01:
		return false
	# Begin just beyond the inspected object's own surface so its cabinet/wall-mounted
	# collision does not reject every otherwise readable shot.
	var ray_start := focus_point + direction.normalized() * 0.35
	var query := PhysicsRayQueryParameters3D.create(ray_start, camera_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

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

## Enable/disable camera controls owned by the desktop mouse: wheel zoom, middle-button drag,
## and edge-scroll. This does not reset framing or disable WASD/touch/scripted camera control.
func set_mouse_camera_controls_enabled(enabled: bool) -> void:
	_mouse_camera_controls_enabled = enabled
	if not enabled:
		_panning = false

func are_mouse_camera_controls_enabled() -> bool:
	return _mouse_camera_controls_enabled

## Apply the camera part of a recording's input-ownership contract. An optional session makes the
## seam directly testable; production scenes resolve the PlaythroughRecorder autoload. The binding
## also restores mouse controls automatically when a non-quitting record/replay session ends.
func sync_playthrough_input_policy(playthrough: Node = null) -> void:
	if playthrough == null:
		playthrough = get_node_or_null("/root/PlaythroughRecorder")
	_bind_playthrough_input_policy(playthrough)
	var ambient_mouse_enabled := true
	if playthrough != null and playthrough.has_method(
		"ambient_mouse_camera_controls_enabled"
	):
		ambient_mouse_enabled = bool(
			playthrough.call("ambient_mouse_camera_controls_enabled")
		)
	elif playthrough != null and playthrough.has_method("is_autonomous_input_session"):
		# Compatibility with an older recorder autoload that predates the explicit
		# persisted camera-policy field.
		ambient_mouse_enabled = not bool(
			playthrough.call("is_autonomous_input_session")
		)
	set_mouse_camera_controls_enabled(ambient_mouse_enabled)

func _bind_playthrough_input_policy(playthrough: Node) -> void:
	if playthrough == _playthrough_input_policy_source:
		return
	var camera_callback := Callable(self, "_on_camera_input_policy_changed")
	var autonomous_callback := Callable(self, "_on_autonomous_input_session_changed")
	if _playthrough_input_policy_source != null \
			and is_instance_valid(_playthrough_input_policy_source):
		if _playthrough_input_policy_source.has_signal("camera_input_policy_changed") \
				and _playthrough_input_policy_source.is_connected(
					"camera_input_policy_changed", camera_callback):
			_playthrough_input_policy_source.disconnect(
				"camera_input_policy_changed", camera_callback)
		if _playthrough_input_policy_source.has_signal(
			"autonomous_input_session_changed"
		) and _playthrough_input_policy_source.is_connected(
			"autonomous_input_session_changed", autonomous_callback
		):
			_playthrough_input_policy_source.disconnect(
				"autonomous_input_session_changed", autonomous_callback)
	_playthrough_input_policy_source = playthrough
	if _playthrough_input_policy_source == null:
		return
	if _playthrough_input_policy_source.has_signal("camera_input_policy_changed"):
		if not _playthrough_input_policy_source.is_connected(
			"camera_input_policy_changed", camera_callback):
			_playthrough_input_policy_source.connect(
				"camera_input_policy_changed", camera_callback)
	elif _playthrough_input_policy_source.has_signal(
		"autonomous_input_session_changed"
	) and not _playthrough_input_policy_source.is_connected(
		"autonomous_input_session_changed", autonomous_callback
	):
		_playthrough_input_policy_source.connect(
			"autonomous_input_session_changed", autonomous_callback)

func _on_camera_input_policy_changed(ambient_mouse_enabled: bool) -> void:
	set_mouse_camera_controls_enabled(ambient_mouse_enabled)

func _on_autonomous_input_session_changed(active: bool) -> void:
	set_mouse_camera_controls_enabled(not active)

## Enable/disable WASD keyboard pan
func set_wasd_pan_enabled(enabled: bool) -> void:
	_wasd_pan_enabled = enabled
	if not enabled:
		_pan_offset = Vector3.ZERO

## Free-look mode: the full "move the camera around" control set in one call — WASD pan + middle-drag pan +
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
