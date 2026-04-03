extends Camera3D

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
var _following := true
var _locked := false
var _lock_position := Vector3.ZERO
var _wasd_pan_enabled := false

# Screen shake state
var _shake_intensity := 0.0
var _shake_decay := 5.0
var _shake_offset := Vector3.ZERO

# Pan hint — emitted when something is off-screen and the player might want to pan
signal pan_hint_triggered(direction: Vector2)

func _ready() -> void:
	_update_immediate()

func _unhandled_input(event: InputEvent) -> void:
	if _locked:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
		# Left click snaps camera back to target
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pan_offset = Vector3.ZERO

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

	var goal := target.global_position + follow_offset + _pan_offset
	global_position = global_position.lerp(goal, follow_speed * delta) + _shake_offset
	look_at(target.global_position + _pan_offset, Vector3.UP)

func _update_immediate() -> void:
	if target:
		global_position = target.global_position + follow_offset
		look_at(target.global_position, Vector3.UP)

## Lock camera to a world position (for scripted sequences)
func lock_to(pos: Vector3) -> void:
	_locked = true
	_lock_position = pos

## Unlock camera back to following the target
func unlock() -> void:
	_locked = false
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
