class_name PatrolReconReceiver
extends Node3D

## Visible authority for a Recon terminal's one effect: revealing authored patrol routes.
##
## The receiver owns both the saved consequence and its presentation. The terminal only mints a
## typed command after consuming its own GameState interaction receipt. Route geometry is planning
## information: after it has been revealed, it is visible only through Aster's data overlay while
## the simulation is paused/planning. It never moves or reconfigures an enemy.

const STATE_CONTRACT := "patrol_recon_receiver/v1"
const AUTHORITY_PREFIX := "gameplay:patrol_recon:"
const TERMINAL_CONTRACT := "typed_terminal/v1"
const TERMINAL_ID_PREFIX := "typed_terminal:"
const TERMINAL_KEY_PREFIX := "gameplay:typed_terminal:"
const POSITION_EPSILON := 0.05
const TICK_EPSILON := 0.000001
const ASTER_TINT := Color(0.29, 0.74, 1.0)
const LINE_HEIGHT := 0.075
const CHEVRON_SPACING := 6.0
const CHEVRON_SPEED := 2.8
const CHEVRONS_PER_ROUTE := 5

var _game_state = null
var _stable_id := ""
var _routes: Array[Array] = []
var _route_lengths: Array[float] = []
var _route_root: Node3D
var _chevrons: Array[Dictionary] = []
var _revealed := false
var _accepted_source_id := ""
var _accepted_trigger_count := 0
var _accepted_tick := -1.0
var _aster_overlay_active := false
var _planning_active := false
var _configured := false


func configure(game_state, stable_id: String, routes: Array) -> bool:
	if _configured or game_state == null or stable_id.strip_edges().is_empty():
		return false
	var normalized := _normalize_routes(routes)
	if normalized.is_empty():
		return false
	_game_state = game_state
	_stable_id = stable_id.strip_edges()
	_routes = normalized
	_configured = true
	_build_route_presentation()
	_restore_authority_or_baseline()
	set_process(true)
	return true


func can_accept_terminal_command(command: Dictionary) -> bool:
	if not _configured or _revealed:
		return false
	var normalized := _normalize_command(command)
	return not normalized.is_empty() and _live_source_matches(normalized)


func accept_terminal_command(command: Dictionary) -> bool:
	if not can_accept_terminal_command(command):
		return false
	var receipt := _normalize_command(command)
	_revealed = true
	_accepted_source_id = str(receipt.get("source_id", ""))
	_accepted_trigger_count = int(receipt.get("source_trigger_count", 0))
	_accepted_tick = float(receipt.get("accepted_tick", _scheduler_tick()))
	_publish_authority()
	_apply_visibility()
	return true


func _normalize_command(command: Dictionary) -> Dictionary:
	if str(command.get("family", "")) != "terminal" \
			or str(command.get("subtype", "")) != "recon" \
			or str(command.get("effect", "")) != "reveal" \
			or str(command.get("actor", "")) != "aster":
		return {}
	var source_id := str(command.get("source_id", ""))
	if not source_id.begins_with(TERMINAL_ID_PREFIX) \
			or source_id.length() <= TERMINAL_ID_PREFIX.length():
		return {}
	var stable_id := source_id.trim_prefix(TERMINAL_ID_PREFIX)
	var source_key := str(command.get("source_authority_key", ""))
	var trigger_count := int(command.get("source_trigger_count", 0))
	var source_position := _vector(command.get("source_position", []))
	var accepted_tick := float(command.get("accepted_tick", -1.0))
	if source_key != TERMINAL_KEY_PREFIX + stable_id or trigger_count <= 0 \
			or not source_position.is_finite() or not is_finite(accepted_tick) \
			or accepted_tick < 0.0:
		return {}
	return {
		"family": "terminal",
		"subtype": "recon",
		"effect": "reveal",
		"source_id": source_id,
		"source_authority_key": source_key,
		"source_trigger_count": trigger_count,
		"actor": "aster",
		"source_position": [source_position.x, source_position.y, source_position.z],
		"accepted_tick": accepted_tick,
	}


func _live_source_matches(command: Dictionary) -> bool:
	var source_id := str(command.get("source_id", ""))
	if _game_state == null or not _game_state.characters.has("aster") \
			or not _game_state.has_interactable(source_id) or _game_state.scheduler == null:
		return false
	var source: Dictionary = _game_state.get_interactable(source_id)
	if not _registry_receipt_matches(source, command):
		return false
	var source_position := _vector(command.get("source_position", []))
	var registered_position := _vector(source.get("position", Vector3(INF, INF, INF)))
	if source_position.distance_to(registered_position) > POSITION_EPSILON:
		return false
	var radius := maxf(0.0, float(source.get("radius", 0.0)))
	if _game_state.get_position("aster").distance_to(registered_position) \
			> radius + POSITION_EPSILON:
		return false
	var now := float(_game_state.scheduler.get_current_tick())
	return absf(float(command.get("accepted_tick", -1.0)) - now) <= TICK_EPSILON \
		and _source_authority_matches(command)


func _registry_receipt_matches(source: Dictionary, command: Dictionary) -> bool:
	return bool(source.get("one_shot", false)) \
		and bool(source.get("triggered", false)) \
		and not bool(source.get("enabled", true)) \
		and int(source.get("trigger_count", 0)) \
			== int(command.get("source_trigger_count", -1)) \
		and str(source.get("last_trigger_character", "")) == "aster"


func _source_authority_matches(command: Dictionary) -> bool:
	var raw: Variant = _game_state.get_world_state(
		str(command.get("source_authority_key", "")), {})
	if not (raw is Dictionary):
		return false
	var source := raw as Dictionary
	if str(source.get("contract", "")) != TERMINAL_CONTRACT \
			or not (source.get("command", null) is Dictionary):
		return false
	var normalized := _normalize_command(source.get("command", {}) as Dictionary)
	return not normalized.is_empty() and normalized == command


func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)


func authority_state_key() -> String:
	return AUTHORITY_PREFIX + _stable_id


func is_revealed() -> bool:
	return _revealed


func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"authority_id": authority_state_key(),
		"revealed": _revealed,
		"accepted_source_id": _accepted_source_id,
		"accepted_trigger_count": _accepted_trigger_count,
		"accepted_tick": _accepted_tick,
		"route_count": _routes.size(),
		"visible": _route_root != null and _route_root.visible,
		"aster_overlay_active": _aster_overlay_active,
		"planning_active": _planning_active,
	}


func get_mechanism_spec() -> Dictionary:
	return {
		"family": "terminal_receiver",
		"subtype": "recon",
		"effect": "reveal",
		"owner_character": "aster",
		"state_contract": STATE_CONTRACT,
		"authority_key": authority_state_key(),
	}


func set_overlay_context(aster_visible: bool, planning: bool) -> void:
	_aster_overlay_active = aster_visible
	_planning_active = planning
	_apply_visibility()


func set_preview_planning_feedback(active: bool) -> void:
	_planning_active = active
	_apply_visibility()


func reset_reveal() -> bool:
	if not _configured:
		return false
	_revealed = false
	_accepted_source_id = ""
	_accepted_trigger_count = 0
	_accepted_tick = -1.0
	_publish_authority()
	_apply_visibility()
	return true


func on_game_state_snapshot_restored() -> void:
	_restore_authority_or_baseline()


func _process(_delta: float) -> void:
	if _route_root == null or not _route_root.visible:
		return
	_update_chevrons(_scheduler_tick())


func _normalize_routes(raw_routes: Array) -> Array[Array]:
	var normalized: Array[Array] = []
	for route_variant in raw_routes:
		if not (route_variant is Array):
			return []
		var route: Array[Vector3] = []
		for point_variant in route_variant as Array:
			if not (point_variant is Vector3) or not (point_variant as Vector3).is_finite():
				return []
			var point := point_variant as Vector3
			if route.is_empty() or route[-1].distance_to(point) > 0.01:
				route.append(point)
		if route.size() < 2:
			return []
		normalized.append(route)
	return normalized


func _build_route_presentation() -> void:
	_route_root = Node3D.new()
	_route_root.name = "RevealedPatrolRoutes"
	add_child(_route_root)
	_route_lengths.clear()
	_chevrons.clear()
	for route_index in range(_routes.size()):
		var route := _routes[route_index]
		var route_length := _route_length(route)
		_route_lengths.append(route_length)
		for point_index in range(route.size() - 1):
			_add_line_segment(route[point_index], route[point_index + 1], route_index, point_index)
		var marker_count := clampi(int(floor(route_length / CHEVRON_SPACING)), 2, CHEVRONS_PER_ROUTE)
		for marker_index in range(marker_count):
			var marker := _build_chevron(route_index, marker_index)
			_route_root.add_child(marker)
			_chevrons.append({
				"node": marker,
				"route_index": route_index,
				"phase": float(marker_index) / float(marker_count),
			})
	_apply_visibility()


func _add_line_segment(a: Vector3, b: Vector3, route_index: int, segment_index: int) -> void:
	var delta := b - a
	var planar := Vector3(delta.x, 0.0, delta.z)
	var length := planar.length()
	if length <= 0.01:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "RouteLine_%d_%d" % [route_index, segment_index]
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.025, length)
	mesh.mesh = box
	mesh.position = (a + b) * 0.5
	mesh.position.y = maxf(a.y, b.y) + LINE_HEIGHT
	mesh.basis = _basis_with_z(planar.normalized())
	var line_color := Color(ASTER_TINT.r, ASTER_TINT.g, ASTER_TINT.b, 0.42)
	mesh.material_override = _route_material(line_color, 0.85)
	mesh.set_meta("camera_occlusion_exempt", true)
	_route_root.add_child(mesh)


func _build_chevron(route_index: int, marker_index: int) -> Node3D:
	var marker := Node3D.new()
	marker.name = "RouteChevron_%d_%d" % [route_index, marker_index]
	var material := _route_material(ASTER_TINT, 2.1)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.11, 0.035, 0.52)
		arm.mesh = box
		arm.position = Vector3(side * 0.17, 0.0, 0.0)
		arm.rotation.y = side * deg_to_rad(38.0)
		arm.material_override = material
		arm.set_meta("camera_occlusion_exempt", true)
		marker.add_child(arm)
	return marker


func _route_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _update_chevrons(tick: float) -> void:
	for marker_entry in _chevrons:
		var marker := marker_entry.get("node") as Node3D
		var route_index := int(marker_entry.get("route_index", -1))
		if marker == null or route_index < 0 or route_index >= _routes.size():
			continue
		var length := _route_lengths[route_index]
		var distance := fposmod(
			tick * CHEVRON_SPEED + float(marker_entry.get("phase", 0.0)) * length,
			length
		)
		var sample := _sample_route(_routes[route_index], distance)
		marker.position = sample["position"] + Vector3(0.0, LINE_HEIGHT + 0.035, 0.0)
		marker.basis = _basis_with_z(sample["direction"])


func _sample_route(route: Array, distance: float) -> Dictionary:
	var remaining := maxf(0.0, distance)
	for index in range(route.size() - 1):
		var a := route[index] as Vector3
		var b := route[index + 1] as Vector3
		var delta := b - a
		var segment_length := Vector2(delta.x, delta.z).length()
		if segment_length <= 0.001:
			continue
		if remaining <= segment_length:
			return {
				"position": a.lerp(b, remaining / segment_length),
				"direction": Vector3(delta.x, 0.0, delta.z).normalized(),
			}
		remaining -= segment_length
	var tail := route[-1] as Vector3
	var before := route[-2] as Vector3
	return {
		"position": tail,
		"direction": Vector3(tail.x - before.x, 0.0, tail.z - before.z).normalized(),
	}


func _route_length(route: Array) -> float:
	var length := 0.0
	for index in range(route.size() - 1):
		var a := route[index] as Vector3
		var b := route[index + 1] as Vector3
		length += Vector2(b.x - a.x, b.z - a.z).length()
	return maxf(length, 0.01)


func _basis_with_z(z_axis: Vector3) -> Basis:
	var resolved := z_axis.normalized()
	if resolved.length_squared() <= 0.001:
		resolved = Vector3.FORWARD
	var x_axis := Vector3.UP.cross(resolved).normalized()
	return Basis(x_axis, Vector3.UP, resolved)


func _restore_authority_or_baseline() -> void:
	if _game_state == null or not _game_state.has_method("get_world_state"):
		_apply_visibility()
		return
	var raw: Variant = _game_state.get_world_state(authority_state_key(), null)
	if _valid_authority(raw):
		var saved := raw as Dictionary
		_revealed = bool(saved.get("revealed", false))
		_accepted_source_id = str(saved.get("accepted_source_id", ""))
		_accepted_trigger_count = int(saved.get("accepted_trigger_count", 0))
		_accepted_tick = float(saved.get("accepted_tick", -1.0))
	else:
		_revealed = false
		_accepted_source_id = ""
		_accepted_trigger_count = 0
		_accepted_tick = -1.0
		_publish_authority()
	_apply_visibility()


func _valid_authority(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var saved := raw as Dictionary
	var revealed := bool(saved.get("revealed", false))
	var source_id := str(saved.get("accepted_source_id", ""))
	var trigger_count := int(saved.get("accepted_trigger_count", 0))
	var accepted_tick := float(saved.get("accepted_tick", -1.0))
	return str(saved.get("contract", "")) == STATE_CONTRACT \
		and str(saved.get("authority_id", "")) == authority_state_key() \
		and ((not revealed and source_id.is_empty() and trigger_count == 0 and accepted_tick < 0.0) \
			or (revealed and source_id.begins_with("typed_terminal:") \
				and trigger_count > 0 and accepted_tick >= 0.0))


func _publish_authority() -> void:
	if _game_state == null or not _game_state.has_method("set_world_state"):
		return
	_game_state.set_world_state(authority_state_key(), {
		"contract": STATE_CONTRACT,
		"authority_id": authority_state_key(),
		"revealed": _revealed,
		"accepted_source_id": _accepted_source_id,
		"accepted_trigger_count": _accepted_trigger_count,
		"accepted_tick": _accepted_tick,
	})


func _apply_visibility() -> void:
	if _route_root != null:
		_route_root.visible = _revealed and _aster_overlay_active and _planning_active


func _scheduler_tick() -> float:
	if _game_state != null and _game_state.scheduler != null:
		return float(_game_state.scheduler.now)
	return 0.0
