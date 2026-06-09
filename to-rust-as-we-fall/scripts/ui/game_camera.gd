extends Camera3D
# @rendering_only_file: camera shake is visual-only; safe to use Godot's
# wall-clock RNG (does not affect game state or replay determinism).

## Isometric-style follow camera with pan. Follows a target by default.
## Player can pan with right-drag or edge scroll. Snaps back on movement input.
## During scripted sequences, can be locked or guided.

@export var target: Node3D
@export var follow_offset := Vector3(0, 12, 8)
@export var follow_speed := 4.0
@export var pan_speed := 0.03
@export var edge_scroll_margin := 40.0
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
var _wasd_pan_enabled := false

# Screen shake state
var _shake_intensity := 0.0
var _shake_decay := 5.0
var _shake_offset := Vector3.ZERO

# Pan hint for off-screen targets.
signal pan_hint_triggered(direction: Vector2)

func _ready() -> void:
	_update_immediate()

func _unhandled_input(event: InputEvent) -> void:
	if _locked:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Middle-drag pans (RTS-style). RIGHT is the move/interact command, LEFT is character-select
		# (owned by the SelectionController) — neither touches the camera. WASD + edge-scroll stay
		# the primary pan affordances (RimWorld-like).
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed

	if event is InputEventMouseMotion and _panning and _pan_enabled:
		var mm := event as InputEventMouseMotion
		var right := global_transform.basis.x.normalized()
		var forward := Vector3(-global_transform.basis.z.x, 0, -global_transform.basis.z.z).normalized()
		_pan_offset += right * -mm.relative.x * pan_speed
		_pan_offset += forward * mm.relative.y * pan_speed
		# Clamp pan distance
		if _pan_offset.length() > max_pan_distance:
			_pan_offset = _pan_offset.normalized() * max_pan_distance

func _process(delta: float) -> void:
	if _locked:
		var goal := _lock_position + follow_offset
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
	var goal := look + follow_offset
	global_position = global_position.lerp(goal, follow_speed * delta) + _shake_offset
	look_at(look, Vector3.UP)

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

## Lock camera to a world position (for scripted sequences)
func lock_to(pos: Vector3) -> void:
	_locked = true
	_lock_position = pos

## Unlock camera back to following the target
func unlock() -> void:
	_locked = false
	_pan_offset = Vector3.ZERO

func is_locked() -> bool:
	return _locked

func get_lock_position() -> Vector3:
	return _lock_position

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
