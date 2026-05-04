class_name PuzzleFragmentRunner
extends RefCounted

var _tree: SceneTree

func _init(tree: SceneTree) -> void:
	_tree = tree

func run_catalog(catalog, only_fragment_id := "") -> Dictionary:
	var fragment_results: Array = []
	var total_passed := 0
	var total_failed := 0

	for fragment in catalog.get_fragments():
		if only_fragment_id != "" and str(fragment.get("id", "")) != only_fragment_id:
			continue
		var fragment_result: Dictionary = await run_fragment(fragment)
		fragment_results.append(fragment_result)
		total_passed += int(fragment_result.get("passed", 0))
		total_failed += int(fragment_result.get("failed", 0))

	return {
		"catalog_path": catalog.source_path,
		"fragment_filter": only_fragment_id,
		"passed": total_passed,
		"failed": total_failed,
		"fragments": fragment_results,
	}

func run_fragment(fragment: Dictionary) -> Dictionary:
	var scene_path := str(fragment.get("scene", ""))
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return {
			"id": str(fragment.get("id", "")),
			"display_name": str(fragment.get("display_name", fragment.get("id", ""))),
			"scene": scene_path,
			"passed": 0,
			"failed": 1,
			"scenarios": [{
				"id": "scene_load",
				"success": false,
				"error": "scene_not_found",
				"message": "Could not load %s" % scene_path,
			}],
		}

	var scenario_results: Array = []
	var passed := 0
	var failed := 0
	for raw_scenario in fragment.get("scenarios", []):
		if typeof(raw_scenario) != TYPE_DICTIONARY:
			continue
		var scenario: Dictionary = raw_scenario.duplicate(true)
		var result: Dictionary = await _run_scenario(scene, fragment, scenario)
		scenario_results.append(result)
		if bool(result.get("success", false)):
			passed += 1
		else:
			failed += 1

	return {
		"id": str(fragment.get("id", "")),
		"display_name": str(fragment.get("display_name", fragment.get("id", ""))),
		"kind": str(fragment.get("kind", "")),
		"scene": scene_path,
		"passed": passed,
		"failed": failed,
		"scenarios": scenario_results,
	}

func _run_scenario(scene: PackedScene, fragment: Dictionary, scenario: Dictionary) -> Dictionary:
	var settle_frames: int = int(fragment.get("settle_frames", 5))
	var instance: Node = await _instantiate_scene(scene, settle_frames)
	if instance == null:
		return {
			"id": str(scenario.get("id", "")),
			"success": false,
			"error": "instantiate_failed",
			"message": "Scene instance was null",
		}

	var steps: Array = []
	var snapshots: Dictionary = {}
	var anchors: Dictionary = _get_anchor_positions(instance)
	var failure := ""
	var failure_message := ""
	var action_index := 0
	var script: Array = []
	script.append_array(fragment.get("setup", []))
	script.append_array(scenario.get("setup", []))
	script.append_array(scenario.get("script", []))

	for raw_action in script:
		action_index += 1
		if typeof(raw_action) != TYPE_DICTIONARY:
			failure = "invalid_action"
			failure_message = "Step %d is not a dictionary" % action_index
			break
		var action: Dictionary = raw_action
		var step_result: Dictionary = _execute_action(instance, anchors, snapshots, action)
		step_result["index"] = action_index
		steps.append(step_result)
		if not bool(step_result.get("ok", false)):
			failure = str(step_result.get("error", "step_failed"))
			failure_message = str(step_result.get("message", ""))
			break
		if action.get("type", "") == "refresh_anchors":
			anchors = _get_anchor_positions(instance)

	var final_state: Dictionary = _get_scene_state(instance)
	await _dispose_scene(instance)
	return {
		"id": str(scenario.get("id", "")),
		"display_name": str(scenario.get("display_name", scenario.get("id", ""))),
		"success": failure == "",
		"error": failure,
		"message": failure_message,
		"steps": steps,
		"final_state": final_state,
	}

func _instantiate_scene(scene: PackedScene, settle_frames: int) -> Node:
	var instance: Node = scene.instantiate()
	_tree.root.add_child(instance)
	for _i in range(maxi(1, settle_frames)):
		await _tree.process_frame
	return instance

func _dispose_scene(instance: Node) -> void:
	if instance and is_instance_valid(instance):
		instance.queue_free()
		await _tree.process_frame

func _get_anchor_positions(instance: Node) -> Dictionary:
	if instance.has_method("headless_get_anchor_positions"):
		return instance.headless_get_anchor_positions()
	return {}

func _get_scene_state(instance: Node) -> Dictionary:
	if instance.has_method("headless_get_state"):
		return instance.headless_get_state()
	return {}

func _execute_action(instance: Node, anchors: Dictionary, snapshots: Dictionary, action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", ""))
	match action_type:
		"select_character":
			var char_id := str(action.get("char_id", ""))
			if char_id == "":
				return _step_error("missing_char_id", "select_character requires char_id")
			if instance.has_method("headless_select_character"):
				instance.headless_select_character(char_id)
				return _step_ok("Selected %s" % char_id)
			return _step_error("missing_method", "Scene does not expose headless_select_character")
		"teleport":
			var teleport_id := str(action.get("char_id", ""))
			if teleport_id == "":
				return _step_error("missing_char_id", "teleport requires char_id")
			if not instance.has_method("headless_set_character_position"):
				return _step_error("missing_method", "Scene does not expose headless_set_character_position")
			var pos_result: Dictionary = _resolve_position(action, anchors)
			if not bool(pos_result.get("ok", false)):
				return pos_result
			instance.headless_set_character_position(teleport_id, pos_result["value"])
			return _step_ok("Teleported %s" % teleport_id, {"position": pos_result["value"]})
		"advance":
			var seconds: float = float(action.get("seconds", 0.0))
			var step: float = float(action.get("step", 0.05))
			if not instance.has_method("headless_advance"):
				return _step_error("missing_method", "Scene does not expose headless_advance")
			instance.headless_advance(seconds, step)
			return _step_ok("Advanced %.2fs" % seconds)
		"call":
			var method_name := str(action.get("method", ""))
			if method_name == "":
				return _step_error("missing_method_name", "call requires method")
			if not instance.has_method(method_name):
				return _step_error("missing_method", "Scene does not expose %s" % method_name)
			var args: Array = action.get("args", [])
			instance.callv(method_name, args)
			return _step_ok("Called %s" % method_name)
		"call_chunk":
			var chunk_method := str(action.get("method", ""))
			if chunk_method == "":
				return _step_error("missing_method_name", "call_chunk requires method")
			if not instance.has_method("headless_call_chunk"):
				return _step_error("missing_method", "Scene does not expose headless_call_chunk")
			var chunk_args: Array = action.get("args", [])
			instance.call("headless_call_chunk", chunk_method, chunk_args)
			return _step_ok("Called chunk %s" % chunk_method)
		"snapshot_state":
			var key := str(action.get("key", ""))
			if key == "":
				return _step_error("missing_snapshot_key", "snapshot_state requires key")
			snapshots[key] = _get_scene_state(instance)
			return _step_ok("Captured snapshot %s" % key)
		"refresh_anchors":
			return _step_ok("Refreshed anchor positions")
		"assert_path":
			return _assert_path(instance, snapshots, action)
		_:
			return _step_error("unknown_action", "Unknown action type: %s" % action_type)

func _assert_path(instance: Node, snapshots: Dictionary, action: Dictionary) -> Dictionary:
	var path := str(action.get("path", ""))
	var op := str(action.get("op", "=="))
	if path == "":
		return _step_error("missing_path", "assert_path requires path")

	var state: Dictionary = _get_scene_state(instance)
	var actual_result: Dictionary = _read_path(state, path)
	if not bool(actual_result.get("ok", false)):
		return _step_error("path_not_found", "Could not resolve %s" % path)

	var expected: Variant = null
	if action.has("snapshot"):
		var snapshot_key := str(action.get("snapshot", ""))
		if not snapshots.has(snapshot_key):
			return _step_error("missing_snapshot", "Snapshot %s was not captured" % snapshot_key)
		var snapshot_path := str(action.get("snapshot_path", path))
		var snapshot_result: Dictionary = _read_path(snapshots[snapshot_key], snapshot_path)
		if not bool(snapshot_result.get("ok", false)):
			return _step_error("snapshot_path_not_found", "Could not resolve %s on snapshot %s" % [snapshot_path, snapshot_key])
		expected = snapshot_result["value"]
	else:
		expected = action.get("value")

	var actual: Variant = actual_result["value"]
	if _compare_values(actual, op, expected):
		return _step_ok("Asserted %s %s %s" % [path, op, str(expected)], {
			"actual": actual,
			"expected": expected,
		})
	return _step_error(
		"assert_failed",
		"Expected %s %s %s, got %s" % [path, op, str(expected), str(actual)],
		{
			"actual": actual,
			"expected": expected,
		}
	)

func _resolve_position(action: Dictionary, anchors: Dictionary) -> Dictionary:
	if action.has("anchor"):
		var anchor_name := str(action.get("anchor", ""))
		if not anchors.has(anchor_name):
			return _step_error("anchor_not_found", "Unknown anchor: %s" % anchor_name)
		var anchor_value: Variant = anchors[anchor_name]
		if anchor_value is Vector3:
			var offset := _vector3_from_variant(action.get("offset", Vector3.ZERO))
			return {"ok": true, "value": anchor_value + offset}
		return _step_error("invalid_anchor", "Anchor %s is not a Vector3" % anchor_name)
	if action.has("position"):
		var pos := _vector3_from_variant(action["position"])
		return {"ok": true, "value": pos}
	return _step_error("missing_position", "Action requires anchor or position")

func _vector3_from_variant(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0))
		)
	return Vector3.ZERO

func _read_path(data: Variant, path: String) -> Dictionary:
	var current: Variant = data
	var parts := path.split(".")
	for i in range(parts.size()):
		var part: String = parts[i]
		match typeof(current):
			TYPE_DICTIONARY:
				if not current.has(part):
					return {"ok": false}
				current = current[part]
			TYPE_ARRAY:
				var index := int(part)
				if index < 0 or index >= current.size():
					return {"ok": false}
				current = current[index]
			TYPE_VECTOR2:
				current = _read_vector2_component(current, part)
			TYPE_VECTOR3:
				current = _read_vector3_component(current, part)
			_:
				return {"ok": false}
		if current == null and i < parts.size() - 1:
			return {"ok": false}
	return {"ok": true, "value": current}

func _read_vector2_component(value: Vector2, part: String) -> Variant:
	match part:
		"x":
			return value.x
		"y":
			return value.y
		_:
			return null

func _read_vector3_component(value: Vector3, part: String) -> Variant:
	match part:
		"x":
			return value.x
		"y":
			return value.y
		"z":
			return value.z
		_:
			return null

func _compare_values(actual: Variant, op: String, expected: Variant) -> bool:
	match op:
		"==":
			return actual == expected
		"!=":
			return actual != expected
		">":
			return float(actual) > float(expected)
		">=":
			return float(actual) >= float(expected)
		"<":
			return float(actual) < float(expected)
		"<=":
			return float(actual) <= float(expected)
		"in":
			return expected is Array and expected.has(actual)
		"contains":
			if actual is Array:
				return actual.has(expected)
			if actual is Dictionary:
				return actual.has(expected)
			if actual is String:
				return actual.contains(str(expected))
			return false
		_:
			return false

func _step_ok(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"message": message,
	}
	result.merge(extra, true)
	return result

func _step_error(error: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"error": error,
		"message": message,
	}
	result.merge(extra, true)
	return result
