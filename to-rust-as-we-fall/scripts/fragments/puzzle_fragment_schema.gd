class_name PuzzleFragmentSchema
extends RefCounted

enum ActionType {
	UNKNOWN,
	SELECT_CHARACTER,
	TELEPORT,
	ADVANCE,
	CALL,
	CALL_CHUNK,
	SNAPSHOT_STATE,
	REFRESH_ANCHORS,
	ASSERT_PATH,
}

enum CompareOp {
	UNKNOWN,
	EQUAL,
	NOT_EQUAL,
	GREATER,
	GREATER_OR_EQUAL,
	LESS,
	LESS_OR_EQUAL,
	IN,
	CONTAINS,
}

const ACTION_SELECT_CHARACTER := "select_character"
const ACTION_TELEPORT := "teleport"
const ACTION_ADVANCE := "advance"
const ACTION_CALL := "call"
const ACTION_CALL_CHUNK := "call_chunk"
const ACTION_SNAPSHOT_STATE := "snapshot_state"
const ACTION_REFRESH_ANCHORS := "refresh_anchors"
const ACTION_ASSERT_PATH := "assert_path"

const ACTION_TYPE_NAMES := {
	ActionType.SELECT_CHARACTER: ACTION_SELECT_CHARACTER,
	ActionType.TELEPORT: ACTION_TELEPORT,
	ActionType.ADVANCE: ACTION_ADVANCE,
	ActionType.CALL: ACTION_CALL,
	ActionType.CALL_CHUNK: ACTION_CALL_CHUNK,
	ActionType.SNAPSHOT_STATE: ACTION_SNAPSHOT_STATE,
	ActionType.REFRESH_ANCHORS: ACTION_REFRESH_ANCHORS,
	ActionType.ASSERT_PATH: ACTION_ASSERT_PATH,
}

const ACTION_NAME_TO_TYPE := {
	ACTION_SELECT_CHARACTER: ActionType.SELECT_CHARACTER,
	ACTION_TELEPORT: ActionType.TELEPORT,
	ACTION_ADVANCE: ActionType.ADVANCE,
	ACTION_CALL: ActionType.CALL,
	ACTION_CALL_CHUNK: ActionType.CALL_CHUNK,
	ACTION_SNAPSHOT_STATE: ActionType.SNAPSHOT_STATE,
	ACTION_REFRESH_ANCHORS: ActionType.REFRESH_ANCHORS,
	ACTION_ASSERT_PATH: ActionType.ASSERT_PATH,
}

const OP_EQUAL := "=="
const OP_NOT_EQUAL := "!="
const OP_GREATER := ">"
const OP_GREATER_OR_EQUAL := ">="
const OP_LESS := "<"
const OP_LESS_OR_EQUAL := "<="
const OP_IN := "in"
const OP_CONTAINS := "contains"

const COMPARE_OP_NAMES := {
	CompareOp.EQUAL: OP_EQUAL,
	CompareOp.NOT_EQUAL: OP_NOT_EQUAL,
	CompareOp.GREATER: OP_GREATER,
	CompareOp.GREATER_OR_EQUAL: OP_GREATER_OR_EQUAL,
	CompareOp.LESS: OP_LESS,
	CompareOp.LESS_OR_EQUAL: OP_LESS_OR_EQUAL,
	CompareOp.IN: OP_IN,
	CompareOp.CONTAINS: OP_CONTAINS,
}

const COMPARE_NAME_TO_OP := {
	OP_EQUAL: CompareOp.EQUAL,
	OP_NOT_EQUAL: CompareOp.NOT_EQUAL,
	OP_GREATER: CompareOp.GREATER,
	OP_GREATER_OR_EQUAL: CompareOp.GREATER_OR_EQUAL,
	OP_LESS: CompareOp.LESS,
	OP_LESS_OR_EQUAL: CompareOp.LESS_OR_EQUAL,
	OP_IN: CompareOp.IN,
	OP_CONTAINS: CompareOp.CONTAINS,
}

const KEY_ACTION_TYPE := "type"
const KEY_ACTUAL := "actual"
const KEY_ANCHOR := "anchor"
const KEY_ARGS := "args"
const KEY_CATALOG_PATH := "catalog_path"
const KEY_CHAR_ID := "char_id"
const KEY_DISPLAY_NAME := "display_name"
const KEY_ERROR := "error"
const KEY_EXPECTED := "expected"
const KEY_FAILED := "failed"
const KEY_FINAL_STATE := "final_state"
const KEY_FRAGMENT_FILTER := "fragment_filter"
const KEY_FRAGMENTS := "fragments"
const KEY_ID := "id"
const KEY_INDEX := "index"
const KEY_KEY := "key"
const KEY_KIND := "kind"
const KEY_MESSAGE := "message"
const KEY_METHOD := "method"
const KEY_OFFSET := "offset"
const KEY_OK := "ok"
const KEY_OP := "op"
const KEY_PASSED := "passed"
const KEY_PATH := "path"
const KEY_POSITION := "position"
const KEY_SCENARIOS := "scenarios"
const KEY_SCENE := "scene"
# When KEY_SCENE is the shared fragment_preview.tscn, these pick the chunk it loads (the consolidated
# preview replaced the per-chunk *_preview.tscn files). Omitted for fragments that load a real scene.
const KEY_PREVIEW_CHUNK := "preview_chunk"
const KEY_PREVIEW_CHUNK_CONFIG := "preview_chunk_config"
const KEY_SCRIPT := "script"
const KEY_SECONDS := "seconds"
const KEY_SETUP := "setup"
const KEY_SETTLE_FRAMES := "settle_frames"
const KEY_SNAPSHOT := "snapshot"
const KEY_SNAPSHOT_PATH := "snapshot_path"
const KEY_STEP := "step"
const KEY_STEPS := "steps"
const KEY_SUCCESS := "success"
const KEY_VALUE := "value"

const SCENARIO_SCENE_LOAD := "scene_load"
const UNKNOWN_NAME := "unknown"

const ERROR_ANCHOR_NOT_FOUND := "anchor_not_found"
const ERROR_ASSERT_FAILED := "assert_failed"
const ERROR_INSTANTIATE_FAILED := "instantiate_failed"
const ERROR_INVALID_ACTION := "invalid_action"
const ERROR_INVALID_ANCHOR := "invalid_anchor"
const ERROR_MISSING_CHAR_ID := "missing_char_id"
const ERROR_MISSING_METHOD := "missing_method"
const ERROR_MISSING_METHOD_NAME := "missing_method_name"
const ERROR_MISSING_PATH := "missing_path"
const ERROR_MISSING_POSITION := "missing_position"
const ERROR_MISSING_SNAPSHOT := "missing_snapshot"
const ERROR_MISSING_SNAPSHOT_KEY := "missing_snapshot_key"
const ERROR_PATH_NOT_FOUND := "path_not_found"
const ERROR_SCENE_NOT_FOUND := "scene_not_found"
const ERROR_SNAPSHOT_PATH_NOT_FOUND := "snapshot_path_not_found"
const ERROR_STEP_FAILED := "step_failed"
const ERROR_UNKNOWN_ACTION := "unknown_action"

const METHOD_HEADLESS_ADVANCE := "headless_advance"
const METHOD_HEADLESS_CALL_CHUNK := "headless_call_chunk"
const METHOD_HEADLESS_GET_ANCHORS := "headless_get_anchor_positions"
const METHOD_HEADLESS_GET_STATE := "headless_get_state"
const METHOD_HEADLESS_SELECT_CHARACTER := "headless_select_character"
const METHOD_HEADLESS_SET_CHARACTER_POSITION := "headless_set_character_position"


static func action_type_from_variant(value: Variant) -> int:
	return int(ACTION_NAME_TO_TYPE.get(str(value), ActionType.UNKNOWN))


static func action_name(action_type: int) -> String:
	return str(ACTION_TYPE_NAMES.get(action_type, "unknown"))


static func compare_op_from_variant(value: Variant) -> int:
	return int(COMPARE_NAME_TO_OP.get(str(value), CompareOp.UNKNOWN))


static func compare_op_name(compare_op: int) -> String:
	return str(COMPARE_OP_NAMES.get(compare_op, "unknown"))
