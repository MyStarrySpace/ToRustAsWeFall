class_name GameEvent
extends RefCounted

## Schema for entries in the event log.
##
## Events represent external inputs to the simulation (player commands,
## sequence-script directives, AI decisions) — not internal state mutations.
## Internal mutations are produced deterministically by the scheduler when
## the same inputs are replayed against an identical starting state.
##
## Each event is a Dictionary with three fields:
##   tick    : float        — scheduler tick at which the input was issued
##   kind    : StringName   — one of the KIND_* constants below
##   payload : Dictionary   — input arguments, restricted to plain data
##                            (no Callables, no Node refs)
##
## Vectors are stored as flat arrays so the log is JSON-compatible for
## diagnostics. Use _arr_to_v3 / _v3_to_arr to convert.

# --- Character lifecycle ---
const KIND_REGISTER_CHARACTER := &"register_character"
const KIND_UNREGISTER_CHARACTER := &"unregister_character"

# --- Movement commands ---
const KIND_MOVE_TO_CELL := &"move_to_cell"
const KIND_MOVE_TO_POS := &"move_to_pos"
const KIND_WALK_PATH := &"walk_path"
const KIND_STOP := &"stop"
const KIND_CHANGE_SPEED := &"change_speed"

const ALL_KINDS: Array[StringName] = [
	KIND_REGISTER_CHARACTER,
	KIND_UNREGISTER_CHARACTER,
	KIND_MOVE_TO_CELL,
	KIND_MOVE_TO_POS,
	KIND_WALK_PATH,
	KIND_STOP,
	KIND_CHANGE_SPEED,
]

static func make(tick: float, kind: StringName, payload: Dictionary) -> Dictionary:
	assert(ALL_KINDS.has(kind), "Unknown GameEvent kind: %s" % kind)
	return {
		"tick": tick,
		"kind": kind,
		"payload": payload.duplicate(true),
	}

static func v3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func arr_to_v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]

static func arr_to_v2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

static func path_to_arr(path: Array[Vector3]) -> Array:
	var out: Array = []
	for p in path:
		out.append(v3_to_arr(p))
	return out

static func arr_to_path(arr: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for a in arr:
		out.append(arr_to_v3(a))
	return out
