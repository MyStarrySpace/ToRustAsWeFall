class_name GameEvent
extends RefCounted

## Plain-data simulation input for replay.
## Shape: {tick: float, kind: StringName, payload: Dictionary}.
## Vectors are stored as arrays for JSON diagnostics.

# --- Character lifecycle ---
const KIND_REGISTER_CHARACTER := &"register_character"
const KIND_UNREGISTER_CHARACTER := &"unregister_character"

# --- Movement commands ---
const KIND_MOVE_TO_CELL := &"move_to_cell"
const KIND_MOVE_CROSS_LEVEL := &"move_cross_level"  # pathfind to a cell on another floor (over ladders/ramps)
const KIND_MOVE_TO_POS := &"move_to_pos"
const KIND_WALK_PATH := &"walk_path"
const KIND_STOP := &"stop"
const KIND_CHANGE_SPEED := &"change_speed"

# --- Stats and running ---
# adjust_stat/reset_characters_to_full replay through set_stat.
const KIND_SET_STAT := &"set_stat"
const KIND_SET_RUNNING := &"set_running"
const KIND_SET_ROUTE_MODE := &"set_route_mode"  # global safe(cautious)/direct routing toggle (Tab) — changes pathfinding, so it must replay
const KIND_SET_LEVEL := &"set_level"  # character changed floors (ladder/ramp arrival)
const KIND_SNAP_POSITION := &"snap_position"  # teleport a character's data position (e.g. an enemy's attack-lunge end)

# --- Item commands ---
# Spawn ids are deterministic under replay.
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
const KIND_PUSH_OBJECT := &"push_object"  # Sokoban push: char walks behind the object and shoves it cell-by-cell to a target
const KIND_APPLY_AREA_IMPULSE := &"apply_area_impulse"

# --- Pendulum commands ---
const KIND_REGISTER_PENDULUM := &"register_pendulum"
const KIND_UNREGISTER_PENDULUM := &"unregister_pendulum"

# --- Dodge ---
const KIND_DODGE_ROLL := &"dodge_roll"

# --- Abilities ---
# Replay looks up queued ability handlers by ability id.
const KIND_QUEUE_ABILITY := &"queue_ability"
const KIND_CANCEL_QUEUED_ABILITY := &"cancel_queued_ability"

# --- Narrative state transitions ---
# Down/restore controls narrative availability.
const KIND_DOWN_CHARACTER := &"down_character"
const KIND_RESTORE_CHARACTER := &"restore_character"
# die_scripted is the only permanent death path.
const KIND_DIE_SCRIPTED := &"die_scripted"

# --- Party cohesion ---
# Party movement is one command; splits are scripted.
const KIND_SET_PARTY := &"set_party"
const KIND_PARTY_MOVE_TO_CELL := &"party_move_to_cell"
const KIND_PARTY_MOVE_TO_POS := &"party_move_to_pos"
const KIND_START_SPLIT := &"start_split"
const KIND_END_SPLIT := &"end_split"

# --- Interactables (data layer owns them; scene node is a view) ---
# Scene-scoped like mechanisms: rebuilt by replaying the log, not snapshot-serialized.
const KIND_REGISTER_INTERACTABLE := &"register_interactable"
const KIND_UNREGISTER_INTERACTABLE := &"unregister_interactable"
const KIND_TRIGGER_INTERACTABLE := &"trigger_interactable"
const KIND_SET_INTERACTABLE_ENABLED := &"set_interactable_enabled"
const KIND_RESET_INTERACTABLE := &"reset_interactable"

const ALL_KINDS: Array[StringName] = [
	KIND_REGISTER_CHARACTER,
	KIND_UNREGISTER_CHARACTER,
	KIND_MOVE_TO_CELL,
	KIND_MOVE_CROSS_LEVEL,
	KIND_MOVE_TO_POS,
	KIND_WALK_PATH,
	KIND_STOP,
	KIND_CHANGE_SPEED,
	KIND_SNAP_POSITION,
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
	KIND_PUSH_OBJECT,
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
	KIND_SET_STAT,
	KIND_SET_RUNNING,
	KIND_SET_ROUTE_MODE,
	KIND_REGISTER_INTERACTABLE,
	KIND_UNREGISTER_INTERACTABLE,
	KIND_TRIGGER_INTERACTABLE,
	KIND_SET_INTERACTABLE_ENABLED,
	KIND_RESET_INTERACTABLE,
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
