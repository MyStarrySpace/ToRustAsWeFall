class_name PuzzleFragmentRunner
extends RefCounted

const Schema = preload("res://scripts/fragments/puzzle_fragment_schema.gd")
const AUTHORITATIVE_PLACEMENT_TOLERANCE := 0.001

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
		Schema.ActionType.PHYSICAL_INTERACT:
			return _execute_physical_interact(instance, action)
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
	var placement_result := _validate_authoritative_character_placement(instance, char_id)
	if not bool(placement_result.get(Schema.KEY_OK, false)):
		return placement_result
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
	var call_result: Variant = instance.callv(method_name, args)
	if typeof(call_result) == TYPE_BOOL and not bool(call_result):
		return _step_error(
			Schema.ERROR_ACTION_REFUSED,
			"Scene call %s refused the requested action" % method_name
		)
	return _step_ok("Called %s" % method_name, {Schema.KEY_VALUE: call_result})

func _execute_call_chunk(instance: Node, action: Dictionary) -> Dictionary:
	var method_name := str(action.get(Schema.KEY_METHOD, ""))
	if method_name == "":
		return _step_error(Schema.ERROR_MISSING_METHOD_NAME, "call_chunk requires method")
	if not instance.has_method(Schema.METHOD_HEADLESS_CALL_CHUNK):
		return _step_error(Schema.ERROR_MISSING_METHOD, "Scene does not expose %s" % Schema.METHOD_HEADLESS_CALL_CHUNK)
	var args: Array = action.get(Schema.KEY_ARGS, [])
	var call_result: Variant = instance.call(
		Schema.METHOD_HEADLESS_CALL_CHUNK, method_name, args)
	if typeof(call_result) == TYPE_BOOL and not bool(call_result):
		return _step_error(
			Schema.ERROR_ACTION_REFUSED,
			"Chunk call %s refused the requested action" % method_name
		)
	return _step_ok("Called chunk %s" % method_name, {Schema.KEY_VALUE: call_result})

func _execute_physical_interact(instance: Node, action: Dictionary) -> Dictionary:
	var char_id := str(action.get(Schema.KEY_CHAR_ID, ""))
	if char_id == "":
		return _step_error(
			Schema.ERROR_MISSING_CHAR_ID,
			"physical_interact requires char_id"
		)
	if not instance.has_method(Schema.METHOD_HEADLESS_SELECT_CHARACTER):
		return _step_error(
			Schema.ERROR_MISSING_METHOD,
			"Scene does not expose %s" % Schema.METHOD_HEADLESS_SELECT_CHARACTER
		)
	if not instance.has_method(Schema.METHOD_HEADLESS_SET_CHARACTER_POSITION):
		return _step_error(
			Schema.ERROR_MISSING_METHOD,
			"Scene does not expose %s" % Schema.METHOD_HEADLESS_SET_CHARACTER_POSITION
		)

	var source_result := _resolve_physical_source(instance, action)
	if not bool(source_result.get(Schema.KEY_OK, false)):
		return source_result
	var source: Node = source_result.get(Schema.KEY_VALUE) as Node
	if source == null or not is_instance_valid(source) or not (source is Node3D) \
			or not source.has_method("_trigger") \
			or not _object_has_property(source, "active_character"):
		return _step_error(
			Schema.ERROR_SOURCE_NOT_INTERACTABLE,
			"Resolved source is not a live world interactable"
		)

	var source_position := _physical_source_data_position(instance, source as Node3D)
	if not source_position.is_finite():
		return _step_error(
			Schema.ERROR_MISSING_POSITION,
			"Could not resolve an authoritative position for %s" % source.name
		)
	var offset := _vector3_from_variant(action.get(Schema.KEY_OFFSET, Vector3.ZERO))
	var approach_position := source_position + offset
	var party_result := _stage_authoritative_party(instance, char_id, action)
	if not bool(party_result.get(Schema.KEY_OK, false)):
		return party_result
	var clock_result := _stage_authoritative_clock(instance, action)
	if not bool(clock_result.get(Schema.KEY_OK, false)):
		return clock_result
	instance.call(Schema.METHOD_HEADLESS_SELECT_CHARACTER, char_id)
	instance.call(
		Schema.METHOD_HEADLESS_SET_CHARACTER_POSITION, char_id, approach_position)
	var placement_result := _validate_authoritative_character_placement(instance, char_id)
	if not bool(placement_result.get(Schema.KEY_OK, false)):
		return placement_result
	# Selection normally projects the active portrait to every registered source. Set the exact source
	# again after staging so the accepted receipt names the actor whose authoritative body is here.
	source.set("active_character", char_id)
	var accepted: Variant = source.call("_trigger", false)
	if typeof(accepted) != TYPE_BOOL or not bool(accepted):
		return _step_error(
			Schema.ERROR_ACTION_REFUSED,
			"%s refused %s at its physical source" % [source.name, char_id],
			{
				Schema.KEY_SOURCE: str(source.name),
				Schema.KEY_POSITION: approach_position,
			}
		)
	return _step_ok(
		"%s interacted with %s" % [char_id, source.name],
		{
			Schema.KEY_SOURCE: str(source.name),
			Schema.KEY_POSITION: approach_position,
		}
	)


## Some production receipts validate party membership in addition to the body at the source. A tape may
## declare that roster on the physical action; install it through GameState's public command before the
## receipt, then verify the exact authoritative roster. Positioning remains explicit teleport/interaction
## staging, so this never manufactures proximity or bypasses any source validator.
func _stage_authoritative_party(
	instance: Node, actor_id: String, action: Dictionary
) -> Dictionary:
	if not action.has(Schema.KEY_PARTY):
		return _step_ok("")
	var party_v: Variant = action.get(Schema.KEY_PARTY, [])
	if not (party_v is Array) or (party_v as Array).is_empty():
		return _step_error(
			Schema.ERROR_INVALID_PARTY,
			"physical_interact party must be a non-empty array"
		)
	var game_state: Variant = _object_property(instance, "_game_state")
	if not (game_state is Object) or not is_instance_valid(game_state) \
			or not game_state.has_method("set_party") \
			or not game_state.has_method("get_party"):
		return _step_error(
			Schema.ERROR_GAME_STATE_NOT_FOUND,
			"Scene does not expose authoritative party commands"
		)
	var characters_v: Variant = _object_property(game_state as Object, "characters")
	if not (characters_v is Dictionary):
		return _step_error(
			Schema.ERROR_GAME_STATE_NOT_FOUND,
			"GameState does not expose its registered characters"
		)
	var party: Array[String] = []
	for member_v in party_v as Array:
		var member_id := str(member_v).strip_edges()
		if member_id.is_empty() or party.has(member_id):
			return _step_error(
				Schema.ERROR_INVALID_PARTY,
				"physical_interact party contains an empty or duplicate member"
			)
		if not (characters_v as Dictionary).has(member_id):
			return _step_error(
				Schema.ERROR_CHARACTER_NOT_FOUND,
				"Party member %s is not registered in GameState" % member_id
			)
		party.append(member_id)
	if actor_id not in party:
		return _step_error(
			Schema.ERROR_INVALID_PARTY,
			"Physical actor %s is not in the declared party" % actor_id
		)
	game_state.call("set_party", party)
	var installed_v: Variant = game_state.call("get_party")
	if not (installed_v is Array) or (installed_v as Array) != party:
		return _step_error(
			Schema.ERROR_INVALID_PARTY,
			"GameState refused the declared physical-interaction party"
		)
	return _step_ok("Staged authoritative party", {Schema.KEY_PARTY: party.duplicate()})


## Shelter-rest validators read GameState's authoritative clock before invoking their chunk callback.
## Fragment previews display a host-owned clock and synchronize it at the callback boundary, which is
## too late for that preflight. A physical tape may therefore declare the same preview clock here;
## install it through GameState's public command and verify the live value before requesting a receipt.
func _stage_authoritative_clock(instance: Node, action: Dictionary) -> Dictionary:
	if not action.has(Schema.KEY_CLOCK):
		return _step_ok("")
	var clock_v: Variant = action.get(Schema.KEY_CLOCK, {})
	if not (clock_v is Dictionary):
		return _step_error(
			Schema.ERROR_INVALID_CLOCK,
			"physical_interact clock must be a day/time dictionary"
		)
	var clock: Dictionary = clock_v
	if not clock.has(Schema.KEY_DAY) or not clock.has(Schema.KEY_TIME):
		return _step_error(
			Schema.ERROR_INVALID_CLOCK,
			"physical_interact clock requires day and time"
		)
	var day_v: Variant = clock.get(Schema.KEY_DAY)
	var time_v: Variant = clock.get(Schema.KEY_TIME)
	if typeof(day_v) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(time_v) not in [TYPE_INT, TYPE_FLOAT]:
		return _step_error(
			Schema.ERROR_INVALID_CLOCK,
			"physical_interact clock day and time must be numeric"
		)
	var day_number := float(day_v)
	var time := float(time_v)
	if not is_finite(day_number) or day_number != floorf(day_number) \
			or day_number < 1.0 or day_number > float(0x7fffffff) \
			or not is_finite(time) or time < 0.0 or time > 1.0:
		return _step_error(
			Schema.ERROR_INVALID_CLOCK,
			"physical_interact clock requires an integer day >= 1 and time in [0, 1]"
		)
	var game_state: Variant = _object_property(instance, "_game_state")
	if not (game_state is Object) or not is_instance_valid(game_state) \
			or not game_state.has_method("set_game_clock") \
			or not game_state.has_method("get_game_day") \
			or not game_state.has_method("get_time_of_day"):
		return _step_error(
			Schema.ERROR_GAME_STATE_NOT_FOUND,
			"Scene does not expose authoritative clock commands"
		)
	var day := int(day_number)
	game_state.call("set_game_clock", day, time)
	var installed_day := int(game_state.call("get_game_day"))
	var installed_time := float(game_state.call("get_time_of_day"))
	if installed_day != day or not is_equal_approx(installed_time, time):
		return _step_error(
			Schema.ERROR_INVALID_CLOCK,
			"GameState refused the declared physical-interaction clock",
			{
				Schema.KEY_EXPECTED: {Schema.KEY_DAY: day, Schema.KEY_TIME: time},
				Schema.KEY_ACTUAL: {
					Schema.KEY_DAY: installed_day,
					Schema.KEY_TIME: installed_time,
				},
			}
		)
	return _step_ok(
		"Staged authoritative clock",
		{Schema.KEY_CLOCK: {Schema.KEY_DAY: day, Schema.KEY_TIME: time}}
	)

func _resolve_physical_source(instance: Node, action: Dictionary) -> Dictionary:
	var target_id := str(action.get(Schema.KEY_TARGET, ""))
	if target_id != "":
		var target_roots: Array = []
		var chunk: Variant = _object_property(instance, "_active_chunk")
		if chunk is Object and is_instance_valid(chunk):
			target_roots.append(chunk)
		target_roots.append(instance)
		for root_v in target_roots:
			var root := root_v as Object
			if root.has_method("get_playthrough_interaction_target"):
				var target: Variant = root.call(
					"get_playthrough_interaction_target", target_id)
				if target is Node and is_instance_valid(target):
					return _step_ok(
						"", {Schema.KEY_VALUE: _interaction_source_from_target(target as Node)})

	var source_path := str(action.get(Schema.KEY_SOURCE_PATH, ""))
	if source_path != "":
		var path_result := _read_object_path(instance, source_path)
		if bool(path_result.get(Schema.KEY_OK, false)):
			var source: Variant = path_result.get(Schema.KEY_VALUE)
			if source is Node and is_instance_valid(source):
				return _step_ok(
					"", {Schema.KEY_VALUE: _interaction_source_from_target(source as Node)})

	var description := target_id if target_id != "" else source_path
	return _step_error(
		Schema.ERROR_SOURCE_NOT_FOUND,
		"Could not resolve physical interaction source: %s" % description
	)

func _interaction_source_from_target(target: Node) -> Node:
	if target.has_method("_trigger"):
		return target
	if target.has_method("get_interaction_delegate"):
		var delegate_v: Variant = target.call("get_interaction_delegate")
		if delegate_v is Node and is_instance_valid(delegate_v):
			return delegate_v as Node
	return target

func _read_object_path(root: Object, path: String) -> Dictionary:
	var current: Variant = root
	var parts := path.split(".", false)
	for part_v in parts:
		var part := str(part_v)
		if current is Dictionary:
			if not (current as Dictionary).has(part):
				return {Schema.KEY_OK: false}
			current = (current as Dictionary)[part]
		elif current is Object and is_instance_valid(current):
			var object := current as Object
			if part == "chunk" and object == root:
				current = _object_property(object, "_active_chunk")
			elif _object_has_property(object, part):
				current = object.get(part)
			else:
				return {Schema.KEY_OK: false}
		else:
			return {Schema.KEY_OK: false}
		if current == null:
			return {Schema.KEY_OK: false}
	return {Schema.KEY_OK: true, Schema.KEY_VALUE: current}

func _physical_source_data_position(instance: Node, source: Node3D) -> Vector3:
	var game_state: Variant = _object_property(instance, "_game_state")
	var data_id := str(_object_property(source, "data_id"))
	if game_state is Object and is_instance_valid(game_state) and data_id != "" \
			and game_state.has_method("has_interactable") \
			and bool(game_state.call("has_interactable", data_id)) \
			and game_state.has_method("get_interactable"):
		var spec: Variant = game_state.call("get_interactable", data_id)
		if spec is Dictionary:
			var registered_position: Variant = (spec as Dictionary).get(
				"position", Vector3.INF)
			if registered_position is Vector3 and registered_position.is_finite():
				return registered_position

	var position := source.global_position
	if game_state is Object and is_instance_valid(game_state):
		var coord_map: Variant = _object_property(game_state, "coord_map")
		if coord_map is Object and is_instance_valid(coord_map) \
				and coord_map.has_method("to_data"):
			var data_position: Variant = coord_map.call("to_data", position)
			if data_position is Vector3:
				return data_position
	return position

func _object_has_property(object: Object, property_name: String) -> bool:
	if object == null or not is_instance_valid(object):
		return false
	for property_v in object.get_property_list():
		if property_v is Dictionary \
				and str((property_v as Dictionary).get("name", "")) == property_name:
			return true
	return false

func _object_property(object: Object, property_name: String) -> Variant:
	return object.get(property_name) if _object_has_property(object, property_name) else null

func _validate_authoritative_character_placement(
		instance: Node, char_id: String) -> Dictionary:
	var game_state_v: Variant = _object_property(instance, "_game_state")
	if not (game_state_v is Object) or not is_instance_valid(game_state_v):
		return _step_error(
			Schema.ERROR_GAME_STATE_NOT_FOUND,
			"Cannot verify %s placement without the scene GameState" % char_id
		)
	var game_state := game_state_v as Object
	if not game_state.has_method("get_render_position"):
		return _step_error(
			Schema.ERROR_GAME_STATE_NOT_FOUND,
			"Scene GameState cannot report %s's render position" % char_id
		)
	var characters_v: Variant = _object_property(game_state, "characters")
	if not (characters_v is Dictionary) or not (characters_v as Dictionary).has(char_id):
		return _step_error(
			Schema.ERROR_CHARACTER_NOT_FOUND,
			"GameState does not contain requested character %s" % char_id
		)

	var character_node := _resolve_live_character_node(instance, char_id)
	if character_node == null:
		return _step_error(
			Schema.ERROR_CHARACTER_NOT_FOUND,
			"Scene does not expose a live Node3D for requested character %s" % char_id
		)
	var expected_v: Variant = game_state.call("get_render_position", char_id)
	if not (expected_v is Vector3):
		return _step_error(
			Schema.ERROR_GAME_STATE_NOT_FOUND,
			"GameState returned no render position for %s" % char_id
		)
	var expected: Vector3 = expected_v
	var actual := character_node.global_transform.origin
	var distance := actual.distance_to(expected)
	if not actual.is_finite() or not expected.is_finite() \
			or distance > AUTHORITATIVE_PLACEMENT_TOLERANCE:
		return _step_error(
			Schema.ERROR_CHARACTER_TRANSFORM_MISMATCH,
			(
				"Live %s origin %s does not match authoritative render position %s "
				+ "(distance %.6f)"
			) % [char_id, actual, expected, distance],
			{
				"actual_position": actual,
				"expected_position": expected,
				"distance": distance,
			}
		)
	return _step_ok("Verified authoritative placement for %s" % char_id)

func _resolve_live_character_node(instance: Node, char_id: String) -> Node3D:
	var characters_v: Variant = _object_property(instance, "_characters")
	if characters_v is Dictionary:
		var character_v: Variant = (characters_v as Dictionary).get(char_id)
		if character_v is Node3D and is_instance_valid(character_v):
			return character_v as Node3D
	if instance.has_method("_get_character_node"):
		var accessed_character_v: Variant = instance.call("_get_character_node", char_id)
		if accessed_character_v is Node3D and is_instance_valid(accessed_character_v):
			return accessed_character_v as Node3D
	return null

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
