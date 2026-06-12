@tool
extends Node3D

const DEFAULT_ANIMATION := "idle"
const BEAD_ALPHA := 0.42
const CONNECTOR_THICKNESS := 0.02

var _bead_nodes: Dictionary = {}
var _connections: Array = []
var _connector_segments: Array[MeshInstance3D] = []
var _animation_player: AnimationPlayer
var _connector_material: StandardMaterial3D
var _bead_material: Material

@onready var _model_root: Node3D = $GlassBeadGameModel

func _ready() -> void:
	_rebuild_display()
	set_process(true)

func _process(_delta: float) -> void:
	if not is_instance_valid(_model_root):
		return
	if _connections.is_empty():
		_rebuild_display()
		return
	_play_default_animation()
	_update_connector_segments()

func get_connection_count() -> int:
	return _connections.size()

func get_connection_pairs() -> Array:
	var pairs: Array = []
	for connection in _connections:
		pairs.append("%s-%s" % [connection["a"], connection["b"]])
	return pairs

func _rebuild_display() -> void:
	if not is_instance_valid(_model_root):
		return
	_animation_player = _model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_bead_nodes = _collect_bead_nodes()
	if _bead_nodes.is_empty():
		return
	_apply_bead_materials()
	_connections = _infer_connections()
	_build_connector_segments()
	_play_default_animation()
	_update_connector_segments()

func _collect_bead_nodes() -> Dictionary:
	var bead_nodes := {}
	for node in _model_root.find_children("bead_*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var bead_root := mesh_node.get_parent() as Node3D
		if bead_root:
			bead_nodes[mesh_node.name] = bead_root
	return bead_nodes

func _apply_bead_materials() -> void:
	if _bead_material == null:
		for node in _model_root.find_children("bead_*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			var source := mesh_node.mesh.surface_get_material(0) if mesh_node.mesh and mesh_node.mesh.get_surface_count() > 0 else null
			_bead_material = _make_bead_material(source)
			break

	for node in _model_root.find_children("bead_*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		mesh_node.material_override = _bead_material

func _make_bead_material(source: Material) -> Material:
	if source is BaseMaterial3D:
		var mat := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.08
		mat.metallic = 0.0
		mat.emission_enabled = true
		mat.emission = Color(0.36, 0.91, 0.5)
		mat.emission_energy_multiplier = 0.55
		var tint := mat.albedo_color
		tint.a = BEAD_ALPHA
		mat.albedo_color = tint
		return mat

	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.72, 1.0, 0.8, BEAD_ALPHA)
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fallback.roughness = 0.08
	fallback.emission_enabled = true
	fallback.emission = Color(0.36, 0.91, 0.5)
	fallback.emission_energy_multiplier = 0.55
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	return fallback

func _infer_connections() -> Array:
	var connections: Array = []
	var seen := {}
	for node in _model_root.find_children("connector_*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var connector_root := mesh_node.get_parent() as Node3D
		if connector_root:
			connector_root.visible = false

		var endpoints := _get_connector_endpoints(mesh_node)
		var bead_a := _nearest_bead_name(endpoints[0])
		var bead_b := _nearest_bead_name(endpoints[1], bead_a)
		if bead_a.is_empty() or bead_b.is_empty() or bead_a == bead_b:
			continue

		var pair := [bead_a, bead_b]
		pair.sort()
		var key := "%s:%s" % [pair[0], pair[1]]
		if seen.has(key):
			continue
		seen[key] = true
		connections.append({"a": pair[0], "b": pair[1]})
	return connections

func _get_connector_endpoints(mesh_node: MeshInstance3D) -> Array:
	if mesh_node.mesh == null:
		return [mesh_node.global_position, mesh_node.global_position]
	var aabb := mesh_node.mesh.get_aabb()
	var mid_x := aabb.position.x + aabb.size.x * 0.5
	var mid_z := aabb.position.z + aabb.size.z * 0.5
	var start := mesh_node.to_global(Vector3(mid_x, aabb.position.y, mid_z))
	var finish := mesh_node.to_global(Vector3(mid_x, aabb.position.y + aabb.size.y, mid_z))
	return [start, finish]

func _nearest_bead_name(point: Vector3, exclude := "") -> String:
	var best_name := ""
	var best_distance := INF
	for bead_name in _bead_nodes.keys():
		if bead_name == exclude:
			continue
		var bead_node := _bead_nodes[bead_name] as Node3D
		if bead_node == null:
			continue
		var distance := bead_node.global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best_name = String(bead_name)
	return best_name

func _build_connector_segments() -> void:
	for segment in _connector_segments:
		if is_instance_valid(segment):
			segment.queue_free()
	_connector_segments.clear()

	if _connector_material == null:
		_connector_material = StandardMaterial3D.new()
		_connector_material.albedo_color = Color(0.45, 1.0, 0.62, 0.72)
		_connector_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_connector_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_connector_material.emission_enabled = true
		_connector_material.emission = Color(0.36, 0.91, 0.5)
		_connector_material.emission_energy_multiplier = 0.45
		_connector_material.no_depth_test = true

	for index in range(_connections.size()):
		var segment := MeshInstance3D.new()
		segment.name = "RuntimeConnector%d" % index
		segment.top_level = true
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := BoxMesh.new()
		mesh.size = Vector3(CONNECTOR_THICKNESS, CONNECTOR_THICKNESS, 0.1)
		segment.mesh = mesh
		segment.material_override = _connector_material
		add_child(segment)
		_connector_segments.append(segment)

func _update_connector_segments() -> void:
	for index in range(min(_connections.size(), _connector_segments.size())):
		var connection = _connections[index]
		var bead_a := _bead_nodes.get(connection["a"]) as Node3D
		var bead_b := _bead_nodes.get(connection["b"]) as Node3D
		var segment := _connector_segments[index]
		if bead_a == null or bead_b == null or not is_instance_valid(segment):
			continue

		var start := bead_a.global_position
		var finish := bead_b.global_position
		var direction := finish - start
		var length := direction.length()
		if length <= 0.001:
			segment.visible = false
			continue

		segment.visible = true
		segment.global_position = start.lerp(finish, 0.5)
		var up := Vector3.UP if abs(direction.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		segment.look_at(finish, up)
		var mesh := segment.mesh as BoxMesh
		mesh.size = Vector3(CONNECTOR_THICKNESS, CONNECTOR_THICKNESS, length)

func _play_default_animation() -> void:
	if _animation_player == null:
		return
	var animation_name := DEFAULT_ANIMATION
	if not _animation_player.has_animation(animation_name):
		var animation_list := _animation_player.get_animation_list()
		if animation_list.is_empty():
			return
		animation_name = String(animation_list[0])
	var animation := _animation_player.get_animation(animation_name)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	if _animation_player.current_animation != animation_name or not _animation_player.is_playing():
		_animation_player.play(animation_name)
