class_name EventLog
extends RefCounted

## Append-only ordered log of GameEvent dictionaries.
##
## The log plus a base seed are sufficient to reconstruct the exact game
## state at any point in the recorded session via GameState.replay.
##
## Save files, replay tooling, and bug-report exports all serialize this
## same structure.

## v1: single var_to_bytes blob (atomic save, no partial recovery).
## v2: length-prefixed header + per-event blobs. A corrupted or truncated
##     event terminates loading at that point; everything before it is
##     returned as a partial log. Crash safety + diagnostic recovery.
const FORMAT_VERSION := 2
# Magic header. 8 bytes: "TRWFLOG" + format version byte. Built as a byte
# array because GDScript strings don't support \x escapes and PackedByteArray
# constructor calls aren't constant expressions.
static var MAGIC: PackedByteArray = PackedByteArray([0x54, 0x52, 0x57, 0x46, 0x4C, 0x4F, 0x47, 0x02])

enum LoadStatus {
	OK,         ## Whole stream decoded cleanly
	TRUNCATED,  ## Stream ended mid-event (file cut short)
	CORRUPTED,  ## An event blob failed to decode
	BAD_HEADER, ## Magic / header missing or unreadable
}

var base_seed: int = 0
var events: Array = []

## The latest scheduler tick observed during recording. Always >= last event
## tick. Replay drains pending scheduler events up to this tick so movements
## still in flight at save time complete identically. Callers extend it via
## note_tick when the scheduler advances without producing a logged event.
var recorded_until: float = 0.0

## Wall-clock unix seconds at the most recent serialize. Stored in the
## header for UI display ("saved 5 minutes ago"); never read by game logic.
var saved_unix: int = 0

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

func _header_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"base_seed": base_seed,
		"recorded_until": recorded_until,
		"saved_unix": saved_unix,
	}

# Length-prefixed binary stream:
#   [8 bytes magic][4 bytes header_len][header_bytes][per event: 4 bytes ev_len + ev_bytes]
# An event whose ev_len overruns the buffer is treated as TRUNCATED;
# an event whose blob fails to decode is treated as CORRUPTED. In both
# cases the events successfully decoded so far are returned.
func to_bytes() -> PackedByteArray:
	saved_unix = int(Time.get_unix_time_from_system())
	var out := PackedByteArray()
	out.append_array(MAGIC)
	var header_bytes := var_to_bytes(_header_dict())
	out.append_array(_pack_u32(header_bytes.size()))
	out.append_array(header_bytes)
	for event in events:
		var ev_bytes := var_to_bytes(event)
		out.append_array(_pack_u32(ev_bytes.size()))
		out.append_array(ev_bytes)
	return out

## Returns Dictionary {log: EventLog, status: LoadStatus, recovered: int}.
## On any non-OK status the log still contains every event that decoded
## cleanly before the failure point.
static func load_bytes(bytes: PackedByteArray) -> Dictionary:
	var log := EventLog.new()
	var status: LoadStatus = LoadStatus.OK
	var recovered := 0

	if bytes.size() < MAGIC.size() or bytes.slice(0, MAGIC.size()) != MAGIC:
		return {"log": log, "status": LoadStatus.BAD_HEADER, "recovered": 0}
	var pos := MAGIC.size()

	if pos + 4 > bytes.size():
		return {"log": log, "status": LoadStatus.BAD_HEADER, "recovered": 0}
	var header_len := _unpack_u32(bytes, pos)
	pos += 4
	if pos + header_len > bytes.size():
		return {"log": log, "status": LoadStatus.BAD_HEADER, "recovered": 0}
	var header_var: Variant = bytes_to_var(bytes.slice(pos, pos + header_len))
	if not (header_var is Dictionary):
		return {"log": log, "status": LoadStatus.BAD_HEADER, "recovered": 0}
	var header: Dictionary = header_var
	var ver: int = int(header.get("version", 0))
	if ver != FORMAT_VERSION:
		push_warning("EventLog: format version %d != expected %d" % [ver, FORMAT_VERSION])
	log.base_seed = int(header.get("base_seed", 0))
	log.recorded_until = float(header.get("recorded_until", 0.0))
	log.saved_unix = int(header.get("saved_unix", 0))
	pos += header_len

	while pos < bytes.size():
		if pos + 4 > bytes.size():
			status = LoadStatus.TRUNCATED
			break
		var ev_len := _unpack_u32(bytes, pos)
		pos += 4
		if pos + ev_len > bytes.size():
			status = LoadStatus.TRUNCATED
			break
		var ev_var: Variant = bytes_to_var(bytes.slice(pos, pos + ev_len))
		if not (ev_var is Dictionary):
			status = LoadStatus.CORRUPTED
			break
		log.events.append(ev_var)
		recovered += 1
		pos += ev_len

	return {"log": log, "status": status, "recovered": recovered}

## Convenience: load and discard the status. Use load_bytes when corruption
## handling matters.
static func from_bytes(bytes: PackedByteArray) -> EventLog:
	var result := load_bytes(bytes)
	return result["log"]

static func _pack_u32(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, n)
	return out

static func _unpack_u32(bytes: PackedByteArray, pos: int) -> int:
	return bytes.decode_u32(pos)
