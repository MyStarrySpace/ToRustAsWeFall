class_name PuzzleFragmentRunner
extends RefCounted

const Schema = preload("res://scripts/fragments/puzzle_fragment_schema.gd")

var _tree: SceneTree

func _init(tree: SceneTree) -> void:
	_tree = tree

func run_catalog(catalog, only_fragment_id := "") -> Dictionary:
	var fragment_results: Array = []
	var total_passed := 0
	var total_failed := 0

	for fragment in catalog.get_fragments():
		if only_fragment_id != "" and str(fragment.get(Schema.KEY_ID, "")) != only_fragment_id:
			continue
		var fragment_result: Dictionary = await run_fragment(fragment)
		fragment_results.append(fragment_result)
		total_passed += int(fragment_result.get(Schema.KEY_PASSED, 0))
		total_failed += int(fragment_result.get(Schema.KEY_FAILED, 0))

	return {
		Schema.KEY_CATALOG_PATH: catalog.source_path,
		Schema.KEY_FRAGMENT_FILTER: only_fragment_id,
		Schema.KEY_PASSED: total_passed,
		Schema.KEY_FAILED: total_failed,
		Schema.KEY_FRAGMENTS: fragment_results,
	}

func run_fragment(fragment: Dictionary) -> Dictionary:
	var scene_path := str(fragment.get(Schema.KEY_SCENE, ""))
	var scene: PackedScene = load(scene_path)
	if scene == null:
		var fragment_id := str(fragment.get(Schema.KEY_ID, ""))
		return {
			Schema.KEY_ID: fragment_id,
			Schema.KEY_DISPLAY_NAME: str(fragment.get(Schema.KEY_DISPLAY_NAME, fragment_id)),
			Schema.KEY_SCENE: scene_path,
			Schema.KEY_PASSED: 0,
			Schema.KEY_FAILED: 1,
			Schema.KEY_SCENARIOS: [{
				Schema.KEY_ID: Schema.SCENARIO_SCENE_LOAD,
				Schema.KEY_SUCCESS: false,
				Schema.KEY_ERROR: Schema.ERROR_SCENE_NOT_FOUND,
				Schema.KEY_MESSAGE: "Could not load %s" % scene_path,
			}],
		}

	var scenario_results: Array = []
	var passed := 0
	var failed := 0
	for raw_scenario in fragment.get(Schema.KEY_SCENARIOS, []):
		if typeof(raw_scenario) != TYPE_DICTIONARY:
			continue
		var scenario: Dictionary = raw_scenario.duplicate(true)
		var result: Dictionary = await _run_scenario(scene, fragment, scenario)
		scenario_results.append(result)
		if bool(result.get(Schema.KEY_SUCCESS, false)):
			passed += 1
		else:
			failed += 1

	var fragment_id := str(fragment.get(Schema.KEY_ID, ""))
	return {
		Schema.KEY_ID: fragment_id,
		Schema.KEY_DISPLAY_NAME: str(fragment.get(Schema.KEY_DISPLAY_NAME, fragment_id)),
		Schema.KEY_KIND: str(fragment.get(Schema.KEY_KIND, "")),
		Schema.KEY_SCENE: scene_path,
		Schema.KEY_PASSED: passed,
		Schema.KEY_FAILED: failed,
		Schema.KEY_SCENARIOS: scenario_results,
	}

func _run_scenario(scene: PackedScene, fragment: Dictionary, scenario: Dictionary) -> Dictionary:
	var settle_frames: int = int(fragment.get(Schema.KEY_SETTLE_FRAMES, 5))
	var preview_chunk := str(fragment.get(Schema.KEY_PREVIEW_CHUNK, ""))
	var preview_config: Dictionary = fragment.get(Schema.KEY_PREVIEW_CHUNK_CONFIG, {})
	var instance: Node = await _instantiate_scene(scene, settle_frames, preview_chunk, preview_config)
	if instance == null:
		return {
			Schema.KEY_ID: str(scenario.get(Schema.KEY_ID, "")),
			Schema.KEY_SUCCESS: false,
			Schema.KEY_ERROR: Schema.ERROR_INSTANTIATE_FAILED,
			Schema.KEY_MESSAGE: "Scene instance was null",
		}

	var steps: Array = []
	var snapshots: Dictionary = {}
	var anchors: Dictionary = _get_anchor_positions(instance)
	var failure := ""
	var failure_message := ""
	var action_index := 0
	var script: Array = []
	script.append_array(fragment.get(Schema.KEY_SETUP, []))
	script.append_array(scenario.get(Schema.KEY_SETUP, []))
	script.append_array(scenario.get(Schema.KEY_SCRIPT, []))

	for raw_action in script:
		action_index += 1
		if typeof(raw_action) != TYPE_DICTIONARY:
			failure = Schema.ERROR_INVALID_ACTION
			failure_message = "Step %d is not a dictionary" % action_index
			break
		var action: Dictionary = raw_action
		var step_result: Dictionary = _execute_action(instance, anchors, snapshots, action)
		step_result[Schema.KEY_INDEX] = action_index
		steps.append(step_result)
		if not bool(step_result.get(Schema.KEY_OK, false)):
			failure = str(step_result.get(Schema.KEY_ERROR, Schema.ERROR_STEP_FAILED))
			failure_message = str(step_result.get(Schema.KEY_MESSAGE, ""))
			break
		if Schema.action_type_from_variant(action.get(Schema.KEY_ACTION_TYPE, "")) == Schema.ActionType.REFRESH_ANCHORS:
			anchors = _get_anchor_positions(instance)

	var final_state: Dictionary = _get_scene_state(instance)
	await _dispose_scene(instance)
	var scenario_id := str(scenario.get(Schema.KEY_ID, ""))
	return {
		Schema.KEY_ID: scenario_id,
		Schema.KEY_DISPLAY_NAME: str(scenario.get(Schema.KEY_DISPLAY_NAME, scenario_id)),
		Schema.KEY_SUCCESS: failure == "",
		Schema.KEY_ERROR: failure,
		Schema.KEY_MESSAGE: failure_message,
		Schema.KEY_STEPS: steps,
		Schema.KEY_FINAL_STATE: final_state,
	}

func _instantiate_scene(scene: PackedScene, settle_frames: int, preview_chunk := "", preview_config := {}) -> Node:
	var instance: Node = scene.instantiate()
	# When this is the shared fragment_preview.tscn, select the chunk before it enters the tree (its
	# _ready loads the chunk). Real-scene fragments leave preview_chunk empty and skip this.
	if preview_chunk != "":
		instance.set("preview_menu", false)
		instance.set("preview_chunk", preview_chunk)
		if preview_config is Dictionary and not (preview_config as Dictionary).is_empty():
			instance.set("preview_chunk_config", (preview_config as Dictionary).duplicate(true))
	_tree.root.add_child(instance)
	for _i in range(maxi(1, settle_frames)):
		await _tree.process_frame
	return instance

func _dispose_scene(instance: Node) -> void:
	if instance and is_instance_valid(instance):
		instance.queue_free()
		await _tree.process_frame
		await _tree.process_frame

func _get_anchor_positions(instance: Node) -> Dictionary:
	if instance.has_method(Schema.METHOD_HEADLESS_GET_ANCHORS):
		return instance.call(Schema.METHOD_HEADLESS_GET_ANCHORS)
	return {}

func _get_scene_state(instance: Node) -> Dictionary:
	if instance.has_method(Schema.METHOD_HEADLESS_GET_STATE):
		return instance.call(Schema.METHOD_HEADLESS_GET_STATE)
	return {}

func _execute_action(instance: Node, anchors: Dictionary, snapshots: Dictionary, action: Dictionary) -> Dictionary:
	var action_type := Schema.action_type_from_variant(action.get(Schema.KEY_ACTION_TYPE, ""))
	match action_type:
		Schema.ActionType.SELECT_CHARACTER:
			return _execute_select_character(instance, action)
		Schema.ActionType.TELEPORT:
			return _execute_teleport(instance, anchors, action)
		Schema.ActionType.ADVANCE:
			return _execute_advance(instance, action)
		Schema.ActionType.CALL:
			return _execute_call(instance, action)
		Schema.ActionType.CALL_CHUNK:
			return _execute_call_chunk(instance, action)
		Schema.ActionType.SNAPSHOT_STATE:
			return _execute_snapshot(instance, snapshots, action)
		Schema.ActionType.REFRESH_ANCHORS:
			return _step_ok("Refreshed anchor positions")
		Schema.ActionType.ASSERT_PATH:
			return _assert_path(instance, snapshots, action)
		_:
			return _step_error(
				Schema.ERROR_UNKNOWN_ACTION,
				"Unknown action type: %s" % str(action.get(Schema.KEY_ACTION_TYPE, ""))
			)

func _execute_select_character(instance: Node, action: Dictionary) -> Dictionary:
	var char_id := str(action.get(Schema.KEY_CHAR_ID, ""))
	if char_id == "":
		return _step_error(Schema.ERROR_MISSING_CHAR_ID, "select_character requires char_id")
	if instance.has_method(Schema.METHOD_HEADLESS_SELECT_CHARACTER):
		instance.call(Schema.METHOD_HEADLESS_SELECT_CHARACTER, char_id)
		return _step_ok("Selected %s" % char_id)
	return _step_error(Schema.ERROR_MISSING_METHOD, "Scene does not expose %s" % Schema.METHOD_HEADLESS_SELECT_CHARACTER)

func _execute_teleport(instance: Node, anchors: Dictionary, action: Dictionary) -> Dictionary:
	var char_id := str(action.get(Schema.KEY_CHAR_ID, ""))
	if char_id == "":
		return _step_error(Schema.ERROR_MISSING_CHAR_ID, "teleport requires char_id")
	if not instance.has_method(Schema.METHOD_HEADLESS_SET_CHARACTER_POSITION):
		return _step_error(Schema.ERROR_MISSING_METHOD, "Scene does not expose %s" % Schema.METHOD_HEADLESS_SET_CHARACTER_POSITION)
	var pos_result: Dictionary = _resolve_position(action, anchors)
	if not bool(pos_result.get(Schema.KEY_OK, false)):
		return pos_result
	instance.call(Schema.METHOD_HEADLESS_SET_CHARACTER_POSITION, char_id, pos_result[Schema.KEY_VALUE])
	return _step_ok("Teleported %s" % char_id, {Schema.KEY_POSITION: pos_result[Schema.KEY_VALUE]})

func _execute_advance(instance: Node, action: Dictionary) -> Dictionary:
	var seconds: float = float(action.get(Schema.KEY_SECONDS, 0.0))
	var step: float = float(action.get(Schema.KEY_STEP, 0.05))
	if not instance.has_method(Schema.METHOD_HEADLESS_ADVANCE):
		return _step_error(Schema.ERROR_MISSING_METHOD, "Scene does not expose %s" % Schema.METHOD_HEADLESS_ADVANCE)
	instance.call(Schema.METHOD_HEADLESS_ADVANCE, seconds, step)
	return _step_ok("Advanced %.2fs" % seconds)

func _execute_call(instance: Node, action: Dictionary) -> Dictionary:
	var method_name := str(action.get(Schema.KEY_METHOD, ""))
	if method_name == "":
		return _step_error(Schema.ERROR_MISSING_METHOD_NAME, "call requires method")
	if not instance.has_method(method_name):
		return _step_error(Schema.ERROR_MISSING_METHOD, "Scene does not expose %s" % method_name)
	var args: Array = action.get(Schema.KEY_ARGS, [])
	instance.callv(method_name, args)
	return _step_ok("Called %s" % method_name)

func _execute_call_chunk(instance: Node, action: Dictionary) -> Dictionary:
	var method_name := str(action.get(Schema.KEY_METHOD, ""))
	if method_name == "":
		return _step_error(Schema.ERROR_MISSING_METHOD_NAME, "call_chunk requires method")
	if not instance.has_method(Schema.METHOD_HEADLESS_CALL_CHUNK):
		return _step_error(Schema.ERROR_MISSING_METHOD, "Scene does not expose %s" % Schema.METHOD_HEADLESS_CALL_CHUNK)
	var args: Array = action.get(Schema.KEY_ARGS, [])
	instance.call(Schema.METHOD_HEADLESS_CALL_CHUNK, method_name, args)
	return _step_ok("Called chunk %s" % method_name)

func _execute_snapshot(instance: Node, snapshots: Dictionary, action: Dictionary) -> Dictionary:
	var key := str(action.get(Schema.KEY_KEY, ""))
	if key == "":
		return _step_error(Schema.ERROR_MISSING_SNAPSHOT_KEY, "snapshot_state requires key")
	snapshots[key] = _get_scene_state(instance)
	return _step_ok("Captured snapshot %s" % key)

func _assert_path(instance: Node, snapshots: Dictionary, action: Dictionary) -> Dictionary:
	var path := str(action.get(Schema.KEY_PATH, ""))
	var compare_op := Schema.compare_op_from_variant(action.get(Schema.KEY_OP, Schema.OP_EQUAL))
	if path == "":
		return _step_error(Schema.ERROR_MISSING_PATH, "assert_path requires path")

	var state: Dictionary = _get_scene_state(instance)
	var actual_result: Dictionary = _read_path(state, path)
	if not bool(actual_result.get(Schema.KEY_OK, false)):
		return _step_error(Schema.ERROR_PATH_NOT_FOUND, "Could not resolve %s" % path)

	var expected: Variant = null
	if action.has(Schema.KEY_SNAPSHOT):
		var snapshot_key := str(action.get(Schema.KEY_SNAPSHOT, ""))
		if not snapshots.has(snapshot_key):
			return _step_error(Schema.ERROR_MISSING_SNAPSHOT, "Snapshot %s was not captured" % snapshot_key)
		var snapshot_path := str(action.get(Schema.KEY_SNAPSHOT_PATH, path))
		var snapshot_result: Dictionary = _read_path(snapshots[snapshot_key], snapshot_path)
		if not bool(snapshot_result.get(Schema.KEY_OK, false)):
			return _step_error(
				Schema.ERROR_SNAPSHOT_PATH_NOT_FOUND,
				"Could not resolve %s on snapshot %s" % [snapshot_path, snapshot_key]
			)
		expected = snapshot_result[Schema.KEY_VALUE]
	else:
		expected = action.get(Schema.KEY_VALUE)

	var actual: Variant = actual_result[Schema.KEY_VALUE]
	var op_name := Schema.compare_op_name(compare_op)
	if _compare_values(actual, compare_op, expected):
		return _step_ok("Asserted %s %s %s" % [path, op_name, str(expected)], {
			Schema.KEY_ACTUAL: actual,
			Schema.KEY_EXPECTED: expected,
		})
	return _step_error(
		Schema.ERROR_ASSERT_FAILED,
		"Expected %s %s %s, got %s" % [path, op_name, str(expected), str(actual)],
		{
			Schema.KEY_ACTUAL: actual,
			Schema.KEY_EXPECTED: expected,
		}
	)

func _resolve_position(action: Dictionary, anchors: Dictionary) -> Dictionary:
	if action.has(Schema.KEY_ANCHOR):
		var anchor_name := str(action.get(Schema.KEY_ANCHOR, ""))
		if not anchors.has(anchor_name):
			return _step_error(Schema.ERROR_ANCHOR_NOT_FOUND, "Unknown anchor: %s" % anchor_name)
		var anchor_value: Variant = anchors[anchor_name]
		if anchor_value is Vector3:
			var offset := _vector3_from_variant(action.get(Schema.KEY_OFFSET, Vector3.ZERO))
			return _step_ok("", {Schema.KEY_VALUE: anchor_value + offset})
		return _step_error(Schema.ERROR_INVALID_ANCHOR, "Anchor %s is not a Vector3" % anchor_name)
	if action.has(Schema.KEY_POSITION):
		var pos := _vector3_from_variant(action[Schema.KEY_POSITION])
		return _step_ok("", {Schema.KEY_VALUE: pos})
	return _step_error(Schema.ERROR_MISSING_POSITION, "Action requires anchor or position")

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
					return {Schema.KEY_OK: false}
				current = current[part]
			TYPE_ARRAY:
				var index := int(part)
				if index < 0 or index >= current.size():
					return {Schema.KEY_OK: false}
				current = current[index]
			TYPE_VECTOR2:
				current = _read_vector2_component(current, part)
			TYPE_VECTOR3:
				current = _read_vector3_component(current, part)
			_:
				return {Schema.KEY_OK: false}
		if current == null and i < parts.size() - 1:
			return {Schema.KEY_OK: false}
	return {Schema.KEY_OK: true, Schema.KEY_VALUE: current}

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

func _compare_values(actual: Variant, compare_op: int, expected: Variant) -> bool:
	match compare_op:
		Schema.CompareOp.EQUAL:
			return actual == expected
		Schema.CompareOp.NOT_EQUAL:
			return actual != expected
		Schema.CompareOp.GREATER:
			return float(actual) > float(expected)
		Schema.CompareOp.GREATER_OR_EQUAL:
			return float(actual) >= float(expected)
		Schema.CompareOp.LESS:
			return float(actual) < float(expected)
		Schema.CompareOp.LESS_OR_EQUAL:
			return float(actual) <= float(expected)
		Schema.CompareOp.IN:
			return expected is Array and expected.has(actual)
		Schema.CompareOp.CONTAINS:
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
		Schema.KEY_OK: true,
		Schema.KEY_MESSAGE: message,
	}
	result.merge(extra, true)
	return result

func _step_error(error: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		Schema.KEY_OK: false,
		Schema.KEY_ERROR: error,
		Schema.KEY_MESSAGE: message,
	}
	result.merge(extra, true)
	return result
