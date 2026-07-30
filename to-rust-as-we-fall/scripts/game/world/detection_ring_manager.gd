class_name DetectionRingManager
extends Node3D
## THE REVEAL RING LAYER — render what you simulate (the level-authoring law:
## the player must know the outcome BEFORE committing). While the hold-SHIFT
## reveal is active, every LIVE Enemy shows its watch as ground rings built in
## the DATA frame and warped point-by-point through the scene's coord map, so
## the drawn boundary IS the detection predicate's boundary on any warped
## scene: the red OUTER ring (an exposed character inside it will be spotted)
## and the amber INNER band ring (spotted even under a CONCEAL_MEDIUM hide —
## GameState.DETECTION_INNER_FACTOR). A distracted watcher's rings shrink to
## its actual effective reach (DETECTION_DISTRACTED_FACTOR), so a lured
## sentry's shortened watch is visible truth, not tribal knowledge.
##
## One per scene, created by tutorial_sequence beside the path/outline
## managers (the reusable-infrastructure pattern — never a per-chunk one-off).
## Rings are OPAQUE thin ribbons per the overlay-materials law (a blended
## floor overlay is invisible in the preview scene). Purely cosmetic: reads
## GameState + Enemy nodes, writes nothing.

const SEGMENTS := 64
const RING_WIDTH := 0.11
const LIFT := 0.06
const OUTER_COLOR := Color(0.92, 0.25, 0.16)
const INNER_COLOR := Color(0.98, 0.7, 0.2)

var _gs
var _scene_root: Node
var _active := false
var _rings: Array = []

func setup(game_state, scene_root: Node) -> void:
	_gs = game_state
	_scene_root = scene_root

func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if not active:
		_clear()

func is_active() -> bool:
	return _active

func ring_count() -> int:
	return _rings.size()

func _process(_delta: float) -> void:
	if not _active or _gs == null:
		return
	_clear()
	_build_all()

## Headless/test entry: build the current rings without waiting on a frame.
func rebuild_now() -> void:
	_clear()
	if _active:
		_build_all()

func _clear() -> void:
	for r in _rings:
		if is_instance_valid(r):
			(r as Node).queue_free()
	_rings.clear()

func _build_all() -> void:
	if _scene_root == null:
		return
	var stack: Array = [_scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Enemy:
			_build_enemy_rings(n as Enemy)
		for c in n.get_children():
			stack.append(c)

func _build_enemy_rings(enemy: Enemy) -> void:
	if not enemy.is_alive() or enemy.char_id == "" \
			or not _gs.characters.has(enemy.char_id):
		return
	var outer := float((_gs.characters[enemy.char_id].stats as Dictionary).get(
		"detection_range", 0.0))
	if outer <= 0.0:
		return
	if _gs.has_method("is_character_distracted") \
			and bool(_gs.call("is_character_distracted", enemy.char_id)):
		outer *= _gs.DETECTION_DISTRACTED_FACTOR
	var center: Vector3 = _gs.get_position(enemy.char_id)
	_rings.append(_spawn_ring(center, outer, OUTER_COLOR))
	_rings.append(_spawn_ring(center, outer * _gs.DETECTION_INNER_FACTOR, INNER_COLOR))

func _to_world(data_point: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_world(data_point)
	return data_point

## A flat ring ribbon: DATA-frame circle, every vertex warped independently so
## the ring hugs the helix (or any coord map) instead of slicing through it.
func _spawn_ring(center: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in range(SEGMENTS + 1):
		var a := TAU * float(k) / float(SEGMENTS)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var p_out: Vector3 = _to_world(center + dir * (radius + RING_WIDTH * 0.5))
		var p_in: Vector3 = _to_world(center + dir * (radius - RING_WIDTH * 0.5))
		st.set_normal(Vector3.UP)
		st.add_vertex(p_out + Vector3.UP * LIFT)
		st.set_normal(Vector3.UP)
		st.add_vertex(p_in + Vector3.UP * LIFT)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
