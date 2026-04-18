class_name EventLog
extends RefCounted

## Append-only ordered log of GameEvent dictionaries.
##
## The log plus a base seed are sufficient to reconstruct the exact game
## state at any point in the recorded session via GameState.replay.
##
## Save files, replay tooling, and bug-report exports all serialize this
## same structure.

const FORMAT_VERSION := 1

var base_seed: int = 0
var events: Array = []

## The latest scheduler tick observed during recording. Always >= last event
## tick. Replay drains pending scheduler events up to this tick so movements
## still in flight at save time complete identically. Callers extend it via
## note_tick when the scheduler advances without producing a logged event.
var recorded_until: float = 0.0

## Append an event. Tick must be monotonically non-decreasing.
func append(event: Dictionary) -> void:
	assert(event.has("tick") and event.has("kind") and event.has("payload"),
		"Event missing required fields")
	if not events.is_empty():
		var last_tick: float = float(events[events.size() - 1]["tick"])
		var new_tick: float = float(event["tick"])
		assert(new_tick >= last_tick - 1e-6,
			"Events must be appended in monotonic tick order (last=%f, new=%f)"
				% [last_tick, new_tick])
	events.append(event)
	var t: float = float(event["tick"])
	if t > recorded_until:
		recorded_until = t

## Update the recorded-until tick. Used after scheduler advances that issue
## no commands (e.g. waiting for a character to arrive).
func note_tick(tick: float) -> void:
	if tick > recorded_until:
		recorded_until = tick

func size() -> int:
	return events.size()

func is_empty() -> bool:
	return events.is_empty()

func clear() -> void:
	events.clear()

func last_tick() -> float:
	if events.is_empty():
		return 0.0
	return float(events[events.size() - 1]["tick"])

# --- Serialization ---

func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"base_seed": base_seed,
		"recorded_until": recorded_until,
		"events": events.duplicate(true),
	}

static func from_dict(data: Dictionary) -> EventLog:
	var log := EventLog.new()
	var ver: int = int(data.get("version", 0))
	if ver != FORMAT_VERSION:
		push_warning("EventLog: format version %d != expected %d" % [ver, FORMAT_VERSION])
	log.base_seed = int(data.get("base_seed", 0))
	log.recorded_until = float(data.get("recorded_until", 0.0))
	var raw: Array = data.get("events", [])
	log.events = raw.duplicate(true)
	return log

func to_bytes() -> PackedByteArray:
	return var_to_bytes(to_dict())

static func from_bytes(bytes: PackedByteArray) -> EventLog:
	var data: Variant = bytes_to_var(bytes)
	if data is Dictionary:
		return from_dict(data)
	push_error("EventLog: bytes did not decode to a Dictionary")
	return EventLog.new()
