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

# --- Item commands ---
# spawn_item returns the new item id, but the id is deterministic given
# replay of the same sequence (counter starts at 1, only spawn increments).
const KIND_SPAWN_ITEM := &"spawn_item"
const KIND_REMOVE_ITEM := &"remove_item"
const KIND_PICK_UP_ITEM := &"pick_up_item"
const KIND_DROP_ITEM := &"drop_item"
const KIND_TRANSFER_ITEM := &"transfer_item"
const KIND_ENDOCYTOSE_ITEM := &"endocytose_item"
const KIND_CANCEL_ENDOCYTOSIS := &"cancel_endocytosis"
const KIND_EXOCYTOSE_ITEM := &"exocytose_item"

# --- Physics commands ---
const KIND_REGISTER_PHYSICS_OBJECT := &"register_physics_object"
const KIND_UNREGISTER_PHYSICS_OBJECT := &"unregister_physics_object"
const KIND_THROW_PHYSICS_OBJECT := &"throw_physics_object"
const KIND_APPLY_AREA_IMPULSE := &"apply_area_impulse"

# --- Pendulum commands ---
const KIND_REGISTER_PENDULUM := &"register_pendulum"
const KIND_UNREGISTER_PENDULUM := &"unregister_pendulum"

# --- Dodge ---
const KIND_DODGE_ROLL := &"dodge_roll"

# --- Abilities ---
# The Callable side of queue_ability is not replay-safe. Replay looks up
# the handler by ability id in GameState._ability_handlers; game code that
# wants replay-safe abilities must register handlers via
# GameState.register_ability_handler before replaying.
const KIND_QUEUE_ABILITY := &"queue_ability"
const KIND_CANCEL_QUEUED_ABILITY := &"cancel_queued_ability"

# --- Narrative state transitions ---
# down_character and restore_character are gameplay commands that flip a
# character's narrative-availability (can they speak in scenes? can they
# stand on pressure plates?). Driven by damage / rest sequences.
const KIND_DOWN_CHARACTER := &"down_character"
const KIND_RESTORE_CHARACTER := &"restore_character"
# die_scripted is the ONLY path to permanent death. Combat-driven damage
# produces downs (recoverable at hub); death is reserved for narrative
# beats authored in sequence scripts.
const KIND_DIE_SCRIPTED := &"die_scripted"

# --- Party cohesion ---
# Party movement addresses every party member with one command. The player
# clicks once and the whole party goes. Splits are scripted narrative
# events — the player does not initiate splits, the story does.
const KIND_SET_PARTY := &"set_party"
const KIND_PARTY_MOVE_TO_CELL := &"party_move_to_cell"
const KIND_PARTY_MOVE_TO_POS := &"party_move_to_pos"
const KIND_START_SPLIT := &"start_split"
const KIND_END_SPLIT := &"end_split"

const ALL_KINDS: Array[StringName] = [
	KIND_REGISTER_CHARACTER,
	KIND_UNREGISTER_CHARACTER,
	KIND_MOVE_TO_CELL,
	KIND_MOVE_TO_POS,
	KIND_WALK_PATH,
	KIND_STOP,
	KIND_CHANGE_SPEED,
	KIND_SPAWN_ITEM,
	KIND_REMOVE_ITEM,
	KIND_PICK_UP_ITEM,
	KIND_DROP_ITEM,
	KIND_TRANSFER_ITEM,
	KIND_ENDOCYTOSE_ITEM,
	KIND_CANCEL_ENDOCYTOSIS,
	KIND_EXOCYTOSE_ITEM,
	KIND_REGISTER_PHYSICS_OBJECT,
	KIND_UNREGISTER_PHYSICS_OBJECT,
	KIND_THROW_PHYSICS_OBJECT,
	KIND_APPLY_AREA_IMPULSE,
	KIND_REGISTER_PENDULUM,
	KIND_UNREGISTER_PENDULUM,
	KIND_DODGE_ROLL,
	KIND_QUEUE_ABILITY,
	KIND_CANCEL_QUEUED_ABILITY,
	KIND_DOWN_CHARACTER,
	KIND_RESTORE_CHARACTER,
	KIND_DIE_SCRIPTED,
	KIND_SET_PARTY,
	KIND_PARTY_MOVE_TO_CELL,
	KIND_PARTY_MOVE_TO_POS,
	KIND_START_SPLIT,
	KIND_END_SPLIT,
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
