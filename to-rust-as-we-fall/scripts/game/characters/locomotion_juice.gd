class_name LocomotionJuice
extends Node

# @rendering_only_file: every transform this node touches is cosmetic — the
# MESH child only, never the body whose position mirrors the data layer.

## The grounded-gait layer (director: "they are literally just floating from
## place to place"). The body node stays a pure mirror of the data layer; this
## node reads the body's per-frame displacement and gives the MESH the read of
## walking: face the travel direction, lean into motion, and step-bob at a
## stride cadence derived from actual speed (so fast-forward and sprints read
## faster automatically). At rest everything converges back to the exact
## authored mesh transform — the InteractableJuice restore law.

const STRIDE_LENGTH := 1.15      # meters per step — bob frequency = speed / stride
const BOB_HEIGHT := 0.07         # per-step hop of the mesh, meters
const LEAN_RADIANS := 0.10       # forward pitch into travel at full walk speed
const FULL_LEAN_SPEED := 2.8     # speed that earns the full lean
const FACE_TURN_RATE := 10.0     # yaw ease toward the travel direction, rad/s
const SETTLE_RATE := 9.0         # how fast bob/lean die at rest
const MIN_MOVE_SPEED := 0.25     # below this the body counts as standing

var _mesh: Node3D
var _base_transform: Transform3D
var _prev_pos := Vector3.INF
var _phase := 0.0
var _bob := 0.0
var _lean := 0.0
var _yaw := 0.0
var _has_yaw := false

func _ready() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_mesh = parent.get_node_or_null("Mesh") as Node3D
	if _mesh != null:
		_base_transform = _mesh.transform

func _process(delta: float) -> void:
	if _mesh == null or delta <= 0.0:
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	var pos := body.global_position
	if _prev_pos == Vector3.INF:
		_prev_pos = pos
		return
	var vel := (pos - _prev_pos) / delta
	_prev_pos = pos
	var horizontal := Vector2(vel.x, vel.z)
	var speed := horizontal.length()
	if speed > MIN_MOVE_SPEED:
		_phase += (speed / STRIDE_LENGTH) * delta
		var step := absf(sin(_phase * PI))
		_bob = step * BOB_HEIGHT
		_lean = LEAN_RADIANS * clampf(speed / FULL_LEAN_SPEED, 0.0, 1.6)
		var target_yaw := atan2(horizontal.x, horizontal.y)
		_yaw = target_yaw if not _has_yaw else lerp_angle(_yaw, target_yaw,
			clampf(FACE_TURN_RATE * delta, 0.0, 1.0))
		_has_yaw = true
	else:
		var settle := clampf(SETTLE_RATE * delta, 0.0, 1.0)
		_bob = lerpf(_bob, 0.0, settle)
		_lean = lerpf(_lean, 0.0, settle)
		if _bob < 0.002 and _lean < 0.002:
			_bob = 0.0
			_lean = 0.0
			_phase = 0.0
	if _bob == 0.0 and _lean == 0.0:
		_mesh.transform = _base_transform
		return
	var gait := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_lean)
	_mesh.transform = Transform3D(
		gait * _base_transform.basis,
		_base_transform.origin + Vector3(0.0, _bob, 0.0))

## Test hook: true only when the mesh sits EXACTLY on its authored transform.
func is_settled() -> bool:
	return _mesh != null and _mesh.transform.is_equal_approx(_base_transform)
