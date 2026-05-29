class_name NavigationGraph
extends RefCounted

const CONTRACT_ID := "multi_level_navigation_graph_v1"
const DEFAULT_MAX_SNAP_DISTANCE := 8.0
const SAME_POINT_EPSILON := 0.01

var _data: Dictionary = {}
var _nodes: Dictionary = {}
var _adjacency: Dictionary = {}
var _edge_lookup: Dictionary = {}
var _entry_node := ""
var _exit_node := ""
var _max_snap_distance := DEFAULT_MAX_SNAP_DISTANCE
var _supports_multiple_elevations := false
var _warnings: Array[String] = []

func configure(data: Dictionary) -> void:
	_data = data.duplicate(true)
	_nodes.clear()
	_adjacency.clear()
	_edge_lookup.clear()
	_warnings.clear()
	_entry_node = str(_data.get("entry_node", ""))
	_exit_node = str(_data.get("exit_node", ""))
	_max_snap_distance = float(_data.get("max_snap_distance", DEFAULT_MAX_SNAP_DISTANCE))
	_supports_multiple_elevations = bool(_data.get("supports_multiple_elevations", false))

	for raw_node in _data.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node := (raw_node as Dictionary).duplicate(true)
		var node_id := str(node.get("id", ""))
		if node_id == "":
			continue
		node["position"] = _variant_to_vec3(node.get("position", []), Vector3.ZERO)
		node["elevation_index"] = int(node.get("elevation_index", 0))
		_nodes[node_id] = node
		_adjacency[node_id] = []

	for raw_edge in _data.get("edges", []):
		if not (raw_edge is Dictionary):
			continue
		var edge := _normalize_edge(raw_edge as Dictionary)
		if edge.is_empty():
			continue
		_add_directed_edge(edge)
		if bool(edge.get("bidirectional", true)):
			var reverse := edge.duplicate(true)
			var from_id := str(edge.get("from", ""))
			var to_id := str(edge.get("to", ""))
			reverse["from"] = to_id
			reverse["to"] = from_id
			reverse["id"] = "%s:reverse" % str(edge.get("id", "%s_to_%s" % [from_id, to_id]))
			var reverse_waypoints: Array[Vector3] = []
			var waypoints: Array = edge.get("waypoints", [])
			for i in range(waypoints.size() - 1, -1, -1):
				if waypoints[i] is Vector3:
					reverse_waypoints.append(waypoints[i])
			reverse["waypoints"] = reverse_waypoints
			_add_directed_edge(reverse)

func is_empty() -> bool:
	return _nodes.is_empty()

func get_data() -> Dictionary:
	return _data.duplicate(true)

func get_state() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"node_count": _nodes.size(),
		"edge_count": _edge_lookup.size(),
		"entry_node": _entry_node,
		"exit_node": _exit_node,
		"supports_multiple_elevations": _supports_multiple_elevations,
		"elevation_indices": _elevation_indices(),
		"max_snap_distance": _max_snap_distance,
		"warnings": _warnings.duplicate(),
	}

func has_node(node_id: String) -> bool:
	return _nodes.has(node_id)

func get_node_position(node_id: String) -> Vector3:
	if not _nodes.has(node_id):
		return Vector3.INF
	return _nodes[node_id].position

func find_nearest_node_id(position: Vector3, max_distance := -1.0) -> String:
	var limit := _max_snap_distance if max_distance < 0.0 else max_distance
	var best_id := ""
	var best_distance := 1.0e20
	for node_id in _nodes.keys():
		var node_pos: Vector3 = _nodes[node_id].position
		var distance := node_pos.distance_to(position)
		if distance < best_distance or (absf(distance - best_distance) <= 0.0001 and str(node_id) < best_id):
			best_distance = distance
			best_id = str(node_id)
	if best_id == "":
		return ""
	if limit >= 0.0 and best_distance > limit:
		return ""
	return best_id

func find_node_path(from_node_id: String, to_node_id: String, mode := "safe") -> Array[String]:
	if from_node_id == "" or to_node_id == "":
		return []
	if not _nodes.has(from_node_id) or not _nodes.has(to_node_id):
		return []
	if from_node_id == to_node_id:
		return [from_node_id]

	var open: Array[String] = [from_node_id]
	var came_from: Dictionary = {}
	var g_score := {from_node_id: 0.0}
	var closed := {}

	while not open.is_empty():
		var current := _pop_lowest_score(open, g_score, to_node_id)
		if current == to_node_id:
			return _reconstruct_node_path(came_from, current)
		closed[current] = true
		var neighbors: Array = _adjacency.get(current, [])
		for edge in neighbors:
			if not (edge is Dictionary):
				continue
			if not _edge_allowed(edge as Dictionary, mode):
				continue
			var neighbor := str((edge as Dictionary).get("to", ""))
			if neighbor == "" or closed.has(neighbor):
				continue
			var tentative := float(g_score.get(current, 1.0e20)) + float((edge as Dictionary).get("cost", 1.0))
			if tentative >= float(g_score.get(neighbor, 1.0e20)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			if not open.has(neighbor):
				open.append(neighbor)
	return []

func find_path(from_position: Vector3, to_position: Vector3, mode := "safe") -> Array[Vector3]:
	if _nodes.is_empty():
		return []
	var from_node := find_nearest_node_id(from_position)
	var to_node := find_nearest_node_id(to_position)
	if from_node == "" or to_node == "":
		return []
	var node_path := find_node_path(from_node, to_node, mode)
	if node_path.is_empty():
		return []
	var path: Array[Vector3] = [from_position]
	if node_path.size() == 1:
		_append_unique_point(path, to_position)
		return path
	for i in range(node_path.size() - 1):
		var edge := _edge_between(node_path[i], node_path[i + 1])
		if edge.is_empty():
			_append_unique_point(path, get_node_position(node_path[i + 1]))
			continue
		for waypoint in edge.get("waypoints", []):
			if waypoint is Vector3:
				_append_unique_point(path, waypoint)
	_append_unique_point(path, to_position)
	return path

func find_node_path_positions(from_node_id: String, to_node_id: String, mode := "safe") -> Array[Vector3]:
	var node_path := find_node_path(from_node_id, to_node_id, mode)
	var positions: Array[Vector3] = []
	for node_id in node_path:
		positions.append(get_node_position(node_id))
	return positions

func path_uses_multiple_elevations(path: Array) -> bool:
	var seen: Array[int] = []
	for point in path:
		if point is Vector3:
			var elevation := int(roundf(((point as Vector3).y - 0.45) / 0.72))
			if not seen.has(elevation):
				seen.append(elevation)
	return seen.size() > 1

func _normalize_edge(raw_edge: Dictionary) -> Dictionary:
	var from_id := str(raw_edge.get("from", ""))
	var to_id := str(raw_edge.get("to", ""))
	if from_id == "" or to_id == "" or not _nodes.has(from_id) or not _nodes.has(to_id):
		return {}
	var edge := raw_edge.duplicate(true)
	edge["from"] = from_id
	edge["to"] = to_id
	var from_pos: Vector3 = _nodes[from_id].position
	var to_pos: Vector3 = _nodes[to_id].position
	var waypoints: Array[Vector3] = []
	var raw_waypoints: Array = edge.get("waypoints", [])
	if raw_waypoints.is_empty():
		waypoints = [from_pos, to_pos]
	else:
		for raw_waypoint in raw_waypoints:
			waypoints.append(_variant_to_vec3(raw_waypoint, from_pos))
	if waypoints.is_empty():
		waypoints = [from_pos, to_pos]
	edge["waypoints"] = waypoints
	var physical_cost := _path_distance_3d(waypoints)
	if physical_cost <= 0.001:
		physical_cost = from_pos.distance_to(to_pos)
	var explicit_cost := float(edge.get("path_cost", edge.get("cost", -1.0)))
	var cost := physical_cost if explicit_cost < 0.0 else maxf(physical_cost, explicit_cost)
	cost += float(edge.get("risk_penalty", _risk_penalty(str(edge.get("kind", "")))))
	edge["cost"] = maxf(0.001, cost)
	if not edge.has("id"):
		edge["id"] = "%s_to_%s" % [from_id, to_id]
	if not edge.has("bidirectional"):
		edge["bidirectional"] = true
	return edge

func _add_directed_edge(edge: Dictionary) -> void:
	var from_id := str(edge.get("from", ""))
	var to_id := str(edge.get("to", ""))
	if not _adjacency.has(from_id):
		_adjacency[from_id] = []
	_adjacency[from_id].append(edge)
	_edge_lookup["%s>%s" % [from_id, to_id]] = edge

func _edge_between(from_id: String, to_id: String) -> Dictionary:
	return _edge_lookup.get("%s>%s" % [from_id, to_id], {})

func _edge_allowed(edge: Dictionary, mode: String) -> bool:
	if mode == "direct":
		return true
	if mode == "safe" and str(edge.get("kind", "")) == "risky":
		return bool(edge.get("recoverable", true))
	return true

func _pop_lowest_score(open: Array[String], g_score: Dictionary, goal_id: String) -> String:
	var best_index := 0
	var best_id := open[0]
	var best_score := float(g_score.get(best_id, 1.0e20)) + _heuristic(best_id, goal_id)
	for i in range(1, open.size()):
		var node_id := open[i]
		var score := float(g_score.get(node_id, 1.0e20)) + _heuristic(node_id, goal_id)
		if score < best_score or (absf(score - best_score) <= 0.0001 and node_id < best_id):
			best_score = score
			best_id = node_id
			best_index = i
	open.remove_at(best_index)
	return best_id

func _heuristic(from_id: String, to_id: String) -> float:
	if not _nodes.has(from_id) or not _nodes.has(to_id):
		return 0.0
	return (_nodes[from_id].position as Vector3).distance_to(_nodes[to_id].position)

func _reconstruct_node_path(came_from: Dictionary, current: String) -> Array[String]:
	var result: Array[String] = [current]
	while came_from.has(current):
		current = str(came_from[current])
		result.push_front(current)
	return result

func _append_unique_point(path: Array[Vector3], point: Vector3) -> void:
	if path.is_empty() or path[path.size() - 1].distance_to(point) > SAME_POINT_EPSILON:
		path.append(point)

func _path_distance_3d(path: Array) -> float:
	var distance := 0.0
	for i in range(1, path.size()):
		if path[i - 1] is Vector3 and path[i] is Vector3:
			distance += (path[i - 1] as Vector3).distance_to(path[i] as Vector3)
	return distance

func _risk_penalty(kind: String) -> float:
	match kind:
		"risky":
			return 28.0
		"shortcut":
			return 4.0
		_:
			return 0.0

func _elevation_indices() -> Array[int]:
	var indices: Array[int] = []
	for node in _nodes.values():
		var index := int((node as Dictionary).get("elevation_index", 0))
		if not indices.has(index):
			indices.append(index)
	indices.sort()
	return indices

static func _variant_to_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2]))
	return fallback
