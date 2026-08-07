class_name GameState
extends RefCounted

const CanonicalCharacterAbilityScript := preload(
	"res://scripts/game/mechanics/canonical_character_ability.gd")


## Scheduler-driven state for movement, stats, items, hazards, and replay.
## Positions are derived from ticks. Detection is predicted when movement changes.

signal character_arrived(id: String)
signal movement_started(id: String)  # a movement committed for id (derived event, like character_arrived)
signal movement_cancelled(id: String) # a committed ordinary path ended before its authored arrival
## An accepted navigation command replaced its active planar route because its
## locomotion pace changed. Presentation uses this derived signal to name the
## replan even when the new geometric suffix is exactly the same length.
signal navigation_route_replanned(id: String, state: Dictionary)
## A rally moved without this member because they could not reach the formation. Presentation binds
## this to mark them in the WORLD (an X over their head) so a partial rally is never a silent split.
## Derived like character_arrived — the rally event already records who actually moved.
signal rally_member_blocked(id: String, reason: Dictionary)
signal external_traversal_started(id: String, state: Dictionary)
signal external_traversal_finished(id: String, traversal_id: StringName)
signal external_traversal_cancelled(id: String, traversal_id: StringName, reason: StringName)
signal mechanism_phase_started(mechanism_id: StringName, state: Dictionary)
signal mechanism_phase_completed(mechanism_id: StringName, phase: StringName)
signal mechanism_phase_reset(mechanism_id: StringName, reason: StringName)
signal detection_predicted(detector_id: String, target_id: String)
signal physics_collision(obj_id: String, collider_id: String, impulse: Vector3)
signal pendulum_hit(pendulum_id: String, target_id: String, bob_velocity: Vector3)
signal item_picked_up(char_id: String, item_id: String)
signal item_dropped(char_id: String, item_id: String)
signal item_endocytosed(char_id: String, item_id: String, effect: String)
signal item_transferred(from_id: String, to_id: String, item_id: String)
signal item_exocytosed(char_id: String, item_id: String)
signal ability_fired(char_id: String, ability: String, target_pos: Vector3)
signal dodge_started(char_id: String, direction: Vector3)
signal knockdown_started(char_id: String)
signal knockdown_ended(char_id: String)
signal dodge_finished(char_id: String)
signal stat_changed(char_id: String, stat: String, value: float)
signal damage_absorbed(char_id: String, amount: float, shield_remaining: float, source_id: String)
signal damage_shield_changed(char_id: String, amount: float, source_id: String)
## A party body took an enemy strike (emitted by the shared Enemy._resolve_strike
## path AFTER damage + knockback commit). Presentation-only consumers (screen
## shake, flash, blink, offscreen alerts) — never gameplay logic.
signal character_struck(char_id: String, attacker_id: String)
signal running_changed(char_id: String, running: bool)
signal interactable_registered(id: String)
signal interactable_triggered(id: String, character: String)
signal interactable_enabled_changed(id: String, enabled: bool)
## Emitted once after an authoritative snapshot has been rebuilt and prediction queues are armed.
## Scene presenters may rebind here; no gameplay command is emitted during restoration.
signal snapshot_restored(snapshot: Dictionary)

var grid: GridWorld
var route_cautious := false  # global safe/direct routing (Tab); set via set_route_mode (logged)
var scheduler: EventScheduler
var explored: Dictionary = {}
var characters: Dictionary = {}
var physics_objects: Dictionary = {}
var pendulums: Dictionary = {}
var items: Dictionary = {}        # item_id → item dict
## Which registered characters are PARTY. register_character gives every character (enemies
## included) empty hands, and there is no faction concept anywhere else, so without this an
## auto-catch would let an enemy pocket a thrown item. Derived state, set by the sequence at
## registration — never logged, rebuilt identically on replay, like concealment and distraction.
var party_ids: Dictionary = {}    # char_id → true
var collection: Array[String] = [] # Permanently collected item IDs (cure components, etc.)
## Scene-scoped mechanisms, not serialized.
var mechanisms: Dictionary = {}   # id (StringName) → Mechanism
## Scene-scoped interactables as data (the source of truth; the scene node is a
## view bound to an id). Like mechanisms: rebuilt by replaying the log, not
## snapshot-serialized. id (String) → spec Dictionary.
var interactables: Dictionary = {}
var _next_item_id := 1
var _endocytosing: Dictionary = {} # char_id → {item_id, handle} for in-progress endocytosis
var _dodging: Dictionary = {}     # char_id → {end_tick, handle}
var _knocked_down: Dictionary = {}  # char_id → {end_tick, handle} — fell on a no-stamina dodge; vulnerable
## Ability shields are scheduler-derived combat state. WRAP applies one of these; ordinary
## negative HP deltas pass through this single resolver instead of scene-private shield flags.
var _damage_shields: Dictionary = {}  # char_id -> {amount, source_id, handle, expires_tick}
## Per-character running tick state. Missing key = walking.
var _running: Dictionary = {}
## Cooperative-pathfinding space-time reservations: Vector2i cell →
## Array of {t0, t1, id}. A character claims each cell it transits for a
## padded time window so others can plan paths that never overlap it in
## space and time. Derived from movement, never serialized.
var _reservations: Dictionary = {}
## Space-time nodes the LAST _plan_cooperative call expanded (0 when an early-out or the uncontested
## spatial fast path handled it). Derived diagnostic for perf tests; never serialized.
var _coop_last_nodes := 0
## Pathfinding tracing — run with PATHFIND_DEBUG=1. Prints every cooperative search + the preview, AND
## appends to the flushed file GridWorld writes (user://pathfind.log) so it survives a hard crash.
static var _pf_debug: bool = OS.has_environment("PATHFIND_DEBUG")

## In-flight graph plans: char_id -> ordered Array of per-level segments. Each segment retains the
## typed edge that enters it plus execution flags, so an authored LADDER/RAMP never degrades into an
## instantaneous `set_level`. The edge is executed by the scheduler-authoritative traversal machine;
## both the remaining plan and active edge survive save/load and deterministic replay.
var _cross_level_plan: Dictionary = {}

## Scheduler callbacks are allowed to outlive the movement record that created them (for example,
## when a Rally replaces a path while the scheduler is already dispatching a due batch).  The
## callback must therefore identify its own movement instead of completing whichever replacement
## happens to be stored under the same character id.
var _next_movement_epoch := 1

## Authoritative mechanism-owned movement. Unlike an ordinary path, its simulation/data endpoints
## may differ from its visible endpoints (a generated helix climb is vertical in the rendered world
## while returning one loop in flat data space). Progress is always a pure scheduler-tick function.
## `locked` refuses ordinary movement until derived completion or an explicit authorized cancel.
var _external_traversals: Dictionary = {} # char_id -> traversal state + scheduler handle

## Logged, saveable scheduler phases for world mechanisms. Scene nodes are deliberately only views:
## they query this registry to render progress and enable their interactions. A mechanism remains
## deploying/deployed through replay or save/load even when its presenting node is constructed later.
var _timed_mechanism_phases: Dictionary = {} # mechanism_id -> phase state + scheduler handle

const HP_MAX := 100.0
const STAMINA_MAX := 100.0
const ATP_MAX_PIPS := 8.0
const ATP_PIP_STEP := 0.5
const WALK_SPEED := 3.0
const RUN_SPEED := 6.0
# Tunable (not const) so the tension sweep can measure candidate economies; the DEFAULT is the
# game-wide currency every tension chunk prices its routes in.
var run_stamina_drain_per_sec := 15.0   # one full bar = 40wu of sprint (the tension-sweep ruling)
const RUN_TICK_INTERVAL := 0.1
## Detection ignores targets separated by more than this vertical gap (a stacked floor). Standing-
## height / ramp differences stay within it; a full level (grid.level_height ~4) is blocked.
const DETECTION_VERTICAL_BAND := 2.0
## A medium hide drops an enemy's effective spotting range to this fraction of its outer range — the
## "inner" tier. Close enough (inside this band) and a corner/scarpet won't shake a chaser.
const DETECTION_INNER_FACTOR := 0.45
## How often a wall-BLOCKED spot re-checks while the pair is still moving (scheduler ticks). Coarse enough
## to stay cheap, fine enough that stepping out of cover mid-move is seen within a step.
const DETECTION_LOS_RECHECK_INTERVAL := 0.25
## Upper bound on one armed re-check chain (~30s of continuous motion). A deterministic backstop so a
## permanently-blocked pair that never stops moving (roam yards) can't poll forever; any recompute or a
## fresh primary event starts a new chain with a fresh budget.
const DETECTION_LOS_RECHECK_MAX_HOPS := 120

## Detection is invalidated by movement/state changes, then solved analytically into scheduler events.
## These derived registries keep that work proportional to active detector->target subscriptions instead
## of every character pair in the scene. The counters are deliberately cheap and exposed for performance
## regressions; they never affect simulation or serialization.
var _detection_active_pairs: Dictionary = {}  # symmetric pair tag -> {a, b}
var _detection_batch_depth := 0
var _detection_batch_dirty := false
var _detection_batch_all_dirty := false
var _detection_batch_dirty_ids: Dictionary = {}
var _performance_counters := {
	"detection_recomputes": 0,
	"detection_pairs_considered": 0,
	"detection_predictions_solved": 0,
	"detection_events_scheduled": 0,
	"cooperative_plans": 0,
	"cooperative_fast_paths": 0,
	"cooperative_wait_fast_paths": 0,
	"cooperative_conflict_searches": 0,
	"group_replans": 0,
	"group_replan_members": 0,
	"plain_plans": 0,
}

func reset_performance_counters() -> void:
	for key in _performance_counters.keys():
		_performance_counters[key] = 0

func get_performance_counters() -> Dictionary:
	return _performance_counters.duplicate()

## Coalesce a burst of state/movement invalidations (for example, revealing a streamed ecology) into
## one detection rebuild. Nestable so scene activation and movement replacement can share the seam.
func begin_detection_update_batch() -> void:
	_detection_batch_depth += 1

func end_detection_update_batch() -> void:
	if _detection_batch_depth <= 0:
		return
	_detection_batch_depth -= 1
	if _detection_batch_depth == 0 and _detection_batch_dirty:
		var all_dirty := _detection_batch_all_dirty
		var dirty_ids := _detection_batch_dirty_ids.keys()
		_detection_batch_dirty = false
		_detection_batch_all_dirty = false
		_detection_batch_dirty_ids.clear()
		if not all_dirty and dirty_ids.size() == 1:
			_recompute_all_detection_predictions(str(dirty_ids[0]))
		else:
			_recompute_all_detection_predictions()

static func normalize_atp(value: float) -> float:
	if value > ATP_MAX_PIPS + 0.001:
		return clampf(quantize_atp((value / 100.0) * ATP_MAX_PIPS), 0.0, ATP_MAX_PIPS)
	return clamp_atp(value)

static func quantize_atp(value: float) -> float:
	return roundf(value / ATP_PIP_STEP) * ATP_PIP_STEP

static func clamp_atp(value: float) -> float:
	return clampf(quantize_atp(value), 0.0, ATP_MAX_PIPS)

static func atp_text(value: float) -> String:
	var normalized := normalize_atp(value)
	if is_equal_approx(normalized, roundf(normalized)):
		return "%d/%d" % [int(normalized), int(ATP_MAX_PIPS)]
	return "%.1f/%d" % [normalized, int(ATP_MAX_PIPS)]

## Optional log for external commands.
var event_log: EventLog
var _recording: bool = true

## Consumed by the next GameState so CLI recording starts at setup.
static var _pending_event_log: EventLog = null

## Run seed used by every deterministic RNG.
var base_seed: int = 0

## Per-system deterministic RNG registry.
var rng_registry: RngRegistry

func _init() -> void:
	if _pending_event_log != null:
		event_log = _pending_event_log
		_pending_event_log = null
	rng_registry = RngRegistry.new(base_seed)

## Set before systems fetch RNGs.
func set_base_seed(seed_value: int) -> void:
	base_seed = seed_value
	rng_registry = RngRegistry.new(seed_value)
	if event_log != null:
		event_log.base_seed = seed_value

func _record_tick() -> float:
	if scheduler:
		return scheduler.get_current_tick()
	return 0.0

func _emit(kind: StringName, payload: Dictionary) -> void:
	if EventLog.print_events:
		print("[EVENT t=%8.2f] %-20s %s" % [_record_tick(), str(kind), str(payload)])
	if event_log == null or not _recording:
		return
	event_log.append(GameEvent.make(_record_tick(), kind, payload))

## Extend the log to the current scheduler tick before serializing.
func flush_tick() -> void:
	if event_log != null and _recording and scheduler:
		event_log.note_tick(scheduler.get_current_tick())

## Pendulum schema:
## {
##   anchor: Vector3,         # Pivot point (top of swing)
##   length: float,           # Rope/chain length
##   amplitude: float,        # Max swing angle in radians
##   phase: float,            # Phase offset in radians
##   swing_axis: Vector3,     # Normalized swing-plane axis.
##   bob_radius: float,       # Collision radius of the bob
##   damping: float,          # Amplitude decay per second (0 = no decay)
##   start_tick: float,       # When oscillation began
## }

## PhysicsObject schema:
## {
##   position: Vector3,
##   radius: float,           # Collision radius
##   mass: float,             # 1.0 = character-weight
##   friction: float,         # 0.3 = icy, 0.8 = rough
##   movement: Dictionary|null,  # Same schema as character movement
##   grid_cell: Vector2i,
##   pushable: bool,
## }

## CharDict schema:
## {
##   position: Vector3,         # Settled position (updated on arrival/stop)
##   grid_cell: Vector2i,       # Settled grid cell
##   move_speed: float,
##   stats: Dictionary,
##   movement: Dictionary|null  # Non-null when in motion
##     {
##       path: Array[Vector3],
##       cum_dist: Array[float],
##       total_distance: float,
##       start_tick: float,
##       duration: float,
##       handle: int,
##     }
## }

func register_character(id: String, pos: Vector3, speed: float = 3.0, stats: Dictionary = {}) -> void:
	_emit(GameEvent.KIND_REGISTER_CHARACTER, {
		"id": id,
		"pos": GameEvent.v3_to_arr(pos),
		"speed": speed,
		"stats": stats.duplicate(true),
	})
	var normalized_stats := stats.duplicate(true)
	if normalized_stats.has("atp"):
		normalized_stats["atp"] = normalize_atp(float(normalized_stats["atp"]))
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	characters[id] = {
		"position": pos,
		"grid_cell": cell,
		"level": _level_for_y(pos.y),  # which stacked floor (derived from spawn Y)
		"move_speed": speed,
		"stats": normalized_stats,
		"movement": null,
		"hands": [null, null],
		"internal": [],
	}
	explored[id] = {}
	_reserve_parked(id, cell)

## Which stacked floor a world Y sits on (round to the nearest grid level). 0 without a grid.
func _level_for_y(y: float) -> int:
	if grid != null and grid.level_height > 0.0:
		return int(round((y - grid.origin.y) / grid.level_height))
	return 0

func get_character_level(id: String) -> int:
	return int((characters.get(id, {}) as Dictionary).get("level", 0))

## Set a character's floor (a level transition — a ladder/ramp arrival). Stops any current move and
## snaps the data-layer Y to that floor, so positions/paths read at the right height.
func set_character_level(id: String, level: int) -> void:
	if not characters.has(id) or is_external_traversal_active(id):
		return
	_emit(GameEvent.KIND_SET_LEVEL, {"id": id, "level": level})
	_apply_set_level(id, level)

## Floor change without its own log entry — used by the cross-level executor so a
## whole multi-floor traversal is one logged command (the transitions are derived,
## not separately recorded). Snaps the data-layer Y to the target floor.
func _apply_set_level(id: String, level: int) -> void:
	if not characters.has(id):
		return
	var p := get_position(id)  # capture the current interpolated position before cancelling
	_cancel_movement(id)
	characters[id]["level"] = level
	if grid != null:
		p.y = grid.origin.y + float(level) * grid.level_height
	characters[id]["position"] = p
	if grid != null:
		characters[id]["grid_cell"] = grid.world_to_grid(p)
		_reserve_parked(id, characters[id]["grid_cell"])

func unregister_character(id: String) -> void:
	_emit(GameEvent.KIND_UNREGISTER_CHARACTER, {"id": id})
	clear_damage_shield(id)
	_cancel_external_traversal_derived(id, &"unregistered")
	_end_drag_involving(id)
	_cross_level_plan.erase(id)
	if characters.has(id):
		# Cleanup only; no log entry.
		if _running.has(id):
			var handle: int = int(_running[id].get("tick_handle", 0))
			if handle != 0 and scheduler:
				scheduler.cancel(handle)
			_running.erase(id)
		_cancel_movement(id)
		if scheduler:
			for other in characters.keys():
				if str(other) != id:
					scheduler.cancel_tag(_detection_pair_tag(id, str(other)))
		_cancel_detection_prediction_tags(id)
	characters.erase(id)
	explored.erase(id)
	_coop_exempt.erase(id)

# --- Movement Commands ---

## Presentation provenance travels with player-facing authority instead of being inferred later
## from a traversal id or a surprising endpoint. Empty remains backward-compatible for direct
## navigation and legacy internal traversals; new forced consequences use the player_facing scope.
## Bookkeeping that intentionally has no cue must name its silent reason explicitly.
func _validated_presentation_receipt(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	var portable := value.duplicate(true)
	var scope := str(value.get("scope", ""))
	if scope not in ["player_facing", "direct_input", "bookkeeping"]:
		return {}
	if scope == "bookkeeping":
		return portable if not str(value.get("silent_reason", "")).is_empty() else {}
	if scope == "direct_input":
		return portable
	for required_key in [
		"event_id", "cause_id", "cause_kind", "effect_kind", "cue_kind",
	]:
		if str(value.get(required_key, "")).is_empty():
			return {}
	# A visible mechanism can carry its own telegraph. Such receipts keep causal
	# provenance and world motion without manufacturing explanatory UI copy.
	if bool(value.get("show_label", true)) and str(value.get("label", "")).is_empty():
		return {}
	if str(value.get("effect_kind", "")) == "forced_movement" \
			and str(value.get("destination_label", "")).is_empty():
		return {}
	if str(value.get("effect_kind", "")) == "forced_movement" \
			and str(value.get("subject_id", "")).is_empty():
		return {}
	for tick_key in ["telegraph_tick", "commit_tick"]:
		if value.has(tick_key) and not is_finite(float(value[tick_key])):
			return {}
	for position_key in ["source_render_position", "destination_render_position"]:
		var position_v: Variant = value.get(position_key, null)
		var position: Array = []
		if position_v is Vector3:
			position = GameEvent.v3_to_arr(position_v as Vector3)
		elif position_v is Array:
			position = (position_v as Array).duplicate()
		if position.size() != 3:
			return {}
		for component in position:
			if not is_finite(float(component)):
				return {}
		portable[position_key] = [
			float(position[0]), float(position[1]), float(position[2])]
	return portable

## Commit a mechanism-owned traversal. The event records both coordinate spaces and the complete
## time interval; once accepted, the rider is immediately owned by this state machine rather than
## standing at the origin until a delayed teleport. `locked` is the sole policy today: ordinary
## move/stop commands are refused, while a hazard or checkpoint may invoke the separately logged
## cancel command with an explicit reason.
func command_external_traversal(
		id: String,
		traversal_id: StringName,
		data_destination: Vector3,
		render_origin: Vector3,
		render_destination: Vector3,
		duration: float,
		interrupt_policy: StringName = &"locked",
		presentation_receipt: Dictionary = {}
	) -> bool:
	var data_origin := get_position(id) if characters.has(id) else Vector3.ZERO
	return command_external_path_traversal(
		id,
		traversal_id,
		[data_origin, data_destination],
		[render_origin, render_destination],
		duration,
		interrupt_policy,
		presentation_receipt)


## Path-preserving mechanism traversal. A crawl/rail/river may cross grid-forbidden space along
## authored bends; reducing that transit to an endpoint lerp changes both what can see the rider and
## what a replay shows. The complete paired data/render waypoint paths are logged and serialized.
func command_external_path_traversal(
		id: String,
		traversal_id: StringName,
		data_path_value: Array,
		render_path_value: Array,
		duration: float,
		interrupt_policy: StringName = &"locked",
		presentation_receipt: Dictionary = {}
	) -> bool:
	if not characters.has(id) or scheduler == null or duration <= 0.0:
		return false
	if _external_traversals.has(id) or interrupt_policy != &"locked":
		return false
	if is_endocytosing(id) or is_dodging(id) or is_knocked_down(id) \
			or is_downed(id) or is_dragging(id):
		return false
	var data_path := _validated_external_path(data_path_value)
	var render_path := _validated_external_path(render_path_value)
	if data_path.size() < 2 or render_path.size() != data_path.size() \
			or not (data_path[0] as Vector3).is_equal_approx(get_position(id)):
		return false
	if is_running(id):
		set_running(id, false)
	var start_tick := float(scheduler.get_current_tick())
	var data_path_payload := _external_path_to_payload(data_path)
	var render_path_payload := _external_path_to_payload(render_path)
	var portable_presentation := _validated_presentation_receipt(presentation_receipt)
	if not presentation_receipt.is_empty() and portable_presentation.is_empty():
		return false
	var payload := {
		"id": id,
		"traversal_id": traversal_id,
		"data_origin": data_path_payload[0],
		"data_destination": data_path_payload[data_path_payload.size() - 1],
		"render_origin": render_path_payload[0],
		"render_destination": render_path_payload[render_path_payload.size() - 1],
		"data_path": data_path_payload,
		"render_path": render_path_payload,
		"start_tick": start_tick,
		"end_tick": start_tick + duration,
		"progress_start": 0.0,
		"interrupt_policy": interrupt_policy,
		"presentation_receipt": portable_presentation,
	}
	_emit(GameEvent.KIND_BEGIN_EXTERNAL_TRAVERSAL, payload)
	return _apply_external_traversal(payload)


## Explicit interruption seam for hazards/checkpoints. Ordinary player movement never calls this
## for a locked traversal. Cancellation freezes the authoritative data position at the current tick.
func cancel_external_traversal(id: String, reason: StringName = &"cancelled") -> bool:
	if not _external_traversals.has(id):
		return false
	var state: Dictionary = _external_traversals[id]
	var payload := {
		"id": id,
		"traversal_id": state.get("traversal_id", &""),
		"reason": reason,
	}
	_emit(GameEvent.KIND_CANCEL_EXTERNAL_TRAVERSAL, payload)
	return _apply_cancel_external_traversal(payload)


func is_external_traversal_active(id: String) -> bool:
	return _external_traversals.has(id)


## Handle-free readback for saves, interaction guards, tests, and pause inspection.
func get_external_traversal_state(id: String) -> Dictionary:
	if not _external_traversals.has(id):
		return {}
	var state: Dictionary = _external_traversals[id]
	var out := state.duplicate(true)
	out.erase("handle")
	var now := float(scheduler.get_current_tick()) if scheduler != null else float(state["start_tick"])
	var progress := _external_traversal_progress_at(state, now)
	out["progress"] = progress
	out["remaining"] = maxf(0.0, float(state["end_tick"]) - now)
	out["data_position"] = _external_data_position_at(state, now)
	out["render_position"] = _external_render_position_at(state, now)
	return out


func _apply_external_traversal(payload: Dictionary) -> bool:
	var id := str(payload.get("id", ""))
	if not characters.has(id) or scheduler == null or _external_traversals.has(id):
		return false
	var policy := StringName(str(payload.get("interrupt_policy", "")))
	if policy != &"locked":
		return false
	var start_tick := float(payload.get("start_tick", scheduler.get_current_tick()))
	var end_tick := float(payload.get("end_tick", start_tick))
	var progress_start := clampf(float(payload.get("progress_start", 0.0)), 0.0, 1.0)
	if end_tick <= start_tick or end_tick < float(scheduler.get_current_tick()) \
			or progress_start >= 1.0:
		return false
	var data_origin := GameEvent.arr_to_v3(payload.get("data_origin", [0.0, 0.0, 0.0]))
	var data_destination := GameEvent.arr_to_v3(payload.get("data_destination", [0.0, 0.0, 0.0]))
	var render_origin := GameEvent.arr_to_v3(payload.get("render_origin", [0.0, 0.0, 0.0]))
	var render_destination := GameEvent.arr_to_v3(payload.get("render_destination", [0.0, 0.0, 0.0]))
	var data_path := _external_path_from_payload(
		payload.get("data_path", []), data_origin, data_destination)
	var render_path := _external_path_from_payload(
		payload.get("render_path", []), render_origin, render_destination)
	var traversal_id := StringName(str(payload.get("traversal_id", "")))
	var presentation_receipt := _validated_presentation_receipt(
		payload.get("presentation_receipt", {}) as Dictionary)
	if not (payload.get("presentation_receipt", {}) as Dictionary).is_empty() \
			and presentation_receipt.is_empty():
		return false
	if String(traversal_id).is_empty() or data_path.size() < 2 \
			or render_path.size() != data_path.size():
		return false
	data_origin = data_path[0]
	data_destination = data_path[data_path.size() - 1]
	render_origin = render_path[0]
	render_destination = render_path[render_path.size() - 1]

	# A typed navigation edge uses this same authoritative traversal engine, but its remaining
	# graph plan must survive until the edge lands and the next planar segment begins.
	var preserves_graph_plan := bool(payload.get("preserve_cross_level_plan", false))
	if not preserves_graph_plan:
		_cross_level_plan.erase(id)
	_cancel_movement(id)
	_stop_rest(id)
	cancel_field_restore(id)
	characters[id]["position"] = data_origin
	if grid != null:
		characters[id]["grid_cell"] = grid.world_to_grid(data_origin)
		_clear_reservations(id)
	var handle := int(scheduler.schedule_at(
		end_tick,
		_finish_external_traversal.bind(id, traversal_id, start_tick),
		"external_traversal_%s" % id
	))
	if handle <= 0:
		return false
	var path_cumulative := _external_path_cumulative(data_path)
	if float(path_cumulative[path_cumulative.size() - 1]) <= 0.000001:
		path_cumulative = _external_path_cumulative(render_path)
	if float(path_cumulative[path_cumulative.size() - 1]) <= 0.000001:
		scheduler.cancel(handle)
		return false
	_external_traversals[id] = {
		"traversal_id": traversal_id,
		"data_origin": data_origin,
		"data_destination": data_destination,
		"render_origin": render_origin,
		"render_destination": render_destination,
		"data_path": data_path,
		"render_path": render_path,
		"path_cumulative": path_cumulative,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"progress_start": progress_start,
		"interrupt_policy": policy,
		"preserve_cross_level_plan": preserves_graph_plan,
		"navigation_edge": (payload.get("navigation_edge", {}) as Dictionary).duplicate(true),
		"presentation_receipt": presentation_receipt,
		"handle": handle,
	}
	movement_started.emit(id)
	external_traversal_started.emit(id, get_external_traversal_state(id))
	_recompute_all_detection_predictions(id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()
	return true


func _finish_external_traversal(id: String, traversal_id: StringName, start_tick: float) -> void:
	if not characters.has(id) or not _external_traversals.has(id):
		return
	var state: Dictionary = _external_traversals[id]
	if state.get("traversal_id", &"") != traversal_id \
			or not is_equal_approx(float(state.get("start_tick", -1.0)), start_tick):
		return
	var destination: Vector3 = state["data_destination"]
	_external_traversals.erase(id)
	characters[id]["position"] = destination
	if grid != null:
		characters[id]["grid_cell"] = grid.world_to_grid(destination)
		characters[id]["level"] = _level_for_y(destination.y)
		_reserve_parked(id, characters[id]["grid_cell"])
	external_traversal_finished.emit(id, traversal_id)
	character_arrived.emit(id)
	_recompute_all_detection_predictions(id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()


func _apply_cancel_external_traversal(payload: Dictionary) -> bool:
	var id := str(payload.get("id", ""))
	if not characters.has(id) or not _external_traversals.has(id):
		return false
	var state: Dictionary = _external_traversals[id]
	var requested_id := StringName(str(payload.get("traversal_id", "")))
	if requested_id != state.get("traversal_id", &""):
		return false
	var now := float(scheduler.get_current_tick()) if scheduler != null else float(state["start_tick"])
	var pinned := _external_data_position_at(state, now)
	if scheduler != null:
		scheduler.cancel(int(state.get("handle", 0)))
	_external_traversals.erase(id)
	# An interrupted typed edge invalidates the remainder of its route. Otherwise the generic
	# arrival signal below would resume the plan from a point midway through the traversal.
	if bool(state.get("preserve_cross_level_plan", false)):
		_cross_level_plan.erase(id)
	characters[id]["position"] = pinned
	if grid != null:
		characters[id]["grid_cell"] = grid.world_to_grid(pinned)
		characters[id]["level"] = _level_for_y(pinned.y)
		_reserve_parked(id, characters[id]["grid_cell"])
	var reason := StringName(str(payload.get("reason", "cancelled")))
	external_traversal_cancelled.emit(id, requested_id, reason)
	character_arrived.emit(id)
	_recompute_all_detection_predictions(id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()
	return true


func _cancel_external_traversal_derived(id: String, reason: StringName) -> bool:
	if not _external_traversals.has(id):
		return false
	var state: Dictionary = _external_traversals[id]
	return _apply_cancel_external_traversal({
		"id": id,
		"traversal_id": state.get("traversal_id", &""),
		"reason": reason,
	})


func _external_traversal_progress_at(state: Dictionary, tick: float) -> float:
	var progress_start := clampf(float(state.get("progress_start", 0.0)), 0.0, 1.0)
	return lerpf(progress_start, 1.0, _external_traversal_local_progress_at(state, tick))


func _external_traversal_local_progress_at(state: Dictionary, tick: float) -> float:
	var start := float(state.get("start_tick", tick))
	var finish := float(state.get("end_tick", start))
	if finish <= start:
		return 1.0
	return clampf((tick - start) / (finish - start), 0.0, 1.0)


func _external_data_position_at(state: Dictionary, tick: float) -> Vector3:
	var path: Array = state.get("data_path", [])
	var cumulative: Array = state.get("path_cumulative", [])
	if path.size() >= 2 and cumulative.size() == path.size():
		return _external_path_position_at(
			path, cumulative, _external_traversal_progress_at(state, tick))
	return (state.get("data_origin", Vector3.ZERO) as Vector3).lerp(
		state.get("data_destination", Vector3.ZERO) as Vector3,
		_external_traversal_local_progress_at(state, tick))


func _external_render_position_at(state: Dictionary, tick: float) -> Vector3:
	var path: Array = state.get("render_path", [])
	var cumulative: Array = state.get("path_cumulative", [])
	if path.size() >= 2 and cumulative.size() == path.size():
		return _external_path_position_at(
			path, cumulative, _external_traversal_progress_at(state, tick))
	return (state.get("render_origin", Vector3.ZERO) as Vector3).lerp(
		state.get("render_destination", Vector3.ZERO) as Vector3,
		_external_traversal_local_progress_at(state, tick))


func _validated_external_path(raw: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for value in raw:
		if not value is Vector3 or not (value as Vector3).is_finite():
			return []
		out.append(value as Vector3)
	return out


func _external_path_to_payload(path: Array) -> Array:
	var out: Array = []
	for point in path:
		out.append(GameEvent.v3_to_arr(point as Vector3))
	return out


func _external_path_from_payload(
		raw: Variant, fallback_origin: Vector3, fallback_destination: Vector3
	) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if raw is Array:
		for value in raw as Array:
			var point: Vector3
			if value is Vector3:
				point = value as Vector3
			elif value is Array and (value as Array).size() >= 3:
				point = GameEvent.arr_to_v3(value)
			else:
				return []
			if not point.is_finite():
				return []
			out.append(point)
	if out.size() >= 2:
		return out
	return [fallback_origin, fallback_destination]


func _external_path_cumulative(path: Array) -> Array[float]:
	var out: Array[float] = [0.0]
	for i in range(1, path.size()):
		out.append(out[i - 1] + (path[i - 1] as Vector3).distance_to(path[i] as Vector3))
	return out


func _external_path_position_at(path: Array, cumulative: Array, progress: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if path.size() == 1 or cumulative.size() != path.size():
		return path[path.size() - 1] as Vector3
	var total := float(cumulative[cumulative.size() - 1])
	if total <= 0.000001:
		return path[path.size() - 1] as Vector3
	var distance := clampf(progress, 0.0, 1.0) * total
	for i in range(1, cumulative.size()):
		var segment_end := float(cumulative[i])
		if distance > segment_end and i < cumulative.size() - 1:
			continue
		var segment_start := float(cumulative[i - 1])
		var span := segment_end - segment_start
		var local := clampf((distance - segment_start) / span, 0.0, 1.0) \
			if span > 0.000001 else 1.0
		return (path[i - 1] as Vector3).lerp(path[i] as Vector3, local)
	return path[path.size() - 1] as Vector3


# --- Scheduler-owned mechanism phases ---

## Commit a one-way timed phase such as `deploying -> deployed`. The full timing window is logged at
## commitment; progress and completion are derived from scheduler time. An existing state (active or
## completed) refuses a second commitment until an explicit reset, preventing double-tend exploits.
func command_begin_mechanism_phase(
		mechanism_id: StringName,
		phase: StringName,
		duration: float,
		completion_phase: StringName,
		metadata: Dictionary = {}
	) -> bool:
	if scheduler == null or String(mechanism_id).is_empty() or String(phase).is_empty() \
			or String(completion_phase).is_empty() or phase == completion_phase or duration <= 0.0:
		return false
	if _timed_mechanism_phases.has(mechanism_id):
		return false
	var start_tick := float(scheduler.get_current_tick())
	var payload := {
		"mechanism_id": mechanism_id,
		"phase": phase,
		"completion_phase": completion_phase,
		"start_tick": start_tick,
		"end_tick": start_tick + duration,
		"progress_start": 0.0,
		"metadata": metadata.duplicate(true),
	}
	_emit(GameEvent.KIND_BEGIN_MECHANISM_PHASE, payload)
	return _apply_begin_mechanism_phase(payload)


## Explicitly clear either an active or completed mechanism phase. Reset is itself logged so a
## checkpoint replay cannot leave a gate open merely because its old completion callback once ran.
func command_reset_mechanism_phase(
		mechanism_id: StringName,
		reason: StringName = &"reset"
	) -> bool:
	if not _timed_mechanism_phases.has(mechanism_id):
		return false
	var payload := {
		"mechanism_id": mechanism_id,
		"reason": reason,
	}
	_emit(GameEvent.KIND_RESET_MECHANISM_PHASE, payload)
	return _apply_reset_mechanism_phase(payload)


func has_mechanism_phase(mechanism_id: StringName) -> bool:
	return _timed_mechanism_phases.has(mechanism_id)


## Handle-free authoritative readback. Presentation code may sample this every frame; doing so never
## mutates simulation or adds log entries.
func get_mechanism_phase_state(mechanism_id: StringName) -> Dictionary:
	if not _timed_mechanism_phases.has(mechanism_id):
		return {}
	var state: Dictionary = _timed_mechanism_phases[mechanism_id]
	var out := state.duplicate(true)
	out.erase("handle")
	var now := float(scheduler.get_current_tick()) if scheduler != null \
		else float(state.get("start_tick", 0.0))
	var completed: bool = state.get("phase", &"") == state.get("completion_phase", &"")
	out["progress"] = 1.0 if completed else _mechanism_phase_progress_at(state, now)
	out["remaining"] = 0.0 if completed \
		else maxf(0.0, float(state.get("end_tick", now)) - now)
	return out


func _apply_begin_mechanism_phase(payload: Dictionary) -> bool:
	if scheduler == null:
		return false
	var mechanism_id := StringName(str(payload.get("mechanism_id", "")))
	var phase := StringName(str(payload.get("phase", "")))
	var completion_phase := StringName(str(payload.get("completion_phase", "")))
	if String(mechanism_id).is_empty() or String(phase).is_empty() \
			or String(completion_phase).is_empty() or phase == completion_phase \
			or _timed_mechanism_phases.has(mechanism_id):
		return false
	var now := float(scheduler.get_current_tick())
	var start_tick := float(payload.get("start_tick", now))
	var end_tick := float(payload.get("end_tick", start_tick))
	var progress_start := clampf(float(payload.get("progress_start", 0.0)), 0.0, 1.0)
	if end_tick <= start_tick or end_tick < now or progress_start >= 1.0:
		return false
	var handle := int(scheduler.schedule_at(
		end_tick,
		_finish_mechanism_phase.bind(mechanism_id, phase, start_tick),
		"mechanism_phase_%s" % String(mechanism_id)
	))
	if handle <= 0:
		return false
	_timed_mechanism_phases[mechanism_id] = {
		"mechanism_id": mechanism_id,
		"phase": phase,
		"completion_phase": completion_phase,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"progress_start": progress_start,
		"metadata": (payload.get("metadata", {}) as Dictionary).duplicate(true),
		"handle": handle,
	}
	mechanism_phase_started.emit(mechanism_id, get_mechanism_phase_state(mechanism_id))
	return true


func _finish_mechanism_phase(
		mechanism_id: StringName,
		expected_phase: StringName,
		expected_start_tick: float
	) -> void:
	if not _timed_mechanism_phases.has(mechanism_id):
		return
	var state: Dictionary = _timed_mechanism_phases[mechanism_id]
	if state.get("phase", &"") != expected_phase \
			or not is_equal_approx(float(state.get("start_tick", -1.0)), expected_start_tick):
		return
	var completion_phase := StringName(str(state.get("completion_phase", "")))
	state["phase"] = completion_phase
	state["handle"] = 0
	_timed_mechanism_phases[mechanism_id] = state
	mechanism_phase_completed.emit(mechanism_id, completion_phase)


func _apply_reset_mechanism_phase(payload: Dictionary) -> bool:
	var mechanism_id := StringName(str(payload.get("mechanism_id", "")))
	if not _timed_mechanism_phases.has(mechanism_id):
		return false
	var state: Dictionary = _timed_mechanism_phases[mechanism_id]
	if scheduler != null:
		var handle := int(state.get("handle", 0))
		if handle > 0:
			scheduler.cancel(handle)
	_timed_mechanism_phases.erase(mechanism_id)
	var reason := StringName(str(payload.get("reason", "reset")))
	mechanism_phase_reset.emit(mechanism_id, reason)
	return true


func _mechanism_phase_progress_at(state: Dictionary, tick: float) -> float:
	var progress_start := clampf(float(state.get("progress_start", 0.0)), 0.0, 1.0)
	var start_tick := float(state.get("start_tick", tick))
	var end_tick := float(state.get("end_tick", start_tick))
	if end_tick <= start_tick:
		return 1.0
	var interval_progress := clampf((tick - start_tick) / (end_tick - start_tick), 0.0, 1.0)
	return lerpf(progress_start, 1.0, interval_progress)

func get_navigation_state() -> Dictionary:
	# The grid is the ONE traversal layer — gridless scenes resolve straight-line moves only.
	if grid != null:
		var walkable := 0
		for z in range(grid.height):
			for x in range(grid.width):
				if int(grid.grid[z][x]) != GridWorld.Tile.WALL:
					walkable += 1
		return {
			"contract_id": GridWorld.GRID_DATA_CONTRACT_ID,
			"walkable_cell_count": walkable,
			"link_count": grid.inter_level_links.size(),
			"level_count": grid.level_count,
			"supports_multiple_elevations": grid.level_count > 1,
			"risk_cell_count": grid.risk_cells.size(),
		}
	return {}

## Whether a character can currently accept an ordinary explicit movement command.
## Keep this in lockstep with the internal position/cell move guards so UI previews and
## multi-character commands can report the exact movable roster before issuing an event.
func can_accept_move_command(id: String) -> bool:
	if not characters.has(id) or not scheduler:
		return false
	return not is_endocytosing(id) and not is_dodging(id) \
		and not is_knocked_down(id) and not is_downed(id) \
		and not is_external_traversal_active(id)

## Shared side effects of a fresh explicit movement command. These are derived state, so replay
## applies them through the same command/application path without recording additional events.
func _prepare_explicit_move(id: String) -> void:
	if is_external_traversal_active(id):
		return
	_cross_level_plan.erase(id)
	if not _push_plans.is_empty() and _push_plans.has(id):
		_push_plans.erase(id)
	_stop_rest(id)
	cancel_field_restore(id)

## A* pathfind to a grid cell on the character's current floor. Returns true if a path was found.
func command_move_to_cell(id: String, cell: Vector2i) -> bool:
	_warn_if_off_frame("command_move_to_cell(%s)" % id, grid.grid_to_world(cell) if grid != null else Vector3(float(cell.x), 0.0, float(cell.y)))
	_prepare_explicit_move(id)
	_emit(GameEvent.KIND_MOVE_TO_CELL, {"id": id, "cell": GameEvent.v2i_to_arr(cell)})
	return _do_move_to_cell(id, cell)

## Straight-line move to a world position.
func command_move_to_pos(id: String, pos: Vector3) -> bool:
	_warn_if_off_frame("command_move_to_pos(%s)" % id, pos)
	_prepare_explicit_move(id)
	_emit(GameEvent.KIND_MOVE_TO_POS, {"id": id, "pos": GameEvent.v3_to_arr(pos)})
	return _do_move_to_pos(id, pos)

## Commit the stable graph identity produced by hover resolution. Keeping `(cell, level)` together
## prevents two stacked surfaces at the same XZ from aliasing between preview and RMB dispatch.
## The ordinary command kinds remain the replay wire format; this is the typed routing boundary.
func command_move_to_navigation_location(id: String, location: Dictionary) -> bool:
	if not characters.has(id) or grid == null or location.is_empty():
		return false
	var cell_value: Variant = location.get("cell", null)
	if not cell_value is Vector2i:
		return false
	var cell := cell_value as Vector2i
	var level := int(location.get("level", get_character_level(id)))
	if level < 0 or level >= grid.level_count \
			or not grid.is_walkable(cell.x, cell.y, {}, {}, level):
		return false
	if level == get_character_level(id):
		return command_move_to_cell(id, cell)
	return command_move_cross_level(id, cell, level)

## Pathfind to a cell on a (possibly different) floor, routing over ladders/ramps.
## On the same floor this is just command_move_to_cell. Across floors it walks to the
## ladder cell on the current floor, transitions there, then continues — one logged
## command (KIND_MOVE_CROSS_LEVEL) that replay reproduces transition-for-transition.
## Returns true if a (multi-floor) route exists.
func command_move_cross_level(id: String, end_cell: Vector2i, end_level: int) -> bool:
	_emit(GameEvent.KIND_MOVE_CROSS_LEVEL, {
		"id": id,
		"cell": GameEvent.v2i_to_arr(end_cell),
		"level": end_level,
	})
	return _do_move_cross_level(id, end_cell, end_level)

func _do_move_cross_level(id: String, end_cell: Vector2i, end_level: int) -> bool:
	_cross_level_plan.erase(id)
	if not characters.has(id) or not grid or not scheduler:
		return false
	if is_endocytosing(id) or is_dodging(id) or is_knocked_down(id) or is_downed(id) \
			or is_external_traversal_active(id):
		return false
	var cur_pos := get_position(id)
	var cur_level := get_character_level(id)
	# Same off-mesh-start snap as _begin_cooperative_move (the multi-level A* can't expand
	# from a disconnected cell).
	var cur_cell := grid.nearest_walkable_cell(grid.world_to_grid(cur_pos), cur_level)
	if cur_level == end_level:
		return _do_move_to_cell(id, end_cell)  # same floor — ordinary cooperative move
	var navigation_plan: Dictionary = grid.find_multi_level_plan(
		cur_cell, cur_level, end_cell, end_level)
	var nodes: Array = navigation_plan.get("nodes", [])
	if nodes.is_empty():
		return false  # no ladder/ramp route between these floors
	var segments := _navigation_segments_from_plan(navigation_plan)
	if segments.is_empty():
		return false
	_cross_level_plan[id] = segments
	# The executor advances on ordinary movement and typed-edge arrivals; connect once (survives
	# replay and snapshot restoration on a fresh GameState).
	if not character_arrived.is_connected(_on_cross_level_arrival):
		character_arrived.connect(_on_cross_level_arrival)
	_advance_cross_level_plan(id)
	return _cross_level_plan.has(id) or is_moving(id) \
		or (grid.world_to_grid(get_position(id)) == end_cell \
			and get_character_level(id) == end_level)

## Convert a node+edge plan into planar legs. The edge entering a leg remains attached to that leg;
## this is the information the old waypoint-only reconstruction discarded.
func _navigation_segments_from_plan(navigation_plan: Dictionary) -> Array:
	var nodes: Array = navigation_plan.get("nodes", [])
	var edges: Array = navigation_plan.get("edges", [])
	if nodes.is_empty() or edges.size() != maxi(0, nodes.size() - 1):
		return []
	var first := nodes[0] as Dictionary
	var segments: Array = [{
		"level": int(first.get("level", 0)),
		"cells": [first.get("cell", Vector2i.ZERO)],
		"entry_edge": {},
		"entry_traversed": true,
		"started": false,
	}]
	for edge_index in range(edges.size()):
		var edge := (edges[edge_index] as Dictionary).duplicate(true)
		var next_node := nodes[edge_index + 1] as Dictionary
		var next_level := int(next_node.get("level", 0))
		var next_cell: Vector2i = next_node.get("cell", Vector2i.ZERO)
		var edge_kind := str(edge.get("kind", edge.get("type", "walk"))).to_lower()
		var is_traversal := edge_kind != "walk" \
			or int(edge.get("from_level", next_level)) != int(edge.get("to_level", next_level))
		if is_traversal:
			segments.append({
				"level": next_level,
				"cells": [next_cell],
				"entry_edge": edge,
				"entry_traversed": false,
				"started": false,
			})
		else:
			((segments[segments.size() - 1] as Dictionary)["cells"] as Array).append(next_cell)
	return segments

## Every arrival is interpreted against explicit per-leg phase flags. A planar leg is completed and
## removed; its successor first executes the retained entry edge, then begins its planar cells. This
## prevents an edge's arrival signal from accidentally consuming the leg that still follows it.
func _on_cross_level_arrival(id: String) -> void:
	_advance_cross_level_plan(id)


func _advance_cross_level_plan(id: String) -> void:
	if not _cross_level_plan.has(id):
		return
	var segments: Array = _cross_level_plan[id]
	while not segments.is_empty():
		var segment := segments[0] as Dictionary
		# An arrival after a started planar leg completes exactly that leg.
		if bool(segment.get("started", false)):
			segments.pop_front()
			_cross_level_plan[id] = segments
			continue

		var entry_edge := segment.get("entry_edge", {}) as Dictionary
		if not entry_edge.is_empty() and not bool(segment.get("entry_traversed", false)):
			segment["entry_traversed"] = true
			segments[0] = segment
			_cross_level_plan[id] = segments
			if not _begin_navigation_edge_traversal(id, entry_edge):
				_cross_level_plan.erase(id)
			return

		var cells: Array = segment.get("cells", [])
		if cells.is_empty():
			segments.pop_front()
			_cross_level_plan[id] = segments
			continue
		var segment_level := int(segment.get("level", get_character_level(id)))
		if get_character_level(id) != segment_level:
			push_warning("GameState: graph leg for %s expected level %d, found %d" % [
				id, segment_level, get_character_level(id)])
			_cross_level_plan.erase(id)
			return
		var segment_last: Vector2i = cells[cells.size() - 1]
		if grid != null and grid.world_to_grid(get_position(id)) == segment_last:
			segments.pop_front()
			_cross_level_plan[id] = segments
			continue
		segment["started"] = true
		segments[0] = segment
		_cross_level_plan[id] = segments
		if not _do_move_to_cell(id, segment_last):
			_cross_level_plan.erase(id)
		return
	_cross_level_plan.erase(id)


## Execute an annotated graph edge as authoritative scheduler state. The parent cross-level command
## is already logged, so this derived phase deliberately calls the application path directly instead
## of emitting a second player command into the replay log.
func _begin_navigation_edge_traversal(id: String, edge_value: Dictionary) -> bool:
	if grid == null or scheduler == null or not characters.has(id):
		return false
	var edge := edge_value.duplicate(true)
	if grid.has_method("is_navigation_edge_available") \
			and not bool(grid.call("is_navigation_edge_available", edge)):
		return false
	var from_cell: Vector2i = edge.get("from_cell", grid.world_to_grid(get_position(id)))
	var to_cell: Vector2i = edge.get("to_cell", from_cell)
	var from_level := int(edge.get("from_level", get_character_level(id)))
	var to_level := int(edge.get("to_level", from_level))
	if get_character_level(id) != from_level \
			or grid.world_to_grid(get_position(id)) != from_cell \
			or not grid.is_walkable(to_cell.x, to_cell.y, {}, {}, to_level):
		return false
	var data_origin := get_position(id)
	var data_destination := grid.grid_to_world(to_cell, to_level)
	var render_origin := get_render_position(id)
	var render_destination: Vector3 = data_destination
	if coord_map != null:
		render_destination = coord_map.to_world(data_destination)
	var duration := float(edge.get("duration", 0.0))
	if duration <= 0.0:
		var edge_kind := str(edge.get("kind", edge.get("type", "link"))).to_lower()
		var distance := data_origin.distance_to(data_destination)
		var traversal_speed := WALK_SPEED * (0.75 if edge_kind == "ladder" else 1.0)
		duration = maxf(0.2, distance / maxf(0.1, traversal_speed))
	edge["duration"] = duration
	var edge_kind := str(edge.get("kind", edge.get("type", "link"))).to_lower()
	var traversal_id := StringName("nav/%s/%d,%d,%d/%d,%d,%d" % [
		edge_kind,
		from_cell.x, from_cell.y, from_level,
		to_cell.x, to_cell.y, to_level,
	])
	var start_tick := float(scheduler.get_current_tick())
	var data_path: Array[Vector3] = [data_origin, data_destination]
	var render_path: Array[Vector3] = [render_origin, render_destination]
	return _apply_external_traversal({
		"id": id,
		"traversal_id": traversal_id,
		"data_origin": GameEvent.v3_to_arr(data_origin),
		"data_destination": GameEvent.v3_to_arr(data_destination),
		"render_origin": GameEvent.v3_to_arr(render_origin),
		"render_destination": GameEvent.v3_to_arr(render_destination),
		"data_path": _external_path_to_payload(data_path),
		"render_path": _external_path_to_payload(render_path),
		"start_tick": start_tick,
		"end_tick": start_tick + duration,
		"progress_start": 0.0,
		"interrupt_policy": &"locked",
		"preserve_cross_level_plan": true,
		"navigation_edge": edge,
	})

# Internal move without its own log entry.
func _do_move_to_pos(
		id: String,
		pos: Vector3,
		allow_group_start_wait := false,
		already_prepared := false,
		route_cell_constraint: Dictionary = {}
	) -> bool:
	if not can_accept_move_command(id):
		return false
	# On a grid a position move routes on the CELLS (the cooperative planner, same as a cell move) —
	# never a straight line that would cut through walls. The target quantizes to its cell, exactly
	# what the hover preview shows. On a multi-level grid the target LEVEL is inferred from the
	# position's Y (same as the player's cross-floor click routing), so a move to another elevation
	# walks the ladder/ramp links instead of failing on the current floor. Gridless keeps the
	# straight-line resolution.
	if grid != null:
		# A programmatic position move (chunks, NPC scripts) snaps an off-mesh TARGET to the nearest
		# walkable cell — the grid equivalent of the old graph's snap-to-node. (Player clicks stay
		# strict: command_move_to_cell still rejects an unwalkable destination.)
		if grid.level_count > 1:
			var target_level := grid.level_for_y(pos.y)
			var target_cell := grid.nearest_walkable_cell(grid.world_to_grid(pos), target_level)
			if target_level != get_character_level(id):
				if not route_cell_constraint.is_empty():
					return false
				return _do_move_cross_level(id, target_cell, target_level)
			return _do_move_to_cell(
				id, target_cell, allow_group_start_wait, already_prepared,
				route_cell_constraint)
		return _do_move_to_cell(
			id,
			grid.nearest_walkable_cell(grid.world_to_grid(pos), get_character_level(id)),
			allow_group_start_wait,
			already_prepared,
			route_cell_constraint)
	var current_pos := get_position(id)
	var target := Vector3(pos.x, pos.y, pos.z)
	if not already_prepared:
		_cancel_movement(id)
	characters[id].position = current_pos
	_start_movement(id, _resolve_world_path(current_pos, target))
	return true

## Set an explicit path (scripted waypoints).
func command_walk_path(id: String, path: Array[Vector3]) -> void:
	_cross_level_plan.erase(id)
	_emit(GameEvent.KIND_WALK_PATH, {"id": id, "path": GameEvent.path_to_arr(path)})
	if not characters.has(id) or not scheduler or path.is_empty():
		return
	if is_endocytosing(id) or is_dodging(id) or is_knocked_down(id) or is_downed(id) \
			or is_external_traversal_active(id):
		return
	var current_pos := get_position(id)
	_cancel_movement(id)
	characters[id].position = current_pos
	var full_path: Array[Vector3] = [current_pos]
	full_path.append_array(path)
	_start_movement(id, full_path)

## Halt movement at current interpolated position. Stopping also abandons an in-flight push plan
## (the crate stays wherever its last completed shove left it).
func command_stop(id: String) -> void:
	_cross_level_plan.erase(id)
	_push_plans.erase(id)
	_emit(GameEvent.KIND_STOP, {"id": id})
	_do_stop(id)

func _do_stop(id: String) -> void:
	if not characters.has(id):
		return
	if is_external_traversal_active(id) or is_dodging(id) or is_knocked_down(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement != null:
		ch.position = get_position(id)
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
	_cancel_movement(id)
	_reserve_parked(id, ch.grid_cell)

## Teleport a character's DATA position to a world point with no animation. Ordinary
## combat/AI snaps preserve the current floor Y; authored spawn/reset placement passes
## preserve_y=false so the supplied full-XYZ feet transform becomes authoritative.
## The optional flag is serialized on the existing event kind for compatible replay.
func snap_character_to(id: String, pos: Vector3, preserve_y := true) -> void:
	_warn_if_off_frame("snap_character_to(%s)" % id, pos)
	if not characters.has(id) or is_external_traversal_active(id):
		return
	_emit(GameEvent.KIND_SNAP_POSITION, {
		"id": id,
		"pos": GameEvent.v3_to_arr(pos),
		"preserve_y": preserve_y,
	})
	var ch: Dictionary = characters[id]
	_cancel_movement(id)
	ch.position = Vector3(pos.x, ch.position.y if preserve_y else pos.y, pos.z)
	if grid:
		if not preserve_y:
			ch.level = grid.level_for_y(pos.y)
		ch.grid_cell = grid.world_to_grid(ch.position)
	_reserve_parked(id, ch.grid_cell)
	# _cancel_movement recomputed detection at the PRE-teleport position — its stale in-range events would
	# fire against a spot the character no longer occupies (a swept member could be "spotted" at the place
	# it was swept FROM). Recompute again now that the position has actually moved.
	_recompute_all_detection_predictions()

## Change movement speed. If currently moving, recalculates arrival time.
func change_move_speed(id: String, new_speed: float) -> void:
	_emit(GameEvent.KIND_CHANGE_SPEED, {"id": id, "speed": new_speed})
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	var previous_speed := float(ch.get("move_speed", new_speed))
	ch.move_speed = new_speed
	if ch.movement == null:
		return
	var route_cell_constraint := (ch.movement as Dictionary).get(
		"route_cell_constraint", {}) as Dictionary
	var current_pos := get_position(id)
	var dest: Vector3 = ch.movement.path[ch.movement.path.size() - 1]
	_cancel_movement(id)
	ch.position = current_pos
	if grid:
		# Replan cooperatively at the new speed so a mid-move speed change (e.g.
		# toggling run) keeps respecting other characters' reservations rather
		# than reverting to a plain, overlap-prone straight path.
		var dest_cell := grid.world_to_grid(dest)
		var current_cell := grid.world_to_grid(current_pos)
		if _begin_cooperative_move(
				id, current_pos, current_cell, dest_cell, new_speed, false,
				route_cell_constraint):
			_emit_navigation_route_replanned(
				id, previous_speed, new_speed, "pace_change")
			return
		if not route_cell_constraint.is_empty():
			# A constrained mechanism route may refuse a speed replan, but it may never
			# silently continue on an unrestricted straight line.
			_reserve_parked(id, current_cell)
			return
	_start_movement(id, _resolve_world_path(current_pos, dest))
	_emit_navigation_route_replanned(id, previous_speed, new_speed, "pace_change")


func _emit_navigation_route_replanned(
		id: String, previous_speed: float, next_speed: float, reason: String
	) -> void:
	if not is_navigation_route_active(id):
		return
	navigation_route_replanned.emit(id, {
		"contract": "navigation_route_replan/v1",
		"reason": reason,
		"previous_speed": previous_speed,
		"next_speed": next_speed,
	})

func _resolve_world_path(current_pos: Vector3, target: Vector3) -> Array[Vector3]:
	# Gridless straight line — grid scenes never reach here (_do_move_to_pos routes on cells).
	return [current_pos, target]

## Resolve a surface hit to the stable navigation identity used by both preview and commit. World Y
## selects the stacked level before XZ is quantized, so an upper landing can never become its lower
## same-XZ cell merely because the pointer paused there.
func resolve_navigation_location(id: String, target_pos: Vector3, snap_radius := 3) -> Dictionary:
	if not characters.has(id) or grid == null or not target_pos.is_finite():
		return {}
	var level := grid.level_for_y(target_pos.y) if grid.level_count > 1 \
		else get_character_level(id)
	var requested_cell := grid.world_to_grid(target_pos)
	var cell := grid.nearest_walkable_cell(requested_cell, level, snap_radius)
	if not grid.is_in_bounds(cell.x, cell.y) \
			or not grid.is_walkable(cell.x, cell.y, {}, {}, level):
		return {}
	return {
		"cell": cell,
		"level": level,
		"data_position": grid.grid_to_world(cell, level),
		"graph_revision": grid.get_path_walkability_revision(),
	}


## READ-ONLY typed preview. Besides renderable points it returns the exact `(cell, level)` destination,
## graph revision, and retained node+edge plan. It touches no movement, reservations, or EventLog.
func compute_preview_navigation(id: String, target_pos: Vector3) -> Dictionary:
	var perf_started := PerformanceTrace.begin()
	if not characters.has(id):
		PerformanceTrace.end(&"nav", &"game_state.compute_preview_navigation", perf_started, id, 0)
		return {}
	if _pf_debug:
		GridWorld._pf_trace("[preview] compute_preview_path '%s' -> %v" % [id, target_pos])
	var current := get_position(id)
	if grid != null:
		var location := resolve_navigation_location(id, target_pos)
		if location.is_empty():
			PerformanceTrace.end(&"nav", &"game_state.compute_preview_navigation", perf_started, id, 0)
			return {}
		var level := get_character_level(id)
		var target_level := int(location["level"])
		var start_cell := grid.world_to_grid(current)
		var end_cell: Vector2i = location["cell"]
		# The preview is a COSMETIC hint, recomputed per hovered cell — so it uses the cheap 2D find_path,
		# NOT the cooperative space-time A*. The cooperative search expands (cell, tick) wait-states and, for
		# a far target, explores toward its node cap (≈80ms/hover on the channels — the reported freeze). The
		# click still COMMITS the cooperative route (which detours around other characters' reservations); the
		# dim preview just shows the spatial route, which matches the commit whenever no reservation forces a
		# detour. Speed over perfect fidelity for a hover hint.
		var out: Array[Vector3] = [current]
		var navigation_plan: Dictionary = {}
		if target_level != level:
			navigation_plan = grid.find_multi_level_plan(
				start_cell, level, end_cell, target_level)
			var nodes: Array = navigation_plan.get("nodes", [])
			if nodes.is_empty():
				PerformanceTrace.end(&"nav", &"game_state.compute_preview_navigation", perf_started, id, 0)
				return {}
			# Node zero is the occupied start cell. Every following node remains level-aware, including
			# the paired bottom/top points of a ladder edge.
			for node_index in range(1, nodes.size()):
				var node := nodes[node_index] as Dictionary
				out.append(grid.grid_to_world(
					node.get("cell", Vector2i.ZERO), int(node.get("level", level))))
		else:
			# find_path returns WORLD positions (one per cell) already on the right level.
			var waypoints: Array[Vector3] = grid.find_path(
				start_cell, end_cell, {}, route_cautious, {}, {}, level)
			if waypoints.is_empty() and start_cell != end_cell:
				PerformanceTrace.end(&"nav", &"game_state.compute_preview_navigation", perf_started, id, 0)
				return {}
			out.append_array(waypoints)
			if out.size() == 1:
				out.append(location["data_position"] as Vector3)
		if _pf_debug:
			GridWorld._pf_trace("[preview] returning %d pts" % out.size())
		PerformanceTrace.end(&"nav", &"game_state.compute_preview_navigation", perf_started, id, out.size())
		return {
			"location": location,
			"path": out,
			"plan": navigation_plan,
			"graph_revision": int(location["graph_revision"]),
		}
	var direct := _resolve_world_path(current, target_pos)
	PerformanceTrace.end(&"nav", &"game_state.compute_preview_navigation", perf_started, id, direct.size())
	return {
		"location": {"data_position": target_pos, "level": get_character_level(id)},
		"path": direct,
		"graph_revision": -1,
	}


## Compatibility projection for existing ribbon/debug callers.
func compute_preview_path(id: String, target_pos: Vector3) -> Array[Vector3]:
	var preview := compute_preview_navigation(id, target_pos)
	var out: Array[Vector3] = []
	for point_v in (preview.get("path", []) as Array):
		if point_v is Vector3:
			out.append(point_v as Vector3)
	return out

## READ-ONLY per-member route preview: the path EACH party member WOULD take to its own spread
## destination on a party move. Mirrors party_move_to_pos's spread EXACTLY — distinct grid cells via
## _assign_party_cells, or a deterministic Z-fan when gridless — so the preview matches what the click
## commits. Pure UI: no mutation, no move, no log. Returns [{char_id, path}].
func compute_preview_party_paths(target_pos: Vector3) -> Array:
	var perf_started := PerformanceTrace.begin()
	var members := _main_group()
	var out: Array = []
	if grid != null:
		var assigned := _assign_party_cells(members, grid.world_to_grid(target_pos))
		for id in members:
			var level := get_character_level(id)
			var dest := grid.grid_to_world(assigned[id], level)
			out.append({"char_id": id, "path": compute_preview_path(id, dest)})
	else:
		var count := members.size()
		for i in range(count):
			var lateral := (float(i) - float(count - 1) / 2.0) * _PARTY_GRIDLESS_SPACING
			var dest: Vector3 = target_pos + Vector3(0.0, 0.0, lateral)
			out.append({"char_id": members[i], "path": compute_preview_path(members[i], dest)})
	PerformanceTrace.end(&"nav", &"game_state.compute_preview_party_paths", perf_started, "party", out.size())
	return out

# --- Queries ---

## RENDER-ONLY coordinate map (default null = identity). When set to an object exposing
## `to_world(Vector3)->Vector3` / `to_data(Vector3)->Vector3`, the data layer stays FLAT (positions,
## grid, wash, detection all run in the flat frame) while node followers render through `to_world` —
## e.g. ChannelsCoordMap wraps the flat wash gauntlet onto the channels helix. Never serialized, never
## logged: it's a pure presentation transform a scene installs, so gameplay/replay are unaffected.
var coord_map = null
## Optional authoring-frame bounds for the DATA layer (a warped scene's flat
## frame, e.g. the wash coil's 26x8). Never gameplay-enforced — purely a LOUD
## frame-mixing tripwire: a data-layer move command far outside the authored
## frame almost always means a RENDER position leaked into a data API (the bug
## class a coord_map scene makes possible; a player-contract flake teleported a
## member to the render frame's coordinates once and the cause outran four
## instrumentation passes — this warning is the permanent net). Scenes with a
## coord_map should set it.
var data_frame_bounds := Rect2()

func _warn_if_off_frame(what: String, p: Vector3) -> void:
	if data_frame_bounds.size == Vector2.ZERO:
		return
	if not data_frame_bounds.grow(2.0).has_point(Vector2(p.x, p.z)):
		push_warning("GameState: %s targets (%.1f, %.1f) OUTSIDE the data frame %s — render/data frame mixing?" % [
			what, p.x, p.z, data_frame_bounds])

## The position a character's NODE should render at: the flat data position warped through coord_map
## (identity when no map is installed, so every flat scene is unchanged).
func get_render_position(id: String) -> Vector3:
	if _external_traversals.has(id):
		var state: Dictionary = _external_traversals[id]
		var now := float(scheduler.get_current_tick()) if scheduler != null else float(state["start_tick"])
		return _external_render_position_at(state, now)
	var p := get_position(id)
	return p if coord_map == null else coord_map.to_world(p)

## Current position, interpolated while moving.
func get_position(id: String) -> Vector3:
	if not characters.has(id):
		return Vector3.ZERO
	# A dragged (downed) character rides the dragger: their position is a pure function of the
	# dragger's tick-interpolated position, so the carry is replay-deterministic and fast-forward
	# invariant like all movement.
	var drag_owner := get_dragger_of(id)
	if drag_owner != "":
		return get_position(drag_owner) + DRAG_TRAIL_OFFSET
	if _external_traversals.has(id):
		var external: Dictionary = _external_traversals[id]
		var now := float(scheduler.get_current_tick()) if scheduler != null else float(external["start_tick"])
		return _external_data_position_at(external, now)
	var ch: Dictionary = characters[id]
	if ch.movement == null or not scheduler:
		return ch.position
	var mv: Dictionary = ch.movement
	if mv.has("arrival_ticks"):
		return _interpolate_path_timed(mv.path, mv.arrival_ticks, scheduler.get_current_tick())
	if mv.duration <= 0.0:
		return mv.path[mv.path.size() - 1]
	var t := clampf((scheduler.get_current_tick() - mv.start_tick) / mv.duration, 0.0, 1.0)
	return _interpolate_path(mv.path, mv.cum_dist, t)

## Pure analytic: the position `dt` seconds from now on the CURRENT committed plan (parked
## characters stay put; a finished plan parks at its destination). The chase/lead computations
## read the future the same way the scheduler will play it — never by per-frame sampling.
func predict_position(id: String, dt: float) -> Vector3:
	if not characters.has(id):
		return Vector3.ZERO
	if _external_traversals.has(id):
		var external: Dictionary = _external_traversals[id]
		var future_external_tick := (float(scheduler.get_current_tick()) if scheduler != null else 0.0) \
			+ maxf(0.0, dt)
		return _external_data_position_at(external, future_external_tick)
	var ch: Dictionary = characters[id]
	if ch.movement == null or not scheduler:
		return get_position(id)
	var mv: Dictionary = ch.movement
	var future_tick: float = scheduler.get_current_tick() + maxf(0.0, dt)
	if mv.has("arrival_ticks"):
		return _interpolate_path_timed(mv.path, mv.arrival_ticks, future_tick)
	if mv.duration <= 0.0:
		return mv.path[mv.path.size() - 1]
	var t := clampf((future_tick - mv.start_tick) / mv.duration, 0.0, 1.0)
	return _interpolate_path(mv.path, mv.cum_dist, t)

func is_moving(id: String) -> bool:
	if not characters.has(id):
		return false
	return characters[id].movement != null or is_external_traversal_active(id)


## True while any part of an accepted navigation command still owns the character.
## A typed multi-level plan briefly has no planar movement between an arrival and the
## next ladder/ramp phase; consumers must not mistake that route handoff for a stop.
func is_navigation_route_active(id: String) -> bool:
	if not characters.has(id):
		return false
	return _cross_level_plan.has(id) or is_moving(id)


## Final data-space endpoint of the complete accepted navigation command. Unlike
## `get_destination()`, this does not collapse a multi-level route to its current
## planar leg or typed edge. Malformed retained plans fail closed instead of exposing
## a plausible-but-wrong intermediate destination.
func get_navigation_route_destination(id: String) -> Vector3:
	if not characters.has(id):
		return Vector3.INF
	if not _cross_level_plan.has(id):
		return get_destination(id)
	if grid == null:
		return Vector3.INF
	var segments_value: Variant = _cross_level_plan.get(id, null)
	if not (segments_value is Array) or (segments_value as Array).is_empty():
		return Vector3.INF
	var final_segment_value: Variant = (segments_value as Array).back()
	if not (final_segment_value is Dictionary):
		return Vector3.INF
	var final_segment := final_segment_value as Dictionary
	var cells_value: Variant = final_segment.get("cells", null)
	if not (cells_value is Array) or (cells_value as Array).is_empty():
		return Vector3.INF
	var final_cell_value: Variant = (cells_value as Array).back()
	if not (final_cell_value is Vector2i):
		return Vector3.INF
	var final_level := int(final_segment.get("level", -1))
	if final_level < 0 or final_level >= grid.level_count:
		return Vector3.INF
	return grid.grid_to_world(final_cell_value as Vector2i, final_level)


## Read-only dependency query for moving-platform and topology mechanisms. It intentionally exposes
## cells rather than the private movement record so mechanisms can invalidate routes without
## mutating path internals or guessing from render transforms.
func navigation_route_intersects_cells(
		id: String, cells: Dictionary, levels: Array[int] = []
	) -> bool:
	if not characters.has(id) or grid == null or cells.is_empty():
		return false
	var movement_v: Variant = (characters[id] as Dictionary).get("movement", null)
	if movement_v is Dictionary:
		for point_v in ((movement_v as Dictionary).get("path", []) as Array):
			if not (point_v is Vector3):
				continue
			var point := point_v as Vector3
			var level := grid.level_for_y(point.y)
			if cells.has(grid.world_to_grid(point)) and (levels.is_empty() or levels.has(level)):
				return true
	if _cross_level_plan.has(id):
		for segment_v in (_cross_level_plan[id] as Array):
			var segment := segment_v as Dictionary
			var level := int(segment.get("level", -1))
			if not levels.is_empty() and not levels.has(level):
				continue
			for cell_v in (segment.get("cells", []) as Array):
				if cell_v is Vector2i and cells.has(cell_v as Vector2i):
					return true
	return false


## Remaining data-space length of the currently accepted navigation route.
## Presentation uses this derived readback for a truthful progress cue on curved
## and multi-segment paths; it never mutates or replans the command.
func get_navigation_route_remaining_distance(id: String) -> float:
	if not characters.has(id):
		return -1.0
	var remaining := _active_navigation_phase_remaining_distance(id)
	if not _cross_level_plan.has(id) or grid == null:
		return remaining
	var segments_v: Variant = _cross_level_plan.get(id, null)
	if not (segments_v is Array):
		return -1.0
	var segments := segments_v as Array
	for segment_index in range(segments.size()):
		var segment_v: Variant = segments[segment_index]
		if not (segment_v is Dictionary):
			return -1.0
		var segment := segment_v as Dictionary
		# The current ordinary movement already contains the whole started leg.
		if segment_index == 0 and bool(segment.get("started", false)):
			continue
		var entry_edge := segment.get("entry_edge", {}) as Dictionary
		var active_entry := segment_index == 0 \
			and not bool(segment.get("started", false)) \
			and bool(segment.get("entry_traversed", false)) \
			and is_external_traversal_active(id)
		if not entry_edge.is_empty() \
				and not bool(segment.get("entry_traversed", false)):
			remaining += _navigation_edge_data_distance(entry_edge)
		elif not entry_edge.is_empty() and segment_index > 0:
			remaining += _navigation_edge_data_distance(entry_edge)
		# An active typed edge is already included above; its destination is the
		# first cell of this planar leg, so only subsequent cell-to-cell travel
		# remains. The same is true for a future edge.
		var cells := segment.get("cells", []) as Array
		var segment_level := int(segment.get("level", get_character_level(id)))
		for cell_index in range(1, cells.size()):
			if not (cells[cell_index - 1] is Vector2i) \
					or not (cells[cell_index] is Vector2i):
				return -1.0
			remaining += grid.grid_to_world(
				cells[cell_index - 1] as Vector2i, segment_level).distance_to(
				grid.grid_to_world(cells[cell_index] as Vector2i, segment_level))
		if segment_index == 0 and entry_edge.is_empty() and not active_entry \
				and not bool(segment.get("started", false)) and not cells.is_empty() \
				and cells[0] is Vector2i:
			remaining += get_position(id).distance_to(
				grid.grid_to_world(cells[0] as Vector2i, segment_level))
	return maxf(0.0, remaining)


## Read-only presentation fact for an explicit timed zero-distance segment in
## the current navigation plan. Cooperative pathfinding represents yielding as
## duplicate waypoints with increasing arrival ticks; exposing only the finite
## remaining duration lets the HUD explain a stationary party member without
## leaking path cells or becoming movement authority.
func get_navigation_wait_state(id: String) -> Dictionary:
	if not characters.has(id) or scheduler == null \
			or is_external_traversal_active(id):
		return {}
	var movement_v: Variant = characters[id].get("movement", null)
	if not (movement_v is Dictionary):
		return {}
	var movement := movement_v as Dictionary
	var path := movement.get("path", []) as Array
	var ticks := movement.get("arrival_ticks", []) as Array
	if path.size() < 2 or ticks.size() != path.size():
		return {}
	var now := float(scheduler.get_current_tick())
	for point_index in range(1, ticks.size()):
		var segment_start := float(ticks[point_index - 1])
		var segment_end := float(ticks[point_index])
		if now < segment_start - 0.000001:
			break
		if now > segment_end + 0.000001:
			continue
		var from_v: Variant = path[point_index - 1]
		var to_v: Variant = path[point_index]
		if not (from_v is Vector3) or not (to_v is Vector3) \
				or (from_v as Vector3).distance_to(to_v as Vector3) >= 0.001 \
				or segment_end - segment_start <= 0.0001:
			return {}
		var remaining := maxf(0.0, segment_end - now)
		if remaining <= 0.0001:
			return {}
		return {
			"contract": "navigation_wait_state/v1",
			"active": true,
			"kind": "cooperative_hold",
			"reason": "Waiting for party route clearance",
			"remaining_seconds": remaining,
			"total_seconds": segment_end - segment_start,
		}
	return {}


func _active_navigation_phase_remaining_distance(id: String) -> float:
	if is_external_traversal_active(id):
		var state := get_external_traversal_state(id)
		var path := state.get("data_path", []) as Array
		var total := 0.0
		for point_index in range(1, path.size()):
			if path[point_index - 1] is Vector3 and path[point_index] is Vector3:
				total += (path[point_index - 1] as Vector3).distance_to(
					path[point_index] as Vector3)
		return total * (1.0 - clampf(float(state.get("progress", 0.0)), 0.0, 1.0))
	var movement_v: Variant = characters[id].get("movement", null)
	if not (movement_v is Dictionary):
		return 0.0
	var movement := movement_v as Dictionary
	var path := movement.get("path", []) as Array
	var ticks := movement.get("arrival_ticks", []) as Array
	if path.size() < 2 or ticks.size() != path.size() or scheduler == null:
		return maxf(0.0, get_position(id).distance_to(get_destination(id)))
	var now := float(scheduler.get_current_tick())
	var first_future := -1
	for point_index in range(1, ticks.size()):
		if float(ticks[point_index]) > now + 0.000001:
			first_future = point_index
			break
	if first_future < 0:
		return 0.0
	var remaining := get_position(id).distance_to(path[first_future] as Vector3)
	for point_index in range(first_future + 1, path.size()):
		remaining += (path[point_index - 1] as Vector3).distance_to(
			path[point_index] as Vector3)
	return maxf(0.0, remaining)


func _navigation_edge_data_distance(edge: Dictionary) -> float:
	if grid == null:
		return 0.0
	var from_cell_v: Variant = edge.get("from_cell", null)
	var to_cell_v: Variant = edge.get("to_cell", null)
	if not (from_cell_v is Vector2i) or not (to_cell_v is Vector2i):
		return 0.0
	var from_level := int(edge.get("from_level", 0))
	var to_level := int(edge.get("to_level", from_level))
	return grid.grid_to_world(from_cell_v as Vector2i, from_level).distance_to(
		grid.grid_to_world(to_cell_v as Vector2i, to_level))

## The final waypoint of the character's current (or queued) move, in DATA space; Vector3.INF when the
## character isn't moving. The path/marker renderers read this to mark where a move ENDS for ANY character
## (not just whoever was clicked) — derived state, written nowhere.
func get_destination(id: String) -> Vector3:
	if not characters.has(id):
		return Vector3.INF
	if _external_traversals.has(id):
		return _external_traversals[id].get("data_destination", Vector3.INF)
	var mv = characters[id].movement
	if mv == null:
		return Vector3.INF
	var path: Array = mv.get("path", [])
	if path.is_empty():
		return Vector3.INF
	return path[path.size() - 1]

# --- Stats ---

## Read a stat (hp/stamina/atp/...). Returns 0.0 if unknown character or stat.
func get_stat(id: String, stat: String) -> float:
	if not characters.has(id):
		return 0.0
	return float(characters[id].stats.get(stat, 0.0))

## Per-character cap for hp/stamina/atp.
func get_stat_cap(id: String, stat: String) -> float:
	if not characters.has(id):
		return 0.0
	var stats: Dictionary = characters[id].stats
	var cap_key := stat + "_max"
	if stats.has(cap_key):
		return float(stats[cap_key])
	match stat:
		"hp": return HP_MAX
		"stamina":
			# Rest deprivation (no sleep last night) cuts the stamina ceiling until they sleep.
			return STAMINA_MAX * (REST_DEPRIVED_STAMINA_FACTOR if _rest_deprived.has(id) else 1.0)
		"atp": return ATP_MAX_PIPS
	return 0.0

## Set a stat and clamp hp/stamina/atp to their caps. Optional source metadata is
## diagnostic provenance only; replay remains driven by the resulting absolute value.
func set_stat(id: String, stat: String, value: float, source := "") -> void:
	var payload := {"id": id, "stat": stat, "value": value}
	if source != "":
		payload["source"] = source
	_emit(GameEvent.KIND_SET_STAT, payload)
	if not characters.has(id):
		return
	var clamped: float = value
	match stat:
		"stamina":
			clamped = clampf(value, 0.0, get_stat_cap(id, "stamina"))
		"hp":
			clamped = clampf(value, 0.0, get_stat_cap(id, "hp"))
		"atp":
			clamped = clampf(quantize_atp(value), 0.0, get_stat_cap(id, "atp"))
	characters[id].stats[stat] = clamped
	stat_changed.emit(id, stat, clamped)
	# Combat damage that zeroes hp IS a down (GDD 2.4.3: a knockout, not death) — the same transition
	# as a scripted down_character. Derived from the logged hp change itself (no extra log entry), so
	# replaying the damage re-derives the down identically.
	if stat == "hp" and clamped <= 0.0 and not is_downed(id) and not bool(characters[id].stats.get("dead", false)):
		_mark_downed(id)

## Apply or refresh a finite damage shield. Duration follows the gameplay scheduler, so pause,
## fast-forward, replay, and headless tests all observe the same window.
func apply_damage_shield(
		char_id: String,
		amount: float,
		duration: float,
		source_id := ""
	) -> bool:
	if not characters.has(char_id) or amount <= 0.0 or duration <= 0.0 or scheduler == null:
		return false
	clear_damage_shield(char_id)
	var tag := "damage_shield_" + char_id
	var cid := char_id
	var handle := scheduler.schedule_after(duration, func(): clear_damage_shield(cid), tag)
	_damage_shields[char_id] = {
		"amount": amount,
		"source_id": source_id,
		"handle": handle,
		"expires_tick": scheduler.get_current_tick() + duration,
	}
	damage_shield_changed.emit(char_id, amount, source_id)
	return true

func clear_damage_shield(char_id: String) -> void:
	if not _damage_shields.has(char_id):
		return
	var shield: Dictionary = _damage_shields[char_id]
	_damage_shields.erase(char_id)
	if scheduler:
		var handle := int(shield.get("handle", 0))
		if handle != 0:
			scheduler.cancel(handle)
	damage_shield_changed.emit(char_id, 0.0, str(shield.get("source_id", "")))

func get_damage_shield(char_id: String) -> float:
	return float((_damage_shields.get(char_id, {}) as Dictionary).get("amount", 0.0))

func _resolve_incoming_damage(char_id: String, incoming: float) -> float:
	if incoming <= 0.0 or not _damage_shields.has(char_id):
		return incoming
	var shield: Dictionary = _damage_shields[char_id]
	var available := float(shield.get("amount", 0.0))
	var absorbed := minf(available, incoming)
	var remaining := maxf(0.0, available - absorbed)
	var source_id := str(shield.get("source_id", ""))
	if remaining <= 0.0:
		clear_damage_shield(char_id)
	else:
		shield["amount"] = remaining
		_damage_shields[char_id] = shield
		damage_shield_changed.emit(char_id, remaining, source_id)
	damage_absorbed.emit(char_id, absorbed, remaining, source_id)
	return incoming - absorbed

## Shorthand for relative stat changes (damage, drain, healing). Negative HP changes pass through
## the shared shield resolver; source metadata keeps the cause diagnosable in the event log.
func adjust_stat(
		id: String,
		stat: String,
		delta: float,
		source := ""
	) -> void:
	var resolved_delta := delta
	if stat == "hp" and delta < 0.0:
		resolved_delta = -_resolve_incoming_damage(id, -delta)
	set_stat(id, stat, get_stat(id, stat) + resolved_delta, source)

## Apply a stat_upgrade payload. Capacity upgrades also refill the stat.
func _apply_stat_upgrade(char_id: String, payload: Dictionary) -> void:
	if not characters.has(char_id):
		return
	var stat: String = str(payload.get("stat", ""))
	var amount: float = float(payload.get("amount", 0.0))
	if stat == "" or amount == 0.0:
		return
	var stats: Dictionary = characters[char_id].stats
	if stat in ["hp_max", "stamina_max", "atp_max"]:
		# Upgrade from the current cap, including defaults.
		var current_stat := stat.substr(0, stat.find("_max"))
		var new_cap: float = get_stat_cap(char_id, current_stat) + amount
		stats[stat] = new_cap
		stat_changed.emit(char_id, stat, new_cap)
		set_stat(char_id, current_stat, new_cap)
	else:
		var new_value: float = float(stats.get(stat, 0.0)) + amount
		stats[stat] = new_value
		stat_changed.emit(char_id, stat, new_value)

# --- Running ---

func is_running(id: String) -> bool:
	return _running.has(id)

## Global safe(cautious)/direct routing mode (the Tab toggle). Cautious routing detours around risky
## cells and refuses non-recoverable ones; direct ignores risk. It changes which paths the planners
## produce, so it is a LOGGED command — replay restores it in order and recomputes identical routes.
func set_route_mode(cautious: bool) -> void:
	_emit(GameEvent.KIND_SET_ROUTE_MODE, {"cautious": cautious})
	route_cautious = cautious

func is_route_cautious() -> bool:
	return route_cautious

## Enter or leave running state.
func set_running(id: String, running: bool) -> void:
	_emit(GameEvent.KIND_SET_RUNNING, {"id": id, "running": running})
	if not characters.has(id):
		return
	if running and is_external_traversal_active(id):
		return
	if running and (is_endocytosing(id) or is_dodging(id) or is_knocked_down(id) \
			or is_downed(id) or is_field_restoring(id) or is_resting(id)):
		return
	if running == is_running(id):
		return
	if running:
		if get_stat(id, "stamina") <= 0.0:
			return
		# Dead weight cannot sprint: both hands are full of friend (canon: slower + heavier while
		# dragging). The haul pace IS the pace.
		if is_dragging(id):
			return
		_running[id] = {"tick_handle": 0, "next_tick": 0.0}
		change_move_speed(id, RUN_SPEED)
		# A mid-move speed rebuild enters _start_movement(), which already arms the drain from the
		# new movement epoch. Do not add a second callback for the same runner.
		if int(_running[id].get("tick_handle", 0)) == 0:
			_schedule_running_tick(id)
	else:
		var entry: Dictionary = _running.get(id, {})
		var handle: int = int(entry.get("tick_handle", 0))
		if handle != 0 and scheduler:
			scheduler.cancel(handle)
		_running.erase(id)
		change_move_speed(id, WALK_SPEED)
	running_changed.emit(id, running)

func toggle_running(id: String) -> void:
	set_running(id, not is_running(id))

func _schedule_running_tick(id: String, delay: float = RUN_TICK_INTERVAL) -> void:
	if not is_running(id) or not scheduler:
		return
	# One authoritative cadence per runner. This defensive guard also prevents two callers in the
	# same command boundary from silently doubling the stamina economy.
	if int(_running[id].get("tick_handle", 0)) != 0:
		return
	delay = maxf(0.000001, delay)
	var handle := scheduler.schedule_after(
		delay,
		func(): _on_running_tick(id),
		"running_" + id
	)
	_running[id]["tick_handle"] = handle
	_running[id]["next_tick"] = scheduler.get_current_tick() + delay

func _on_running_tick(id: String) -> void:
	if not is_running(id) or not characters.has(id):
		return
	# The scheduler consumed this handle before invoking us. Clear it first so the next cadence can
	# be armed exactly once, including when a stat listener synchronously changes movement.
	_running[id]["tick_handle"] = 0
	_running[id]["next_tick"] = 0.0
	if not is_moving(id):
		# Pause stamina ticks while idle.
		return
	var new_val: float = maxf(0.0, get_stat(id, "stamina") - run_stamina_drain_per_sec * RUN_TICK_INTERVAL)
	set_stat(id, "stamina", new_val)
	if new_val <= 0.0:
		set_running(id, false)
		return
	_schedule_running_tick(id)

## Restore all registered characters to full stats and clear running flags.
func reset_characters_to_full() -> void:
	for id in characters.keys():
		clear_damage_shield(id)
		if is_running(id):
			set_running(id, false)
		set_stat(id, "hp", get_stat_cap(id, "hp"))
		set_stat(id, "stamina", get_stat_cap(id, "stamina"))
		set_stat(id, "atp", get_stat_cap(id, "atp"))

func get_grid_cell(id: String) -> Vector2i:
	if not grid:
		return Vector2i.ZERO
	return grid.world_to_grid(get_position(id))

# --- Serialization ---

## Same-process hash for tests. Use serialize() for cross-process checks.
func state_hash() -> int:
	return serialize().hash()

## Complete authoritative snapshot for save/load. Every committed gameplay phase is restored with
## its remaining scheduler time; presentation and prediction queues are rebuilt from this state.
func serialize() -> Dictionary:
	var char_data := {}
	for id in characters:
		var pos := get_position(id)
		var ch: Dictionary = characters[id]
		char_data[id] = {
			"position": [pos.x, pos.y, pos.z],
			"grid_cell": [ch.grid_cell.x, ch.grid_cell.y],
			"level": int(ch.get("level", 0)),
			"move_speed": ch.move_speed,
			"stats": ch.stats.duplicate(),
			"hands": (ch.get("hands", [null, null]) as Array).duplicate(true),
			"internal": (ch.get("internal", []) as Array).duplicate(true),
		}
	var coop_exempt_ids := _coop_exempt.keys()
	coop_exempt_ids.sort()
	return {
		"characters": char_data,
		"character_movements": _serialize_character_movements(),
		"cross_level_plans": _serialize_cross_level_plans(),
		"explored": _serialize_explored(),
		"route_cautious": route_cautious,
		"world_state": world_state.duplicate(true),
		"rng_registry": rng_registry.serialize(),
		"items": _serialize_items(),
		"next_item_id": _next_item_id,
		"collection": collection.duplicate(),
		"interactables": _serialize_interactables(),
		"physics_objects": _serialize_physics_objects(),
		"pendulums": _serialize_pendulums(),
		"flora": _serialize_flora(),
		"flora_seq": _flora_seq,
		"party": party.duplicate(),
		"split_members": _split_members.duplicate(),
		"coop_exempt": coop_exempt_ids,
		"clock_state": _serialize_clock_state(),
		"endocytosing": _serialize_endocytosing(),
		"dodging": _serialize_dodging(),
		"knocked_down": _serialize_knocked_down(),
		"running": _serialize_running(),
		"resting": _serialize_resting(),
		"revive_state": _serialize_revive_state(),
		"field_restores": _serialize_field_restores(),
		"queued_canonical_abilities": _serialize_queued_canonical_abilities(),
		"drags": _serialize_drags(),
		"push_plans": _serialize_push_plans(),
		"damage_shields": _serialize_damage_shields(),
		"external_traversals": _serialize_external_traversals(),
		"timed_mechanism_phases": _serialize_timed_mechanism_phases(),
	}

func deserialize(data: Dictionary) -> void:
	# A loaded snapshot replaces every scheduler-owned phase represented below. Scene construction may already
	# have registered the same characters and armed callbacks; cancel/clear those derived records before rearming
	# from saved remaining durations. This method deliberately emits no gameplay commands while restoring.
	_clear_snapshot_runtime_phases()
	if data.has("characters"):
		# A snapshot replaces the roster; it is not a patch over whichever actors the current scene
		# happened to spawn before loading.  Keeping a later-spawned enemy here lets a player save before
		# a wave, trigger it, then load and retain the extra body (and sometimes its collision/detection)
		# even though every callback that created the wave was rolled back.
		var saved_character_ids := {}
		for saved_id_v in (data["characters"] as Dictionary).keys():
			saved_character_ids[str(saved_id_v)] = true
		for current_id_v in characters.keys():
			var current_id := str(current_id_v)
			if saved_character_ids.has(current_id):
				continue
			characters.erase(current_id)
			explored.erase(current_id)
			_coop_exempt.erase(current_id)
			_rest_deprived.erase(current_id)
		for id in data.characters:
			var cd: Dictionary = data.characters[id]
			var position_data: Array = cd.get("position", [0.0, 0.0, 0.0])
			var pos := Vector3(
				float(position_data[0]), float(position_data[1]), float(position_data[2])
			)
			var existing: Dictionary = characters.get(str(id), {})
			var hands: Array = (cd.get(
				"hands", existing.get("hands", [null, null])
			) as Array).duplicate(true)
			while hands.size() < 2:
				hands.append(null)
			characters[str(id)] = {
				"position": pos,
				"grid_cell": grid.world_to_grid(pos) if grid != null else Vector2i.ZERO,
				"level": int(cd.get("level", _level_for_y(pos.y))),
				"move_speed": float(cd.get("move_speed", existing.get("move_speed", 3.0))),
				"stats": (cd.get("stats", existing.get("stats", {})) as Dictionary).duplicate(true),
				"movement": null,
				"hands": hands,
				"internal": (cd.get(
					"internal", existing.get("internal", [])
				) as Array).duplicate(true),
			}
			if not explored.has(str(id)):
				explored[str(id)] = {}
			if grid != null:
				_reserve_parked(str(id), grid.world_to_grid(pos))
	if data.has("explored"):
		_deserialize_explored(data.explored)
	if data.has("route_cautious"):
		route_cautious = bool(data["route_cautious"])
	if data.has("world_state"):
		world_state = (data["world_state"] as Dictionary).duplicate(true)
	if data.has("rng_registry"):
		rng_registry.deserialize(data["rng_registry"] as Dictionary)
		base_seed = rng_registry.base_seed
		if event_log != null:
			event_log.base_seed = base_seed
	if data.has("items"):
		_restore_items(data["items"] as Dictionary)
		_next_item_id = maxi(1, int(data.get("next_item_id", 1)))
		collection.clear()
		for item_id_v in (data.get("collection", []) as Array):
			collection.append(str(item_id_v))
	if data.has("interactables"):
		_restore_interactables(data["interactables"] as Dictionary)
	if data.has("physics_objects"):
		_restore_physics_objects(data["physics_objects"] as Dictionary)
	if data.has("pendulums"):
		_restore_pendulums(data["pendulums"] as Dictionary)
	if data.has("flora"):
		_restore_flora(data["flora"] as Dictionary)
		_flora_seq = maxi(0, int(data.get("flora_seq", 0)))
	if data.has("party"):
		party.clear()
		for member_v in (data["party"] as Array):
			party.append(str(member_v))
	if data.has("split_members"):
		_split_members.clear()
		for member_v in (data["split_members"] as Array):
			_split_members.append(str(member_v))
	if data.has("coop_exempt"):
		_coop_exempt.clear()
		for member_v in (data["coop_exempt"] as Array):
			_coop_exempt[str(member_v)] = true
	if data.has("clock_state"):
		_restore_clock_state(data["clock_state"] as Dictionary)
	if data.has("cross_level_plans"):
		_restore_cross_level_plans(data["cross_level_plans"] as Dictionary)
	if data.has("push_plans"):
		_restore_push_plans(data["push_plans"] as Dictionary)
	if data.has("drags"):
		_restore_drags(data["drags"] as Dictionary)
	if data.has("dodging"):
		_restore_dodging(data["dodging"] as Dictionary)
	if data.has("character_movements"):
		_restore_character_movements(data["character_movements"] as Dictionary)
	if data.has("knocked_down"):
		_restore_knocked_down(data["knocked_down"] as Dictionary)
	if data.has("endocytosing"):
		_restore_endocytosing(data["endocytosing"] as Dictionary)
	if data.has("resting"):
		_restore_resting(data["resting"] as Dictionary)
	if data.has("revive_state"):
		_restore_revive_state(data["revive_state"] as Dictionary)
	if data.has("field_restores"):
		_restore_field_restores(data["field_restores"] as Dictionary)
	if data.has("queued_canonical_abilities"):
		_restore_queued_canonical_abilities(
			data["queued_canonical_abilities"] as Dictionary)
	if data.has("running"):
		_restore_running(data["running"] as Dictionary)
	if data.has("damage_shields"):
		_restore_damage_shields(data["damage_shields"] as Dictionary)
	if data.has("external_traversals"):
		_restore_external_traversals(data["external_traversals"] as Dictionary)
	if data.has("timed_mechanism_phases"):
		_restore_timed_mechanism_phases(data["timed_mechanism_phases"] as Dictionary)
	_recompute_all_detection_predictions()
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()
	evaluate_mechanisms()
	snapshot_restored.emit(data.duplicate(true))


func _clear_snapshot_runtime_phases() -> void:
	# The scheduler itself is cleared by the owning save loader before its clock is restored. Cancelling here is
	# still useful for direct GameState.deserialize callers and harmless after that clear.
	for state_v in _external_traversals.values():
		var state := state_v as Dictionary
		var handle := int(state.get("handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_external_traversals.clear()
	for state_v in _timed_mechanism_phases.values():
		var state := state_v as Dictionary
		var handle := int(state.get("handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_timed_mechanism_phases.clear()
	for state_v in _damage_shields.values():
		var state := state_v as Dictionary
		var handle := int(state.get("handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_damage_shields.clear()
	for state_v in _endocytosing.values():
		var state := state_v as Dictionary
		var handle := int(state.get("handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_endocytosing.clear()
	for state_v in _dodging.values():
		var state := state_v as Dictionary
		var handle := int(state.get("handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_dodging.clear()
	for state_v in _knocked_down.values():
		var state := state_v as Dictionary
		var handle := int(state.get("handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_knocked_down.clear()
	for state_v in _running.values():
		var state := state_v as Dictionary
		var handle := int(state.get("tick_handle", 0))
		if scheduler != null and handle != 0:
			scheduler.cancel(handle)
	_running.clear()
	for char_id_v in _queued_abilities.keys():
		if scheduler != null:
			scheduler.cancel_tag("ability_range_" + str(char_id_v))
	_queued_abilities.clear()
	_cross_level_plan.clear()
	_push_plans.clear()
	if character_arrived.is_connected(_on_push_char_arrived):
		character_arrived.disconnect(_on_push_char_arrived)
	if scheduler != null:
		for char_id_v in _resting.keys():
			scheduler.cancel_tag("rest_" + str(char_id_v))
		for caster_id_v in _field_restores.keys():
			scheduler.cancel_tag("field_restore_" + str(caster_id_v))
		scheduler.cancel_tag("shelter_revive_watch")
		scheduler.cancel_tag("game_clock_poll")
		for dragger_id_v in _drags.keys():
			scheduler.cancel_tag("drag_" + str(dragger_id_v))
	_resting.clear()
	_field_restores.clear()
	_revive_progress.clear()
	_revive_watch_running = false
	_revive_next_tick = 0.0
	_clock_next_poll_tick = 0.0
	_drags.clear()
	_drag_prev_speed.clear()
	_drag_next_tick.clear()
	_reservations.clear()
	for obj_id_v in physics_objects.keys():
		var obj: Dictionary = physics_objects[obj_id_v]
		if obj.get("movement", null) != null and scheduler != null:
			var movement: Dictionary = obj["movement"]
			var handle := int(movement.get("handle", 0))
			if handle != 0:
				scheduler.cancel(handle)
		if grid != null:
			grid.remove_dynamic_blocker(obj.get("grid_cell", Vector2i.ZERO))
		obj["movement"] = null
		obj["throw"] = null
	for id_v in characters.keys():
		var id := str(id_v)
		if characters[id].get("movement", null) != null:
			_cancel_movement(id)


func _serialize_character_movements() -> Dictionary:
	var result := {}
	if scheduler == null:
		return result
	var now := float(scheduler.get_current_tick())
	for id_v in characters.keys():
		var id := str(id_v)
		if _external_traversals.has(id) or _dodging.has(id):
			continue
		var movement_v: Variant = characters[id].get("movement", null)
		if movement_v == null:
			continue
		var movement := movement_v as Dictionary
		var path := movement.get("path", []) as Array
		if path.size() < 2:
			continue
		var absolute_ticks := movement.get("arrival_ticks", []) as Array
		if absolute_ticks.size() != path.size():
			absolute_ticks = []
			var start_tick := float(movement.get("start_tick", now))
			var duration := maxf(0.0, float(movement.get("duration", 0.0)))
			var cum_dist := movement.get("cum_dist", []) as Array
			var total_distance := maxf(0.0001, float(movement.get("total_distance", 0.0)))
			for i in range(path.size()):
				var dist := float(cum_dist[i]) if i < cum_dist.size() else 0.0
				absolute_ticks.append(start_tick + duration * dist / total_distance)
		var remaining_path: Array = [GameEvent.v3_to_arr(get_position(id))]
		var relative_ticks: Array = [0.0]
		for i in range(1, path.size()):
			var arrival := float(absolute_ticks[i])
			if arrival <= now + 0.000001:
				continue
			remaining_path.append(GameEvent.v3_to_arr(path[i] as Vector3))
			relative_ticks.append(arrival - now)
		if remaining_path.size() >= 2:
			var serialized_movement := {
				"path": remaining_path,
				"relative_arrival_ticks": relative_ticks,
			}
			var route_cell_constraint_v: Variant = movement.get("route_cell_constraint", {})
			if route_cell_constraint_v is Dictionary \
					and not (route_cell_constraint_v as Dictionary).is_empty():
				serialized_movement["route_cell_constraint"] = \
					(route_cell_constraint_v as Dictionary).duplicate(true)
			result[id] = serialized_movement
	return result


func _restore_character_movements(saved: Dictionary) -> void:
	if scheduler == null:
		return
	var now := float(scheduler.get_current_tick())
	for id_v in saved.keys():
		var id := str(id_v)
		if not characters.has(id) or _external_traversals.has(id) or _dodging.has(id) \
				or _knocked_down.has(id) or _endocytosing.has(id):
			continue
		var state := saved[id_v] as Dictionary
		var encoded_path := state.get("path", []) as Array
		var relative := state.get("relative_arrival_ticks", []) as Array
		if encoded_path.size() < 2 or relative.size() != encoded_path.size():
			continue
		var path: Array[Vector3] = []
		var ticks: Array[float] = []
		for point_v in encoded_path:
			path.append(GameEvent.arr_to_v3(point_v))
		for relative_v in relative:
			ticks.append(now + maxf(0.0, float(relative_v)))
		var route_cell_constraint_v: Variant = state.get("route_cell_constraint", {})
		if not route_cell_constraint_v is Dictionary:
			continue
		var route_cell_constraint := route_cell_constraint_v as Dictionary
		if not route_cell_constraint.is_empty():
			var canonical := _normalize_rally_route_cell_constraint(route_cell_constraint)
			if canonical.is_empty() \
					or not _rally_route_constraint_is_canonical_wire(
						route_cell_constraint, canonical):
				continue
			route_cell_constraint = canonical
			if not _world_path_obeys_route_cell_constraint(path, canonical):
				continue
		characters[id]["position"] = path[0]
		_start_movement(id, path, ticks, route_cell_constraint)


func _serialize_cross_level_plans() -> Dictionary:
	var result := {}
	for id_v in _cross_level_plan.keys():
		var encoded_segments: Array = []
		for segment_v in (_cross_level_plan[id_v] as Array):
			var segment := segment_v as Dictionary
			var cells: Array = []
			for cell_v in (segment.get("cells", []) as Array):
				cells.append(GameEvent.v2i_to_arr(cell_v as Vector2i))
			encoded_segments.append({
				"level": int(segment.get("level", 0)),
				"cells": cells,
				"entry_edge": _serialize_navigation_edge(
					segment.get("entry_edge", {}) as Dictionary),
				"entry_traversed": bool(segment.get("entry_traversed", false)),
				"started": bool(segment.get("started", false)),
			})
		result[str(id_v)] = encoded_segments
	return result


func _serialize_navigation_edge(edge: Dictionary) -> Dictionary:
	if edge.is_empty():
		return {}
	var out := edge.duplicate(true)
	if out.get("from_cell", null) is Vector2i:
		out["from_cell"] = GameEvent.v2i_to_arr(out["from_cell"] as Vector2i)
	if out.get("to_cell", null) is Vector2i:
		out["to_cell"] = GameEvent.v2i_to_arr(out["to_cell"] as Vector2i)
	return out


func _restore_navigation_edge(encoded: Dictionary) -> Dictionary:
	if encoded.is_empty():
		return {}
	var out := encoded.duplicate(true)
	if out.get("from_cell", null) is Array:
		out["from_cell"] = GameEvent.arr_to_v2i(out["from_cell"] as Array)
	if out.get("to_cell", null) is Array:
		out["to_cell"] = GameEvent.arr_to_v2i(out["to_cell"] as Array)
	return out


func _restore_cross_level_plans(saved: Dictionary) -> void:
	_cross_level_plan.clear()
	for id_v in saved.keys():
		var id := str(id_v)
		if not characters.has(id):
			continue
		var segments: Array = []
		var segment_index := 0
		for segment_v in (saved[id_v] as Array):
			var encoded := segment_v as Dictionary
			var cells: Array[Vector2i] = []
			for cell_v in (encoded.get("cells", []) as Array):
				cells.append(GameEvent.arr_to_v2i(cell_v))
			# Legacy snapshots predate typed edge phases. Their first saved segment was necessarily
			# already walking; preserve that one useful execution fact rather than restarting it.
			var has_phase_flags := encoded.has("started")
			segments.append({
				"level": int(encoded.get("level", 0)),
				"cells": cells,
				"entry_edge": _restore_navigation_edge(
					encoded.get("entry_edge", {}) as Dictionary),
				"entry_traversed": bool(encoded.get("entry_traversed", true)),
				"started": bool(encoded.get("started", segment_index == 0)) \
					if has_phase_flags else segment_index == 0,
			})
			segment_index += 1
		if not segments.is_empty():
			_cross_level_plan[id] = segments
	if not _cross_level_plan.is_empty() and not character_arrived.is_connected(_on_cross_level_arrival):
		character_arrived.connect(_on_cross_level_arrival)


func _serialize_push_plans() -> Dictionary:
	var result := {}
	for id_v in _push_plans.keys():
		var plan := _push_plans[id_v] as Dictionary
		var encoded_steps: Array = []
		for step_v in (plan.get("steps", []) as Array):
			var step := step_v as Dictionary
			encoded_steps.append({
				"obj_from": GameEvent.v2i_to_arr(step.get("obj_from", Vector2i.ZERO)),
				"obj_to": GameEvent.v2i_to_arr(step.get("obj_to", Vector2i.ZERO)),
				"char_push_cell": GameEvent.v2i_to_arr(
					step.get("char_push_cell", Vector2i.ZERO)),
			})
		result[str(id_v)] = {
			"obj_id": str(plan.get("obj_id", "")),
			"steps": encoded_steps,
			"index": int(plan.get("index", 0)),
			"stage": str(plan.get("stage", "approach")),
		}
	return result


func _restore_push_plans(saved: Dictionary) -> void:
	_push_plans.clear()
	for id_v in saved.keys():
		var id := str(id_v)
		var encoded := saved[id_v] as Dictionary
		var obj_id := str(encoded.get("obj_id", ""))
		if not characters.has(id) or not physics_objects.has(obj_id):
			continue
		var steps: Array = []
		for step_v in (encoded.get("steps", []) as Array):
			var step := step_v as Dictionary
			steps.append({
				"obj_from": GameEvent.arr_to_v2i(step.get("obj_from", [0, 0])),
				"obj_to": GameEvent.arr_to_v2i(step.get("obj_to", [0, 0])),
				"char_push_cell": GameEvent.arr_to_v2i(
					step.get("char_push_cell", [0, 0])),
			})
		if steps.is_empty():
			continue
		_push_plans[id] = {
			"obj_id": obj_id,
			"steps": steps,
			"index": clampi(int(encoded.get("index", 0)), 0, steps.size()),
			"stage": str(encoded.get("stage", "approach")),
		}
	if not _push_plans.is_empty() and not character_arrived.is_connected(_on_push_char_arrived):
		character_arrived.connect(_on_push_char_arrived)


func _serialize_items() -> Dictionary:
	var result := {}
	for item_id_v in items.keys():
		var item_id := str(item_id_v)
		var item := items[item_id_v] as Dictionary
		result[item_id] = {
			"type": str(item.get("type", "")),
			"holder": str(item.get("holder", "")),
			"location": str(item.get("location", "ground")),
			"position": GameEvent.v3_to_arr(item.get("position", Vector3.ZERO)),
			"properties": (item.get("properties", {}) as Dictionary).duplicate(true),
		}
	return result


func _restore_items(saved: Dictionary) -> void:
	items.clear()
	for item_id_v in saved.keys():
		var item_id := str(item_id_v)
		var encoded := saved[item_id_v] as Dictionary
		items[item_id] = {
			"type": str(encoded.get("type", "")),
			"holder": str(encoded.get("holder", "")),
			"location": str(encoded.get("location", "ground")),
			"position": GameEvent.arr_to_v3(encoded.get("position", [0.0, 0.0, 0.0])),
			"properties": (encoded.get("properties", {}) as Dictionary).duplicate(true),
		}


func _serialize_interactables() -> Dictionary:
	var result := {}
	for interactable_id_v in interactables.keys():
		var interactable_id := str(interactable_id_v)
		var spec := interactables[interactable_id_v] as Dictionary
		var encoded := spec.duplicate(true)
		encoded["position"] = GameEvent.v3_to_arr(spec.get("position", Vector3.ZERO))
		result[interactable_id] = encoded
	return result


func _restore_interactables(saved: Dictionary) -> void:
	interactables.clear()
	for interactable_id_v in saved.keys():
		var interactable_id := str(interactable_id_v)
		var encoded := (saved[interactable_id_v] as Dictionary).duplicate(true)
		encoded["id"] = interactable_id
		var spec := _normalize_interactable_spec(encoded)
		spec["triggered"] = bool(encoded.get("triggered", false))
		spec["enabled"] = bool(encoded.get("enabled", true))
		# Legacy saves have only the ever-triggered bit; seed their monotonic identity at one so the
		# next repeat receipt still expects a distinct acceptance.
		spec["trigger_count"] = maxi(0, int(encoded.get(
			"trigger_count", 1 if bool(spec["triggered"]) else 0)))
		spec["last_trigger_character"] = String(encoded.get("last_trigger_character", ""))
		interactables[interactable_id] = spec


func _serialize_flora() -> Dictionary:
	var result := {}
	for flora_id_v in flora.keys():
		var flora_id := str(flora_id_v)
		var growth := (flora[flora_id_v] as Dictionary).duplicate(true)
		growth["position"] = GameEvent.v3_to_arr(growth.get("position", Vector3.ZERO))
		result[flora_id] = growth
	return result


func _restore_flora(saved: Dictionary) -> void:
	flora.clear()
	for flora_id_v in saved.keys():
		var flora_id := str(flora_id_v)
		var growth := (saved[flora_id_v] as Dictionary).duplicate(true)
		growth["position"] = GameEvent.arr_to_v3(
			growth.get("position", [0.0, 0.0, 0.0]))
		flora[flora_id] = growth


func _serialize_pendulums() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for pendulum_id_v in pendulums.keys():
		var pendulum_id := str(pendulum_id_v)
		var pendulum := pendulums[pendulum_id_v] as Dictionary
		result[pendulum_id] = {
			"anchor": GameEvent.v3_to_arr(pendulum.get("anchor", Vector3.ZERO)),
			"length": float(pendulum.get("length", 1.0)),
			"amplitude": float(pendulum.get("amplitude", 0.0)),
			"phase": float(pendulum.get("phase", 0.0)),
			"swing_axis": GameEvent.v3_to_arr(
				pendulum.get("swing_axis", Vector3.FORWARD)),
			"bob_radius": float(pendulum.get("bob_radius", 0.4)),
			"damping": float(pendulum.get("damping", 0.0)),
			"elapsed": maxf(0.0, now - float(pendulum.get("start_tick", now))),
		}
	return result


func _restore_pendulums(saved: Dictionary) -> void:
	pendulums.clear()
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for pendulum_id_v in saved.keys():
		var pendulum_id := str(pendulum_id_v)
		var encoded := saved[pendulum_id_v] as Dictionary
		pendulums[pendulum_id] = {
			"anchor": GameEvent.arr_to_v3(encoded.get("anchor", [0.0, 0.0, 0.0])),
			"length": float(encoded.get("length", 1.0)),
			"amplitude": float(encoded.get("amplitude", 0.0)),
			"phase": float(encoded.get("phase", 0.0)),
			"swing_axis": GameEvent.arr_to_v3(
				encoded.get("swing_axis", [0.0, 0.0, 1.0])).normalized(),
			"bob_radius": float(encoded.get("bob_radius", 0.4)),
			"damping": float(encoded.get("damping", 0.0)),
			"start_tick": now - maxf(0.0, float(encoded.get("elapsed", 0.0))),
		}


func _serialize_physics_objects() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for obj_id_v in physics_objects.keys():
		var obj_id := str(obj_id_v)
		var obj := physics_objects[obj_id_v] as Dictionary
		var encoded := {
			"position": GameEvent.v3_to_arr(get_physics_position(obj_id)),
			"radius": float(obj.get("radius", 0.5)),
			"mass": float(obj.get("mass", 2.0)),
			"friction": float(obj.get("friction", 0.6)),
			"pushable": bool(obj.get("pushable", true)),
		}
		if obj.has("signature"):
			encoded["signature"] = str(obj.get("signature", "physics_object"))
		var movement_v: Variant = obj.get("movement", null)
		if movement_v != null:
			var movement := movement_v as Dictionary
			var remaining := maxf(0.0,
				float(movement.get("start_tick", now))
				+ float(movement.get("duration", 0.0)) - now)
			var path := movement.get("path", []) as Array
			if remaining > 0.0 and not path.is_empty():
				var movement_state := {
					"destination": GameEvent.v3_to_arr(path[path.size() - 1] as Vector3),
					"remaining": remaining,
					"kind": "throw" if obj.get("throw", null) != null else "slide",
				}
				if obj.get("throw", null) != null:
					var throw_state := obj["throw"] as Dictionary
					var elapsed := now - float(throw_state.get("start_tick", now))
					movement_state["vertical_velocity"] = \
						float(throw_state.get("vy", 0.0)) - PENDULUM_GRAVITY * elapsed
					movement_state["ground_y"] = float(throw_state.get("ground_y", 0.0))
				encoded["movement"] = movement_state
		result[obj_id] = encoded
	return result


func _restore_physics_objects(saved: Dictionary) -> void:
	physics_objects.clear()
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for obj_id_v in saved.keys():
		var obj_id := str(obj_id_v)
		var encoded := saved[obj_id_v] as Dictionary
		var current := GameEvent.arr_to_v3(encoded.get("position", [0.0, 0.0, 0.0]))
		var obj := {
			"position": current,
			"radius": float(encoded.get("radius", 0.5)),
			"mass": float(encoded.get("mass", 2.0)),
			"friction": float(encoded.get("friction", 0.6)),
			"movement": null,
			"throw": null,
			"grid_cell": grid.world_to_grid(current) if grid != null else Vector2i.ZERO,
			"pushable": bool(encoded.get("pushable", true)),
		}
		if encoded.has("signature"):
			obj["signature"] = StringName(str(encoded.get("signature", "physics_object")))
		physics_objects[obj_id] = obj
		var movement_state := encoded.get("movement", {}) as Dictionary
		var remaining := maxf(0.0, float(movement_state.get("remaining", 0.0)))
		if scheduler != null and remaining > 0.0:
			var destination := GameEvent.arr_to_v3(movement_state.get(
				"destination", GameEvent.v3_to_arr(current)))
			var kind := str(movement_state.get("kind", "slide"))
			var path_start := current
			if kind == "throw":
				var ground_y := float(movement_state.get("ground_y", 0.0))
				path_start.y = ground_y
				destination.y = ground_y
				obj["throw"] = {
					"start_tick": now,
					"start_y": current.y,
					"vy": float(movement_state.get("vertical_velocity", 0.0)),
					"ground_y": ground_y,
					"landing_tick": now + remaining,
				}
			var path: Array[Vector3] = [path_start, destination]
			var cum_dist := _compute_cum_dist(path)
			var handle := scheduler.schedule_at(
				now + remaining,
				_restore_physics_completion.bind(obj_id, kind),
				("throw_" if kind == "throw" else "physics_move_") + obj_id)
			obj["movement"] = {
				"path": path,
				"cum_dist": cum_dist,
				"total_distance": maxf(0.001, float(cum_dist[cum_dist.size() - 1])),
				"start_tick": now,
				"duration": remaining,
				"handle": handle,
			}
		elif grid != null and not bool(obj.get("pushable", true)):
			grid.add_dynamic_blocker(obj["grid_cell"], obj_id)


func _restore_physics_completion(obj_id: String, kind: String) -> void:
	if kind == "throw":
		_on_throw_landing(obj_id)
	else:
		_on_physics_arrival(obj_id)


func _serialize_endocytosing() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for char_id_v in _endocytosing.keys():
		var state := _endocytosing[char_id_v] as Dictionary
		result[str(char_id_v)] = {
			"item_id": str(state.get("item_id", "")),
			"remaining": maxf(0.0, float(state.get("end_tick", now)) - now),
		}
	return result


func _restore_endocytosing(saved: Dictionary) -> void:
	if scheduler == null:
		return
	var now := float(scheduler.get_current_tick())
	for char_id_v in saved.keys():
		var char_id := str(char_id_v)
		var state := saved[char_id_v] as Dictionary
		var item_id := str(state.get("item_id", ""))
		var remaining := maxf(0.0, float(state.get("remaining", 0.0)))
		if not characters.has(char_id) or not items.has(item_id):
			continue
		if remaining <= 0.0:
			_complete_endocytosis(char_id, item_id)
			continue
		var handle := scheduler.schedule_at(
			now + remaining,
			_complete_endocytosis.bind(char_id, item_id),
			"endocytose_" + char_id)
		_endocytosing[char_id] = {
			"item_id": item_id,
			"end_tick": now + remaining,
			"handle": handle,
		}


func _serialize_dodging() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for char_id_v in _dodging.keys():
		var char_id := str(char_id_v)
		if not characters.has(char_id):
			continue
		var movement_v: Variant = characters[char_id].get("movement", null)
		if movement_v == null:
			continue
		var movement := movement_v as Dictionary
		var path := movement.get("path", []) as Array
		if path.is_empty():
			continue
		var state := _dodging[char_id_v] as Dictionary
		result[char_id] = {
			"position": GameEvent.v3_to_arr(get_position(char_id)),
			"destination": GameEvent.v3_to_arr(path[path.size() - 1] as Vector3),
			"remaining": maxf(0.0, float(state.get("end_tick", now)) - now),
		}
	return result


func _restore_dodging(saved: Dictionary) -> void:
	if scheduler == null:
		return
	var now := float(scheduler.get_current_tick())
	for char_id_v in saved.keys():
		var char_id := str(char_id_v)
		if not characters.has(char_id):
			continue
		var state := saved[char_id_v] as Dictionary
		var from := GameEvent.arr_to_v3(state.get("position", [0.0, 0.0, 0.0]))
		var destination := GameEvent.arr_to_v3(state.get(
			"destination", GameEvent.v3_to_arr(from)))
		var remaining := maxf(0.0, float(state.get("remaining", 0.0)))
		characters[char_id]["position"] = from
		if remaining <= 0.0:
			characters[char_id]["position"] = destination
			continue
		var path: Array[Vector3] = [from, destination]
		var ticks: Array[float] = [now, now + remaining]
		var handle := scheduler.schedule_at(
			now + remaining, _on_dodge_end.bind(char_id), "dodge_" + char_id)
		characters[char_id]["movement"] = {
			"path": path,
			"cum_dist": _compute_cum_dist(path),
			"arrival_ticks": ticks,
			"total_distance": maxf(0.001, from.distance_to(destination)),
			"start_tick": now,
			"duration": remaining,
			"handle": handle,
		}
		_reserve_path(char_id, path, ticks)
		_dodging[char_id] = {"end_tick": now + remaining, "handle": handle}


func _serialize_knocked_down() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for char_id_v in _knocked_down.keys():
		var state := _knocked_down[char_id_v] as Dictionary
		result[str(char_id_v)] = {
			"remaining": maxf(0.0, float(state.get("end_tick", now)) - now),
		}
	return result


func _restore_knocked_down(saved: Dictionary) -> void:
	if scheduler == null:
		return
	var now := float(scheduler.get_current_tick())
	for char_id_v in saved.keys():
		var char_id := str(char_id_v)
		if not characters.has(char_id):
			continue
		var remaining := maxf(0.0, float(
			(saved[char_id_v] as Dictionary).get("remaining", 0.0)))
		if remaining <= 0.0:
			continue
		var handle := scheduler.schedule_at(
			now + remaining, _on_knockdown_end.bind(char_id), "knockdown_" + char_id)
		_knocked_down[char_id] = {"end_tick": now + remaining, "handle": handle}


func _serialize_running() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for char_id_v in _running.keys():
		var state := _running[char_id_v] as Dictionary
		var next_tick := float(state.get("next_tick", 0.0))
		result[str(char_id_v)] = {
			"remaining_to_tick": maxf(0.0, next_tick - now) if next_tick > 0.0 else 0.0,
		}
	return result


func _restore_running(saved: Dictionary) -> void:
	if scheduler == null:
		return
	for char_id_v in saved.keys():
		var char_id := str(char_id_v)
		if not characters.has(char_id) or is_dragging(char_id) or is_dodging(char_id) \
				or is_external_traversal_active(char_id):
			continue
		_running[char_id] = {"tick_handle": 0, "next_tick": 0.0}
		characters[char_id]["move_speed"] = RUN_SPEED
		if is_moving(char_id):
			var remaining := float(
				(saved[char_id_v] as Dictionary).get("remaining_to_tick", RUN_TICK_INTERVAL))
			_schedule_running_tick(char_id, remaining if remaining > 0.0 else RUN_TICK_INTERVAL)


func _serialize_resting() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for char_id_v in _resting.keys():
		var state := _resting[char_id_v] as Dictionary
		result[str(char_id_v)] = {
			"pip_seconds": float(state.get("pip_seconds", REST_SECONDS_PER_PIP)),
			"remaining_to_tick": maxf(0.0, float(state.get("next_tick", now)) - now),
			"night_skip_on_tick": bool(state.get("night_skip_on_tick", false)),
		}
	return result


func _restore_resting(saved: Dictionary) -> void:
	if scheduler == null:
		return
	for char_id_v in saved.keys():
		var char_id := str(char_id_v)
		if not characters.has(char_id):
			continue
		var encoded := saved[char_id_v] as Dictionary
		_resting[char_id] = {
			"pip_seconds": float(encoded.get("pip_seconds", REST_SECONDS_PER_PIP)),
			"next_tick": 0.0,
			"night_skip_on_tick": bool(encoded.get("night_skip_on_tick", false)),
		}
		var remaining := float(encoded.get("remaining_to_tick", 1.0))
		_schedule_rest_tick(char_id, remaining if remaining > 0.0 else 1.0)


func _serialize_field_restores() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for caster_id_v in _field_restores.keys():
		var state := _field_restores[caster_id_v] as Dictionary
		result[str(caster_id_v)] = {
			"target_id": str(state.get("target_id", "")),
			"remaining": maxf(0.0, float(state.get("end_tick", now)) - now),
		}
	return result


func _restore_field_restores(saved: Dictionary) -> void:
	if scheduler == null:
		return
	var now := float(scheduler.get_current_tick())
	for caster_id_v in saved.keys():
		var caster_id := str(caster_id_v)
		var encoded := saved[caster_id_v] as Dictionary
		var target_id := str(encoded.get("target_id", ""))
		var remaining := maxf(0.0, float(encoded.get("remaining", 0.0)))
		if not characters.has(caster_id) or not characters.has(target_id) or remaining <= 0.0:
			continue
		_field_restores[caster_id] = {
			"target_id": target_id,
			"end_tick": now + remaining,
		}
		scheduler.schedule_at(
			now + remaining,
			_on_field_restore_complete.bind(caster_id),
			"field_restore_" + caster_id)


func _serialize_queued_canonical_abilities() -> Dictionary:
	var result := {}
	for char_id_v in _queued_abilities.keys():
		var state := _queued_abilities[char_id_v] as Dictionary
		var canonical := state.get("canonical", {}) as Dictionary
		if canonical.is_empty():
			continue
		result[str(char_id_v)] = {
			"ability": str(state.get("ability", "")),
			"target_pos": GameEvent.v3_to_arr(state.get("target_pos", Vector3.ZERO)),
			"range": float(state.get("range", 0.0)),
			"canonical": canonical.duplicate(true),
		}
	return result


func _restore_queued_canonical_abilities(saved: Dictionary) -> void:
	for char_id_v in saved.keys():
		var char_id := str(char_id_v)
		if not characters.has(char_id):
			continue
		var encoded := saved[char_id_v] as Dictionary
		var canonical := encoded.get("canonical", {}) as Dictionary
		if canonical.is_empty():
			continue
		_queued_abilities[char_id] = {
			"ability": str(encoded.get("ability", "")),
			"target_pos": GameEvent.arr_to_v3(
				encoded.get("target_pos", [0.0, 0.0, 0.0])),
			"range": float(encoded.get("range", 0.0)),
			"callback": Callable(),
			"canonical": canonical.duplicate(true),
			"world_root": null,
		}
		_schedule_ability_in_range(char_id)


func _serialize_drags() -> Dictionary:
	var result := {}
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	for dragger_id_v in _drags.keys():
		var dragger_id := str(dragger_id_v)
		var next_tick := float(_drag_next_tick.get(dragger_id, 0.0))
		result[dragger_id] = {
			"downed_id": str(_drags[dragger_id_v]),
			"previous_speed": float(_drag_prev_speed.get(dragger_id, WALK_SPEED)),
			"remaining_to_tick": maxf(0.0, next_tick - now) if next_tick > 0.0 else DRAG_TICK,
		}
	return result


func _restore_drags(saved: Dictionary) -> void:
	if scheduler == null:
		return
	for dragger_id_v in saved.keys():
		var dragger_id := str(dragger_id_v)
		var encoded := saved[dragger_id_v] as Dictionary
		var downed_id := str(encoded.get("downed_id", ""))
		if not characters.has(dragger_id) or not characters.has(downed_id):
			continue
		_drags[dragger_id] = downed_id
		_drag_prev_speed[dragger_id] = float(encoded.get("previous_speed", WALK_SPEED))
		var remaining := float(encoded.get("remaining_to_tick", DRAG_TICK))
		_arm_drag_tick(dragger_id, remaining if remaining > 0.0 else DRAG_TICK)


func _serialize_revive_state() -> Dictionary:
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	return {
		"progress": _revive_progress.duplicate(true),
		"watch_running": _revive_watch_running,
		"remaining_to_tick": maxf(0.0, _revive_next_tick - now) \
			if _revive_watch_running and _revive_next_tick > 0.0 else 0.0,
	}


func _restore_revive_state(saved: Dictionary) -> void:
	_revive_progress = (saved.get("progress", {}) as Dictionary).duplicate(true)
	_revive_watch_running = bool(saved.get("watch_running", false))
	if not _revive_watch_running or scheduler == null:
		_revive_next_tick = 0.0
		return
	var remaining := float(saved.get("remaining_to_tick", 1.0))
	_schedule_revive_watch_tick(remaining if remaining > 0.0 else 1.0)


func _serialize_clock_state() -> Dictionary:
	var now := float(scheduler.get_current_tick()) if scheduler != null else 0.0
	var deprived: Array = []
	for char_id_v in _rest_deprived.keys():
		deprived.append(str(char_id_v))
	deprived.sort()
	return {
		"day": get_game_day(),
		"time": get_time_of_day(),
		"day_length_seconds": day_length_seconds,
		"last_polled_day": _last_polled_day,
		"rest_deprived": deprived,
		"remaining_to_poll": maxf(0.0, _clock_next_poll_tick - now) \
			if day_length_seconds > 0.0 and _clock_next_poll_tick > 0.0 else 0.0,
	}


func _restore_clock_state(saved: Dictionary) -> void:
	game_day = maxi(1, int(saved.get("day", 1)))
	game_time = clampf(float(saved.get("time", 0.25)), 0.0, 1.0)
	day_length_seconds = maxf(0.0, float(saved.get("day_length_seconds", 0.0)))
	_clock_base_tick = float(scheduler.get_current_tick()) if scheduler != null else 0.0
	_last_polled_day = int(saved.get("last_polled_day", game_day))
	_rest_deprived.clear()
	for char_id_v in (saved.get("rest_deprived", []) as Array):
		var char_id := str(char_id_v)
		if characters.has(char_id):
			_rest_deprived[char_id] = true
	if scheduler != null and day_length_seconds > 0.0:
		var remaining := float(saved.get("remaining_to_poll", 0.5))
		_schedule_clock_poll(remaining if remaining > 0.0 else 0.5)


func _serialize_external_traversals() -> Dictionary:
	var result := {}
	for id_variant in _external_traversals.keys():
		var id := str(id_variant)
		var state: Dictionary = _external_traversals[id_variant]
		var readback := get_external_traversal_state(id)
		var data_path: Array = state.get("data_path", [])
		var render_path: Array = state.get("render_path", [])
		result[id] = {
			"traversal_id": state.get("traversal_id", &""),
			# A save resumes from where the rider actually is, never from the original mouth.
			"data_origin": GameEvent.v3_to_arr(readback.get("data_position", Vector3.ZERO)),
			"data_destination": GameEvent.v3_to_arr(state.get("data_destination", Vector3.ZERO)),
			"render_origin": GameEvent.v3_to_arr(readback.get("render_position", Vector3.ZERO)),
			"render_destination": GameEvent.v3_to_arr(state.get("render_destination", Vector3.ZERO)),
			"data_path": _external_path_to_payload(data_path),
			"render_path": _external_path_to_payload(render_path),
			"progress_start": float(readback.get("progress", 0.0)),
			"remaining": float(readback.get("remaining", 0.0)),
			"interrupt_policy": state.get("interrupt_policy", &"locked"),
			"preserve_cross_level_plan": bool(
				state.get("preserve_cross_level_plan", false)),
			"navigation_edge": _serialize_navigation_edge(
				state.get("navigation_edge", {}) as Dictionary),
			"presentation_receipt": (state.get(
				"presentation_receipt", {}) as Dictionary).duplicate(true),
			"original_start_tick": float(state.get("start_tick", 0.0)),
			"original_end_tick": float(state.get("end_tick", 0.0)),
		}
	return result


func _restore_external_traversals(saved: Dictionary) -> void:
	if scheduler == null:
		return
	for id_variant in saved.keys():
		var id := str(id_variant)
		if not characters.has(id):
			continue
		var state: Dictionary = saved[id_variant]
		var remaining := float(state.get("remaining", 0.0))
		var destination := GameEvent.arr_to_v3(state.get(
			"data_destination", GameEvent.v3_to_arr(get_position(id))))
		if remaining <= 0.0:
			characters[id]["position"] = destination
			continue
		var now := float(scheduler.get_current_tick())
		var payload := {
			"id": id,
			"traversal_id": state.get("traversal_id", &""),
			"data_origin": state.get("data_origin", GameEvent.v3_to_arr(get_position(id))),
			"data_destination": state.get("data_destination", GameEvent.v3_to_arr(destination)),
			"render_origin": state.get("render_origin", GameEvent.v3_to_arr(get_render_position(id))),
			"render_destination": state.get("render_destination", GameEvent.v3_to_arr(destination)),
			"data_path": state.get("data_path", []),
			"render_path": state.get("render_path", []),
			"start_tick": now,
			"end_tick": now + remaining,
			"progress_start": float(state.get("progress_start", 0.0)),
			"interrupt_policy": state.get("interrupt_policy", &"locked"),
			"preserve_cross_level_plan": bool(
				state.get("preserve_cross_level_plan", false)),
			"navigation_edge": _restore_navigation_edge(
				state.get("navigation_edge", {}) as Dictionary),
			"presentation_receipt": (state.get(
				"presentation_receipt", {}) as Dictionary).duplicate(true),
		}
		_apply_external_traversal(payload)


func _serialize_timed_mechanism_phases() -> Dictionary:
	var result := {}
	var ids := _timed_mechanism_phases.keys()
	ids.sort()
	for id_variant in ids:
		var mechanism_id := StringName(str(id_variant))
		var state: Dictionary = _timed_mechanism_phases[id_variant]
		var readback := get_mechanism_phase_state(mechanism_id)
		result[String(mechanism_id)] = {
			"phase": state.get("phase", &""),
			"completion_phase": state.get("completion_phase", &""),
			"progress": float(readback.get("progress", 0.0)),
			"remaining": float(readback.get("remaining", 0.0)),
			"metadata": (state.get("metadata", {}) as Dictionary).duplicate(true),
			"original_start_tick": float(state.get("start_tick", 0.0)),
			"original_end_tick": float(state.get("end_tick", 0.0)),
		}
	return result


func _restore_timed_mechanism_phases(saved: Dictionary) -> void:
	if scheduler == null:
		return
	var ids := saved.keys()
	ids.sort()
	for id_variant in ids:
		var mechanism_id := StringName(str(id_variant))
		if String(mechanism_id).is_empty() or _timed_mechanism_phases.has(mechanism_id):
			continue
		var saved_state: Dictionary = saved[id_variant]
		var phase := StringName(str(saved_state.get("phase", "")))
		var completion_phase := StringName(str(saved_state.get("completion_phase", "")))
		if String(phase).is_empty() or String(completion_phase).is_empty():
			continue
		var now := float(scheduler.get_current_tick())
		var remaining := maxf(0.0, float(saved_state.get("remaining", 0.0)))
		var progress := clampf(float(saved_state.get("progress", 0.0)), 0.0, 1.0)
		var metadata := (saved_state.get("metadata", {}) as Dictionary).duplicate(true)
		if phase == completion_phase or progress >= 1.0 or remaining <= 0.0:
			_timed_mechanism_phases[mechanism_id] = {
				"mechanism_id": mechanism_id,
				"phase": completion_phase,
				"completion_phase": completion_phase,
				"start_tick": now,
				"end_tick": now,
				"progress_start": 1.0,
				"metadata": metadata,
				"handle": 0,
			}
			continue
		_apply_begin_mechanism_phase({
			"mechanism_id": mechanism_id,
			"phase": phase,
			"completion_phase": completion_phase,
			"start_tick": now,
			"end_tick": now + remaining,
			"progress_start": progress,
			"metadata": metadata,
		})

func _serialize_damage_shields() -> Dictionary:
	var result := {}
	var now := scheduler.get_current_tick() if scheduler != null else 0.0
	for id_variant in _damage_shields.keys():
		var char_id := str(id_variant)
		var shield: Dictionary = _damage_shields[id_variant]
		var remaining := maxf(0.0, float(shield.get("expires_tick", now)) - now)
		var amount := float(shield.get("amount", 0.0))
		if amount <= 0.0 or remaining <= 0.0:
			continue
		result[char_id] = {
			"amount": amount,
			"source_id": str(shield.get("source_id", "")),
			"remaining": remaining,
		}
	return result

func _restore_damage_shields(serialized: Dictionary) -> void:
	for id_variant in _damage_shields.keys():
		clear_damage_shield(str(id_variant))
	if scheduler == null:
		return
	for id_variant in serialized.keys():
		var char_id := str(id_variant)
		if not characters.has(char_id):
			continue
		var shield: Dictionary = serialized[id_variant]
		apply_damage_shield(
			char_id,
			float(shield.get("amount", 0.0)),
			float(shield.get("remaining", 0.0)),
			str(shield.get("source_id", "")))

# --- Internal ---

## Begin interpolated movement along full_path. If arrival_ticks is supplied
## (one absolute tick per waypoint, monotonic, arrival_ticks[0] == now), the
## character follows that exact timing — letting cooperative paths embed waits.
## Otherwise timing is uniform constant-speed, identical to the prior behavior.
func _start_movement(
		id: String,
		full_path: Array[Vector3],
		arrival_ticks: Array[float] = [],
		route_cell_constraint: Dictionary = {}
	) -> void:
	var ch: Dictionary = characters[id]
	var cum_dist := _compute_cum_dist(full_path)
	var total_dist: float = cum_dist[cum_dist.size() - 1]
	if total_dist < 0.01:
		ch.position = full_path[full_path.size() - 1]
		if grid:
			ch.grid_cell = grid.world_to_grid(ch.position)
		_clear_reservations(id)
		_reserve_parked(id, ch.grid_cell)
		character_arrived.emit(id)
		_recompute_all_detection_predictions(id)
		_recompute_physics_predictions()
		return
	var speed: float = ch.move_speed
	var start_tick := scheduler.get_current_tick()
	var ticks: Array[float] = arrival_ticks
	if ticks.size() != full_path.size():
		ticks = []
		for d in cum_dist:
			ticks.append(start_tick + d / speed)
	var final_tick: float = ticks[ticks.size() - 1]
	var duration := final_tick - start_tick
	var movement_epoch := _next_movement_epoch
	_next_movement_epoch += 1
	var handle := scheduler.schedule_at(
		final_tick,
		_on_arrival.bind(id, movement_epoch),
		"movement_" + id
	)
	ch.movement = {
		"path": full_path,
		"cum_dist": cum_dist,
		"arrival_ticks": ticks,
		"total_distance": total_dist,
		"start_tick": start_tick,
		"duration": duration,
		"handle": handle,
		"epoch": movement_epoch,
	}
	if not route_cell_constraint.is_empty():
		ch.movement["route_cell_constraint"] = route_cell_constraint.duplicate(true)
	_reserve_path(id, full_path, ticks)
	movement_started.emit(id)
	# Resume stamina drain on movement.
	# that the character is in motion again.
	if is_running(id) and int(_running[id].get("tick_handle", 0)) == 0:
		_schedule_running_tick(id)
	_recompute_all_detection_predictions(id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func _cancel_movement(id: String) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	var cancelled := ch.movement != null
	if ch.movement != null:
		if scheduler:
			scheduler.cancel(ch.movement.handle)
		ch.movement = null
	if cancelled:
		movement_cancelled.emit(id)
	_clear_reservations(id)
	_recompute_all_detection_predictions(id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func _on_arrival(id: String, movement_epoch: int) -> void:
	if not characters.has(id):
		return
	var ch: Dictionary = characters[id]
	if ch.movement == null \
			or int((ch.movement as Dictionary).get("epoch", -1)) != movement_epoch:
		return
	var dest: Vector3 = ch.movement.path[ch.movement.path.size() - 1]
	ch.position = dest
	if grid:
		ch.grid_cell = grid.world_to_grid(dest)
	ch.movement = null
	_reserve_parked(id, ch.grid_cell)
	character_arrived.emit(id)

static func _compute_cum_dist(path: Array[Vector3]) -> Array[float]:
	var result: Array[float] = [0.0]
	for i in range(1, path.size()):
		result.append(result[result.size() - 1] + path[i - 1].distance_to(path[i]))
	return result

static func _interpolate_path(path: Array[Vector3], cum_dist: Array[float], t: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	if path.size() == 1 or t <= 0.0:
		return path[0]
	if t >= 1.0:
		return path[path.size() - 1]
	var total := cum_dist[cum_dist.size() - 1]
	var target_dist := t * total
	for i in range(1, cum_dist.size()):
		if cum_dist[i] >= target_dist:
			var seg_start := cum_dist[i - 1]
			var seg_len := cum_dist[i] - seg_start
			if seg_len < 0.001:
				return path[i]
			var seg_t := (target_dist - seg_start) / seg_len
			return path[i - 1].lerp(path[i], seg_t)
	return path[path.size() - 1]

## Interpolate along a path with explicit per-waypoint arrival ticks. Unlike the
## constant-speed variant, this honors uneven segment timing — including a
## "wait" segment where two consecutive waypoints share a position but span time,
## which holds the character in place. Cooperative paths use this to pause and let
## another character pass.
static func _interpolate_path_timed(path: Array[Vector3], arrival_ticks: Array, tick: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var n := path.size()
	if n == 1 or tick <= arrival_ticks[0]:
		return path[0]
	if tick >= arrival_ticks[n - 1]:
		return path[n - 1]
	for i in range(1, n):
		if arrival_ticks[i] >= tick:
			var span: float = arrival_ticks[i] - arrival_ticks[i - 1]
			if span <= 0.0001:
				return path[i]
			var seg_t: float = (tick - arrival_ticks[i - 1]) / span
			return path[i - 1].lerp(path[i], seg_t)
	return path[n - 1]

# --- Cooperative pathfinding (space-time reservations) ---
#
# Each character claims every cell it transits for a padded time window. The
# window for cell k spans from when the character leaves cell k-1 until it
# reaches cell k+1 — a 3-cell sliding claim, so a head-on swap (A: X→Y while
# B: Y→X at the same time) shows up as overlapping claims on BOTH shared cells
# and is rejected by a single vertex check. The space-time A* plans paths that
# avoid every reserved (cell, time) window, inserting waits when needed.
# Reservations are derived from movement and scheduler ticks, so they replay
# identically and behave the same under fast-forward.

## Slack ticks padded around each reserved window so characters keep a little
## space and never graze at a shared boundary.
const _RESERVE_BUFFER := 0.18
## A parked character holds its cell effectively forever; others route around it.
const _PARK_HORIZON := 1.0e12
## Search bounds for the cooperative planner. Generous so legitimate solutions
## that need a long wait (e.g. letting a slow character clear a corridor) are
## found, keeping the overlap-prone plain-A* fallback a true last resort.
const _COOP_MAX_NODES := 12000
## The PREVIEW (dim hover ribbon, recomputed per hovered cell) caps its cooperative search far lower: a
## hard/far target that would expand toward the full budget is "seconds" of per-node work (string keys +
## reservation checks) EVERY hover, which froze the game. A reachable near target is found well under this;
## anything past it falls back to plain find_path (cheap), so the preview is bounded per hover. The COMMIT
## (a one-time click) still uses the full budget, so an actual move can still take the long cooperative route.
const _COOP_PREVIEW_MAX_NODES := 1500
## Extra wait/detour slack (in cell-times) the planner may spend beyond the
## straight-line estimate before giving up.
const _COOP_WAIT_SLACK_CELLS := 48.0
## Rally/group commands mean "leave together". A later member may cheaply wait
## at its start for an earlier member's route reservation to clear, but only for
## a short, legible beat. Longer or permanent conflicts still use cooperative A*.
const _GROUP_START_WAIT_MAX_SECONDS := 1.5
const _GROUP_START_WAIT_ATTEMPTS := 12

func _clear_reservations(id: String) -> void:
	# exempt characters never write reservations — nothing to scan for (the erase is a full-table
	# walk, paid on EVERY move command; a chase pack re-commanding at rescan cadence made it hot)
	if _coop_exempt.has(id):
		return
	if _reservations.is_empty():
		return
	var empty_cells: Array = []
	for cell in _reservations:
		var slots: Array = _reservations[cell]
		var kept: Array = []
		for s in slots:
			if s.id != id:
				kept.append(s)
		if kept.is_empty():
			empty_cells.append(cell)
		else:
			_reservations[cell] = kept
	for cell in empty_cells:
		_reservations.erase(cell)

func _add_reservation(cell: Vector2i, t0: float, t1: float, id: String) -> void:
	if _coop_exempt.has(id):
		return
	if not _reservations.has(cell):
		_reservations[cell] = []
	_reservations[cell].append({"t0": t0, "t1": t1, "id": id})

## Reserve a stationary character's cell from now to the horizon.
func _reserve_parked(id: String, cell: Vector2i) -> void:
	if not scheduler:
		return
	_clear_reservations(id)
	_add_reservation(cell, scheduler.get_current_tick() - _RESERVE_BUFFER, _PARK_HORIZON, id)

## Reserve every cell a path transits with its 3-cell sliding time window. The
## final (destination) cell is held to the horizon since the character parks there.
func _reserve_path(id: String, world_path: Array[Vector3], arrival_ticks: Array) -> void:
	if not grid:
		return
	_clear_reservations(id)
	var n := world_path.size()
	for k in range(n):
		var cell := grid.world_to_grid(world_path[k])
		var lo := maxi(0, k - 1)
		var hi := mini(n - 1, k + 1)
		var t0: float = float(arrival_ticks[lo]) - _RESERVE_BUFFER
		var t1: float
		if k == n - 1:
			t1 = _PARK_HORIZON
		else:
			t1 = float(arrival_ticks[hi]) + _RESERVE_BUFFER
		_add_reservation(cell, t0, t1, id)

## True if any character other than exclude_id has cell reserved during [t0, t1].
func _cell_reserved(cell: Vector2i, t0: float, t1: float, exclude_id: String) -> bool:
	if not _reservations.has(cell):
		return false
	for s in _reservations[cell]:
		if s.id == exclude_id:
			continue
		if t0 <= s.t1 and s.t0 <= t1:
			return true
	return false

func _coop_h(cell: Vector2i, end: Vector2i, card: float) -> float:
	var dx := absf(cell.x - end.x)
	var dz := absf(cell.y - end.y)
	return (maxf(dx, dz) + 0.4142136 * minf(dx, dz)) * card

func _coop_key(cell: Vector2i, t: float, t_start: float, tq: float) -> Vector3i:
	return Vector3i(cell.x, cell.y, int(round((t - t_start) / tq)))

## Turn the cheap 2D path into a timed cooperative plan and report whether it
## intersects another character's reservation. Most player commands are
## uncontested; accepting that route directly avoids a reachability flood plus
## a second, allocation-heavy space-time search. A real conflict still falls
## through to the full cooperative A* below, preserving waits and detours.
func _time_spatial_path(
		start: Vector2i,
		world_path: Array[Vector3],
		speed: float,
		t_start: float,
		exclude_id: String
) -> Dictionary:
	var cells: Array[Vector2i] = [start]
	var ticks: Array[float] = [t_start]
	var previous := start
	var arrival := t_start
	for world_point in world_path:
		var cell := grid.world_to_grid(world_point)
		if cell == previous:
			continue
		var diagonal := cell.x != previous.x and cell.y != previous.y
		var distance := grid.cell_size * (1.4142136 if diagonal else 1.0)
		var dt := distance / speed if speed > 0.0 else 1.0
		var next_arrival := arrival + dt
		if _cell_reserved(cell, arrival - _RESERVE_BUFFER,
				next_arrival + _RESERVE_BUFFER, exclude_id):
			return {"conflict": true, "cells": cells, "ticks": ticks}
		cells.append(cell)
		ticks.append(next_arrival)
		previous = cell
		arrival = next_arrival
	return {"conflict": false, "cells": cells, "ticks": ticks}

## Rally-scoped fast path for a convoy conflict. Keep the ordinary spatial route
## and try a tightly bounded wait at the member's current cell before paying for
## the allocation-heavy space-time search. The duplicated start cell makes the
## wait explicit in arrival_ticks, so prediction, replay, and path reservations
## all observe the same deterministic timing.
func _try_group_start_wait_spatial_path(
		start: Vector2i,
		world_path: Array[Vector3],
		speed: float,
		t_start: float,
		exclude_id: String
	) -> Dictionary:
	var card := (grid.cell_size / speed) if speed > 0.0 else 1.0
	var wait_step := minf(_GROUP_START_WAIT_MAX_SECONDS, maxf(card * 0.5,
		_GROUP_START_WAIT_MAX_SECONDS / float(_GROUP_START_WAIT_ATTEMPTS)))
	for attempt in range(1, _GROUP_START_WAIT_ATTEMPTS + 1):
		var wait_seconds := minf(
			wait_step * float(attempt), _GROUP_START_WAIT_MAX_SECONDS)
		# A wait is itself occupancy. The earlier-planned member may cross this
		# member's start cell, in which case blindly delaying only the onward
		# route would manufacture an overlap the full space-time planner avoids.
		if _cell_reserved(start, t_start - _RESERVE_BUFFER,
				t_start + wait_seconds + _RESERVE_BUFFER, exclude_id):
			if wait_seconds >= _GROUP_START_WAIT_MAX_SECONDS:
				break
			continue
		var delayed := _time_spatial_path(
			start, world_path, speed, t_start + wait_seconds, exclude_id)
		if bool(delayed.get("conflict", true)):
			# minf() caps later attempts to the same value; do not repeat the
			# identical path scan after the maximum allowed wait already failed.
			if wait_seconds >= _GROUP_START_WAIT_MAX_SECONDS:
				break
			continue
		var cells: Array[Vector2i] = [start]
		for cell_variant in delayed.get("cells", []):
			var cell: Vector2i = cell_variant
			cells.append(cell)
		var ticks: Array[float] = [t_start]
		for tick_variant in delayed.get("ticks", []):
			ticks.append(float(tick_variant))
		return {"cells": cells, "ticks": ticks, "wait": wait_seconds}
	return {}

## Space-time A*: a grid-cell path from start to end whose timed transit avoids
## every reserved (cell, time) window owned by another character, inserting
## waits where needed. Returns {cells: Array[Vector2i], ticks: Array[float]}
## (absolute arrival tick per cell) or {} if no conflict-free path is found.
# Binary min-heap for the cooperative A* open set. Ordered by f, then by insertion seq so ties break
# deterministically (FIFO) — replaces the old O(n) linear min-scan, which made a large/hard search
# O(n²) (≈ seconds at the 12k-node budget) and froze the per-hover path preview.
# Cooperative heap entries are immutable records in parallel packed arrays;
# the heap itself stores only their integer ids. This preserves the exact
# f-score/insertion-sequence ordering while avoiding one Dictionary allocation
# for every candidate space-time state.
static func _coop_entry_heap_push(
		heap: PackedInt32Array,
		entry_f: PackedFloat64Array,
		entry_seq: PackedInt32Array,
		entry_id: int
	) -> void:
	heap.append(entry_id)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		var child_id := heap[i]
		var parent_id := heap[parent]
		if entry_f[child_id] > entry_f[parent_id] or (entry_f[child_id] == entry_f[parent_id] \
				and entry_seq[child_id] >= entry_seq[parent_id]):
			break
		heap[i] = parent_id
		heap[parent] = child_id
		i = parent

static func _coop_entry_heap_pop(
		heap: PackedInt32Array,
		entry_f: PackedFloat64Array,
		entry_seq: PackedInt32Array
	) -> int:
	var top_id := heap[0]
	var last_index := heap.size() - 1
	if last_index == 0:
		heap.resize(0)
		return top_id
	heap[0] = heap[last_index]
	heap.resize(last_index)
	var i := 0
	var heap_size := heap.size()
	while true:
		var smallest := i
		var left := 2 * i + 1
		var right := left + 1
		if left < heap_size:
			var left_id := heap[left]
			var smallest_id := heap[smallest]
			if entry_f[left_id] < entry_f[smallest_id] or (entry_f[left_id] == entry_f[smallest_id] \
					and entry_seq[left_id] < entry_seq[smallest_id]):
				smallest = left
		if right < heap_size:
			var right_id := heap[right]
			var smallest_id := heap[smallest]
			if entry_f[right_id] < entry_f[smallest_id] or (entry_f[right_id] == entry_f[smallest_id] \
					and entry_seq[right_id] < entry_seq[smallest_id]):
				smallest = right
		if smallest == i:
			break
		var tmp_id := heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = tmp_id
		i = smallest
	return top_id

func _plan_cooperative(
		start: Vector2i,
		end: Vector2i,
		speed: float,
		t_start: float,
		exclude_id: String,
		level: int = 0,
		max_nodes: int = _COOP_MAX_NODES,
		allow_group_start_wait := false,
		allowed_cells: Dictionary = {}
	) -> Dictionary:
	var perf_started := PerformanceTrace.begin()
	_coop_last_nodes = 0
	if _pf_debug:
		GridWorld._pf_trace("[coop A*] start %v -> %v (budget %d, for '%s')" % [start, end, max_nodes, exclude_id])
	if not grid:
		PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, "no_grid", 0)
		return {}
	if not allowed_cells.is_empty() \
			and (not allowed_cells.has(start) or not allowed_cells.has(end)):
		PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started,
			"outside_allowed_cells", 0)
		return {}
	if start == end:
		PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, exclude_id, 1)
		return {"cells": [start] as Array[Vector2i], "ticks": [t_start] as Array[float]}
	if not grid.is_in_bounds(end.x, end.y) or not grid.is_walkable(end.x, end.y, {}, {}, level):
		PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, "blocked", 0)
		return {}
	var card: float = (grid.cell_size / speed) if speed > 0.0 else 1.0
	var diag: float = card * 1.4142136
	var tq: float = maxf(card * 0.5, 0.0001)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	# A budget on total time so the planner can't wait/wander forever.
	var time_budget: float = _coop_h(start, end, card) * 3.0 + card * _COOP_WAIT_SLACK_CELLS
	# A destination reserved for the ENTIRE plan window by someone else (a PARKED character holds its
	# cell to the horizon) can never be arrived at — bail now instead of exhausting the node budget on
	# endless waits (12k space-time expansions ≈ seconds; this runs per hover frame via the preview).
	for s in _reservations.get(end, []):
		if s.id != exclude_id and float(s.t0) <= t_start and float(s.t1) >= t_start + time_budget:
			PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, "reserved", 0)
			return {}
	# First solve the ordinary 2D problem. Besides being the common fast path,
	# an empty result is the geometric-unreachability proof that the old BFS
	# computed separately. This avoids traversing reachable space twice.
	var spatial_path := grid.find_path(
		start, end, {}, route_cautious, {}, {}, level, allowed_cells)
	if spatial_path.is_empty():
		PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, "unreachable", 0)
		return {}
	var spatial_plan := _time_spatial_path(start, spatial_path, speed, t_start, exclude_id)
	if not bool(spatial_plan.get("conflict", true)):
		_performance_counters["cooperative_fast_paths"] = \
			int(_performance_counters["cooperative_fast_paths"]) + 1
		var spatial_cells := (spatial_plan.get("cells", []) as Array).size()
		PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started,
			"spatial:%s" % exclude_id, spatial_cells)
		return {"cells": spatial_plan.cells, "ticks": spatial_plan.ticks}
	if allow_group_start_wait:
		var waited_plan := _try_group_start_wait_spatial_path(
			start, spatial_path, speed, t_start, exclude_id)
		if not waited_plan.is_empty():
			_performance_counters["cooperative_wait_fast_paths"] = \
				int(_performance_counters["cooperative_wait_fast_paths"]) + 1
			var waited_cells := (waited_plan.get("cells", []) as Array).size()
			PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started,
				"wait:%s" % exclude_id, waited_cells)
			return {"cells": waited_plan.cells, "ticks": waited_plan.ticks}
	_performance_counters["cooperative_conflict_searches"] = \
		int(_performance_counters["cooperative_conflict_searches"]) + 1
	# Reuse GridWorld's derived dense predicates. Cooperative A* has no
	# query-specific locked doors, so byte/float lookups are exactly equivalent
	# to repeatedly probing tile, level-footprint, blocker and risk Dictionaries.
	var walkability_mask := grid.get_path_walkability_mask(level)
	var risk_penalties := PackedFloat64Array()
	var risk_blocked := PackedByteArray()
	var risk_potential := PackedFloat64Array()
	if route_cautious:
		var risk_masks := grid.get_path_risk_masks()
		risk_penalties = risk_masks.get("penalties", PackedFloat64Array())
		risk_blocked = risk_masks.get("blocked", PackedByteArray())
		risk_potential = grid.get_cautious_goal_risk_potential(end)
	var seq := 0
	var entry_x := PackedInt32Array([start.x])
	var entry_z := PackedInt32Array([start.y])
	var entry_t := PackedFloat64Array([t_start])
	var entry_g := PackedFloat64Array([0.0])
	var start_risk_potential := risk_potential[start.y * grid.width + start.x] * card \
		if not risk_potential.is_empty() else 0.0
	var entry_f := PackedFloat64Array([_coop_h(start, end, card) + start_risk_potential])
	var entry_seq := PackedInt32Array([seq])
	var open := PackedInt32Array([0])
	seq += 1
	var start_key := _coop_key(start, t_start, t_start, tq)
	var best_g: Dictionary = {start_key: 0.0}
	var came: Dictionary = {start_key: {"cell": start, "t": t_start, "pkey": ""}}
	var nodes := 0
	while not open.is_empty() and nodes < max_nodes:
		nodes += 1
		_coop_last_nodes = nodes
		var current_entry := _coop_entry_heap_pop(open, entry_f, entry_seq)
		var ccell := Vector2i(entry_x[current_entry], entry_z[current_entry])
		var ct: float = entry_t[current_entry]
		var cur_key := _coop_key(ccell, ct, t_start, tq)
		# A stale entry (we already reached this state cheaper) — skip.
		if entry_g[current_entry] > float(best_g.get(cur_key, INF)) + 0.0001:
			continue
		if ccell == end:
			if _pf_debug:
				GridWorld._pf_trace("[coop A*] done: reached in %d nodes" % nodes)
			var result := _coop_reconstruct(came, cur_key)
			PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, exclude_id, nodes)
			return result
		# Eight moves plus a wait-in-place.
		for di in range(dirs.size() + 1):
			var is_wait := di == dirs.size()
			var ncell: Vector2i = ccell if is_wait else ccell + dirs[di]
			var dt: float = card
			if not is_wait:
				var dir := dirs[di]
				var is_diag := dir.x != 0 and dir.y != 0
				dt = diag if is_diag else card
				if not grid.is_in_bounds(ncell.x, ncell.y):
					continue
				var ncell_index := ncell.y * grid.width + ncell.x
				if walkability_mask[ncell_index] == 0:
					continue
				if not allowed_cells.is_empty() and not allowed_cells.has(ncell):
					continue
				if is_diag:
					var adjacent_a := Vector2i(ccell.x + dir.x, ccell.y)
					var adjacent_b := Vector2i(ccell.x, ccell.y + dir.y)
					var adjacent_a_index := ccell.y * grid.width + ccell.x + dir.x
					var adjacent_b_index := (ccell.y + dir.y) * grid.width + ccell.x
					if walkability_mask[adjacent_a_index] == 0 \
							or walkability_mask[adjacent_b_index] == 0:
						continue
					if not allowed_cells.is_empty() \
							and (not allowed_cells.has(adjacent_a) \
								or not allowed_cells.has(adjacent_b)):
						continue
			# Cautious (safe) routing: never enter a non-recoverable risky cell; a recoverable one
			# costs extra so the plan detours when a detour exists. Penalty is scaled to time units
			# (g is time-shaped) via card. Direct routing ignores risk.
			if route_cautious and not is_wait:
				var risk_index := ncell.y * grid.width + ncell.x
				if risk_blocked[risk_index] != 0:
					continue
			var nt: float = ct + dt
			if _cell_reserved(ncell, ct - _RESERVE_BUFFER, nt + _RESERVE_BUFFER, exclude_id):
				continue
			var ng: float = entry_g[current_entry] + dt
			if route_cautious and not is_wait:
				ng += risk_penalties[ncell.y * grid.width + ncell.x] * card
			# Budget on ELAPSED TIME (not cost): risk penalties shape route choice but must not
			# starve the search budget.
			if nt - t_start > time_budget:
				continue
			var nkey := _coop_key(ncell, nt, t_start, tq)
			if ng < float(best_g.get(nkey, INF)) - 0.0001:
				best_g[nkey] = ng
				came[nkey] = {"cell": ncell, "t": nt, "pkey": cur_key}
				var next_entry := entry_x.size()
				entry_x.append(ncell.x)
				entry_z.append(ncell.y)
				entry_t.append(nt)
				entry_g.append(ng)
				var remaining_risk := risk_potential[ncell.y * grid.width + ncell.x] * card \
					if not risk_potential.is_empty() else 0.0
				entry_f.append(ng + _coop_h(ncell, end, card) + remaining_risk)
				entry_seq.append(seq)
				_coop_entry_heap_push(open, entry_f, entry_seq, next_entry)
				seq += 1
	if _pf_debug:
		GridWorld._pf_trace("[coop A*] done: EXHAUSTED %d nodes (budget %d) — no conflict-free path, falling back" % [nodes, max_nodes])
	PerformanceTrace.end(&"nav", &"game_state.plan_cooperative", perf_started, "exhausted", nodes)
	return {}

func _coop_reconstruct(came: Dictionary, key: Variant) -> Dictionary:
	var cells: Array[Vector2i] = []
	var ticks: Array[float] = []
	var k: Variant = key
	while came.has(k):
		var node: Dictionary = came[k]
		cells.push_front(node.cell)
		ticks.push_front(float(node.t))
		k = node.pkey
	return {"cells": cells, "ticks": ticks}

## Convert a planned cell sequence (cell centers + absolute arrival ticks) into a
## world path that begins at the character's actual current position. A short
## glide from current_pos to the first cell center is timed by distance/speed,
## then the planner's per-cell ticks follow (shifted by that glide).
func _build_timed_world_path(current_pos: Vector3, cells: Array, plan_ticks: Array, speed: float, level: int = 0) -> Dictionary:
	var path: Array[Vector3] = [current_pos]
	var ticks: Array[float] = [float(plan_ticks[0])]
	var first_center := grid.grid_to_world(cells[0], level)
	var glide: float = (current_pos.distance_to(first_center) / speed) if speed > 0.0 else 0.0
	for i in range(cells.size()):
		path.append(grid.grid_to_world(cells[i], level))
		ticks.append(float(plan_ticks[i]) + glide)
	# Drop a redundant first center identical to current_pos (zero-length lead-in).
	if path.size() >= 2 and path[0].distance_to(path[1]) < 0.001 and absf(ticks[1] - ticks[0]) < 0.0001:
		path.remove_at(0)
		ticks.remove_at(0)
	return {"path": path, "ticks": ticks}

func _serialize_explored() -> Dictionary:
	var result := {}
	for id in explored:
		var cells: Dictionary = explored[id]
		var cell_list := []
		for cell in cells:
			cell_list.append([cell.x, cell.y])
		result[id] = cell_list
	return result

func _deserialize_explored(data: Dictionary) -> void:
	for id in data:
		explored[id] = {}
		for cell_arr in data[id]:
			explored[id][Vector2i(cell_arr[0], cell_arr[1])] = true

# --- Concealment (hide spots, tiered) ---
#
# A character's concealment TIER throttles how close an enemy must be to spot them (two-tier
# detection): 0 exposed -> spotted within the enemy's full (outer) range; 1 medium hide (a corner /
# scarpet) -> spotted only within the INNER band, so it loses an outer-range chaser but not a close
# one; 2 full hide (a tight spot / shelter) -> never spotted. Derived state (a chunk sets it from
# hide-zone proximity), never logged; rebuilt from position on replay. Recomputing detection on
# change makes an enemy lose/reacquire a target the instant the concealment changes.
const CONCEAL_NONE := 0
const CONCEAL_MEDIUM := 1
const CONCEAL_FULL := 2

func get_character_concealment(id: String) -> int:
	if not characters.has(id):
		return CONCEAL_NONE
	return int(characters[id].stats.get("concealment", CONCEAL_NONE))

## Set a character's concealment tier (0 exposed / 1 medium / 2 full). Recomputes detection on change.
func set_character_concealment(id: String, tier: int) -> void:
	if not characters.has(id):
		return
	var clamped := clampi(tier, CONCEAL_NONE, CONCEAL_FULL)
	if int(characters[id].stats.get("concealment", CONCEAL_NONE)) == clamped:
		return
	characters[id].stats["concealment"] = clamped
	_recompute_all_detection_predictions(id)

## Concealed at all (tier >= 1) for reads; the bool setter maps to a FULL hide (tier 2).
func is_character_hidden(id: String) -> bool:
	return get_character_concealment(id) >= CONCEAL_MEDIUM

func set_character_hidden(id: String, hidden: bool) -> void:
	set_character_concealment(id, CONCEAL_FULL if hidden else CONCEAL_NONE)

# A DISTRACTED detector (one drawn to a flure) has its outer reach shrunk to this fraction — it
# can still catch a target that walks right into it, but won't notice one keeping its distance. The
# detector-side mirror of concealment: derived state (a chunk sets it from lure proximity), never
# logged, rebuilt on replay. Recomputes detection on change so the shrink/restore takes effect at once.
const DETECTION_DISTRACTED_FACTOR := 0.4

func is_character_distracted(id: String) -> bool:
	if not characters.has(id):
		return false
	return bool(characters[id].stats.get("distracted", false))

func set_character_distracted(id: String, distracted: bool) -> void:
	if not characters.has(id):
		return
	if bool(characters[id].stats.get("distracted", false)) == distracted:
		return
	characters[id].stats["distracted"] = distracted
	_recompute_all_detection_predictions(id)

## Publish the only character ids a detector is interested in. Enemy owns the semantic roster; GameState
## owns prediction. An explicit empty list means the detector is listening to nobody. Older callers that
## never publish a list retain the legacy all-character fallback.
func set_detection_targets(detector_id: String, target_ids: Array) -> void:
	if not characters.has(detector_id):
		return
	var normalized: Array[String] = []
	for raw_id in target_ids:
		var target_id := str(raw_id)
		if target_id == detector_id or normalized.has(target_id):
			continue
		normalized.append(target_id)
	var stats: Dictionary = characters[detector_id].stats
	var previous: Array = stats.get("detection_targets", [])
	if stats.has("detection_targets") and previous == normalized:
		return
	stats["detection_targets"] = normalized
	_recompute_all_detection_predictions(detector_id)

## Scanning is a state-machine capability, not a permanent property. Alert/pursuit/attack states disable
## their outgoing prediction subscription; returning to idle/roam/patrol/search enables it again.
func set_detection_enabled(detector_id: String, enabled: bool) -> void:
	if not characters.has(detector_id):
		return
	var stats: Dictionary = characters[detector_id].stats
	if bool(stats.get("detection_enabled", true)) == enabled and stats.has("detection_enabled"):
		return
	stats["detection_enabled"] = enabled
	_recompute_all_detection_predictions(detector_id)

func _detection_target_ids(detector_id: String) -> Array[String]:
	var out: Array[String] = []
	if not characters.has(detector_id):
		return out
	var stats: Dictionary = characters[detector_id].stats
	if stats.has("detection_targets"):
		for raw_id in stats.get("detection_targets", []):
			out.append(str(raw_id))
		return out
	# Compatibility for data-only detectors that predate explicit subscriptions.
	for raw_id in characters.keys():
		var id := str(raw_id)
		if id != detector_id:
			out.append(id)
	return out

## A detector's outer reach, after any distraction shrink — the base from which the target's
## concealment tier then carves the effective spotting range.
func _detector_outer_range(detector_id: String) -> float:
	if not characters.has(detector_id):
		return 0.0
	var outer := float(characters[detector_id].stats.get("detection_range", 0.0))
	if bool(characters[detector_id].stats.get("distracted", false)):
		outer *= DETECTION_DISTRACTED_FACTOR
	return outer

## The range at which a detector of `detector_outer` reach actually spots a target at concealment
## `tier`: full range when exposed, the inner band when medium-hidden, nothing when fully hidden.
func _effective_detection_range(detector_outer: float, target_concealment: int) -> float:
	if target_concealment >= CONCEAL_FULL:
		return 0.0
	if target_concealment == CONCEAL_MEDIUM:
		return detector_outer * DETECTION_INNER_FACTOR
	return detector_outer

## Defensive delivery-time truth for a predicted detection. Predictions are intentionally solved
## ahead of time, but spatial concealment can change at an analytic terrain boundary before the
## queued event is delivered. Consumers must never treat the old schedule as permission to acquire.
func is_detection_pair_currently_visible(detector_id: String, target_id: String) -> bool:
	if not _detection_pair_live_range_valid(detector_id, target_id):
		return false
	if not _has_detection_los(detector_id, target_id):
		return false
	if is_at_shelter(target_id) or is_dodging(target_id):
		return false
	return true

## Read-only diagnostic used by live-scene regressions to prove a prediction was genuinely armed
## before a spatial state transition. A negative value means no current prediction owns the pair.
func get_detection_prediction_tick(detector_id: String, target_id: String) -> float:
	var pair: Dictionary = _detection_active_pairs.get(
		_detection_pair_tag(detector_id, target_id), {})
	return float(pair.get("tick", -1.0))

func _detection_pair_live_range_valid(detector_id: String, target_id: String) -> bool:
	if not characters.has(detector_id) or not characters.has(target_id):
		return false
	var detector_stats: Dictionary = characters[detector_id].stats
	if not bool(detector_stats.get("detection_enabled", true)):
		return false
	if detector_stats.has("detection_targets") \
			and target_id not in _detection_target_ids(detector_id):
		return false
	if is_external_traversal_active(detector_id) or is_external_traversal_active(target_id):
		return false
	var detector_pos := get_position(detector_id)
	var target_pos := get_position(target_id)
	if absf(detector_pos.y - target_pos.y) > DETECTION_VERTICAL_BAND:
		return false
	var effective_range := _effective_detection_range(
		_detector_outer_range(detector_id), get_character_concealment(target_id))
	if effective_range <= 0.0:
		return false
	return Vector2(
		detector_pos.x - target_pos.x,
		detector_pos.z - target_pos.z
	).length() <= effective_range + 0.0001

# --- Predictive Detection ---

## Detection predictions are scheduled under a PER-PAIR tag, so a single character's move only
## recomputes its own pairs (only_id) instead of every detector x target in the scene — the all-pairs
## quadratic re-solve on every move was the hottest data-layer cost in crowded scenes.
func _detection_pair_tag(a: String, b: String) -> String:
	return "dp_%s|%s" % [a, b] if a < b else "dp_%s|%s" % [b, a]

func _cancel_detection_prediction_tags(only_id: String = "") -> void:
	for raw_tag in _detection_active_pairs.keys():
		var tag := str(raw_tag)
		var pair: Dictionary = _detection_active_pairs[tag]
		if only_id != "" and str(pair.get("a", "")) != only_id and str(pair.get("b", "")) != only_id:
			continue
		scheduler.cancel_tag(tag)
		_detection_active_pairs.erase(tag)

func _recompute_all_detection_predictions(only_id: String = "") -> void:
	var perf_started := PerformanceTrace.begin()
	if _detection_batch_depth > 0:
		_detection_batch_dirty = true
		if only_id == "":
			_detection_batch_all_dirty = true
		else:
			_detection_batch_dirty_ids[only_id] = true
		PerformanceTrace.end(&"update", &"game_state.recompute_detection", perf_started, "deferred", 0)
		return
	if not scheduler:
		PerformanceTrace.end(&"update", &"game_state.recompute_detection", perf_started, "no_scheduler", 0)
		return
	var pairs_before := int(_performance_counters["detection_pairs_considered"])
	_performance_counters["detection_recomputes"] = int(_performance_counters["detection_recomputes"]) + 1
	_cancel_detection_prediction_tags(only_id)
	var now := scheduler.get_current_tick()
	for raw_detector_id in characters.keys():
		var detector_id := str(raw_detector_id)
		var detector_stats: Dictionary = characters[detector_id].stats
		if not bool(detector_stats.get("detection_enabled", true)):
			continue
		var outer_range := _detector_outer_range(detector_id)
		if outer_range <= 0.0:
			continue
		for target_id in _detection_target_ids(detector_id):
			if target_id == detector_id or not characters.has(target_id):
				continue
			if only_id != "" and detector_id != only_id and target_id != only_id:
				continue
			_performance_counters["detection_pairs_considered"] = int(
				_performance_counters["detection_pairs_considered"]) + 1
			# Enemies don't see across floors: a target more than a floor's vertical gap away (e.g.
			# the party crossing the bridge ABOVE the lower ecology) isn't spotted until it's on the
			# same level. Recomputed on every move/level change, so detection resumes after a fall.
			if absf(get_position(detector_id).y - get_position(target_id).y) > DETECTION_VERTICAL_BAND:
				continue
			# A body under a LOCKED carry (a sweep, a crawl, a scripted ride) neither sees nor is
			# seen: it isn't walking the deck, and a sentry that aggros a body the current is
			# carrying past will chase it into open water and drown before the level even starts.
			# _finish_external_traversal recomputes at the landing, so sight resumes exactly there.
			if is_external_traversal_active(detector_id) or is_external_traversal_active(target_id):
				continue
			var effective_range := _effective_detection_range(
				outer_range, get_character_concealment(target_id))
			if effective_range <= 0.0:
				continue
			_performance_counters["detection_predictions_solved"] = int(
				_performance_counters["detection_predictions_solved"]) + 1
			var detection_tick := _predict_detection_time(
				detector_id, target_id, effective_range, now)
			if detection_tick < 0.0:
				continue
			var scheduled_detector := detector_id
			var scheduled_target := target_id
			var tag := _detection_pair_tag(detector_id, target_id)
			_detection_active_pairs[tag] = {
				"a": detector_id,
				"b": target_id,
				"tick": detection_tick,
			}
			_performance_counters["detection_events_scheduled"] = int(
				_performance_counters["detection_events_scheduled"]) + 1
			scheduler.schedule_at(detection_tick,
				func(): _on_detection_event(scheduled_detector, scheduled_target), tag)
	PerformanceTrace.end(
		&"update", &"game_state.recompute_detection", perf_started,
		only_id if only_id != "" else "all",
		int(_performance_counters["detection_pairs_considered"]) - pairs_before)

func _on_detection_event(detector_id: String, target_id: String, recheck_hops: int = 0) -> void:
	if not characters.has(detector_id) or not characters.has(target_id):
		return
	var detector_stats: Dictionary = characters[detector_id].stats
	if not bool(detector_stats.get("detection_enabled", true)):
		return
	if detector_stats.has("detection_targets") and target_id not in _detection_target_ids(detector_id):
		return
	# The event's scheduled tick proves only what the pair's old movement/concealment plan predicted.
	# Re-read the live analytic positions and effective range before any acquisition side effect. This
	# rejects a stale event when the target crossed into Candid/full cover after the event was armed.
	if not _detection_pair_live_range_valid(detector_id, target_id):
		return
	# Line of sight: a wall between detector and target blocks the spot (enemies can't see through walls).
	# A blocked spot is NOT the last word while the pair is still in motion: the range-crossing event fires
	# once per recompute, so a target that entered range BEHIND a wall and then walked into the open within
	# the SAME move would otherwise never be re-checked — cover would grant immunity for the rest of the
	# move (The Watched Gap caught this). While either side is moving, re-arm a short scheduler re-check
	# under the pair tag (any recompute replaces it; both parked = frozen geometry = no re-arm needed, the
	# next move recomputes). Scheduler-driven, so it stays replay-deterministic and fast-forward invariant.
	if not _has_detection_los(detector_id, target_id):
		_arm_detection_los_recheck(detector_id, target_id, recheck_hops)
		return
	# Shelter sanctuary: a target standing INSIDE a declared shelter region is never spotted — the
	# rest/revive system is built on shelters being safe ground. Like a wall block, a sheltered miss
	# is not the last word while the pair is still moving (stepping OUT mid-move must still get
	# spotted), so it re-arms the same re-check chain.
	if is_at_shelter(target_id):
		_arm_detection_los_recheck(detector_id, target_id, recheck_hops)
		return
	if is_dodging(target_id):
		return
	# Auto-dodge: if target has dodge queued, automatically evade
	var target_ch: Dictionary = characters[target_id]
	if target_ch.stats.get("auto_dodge", false) and target_ch.stats.get("dodge_unlocked", false):
		var attacker_pos := get_position(detector_id)
		var target_pos := get_position(target_id)
		var approach := Vector3(attacker_pos.x - target_pos.x, 0, attacker_pos.z - target_pos.z)
		if approach.length_squared() > 0.001:
			# Dodge perpendicular to the attack direction
			var perp := Vector3(-approach.z, 0, approach.x).normalized()
			if dodge_roll(target_id, perp):
				return
	detection_predicted.emit(detector_id, target_id)

## Grid line-of-sight gate for detection. No grid, or a scene whose walls aren't grid cells, => always visible
## (unchanged behaviour — only scenes that mark walls/sight-blockers get LOS). Pure grid query, so it stays
## replay-deterministic. Cross-floor cases are already handled by DETECTION_VERTICAL_BAND upstream.
func _has_detection_los(detector_id: String, target_id: String) -> bool:
	if grid == null:
		return true
	return grid.has_line_of_sight(get_position(detector_id), get_position(target_id))

## Arm one hop of the LOS re-check chain. Only while either side is MOVING (parked-parked geometry is
## frozen — the next move recomputes fresh), and bounded by a hop budget so a permanently-blocked pair in
## constant motion can't poll forever. Uses the pair tag, so any recompute cancels + supersedes the chain.
func _arm_detection_los_recheck(detector_id: String, target_id: String, hops: int) -> void:
	if scheduler == null or hops >= DETECTION_LOS_RECHECK_MAX_HOPS:
		return
	if not (is_moving(detector_id) or is_moving(target_id)):
		return
	var tag := _detection_pair_tag(detector_id, target_id)
	_detection_active_pairs[tag] = {
		"a": detector_id,
		"b": target_id,
		"tick": float(scheduler.get_current_tick()) + DETECTION_LOS_RECHECK_INTERVAL,
	}
	scheduler.schedule_after(DETECTION_LOS_RECHECK_INTERVAL,
		func(): _recheck_detection_after_los_block(detector_id, target_id, hops + 1),
		tag)

## The follow-up to a wall-blocked spot on a pair still in motion. Unlike the primary event (whose scheduled
## tick IS the range-crossing proof), time has passed — so re-verify the pair is STILL spottable now (band,
## concealment tier, effective range) before handing back to _on_detection_event, which redoes the LOS gate
## and re-arms this if the wall still intervenes. A transient RANGE dip is NOT terminal while the pair is
## still moving — the one-shot range-crossing prediction was already consumed by the original blocked event,
## so dropping the chain here would resurrect the cover-immunity bug for in-move re-entries (the review
## caught this). Only out-of-range AND parked (or a concealment/band change, which recompute) end it.
func _recheck_detection_after_los_block(detector_id: String, target_id: String, hops: int = 1) -> void:
	if not characters.has(detector_id) or not characters.has(target_id):
		return
	if absf(get_position(detector_id).y - get_position(target_id).y) > DETECTION_VERTICAL_BAND:
		return
	var eff := _effective_detection_range(
		_detector_outer_range(detector_id), get_character_concealment(target_id))
	if eff <= 0.0:
		return
	var dpos := get_position(detector_id)
	var tpos := get_position(target_id)
	if Vector2(dpos.x - tpos.x, dpos.z - tpos.z).length() > eff:
		_arm_detection_los_recheck(detector_id, target_id, hops)
		return
	_on_detection_event(detector_id, target_id, hops)

func _predict_detection_time(detector_id: String, target_id: String, det_range: float, now: float) -> float:
	var segs_a := _get_movement_segments(detector_id)
	var segs_b := _get_movement_segments(target_id)
	var earliest := -1.0
	for seg_a in segs_a:
		for seg_b in segs_b:
			var t0: float = maxf(seg_a.start_tick, seg_b.start_tick)
			var t1: float = minf(seg_a.end_tick, seg_b.end_tick)
			if t0 >= t1:
				continue
			if t0 < now:
				t0 = now
			if t0 >= t1:
				continue
			var pos_a: Vector3 = seg_a.start_pos + (t0 - seg_a.start_tick) * seg_a.velocity
			var pos_b: Vector3 = seg_b.start_pos + (t0 - seg_b.start_tick) * seg_b.velocity
			var tau := _solve_quadratic_detection(pos_a, seg_a.velocity, pos_b, seg_b.velocity, det_range, t1 - t0)
			if tau >= 0.0:
				var abs_t := t0 + tau
				if earliest < 0.0 or abs_t < earliest:
					earliest = abs_t
	return earliest

func _get_movement_segments(id: String) -> Array[Dictionary]:
	if _external_traversals.has(id):
		var external: Dictionary = _external_traversals[id]
		var start: Vector3 = external["data_origin"]
		var destination: Vector3 = external["data_destination"]
		var start_tick := float(external["start_tick"])
		var end_tick := float(external["end_tick"])
		var span := end_tick - start_tick
		var velocity := Vector3.ZERO
		if span > 0.0001:
			velocity = Vector3(destination.x - start.x, 0.0, destination.z - start.z) / span
		return [
			{
				"start_tick": start_tick,
				"end_tick": end_tick,
				"start_pos": Vector3(start.x, 0.0, start.z),
				"velocity": velocity,
			},
			{
				"start_tick": end_tick,
				"end_tick": 1e12,
				"start_pos": Vector3(destination.x, 0.0, destination.z),
				"velocity": Vector3.ZERO,
			},
		]
	var ch: Dictionary = characters[id]
	if ch.movement == null:
		var pos: Vector3 = ch.position
		return [{"start_tick": 0.0, "end_tick": 1e12, "start_pos": Vector3(pos.x, 0, pos.z), "velocity": Vector3.ZERO}]
	var mv: Dictionary = ch.movement
	var segments: Array[Dictionary] = []
	var has_ticks: bool = mv.has("arrival_ticks")
	for i in range(1, mv.path.size()):
		var seg_start_tick: float
		var seg_end_tick: float
		if has_ticks:
			seg_start_tick = mv.arrival_ticks[i - 1]
			seg_end_tick = mv.arrival_ticks[i]
		else:
			seg_start_tick = mv.start_tick + (mv.cum_dist[i - 1] / mv.total_distance) * mv.duration
			seg_end_tick = mv.start_tick + (mv.cum_dist[i] / mv.total_distance) * mv.duration
		var dir := Vector3(mv.path[i].x - mv.path[i - 1].x, 0, mv.path[i].z - mv.path[i - 1].z)
		var span: float = seg_end_tick - seg_start_tick
		var vel := dir / span if (dir.length() > 0.001 and span > 0.0001) else Vector3.ZERO
		segments.append({
			"start_tick": seg_start_tick,
			"end_tick": seg_end_tick,
			"start_pos": Vector3(mv.path[i - 1].x, 0, mv.path[i - 1].z),
			"velocity": vel,
		})
	# After the final waypoint the character is PARKED there, not gone. Append a trailing static
	# segment so the predictor still sees it once it stops — otherwise a target approaching an enemy
	# that has already arrived (e.g. a guard parked on a lure) is never predicted, because the moving
	# segments end at arrival and nothing recomputes on arrival.
	var last_pos: Vector3 = mv.path[mv.path.size() - 1]
	var last_tick: float = mv.arrival_ticks[mv.arrival_ticks.size() - 1] if has_ticks else (mv.start_tick + mv.duration)
	segments.append({
		"start_tick": last_tick,
		"end_tick": 1e12,
		"start_pos": Vector3(last_pos.x, 0, last_pos.z),
		"velocity": Vector3.ZERO,
	})
	return segments

## Exact scheduler ticks at which the current committed movement plan touches an axis-aligned XZ
## region boundary. Spatial terrain systems use these ticks to invalidate derived state at the
## physical boundary rather than waiting for a polling cadence. This is read-only and deterministic:
## it solves against the same piecewise-linear movement segments used by predictive detection.
func predict_axis_aligned_region_boundary_ticks(
		id: String,
		center_xz: Vector2,
		half_size: Vector2
	) -> Array[float]:
	var candidates: Array[float] = []
	if not characters.has(id) or scheduler == null \
			or half_size.x < 0.0 or half_size.y < 0.0:
		return candidates
	var now := float(scheduler.get_current_tick())
	var min_x := center_xz.x - half_size.x
	var max_x := center_xz.x + half_size.x
	var min_z := center_xz.y - half_size.y
	var max_z := center_xz.y + half_size.y
	for segment in _get_movement_segments(id):
		var start_tick := float(segment.get("start_tick", now))
		var end_tick := float(segment.get("end_tick", now))
		if end_tick <= now + 0.000001:
			continue
		var start_pos := segment.get("start_pos", Vector3.ZERO) as Vector3
		var velocity := segment.get("velocity", Vector3.ZERO) as Vector3
		if absf(velocity.x) > 0.000001:
			for boundary_x in [min_x, max_x]:
				var tick_x := start_tick + (float(boundary_x) - start_pos.x) / velocity.x
				if tick_x <= now + 0.000001 or tick_x > end_tick + 0.000001:
					continue
				var cross_z := start_pos.z + velocity.z * (tick_x - start_tick)
				if cross_z >= min_z - 0.0001 and cross_z <= max_z + 0.0001:
					candidates.append(tick_x)
		if absf(velocity.z) > 0.000001:
			for boundary_z in [min_z, max_z]:
				var tick_z := start_tick + (float(boundary_z) - start_pos.z) / velocity.z
				if tick_z <= now + 0.000001 or tick_z > end_tick + 0.000001:
					continue
				var cross_x := start_pos.x + velocity.x * (tick_z - start_tick)
				if cross_x >= min_x - 0.0001 and cross_x <= max_x + 0.0001:
					candidates.append(tick_z)
	candidates.sort()
	var unique_ticks: Array[float] = []
	for candidate in candidates:
		if unique_ticks.is_empty() \
				or absf(candidate - unique_ticks[unique_ticks.size() - 1]) > 0.00001:
			unique_ticks.append(candidate)
	return unique_ticks

## Exact positive-duration intervals where the current finite movement plan occupies an axis-aligned
## XZ region. Unlike a point sample, this catches a thin hazard crossed entirely between cadence
## ticks. The trailing parked segment is intentionally excluded; stationary exposure remains owned
## by the hazard's fixed cadence.
func predict_axis_aligned_region_occupancy_intervals(
		id: String,
		center_xz: Vector2,
		half_size: Vector2
	) -> Array[Dictionary]:
	var intervals: Array[Dictionary] = []
	if not characters.has(id) or scheduler == null \
			or half_size.x < 0.0 or half_size.y < 0.0:
		return intervals
	var now := float(scheduler.get_current_tick())
	var min_x := center_xz.x - half_size.x
	var max_x := center_xz.x + half_size.x
	var min_z := center_xz.y - half_size.y
	var max_z := center_xz.y + half_size.y
	for segment in _get_movement_segments(id):
		var segment_start := float(segment.get("start_tick", now))
		var segment_end := float(segment.get("end_tick", now))
		# `_get_movement_segments` appends a practically-infinite parked segment. It is not travel.
		if segment_end >= 1e11 or segment_end <= now + 0.000001:
			continue
		var clipped_start := maxf(now, segment_start)
		var duration := segment_end - clipped_start
		if duration <= 0.000001:
			continue
		var velocity := segment.get("velocity", Vector3.ZERO) as Vector3
		var origin := (segment.get("start_pos", Vector3.ZERO) as Vector3) \
			+ velocity * (clipped_start - segment_start)
		var local_enter := 0.0
		var local_exit := duration
		var intersects := true
		if absf(velocity.x) <= 0.000001:
			intersects = origin.x >= min_x and origin.x <= max_x
		else:
			var x0 := (min_x - origin.x) / velocity.x
			var x1 := (max_x - origin.x) / velocity.x
			local_enter = maxf(local_enter, minf(x0, x1))
			local_exit = minf(local_exit, maxf(x0, x1))
		if intersects:
			if absf(velocity.z) <= 0.000001:
				intersects = origin.z >= min_z and origin.z <= max_z
			else:
				var z0 := (min_z - origin.z) / velocity.z
				var z1 := (max_z - origin.z) / velocity.z
				local_enter = maxf(local_enter, minf(z0, z1))
				local_exit = minf(local_exit, maxf(z0, z1))
		local_enter = maxf(0.0, local_enter)
		local_exit = minf(duration, local_exit)
		if not intersects or local_exit <= local_enter + 0.000001:
			continue
		var absolute_start := clipped_start + local_enter
		var absolute_end := clipped_start + local_exit
		if not intervals.is_empty() \
				and float(intervals[intervals.size() - 1].get("end_tick", -1.0)) \
					>= absolute_start - 0.00001:
			intervals[intervals.size() - 1]["end_tick"] = maxf(
				float(intervals[intervals.size() - 1].get("end_tick", absolute_end)),
				absolute_end)
		else:
			intervals.append({
				"start_tick": absolute_start,
				"end_tick": absolute_end,
			})
	return intervals

## ANALYTIC WAITING — the reason the scheduler architecture exists. Position is a pure function of the
## tick, so "when is `id` first within `radius` of `point`?" is SOLVED from its current movement plan, not
## discovered by polling. Tests jump the scheduler exactly to the returned tick (identical to waiting,
## none of the cost), and the WHEN register reads the same number diegetically (for example, a
## target-owned patrol-gauge scan queries the sentry's real beat). Returns the absolute tick, or -1.0 if the CURRENT plan never
## comes that close (a future plan — the next patrol leg, a new command — needs a re-ask after it exists).
func predict_proximity_tick(id: String, point: Vector3, radius: float) -> float:
	if not characters.has(id) or scheduler == null:
		return -1.0
	var now: float = scheduler.get_current_tick()
	var target := Vector3(point.x, 0.0, point.z)
	for seg in _get_movement_segments(id):
		var t0: float = maxf(float(seg["start_tick"]), now)
		var t1: float = float(seg["end_tick"])
		if t0 >= t1:
			continue
		var p0: Vector3 = (seg["start_pos"] as Vector3) + (seg["velocity"] as Vector3) * (t0 - float(seg["start_tick"]))
		var tau := _solve_quadratic_detection(p0, seg["velocity"], target, Vector3.ZERO, radius, t1 - t0)
		if tau >= 0.0:
			return t0 + tau
	return -1.0

## The tick the current movement plan ARRIVES (its last waypoint), or now if parked. The analytic form of
## "wait until they get there".
func get_plan_end_tick(id: String) -> float:
	if not characters.has(id) or scheduler == null:
		return -1.0
	var now: float = scheduler.get_current_tick()
	if _external_traversals.has(id):
		return maxf(float(_external_traversals[id].get("end_tick", now)), now)
	var ch: Dictionary = characters[id]
	if ch.movement == null:
		return now
	var mv: Dictionary = ch.movement
	if mv.has("arrival_ticks"):
		return maxf(float(mv.arrival_ticks[mv.arrival_ticks.size() - 1]), now)
	return maxf(float(mv.start_tick) + float(mv.duration), now)

# --- Dodge Roll ---

const DODGE_DISTANCE := 3.0
const DODGE_DURATION := 0.35
const DODGE_STAMINA_COST := 15.0
const DODGE_COOLDOWN := 1.0
const KNOCKDOWN_DURATION := 1.6  # seconds flat on the ground after a failed (no-stamina) dodge

func dodge_roll(char_id: String, direction: Vector3) -> bool:
	_emit(GameEvent.KIND_DODGE_ROLL, {
		"char_id": char_id,
		"direction": GameEvent.v3_to_arr(direction),
	})
	if not characters.has(char_id) or not scheduler:
		return false
	if is_endocytosing(char_id) or is_external_traversal_active(char_id) \
			or is_dragging(char_id) or is_resting(char_id) or is_field_restoring(char_id):
		return false
	var ch: Dictionary = characters[char_id]
	if not ch.stats.get("dodge_unlocked", false):
		return false
	if float(ch.stats.get("hp", 1.0)) <= 0.0:
		return false  # a downed character can't dodge (no spending stamina from a corpse)
	if is_dodging(char_id) or is_knocked_down(char_id):
		return false
	# Cooldown check
	var now := scheduler.get_current_tick()
	var last_dodge: float = ch.stats.get("_last_dodge_tick", -10.0)
	if now - last_dodge < DODGE_COOLDOWN:
		return false
	# Stamina check: a character too exhausted to roll FALLS instead — flat on the ground and
	# vulnerable (can't move or dodge) until they pick themselves up. The fall costs nothing.
	var stamina: float = ch.stats.get("stamina", 0.0)
	if stamina < DODGE_STAMINA_COST:
		_begin_knockdown(char_id)
		return false
	# A dodge is its own committed locomotion policy. Retire sprint before installing the dodge
	# callback so a run-toggle cannot cancel that callback and leave permanent dodge immunity.
	if is_running(char_id):
		set_running(char_id, false)

	# Compute the dodge destination FIRST and reject a fully wall-blocked dodge before spending anything —
	# a dodge that never moves must cost neither stamina NOR the cooldown (else a corner traps you on cd).
	# Prefer a roll that does NOT land on another character: try the requested direction, then rotated
	# alternatives (deterministic order); if every clear lane is occupied, take the first one that MOVES
	# (dodging into a crowd beats eating the hit).
	var dir := Vector3(direction.x, 0, direction.z)
	if dir.length_squared() < 0.001:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var from := get_position(char_id)
	var to := Vector3.INF
	var fallback := Vector3.INF
	for angle_deg in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
		var cand_dir := dir.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var cand := from + cand_dir * DODGE_DISTANCE
		if grid:
			cand = _trace_slide_against_walls(from, cand)
		# A lane must give a MEANINGFUL evade — a sub-cell shuffle against a wall is not a dodge.
		if Vector3(cand.x - from.x, 0, cand.z - from.z).length() < DODGE_DISTANCE / 3.0:
			continue  # wall-blocked lane
		if fallback == Vector3.INF:
			fallback = cand
		if not _dodge_lands_on_character(char_id, cand):
			to = cand
			break
	if to == Vector3.INF:
		to = fallback
	if to == Vector3.INF:
		return false  # fully wall-blocked: nothing consumed, no cooldown armed
	var dodge_dist := Vector3(to.x - from.x, 0, to.z - from.z).length()

	# Commit: spend stamina + arm the cooldown only now that the dodge will actually happen.
	ch.stats["stamina"] = stamina - DODGE_STAMINA_COST
	ch.stats["_last_dodge_tick"] = now

	# Cancel current movement and start dodge movement
	_cancel_movement(char_id)
	ch.position = from

	var speed := dodge_dist / DODGE_DURATION
	var path: Array[Vector3] = [from, to]
	var cum_dist := _compute_cum_dist(path)
	var cid := char_id
	var handle := scheduler.schedule_at(
		now + DODGE_DURATION,
		func(): _on_dodge_end(cid),
		"dodge_" + char_id
	)
	var dodge_ticks: Array[float] = [now, now + DODGE_DURATION]
	ch.movement = {
		"path": path,
		"cum_dist": cum_dist,
		"arrival_ticks": dodge_ticks,
		"total_distance": dodge_dist,
		"start_tick": now,
		"duration": DODGE_DURATION,
		"handle": handle,
	}
	# Reserve the dodge's cells so a cooperative mover routes around the dodging
	# character (the manual movement dict above bypasses _start_movement).
	_reserve_path(char_id, path, dodge_ticks)
	_dodging[char_id] = {"end_tick": now + DODGE_DURATION, "handle": handle}

	# Emit the RESOLVED roll direction (avoidance may have rotated it off the requested vector).
	dodge_started.emit(char_id, Vector3(to.x - from.x, 0, to.z - from.z).normalized())
	_recompute_all_detection_predictions(char_id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()
	return true

func is_dodging(char_id: String) -> bool:
	return _dodging.has(char_id)

# --- Knockdown (the failed dodge): flat on the ground, can't move or dodge, strikes land. ---
# Derived state: a deterministic consequence of the logged dodge_roll command + stamina, with the
# recovery riding the scheduler. Replay derives it from the command and snapshots preserve its remainder.

func is_knocked_down(char_id: String) -> bool:
	return _knocked_down.has(char_id)

## Whether the destination of a candidate dodge lands on (or grazes) another living character.
func _dodge_lands_on_character(char_id: String, dest: Vector3) -> bool:
	for other_id in characters.keys():
		if str(other_id) == char_id:
			continue
		if float(characters[other_id].stats.get("hp", 1.0)) <= 0.0:
			continue
		var p := get_position(str(other_id))
		if Vector2(p.x - dest.x, p.z - dest.z).length() < 0.9:
			return true
	return false

func _begin_knockdown(char_id: String) -> void:
	if is_knocked_down(char_id) or not scheduler:
		return
	# Fall where you stand: pin the position, drop any movement.
	var pinned := get_position(char_id)
	_cancel_movement(char_id)
	characters[char_id].position = pinned
	if grid:
		characters[char_id].grid_cell = grid.world_to_grid(pinned)
		_reserve_parked(char_id, characters[char_id].grid_cell)
	var cid := char_id
	var handle := scheduler.schedule_after(KNOCKDOWN_DURATION, func(): _on_knockdown_end(cid), "knockdown_" + char_id)
	_knocked_down[char_id] = {"end_tick": scheduler.get_current_tick() + KNOCKDOWN_DURATION, "handle": handle}
	knockdown_started.emit(char_id)

func _on_knockdown_end(char_id: String) -> void:
	_knocked_down.erase(char_id)
	knockdown_ended.emit(char_id)

func _on_dodge_end(char_id: String) -> void:
	_dodging.erase(char_id)
	if not characters.has(char_id):
		return
	var ch: Dictionary = characters[char_id]
	if ch.movement != null:
		var dest: Vector3 = ch.movement.path[ch.movement.path.size() - 1]
		ch.position = dest
		if grid:
			ch.grid_cell = grid.world_to_grid(dest)
		ch.movement = null
	_reserve_parked(char_id, ch.grid_cell)
	# A detection event that fired DURING the dodge window was consumed by the is_dodging gate with nothing
	# re-armed — without a recompute here, a dodger standing in the open inside range would stay unseen
	# until some unrelated command recomputed (post-dodge immunity, same bug class as the LOS re-check).
	_recompute_all_detection_predictions()
	dodge_finished.emit(char_id)

# --- Queued Abilities (auto-move-into-range) ---

var _queued_abilities: Dictionary = {} # char_id → {ability, target_pos, range, callback}

## Legacy replay handlers for non-canonical callback abilities. EMP and WRAP carry a serializable
## command payload and resolve through CanonicalCharacterAbility without this registry.
var _ability_handlers: Dictionary = {}

func register_ability_handler(ability_id: StringName, handler: Callable) -> void:
	_ability_handlers[ability_id] = handler

func queue_ability(char_id: String, ability: String, target_pos: Vector3, ability_range: float, callback: Callable) -> void:
	_emit(GameEvent.KIND_QUEUE_ABILITY, {
		"char_id": char_id,
		"ability": ability,
		"target_pos": GameEvent.v3_to_arr(target_pos),
		"range": ability_range,
	})
	_queue_ability_internal(char_id, ability, target_pos, ability_range, callback)

## Queue a canonical cast as one authoritative, replayable command. target_pos is DATA-space, like
## every GameState movement command. WRAP also requires options.target_id; options.allowed_target_ids
## defaults to the current party roster. A scene can explicitly authorize a conscious non-party ward
## such as Monos without admitting every registered actor. world_root is a runtime-only EMP receiver
## root: replay rebuilds all
## GameState consequences (including stamina and WRAP) without a handler, while scene objects are
## expected to be rebuilt by their scene just like other scene-scoped mechanisms.
func queue_canonical_ability(
		char_id: String,
		ability: String,
		target_pos: Vector3,
		options: Dictionary = {},
		world_root: Node = null,
		callback: Callable = Callable()
	) -> Dictionary:
	var canonical := _canonical_command_options(ability, options)
	var ability_range := float(canonical.get(
		"approach_range", CanonicalCharacterAbilityScript.cast_range(ability)))
	_emit(GameEvent.KIND_QUEUE_ABILITY, {
		"char_id": char_id,
		"ability": ability,
		"target_pos": GameEvent.v3_to_arr(target_pos),
		"range": ability_range,
		"canonical": canonical.duplicate(true),
	})
	var validation := CanonicalCharacterAbilityScript.validate_cast(
		self, ability, char_id, target_pos, canonical, false)
	if not bool(validation.get("accepted", false)):
		return validation
	return _queue_ability_internal(
		char_id, ability, target_pos, ability_range, callback, canonical, world_root)

func _canonical_command_options(ability: String, options: Dictionary) -> Dictionary:
	var requested_targets = options.get(
		"allowed_target_ids", options.get("party_ids", get_party()))
	var allowed_target_ids: Array = requested_targets.duplicate() \
		if requested_targets is Array else []
	var canonical := {
		"target_is_data": true,
		"allowed_target_ids": allowed_target_ids,
	}
	if options.has("approach_range"):
		canonical["approach_range"] = maxf(0.0, float(options.get("approach_range", 0.0)))
	if options.has("duration"):
		canonical["duration"] = float(options.get("duration", 0.0))
	if ability == CanonicalCharacterAbilityScript.WRAP_ID:
		canonical["target_id"] = str(options.get("target_id", ""))
		if not canonical.has("duration"):
			canonical["duration"] = CanonicalCharacterAbilityScript.WRAP_DURATION_SECONDS
	return canonical

func _queue_ability_internal(
		char_id: String,
		ability: String,
		target_pos: Vector3,
		ability_range: float,
		callback: Callable,
		canonical: Dictionary = {},
		world_root: Node = null
	) -> Dictionary:
	if not characters.has(char_id):
		return {"accepted": false, "reason": "invalid_owner"}
	var char_pos := get_position(char_id)
	var dist := Vector2(char_pos.x - target_pos.x, char_pos.z - target_pos.z).length()
	if dist <= ability_range:
		var immediate := _execute_ability_entry(char_id, {
			"ability": ability,
			"target_pos": target_pos,
			"range": ability_range,
			"callback": callback,
			"canonical": canonical,
			"world_root": world_root,
		})
		if bool(immediate.get("accepted", false)):
			ability_fired.emit(char_id, ability, target_pos)
		immediate["queued"] = false
		return immediate
	if scheduler:
		scheduler.cancel_tag("ability_range_" + char_id)
	_queued_abilities[char_id] = {
		"ability": ability,
		"target_pos": target_pos,
		"range": ability_range,
		"callback": callback,
		"canonical": canonical,
		"world_root": world_root,
	}
	var move_target := target_pos
	_do_move_to_pos(char_id, move_target)
	_schedule_ability_in_range(char_id)
	return {"accepted": true, "queued": true}

func cancel_queued_ability(char_id: String) -> void:
	_emit(GameEvent.KIND_CANCEL_QUEUED_ABILITY, {"char_id": char_id})
	_queued_abilities.erase(char_id)
	if scheduler:
		scheduler.cancel_tag("ability_range_" + char_id)

func has_queued_ability(char_id: String) -> bool:
	return _queued_abilities.has(char_id)

func get_queued_ability(char_id: String) -> String:
	if _queued_abilities.has(char_id):
		return _queued_abilities[char_id].ability
	return ""

func _schedule_ability_in_range(char_id: String) -> void:
	if not _queued_abilities.has(char_id) or not scheduler:
		return
	scheduler.cancel_tag("ability_range_" + char_id)
	var qa: Dictionary = _queued_abilities[char_id]
	var now := scheduler.get_current_tick()
	var char_segs := _get_movement_segments(char_id)
	var target_seg: Array[Dictionary] = [{
		"start_tick": 0.0,
		"end_tick": 1e12,
		"start_pos": Vector3(qa.target_pos.x, 0, qa.target_pos.z),
		"velocity": Vector3.ZERO,
	}]
	var t := _predict_collision_time(char_segs, target_seg, qa.range, now)
	if t >= 0.0:
		var cid := char_id
		scheduler.schedule_at(t, func(): _on_ability_in_range(cid), "ability_range_" + char_id)

func _on_ability_in_range(char_id: String) -> void:
	if not _queued_abilities.has(char_id):
		return
	var qa: Dictionary = _queued_abilities[char_id]
	_queued_abilities.erase(char_id)
	_do_stop(char_id)
	var result := _execute_ability_entry(char_id, qa)
	if bool(result.get("accepted", false)):
		ability_fired.emit(char_id, qa.ability, qa.target_pos)

func _execute_ability_entry(char_id: String, queued: Dictionary) -> Dictionary:
	var canonical: Dictionary = queued.get("canonical", {})
	var callback: Callable = queued.get("callback", Callable())
	if not canonical.is_empty():
		var runtime_options := canonical.duplicate(true)
		runtime_options["world_root"] = queued.get("world_root")
		var result := CanonicalCharacterAbilityScript.execute(
			self,
			str(queued.get("ability", "")),
			char_id,
			queued.get("target_pos", Vector3.ZERO),
			runtime_options)
		if bool(result.get("accepted", false)) and callback.is_valid():
			callback.call()
		return result
	if callback.is_valid():
		callback.call()
		return {"accepted": true}
	return {"accepted": false, "reason": "missing_handler"}

# --- Items / Hands / Endocytosis ---

const TRANSFER_RANGE := 1.5
const ENDOCYTOSE_DEFAULT_DURATION := 2.0

func spawn_item(type: String, pos: Vector3, properties: Dictionary = {}) -> String:
	_emit(GameEvent.KIND_SPAWN_ITEM, {
		"type": type,
		"pos": GameEvent.v3_to_arr(pos),
		"properties": properties.duplicate(true),
	})
	var id := "item_%d" % _next_item_id
	_next_item_id += 1
	var type_data := ItemData.get_type_data(type)
	type_data.merge(properties, true)
	if not type_data.has("hand_slots"):
		type_data["hand_slots"] = ItemData.get_hand_slots(type)
	if not type_data.has("endocytosis_allowed"):
		type_data["endocytosis_allowed"] = ItemData.can_endocytose(type)
	items[id] = {
		"type": type,
		"holder": "",
		"location": "ground",
		"position": pos,
		"properties": type_data,
	}
	return id

func remove_item(item_id: String) -> void:
	_emit(GameEvent.KIND_REMOVE_ITEM, {"item_id": item_id})
	if not items.has(item_id):
		return
	var item: Dictionary = items[item_id]
	if item.holder != "" and characters.has(item.holder):
		var ch: Dictionary = characters[item.holder]
		if item.location == "hand":
			for i in range(ch.hands.size()):
				if ch.hands[i] == item_id:
					ch.hands[i] = null
		elif item.location == "internal":
			ch.internal.erase(item_id)
	items.erase(item_id)

func pick_up_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_PICK_UP_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id):
		return false
	if is_endocytosing(char_id):
		return false
	var item: Dictionary = items[item_id]
	if item.location != "ground":
		return false
	var ch: Dictionary = characters[char_id]
	var required_slots := _required_hand_slots(item)
	var slots := _find_free_hand_slots(char_id, required_slots)
	if slots.is_empty():
		return false
	var char_pos := get_position(char_id)
	var dist := Vector3(char_pos.x - item.position.x, 0, char_pos.z - item.position.z).length()
	if dist > 2.0:
		return false
	for slot in slots:
		ch.hands[int(slot)] = item_id
	item.holder = char_id
	item.location = "hand"
	item_picked_up.emit(char_id, item_id)
	return true

func drop_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_DROP_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id):
		return false
	if is_endocytosing(char_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "hand":
		return false
	var ch: Dictionary = characters[char_id]
	_clear_item_from_hands(ch, item_id)
	item.holder = ""
	item.location = "ground"
	item.position = get_position(char_id)
	item_dropped.emit(char_id, item_id)
	return true

func transfer_item(from_id: String, to_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_TRANSFER_ITEM, {"from_id": from_id, "to_id": to_id, "item_id": item_id})
	if not characters.has(from_id) or not characters.has(to_id) or not items.has(item_id):
		return false
	if is_endocytosing(from_id) or is_endocytosing(to_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != from_id or item.location != "hand":
		return false
	var to_slots := _find_free_hand_slots(to_id, _required_hand_slots(item))
	if to_slots.is_empty():
		return false
	var dist := get_position(from_id).distance_to(get_position(to_id))
	if dist > TRANSFER_RANGE:
		return false
	var from_ch: Dictionary = characters[from_id]
	_clear_item_from_hands(from_ch, item_id)
	var to_ch: Dictionary = characters[to_id]
	for slot in to_slots:
		to_ch.hands[int(slot)] = item_id
	item.holder = to_id
	item_transferred.emit(from_id, to_id, item_id)
	return true

# --- The Pass: throwing an item hand-to-point (docs/THROW_HANDOFF.md) ---
#
# A throw moves an ITEM to a POINT. It never resolves against a body, carries no velocity and no
# force, and cannot express "hit that thing" — the arriving object is inert. The whole outcome is
# solved ONCE, in closed form, at the release tick, and the solved point is what gets logged, so
# replay re-runs the landing from the record and never re-solves. Nothing about the result is ever
# discovered by sampling, which is what keeps it identical at 1x and 10x.

## Arm speed and arc ceiling, promoted from the constants throw_physics_object_to already hardcodes
## rather than invented — a ~15 m envelope that falls off with height difference.
const THROW_XZ_SPEED := 6.0
const THROW_MAX_ARC := 2.5
## How close a party member must be to the landing point to catch it out of the air.
const THROW_CATCH_RADIUS := 1.2

## Smallest positive flight time at which a projectile of XZ speed `speed` launched from `from_xz`
## meets a target that is at `q_xz` now and moving at constant `vel_xz`. Solves
##     (|u|^2 - v^2) t^2 + 2 (d.u) t + |d|^2 = 0,   d = q - p
## exactly — no iteration, so there is no convergence tolerance that could drift between step sizes.
## A parked target (u = 0) is not a special case: it reduces to t = |d| / v through the same path.
## Returns -1.0 when the projectile can never catch it. Mirrors _solve_quadratic_detection's shape,
## including its degenerate-`a` handling.
static func _solve_quadratic_intercept(from_xz: Vector3, q_xz: Vector3, vel_xz: Vector3, speed: float) -> float:
	var dx := q_xz.x - from_xz.x
	var dz := q_xz.z - from_xz.z
	var a := vel_xz.x * vel_xz.x + vel_xz.z * vel_xz.z - speed * speed
	var b := 2.0 * (dx * vel_xz.x + dz * vel_xz.z)
	var c := dx * dx + dz * dz
	if c <= 1e-6:
		return 0.0  # already underfoot
	if absf(a) < 1e-8:
		# Target recedes at exactly the arm speed: linear. Only closable if it is closing at all.
		if b >= -1e-8:
			return -1.0
		return -c / b
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var sqrt_disc := sqrt(disc)
	var t1 := (-b - sqrt_disc) / (2.0 * a)
	var t2 := (-b + sqrt_disc) / (2.0 * a)
	var lo := minf(t1, t2)
	var hi := maxf(t1, t2)
	if lo > 1e-6:
		return lo
	if hi > 1e-6:
		return hi
	return -1.0

## EVERYTHING IS THROWABLE — there is deliberately no allowlist and no per-item opt-out.
## A verb that works on some items and not others is a rule the player has to memorise, and the
## mental load costs more than the restriction saves. This is the same one-rule-no-exceptions law
## the Capbage cache and endocytosis already follow: the cavity holds whatever you put in it, and
## you learn through results. The safety that an allowlist was standing in for belongs one layer
## down instead: there must never be a generic "run the item's effect where it lands" rule. What
## arrives is an item on the floor. A fire fruit's damage is an ENDOCYTOSIS effect — it hurts the
## character who eats it — and throwing one must never turn it into a grenade.

## PURE READ — the preview. Returns {ok, reason, landing, level, flight, aim}. command_throw_item
## runs exactly this and then delegates, so what the preview draws is what a commit executes.
func solve_throw(from_id: String, item_id: String, target_kind: String, target_ref) -> Dictionary:
	var fail := func(why: String) -> Dictionary:
		return {"ok": false, "reason": why, "landing": Vector3.ZERO, "level": 0, "flight": 0.0, "aim": ""}
	if not characters.has(from_id) or not items.has(item_id):
		return fail.call("no such thrower or item")
	var item: Dictionary = items[item_id]
	if item.holder != from_id or item.location != "hand":
		return fail.call("not in hand")
	var from_pos := get_position(from_id)
	var from_level := get_character_level(from_id)
	var aim := ""
	var to_level := from_level
	var landing := Vector3.ZERO
	var flight := 0.0
	if target_kind == "char":
		var target_id := String(target_ref)
		if not characters.has(target_id):
			return fail.call("no such target")
		aim = target_id
		to_level = get_character_level(target_id)
		var now := float(scheduler.get_current_tick()) if scheduler else 0.0
		var solved := false
		for seg in _get_movement_segments(target_id):
			var s0 := float(seg["start_tick"])
			var s1 := float(seg["end_tick"])
			if s1 <= now:
				continue
			var u: Vector3 = seg["velocity"]
			# Extrapolate the segment's line to NOW so the projectile and the target share t=0.
			var q0: Vector3 = seg["start_pos"] + u * (now - s0)
			var t := _solve_quadratic_intercept(from_pos, q0, u, THROW_XZ_SPEED)
			if t < 0.0:
				continue
			var land_tick := now + t
			if land_tick < maxf(s0, now) - 1e-6 or land_tick > s1 + 1e-6:
				continue
			landing = q0 + u * t
			flight = t
			solved = true
			break
		if not solved:
			return fail.call("cannot lead that target")
	else:
		var pt: Vector3 = target_ref
		landing = Vector3(pt.x, 0.0, pt.z)
		if target_kind == "point_on_level":
			to_level = int(round(pt.y))
		flight = Vector2(landing.x - from_pos.x, landing.z - from_pos.z).length() / THROW_XZ_SPEED
	# The consistency check. A clamped flight time with an unclamped landing point would imply an
	# unbounded arm — the projectile would teleport — so the arc ceiling refuses instead of lying.
	if flight <= 1e-6:
		return fail.call("already there")
	if flight > THROW_MAX_ARC:
		return fail.call("out of arc")
	var implied := Vector2(landing.x - from_pos.x, landing.z - from_pos.z).length() / flight
	if absf(implied - THROW_XZ_SPEED) > 0.25:
		return fail.call("out of arc")
	if absi(to_level - from_level) > 1:
		return fail.call("too many floors")
	# _get_movement_segments zeroes Y in every branch, so the solved point is on the y=0 plane
	# structurally. Derive the real height from the destination floor instead of trusting it.
	if grid:
		var cell := grid.world_to_grid(landing)
		landing.y = grid.grid_to_world(cell, to_level).y
		if not grid.has_throw_line(from_pos, landing):
			return fail.call("no line")
		if not grid.is_walkable(cell.x, cell.y, {}, {}, to_level):
			return fail.call("cannot land there")
	return {"ok": true, "reason": "", "landing": landing, "level": to_level, "flight": flight, "aim": aim}

## Solve, then delegate on success only. Emits nothing itself — throw_item does — so a refusal
## never enters the log. Both the GUI and the CLI converge here, so they refuse identically.
func command_throw_item(from_id: String, item_id: String, target_kind: String, target_ref) -> Dictionary:
	var solved := solve_throw(from_id, item_id, target_kind, target_ref)
	if not bool(solved["ok"]):
		return solved
	throw_item(item_id, from_id, solved["landing"], int(solved["level"]),
		float(solved["flight"]), String(solved["aim"]))
	return solved

## Emit FIRST, then validate — the house pattern shared with throw_physics_object and transfer_item.
## Validating first and emitting only on success makes live play and replay diverge the moment a
## refusal is timing-dependent, which for this verb is the normal case.
func throw_item(item_id: String, from_id: String, landing: Vector3, level: int,
		flight: float, aim: String = "") -> void:
	_emit(GameEvent.KIND_THROW_ITEM, {
		"item_id": item_id,
		"from": from_id,
		"landing": GameEvent.v3_to_arr(landing),
		"level": level,
		"flight": flight,
		"aim": aim,
	})
	if not items.has(item_id) or not characters.has(from_id):
		return
	var item: Dictionary = items[item_id]
	var origin := get_position(from_id)
	if characters.has(item.holder):
		_clear_item_from_hands(characters[item.holder], item_id)
	item.holder = ""
	item.location = "airborne"
	item.position = landing
	var now := float(scheduler.get_current_tick()) if scheduler else 0.0
	item["flight"] = {
		"from": Vector3(origin.x, origin.y, origin.z),
		"to": landing,
		"start_tick": now,
		"land_tick": now + flight,
		"level": level,
		"aim": aim,
	}
	if scheduler:
		scheduler.schedule_after(flight, func(): _on_item_landing(item_id), "throw_item_" + item_id)

## Derived, never a second logged event. The landing is a pure function of the logged throw plus the
## logged movements plus the tick, so replay reproduces it from the one record. A second event here
## would also fight event_log's monotonic-tick assert.
func _on_item_landing(item_id: String) -> void:
	if not items.has(item_id):
		return
	var item: Dictionary = items[item_id]
	if item.location != "airborne":
		return
	var rec: Dictionary = item.get("flight", {})
	var landing: Vector3 = rec.get("to", item.position)
	item.location = "ground"
	item.position = landing
	item.erase("flight")
	if grid:
		item["grid_cell"] = grid.world_to_grid(landing)
	# Auto-pickup is a CONVENIENCE layered on the ground landing, not a second outcome: the catcher
	# must be PARTY (register_character hands enemies empty hands too), close enough, and have room.
	var catcher := String(rec.get("aim", ""))
	if catcher == "" or not party_ids.has(catcher) or not characters.has(catcher):
		return
	if get_position(catcher).distance_to(landing) > THROW_CATCH_RADIUS:
		return
	var slots := _find_free_hand_slots(catcher, _required_hand_slots(item))
	if slots.is_empty():
		return
	var ch: Dictionary = characters[catcher]
	for slot in slots:
		ch.hands[int(slot)] = item_id
	item.holder = catcher
	item.location = "hand"

## Where an item is right now. Airborne evaluates the parabola from the scheduler tick, so a view
## that reads this is correct while paused, correct under hold-F, and correct after a save — the
## same reason movement interpolates by tick instead of integrating delta.
func get_item_position(item_id: String) -> Vector3:
	if not items.has(item_id):
		return Vector3.ZERO
	var item: Dictionary = items[item_id]
	if item.location == "hand" and characters.has(item.holder):
		return get_position(item.holder)
	if item.location != "airborne":
		return item.position
	var rec: Dictionary = item.get("flight", {})
	if rec.is_empty() or not scheduler:
		return item.position
	var t0 := float(rec["start_tick"])
	var t1 := float(rec["land_tick"])
	var span := maxf(1e-6, t1 - t0)
	var f := clampf((float(scheduler.get_current_tick()) - t0) / span, 0.0, 1.0)
	var a: Vector3 = rec["from"]
	var b: Vector3 = rec["to"]
	var pos := a.lerp(b, f)
	# y(t) = a.y + vy*t - 0.5*g*t^2, with vy chosen so y(span) == b.y. Apex is cosmetic.
	var t := f * span
	var vy := (b.y - a.y + 0.5 * PENDULUM_GRAVITY * span * span) / span
	pos.y = a.y + vy * t - 0.5 * PENDULUM_GRAVITY * t * t
	return pos

func endocytose_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_ENDOCYTOSE_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id) or not scheduler:
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "hand":
		return false
	if not bool(item.properties.get("endocytosis_allowed", ItemData.can_endocytose(item.type))):
		return false
	if _endocytosing.has(char_id):
		return false
	if is_dodging(char_id) or is_knocked_down(char_id) or is_downed(char_id) \
			or is_external_traversal_active(char_id) or is_dragging(char_id) \
			or is_resting(char_id) or is_field_restoring(char_id):
		return false
	_do_stop(char_id)
	var duration: float = item.properties.get("endocytosis_duration", ENDOCYTOSE_DEFAULT_DURATION)
	var end_tick := scheduler.get_current_tick() + duration
	var cid := char_id
	var iid := item_id
	var handle := scheduler.schedule_at(
		end_tick, func(): _complete_endocytosis(cid, iid), "endocytose_" + char_id)
	_endocytosing[char_id] = {
		"item_id": item_id, "end_tick": end_tick, "handle": handle,
	}
	return true

func cancel_endocytosis(char_id: String) -> void:
	_emit(GameEvent.KIND_CANCEL_ENDOCYTOSIS, {"char_id": char_id})
	if not _endocytosing.has(char_id):
		return
	var info: Dictionary = _endocytosing[char_id]
	if scheduler:
		scheduler.cancel(info.handle)
	_endocytosing.erase(char_id)

func is_endocytosing(char_id: String) -> bool:
	return _endocytosing.has(char_id)

func _complete_endocytosis(char_id: String, item_id: String) -> void:
	_endocytosing.erase(char_id)
	if not characters.has(char_id) or not items.has(item_id):
		return
	var item: Dictionary = items[item_id]
	var ch: Dictionary = characters[char_id]
	var effect := ItemData.get_endocytosis_effect(item.type)

	# Remove from hand
	_clear_item_from_hands(ch, item_id)

	match effect:
		"digest":
			var restore: float = normalize_atp(float(item.properties.get("atp_restore", 0.0)))
			var current_atp: float = normalize_atp(float(ch.stats.get("atp", 0.0)))
			var restored_atp := clamp_atp(current_atp + restore)
			ch.stats["atp"] = restored_atp
			# Endocytosis is already the logged transaction; publish its derived stat
			# mutation without creating a second command. HUD consumers and optional
			# scarcity clocks then observe the same authoritative refill immediately.
			stat_changed.emit(char_id, "atp", restored_atp)
			items.erase(item_id)
		"store":
			item.location = "internal"
			ch.internal.append(item_id)
			if item.properties.get("adds_to_collection", false) and item_id not in collection:
				collection.append(item_id)
		"stun_self":
			item.location = "internal"
			ch.internal.append(item_id)
		"scent_broadcast":
			item.location = "internal"
			ch.internal.append(item_id)
		"self_damage":
			var dmg: float = item.properties.get("damage", 0.0)
			var hp: float = ch.stats.get("hp", 100.0)
			ch.stats["hp"] = maxf(0.0, hp - dmg)
			items.erase(item_id)
		"stat_upgrade":
			var payload := ItemData.get_upgrade_payload(item.type)
			var locked_to: String = str(payload.get("locked_to", ""))
			if locked_to != "" and locked_to != char_id:
				# Wrong character; keep the item internally so it can be
				# transferred to whoever it's locked to. No upgrade applied.
				item.location = "internal"
				ch.internal.append(item_id)
			else:
				_apply_stat_upgrade(char_id, payload)
				items.erase(item_id)
		_:
			item.location = "internal"
			ch.internal.append(item_id)

	item_endocytosed.emit(char_id, item_id, effect)

func exocytose_item(char_id: String, item_id: String) -> bool:
	_emit(GameEvent.KIND_EXOCYTOSE_ITEM, {"char_id": char_id, "item_id": item_id})
	if not characters.has(char_id) or not items.has(item_id):
		return false
	if is_endocytosing(char_id):
		return false
	var item: Dictionary = items[item_id]
	if item.holder != char_id or item.location != "internal":
		return false
	var ch: Dictionary = characters[char_id]
	ch.internal.erase(item_id)
	var slots := _find_free_hand_slots(char_id, _required_hand_slots(item))
	if not slots.is_empty():
		for slot in slots:
			ch.hands[int(slot)] = item_id
		item.location = "hand"
	else:
		item.holder = ""
		item.location = "ground"
		item.position = get_position(char_id)
	item_exocytosed.emit(char_id, item_id)
	return true

func get_hand_items(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	var result := []
	for slot in characters[char_id].hands:
		if slot != null and not result.has(slot):
			result.append(slot)
	return result

func get_hand_slots(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	return characters[char_id].hands.duplicate()

func get_internal_items(char_id: String) -> Array:
	if not characters.has(char_id):
		return []
	return characters[char_id].internal.duplicate()

func has_free_hand(char_id: String) -> bool:
	return _find_free_hand(char_id) >= 0

func has_free_hands(char_id: String, required_slots := 1) -> bool:
	return not _find_free_hand_slots(char_id, required_slots).is_empty()

## Which party member should service an interaction (RTS right-click): the required character if the
## interactable names one and it's a candidate; otherwise the nearest candidate to the object — preferring
## ones with a free hand when the interaction picks something up. Pure/derived (reads positions +
## required_character only, never mutates), so it stays replay-safe and is NEVER logged. Deterministic:
## free-hand first, then distance, then char_id, so a tie always resolves the same way on replay.
func pick_interactor(required_char: String, target_pos: Vector3, candidates: Array, needs_free_hand := false) -> String:
	var pool: Array[String] = []
	for raw in candidates:
		var id := str(raw)
		# Downed bodies remain registered so they can be dragged/revived, but they cannot
		# service a queued interaction. Excluding them here prevents the nearest corpse
		# from owning a walk-to action that can never legitimately complete.
		if characters.has(id) and not is_downed(id) and not pool.has(id):
			pool.append(id)
	if pool.is_empty():
		return ""
	if required_char != "" and pool.has(required_char):
		return required_char
	var best := ""
	var best_penalty := 2
	var best_dist := INF
	for id in pool:
		var penalty := 1 if (needs_free_hand and not has_free_hands(id)) else 0
		var dist := get_position(id).distance_to(target_pos)
		if best == "" or penalty < best_penalty \
				or (penalty == best_penalty and dist < best_dist - 0.0001) \
				or (penalty == best_penalty and absf(dist - best_dist) <= 0.0001 and id < best):
			best = id
			best_penalty = penalty
			best_dist = dist
	return best

func _find_free_hand(char_id: String) -> int:
	if not characters.has(char_id):
		return -1
	var hands: Array = characters[char_id].hands
	for i in range(hands.size()):
		if hands[i] == null:
			return i
	return -1

func _find_free_hand_slots(char_id: String, required_slots: int) -> Array[int]:
	var slots: Array[int] = []
	if not characters.has(char_id):
		return slots
	for i in range(characters[char_id].hands.size()):
		if characters[char_id].hands[i] == null:
			slots.append(i)
			if slots.size() >= maxi(required_slots, 1):
				return slots
	return []

func _clear_item_from_hands(ch: Dictionary, item_id: String) -> void:
	for i in range(ch.hands.size()):
		if ch.hands[i] == item_id:
			ch.hands[i] = null

func _required_hand_slots(item: Dictionary) -> int:
	return maxi(int(item.get("properties", {}).get("hand_slots", ItemData.get_hand_slots(str(item.get("type", ""))))), 1)

func get_scent_radius(char_id: String) -> float:
	if not characters.has(char_id):
		return 0.0
	var radius := 0.0
	for item_id in get_hand_items(char_id):
		if items.has(item_id) and ItemData.has_scent(items[item_id].type):
			var sr: float = items[item_id].properties.get("scent_radius", 0.0)
			radius = maxf(radius, sr)
	for item_id in get_internal_items(char_id):
		if items.has(item_id) and ItemData.has_scent(items[item_id].type):
			var sr: float = items[item_id].properties.get("scent_radius", 0.0)
			radius = maxf(radius, sr)
	return radius

# --- Physics Objects ---

const PHYSICS_COLLISION_RADIUS := 0.4
const PHYSICS_DECELERATION := 3.0  # Units/sec² deceleration during slide (game-tuned)
const PHYSICS_RESTITUTION := 0.85

func register_physics_object(id: String, pos: Vector3, radius: float = 0.5, mass: float = 2.0, friction: float = 0.6, pushable: bool = true) -> void:
	_emit(GameEvent.KIND_REGISTER_PHYSICS_OBJECT, {
		"id": id,
		"pos": GameEvent.v3_to_arr(pos),
		"radius": radius,
		"mass": mass,
		"friction": friction,
		"pushable": pushable,
	})
	var cell := Vector2i.ZERO
	if grid:
		cell = grid.world_to_grid(pos)
	physics_objects[id] = {
		"position": pos,
		"radius": radius,
		"mass": mass,
		"friction": friction,
		"movement": null,
		"grid_cell": cell,
		"pushable": pushable,
	}
	# Pushable objects are NOT pathfinding blockers: walking through one is exactly how a push
	# happens (a blocker would make cell routing detour around it and pushing impossible).
	if grid and not pushable:
		grid.add_dynamic_blocker(cell, id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func unregister_physics_object(id: String) -> void:
	_emit(GameEvent.KIND_UNREGISTER_PHYSICS_OBJECT, {"id": id})
	if physics_objects.has(id):
		var obj: Dictionary = physics_objects[id]
		if obj.movement != null and scheduler:
			scheduler.cancel(obj.movement.handle)
		if grid:
			grid.remove_dynamic_blocker(obj.grid_cell)
	physics_objects.erase(id)
	_recompute_physics_predictions()

func get_physics_position(id: String) -> Vector3:
	if not physics_objects.has(id):
		return Vector3.ZERO
	var obj: Dictionary = physics_objects[id]
	if obj.movement == null or not scheduler:
		return obj.position
	var mv: Dictionary = obj.movement
	if mv.duration <= 0.0:
		return mv.path[mv.path.size() - 1]
	var t := clampf((scheduler.get_current_tick() - mv.start_tick) / mv.duration, 0.0, 1.0)
	var pos := _interpolate_path(mv.path, mv.cum_dist, t)
	if obj.has("throw") and obj.throw != null:
		var tw: Dictionary = obj.throw
		var dt: float = scheduler.get_current_tick() - tw.start_tick
		pos.y = tw.start_y + tw.vy * dt - 0.5 * PENDULUM_GRAVITY * dt * dt
		if pos.y < tw.ground_y:
			pos.y = tw.ground_y
	return pos

func is_physics_moving(id: String) -> bool:
	if not physics_objects.has(id):
		return false
	return physics_objects[id].movement != null

func is_physics_airborne(id: String) -> bool:
	if not physics_objects.has(id):
		return false
	var obj: Dictionary = physics_objects[id]
	return obj.has("throw") and obj.throw != null

func _get_physics_segments(id: String) -> Array[Dictionary]:
	var obj: Dictionary = physics_objects[id]
	if obj.movement == null:
		var pos: Vector3 = obj.position
		return [{"start_tick": 0.0, "end_tick": 1e12, "start_pos": Vector3(pos.x, 0, pos.z), "velocity": Vector3.ZERO}]
	var mv: Dictionary = obj.movement
	var segments: Array[Dictionary] = []
	for i in range(1, mv.path.size()):
		var seg_start_tick: float = mv.start_tick + (mv.cum_dist[i - 1] / mv.total_distance) * mv.duration
		var seg_end_tick: float = mv.start_tick + (mv.cum_dist[i] / mv.total_distance) * mv.duration
		var dir := Vector3(mv.path[i].x - mv.path[i - 1].x, 0, mv.path[i].z - mv.path[i - 1].z)
		var seg_len := dir.length()
		var speed: float = mv.total_distance / mv.duration if mv.duration > 0 else 0.0
		var vel: Vector3 = dir.normalized() * speed if seg_len > 0.001 else Vector3.ZERO
		segments.append({
			"start_tick": seg_start_tick,
			"end_tick": seg_end_tick,
			"start_pos": Vector3(mv.path[i - 1].x, 0, mv.path[i - 1].z),
			"velocity": vel,
		})
	return segments

func _get_velocity_at_tick(id: String, tick: float) -> Vector3:
	var segs: Array[Dictionary]
	if characters.has(id):
		segs = _get_movement_segments(id)
	elif physics_objects.has(id):
		segs = _get_physics_segments(id)
	else:
		return Vector3.ZERO
	for seg in segs:
		if tick >= seg.start_tick and tick < seg.end_tick:
			return seg.velocity
	return Vector3.ZERO

# --- Physics Collision Prediction ---

func _recompute_physics_predictions() -> void:
	var perf_started := PerformanceTrace.begin()
	if not scheduler:
		PerformanceTrace.end(&"update", &"game_state.recompute_physics", perf_started, "no_scheduler", 0)
		return
	scheduler.cancel_tag("physics_predict")
	var now := scheduler.get_current_tick()

	# Character vs PhysicsObject
	for char_id in characters:
		for obj_id in physics_objects:
			var obj: Dictionary = physics_objects[obj_id]
			var collision_range: float = PHYSICS_COLLISION_RADIUS + obj.radius
			var segs_c := _get_movement_segments(char_id)
			var segs_o := _get_physics_segments(obj_id)
			var t := _predict_collision_time(segs_c, segs_o, collision_range, now)
			# Normally skip a collision at (or within a hair of) the current tick — for a PUSHABLE object that
			# would otherwise re-fire a contact already being resolved on every recompute. But an AIRBORNE thrown
			# object hasn't landed yet (its `throw` stays live and clears only on impact via _on_throw_landing), so
			# an imminent strike that aliases the 0.01 guard must NOT be dropped: a recompute timed against contact
			# (e.g. a patrolling enemy re-issuing a move) cancels the pending physics_predict, and without this the
			# strike is lost and never re-fires (the barrel "passes through"). Clamp it just past `now` and still
			# fire it — the throw-landing dedup makes it strike exactly once.
			var obj_airborne: bool = obj.has("throw") and obj.throw != null
			if t >= 0.0 and (t > now + 0.01 or obj_airborne):
				var cid: String = char_id
				var oid: String = obj_id
				var sched_t: float = t if t > now + 0.01 else now + 0.0001
				scheduler.schedule_at(sched_t, func(): _on_physics_collision_event(oid, cid), "physics_predict")

	# PhysicsObject vs PhysicsObject
	var obj_ids := physics_objects.keys()
	for i in range(obj_ids.size()):
		for j in range(i + 1, obj_ids.size()):
			var id_a: String = obj_ids[i]
			var id_b: String = obj_ids[j]
			var collision_range: float = physics_objects[id_a].radius + physics_objects[id_b].radius
			var segs_a := _get_physics_segments(id_a)
			var segs_b := _get_physics_segments(id_b)
			var t := _predict_collision_time(segs_a, segs_b, collision_range, now)
			if t >= 0.0 and t > now + 0.01:
				var a := id_a
				var b := id_b
				scheduler.schedule_at(t, func(): _on_physics_obj_collision(a, b), "physics_predict")
	PerformanceTrace.end(
		&"update", &"game_state.recompute_physics", perf_started, "pairs",
		characters.size() * physics_objects.size() + (obj_ids.size() * (obj_ids.size() - 1)) / 2)

func _predict_collision_time(segs_a: Array[Dictionary], segs_b: Array[Dictionary], collision_range: float, now: float) -> float:
	var earliest := -1.0
	for seg_a in segs_a:
		for seg_b in segs_b:
			var t0: float = maxf(seg_a.start_tick, seg_b.start_tick)
			var t1: float = minf(seg_a.end_tick, seg_b.end_tick)
			if t0 >= t1:
				continue
			if t0 < now:
				t0 = now
			if t0 >= t1:
				continue
			var pos_a: Vector3 = seg_a.start_pos + (t0 - seg_a.start_tick) * seg_a.velocity
			var pos_b: Vector3 = seg_b.start_pos + (t0 - seg_b.start_tick) * seg_b.velocity
			var tau := _solve_quadratic_detection(pos_a, seg_a.velocity, pos_b, seg_b.velocity, collision_range, t1 - t0)
			if tau >= 0.0:
				var abs_t := t0 + tau
				if earliest < 0.0 or abs_t < earliest:
					earliest = abs_t
	return earliest

# --- Physics Collision Resolution ---

func _on_physics_collision_event(obj_id: String, collider_id: String) -> void:
	if not physics_objects.has(obj_id) or not characters.has(collider_id):
		return
	var obj: Dictionary = physics_objects[obj_id]

	# Airborne object hitting a character: emit signal and land, don't self-push
	if obj.has("throw") and obj.throw != null:
		var obj_vel := _get_velocity_at_tick(obj_id, scheduler.get_current_tick())
		physics_collision.emit(obj_id, collider_id, obj_vel)
		_on_throw_landing(obj_id)
		return

	if not obj.pushable:
		return

	var collider_pos := get_position(collider_id)
	var collider_vel := _get_velocity_at_tick(collider_id, scheduler.get_current_tick())

	var obj_pos := get_physics_position(obj_id)
	var obj_vel := _get_velocity_at_tick(obj_id, scheduler.get_current_tick())

	_resolve_physics_impulse(obj_id, obj_pos, obj_vel, collider_pos, collider_vel, obj)
	physics_collision.emit(obj_id, collider_id, Vector3.ZERO)

func _on_physics_obj_collision(id_a: String, id_b: String) -> void:
	if not physics_objects.has(id_a) or not physics_objects.has(id_b):
		return
	var obj_a: Dictionary = physics_objects[id_a]
	var obj_b: Dictionary = physics_objects[id_b]
	var pos_a := get_physics_position(id_a)
	var pos_b := get_physics_position(id_b)
	var vel_a := _get_velocity_at_tick(id_a, scheduler.get_current_tick())
	var vel_b := _get_velocity_at_tick(id_b, scheduler.get_current_tick())

	if obj_b.pushable:
		_resolve_physics_impulse(id_b, pos_b, vel_b, pos_a, vel_a, obj_b)
	if obj_a.pushable:
		_resolve_physics_impulse(id_a, pos_a, vel_a, pos_b, vel_b, obj_a)

func _resolve_physics_impulse(obj_id: String, obj_pos: Vector3, obj_vel: Vector3, collider_pos: Vector3, collider_vel: Vector3, obj: Dictionary) -> void:
	var push_dir := Vector3(obj_pos.x - collider_pos.x, 0, obj_pos.z - collider_pos.z)
	if push_dir.length_squared() < 0.001:
		push_dir = Vector3(1, 0, 0)
	push_dir = push_dir.normalized()

	var rel_vel := collider_vel - obj_vel
	var impact_speed := maxf(0.0, rel_vel.dot(push_dir))
	if impact_speed < 0.01:
		return

	var mass_ratio: float = 1.0 / obj.mass
	var impulse_speed: float = impact_speed * mass_ratio * PHYSICS_RESTITUTION

	var slide_distance: float = (impulse_speed * impulse_speed) / (2.0 * obj.friction * PHYSICS_DECELERATION)
	if slide_distance < 0.05:
		return

	var slide_target: Vector3 = obj_pos + push_dir * slide_distance

	# Temporarily remove own blocker so trace doesn't collide with self
	var own_cell: Vector2i = obj.grid_cell
	if grid:
		grid.remove_dynamic_blocker(own_cell)
	slide_target = _trace_slide_against_walls(obj_pos, slide_target)
	if grid and not obj.get("pushable", false):
		grid.add_dynamic_blocker(own_cell, obj_id)

	slide_distance = Vector3(slide_target.x - obj_pos.x, 0, slide_target.z - obj_pos.z).length()
	if slide_distance < 0.05:
		return

	_apply_physics_movement(obj_id, obj_pos, slide_target, impulse_speed)

func _trace_slide_against_walls(from: Vector3, to: Vector3) -> Vector3:
	if not grid:
		return to
	var dir := Vector3(to.x - from.x, 0, to.z - from.z)
	var dist := dir.length()
	if dist < 0.01:
		return from
	var step := dir.normalized() * grid.cell_size * 0.5
	var steps := int(dist / (grid.cell_size * 0.5)) + 1
	var pos := from
	for i in range(steps):
		var next := pos + step
		var cell := grid.world_to_grid(next)
		if not grid.is_walkable(cell.x, cell.y):
			return pos
		pos = next
	return to

func _apply_physics_movement(obj_id: String, from: Vector3, to: Vector3, initial_speed: float) -> void:
	var obj: Dictionary = physics_objects[obj_id]

	# Cancel existing movement
	if obj.movement != null and scheduler:
		scheduler.cancel(obj.movement.handle)
		if grid:
			grid.remove_dynamic_blocker(obj.grid_cell)

	var slide_dist := Vector3(to.x - from.x, 0, to.z - from.z).length()
	if slide_dist < 0.01:
		obj.position = from
		obj.movement = null
		if grid:
			obj.grid_cell = grid.world_to_grid(from)
			if not obj.get("pushable", false):
				grid.add_dynamic_blocker(obj.grid_cell, obj_id)
		return

	# Average speed during deceleration = initial_speed / 2
	var avg_speed := initial_speed * 0.5
	var duration := slide_dist / maxf(avg_speed, 0.1)
	var start_tick := scheduler.get_current_tick()
	var path: Array[Vector3] = [from, to]
	var cum_dist := _compute_cum_dist(path)

	var oid := obj_id
	var handle := scheduler.schedule_at(
		start_tick + duration,
		func(): _on_physics_arrival(oid),
		"physics_move_" + obj_id
	)

	obj.movement = {
		"path": path,
		"cum_dist": cum_dist,
		"total_distance": slide_dist,
		"start_tick": start_tick,
		"duration": duration,
		"handle": handle,
	}

	# Remove grid blocker while moving
	if grid:
		grid.remove_dynamic_blocker(obj.grid_cell)

	_recompute_physics_predictions()

func _on_physics_arrival(obj_id: String) -> void:
	if not physics_objects.has(obj_id):
		return
	var obj: Dictionary = physics_objects[obj_id]
	if obj.movement == null:
		return
	var dest: Vector3 = obj.movement.path[obj.movement.path.size() - 1]
	obj.position = dest
	obj.movement = null
	if grid:
		obj.grid_cell = grid.world_to_grid(dest)
		if not obj.get("pushable", false):
			grid.add_dynamic_blocker(obj.grid_cell, obj_id)
	_recompute_physics_predictions()

# --- Shelter rest (GDD 3.3) -------------------------------------------------
# Rest is the survival loop's sink: healing costs ATP, sleeping needs reserves, and the night
# only skips when every conscious character is bedded down at a shelter. The COMMANDS (rest /
# stop_rest / set_game_clock) are logged; the per-second healing chain, the ally revive timer,
# and the night skip are DERIVED from them (scheduler-driven, no-emit) so replay rebuilds them.

const REST_HP_PER_SEC := 1.0          # GDD: rest heals 1 HP/sec
const REST_STAMINA_PER_SEC := 4.0     # sleep refreshes stamina fast (free — the ATP pays for the HP)
const REST_SECONDS_PER_PIP := 25.0    # one ATP pip buys 25s of resting (~50 HP night = 2 pips)
const REVIVE_SECONDS := 10.0          # downed at shelter + conscious ally nearby -> auto revive
## A shelter revive must remain visibly RESTING for at least one scheduler beat
## before the all-resting night transition consumes the state at dawn.
const REVIVE_REST_VISIBLE_SECONDS := 1.0
const REVIVE_ALLY_RADIUS := 3.0
const REVIVE_HP := 1.0
const NIGHT_SKIP_MAX_HEAL := 50.0     # a full night of sleep heals up to this much
const RESTFUL_BONUS := 1.5            # nobody downed -> restful sleep multiplier
const NIGHT_START := 0.5              # time-of-day where night healing potential is full
const DAWN_TIME := 0.05

var game_day := 1
var game_time := 0.25                 # 0..1 time-of-day

var _shelters: Array = []             # [{min: Vector2, max: Vector2}] world-XZ rects (scene setup)
var _resting := {}                    # char_id -> {pip_seconds, next_tick}; authoritative while active
var _revive_progress := {}            # char_id -> float seconds - derived
var _revive_watch_running := false
var _revive_next_tick := 0.0

signal rest_started(char_id: String)
signal rest_stopped(char_id: String)
signal character_revived(char_id: String)
signal night_skipped(new_day: int)
signal game_clock_changed(day: int, time: float)

## Declare a shelter zone (world-XZ rect). Logged like interactable registration, so a replayed
## log rebuilds the zones the rest commands depend on.
func add_shelter_region(min_xz: Vector2, max_xz: Vector2) -> void:
	_emit(GameEvent.KIND_ADD_SHELTER, {"min": [min_xz.x, min_xz.y], "max": [max_xz.x, max_xz.y]})
	_shelters.append({"min": min_xz, "max": max_xz})
	_start_revive_watch()

func clear_shelter_regions() -> void:
	_shelters.clear()

func is_at_shelter(char_id: String) -> bool:
	if not characters.has(char_id):
		return false
	var p := get_position(char_id)
	for s in _shelters:
		if p.x >= s.min.x and p.x <= s.max.x and p.z >= s.min.y and p.z <= s.max.y:
			return true
	return false

func is_resting(char_id: String) -> bool:
	return _resting.has(char_id)

## Scripted day/night beats and the night skip set the clock; logged so replay carries time.
## With a day length set, this anchors the RUNNING clock at the current tick.
func set_game_clock(day: int, time: float) -> void:
	_emit(GameEvent.KIND_SET_GAME_CLOCK, {"day": day, "time": time})
	game_day = day
	game_time = clampf(time, 0.0, 1.0)
	_clock_base_tick = scheduler.get_current_tick() if scheduler else 0.0
	game_clock_changed.emit(game_day, game_time)

# --- The RUNNING day/night cycle -------------------------------------------
# Time of day is a PURE FUNCTION of the scheduler tick (base anchor + elapsed/day_length), so the
# cycle is fast-forward and replay invariant by construction. day_length 0 (the default) keeps the
# legacy scripted-beats behavior: time only moves when a beat sets it.

const DAY_PHASES := {"dawn": 0.05, "day": 0.12, "dusk": 0.42, "night": 0.55}
const REST_DEPRIVED_STAMINA_FACTOR := 0.6  # the brutal next day: stamina cap cut until they sleep

var day_length_seconds := 0.0
var _clock_base_tick := 0.0
var _rest_deprived := {}     # char_id -> true; persistent consequence of rollovers/skips
var _last_polled_day := 0
var _clock_next_poll_tick := 0.0

signal day_rolled_over(new_day: int)
signal rest_deprivation_changed(char_id: String, deprived: bool)

## Enable the running clock. Logged: replay must run the same cycle (the debuff derives from it).
func set_day_length(seconds: float) -> void:
	_emit(GameEvent.KIND_SET_DAY_LENGTH, {"seconds": seconds})
	day_length_seconds = maxf(0.0, seconds)
	_clock_base_tick = scheduler.get_current_tick() if scheduler else 0.0
	_last_polled_day = game_day
	if day_length_seconds > 0.0 and scheduler:
		scheduler.cancel_tag("game_clock_poll")
		_schedule_clock_poll()
	else:
		_clock_next_poll_tick = 0.0

func _schedule_clock_poll(delay: float = 0.5) -> void:
	if scheduler == null or day_length_seconds <= 0.0:
		_clock_next_poll_tick = 0.0
		return
	delay = maxf(0.000001, delay)
	_clock_next_poll_tick = scheduler.get_current_tick() + delay
	scheduler.schedule_after(delay, _on_clock_poll, "game_clock_poll")

## The live time of day [0..1): the anchored base plus scheduler time since the anchor.
func get_time_of_day() -> float:
	if day_length_seconds <= 0.0 or scheduler == null:
		return game_time
	var elapsed := (scheduler.get_current_tick() - _clock_base_tick) / day_length_seconds
	return fposmod(game_time + elapsed, 1.0)

func get_game_day() -> int:
	if day_length_seconds <= 0.0 or scheduler == null:
		return game_day
	var elapsed := (scheduler.get_current_tick() - _clock_base_tick) / day_length_seconds
	return game_day + int(floor(game_time + elapsed))

func get_day_phase() -> String:
	var t := get_time_of_day()
	if t < DAY_PHASES["dawn"] or t >= DAY_PHASES["night"]:
		return "night"
	if t < DAY_PHASES["day"]:
		return "dawn"
	if t < DAY_PHASES["dusk"]:
		return "day"
	return "dusk"

## A derived poll (scheduler-driven, so it pauses/fast-forwards with gameplay): detects the day
## ROLLING OVER without a night skip — everyone conscious who is not asleep at that moment
## carried through the night awake and wakes up rest-deprived.
func _on_clock_poll() -> void:
	if not scheduler or day_length_seconds <= 0.0:
		return
	var live_day := get_game_day()
	if live_day > _last_polled_day:
		_last_polled_day = live_day
		for char_id in characters.keys():
			var cid := str(char_id)
			if is_downed(cid) or _resting.has(cid):
				continue
			_set_rest_deprived(cid, true)
		_advance_flora_day()
		day_rolled_over.emit(live_day)
		game_clock_changed.emit(live_day, get_time_of_day())
	_schedule_clock_poll()

func is_rest_deprived(char_id: String) -> bool:
	return _rest_deprived.has(char_id)

func _set_rest_deprived(char_id: String, deprived: bool) -> void:
	var was := _rest_deprived.has(char_id)
	if deprived == was:
		return
	if deprived:
		_rest_deprived[char_id] = true
		# The cut cap clamps the CURRENT stamina too — the morning starts heavy.
		_apply_stat_delta(char_id, "stamina", 0.0)
		if get_stat(char_id, "stamina") > get_stat_cap(char_id, "stamina"):
			characters[char_id].stats["stamina"] = get_stat_cap(char_id, "stamina")
			stat_changed.emit(char_id, "stamina", get_stat_cap(char_id, "stamina"))
	else:
		_rest_deprived.erase(char_id)
	rest_deprivation_changed.emit(char_id, deprived)

## Begin resting at a shelter. Gates (GDD): must be AT a shelter, conscious, in need of HP or
## stamina recovery (or committing to the night), and able to afford sleep. One ATP pip buys
## REST_SECONDS_PER_PIP seconds, charged up front. Movement interrupts; daytime recovery stops
## when both HP and stamina are full, while a fully recovered night sleeper stays bedded down so
## the rest of the party can join and trigger the full-night skip.
func command_rest(char_id: String) -> bool:
	_emit(GameEvent.KIND_REST, {"char_id": char_id})
	return _do_rest(char_id)

## Commit one complete, already-settled roster to shelter rest. This is deliberately a separate
## command from repeated command_rest() calls: the latter expose a signal boundary after each ATP
## charge, allowing a signal-time save to contain a partially paid party. Here every mutable guard
## is checked first, then ATP and rest records are installed for the whole batch before any
## stat_changed/rest_started feedback is emitted. The single event gives replay the same boundary.
func command_party_rest(char_ids: Array) -> bool:
	var members := _normalize_party_rest_members(char_ids)
	if members.is_empty() or not _can_party_rest_members(members):
		return false
	_emit(GameEvent.KIND_PARTY_REST, {"char_ids": members.duplicate()})
	return _do_party_rest(members)


## Pure preflight used by exact authored shelters before they publish a committed transaction.
## Group rest requires parked bodies because stopping several active movement plans would itself
## expose movement/detection signal seams before the batch was fully installed.
func can_party_rest(char_ids: Array) -> bool:
	var members := _normalize_party_rest_members(char_ids)
	return not members.is_empty() and _can_party_rest_members(members)


func _normalize_party_rest_members(char_ids: Array) -> Array[String]:
	var members: Array[String] = []
	for char_id_v in char_ids:
		var char_id := str(char_id_v).strip_edges()
		if char_id.is_empty() or members.has(char_id):
			return []
		members.append(char_id)
	return members


func _can_party_rest_members(members: Array[String]) -> bool:
	if scheduler == null or members.is_empty():
		return false
	for char_id in members:
		# A member already solo-resting is NOT a refusal: every accepted member must be at
		# shelter anyway, and a solo rest inside the shelter YIELDS to the party rest (the
		# sanctuary-revive left them recovering — blocking the group bed-down on the very state
		# the player is asking for read as a contradiction). _do_party_rest absorbs it.
		if not characters.has(char_id) or is_moving(char_id) \
				or is_downed(char_id) or is_knocked_down(char_id) or is_dodging(char_id) \
				or is_endocytosing(char_id) or is_external_traversal_active(char_id) \
				or is_dragging(char_id) or is_field_restoring(char_id) \
				or not is_at_shelter(char_id):
			return false
		var hp_full := get_stat(char_id, "hp") >= get_stat_cap(char_id, "hp")
		var stamina_full := get_stat(char_id, "stamina") >= get_stat_cap(char_id, "stamina")
		if hp_full and stamina_full and get_time_of_day() < NIGHT_START:
			return false
		if get_stat(char_id, "atp") < 1.0:
			return false
	return true


func _do_party_rest(members: Array[String]) -> bool:
	# Replay dispatch reaches this method only after the recorded command has rebuilt the same guards.
	# Fail closed on a malformed/tampered event instead of charging a prefix.
	if not _can_party_rest_members(members):
		return false
	# THE ABSORB: a solo rest inside the shelter yields to the party rest. Stop it here, inside
	# the logged command's do-path, so replay reproduces the hand-off and recovery is accounted
	# once — by the batch.
	for absorb_id in members:
		if _resting.has(absorb_id):
			_stop_rest(absorb_id)
	var next_atp := {}
	for char_id in members:
		next_atp[char_id] = clampf(
			quantize_atp(get_stat(char_id, "atp") - 1.0),
			0.0,
			get_stat_cap(char_id, "atp")
		)

	# Authoritative batch mutation. No externally observable signal is emitted until every member
	# owns both the paid ATP value and a scheduled-rest record.
	for char_id in members:
		characters[char_id].stats["atp"] = float(next_atp[char_id])
		_resting[char_id] = {"pip_seconds": REST_SECONDS_PER_PIP, "next_tick": 0.0}
	for char_id in members:
		_schedule_rest_tick(char_id)

	if _party_rest_can_skip_night_atomically():
		_apply_atomic_restful_night_skip(members, next_atp)
	else:
		for char_id in members:
			stat_changed.emit(char_id, "atp", float(next_atp[char_id]))
			rest_started.emit(char_id)
	return true


func _party_rest_can_skip_night_atomically() -> bool:
	if get_time_of_day() < NIGHT_START or characters.is_empty():
		return false
	# The existing night-skip contract also handles downed-body shelter revival. Batch rest is the
	# conscious-roster path; refuse to collapse that distinct revive transaction into this helper.
	for char_id_v in characters.keys():
		var char_id := str(char_id_v)
		if is_downed(char_id) or not _resting.has(char_id):
			return false
	return true


func _apply_atomic_restful_night_skip(members: Array[String], next_atp: Dictionary) -> void:
	var night_remaining := clampf(
		(1.0 - get_time_of_day()) / (1.0 - NIGHT_START), 0.0, 1.0)
	var heal := NIGHT_SKIP_MAX_HEAL * night_remaining * RESTFUL_BONUS
	var previously_deprived: Array[String] = []
	var next_hp := {}
	var next_stamina := {}
	for char_id_v in characters.keys():
		var char_id := str(char_id_v)
		next_hp[char_id] = clampf(
			get_stat(char_id, "hp") + heal, 0.0, get_stat_cap(char_id, "hp"))
		next_stamina[char_id] = get_stat_cap(char_id, "stamina")
		if _rest_deprived.has(char_id):
			previously_deprived.append(char_id)

	# Complete the entire night result before the first feedback signal. A save made by any listener
	# therefore contains either the pre-command world or the complete paid dawn, never a half-party.
	for char_id_v in characters.keys():
		var char_id := str(char_id_v)
		characters[char_id].stats["hp"] = float(next_hp[char_id])
		characters[char_id].stats["stamina"] = float(next_stamina[char_id])
		_rest_deprived.erase(char_id)
		if scheduler != null:
			scheduler.cancel_tag("rest_" + char_id)
	_resting.clear()
	_advance_flora_day()
	game_day += 1
	game_time = DAWN_TIME
	_clock_base_tick = scheduler.get_current_tick() if scheduler else 0.0
	_last_polled_day = game_day

	for char_id in members:
		stat_changed.emit(char_id, "atp", float(next_atp[char_id]))
		rest_started.emit(char_id)
	for char_id_v in characters.keys():
		var char_id := str(char_id_v)
		stat_changed.emit(char_id, "hp", float(next_hp[char_id]))
		stat_changed.emit(char_id, "stamina", float(next_stamina[char_id]))
		if previously_deprived.has(char_id):
			rest_deprivation_changed.emit(char_id, false)
		rest_stopped.emit(char_id)
	game_clock_changed.emit(game_day, game_time)
	night_skipped.emit(game_day)


func _do_rest(
		char_id: String,
		check_night_skip := true,
		first_tick_delay := 1.0
	) -> bool:
	if not scheduler or not characters.has(char_id):
		return false
	if _resting.has(char_id) or is_downed(char_id) or is_knocked_down(char_id) \
			or is_dodging(char_id) or is_endocytosing(char_id) \
			or is_external_traversal_active(char_id) or is_dragging(char_id) \
			or is_field_restoring(char_id):
		return false
	if not is_at_shelter(char_id):
		return false
	var hp_full := get_stat(char_id, "hp") >= get_stat_cap(char_id, "hp")
	var stamina_full := get_stat(char_id, "stamina") >= get_stat_cap(char_id, "stamina")
	var committing_to_night := get_time_of_day() >= NIGHT_START
	if hp_full and stamina_full and not committing_to_night:
		return false
	if get_stat(char_id, "atp") < 1.0:
		return false  # too low to sleep - the Rain World gate
	_do_stop(char_id)
	_apply_stat_delta(char_id, "atp", -1.0)
	_resting[char_id] = {
		"pip_seconds": REST_SECONDS_PER_PIP,
		"next_tick": 0.0,
		# The revive path owns this one-shot flag. Other sleepers must not consume
		# its visible beat merely because their recurring ticks share the same time.
		"night_skip_on_tick": not check_night_skip,
	}
	rest_started.emit(char_id)
	_schedule_rest_tick(char_id, first_tick_delay)
	if check_night_skip:
		_check_night_skip()
	return true

func command_stop_rest(char_id: String) -> bool:
	_emit(GameEvent.KIND_STOP_REST, {"char_id": char_id})
	_stop_rest(char_id)
	return true

func _stop_rest(char_id: String) -> void:
	if not _resting.has(char_id):
		return
	_resting.erase(char_id)
	if scheduler:
		scheduler.cancel_tag("rest_" + char_id)
	rest_stopped.emit(char_id)

func _schedule_rest_tick(char_id: String, delay: float = 1.0) -> void:
	if scheduler == null or not _resting.has(char_id):
		return
	delay = maxf(0.000001, delay)
	var cid := char_id
	_resting[char_id]["next_tick"] = scheduler.get_current_tick() + delay
	scheduler.schedule_after(delay, func(): _on_rest_tick(cid), "rest_" + char_id)

## One second of sleep: +1 HP and +4 stamina, part of a pip. Derived - mutates via the no-emit path.
func _on_rest_tick(char_id: String) -> void:
	if not _resting.has(char_id) or not characters.has(char_id):
		return
	_apply_stat_delta(char_id, "hp", REST_HP_PER_SEC)
	_apply_stat_delta(char_id, "stamina", REST_STAMINA_PER_SEC)
	var state: Dictionary = _resting[char_id]
	state["pip_seconds"] = float(state["pip_seconds"]) - 1.0
	var fully_recovered := get_stat(char_id, "hp") >= get_stat_cap(char_id, "hp") \
		and get_stat(char_id, "stamina") >= get_stat_cap(char_id, "stamina")
	if fully_recovered and get_time_of_day() < NIGHT_START:
		_stop_rest(char_id)
		return
	if float(state["pip_seconds"]) <= 0.0:
		if get_stat(char_id, "atp") < 1.0:
			_stop_rest(char_id)  # can't pay for more sleep
			return
		_apply_stat_delta(char_id, "atp", -1.0)
		state["pip_seconds"] = REST_SECONDS_PER_PIP
	var check_night_after_visible_tick := bool(
		state.get("night_skip_on_tick", false))
	state["night_skip_on_tick"] = false
	_resting[char_id] = state
	if check_night_after_visible_tick:
		_check_night_skip()
		if not _resting.has(char_id):
			return
	_schedule_rest_tick(char_id)

## Derived stat mutation for scheduler-driven effects: replay re-derives these from the logged
## command that started the chain, so they must NOT log themselves.
func _apply_stat_delta(char_id: String, stat: String, delta: float) -> void:
	if not characters.has(char_id):
		return
	if stat == "hp" and delta < 0.0:
		delta = -_resolve_incoming_damage(char_id, -delta)
	var value: float = float(characters[char_id].stats.get(stat, 0.0)) + delta
	match stat:
		"hp":
			value = clampf(value, 0.0, get_stat_cap(char_id, "hp"))
		"atp":
			value = clampf(quantize_atp(value), 0.0, get_stat_cap(char_id, "atp"))
		"stamina":
			value = clampf(value, 0.0, get_stat_cap(char_id, "stamina"))
	characters[char_id].stats[stat] = value
	stat_changed.emit(char_id, stat, value)

# --- Field Restore (GDD: the late-game exception) ----------------------------
# Revive a downed character IN THE FIELD, no shelter: a long stationary cast with a high stamina
# price that leaves the caster vulnerable. The emergency alternative to the long drag home.

const FIELD_RESTORE_CAST_SECONDS := 8.0
const FIELD_RESTORE_STAMINA_COST := 60.0
const FIELD_RESTORE_RANGE := 2.0
const FIELD_RESTORE_CASTER := "oli"

var _field_restores := {}  # caster_id -> {target_id, end_tick}; authoritative while casting

signal field_restore_started(caster_id: String, target_id: String)
signal field_restore_finished(caster_id: String, target_id: String)
signal field_restore_interrupted(caster_id: String)

func is_field_restoring(caster_id: String) -> bool:
	return _field_restores.has(caster_id)

## Start the field revive. Gates: the target is DOWN and in reach, the caster is conscious,
## standing, and can pay the stamina up front (committing is the cost — an interrupted cast does
## not refund). The caster is rooted for the whole cast; moving or going down cancels it.
func command_field_restore(caster_id: String, target_id: String) -> bool:
	_emit(GameEvent.KIND_FIELD_RESTORE, {"caster_id": caster_id, "target_id": target_id})
	return _do_field_restore(caster_id, target_id)

func _do_field_restore(caster_id: String, target_id: String) -> bool:
	if not scheduler or not characters.has(caster_id) or not characters.has(target_id):
		return false
	# Restore is Oli's committed late-game field exception, not a generic party verb.
	# Keep authority at the simulation boundary so a scene cannot silently grant it
	# to whichever character happens to be active.
	if caster_id != FIELD_RESTORE_CASTER:
		return false
	if _field_restores.has(caster_id) or is_downed(caster_id) or is_knocked_down(caster_id) \
			or is_dodging(caster_id) or is_endocytosing(caster_id) \
			or is_external_traversal_active(caster_id) or is_dragging(caster_id):
		return false
	if not is_downed(target_id):
		return false
	if get_position(caster_id).distance_to(get_position(target_id)) > FIELD_RESTORE_RANGE:
		return false
	if get_stat(caster_id, "stamina") < FIELD_RESTORE_STAMINA_COST:
		return false
	_do_stop(caster_id)
	_stop_rest(caster_id)
	_apply_stat_delta(caster_id, "stamina", -FIELD_RESTORE_STAMINA_COST)
	var end_tick := scheduler.get_current_tick() + FIELD_RESTORE_CAST_SECONDS
	_field_restores[caster_id] = {"target_id": target_id, "end_tick": end_tick}
	var cid := caster_id
	scheduler.schedule_at(end_tick,
		func(): _on_field_restore_complete(cid), "field_restore_" + caster_id)
	field_restore_started.emit(caster_id, target_id)
	return true

func cancel_field_restore(caster_id: String) -> void:
	if not _field_restores.has(caster_id):
		return
	_field_restores.erase(caster_id)
	if scheduler:
		scheduler.cancel_tag("field_restore_" + caster_id)
	field_restore_interrupted.emit(caster_id)

## Derived completion: the target stands back up at 1 HP wherever they fell.
func _on_field_restore_complete(caster_id: String) -> void:
	var cast: Dictionary = _field_restores.get(caster_id, {})
	if cast.is_empty():
		return
	_field_restores.erase(caster_id)
	var target_id: String = cast["target_id"]
	if not characters.has(target_id) or not is_downed(target_id):
		return
	characters[target_id].stats["hp"] = REVIVE_HP
	characters[target_id].stats["narrative_available"] = true
	stat_changed.emit(target_id, "hp", REVIVE_HP)
	character_revived.emit(target_id)
	field_restore_finished.emit(caster_id, target_id)

# --- Revive at shelter: presence is sufficient (GDD) -------------------------

## The watch only runs while somebody is actually DOWN — an eternal 1s tick would keep the
## scheduler from ever draining (and burns work in every shelter scene for nothing).
func _start_revive_watch() -> void:
	if _revive_watch_running or not scheduler or _shelters.is_empty():
		return
	if not _any_character_downed():
		return
	_revive_watch_running = true
	_schedule_revive_watch_tick()

func _schedule_revive_watch_tick(delay: float = 1.0) -> void:
	if scheduler == null or not _revive_watch_running:
		_revive_next_tick = 0.0
		return
	delay = maxf(0.000001, delay)
	_revive_next_tick = scheduler.get_current_tick() + delay
	scheduler.schedule_after(delay, _on_revive_watch_tick, "shelter_revive_watch")

func _any_character_downed() -> bool:
	for char_id in characters.keys():
		if is_downed(str(char_id)):
			return true
	return false

## A 1s derived scan: every downed character AT a shelter with a conscious ally nearby gains
## revive progress; the ally stepping away resets it. At REVIVE_SECONDS: up at 1 HP, auto-rest.
func _on_revive_watch_tick() -> void:
	if not scheduler:
		_revive_watch_running = false
		_revive_next_tick = 0.0
		return
	for char_id in characters.keys():
		var cid := str(char_id)
		if not is_downed(cid) or not is_at_shelter(cid):
			_revive_progress.erase(cid)
			continue
		if not _conscious_ally_near(cid):
			_revive_progress.erase(cid)
			continue
		var progress: float = float(_revive_progress.get(cid, 0.0)) + 1.0
		if progress >= REVIVE_SECONDS:
			_revive_progress.erase(cid)
			_apply_revive(cid)
		else:
			_revive_progress[cid] = progress
	if _any_character_downed():
		_schedule_revive_watch_tick()
	else:
		_revive_watch_running = false
		_revive_next_tick = 0.0

func _conscious_ally_near(char_id: String) -> bool:
	var p := get_position(char_id)
	for other in characters.keys():
		var oid := str(other)
		if oid == char_id or is_downed(oid):
			continue
		if get_position(oid).distance_to(p) <= REVIVE_ALLY_RADIUS:
			return true
	return false

## Derived revive (no-emit): up at 1 HP, narratively available again, and straight into rest.
func _apply_revive(char_id: String) -> void:
	if not characters.has(char_id):
		return
	_end_drag_involving(char_id)   # they stand up out of any drag
	characters[char_id].stats["hp"] = REVIVE_HP
	characters[char_id].stats["narrative_available"] = true
	stat_changed.emit(char_id, "hp", REVIVE_HP)
	# Auto-rest is the canonical consequence of presence recovery. Start it
	# before announcing the revive so presentation consumers observe one coherent
	# "recovered and resting" receipt, then let the first rest tick consider dawn.
	_do_rest(char_id, false, REVIVE_REST_VISIBLE_SECONDS)
	character_revived.emit(char_id)

# --- Night skip --------------------------------------------------------------

## When EVERY conscious character is resting at a shelter after nightfall, the night skips to
## dawn. Healing scales with how much night remained when the last head hit the pillow; a party
## with nobody downed sleeps restfully (1.5x). Downed characters AT a shelter come up at 1 HP
## with half healing; downed characters left outside get nothing.
func _check_night_skip() -> void:
	if get_time_of_day() < NIGHT_START:
		return
	var conscious := 0
	var any_downed := false
	for char_id in characters.keys():
		var cid := str(char_id)
		if is_downed(cid):
			any_downed = true
			continue
		conscious += 1
		if not _resting.has(cid):
			return
	if conscious == 0:
		return
	var night_remaining: float = clampf((1.0 - get_time_of_day()) / (1.0 - NIGHT_START), 0.0, 1.0)
	var heal: float = NIGHT_SKIP_MAX_HEAL * night_remaining
	if not any_downed:
		heal *= RESTFUL_BONUS
	for char_id in characters.keys():
		var cid := str(char_id)
		if is_downed(cid):
			if is_at_shelter(cid):
				_apply_revive(cid)
				_stop_rest(cid)
				_apply_stat_delta(cid, "hp", heal * 0.5)
			continue
		_apply_stat_delta(cid, "hp", heal)
		# A night's sleep clears rest deprivation and means fresh legs: full (restored) stamina.
		_set_rest_deprived(cid, false)
		characters[cid].stats["stamina"] = get_stat_cap(cid, "stamina")
		stat_changed.emit(cid, "stamina", get_stat_cap(cid, "stamina"))
		_stop_rest(cid)
	_advance_flora_day()
	game_day += 1
	game_time = DAWN_TIME
	_clock_base_tick = scheduler.get_current_tick() if scheduler else 0.0
	_last_polled_day = game_day
	game_clock_changed.emit(game_day, game_time)
	night_skipped.emit(game_day)

# --- The floral network (GDD: flora tending / the mycelial information layer) ---------------
# Peris plants and tends bioluminescent growths. A growth TENDED during the day advances one
# stage at the day rollover (the living-world beat: return tomorrow and it has grown); untended
# growths hold. Species-authored growths may yield their canonical carried tool; generic growths
# do not manufacture healing items. Flourishing growths shed the most light (the night counter).
# Growths within FLORA_CONNECT_RADIUS of each other are
# one NETWORK — the mycelial layer that remembers (network ids are stable, derived, queryable).
# Commands are logged; growth advances derive from the logged tends + the tick-derived clock.

const FLORA_STAGES := ["planted", "sprouting", "established", "flourishing"]
const FLORA_LIGHT_RADIUS := [0.5, 1.5, 3.0, 5.0]   # per stage — the night-vision counter
const FLORA_CONNECT_RADIUS := 4.0                  # growths this close share a network
const FLORA_TEND_RANGE := 2.0
const FLORA_SITE_TOLERANCE := 0.1                  # one physical site; full 3D keeps stacked floors distinct
const FLORA_HARVEST_STAGE := 2                     # established+ growths yield
const FLORA_TENDER := "peris"                      # only Peris's hands grow things

var flora := {}              # flora_id -> {position, stage, tended_today, harvested_day, planted_day}
var _flora_seq := 0

signal flora_planted(flora_id: String)
signal flora_tended(flora_id: String)
signal flora_grew(flora_id: String, stage: int)
signal flora_harvested(flora_id: String, item_id: String)

## Plant a carried flora seed at a position. Gates: the tender (Peris), in reach of the spot,
## actually CARRYING a seed (hand or internal storage) — the seed is consumed.
func command_plant_flora(char_id: String, pos: Vector3) -> String:
	_emit(GameEvent.KIND_PLANT_FLORA, {"char_id": char_id, "pos": GameEvent.v3_to_arr(pos)})
	return _do_plant_flora(char_id, pos)

func _do_plant_flora(char_id: String, pos: Vector3) -> String:
	if char_id != FLORA_TENDER or not characters.has(char_id):
		return ""
	var char_pos := get_position(char_id)
	if Vector2(char_pos.x - pos.x, char_pos.z - pos.z).length() > FLORA_TEND_RANGE:
		return ""
	# Site occupancy is world truth, not a scene-pad convention. Sort IDs so a malformed legacy
	# overlap still has a stable identity, and reject before looking up/consuming the carried seed.
	if find_flora_at_site(pos) != "":
		return ""
	var seed_id := _find_carried_item(char_id, "flora_seed")
	if seed_id == "":
		return ""
	var seed_properties: Dictionary = (items.get(seed_id, {}) as Dictionary).get(
		"properties", {}).duplicate(true)
	_consume_item(char_id, seed_id)
	_flora_seq += 1
	var flora_id := "flora_%d" % _flora_seq
	flora[flora_id] = {
		"position": pos, "stage": 0, "tended_today": true,
		"harvested_day": -1, "planted_day": get_game_day(),
		# Preserve the consumed physical seed's identity across the flora signal/save boundary.
		# Scene-level pad authority can then reconcile a snapshot captured after consumption but
		# before its own presenter callback without guessing from position or plant type.
		"source_seed_id": seed_id,
		"species": str(seed_properties.get("flora_species", "")),
		"harvest_item_type": str(seed_properties.get("harvest_item_type", "")),
		"harvest_item_properties": (seed_properties.get(
			"harvest_item_properties", {}) as Dictionary).duplicate(true),
	}
	flora_planted.emit(flora_id)
	return flora_id


## Stable full-3D site identity. Two plants within tolerance are the same physical planting site;
## identical X/Z on genuinely different floors remains legal because their Y separation exceeds it.
func find_flora_at_site(pos: Vector3, tolerance := FLORA_SITE_TOLERANCE) -> String:
	var flora_ids := flora.keys()
	flora_ids.sort()
	var site_tolerance := maxf(float(tolerance), 0.0)
	for flora_id_v in flora_ids:
		var flora_id := str(flora_id_v)
		var growth: Dictionary = flora[flora_id]
		var growth_pos: Vector3 = growth.get("position", Vector3.INF)
		if growth_pos.distance_to(pos) <= site_tolerance:
			return flora_id
	return ""

## Tend a growth: it will advance one stage at the next day rollover. Re-tending after each
## rollover is the loop — an abandoned growth simply holds (or, later, gets colonized).
func command_tend_flora(char_id: String, flora_id: String) -> bool:
	_emit(GameEvent.KIND_TEND_FLORA, {"char_id": char_id, "flora_id": flora_id})
	if char_id != FLORA_TENDER or not flora.has(flora_id) or not characters.has(char_id):
		return false
	var growth: Dictionary = flora[flora_id]
	var char_pos := get_position(char_id)
	var fp: Vector3 = growth.position
	if Vector2(char_pos.x - fp.x, char_pos.z - fp.z).length() > FLORA_TEND_RANGE:
		return false
	growth["tended_today"] = true
	flora_tended.emit(flora_id)
	return true

## Harvest an established, species-authored growth. The seed owns the resulting item type and
## properties (for example, a Climbvine cutting or Gasafoetida pod); a generic decorative/network
## growth has no harvest. One yield per growth per day; harvesting never regresses growth.
func command_harvest_flora(char_id: String, flora_id: String) -> String:
	_emit(GameEvent.KIND_HARVEST_FLORA, {"char_id": char_id, "flora_id": flora_id})
	if char_id != FLORA_TENDER or not flora.has(flora_id) or not characters.has(char_id):
		return ""
	var growth: Dictionary = flora[flora_id]
	var harvest_item_type := str(growth.get("harvest_item_type", ""))
	if harvest_item_type == "":
		return ""
	if int(growth.stage) < FLORA_HARVEST_STAGE:
		return ""
	if int(growth.harvested_day) >= get_game_day():
		return ""
	var char_pos := get_position(char_id)
	var fp: Vector3 = growth.position
	if Vector2(char_pos.x - fp.x, char_pos.z - fp.z).length() > FLORA_TEND_RANGE:
		return ""
	growth["harvested_day"] = get_game_day()
	var harvest_properties: Dictionary = (growth.get(
		"harvest_item_properties", {}) as Dictionary).duplicate(true)
	var item_id := spawn_item(
		harvest_item_type, fp + Vector3(0.4, 0.0, 0.2), harvest_properties)
	flora_harvested.emit(flora_id, item_id)
	return item_id

## The day rollover advances every growth tended since the last one (called from BOTH day-advance
## paths: the running clock's rollover and the night skip). Derived — replay re-derives it from
## the logged tends and the tick-derived clock.
func _advance_flora_day() -> void:
	for flora_id in flora.keys():
		var growth: Dictionary = flora[flora_id]
		if bool(growth.tended_today) and int(growth.stage) < FLORA_STAGES.size() - 1:
			growth["stage"] = int(growth.stage) + 1
			flora_grew.emit(flora_id, int(growth.stage))
		growth["tended_today"] = false

func get_flora_stage(flora_id: String) -> int:
	return int(flora.get(flora_id, {}).get("stage", -1))

func get_flora_light_radius(flora_id: String) -> float:
	var stage := get_flora_stage(flora_id)
	return FLORA_LIGHT_RADIUS[stage] if stage >= 0 else 0.0

## The mycelial network: connected components over growths within FLORA_CONNECT_RADIUS. Network
## ids are the lexicographically-smallest member id — stable across queries and replays.
func get_flora_network(flora_id: String) -> Array:
	if not flora.has(flora_id):
		return []
	var member_ids := flora.keys()
	member_ids.sort()
	var component := [flora_id]
	var frontier := [flora_id]
	while not frontier.is_empty():
		var current: String = frontier.pop_back()
		var cp: Vector3 = flora[current].position
		for other in member_ids:
			if component.has(other):
				continue
			var op: Vector3 = flora[other].position
			if Vector2(cp.x - op.x, cp.z - op.z).length() <= FLORA_CONNECT_RADIUS:
				component.append(other)
				frontier.append(other)
	component.sort()
	return component

func get_flora_network_id(flora_id: String) -> String:
	var network := get_flora_network(flora_id)
	return network[0] if not network.is_empty() else ""

## The strongest light shed on a world position by any growth (the night-vision boost).
func get_flora_light_at(pos: Vector3) -> float:
	var best := 0.0
	for flora_id in flora:
		var fp: Vector3 = flora[flora_id].position
		var radius := get_flora_light_radius(str(flora_id))
		var dist := Vector2(pos.x - fp.x, pos.z - fp.z).length()
		if dist <= radius:
			best = maxf(best, 1.0 - dist / radius)
	return best

## A carried item of a type, in a hand or internal storage ('' when not carrying one).
## Read-only inventory query for world objects that need to gate an affordance on a
## specifically carried item. Mutating commands keep using the private helper so they
## can share the exact deterministic lookup without emitting a second event.
func find_carried_item(char_id: String, item_type: String) -> String:
	return _find_carried_item(char_id, item_type)


func _find_carried_item(char_id: String, item_type: String) -> String:
	var ch: Dictionary = characters[char_id]
	for slot in ch.hands:
		if slot != null and items.has(slot) and str(items[slot].type) == item_type:
			return str(slot)
	for stored in ch.internal:
		if items.has(stored) and str(items[stored].type) == item_type:
			return str(stored)
	return ""

func _consume_item(char_id: String, item_id: String) -> void:
	var ch: Dictionary = characters[char_id]
	for i in range(ch.hands.size()):
		if ch.hands[i] == item_id:
			ch.hands[i] = null
	ch.internal.erase(item_id)
	items.erase(item_id)

# --- Sokoban push (the deliberate, planned push: queue on the object, pick a destination) ---

const PUSH_STEP_TIME := 0.45  # scheduler seconds per one-cell shove

var _push_plans := {}  # char_id -> {obj_id, steps, index, stage("approach"|"shove")}; saveable plan

## Read-only: the plan a push to target_cell WOULD take (for ghost previews / the blocked cursor).
func plan_push_for(char_id: String, obj_id: String, target_cell: Vector2i) -> Dictionary:
	var perf_started := PerformanceTrace.begin()
	if not grid or not characters.has(char_id) or not physics_objects.has(obj_id):
		PerformanceTrace.end(&"nav", &"game_state.plan_push", perf_started, char_id, 0)
		return {}
	if not bool(physics_objects[obj_id].get("pushable", false)):
		PerformanceTrace.end(&"nav", &"game_state.plan_push", perf_started, char_id, 0)
		return {}
	var plan := grid.plan_push(
		grid.world_to_grid(get_physics_position(obj_id)),
		grid.world_to_grid(get_position(char_id)),
		target_cell, get_character_level(char_id),
		_pushable_cells_excluding(obj_id))
	PerformanceTrace.end(&"nav", &"game_state.plan_push", perf_started, char_id, (plan.get("steps", []) as Array).size())
	return plan

## Cells occupied by every OTHER pushable object. Pushables carry no standing grid blocker (that
## would make routing detour around them), so the push planner receives them as an explicit
## obstacle set: a crate is an obstacle to a crate — the plan routes around it or refuses.
func _pushable_cells_excluding(obj_id: String) -> Dictionary:
	var blocked := {}
	if not grid:
		return blocked
	for other_id_v in physics_objects.keys():
		var other_id := str(other_id_v)
		if other_id == obj_id:
			continue
		if not bool((physics_objects[other_id_v] as Dictionary).get("pushable", false)):
			continue
		blocked[grid.world_to_grid(get_physics_position(other_id))] = true
	return blocked

## Push the object to target_cell: the character walks behind it and shoves one cardinal cell at a
## time (re-positioning between direction changes), exactly the planner's step list. ONE logged
## command; the per-step walks/slides are derived and chain on arrivals — replay reproduces them.
## Returns false (nothing moves) when no plan exists: "not enough space" refuses the operation.
func command_push_object(char_id: String, obj_id: String, target_cell: Vector2i) -> bool:
	_emit(GameEvent.KIND_PUSH_OBJECT, {
		"char_id": char_id, "obj_id": obj_id, "cell": GameEvent.v2i_to_arr(target_cell),
	})
	return _do_push_object(char_id, obj_id, target_cell)

func _do_push_object(char_id: String, obj_id: String, target_cell: Vector2i) -> bool:
	if not scheduler or is_knocked_down(char_id):
		return false
	var plan := plan_push_for(char_id, obj_id, target_cell)
	if plan.is_empty():
		return false
	_cross_level_plan.erase(char_id)
	var steps: Array = plan.get("steps", [])
	if steps.is_empty():
		return true  # already at the target
	_push_plans[char_id] = {"obj_id": obj_id, "steps": steps, "index": 0, "stage": "approach"}
	if not character_arrived.is_connected(_on_push_char_arrived):
		character_arrived.connect(_on_push_char_arrived)
	_push_advance(char_id)
	return true

func is_pushing(char_id: String) -> bool:
	return _push_plans.has(char_id)

func cancel_push(char_id: String) -> void:
	_push_plans.erase(char_id)

## Drive the current step: approach = walk to the push cell (the object's own cell blocked for the
## route so the walk never cuts through it); then shove.
func _push_advance(char_id: String) -> void:
	var plan: Dictionary = _push_plans.get(char_id, {})
	if plan.is_empty():
		return
	var steps: Array = plan["steps"]
	var index: int = plan["index"]
	if index >= steps.size():
		_push_plans.erase(char_id)
		return
	var step: Dictionary = steps[index]
	var obj_id: String = plan["obj_id"]
	if not physics_objects.has(obj_id) or not characters.has(char_id):
		_push_plans.erase(char_id)
		return
	var push_cell: Vector2i = step["char_push_cell"]
	if grid.world_to_grid(get_position(char_id)) == push_cell:
		_push_shove(char_id)
		return
	var obj_cell: Vector2i = grid.world_to_grid(get_physics_position(obj_id))
	grid.add_dynamic_blocker(obj_cell, obj_id)
	var ok := _do_move_to_cell(char_id, push_cell)
	grid.remove_dynamic_blocker(obj_cell)
	if not ok:
		_push_plans.erase(char_id)

## Slide the object one cell at a constant pace (a controlled shove, not a friction skid) while the
## character steps into the object's old cell.
func _push_shove(char_id: String) -> void:
	var plan: Dictionary = _push_plans.get(char_id, {})
	if plan.is_empty():
		return
	var step: Dictionary = (plan["steps"] as Array)[plan["index"]]
	var obj_id: String = plan["obj_id"]
	# The plan was drawn against plan-time crate positions; if another crate has since arrived on
	# this step's destination, the shove is physically impossible — the push stops here.
	if _pushable_cells_excluding(obj_id).has(step["obj_to"] as Vector2i):
		_push_plans.erase(char_id)
		return
	var obj: Dictionary = physics_objects[obj_id]
	var from: Vector3 = get_physics_position(obj_id)
	var to: Vector3 = grid.grid_to_world(step["obj_to"], get_character_level(char_id))
	to.y = from.y
	if obj.movement != null and obj.movement.has("handle"):
		scheduler.cancel(obj.movement.handle)
	var oid := obj_id
	var handle := scheduler.schedule_at(scheduler.get_current_tick() + PUSH_STEP_TIME,
		func(): _on_physics_arrival(oid), "physics_move_" + obj_id)
	var slide_path: Array[Vector3] = [from, to]
	obj.movement = {
		"path": slide_path,
		"cum_dist": _compute_cum_dist(slide_path),
		"total_distance": Vector3(to.x - from.x, 0, to.z - from.z).length(),
		"start_tick": scheduler.get_current_tick(),
		"duration": PUSH_STEP_TIME,
		"handle": handle,
	}
	if grid:
		grid.remove_dynamic_blocker(obj.grid_cell)
	plan["stage"] = "shove"
	_push_plans[char_id] = plan
	_do_move_to_cell(char_id, step["obj_from"])
	_recompute_physics_predictions()

func _on_push_char_arrived(id: String) -> void:
	var plan: Dictionary = _push_plans.get(id, {})
	if plan.is_empty():
		return
	if plan["stage"] == "approach":
		_push_shove(id)
	else:
		plan["index"] = int(plan["index"]) + 1
		plan["stage"] = "approach"
		_push_plans[id] = plan
		_push_advance(id)

# --- Area Impulse ---

func apply_area_impulse(center: Vector3, radius: float, force: float) -> void:
	_emit(GameEvent.KIND_APPLY_AREA_IMPULSE, {
		"center": GameEvent.v3_to_arr(center),
		"radius": radius,
		"force": force,
	})
	for obj_id in physics_objects:
		var obj: Dictionary = physics_objects[obj_id]
		if not obj.pushable:
			continue
		var pos := get_physics_position(obj_id)
		var dx := pos.x - center.x
		var dz := pos.z - center.z
		var dist := sqrt(dx * dx + dz * dz)
		if dist < radius and dist > 0.01:
			var dir := Vector3(dx, 0, dz).normalized()
			var falloff := 1.0 - (dist / radius)
			var impulse_speed: float = force * falloff / obj.mass
			var slide_distance: float = (impulse_speed * impulse_speed) / (2.0 * obj.friction * PHYSICS_DECELERATION)
			if slide_distance < 0.05:
				continue
			var slide_target: Vector3 = pos + dir * slide_distance
			if grid:
				grid.remove_dynamic_blocker(obj.grid_cell)
			slide_target = _trace_slide_against_walls(pos, slide_target)
			if grid:
				grid.add_dynamic_blocker(obj.grid_cell, obj_id)
			slide_distance = Vector3(slide_target.x - pos.x, 0, slide_target.z - pos.z).length()
			if slide_distance >= 0.05:
				_apply_physics_movement(obj_id, pos, slide_target, impulse_speed)
				physics_collision.emit(obj_id, "", dir * impulse_speed)

# --- Throw Physics ---

func throw_physics_object(obj_id: String, velocity: Vector3, start_pos: Vector3 = Vector3.INF) -> void:
	_emit(GameEvent.KIND_THROW_PHYSICS_OBJECT, {
		"obj_id": obj_id,
		"velocity": GameEvent.v3_to_arr(velocity),
		"start_pos": GameEvent.v3_to_arr(start_pos),
	})
	if not physics_objects.has(obj_id) or not scheduler:
		return
	var obj: Dictionary = physics_objects[obj_id]
	var from: Vector3 = start_pos if start_pos != Vector3.INF else get_physics_position(obj_id)
	var ground_y := 0.0

	# Cancel existing movement
	if obj.movement != null:
		scheduler.cancel(obj.movement.handle)
		obj.movement = null
	if grid:
		grid.remove_dynamic_blocker(obj.grid_cell)

	# Compute flight time from vertical parabola: y = y0 + vy*t - 0.5*g*t²
	# Solve for y = ground_y: 0.5*g*t² - vy*t - (y0 - ground_y) = 0
	var y0: float = from.y
	var vy: float = velocity.y
	var flight_time: float
	if y0 <= ground_y and vy <= 0:
		flight_time = 0.0
	else:
		var a_coeff := 0.5 * PENDULUM_GRAVITY
		var b_coeff := -vy
		var c_coeff := -(y0 - ground_y)
		var disc := b_coeff * b_coeff - 4.0 * a_coeff * c_coeff
		if disc < 0:
			flight_time = 0.0
		else:
			var sqrt_disc := sqrt(disc)
			var t1: float = (-b_coeff + sqrt_disc) / (2.0 * a_coeff)
			var t2: float = (-b_coeff - sqrt_disc) / (2.0 * a_coeff)
			flight_time = maxf(t1, t2)
			if flight_time < 0.01:
				flight_time = 0.0

	if flight_time < 0.01:
		obj.position = Vector3(from.x, ground_y, from.z)
		obj.throw = null
		if grid:
			obj.grid_cell = grid.world_to_grid(obj.position)
			grid.add_dynamic_blocker(obj.grid_cell, obj_id)
		return

	# XZ: linear flight path
	var xz_vel := Vector3(velocity.x, 0, velocity.z)
	var landing_pos := Vector3(from.x + xz_vel.x * flight_time, ground_y, from.z + xz_vel.z * flight_time)

	# Trace XZ path against walls
	if grid:
		var traced := _trace_slide_against_walls(Vector3(from.x, 0, from.z), Vector3(landing_pos.x, 0, landing_pos.z))
		var traced_dist := Vector3(traced.x - from.x, 0, traced.z - from.z).length()
		var full_dist := Vector3(landing_pos.x - from.x, 0, landing_pos.z - from.z).length()
		if traced_dist < full_dist and full_dist > 0.01:
			var frac := traced_dist / full_dist
			flight_time *= frac
			landing_pos = Vector3(traced.x, ground_y, traced.z)

	# Set up throw parabola for Y
	var now := scheduler.get_current_tick()
	obj.throw = {
		"start_tick": now,
		"start_y": y0,
		"vy": vy,
		"ground_y": ground_y,
		"landing_tick": now + flight_time,
	}

	# Set up XZ movement (reuses existing path system)
	var xz_speed := xz_vel.length()
	var xz_from := Vector3(from.x, ground_y, from.z)
	var xz_to := Vector3(landing_pos.x, ground_y, landing_pos.z)
	var path: Array[Vector3] = [xz_from, xz_to]
	var cum_dist := _compute_cum_dist(path)
	var xz_dist: float = cum_dist[cum_dist.size() - 1]

	var oid := obj_id
	var handle := scheduler.schedule_at(
		now + flight_time,
		func(): _on_throw_landing(oid),
		"throw_" + obj_id
	)

	obj.movement = {
		"path": path,
		"cum_dist": cum_dist,
		"total_distance": xz_dist if xz_dist > 0.001 else 0.001,
		"start_tick": now,
		"duration": flight_time,
		"handle": handle,
	}

	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

## Throw a physics object to a target XZ location along an arc. Picks a launch
## velocity from a flight time (scaled with distance unless `arc_time` is given),
## then defers to throw_physics_object — which traces walls and drives the
## parabola off the scheduler tick, so it stays replay-deterministic. Returns
## false if the object isn't registered.
func throw_physics_object_to(obj_id: String, target: Vector3, arc_time: float = 0.0) -> bool:
	if not physics_objects.has(obj_id) or not scheduler:
		return false
	var from := get_physics_position(obj_id)
	var dx := target.x - from.x
	var dz := target.z - from.z
	var horizontal := Vector2(dx, dz).length()
	var t := arc_time
	if t <= 0.0:
		t = clampf(horizontal / 6.0, 0.45, 2.5)
	# y(t) = from.y + vy*t - 0.5*g*t² = target.y  → solve for vy.
	var vy := (target.y - from.y + 0.5 * PENDULUM_GRAVITY * t * t) / t
	throw_physics_object(obj_id, Vector3(dx / t, vy, dz / t), from)
	return true

func _on_throw_landing(obj_id: String) -> void:
	if not physics_objects.has(obj_id):
		return
	var obj: Dictionary = physics_objects[obj_id]
	var landing_pos := get_physics_position(obj_id)
	landing_pos.y = 0.0

	# Get XZ velocity at landing for post-bounce slide
	var xz_vel := _get_velocity_at_tick(obj_id, scheduler.get_current_tick())
	var xz_speed := xz_vel.length()

	# Clear throw and movement
	obj.throw = null
	obj.movement = null
	obj.position = landing_pos
	if grid:
		obj.grid_cell = grid.world_to_grid(landing_pos)

	# Convert remaining XZ velocity into a ground slide (reduced by bounce loss)
	var bounce_factor := 0.5
	var slide_speed := xz_speed * bounce_factor
	if slide_speed > 0.1 and obj.pushable:
		var slide_dir := xz_vel.normalized()
		var slide_distance: float = (slide_speed * slide_speed) / (2.0 * obj.friction * PHYSICS_DECELERATION)
		if slide_distance > 0.05:
			var slide_target: Vector3 = landing_pos + slide_dir * slide_distance
			var own_cell: Vector2i = obj.grid_cell
			if grid:
				grid.remove_dynamic_blocker(own_cell)
			slide_target = _trace_slide_against_walls(landing_pos, slide_target)
			if grid:
				grid.add_dynamic_blocker(own_cell, obj_id)
			slide_distance = Vector3(slide_target.x - landing_pos.x, 0, slide_target.z - landing_pos.z).length()
			if slide_distance >= 0.05:
				_apply_physics_movement(obj_id, landing_pos, slide_target, slide_speed)
				physics_collision.emit(obj_id, "", xz_vel * bounce_factor)
				return

	# No slide; settle in place.
	if grid:
		grid.add_dynamic_blocker(obj.grid_cell, obj_id)
	_recompute_physics_predictions()
	_recompute_pendulum_predictions()

func get_throw_height(id: String) -> float:
	if not physics_objects.has(id):
		return 0.0
	var obj: Dictionary = physics_objects[id]
	if not obj.has("throw") or obj.throw == null or not scheduler:
		return obj.position.y
	var tw: Dictionary = obj.throw
	var dt: float = scheduler.get_current_tick() - tw.start_tick
	var y: float = tw.start_y + tw.vy * dt - 0.5 * PENDULUM_GRAVITY * dt * dt
	return maxf(y, tw.ground_y)

func get_throw_peak_height(id: String) -> float:
	if not physics_objects.has(id):
		return 0.0
	var obj: Dictionary = physics_objects[id]
	if not obj.has("throw") or obj.throw == null:
		return 0.0
	var tw: Dictionary = obj.throw
	var vy: float = tw.vy
	if vy <= 0:
		return tw.start_y
	var t_peak := vy / PENDULUM_GRAVITY
	return tw.start_y + vy * t_peak - 0.5 * PENDULUM_GRAVITY * t_peak * t_peak

# --- Pendulums ---

const PENDULUM_GRAVITY := 9.8
const PENDULUM_SEGMENTS_PER_PERIOD := 12

func register_pendulum(id: String, anchor: Vector3, length: float, amplitude: float, swing_axis: Vector3 = Vector3.FORWARD, bob_radius: float = 0.4, phase: float = 0.0, damping: float = 0.0) -> void:
	_emit(GameEvent.KIND_REGISTER_PENDULUM, {
		"id": id,
		"anchor": GameEvent.v3_to_arr(anchor),
		"length": length,
		"amplitude": amplitude,
		"swing_axis": GameEvent.v3_to_arr(swing_axis),
		"bob_radius": bob_radius,
		"phase": phase,
		"damping": damping,
	})
	var start_tick := scheduler.get_current_tick() if scheduler else 0.0
	pendulums[id] = {
		"anchor": anchor,
		"length": length,
		"amplitude": amplitude,
		"phase": phase,
		"swing_axis": swing_axis.normalized(),
		"bob_radius": bob_radius,
		"damping": damping,
		"start_tick": start_tick,
	}
	_recompute_pendulum_predictions()

func unregister_pendulum(id: String) -> void:
	_emit(GameEvent.KIND_UNREGISTER_PENDULUM, {"id": id})
	pendulums.erase(id)
	if scheduler:
		scheduler.cancel_tag("pendulum_predict")

func get_pendulum_omega(id: String) -> float:
	if not pendulums.has(id):
		return 0.0
	var p: Dictionary = pendulums[id]
	return sqrt(PENDULUM_GRAVITY / p.length)

func get_pendulum_period(id: String) -> float:
	var omega := get_pendulum_omega(id)
	return TAU / omega if omega > 0.001 else 1.0

func get_pendulum_angle(id: String, tick: float = -1.0) -> float:
	if not pendulums.has(id):
		return 0.0
	var p: Dictionary = pendulums[id]
	if tick < 0.0:
		tick = scheduler.get_current_tick() if scheduler else 0.0
	var dt: float = tick - p.start_tick
	var omega := sqrt(PENDULUM_GRAVITY / p.length)
	var amp: float = p.amplitude
	if p.damping > 0.0 and dt > 0.0:
		amp *= exp(-p.damping * dt)
	return amp * cos(omega * dt + p.phase)

func get_pendulum_position(id: String, tick: float = -1.0) -> Vector3:
	if not pendulums.has(id):
		return Vector3.ZERO
	var p: Dictionary = pendulums[id]
	var theta := get_pendulum_angle(id, tick)
	var swing_dir := Vector3(-p.swing_axis.z, 0, p.swing_axis.x)
	var bob_offset: Vector3 = swing_dir * sin(theta) * p.length + Vector3(0, -cos(theta) * p.length, 0)
	return p.anchor + bob_offset

func get_pendulum_bob_velocity(id: String, tick: float = -1.0) -> Vector3:
	if not pendulums.has(id):
		return Vector3.ZERO
	var p: Dictionary = pendulums[id]
	if tick < 0.0:
		tick = scheduler.get_current_tick() if scheduler else 0.0
	var dt: float = tick - p.start_tick
	var omega := sqrt(PENDULUM_GRAVITY / p.length)
	var amp: float = p.amplitude
	if p.damping > 0.0 and dt > 0.0:
		amp *= exp(-p.damping * dt)
	var theta := amp * cos(omega * dt + p.phase)
	var dtheta := -amp * omega * sin(omega * dt + p.phase)
	var swing_dir := Vector3(-p.swing_axis.z, 0, p.swing_axis.x)
	var vx: Vector3 = swing_dir * cos(theta) * p.length * dtheta
	var vy := Vector3(0, sin(theta) * p.length * dtheta, 0)
	return vx + vy

# Decompose pendulum motion into linear segments for collision prediction
func _get_pendulum_segments(id: String, duration: float = -1.0) -> Array[Dictionary]:
	if not pendulums.has(id) or not scheduler:
		return []
	var p: Dictionary = pendulums[id]
	var omega := sqrt(PENDULUM_GRAVITY / p.length)
	var period := TAU / omega if omega > 0.001 else 1.0

	if duration < 0.0:
		# Look ahead 2 periods (or until fully damped)
		duration = period * 2.0
		if p.damping > 0.0:
			# Time until amplitude drops below 0.01 radians
			var decay_time := -log(0.01 / maxf(p.amplitude, 0.01)) / maxf(p.damping, 0.001)
			duration = minf(duration, decay_time)

	var now := scheduler.get_current_tick()
	var step := period / PENDULUM_SEGMENTS_PER_PERIOD
	var steps := int(duration / step) + 1
	var segments: Array[Dictionary] = []

	for i in range(steps):
		var t0 := now + i * step
		var t1 := now + (i + 1) * step
		var pos0 := get_pendulum_position(id, t0)
		var pos1 := get_pendulum_position(id, t1)
		var dt := t1 - t0
		var vel := Vector3((pos1.x - pos0.x) / dt, 0, (pos1.z - pos0.z) / dt) if dt > 0.001 else Vector3.ZERO
		segments.append({
			"start_tick": t0,
			"end_tick": t1,
			"start_pos": Vector3(pos0.x, 0, pos0.z),
			"velocity": vel,
		})

	return segments

func _recompute_pendulum_predictions() -> void:
	if not scheduler:
		return
	scheduler.cancel_tag("pendulum_predict")
	if pendulums.is_empty():
		return
	var now := scheduler.get_current_tick()

	for pend_id in pendulums:
		var p: Dictionary = pendulums[pend_id]
		var pend_segs := _get_pendulum_segments(pend_id)

		# Pendulum vs Characters
		for char_id in characters:
			var collision_range: float = PHYSICS_COLLISION_RADIUS + p.bob_radius
			var char_segs := _get_movement_segments(char_id)
			var t := _predict_collision_time(pend_segs, char_segs, collision_range, now)
			if t >= 0.0 and t > now + 0.01:
				var pid: String = pend_id
				var cid: String = char_id
				scheduler.schedule_at(t, func(): _on_pendulum_hit_character(pid, cid), "pendulum_predict")

		# Pendulum vs Physics Objects
		for obj_id in physics_objects:
			var obj: Dictionary = physics_objects[obj_id]
			var collision_range: float = obj.radius + p.bob_radius
			var obj_segs := _get_physics_segments(obj_id)
			var t := _predict_collision_time(pend_segs, obj_segs, collision_range, now)
			if t >= 0.0 and t > now + 0.01:
				var pid: String = pend_id
				var oid: String = obj_id
				scheduler.schedule_at(t, func(): _on_pendulum_hit_physics(pid, oid), "pendulum_predict")

func _on_pendulum_hit_character(pendulum_id: String, char_id: String) -> void:
	if not pendulums.has(pendulum_id) or not characters.has(char_id):
		return
	if is_dodging(char_id):
		return
	var bob_vel := get_pendulum_bob_velocity(pendulum_id)
	pendulum_hit.emit(pendulum_id, char_id, bob_vel)

func _on_pendulum_hit_physics(pendulum_id: String, obj_id: String) -> void:
	if not pendulums.has(pendulum_id) or not physics_objects.has(obj_id):
		return
	var obj: Dictionary = physics_objects[obj_id]
	if not obj.pushable:
		return
	var bob_vel := get_pendulum_bob_velocity(pendulum_id)
	var obj_pos := get_physics_position(obj_id)
	var bob_pos := get_pendulum_position(pendulum_id)
	_resolve_physics_impulse(obj_id, obj_pos, Vector3.ZERO, bob_pos, bob_vel, obj)
	pendulum_hit.emit(pendulum_id, obj_id, bob_vel)

# --- Replay ---
#
# Replay re-issues logged inputs at their original ticks.

## Build a fresh GameState by replaying a log. Canonical abilities are self-resolving; the optional
## ability_handlers map remains for legacy/modded callback abilities. re_record_into checks determinism.
static func replay(log: EventLog, world_grid: GridWorld, ability_handlers: Dictionary = {}, re_record_into: EventLog = null) -> GameState:
	var sched := EventScheduler.new()
	var gs := GameState.new()
	gs.grid = world_grid
	gs.scheduler = sched
	gs._recording = re_record_into != null
	gs.event_log = re_record_into
	gs.set_base_seed(log.base_seed)
	for id in ability_handlers:
		gs.register_ability_handler(StringName(id), ability_handlers[id])

	var prev_tick := 0.0
	for event in log.events:
		var tick: float = float(event["tick"])
		if tick > prev_tick:
			sched.advance_ticks(tick - prev_tick)
			prev_tick = tick
		gs._dispatch(StringName(event["kind"]), event["payload"])

	# Finish scheduler work that was pending when the log was saved.
	if log.recorded_until > prev_tick:
		sched.advance_ticks(log.recorded_until - prev_tick)

	gs._recording = true
	return gs

func _dispatch(kind: StringName, payload: Dictionary) -> void:
	match kind:
		GameEvent.KIND_REGISTER_CHARACTER:
			register_character(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["pos"]),
				float(payload.get("speed", 3.0)),
				payload.get("stats", {})
			)
		GameEvent.KIND_UNREGISTER_CHARACTER:
			unregister_character(String(payload["id"]))
		GameEvent.KIND_MOVE_TO_CELL:
			command_move_to_cell(String(payload["id"]), GameEvent.arr_to_v2i(payload["cell"]))
		GameEvent.KIND_MOVE_TO_POS:
			command_move_to_pos(String(payload["id"]), GameEvent.arr_to_v3(payload["pos"]))
		GameEvent.KIND_WALK_PATH:
			command_walk_path(String(payload["id"]), GameEvent.arr_to_path(payload["path"]))
		GameEvent.KIND_BEGIN_EXTERNAL_TRAVERSAL:
			# Preserve the exact recorded endpoints/ticks; deriving them again from a warped scene
			# would make replay presentation and save-state ownership diverge.
			_emit(GameEvent.KIND_BEGIN_EXTERNAL_TRAVERSAL, payload)
			_apply_external_traversal(payload)
		GameEvent.KIND_CANCEL_EXTERNAL_TRAVERSAL:
			_emit(GameEvent.KIND_CANCEL_EXTERNAL_TRAVERSAL, payload)
			_apply_cancel_external_traversal(payload)
		GameEvent.KIND_BEGIN_MECHANISM_PHASE:
			# Preserve recorded timing and metadata; a presenting scene may not exist during replay.
			_emit(GameEvent.KIND_BEGIN_MECHANISM_PHASE, payload)
			_apply_begin_mechanism_phase(payload)
		GameEvent.KIND_RESET_MECHANISM_PHASE:
			_emit(GameEvent.KIND_RESET_MECHANISM_PHASE, payload)
			_apply_reset_mechanism_phase(payload)
		GameEvent.KIND_STOP:
			command_stop(String(payload["id"]))
		GameEvent.KIND_CHANGE_SPEED:
			change_move_speed(String(payload["id"]), float(payload["speed"]))
		GameEvent.KIND_SET_ROUTE_MODE:
			set_route_mode(bool(payload["cautious"]))
		GameEvent.KIND_SET_STAT:
			set_stat(
				String(payload["id"]),
				String(payload["stat"]),
				float(payload["value"]),
				String(payload.get("source", ""))
			)
		GameEvent.KIND_SET_RUNNING:
			set_running(String(payload["id"]), bool(payload["running"]))
		GameEvent.KIND_ADD_SHELTER:
			add_shelter_region(
				Vector2(float(payload["min"][0]), float(payload["min"][1])),
				Vector2(float(payload["max"][0]), float(payload["max"][1])))
		GameEvent.KIND_FIELD_RESTORE:
			command_field_restore(String(payload["caster_id"]), String(payload["target_id"]))
		GameEvent.KIND_REST:
			command_rest(String(payload["char_id"]))
		GameEvent.KIND_PARTY_REST:
			command_party_rest(payload.get("char_ids", []) as Array)
		GameEvent.KIND_STOP_REST:
			command_stop_rest(String(payload["char_id"]))
		GameEvent.KIND_SET_GAME_CLOCK:
			set_game_clock(int(payload["day"]), float(payload["time"]))
		GameEvent.KIND_SET_DAY_LENGTH:
			set_day_length(float(payload["seconds"]))
		GameEvent.KIND_PLANT_FLORA:
			command_plant_flora(String(payload["char_id"]), GameEvent.arr_to_v3(payload["pos"]))
		GameEvent.KIND_TEND_FLORA:
			command_tend_flora(String(payload["char_id"]), String(payload["flora_id"]))
		GameEvent.KIND_HARVEST_FLORA:
			command_harvest_flora(String(payload["char_id"]), String(payload["flora_id"]))
		GameEvent.KIND_PUSH_OBJECT:
			command_push_object(
				String(payload["char_id"]), String(payload["obj_id"]),
				GameEvent.arr_to_v2i(payload["cell"]))
		GameEvent.KIND_SET_LEVEL:
			set_character_level(String(payload["id"]), int(payload["level"]))
		GameEvent.KIND_SNAP_POSITION:
			snap_character_to(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["pos"]),
				bool(payload.get("preserve_y", true)))
		GameEvent.KIND_MOVE_CROSS_LEVEL:
			command_move_cross_level(
				String(payload["id"]),
				GameEvent.arr_to_v2i(payload["cell"]),
				int(payload["level"])
			)
		GameEvent.KIND_SPAWN_ITEM:
			spawn_item(
				String(payload["type"]),
				GameEvent.arr_to_v3(payload["pos"]),
				payload.get("properties", {})
			)
		GameEvent.KIND_REMOVE_ITEM:
			remove_item(String(payload["item_id"]))
		GameEvent.KIND_PICK_UP_ITEM:
			pick_up_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_DROP_ITEM:
			drop_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_THROW_ITEM:
			throw_item(
				String(payload["item_id"]),
				String(payload["from"]),
				GameEvent.arr_to_v3(payload["landing"]),
				int(payload.get("level", 0)),
				float(payload["flight"]),
				String(payload.get("aim", ""))
			)
		GameEvent.KIND_TRANSFER_ITEM:
			transfer_item(
				String(payload["from_id"]),
				String(payload["to_id"]),
				String(payload["item_id"])
			)
		GameEvent.KIND_ENDOCYTOSE_ITEM:
			endocytose_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_CANCEL_ENDOCYTOSIS:
			cancel_endocytosis(String(payload["char_id"]))
		GameEvent.KIND_EXOCYTOSE_ITEM:
			exocytose_item(String(payload["char_id"]), String(payload["item_id"]))
		GameEvent.KIND_REGISTER_PHYSICS_OBJECT:
			register_physics_object(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["pos"]),
				float(payload.get("radius", 0.5)),
				float(payload.get("mass", 2.0)),
				float(payload.get("friction", 0.6)),
				bool(payload.get("pushable", true))
			)
		GameEvent.KIND_UNREGISTER_PHYSICS_OBJECT:
			unregister_physics_object(String(payload["id"]))
		GameEvent.KIND_THROW_PHYSICS_OBJECT:
			throw_physics_object(
				String(payload["obj_id"]),
				GameEvent.arr_to_v3(payload["velocity"]),
				GameEvent.arr_to_v3(payload["start_pos"])
			)
		GameEvent.KIND_APPLY_AREA_IMPULSE:
			apply_area_impulse(
				GameEvent.arr_to_v3(payload["center"]),
				float(payload["radius"]),
				float(payload["force"])
			)
		GameEvent.KIND_REGISTER_PENDULUM:
			register_pendulum(
				String(payload["id"]),
				GameEvent.arr_to_v3(payload["anchor"]),
				float(payload["length"]),
				float(payload["amplitude"]),
				GameEvent.arr_to_v3(payload.get("swing_axis", [0.0, 0.0, -1.0])),
				float(payload.get("bob_radius", 0.4)),
				float(payload.get("phase", 0.0)),
				float(payload.get("damping", 0.0))
			)
		GameEvent.KIND_UNREGISTER_PENDULUM:
			unregister_pendulum(String(payload["id"]))
		GameEvent.KIND_DODGE_ROLL:
			dodge_roll(String(payload["char_id"]), GameEvent.arr_to_v3(payload["direction"]))
		GameEvent.KIND_QUEUE_ABILITY:
			var ab_id := String(payload["ability"])
			var canonical: Dictionary = payload.get("canonical", {})
			if not canonical.is_empty():
				queue_canonical_ability(
					String(payload["char_id"]),
					ab_id,
					GameEvent.arr_to_v3(payload["target_pos"]),
					canonical)
			else:
				var handler: Callable = _ability_handlers.get(StringName(ab_id), Callable())
				if not handler.is_valid():
					handler = func(): pass
				queue_ability(
					String(payload["char_id"]),
					ab_id,
					GameEvent.arr_to_v3(payload["target_pos"]),
					float(payload["range"]),
					handler
				)
		GameEvent.KIND_CANCEL_QUEUED_ABILITY:
			cancel_queued_ability(String(payload["char_id"]))
		GameEvent.KIND_DOWN_CHARACTER:
			down_character(String(payload["char_id"]))
		GameEvent.KIND_START_DRAG:
			command_start_drag(String(payload["dragger"]), String(payload["downed"]))
		GameEvent.KIND_STOP_DRAG:
			command_stop_drag(String(payload["dragger"]))
		GameEvent.KIND_RESTORE_CHARACTER:
			restore_character(String(payload["char_id"]))
		GameEvent.KIND_DIE_SCRIPTED:
			die_scripted(String(payload["char_id"]))
		GameEvent.KIND_SET_PARTY:
			set_party(payload.get("members", []))
		GameEvent.KIND_PARTY_MOVE_TO_CELL:
			party_move_to_cell(GameEvent.arr_to_v2i(payload["cell"]))
		GameEvent.KIND_PARTY_MOVE_TO_POS:
			party_move_to_pos(GameEvent.arr_to_v3(payload["pos"]))
		GameEvent.KIND_RALLY_MEMBERS:
			# Formation slots were resolved when the command was recorded. Apply those exact
			# destinations instead of recomputing from the replay's current selection/occupancy.
			# A present route-cell constraint is part of the authoritative command. Malformed
			# replay data fails closed instead of silently degrading to an unrestricted Rally.
			var rally_constraint_v: Variant = payload.get("route_cell_constraint", {})
			if rally_constraint_v is Dictionary:
				_apply_rally_destinations(
					payload.get("members", []),
					GameEvent.arr_to_path(payload.get("destinations", [])),
					rally_constraint_v as Dictionary)
			else:
				push_warning("Rally event has a malformed route_cell_constraint")
		GameEvent.KIND_START_SPLIT:
			start_split(payload.get("members", []))
		GameEvent.KIND_END_SPLIT:
			end_split()
		GameEvent.KIND_REGISTER_INTERACTABLE:
			register_interactable(payload)
		GameEvent.KIND_UNREGISTER_INTERACTABLE:
			unregister_interactable(String(payload["id"]))
		GameEvent.KIND_TRIGGER_INTERACTABLE:
			trigger_interactable(String(payload["id"]), String(payload.get("character", "")))
		GameEvent.KIND_SET_INTERACTABLE_ENABLED:
			set_interactable_enabled(String(payload["id"]), bool(payload["enabled"]))
		GameEvent.KIND_RESET_INTERACTABLE:
			reset_interactable(String(payload["id"]))
		GameEvent.KIND_SET_WORLD_STATE:
			set_world_state(String(payload["key"]), payload["value"])
		_:
			push_warning("GameState._dispatch: unknown event kind %s" % kind)

# --- Party cohesion ---
#
# Party move commands address all non-split party members.

## Ordered party roster.
# Lateral spacing between members on a gridless party move (no cell spread available).
const _PARTY_GRIDLESS_SPACING := 1.0
## Optional serializable allow-list carried only by a Rally that needs to stay on a mechanism's
## permanent topology. Ordinary Rally and every later unrelated command omit it.
const RALLY_ALLOWED_CELLS_SCHEMA := "rally_allowed_cells_v1"
## Portable, node-free contract published by a visible world surface when a held
## Rally means "place the whole roster inside this authored region" rather than
## "spread around this one floor hit".  The region contains exact typed graph
## vertices; paths into it still use the ordinary full navigation graph.
const RALLY_FORMATION_REGION_CONTRACT := "rally_formation_region/v1"

var party: Array[String] = []
## Scripted split members ignored by party_move.
var _split_members: Array[String] = []

func set_party(members: Array) -> void:
	_emit(GameEvent.KIND_SET_PARTY, {"members": members.duplicate()})
	party.clear()
	for m in members:
		party.append(String(m))

func get_party() -> Array[String]:
	return party.duplicate()

func get_split_members() -> Array[String]:
	return _split_members.duplicate()

func is_split_active() -> bool:
	return not _split_members.is_empty()

## Party members currently controlled by party_move.
func _main_group() -> Array[String]:
	if _split_members.is_empty():
		return party.duplicate()
	var result: Array[String] = []
	for m in party:
		if not (m in _split_members):
			result.append(m)
	return result

func party_move_to_cell(cell: Vector2i) -> int:
	_warn_if_off_frame("party_move_to_cell", grid.grid_to_world(cell) if grid != null else Vector3(float(cell.x), 0.0, float(cell.y)))
	_emit(GameEvent.KIND_PARTY_MOVE_TO_CELL, {"cell": GameEvent.v2i_to_arr(cell)})
	var members := _main_group()
	for char_id in members:
		_cross_level_plan.erase(char_id)
	if grid:
		var assigned := _assign_party_cells(members, cell)
		var destinations: Array[Vector3] = []
		for char_id in members:
			var level := get_character_level(char_id) if characters.has(char_id) else 0
			destinations.append(grid.grid_to_world(assigned[char_id], level))
		# A party click is one simultaneous intent, just like Rally. Reuse the same
		# atomic reservation release and bounded start-wait planner so members can
		# convoy through a one-cell gate instead of treating siblings who are about
		# to leave as permanent blockers.
		return _apply_rally_destinations(members, destinations)
	return 0

func party_move_to_pos(pos: Vector3) -> int:
	_emit(GameEvent.KIND_PARTY_MOVE_TO_POS, {"pos": GameEvent.v3_to_arr(pos)})
	var members := _main_group()
	for char_id in members:
		_cross_level_plan.erase(char_id)
	var destinations: Array[Vector3] = []
	if grid:
		# Snap to the grid so the party spreads onto distinct cells around the
		# clicked point and moves cooperatively (no stacking, no overlap).
		var assigned := _assign_party_cells(members, grid.world_to_grid(pos))
		for char_id in members:
			var level := get_character_level(char_id) if characters.has(char_id) else 0
			destinations.append(grid.grid_to_world(assigned[char_id], level))
	else:
		# No grid (e.g. the elevator): cooperative cell spread isn't available, so fan
		# members out along Z around the target by party order — a pure function of the
		# index, so it stays deterministic / replay-safe — rather than stacking them.
		var count := members.size()
		for i in range(count):
			var lateral := (float(i) - float(count - 1) / 2.0) * _PARTY_GRIDLESS_SPACING
			destinations.append(pos + Vector3(0.0, 0.0, lateral))
	return _apply_rally_destinations(members, destinations)

## Move an explicit ordered set of characters into a deterministic formation around `target`.
## This deliberately does NOT read or mutate `party`: the caller owns the intended roster and any
## presentation-layer hold locks, while this command verifies that every supplied member is currently
## movement-available. A rally must not change portrait selection. `anchor_id` reserves the target's
## centre slot (and selects a ring formation when gridless). When that id is also a supplied member,
## it owns the centre destination and remains in the event; it is never removed from member_ids.
##
## The command records both the canonical member ids and their fully resolved destinations. Replay
## applies those destinations directly, so later selection, occupancy, or formation-rule changes cannot
## alter an already-recorded rally.
func command_rally_members(
		member_ids: Array,
		target: Vector3,
		anchor_id := "",
		route_cell_constraint: Dictionary = {}
	) -> int:
	var preflight := compute_rally_preflight(
		member_ids, target, str(anchor_id), route_cell_constraint)
	# A member who cannot reach the formation blocks only themselves (director ruling, 2026-08-06);
	# the rally still commits for everyone who can answer it, and the event records exactly those.
	# The blocked member is marked in the world instead, so the split is seen rather than silent.
	if not bool(preflight.get("accepted", false)):
		for raw_blocked in preflight.get("blocked_members", []):
			rally_member_blocked.emit(
				str(raw_blocked),
				(preflight.get("blocked_reasons", {}) as Dictionary).get(str(raw_blocked), {}))
		return 0
	for raw_blocked in preflight.get("blocked_members", []):
		rally_member_blocked.emit(
			str(raw_blocked),
			(preflight.get("blocked_reasons", {}) as Dictionary).get(str(raw_blocked), {}))
	var members: Array[String] = []
	for raw_id in preflight.get("members", []):
		members.append(str(raw_id))
	var destinations: Array[Vector3] = []
	for destination_v in preflight.get("destinations", []):
		if destination_v is Vector3:
			destinations.append(destination_v as Vector3)
	var canonical_constraint := preflight.get(
		"route_cell_constraint", {}) as Dictionary
	var payload := {
		"members": members.duplicate(),
		"target": GameEvent.v3_to_arr(target),
		"anchor_id": str(anchor_id),
		"destinations": GameEvent.path_to_arr(destinations),
	}
	if not canonical_constraint.is_empty():
		payload["route_cell_constraint"] = canonical_constraint.duplicate(true)
	_emit(GameEvent.KIND_RALLY_MEMBERS, payload)
	return _apply_rally_destinations(members, destinations, canonical_constraint)


## Commit one visible semantic-region Rally as the same atomic rally_members
## event used by ordinary ground Rally.  The portable region is validated again
## at release; only its already-resolved destinations are authoritative during
## replay, so no scene node or later graph query can change a recorded command.
func command_rally_members_to_region(
		member_ids: Array,
		formation_region: Dictionary
	) -> int:
	var preflight := compute_rally_region_preflight(
		member_ids, formation_region)
	if not bool(preflight.get("accepted", false)):
		return 0
	var members: Array[String] = []
	for raw_id in preflight.get("members", []):
		members.append(str(raw_id))
	var destinations: Array[Vector3] = []
	for destination_v in preflight.get("destinations", []):
		if destination_v is Vector3:
			destinations.append(destination_v as Vector3)
	var canonical_region := (
		preflight.get("formation_region", {}) as Dictionary).duplicate(true)
	var assigned_cells := (
		preflight.get("assigned_cells", []) as Array).duplicate(true)
	var target_v: Variant = preflight.get("target", Vector3.INF)
	var target := target_v as Vector3 \
		if target_v is Vector3 else Vector3.INF
	var payload := {
		"members": members.duplicate(),
		"target": GameEvent.v3_to_arr(target),
		"anchor_id": "",
		"destinations": GameEvent.path_to_arr(destinations),
		"formation_region": canonical_region,
		"formation_region_slots": assigned_cells,
	}
	_emit(GameEvent.KIND_RALLY_MEMBERS, payload)
	return _apply_rally_destinations(members, destinations)


## Read-only preview for a semantic formation surface.  Unlike
## route_cell_constraint, this restricts only the final parking slots: members
## may begin outside and traverse the normal connected graph (including typed
## ladder edges) to enter the region.
func compute_rally_region_preflight(
		member_ids: Array,
		formation_region: Dictionary
	) -> Dictionary:
	var members: Array[String] = []
	var seen_members: Dictionary = {}
	for raw_id in member_ids:
		var id := str(raw_id)
		if seen_members.has(id):
			continue
		seen_members[id] = true
		members.append(id)
	if members.is_empty():
		return _rally_preflight_refusal(
			members, [], "empty_roster", [], "NO VISIBLE PARTY")
	var canonical_region := _normalize_rally_formation_region(
		formation_region)
	if canonical_region.is_empty():
		return _rally_preflight_refusal(
			members, [], "invalid_formation_region", members,
			"RALLY REGION CHANGED")
	var cells := canonical_region.get("cells", []) as Array
	if cells.size() < members.size():
		var insufficient := _rally_preflight_refusal(
			members, [], "formation_region_too_small", members,
			"NO COMPLETE FORMATION")
		insufficient["formation_region"] = canonical_region.duplicate(true)
		return insufficient
	var approach := GameEvent.arr_to_v2i(
		canonical_region.get("approach_cell", []) as Array)
	var ordered_cells: Array[Vector2i] = []
	for cell_v in cells:
		ordered_cells.append(GameEvent.arr_to_v2i(cell_v as Array))
	ordered_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := a - approach
		var db := b - approach
		var distance_a := da.x * da.x + da.y * da.y
		var distance_b := db.x * db.x + db.y * db.y
		if distance_a != distance_b:
			return distance_a < distance_b
		return a.x < b.x if a.y == b.y else a.y < b.y
	)
	var level := int(canonical_region.get("authored_level", -1))
	var destinations: Array[Vector3] = []
	var assigned_cells: Array = []
	for member_index in range(members.size()):
		var assigned_cell := ordered_cells[member_index]
		destinations.append(grid.grid_to_world(assigned_cell, level))
		assigned_cells.append(GameEvent.v2i_to_arr(assigned_cell))
	var report := _rally_preflight_report_for_destinations(
		members, destinations)
	report["members"] = members.duplicate()
	report["destinations"] = destinations.duplicate()
	report["formation_region"] = canonical_region.duplicate(true)
	report["assigned_cells"] = assigned_cells
	report["target"] = grid.grid_to_world(approach, level)
	report["anchor_id"] = ""
	return report


## Resolve the visible region's causal centre without exposing scene identity.
## SelectionController stores this point in its immutable pointer receipt; the
## command still validates the full typed region at preview and release.
func get_rally_formation_region_target(
		formation_region: Dictionary
	) -> Vector3:
	var canonical := _normalize_rally_formation_region(formation_region)
	if canonical.is_empty():
		return Vector3.INF
	return grid.grid_to_world(
		GameEvent.arr_to_v2i(canonical.get("approach_cell", []) as Array),
		int(canonical.get("authored_level", -1)))


## Read-only public preview of the exact atomic Rally transaction. UI controllers use this same
## result for the held-command READY cue and formation paths; command_rally_members consumes it
## again at release. That keeps a green cue from advertising an Aster-only route that another
## visible portrait cannot actually traverse.
func compute_rally_preflight(
		member_ids: Array,
		target: Vector3,
		anchor_id := "",
		route_cell_constraint: Dictionary = {}
	) -> Dictionary:
	var members: Array[String] = []
	var seen_members: Dictionary = {}
	for raw_id in member_ids:
		var id := str(raw_id)
		if seen_members.has(id):
			continue
		seen_members[id] = true
		members.append(id)
	if members.is_empty():
		return _rally_preflight_refusal(
			members, [], "empty_roster", [], "NO VISIBLE PARTY")
	if not target.is_finite():
		return _rally_preflight_refusal(
			members, [], "invalid_target", members, "NO RALLY TARGET")
	var canonical_constraint := _normalize_rally_route_cell_constraint(
		route_cell_constraint)
	if not route_cell_constraint.is_empty() and canonical_constraint.is_empty():
		return _rally_preflight_refusal(
			members, [], "invalid_route_constraint", members,
			"ROUTE DATA CHANGED")
	var destinations: Array[Vector3] = compute_rally_destinations(
		members, target, str(anchor_id))
	var report := _rally_preflight_report_for_destinations(
		members, destinations, canonical_constraint)
	# `members` on an accepted report is the set that can actually answer the rally, which is not
	# necessarily the roster that was asked. Keep the request separately rather than overwriting it.
	report["requested_members"] = members.duplicate()
	report["requested_destinations"] = destinations.duplicate()
	if not report.has("members"):
		report["members"] = members.duplicate()
	if not report.has("destinations"):
		report["destinations"] = destinations.duplicate()
	report["target"] = target
	report["anchor_id"] = str(anchor_id)
	report["route_cell_constraint"] = canonical_constraint.duplicate(true)
	return report


## Read-only transaction guard for command_rally_members. Formation destinations have already been
## resolved, so checking each exact endpoint also guarantees that preview and commit use the same
## target level and typed ladder/ramp graph. Cooperative reservations are handled during application;
## this guard rejects permanent graph failures before any participant is prepared or logged.
func _rally_preflight_accepts(
		member_ids: Array[String],
		destinations: Array[Vector3],
		route_cell_constraint: Dictionary = {}
	) -> bool:
	return bool(_rally_preflight_report_for_destinations(
		member_ids, destinations, route_cell_constraint).get("accepted", false))


func _rally_preflight_report_for_destinations(
		member_ids: Array[String],
		destinations: Array[Vector3],
		route_cell_constraint: Dictionary = {}
	) -> Dictionary:
	if member_ids.is_empty() or member_ids.size() != destinations.size():
		return _rally_preflight_refusal(
			member_ids, destinations, "formation_mismatch", member_ids,
			"NO COMPLETE FORMATION")
	var allowed_cells: Dictionary = {}
	var constrained_level := -1
	if not route_cell_constraint.is_empty():
		var canonical := _normalize_rally_route_cell_constraint(route_cell_constraint)
		# Application/replay accepts only the canonical sorted, de-duplicated wire form.
		if canonical.is_empty() \
				or not _rally_route_constraint_is_canonical_wire(
					route_cell_constraint, canonical):
			return _rally_preflight_refusal(
				member_ids, destinations, "invalid_route_constraint", member_ids,
				"ROUTE DATA CHANGED")
		allowed_cells = _rally_route_allowed_cell_set(canonical)
		constrained_level = int(canonical.get("level", -1))
		if grid == null or allowed_cells.is_empty():
			return _rally_preflight_refusal(
				member_ids, destinations, "invalid_route_constraint", member_ids,
				"ROUTE DATA CHANGED")
	# The accepted report owns the exact render paths as well as the destinations.
	# Selection must never run a second, independently interpreted route query and
	# downgrade an accepted atomic command to BLOCKED (or advertise READY for a
	# route different from the one that release validates).
	# Director ruling (2026-08-06): a member who cannot reach the destination blocks ONLY THEMSELF.
	# The members who can route, go. Freezing the whole party because one of them is on another floor
	# reads as a dead click. The original worry behind the old all-or-nothing form was a party that
	# splits SILENTLY — that is answered by the blocked member being visibly marked (an X over their
	# head), not by refusing everyone.
	var preview_paths: Array = []
	var accepted_members: Array[String] = []
	var accepted_destinations: Array[Vector3] = []
	var blocked_members: Array[String] = []
	var blocked_reasons: Dictionary = {}
	var block := func(id: String, code: String, text: String) -> void:
		blocked_members.append(id)
		blocked_reasons[id] = {"reason_code": code, "reason": text}
	for member_index in range(member_ids.size()):
		var id := str(member_ids[member_index])
		var destination: Vector3 = destinations[member_index]
		if not characters.has(id):
			block.call(id, "missing_member", "%s IS NOT PRESENT" % id.to_upper())
			continue
		if not destination.is_finite():
			block.call(id, "invalid_destination", "NO FORMATION SLOT FOR %s" % id.to_upper())
			continue
		if not can_accept_move_command(id):
			block.call(id, "member_unavailable", "%s IS NOT READY" % id.to_upper())
			continue
		if grid != null:
			if not allowed_cells.is_empty():
				# Validate the occupied cell before the ordinary nearest-walkable start snap.
				# A body outside the mechanism's topology may not glide onto it for free.
				var start_cell := grid.world_to_grid(get_position(id))
				var destination_cell := grid.world_to_grid(destination)
				if get_character_level(id) != constrained_level \
						or grid.level_for_y(destination.y) != constrained_level \
						or not allowed_cells.has(start_cell) \
						or not allowed_cells.has(destination_cell) \
						or not grid.is_walkable(
							start_cell.x, start_cell.y, {}, {}, constrained_level) \
						or not grid.is_walkable(
							destination_cell.x, destination_cell.y, {}, {}, constrained_level):
					block.call(id, "constrained_endpoint_invalid",
						"%s IS OUTSIDE THE ROUTE" % id.to_upper())
					continue
				var constrained_path := grid.find_path(
					start_cell, destination_cell, {}, route_cautious, {}, {},
					constrained_level, allowed_cells)
				if constrained_path.is_empty():
					block.call(id, "route_missing", "NO COMPLETE ROUTE FOR %s" % id.to_upper())
					continue
				var constrained_preview: Array[Vector3] = [get_position(id)]
				constrained_preview.append_array(constrained_path)
				preview_paths.append(constrained_preview)
			else:
				# Party rally does not walk between floors -- cross-level movement is wired for a single
				# clicked character, not a party formation. A member standing on another deck therefore
				# cannot answer this rally, and blocks ONLY themselves; the rest still go.
				if grid.level_for_y(destination.y) != get_character_level(id):
					block.call(id, "different_level", "%s IS ON ANOTHER DECK" % id.to_upper())
					continue
				var navigation := compute_preview_navigation(id, destination)
				var member_preview: Array[Vector3] = []
				for point_v in (navigation.get("path", []) as Array):
					if point_v is Vector3:
						member_preview.append(point_v as Vector3)
				if navigation.is_empty() or member_preview.size() < 2:
					block.call(id, "route_missing", "NO COMPLETE ROUTE FOR %s" % id.to_upper())
					continue
				preview_paths.append(member_preview)
		else:
			preview_paths.append([get_position(id), destination])
		accepted_members.append(id)
		accepted_destinations.append(destination)
	# Only a rally that NOBODY can answer is a refused rally.
	if accepted_members.is_empty():
		var worst := str(blocked_reasons.get(
			blocked_members[0] if not blocked_members.is_empty() else "",
			{}).get("reason_code", "route_missing"))
		var worst_text := str(blocked_reasons.get(
			blocked_members[0] if not blocked_members.is_empty() else "",
			{}).get("reason", "NO COMPLETE PARTY ROUTE"))
		return _rally_preflight_refusal(
			member_ids, destinations, worst, blocked_members, worst_text)
	return {
		"accepted": true,
		"reason_code": "accepted" if blocked_members.is_empty() else "accepted_partial",
		"members": accepted_members.duplicate(),
		"destinations": accepted_destinations.duplicate(),
		"blocked_members": blocked_members.duplicate(),
		"blocked_reasons": blocked_reasons.duplicate(true),
		"reason": "",
		"paths": preview_paths,
	}


func _rally_preflight_refusal(
		member_ids: Array,
		destinations: Array,
		reason_code: String,
		blocked_members: Array,
		reason: String
	) -> Dictionary:
	var members: Array[String] = []
	for raw_id in member_ids:
		members.append(str(raw_id))
	var blocked: Array[String] = []
	for raw_id in blocked_members:
		blocked.append(str(raw_id))
	return {
		"accepted": false,
		"members": members,
		"destinations": destinations.duplicate(),
		"reason_code": reason_code,
		"blocked_members": blocked,
		"reason": reason,
		"paths": [],
		"route_cell_constraint": {},
	}


## Canonical JSON-safe validation for a surface-published formation region.
## Every accepted slot is an exact walkable vertex on one authored level, the
## approach vertex belongs to that set, and all slots are mutually connected
## inside the set.  A stale graph revision fails closed instead of letting the
## pointer silently fall through to an approximate ground spread.
func _normalize_rally_formation_region(raw: Dictionary) -> Dictionary:
	if grid == null or str(raw.get("contract_id", "")) \
			!= RALLY_FORMATION_REGION_CONTRACT:
		return {}
	var semantic_id := str(raw.get("semantic_id", "")).strip_edges()
	var level_v: Variant = raw.get("authored_level", null)
	var revision_v: Variant = raw.get("graph_revision", null)
	var approach_v: Variant = raw.get("approach_cell", null)
	var cells_v: Variant = raw.get("cells", null)
	if semantic_id.is_empty() \
			or not _rally_constraint_integral_number(level_v) \
			or not _rally_constraint_integral_number(revision_v) \
			or not (approach_v is Array) \
			or (approach_v as Array).size() != 2 \
			or not (cells_v is Array) or (cells_v as Array).is_empty():
		return {}
	var level := int(level_v)
	if level < 0 or level >= grid.level_count:
		return {}
	var current_revision := int(grid.get_path_walkability_revision()) \
		if grid.has_method("get_path_walkability_revision") else 0
	if int(revision_v) != current_revision:
		return {}
	for coordinate_v in approach_v as Array:
		if not _rally_constraint_integral_number(coordinate_v):
			return {}
	var approach := GameEvent.arr_to_v2i(approach_v as Array)
	var cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell_v in cells_v as Array:
		if not (cell_v is Array) or (cell_v as Array).size() != 2:
			return {}
		for coordinate_v in cell_v as Array:
			if not _rally_constraint_integral_number(coordinate_v):
				return {}
		var cell := GameEvent.arr_to_v2i(cell_v as Array)
		if seen.has(cell) or not grid.is_in_bounds(cell.x, cell.y) \
				or not grid.is_walkable(cell.x, cell.y, {}, {}, level):
			return {}
		seen[cell] = true
		cells.append(cell)
	if not seen.has(approach):
		return {}
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.y == b.y else a.y < b.y
	)
	var slot_policy := str(raw.get("slot_policy", "connected_region"))
	if slot_policy not in ["connected_region", "exact_hide_slots"]:
		return {}
	# Ordinary regions represent connected parking points, not a loose radius.
	# Exact hide slots are intentionally different: each vertex is the bodily
	# interior of a distinct Capbage and routes may cross the normal graph between
	# plants. They remain unique, walkable, revision-bound final destinations.
	var allowed_cells: Dictionary = {}
	for cell in cells:
		allowed_cells[cell] = true
	if slot_policy == "connected_region":
		for cell in cells:
			if cell == approach:
				continue
			var local_path := grid.find_path(
				approach, cell, {}, route_cautious, {}, {}, level, allowed_cells)
			if local_path.is_empty():
				return {}
	var encoded_cells: Array = []
	for cell in cells:
		encoded_cells.append(GameEvent.v2i_to_arr(cell))
	return {
		"contract_id": RALLY_FORMATION_REGION_CONTRACT,
		"semantic_id": semantic_id,
		"label": str(raw.get("label", "RALLY PARTY HERE")).strip_edges(),
		"slot_policy": slot_policy,
		"authored_level": level,
		"graph_revision": current_revision,
		"approach_cell": GameEvent.v2i_to_arr(approach),
		"cells": encoded_cells,
	}


## Canonicalize the optional Rally route allow-list to deterministic JSON-safe data. Callers may
## supply cells in any order; EventLog and replay see one sorted/deduplicated representation.
func _normalize_rally_route_cell_constraint(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	if str(raw.get("schema", "")) != RALLY_ALLOWED_CELLS_SCHEMA or grid == null:
		return {}
	var level_v: Variant = raw.get("level", null)
	var cells_v: Variant = raw.get("cells", null)
	if not _rally_constraint_integral_number(level_v) or not cells_v is Array:
		return {}
	var level := int(level_v)
	if level < 0 or level >= grid.level_count or (cells_v as Array).is_empty():
		return {}
	var cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell_v in cells_v as Array:
		if not cell_v is Array or (cell_v as Array).size() != 2:
			return {}
		var x_v: Variant = (cell_v as Array)[0]
		var z_v: Variant = (cell_v as Array)[1]
		if not _rally_constraint_integral_number(x_v) \
				or not _rally_constraint_integral_number(z_v):
			return {}
		var cell := Vector2i(int(x_v), int(z_v))
		if not grid.is_in_bounds(cell.x, cell.y):
			return {}
		if not seen.has(cell):
			seen[cell] = true
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.y == b.y else a.y < b.y)
	var encoded_cells: Array = []
	for cell in cells:
		encoded_cells.append(GameEvent.v2i_to_arr(cell))
	return {
		"schema": RALLY_ALLOWED_CELLS_SCHEMA,
		"level": level,
		"cells": encoded_cells,
	}


func _rally_constraint_integral_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] \
		and is_finite(float(value)) \
		and float(value) == floorf(float(value))


## JSON decodes numeric fields as floats on some paths. Preserve strict canonical ordering,
## duplicate elimination, key shape, and integral values without rejecting a valid 1 -> 1.0
## round trip solely for its Variant numeric representation.
func _rally_route_constraint_is_canonical_wire(
		raw: Dictionary,
		canonical: Dictionary
	) -> bool:
	if raw.size() != 3 or not raw.has("schema") or not raw.has("level") \
			or not raw.has("cells"):
		return false
	if str(raw.get("schema", "")) != str(canonical.get("schema", "")) \
			or not _rally_constraint_integral_number(raw.get("level", null)) \
			or int(raw.get("level", -1)) != int(canonical.get("level", -2)):
		return false
	var raw_cells_v: Variant = raw.get("cells", null)
	var canonical_cells := canonical.get("cells", []) as Array
	if not raw_cells_v is Array or (raw_cells_v as Array).size() != canonical_cells.size():
		return false
	for cell_index in range(canonical_cells.size()):
		var raw_cell_v: Variant = (raw_cells_v as Array)[cell_index]
		var canonical_cell := canonical_cells[cell_index] as Array
		if not raw_cell_v is Array or (raw_cell_v as Array).size() != 2:
			return false
		var raw_x: Variant = (raw_cell_v as Array)[0]
		var raw_z: Variant = (raw_cell_v as Array)[1]
		if not _rally_constraint_integral_number(raw_x) \
				or not _rally_constraint_integral_number(raw_z) \
				or int(raw_x) != int(canonical_cell[0]) \
				or int(raw_z) != int(canonical_cell[1]):
			return false
	return true


func _rally_route_allowed_cell_set(canonical_constraint: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	for cell_v in canonical_constraint.get("cells", []) as Array:
		if cell_v is Array and (cell_v as Array).size() == 2:
			allowed[GameEvent.arr_to_v2i(cell_v as Array)] = true
	return allowed


## Validate the exact geometry a planner is about to commit. Consecutive cell centres may be
## cardinal, diagonal, or repeated for a wait. A diagonal's two orthogonal supercover supports are
## part of the route even though they are not emitted as waypoints, so both must be allowed.
func _world_path_obeys_route_cell_constraint(
		world_path: Array,
		canonical_constraint: Dictionary
	) -> bool:
	if canonical_constraint.is_empty():
		return true
	if grid == null or world_path.is_empty():
		return false
	var allowed_cells := _rally_route_allowed_cell_set(canonical_constraint)
	var constrained_level := int(canonical_constraint.get("level", -1))
	var previous_cell := Vector2i.ZERO
	var has_previous := false
	for point_v in world_path:
		if not point_v is Vector3 or not (point_v as Vector3).is_finite() \
				or grid.level_for_y((point_v as Vector3).y) != constrained_level:
			return false
		var cell := grid.world_to_grid(point_v as Vector3)
		if not allowed_cells.has(cell):
			return false
		if has_previous:
			var delta := cell - previous_cell
			if absi(delta.x) > 1 or absi(delta.y) > 1:
				return false
			if delta.x != 0 and delta.y != 0:
				if not allowed_cells.has(previous_cell + Vector2i(delta.x, 0)) \
						or not allowed_cells.has(previous_cell + Vector2i(0, delta.y)):
					return false
		previous_cell = cell
		has_previous = true
	return true

## Pure/read-only formation resolver shared by command previews. Returns one destination per supplied
## id, in the same order, without filtering or de-duplicating the caller's list.
func compute_rally_destinations(member_ids: Array, target: Vector3, anchor_id := "") -> Array[Vector3]:
	var perf_started := PerformanceTrace.begin()
	var destinations: Array[Vector3] = []
	var count := member_ids.size()
	var anchor_member := str(anchor_id)
	var has_member_anchor := anchor_member != "" and member_ids.has(anchor_member)
	if count == 0:
		PerformanceTrace.end(&"nav", &"game_state.compute_rally_destinations", perf_started, "empty", 0)
		return destinations
	if grid != null:
		var target_cell := grid.world_to_grid(target)
		var target_level := grid.level_for_y(target.y)
		# A formation is a connected set of graph vertices, not merely N cells
		# that each happen to be walkable. Resolve one walkable component anchor
		# beneath the pointer, then keep every lateral slot in that same component.
		# Without this guard a ladder-edge Rally could place its second portrait on
		# a nearby but disconnected platform and reject the whole atomic command.
		var component_anchor := _nearest_free_cell(
			target_cell, {}, route_cautious, target_level)
		var taken: Dictionary = {}
		if anchor_member != "":
			taken[target_cell] = true
		var lateral_step := Vector2i.ZERO if anchor_member != "" \
			else _party_formation_lateral_step(member_ids, target_cell)
		var surrounding_index := 0
		for member_index in range(member_ids.size()):
			var member_id := str(member_ids[member_index])
			if has_member_anchor and member_id == anchor_member:
				# The release point can acquire a party body while the pointer is held.
				# Keep that body in the transaction and at its visible centre.
				destinations.append(target)
				continue
			# A cautious rally must keep every formation pill out of a known hazard,
			# not merely route the centre member around it.  The old resolver chose
			# adjacent walkable cells without consulting risk, so a safe target on
			# the edge of an iron field could place the second unit inside the field.
			var preferred_cell := target_cell + lateral_step \
				* _party_formation_lateral_offset(surrounding_index)
			var cell := _nearest_free_cell(
				preferred_cell, taken, route_cautious, target_level,
				component_anchor, true)
			taken[cell] = true
			destinations.append(grid.grid_to_world(cell, target_level))
			surrounding_index += 1
		PerformanceTrace.end(&"nav", &"game_state.compute_rally_destinations", perf_started, str(anchor_id), count)
		return destinations

	if anchor_member != "":
		var surrounding_count := count - 1 if has_member_anchor else count
		var surrounding_index := 0
		# An external anchor reserves the centre for another body. A member anchor owns it and only
		# the remaining Rally members occupy the surrounding ring.
		for raw_id in member_ids:
			if has_member_anchor and str(raw_id) == anchor_member:
				destinations.append(target)
				continue
			var angle := -PI * 0.5 + TAU * float(surrounding_index) \
				/ float(maxi(1, surrounding_count))
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * _PARTY_GRIDLESS_SPACING
			destinations.append(target + offset)
			surrounding_index += 1
	else:
		for i in range(count):
			var lateral := (float(i) - float(count - 1) / 2.0) * _PARTY_GRIDLESS_SPACING
			destinations.append(target + Vector3(0.0, 0.0, lateral))
	PerformanceTrace.end(&"nav", &"game_state.compute_rally_destinations", perf_started, str(anchor_id), count)
	return destinations

## Replay entry point: destinations are already final data-space positions and must not be spread again.
func _apply_rally_destinations(
		member_ids: Array,
		destinations: Array[Vector3],
		route_cell_constraint: Dictionary = {}
	) -> int:
	if member_ids.size() != destinations.size():
		push_warning("Rally event has %d members but %d destinations" % [member_ids.size(), destinations.size()])
		return 0
	var canonical_constraint := _normalize_rally_route_cell_constraint(route_cell_constraint)
	if not route_cell_constraint.is_empty() \
			and (canonical_constraint.is_empty() \
				or not _rally_route_constraint_is_canonical_wire(
					route_cell_constraint, canonical_constraint)):
		push_warning("Rally event has a malformed or noncanonical route_cell_constraint")
		return 0
	# Treat malformed or legacy duplicate-member payloads exactly like the canonical
	# command boundary: the first occurrence wins. Planning the same character twice
	# overwrites its movement record while leaving the first scheduler handle alive,
	# allowing that stale callback to finish the replacement route prematurely.
	var unique_members: Array[String] = []
	var unique_destinations: Array[Vector3] = []
	var seen_members: Dictionary = {}
	for i in range(member_ids.size()):
		var member_id := str(member_ids[i])
		if seen_members.has(member_id):
			continue
		seen_members[member_id] = true
		unique_members.append(member_id)
		unique_destinations.append(destinations[i])
	member_ids = unique_members
	destinations = unique_destinations
	# Revalidate a constrained event before cancelling a single old path/reservation. This protects
	# replay and direct application from partial movement if topology changed or the payload was forged.
	if not canonical_constraint.is_empty() \
			and not _rally_preflight_accepts(
				unique_members, unique_destinations, canonical_constraint):
		return 0
	# A Rally is one simultaneous intent. Retire every participating member's OLD
	# path/parked reservation before planning the first new route; otherwise that
	# first planner treats siblings who are about to leave as permanent blockers.
	# Keep the whole transaction in one detection batch, and preserve each
	# interpolated position before cancelling its old scheduler handle.
	var prepared: Dictionary = {}
	if grid != null:
		begin_detection_update_batch()
		prepared = _prepare_group_replan(member_ids)
	# Resolve the front of the formation first. If a rear/centre slot parks
	# before a farther slot is planned, the latter may be forced around its own
	# party through an exposed side route. Sorting only the synchronous planning
	# order (never the member/destination mapping) lets a formation flow through
	# a chokepoint from front to back while replay retains the exact same slots.
	var planning_indices: Array[int] = []
	for i in range(member_ids.size()):
		if grid == null or prepared.has(str(member_ids[i])):
			planning_indices.append(i)
	if grid != null and planning_indices.size() > 1:
		var origin_centroid := Vector3.ZERO
		var destination_centroid := Vector3.ZERO
		for i in planning_indices:
			origin_centroid += prepared[str(member_ids[i])] as Vector3
			destination_centroid += destinations[i]
		origin_centroid /= float(planning_indices.size())
		destination_centroid /= float(planning_indices.size())
		var approach := Vector2(
			destination_centroid.x - origin_centroid.x,
			destination_centroid.z - origin_centroid.z)
		if not approach.is_zero_approx():
			approach = approach.normalized()
			planning_indices.sort_custom(func(a: int, b: int) -> bool:
				var da: Vector3 = destinations[a]
				var db: Vector3 = destinations[b]
				var score_a := Vector2(da.x, da.z).dot(approach)
				var score_b := Vector2(db.x, db.z).dot(approach)
				return a < b if is_equal_approx(score_a, score_b) else score_a > score_b
			)
	# Non-movable ids were deliberately absent from `prepared`; append them only
	# so the ordinary guard path can reject them without disturbing valid plans.
	for i in range(member_ids.size()):
		if not planning_indices.has(i):
			planning_indices.append(i)
	var moved_count := 0
	var planned_prepared := 0
	for i in planning_indices:
		var id := str(member_ids[i])
		if grid == null:
			_prepare_explicit_move(id)
		var is_prepared := prepared.has(id)
		var allow_start_wait := is_prepared and planned_prepared > 0
		if _do_move_to_pos(
				id, destinations[i], allow_start_wait, is_prepared, canonical_constraint):
			moved_count += 1
			if is_prepared:
				planned_prepared += 1
	if grid != null:
		end_detection_update_batch()
	return moved_count

## Prepare an atomic group replan without choosing any destinations. Only valid,
## movable participants lose their old reservations; nonparticipants and
## temporarily immovable members retain theirs. Returns the pinned-position map
## so the caller can mark those members as already cancelled while planning.
func _prepare_group_replan(member_ids: Array) -> Dictionary:
	var prepared: Dictionary = {}
	for raw_id in member_ids:
		var id := str(raw_id)
		if prepared.has(id):
			continue
		_prepare_explicit_move(id)
		if not can_accept_move_command(id):
			continue
		prepared[id] = get_position(id)
	for id_variant in prepared.keys():
		var id := str(id_variant)
		var pinned_position: Vector3 = prepared[id]
		_cancel_movement(id)
		characters[id].position = pinned_position
		if grid != null:
			characters[id].grid_cell = grid.world_to_grid(pinned_position)
	# Releasing every obsolete path reservation must not make a departing body
	# disappear. Until each later member receives its replacement path, keep a
	# finite claim on its start cell for the physical time needed to leave it.
	# The member's own _start_movement replaces this provisional claim with its
	# exact path reservation. This lets the first planner route around siblings
	# without treating them as permanent parked blockers or crossing through them
	# during the first fraction of a simultaneous group command.
	if grid != null and scheduler != null:
		var now := float(scheduler.get_current_tick())
		for id_variant in prepared.keys():
			var id := str(id_variant)
			var start_position: Vector3 = prepared[id]
			var level := get_character_level(id)
			var start_cell := grid.world_to_grid(start_position)
			var start_center := grid.grid_to_world(start_cell, level)
			var speed := maxf(float(characters[id].move_speed), 0.001)
			var departure_seconds := start_position.distance_to(start_center) / speed \
				+ grid.cell_size / speed + _RESERVE_BUFFER
			_add_reservation(start_cell, now - _RESERVE_BUFFER,
				now + departure_seconds, id)
	if not prepared.is_empty():
		_performance_counters["group_replans"] = \
			int(_performance_counters["group_replans"]) + 1
		_performance_counters["group_replan_members"] = \
			int(_performance_counters["group_replan_members"]) + prepared.size()
	return prepared

## Give each party member a distinct, walkable destination cell around target so
## a single party move never stacks everyone on one cell. The order of members
## is deterministic (party order), so this replays and fast-forwards identically.
func _assign_party_cells(members: Array, target: Vector2i) -> Dictionary:
	var assigned: Dictionary = {}
	var taken: Dictionary = {}
	var component_anchor := _nearest_free_cell(target, taken)
	var lateral_step := _party_formation_lateral_step(members, target)
	for member_index in range(members.size()):
		var id = members[member_index]
		var preferred_cell := target + lateral_step \
			* _party_formation_lateral_offset(member_index)
		var cell := _nearest_free_cell(
			preferred_cell, taken, false, 0, component_anchor, true)
		assigned[id] = cell
		taken[cell] = true
	return assigned


## Three or more bodies should form across the direction of travel, not along it.
## Keeping launch and crossing slots on parallel lanes avoids needless path braids,
## cooperative start waits, and one member being routed through a hazard that the
## clicked centre line avoids.  Two-member Rally retains its convoy semantics.
func _party_formation_lateral_step(members: Array, target: Vector2i) -> Vector2i:
	if grid == null or members.size() < 3:
		return Vector2i.ZERO
	var centroid := Vector2.ZERO
	var counted := 0
	for raw_id in members:
		var id := str(raw_id)
		if not characters.has(id):
			continue
		var cell: Vector2i = grid.world_to_grid(get_position(id))
		centroid += Vector2(cell.x, cell.y)
		counted += 1
	if counted == 0:
		return Vector2i.ZERO
	centroid /= float(counted)
	var approach := Vector2(float(target.x), float(target.y)) - centroid
	if absf(approach.x) >= absf(approach.y):
		return Vector2i(0, 1)
	return Vector2i(1, 0)


func _party_formation_lateral_offset(member_index: int) -> int:
	if member_index <= 0:
		return 0
	var magnitude := int((member_index + 1) / 2)
	return -magnitude if member_index % 2 == 1 else magnitude

## Outward ring search from target for the closest walkable cell not already
## taken by another member. Deterministic tie-break by distance then coordinate.
func _nearest_free_cell(
		target: Vector2i,
		taken: Dictionary,
		avoid_risk := false,
		level := 0,
		component_anchor := Vector2i.ZERO,
		require_component := false
	) -> Vector2i:
	if _formation_cell_is_eligible(
			target, taken, avoid_risk, level,
			component_anchor, require_component):
		return target
	# Search the whole reachable extent (capped) so a large party on a big map
	# never falsely stacks just because a free cell sits past a fixed radius.
	var max_radius := mini(maxi(grid.width, grid.height), 24)
	for radius in range(1, max_radius + 1):
		var best := Vector2i.ZERO
		var found := false
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var c := target + Vector2i(dx, dz)
				if not _formation_cell_is_eligible(
						c, taken, avoid_risk, level,
						component_anchor, require_component):
					continue
				if not found or _ring_closer(c, best, target):
					best = c
					found = true
		if found:
			return best
	# No free cell anywhere in range (fewer walkable cells than members) —
	# stacking on the target is then physically unavoidable.
	return target


func _formation_cell_is_eligible(
		cell: Vector2i,
		taken: Dictionary,
		avoid_risk: bool,
		level: int,
		component_anchor: Vector2i,
		require_component: bool
	) -> bool:
	if taken.has(cell) or not grid.is_in_bounds(cell.x, cell.y) \
			or not grid.is_walkable(cell.x, cell.y, {}, {}, level) \
			or (avoid_risk and grid.is_cell_risky(cell)):
		return false
	if not require_component or cell == component_anchor:
		return true
	if not grid.is_in_bounds(component_anchor.x, component_anchor.y) \
			or not grid.is_walkable(
				component_anchor.x, component_anchor.y, {}, {}, level):
		return false
	return not grid.find_path(
		component_anchor, cell, {}, avoid_risk, {}, {}, level).is_empty()

func _ring_closer(c: Vector2i, best: Vector2i, target: Vector2i) -> bool:
	var dc := c - target
	var db := best - target
	var dist_c := dc.x * dc.x + dc.y * dc.y
	var dist_b := db.x * db.x + db.y * db.y
	if dist_c != dist_b:
		return dist_c < dist_b
	if c.x != best.x:
		return c.x < best.x
	return c.y < best.y

## Scripted split; not exposed to player input.
func start_split(members: Array) -> void:
	_emit(GameEvent.KIND_START_SPLIT, {"members": members.duplicate()})
	_split_members.clear()
	for m in members:
		var cid := String(m)
		if cid in party:
			_split_members.append(cid)

func end_split() -> void:
	_emit(GameEvent.KIND_END_SPLIT, {})
	_split_members.clear()

# Internal cell move without its own log entry.
func _do_move_to_cell(
		id: String,
		cell: Vector2i,
		allow_group_start_wait := false,
		already_prepared := false,
		route_cell_constraint: Dictionary = {}
	) -> bool:
	if not grid or not can_accept_move_command(id):
		return false
	var current_pos := get_position(id)
	var current_cell := grid.world_to_grid(current_pos)
	var speed: float = characters[id].move_speed
	if not already_prepared:
		begin_detection_update_batch()
		_cancel_movement(id)
	characters[id].position = current_pos
	characters[id].grid_cell = current_cell
	var moved := _begin_cooperative_move(
		id, current_pos, current_cell, cell, speed, allow_group_start_wait,
		route_cell_constraint)
	if not already_prepared:
		end_detection_update_batch()
	return moved

## Plan a cooperative path from current_cell to dest_cell (waiting/detouring to
## avoid other characters' reserved cell-time windows) and start it. Falls back
## to plain A* only when no conflict-free path exists within the search budget,
## so the character still moves (the fallback prioritizes liveness — it may
## briefly overlap another character). Assumes the caller already cancelled any
## prior movement and pinned characters[id].position to current_pos.
## Characters exempt from cooperative (space-time) planning: chase PACKS re-planning every rescan
## against five pack-mates' reservations drive the planner into deep wait-state searches — a 5 wu
## hop measured 30-90 ms mid-chase (the lockout chase's frame drops). An exempt character routes
## by plain A* and neither writes nor consults reservations; brief pack overlaps are the accepted
## trade (a mob is not a stealth puzzle). Derived state — set at spawn, never logged.
var _coop_exempt := {}

func set_coop_exempt(id: String, exempt := true) -> void:
	if exempt:
		_coop_exempt[id] = true
	else:
		_coop_exempt.erase(id)

func _begin_cooperative_move(
		id: String,
		current_pos: Vector3,
		current_cell: Vector2i,
		dest_cell: Vector2i,
		speed: float,
		allow_group_start_wait := false,
		route_cell_constraint: Dictionary = {}
	) -> bool:
	var perf_started := PerformanceTrace.begin()
	var level := get_character_level(id)  # keep waypoints on the character's current floor
	var allowed_cells: Dictionary = {}
	if not route_cell_constraint.is_empty():
		var canonical := _normalize_rally_route_cell_constraint(route_cell_constraint)
		if canonical.is_empty() \
				or not _rally_route_constraint_is_canonical_wire(
					route_cell_constraint, canonical) \
				or int(canonical.get("level", -1)) != level:
			PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, "bad_constraint", 0)
			return false
		route_cell_constraint = canonical
		allowed_cells = _rally_route_allowed_cell_set(canonical)
		# Check the raw occupied start before nearest_walkable_cell can repair it.
		if not allowed_cells.has(current_cell) or not allowed_cells.has(dest_cell) \
				or not grid.is_walkable(current_cell.x, current_cell.y, {}, {}, level) \
				or not grid.is_walkable(dest_cell.x, dest_cell.y, {}, {}, level):
			PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, "outside_constraint", 0)
			return false
	# A character parked off the carved footprint still routes: snap the START to the nearest walkable
	# cell (the glide from current_pos to the first cell center walks it onto the mesh).
	current_cell = grid.nearest_walkable_cell(current_cell, level)
	if _coop_exempt.has(id):
		_performance_counters["plain_plans"] = int(_performance_counters["plain_plans"]) + 1
		# snap the destination too — a plain A* to an unwalkable cell scans the whole reachable
		# region before failing (the residual spike)
		var dest_snapped := grid.nearest_walkable_cell(dest_cell, level)
		var plain := grid.find_path(
			current_cell, dest_snapped, {}, route_cautious, {}, {}, level, allowed_cells)
		if plain.is_empty():
			PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, id, 0)
			return false
		var plain_full: Array[Vector3] = [current_pos]
		plain_full.append_array(plain)
		if not _world_path_obeys_route_cell_constraint(
				plain_full, route_cell_constraint):
			PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started,
				"constraint_path_mismatch", 0)
			return false
		_start_movement(id, plain_full, [], route_cell_constraint)
		PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, id, plain_full.size())
		return true
	_performance_counters["cooperative_plans"] = int(_performance_counters["cooperative_plans"]) + 1
	var plan := _plan_cooperative(
		current_cell,
		dest_cell,
		speed,
		scheduler.get_current_tick(),
		id,
		level,
		_COOP_MAX_NODES,
		allow_group_start_wait,
		allowed_cells)
	if not plan.is_empty() and not plan.cells.is_empty():
		var built := _build_timed_world_path(current_pos, plan.cells, plan.ticks, speed, level)
		if not _world_path_obeys_route_cell_constraint(
				built.path, route_cell_constraint):
			PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started,
				"constraint_path_mismatch", 0)
			return false
		_start_movement(id, built.path, built.ticks, route_cell_constraint)
		PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, id, built.path.size())
		return true
	var path := grid.find_path(
		current_cell, dest_cell, {}, route_cautious, {}, {}, level, allowed_cells)
	if path.is_empty():
		_reserve_parked(id, current_cell)
		PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, id, 0)
		return false
	var full_path: Array[Vector3] = [current_pos]
	full_path.append_array(path)
	if not _world_path_obeys_route_cell_constraint(full_path, route_cell_constraint):
		_reserve_parked(id, current_cell)
		PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started,
			"constraint_path_mismatch", 0)
		return false
	_start_movement(id, full_path, [], route_cell_constraint)
	PerformanceTrace.end(&"nav", &"game_state.begin_move", perf_started, id, full_path.size())
	return true

# --- Narrative state transitions (downed / restored) ---
#
# Downed characters remain present but cannot speak, gate, or actuate.

signal character_downed(char_id: String)
signal character_restored(char_id: String)
## Permanent death signal; currently only scripted.
signal character_died(char_id: String, scripted: bool)

func down_character(char_id: String) -> void:
	_emit(GameEvent.KIND_DOWN_CHARACTER, {"char_id": char_id})
	if not characters.has(char_id):
		return
	_mark_downed(char_id)

## The ONE downed transition — scripted downs (down_character) and combat hp-0 (set_stat) both land
## here, so the state can never diverge by cause. They drop where they stood, dead weight until
## restored/revived; a downed caster drops the cast.
func _mark_downed(char_id: String) -> void:
	clear_damage_shield(char_id)
	_cancel_external_traversal_derived(char_id, &"incapacitated")
	var ch: Dictionary = characters[char_id]
	ch.stats["hp"] = 0.0
	ch.stats["stamina"] = 0.0
	ch.stats["narrative_available"] = false
	_end_drag_involving(char_id)   # a downed dragger drops the load where it is
	_do_stop(char_id)
	cancel_field_restore(char_id)
	_start_revive_watch()
	character_downed.emit(char_id)

func restore_character(char_id: String) -> void:
	_emit(GameEvent.KIND_RESTORE_CHARACTER, {"char_id": char_id})
	if not characters.has(char_id):
		return
	var ch: Dictionary = characters[char_id]
	var stats: Dictionary = ch.stats
	# Checkpoint/wipe reset, not shelter rest or food. HP and stamina put a
	# knocked-out character back in play; ATP is preserved because only lysate
	# replenishes the rest budget.
	# Legacy "max_hp"/"max_stamina" keys win if authored; otherwise the standard stat caps
	# (get_stat_cap honours "<stat>_max" overrides and the engine defaults) — a restore always
	# actually refills, never leaves a walking 0-hp character.
	stats["hp"] = float(stats["max_hp"]) if stats.has("max_hp") else get_stat_cap(char_id, "hp")
	stats["stamina"] = float(stats["max_stamina"]) if stats.has("max_stamina") else get_stat_cap(char_id, "stamina")
	stats["narrative_available"] = true
	_end_drag_involving(char_id)   # a restored character stands up out of any drag
	stat_changed.emit(char_id, "hp", float(stats["hp"]))
	stat_changed.emit(char_id, "stamina", float(stats["stamina"]))
	character_restored.emit(char_id)

func is_narratively_available(char_id: String) -> bool:
	if not characters.has(char_id):
		return false
	return bool(characters[char_id].stats.get("narrative_available", true))

func is_downed(char_id: String) -> bool:
	if not characters.has(char_id):
		return false
	return not bool(characters[char_id].stats.get("narrative_available", true))

## True when every listed party member is downed.
func is_party_downed(members: Array) -> bool:
	if members.is_empty():
		return false
	for char_id in members:
		if not is_downed(String(char_id)):
			return false
	return true

# --- Drag / retrieve (GDD 2.4.3) --------------------------------------------
#
# A knocked-out character is dead weight; a conscious member can take hold and haul them — moving
# slower and burning stamina while the load is actually moving. The body follows as a pure function
# of the dragger's position; setting it down parks it where it was carried. Dragging a fallen friend
# into a shelter is the RETRIEVE loop (the revive watch takes over from there).

const DRAG_SPEED_FACTOR := 0.55       # the dragger's move speed while hauling dead weight
const DRAG_PICKUP_RADIUS := 1.8       # how close the dragger must stand to take hold
const DRAG_STAMINA_PER_SEC := 4.0     # the extra burn while the load is moving
const DRAG_TICK := 0.5                # drain granularity (scheduler-driven, derived on replay)
const DRAG_TRAIL_OFFSET := Vector3(-0.45, 0.0, 0.4)   # the body trails just off the dragger's heel

signal drag_started(dragger_id: String, downed_id: String)
signal drag_stopped(dragger_id: String, downed_id: String)

var _drags := {}              # dragger_id -> downed_id; authoritative two-hand carry ownership
var _drag_prev_speed := {}    # dragger_id -> move_speed before the drag slowdown
var _drag_next_tick := {}     # dragger_id -> absolute scheduler tick for the next stamina charge

## Take hold of a downed character. Fails from too far away, for a downed/occupied dragger, or if
## either side is already part of a drag. Taking hold stops the dragger — the next move hauls.
func command_start_drag(dragger_id: String, downed_id: String) -> bool:
	if dragger_id == downed_id or not characters.has(dragger_id) or not characters.has(downed_id):
		return false
	if not is_downed(downed_id) or is_downed(dragger_id):
		return false
	if is_dragging(dragger_id) or get_dragger_of(downed_id) != "":
		return false
	if is_endocytosing(dragger_id) or is_knocked_down(dragger_id) \
			or is_dodging(dragger_id) or is_external_traversal_active(dragger_id) \
			or is_resting(dragger_id) or is_field_restoring(dragger_id):
		return false
	var dp := get_position(dragger_id)
	var bp := get_position(downed_id)
	if Vector2(dp.x - bp.x, dp.z - bp.z).length() > DRAG_PICKUP_RADIUS:
		return false
	# Dead weight is a TWO-HAND load: both hand slots must be free, and the carry occupies them
	# (no tools, no pickups, no transfers while hauling a friend).
	var carry_slots := _find_free_hand_slots(dragger_id, 2)
	if carry_slots.size() < 2:
		return false
	_emit(GameEvent.KIND_START_DRAG, {"dragger": dragger_id, "downed": downed_id})
	# Taking hold settles a runner into the haul: run drops FIRST so the drag multiplier applies to
	# the walk pace, never to a sprint that would smuggle dead weight at full speed.
	if is_running(dragger_id):
		set_running(dragger_id, false)
	_do_stop(dragger_id)
	_drags[dragger_id] = downed_id
	for slot in carry_slots:
		characters[dragger_id].hands[int(slot)] = _carry_hold_id(downed_id)
	_drag_prev_speed[dragger_id] = characters[dragger_id].move_speed
	characters[dragger_id].move_speed = float(characters[dragger_id].move_speed) * DRAG_SPEED_FACTOR
	_arm_drag_tick(dragger_id)
	drag_started.emit(dragger_id, downed_id)
	return true

## Set the load down where it is carried; the dragger's speed comes back.
func command_stop_drag(dragger_id: String) -> void:
	if not _drags.has(dragger_id):
		return
	_emit(GameEvent.KIND_STOP_DRAG, {"dragger": dragger_id})
	_end_drag_for(dragger_id)

func is_dragging(char_id: String) -> bool:
	return _drags.has(char_id)

func get_drag_target(dragger_id: String) -> String:
	return str(_drags.get(dragger_id, ""))

## The hand-slot sentinel while carrying a downed character. Not a real item: pick_up/drop/transfer
## all no-op on it, but get_hand_items surfaces it so the HUD shows the hands are full of friend.
func _carry_hold_id(downed_id: String) -> String:
	return "carry:" + downed_id

func get_dragger_of(downed_id: String) -> String:
	for k in _drags.keys():
		if str(_drags[k]) == downed_id:
			return str(k)
	return ""

## Shared teardown (explicit stop, dragger downed mid-haul, load revived/restored, unregister).
## Derived — the logged START/STOP/DOWN/RESTORE commands are the causes; replay re-derives it.
func _end_drag_for(dragger_id: String) -> void:
	if not _drags.has(dragger_id):
		return
	var downed_id := str(_drags[dragger_id])
	if characters.has(downed_id):
		characters[downed_id].position = get_position(downed_id)   # park the body where carried
	_drags.erase(dragger_id)
	if characters.has(dragger_id):
		_clear_item_from_hands(characters[dragger_id], _carry_hold_id(downed_id))
	if characters.has(dragger_id) and _drag_prev_speed.has(dragger_id):
		characters[dragger_id].move_speed = float(_drag_prev_speed[dragger_id])
	_drag_prev_speed.erase(dragger_id)
	_drag_next_tick.erase(dragger_id)
	if scheduler:
		scheduler.cancel_tag("drag_" + dragger_id)
	drag_stopped.emit(dragger_id, downed_id)

func _end_drag_involving(char_id: String) -> void:
	if _drags.has(char_id):
		_end_drag_for(char_id)
	var dragger := get_dragger_of(char_id)
	if dragger != "":
		_end_drag_for(dragger)

## The stamina burn rides the scheduler and only bites while the dragger is actually MOVING the
## load. Direct stat write + signal (derived, no log entry): replay re-arms this tick from the
## logged start-drag and re-derives the identical drain.
func _arm_drag_tick(dragger_id: String, delay: float = DRAG_TICK) -> void:
	if scheduler == null:
		return
	delay = maxf(0.000001, delay)
	_drag_next_tick[dragger_id] = scheduler.get_current_tick() + delay
	scheduler.schedule_after(delay, func(): _on_drag_tick(dragger_id), "drag_" + dragger_id)

func _on_drag_tick(dragger_id: String) -> void:
	if not _drags.has(dragger_id) or not characters.has(dragger_id):
		return
	if is_moving(dragger_id):
		var stats: Dictionary = characters[dragger_id].stats
		var next := maxf(0.0, float(stats.get("stamina", 0.0)) - DRAG_STAMINA_PER_SEC * DRAG_TICK)
		stats["stamina"] = next
		stat_changed.emit(dragger_id, "stamina", next)
	_arm_drag_tick(dragger_id)

## Permanent, scripted-only removal from the simulation.
func die_scripted(char_id: String) -> void:
	_emit(GameEvent.KIND_DIE_SCRIPTED, {"char_id": char_id})
	if not characters.has(char_id):
		return
	_cancel_external_traversal_derived(char_id, &"scripted_death")
	_do_stop(char_id)
	var ch: Dictionary = characters[char_id]
	ch.stats["hp"] = 0.0
	ch.stats["stamina"] = 0.0
	ch.stats["narrative_available"] = false
	ch.stats["dead"] = true
	character_died.emit(char_id, true)

# --- Mechanisms ---
#
# Mechanisms see only Actuator data.

func register_mechanism(m: Mechanism) -> void:
	mechanisms[m.id] = m

func unregister_mechanism(mech_id: StringName) -> void:
	mechanisms.erase(mech_id)

# Build actuator data from current actors, items, and physics objects.
func get_all_actuators() -> Array:
	var result: Array = []
	for char_id in characters:
		var ch: Dictionary = characters[char_id]
		var stats: Dictionary = ch.get("stats", {})
		var w: float = float(stats.get("weight", 1.0))
		var sig: StringName = StringName(str(stats.get("signature", "organic")))
		result.append(Actuator.make(get_position(char_id), w, sig))
	for item_id in items:
		var item: Dictionary = items[item_id]
		if item.get("location", "") != "ground":
			continue
		var props: Dictionary = item.get("properties", {})
		var w: float = float(props.get("weight", 0.0))
		var sig: StringName = StringName(str(props.get("signature", item.get("type", ""))))
		result.append(Actuator.make(item.get("position", Vector3.ZERO), w, sig))
	for obj_id in physics_objects:
		var obj: Dictionary = physics_objects[obj_id]
		var w: float = float(obj.get("mass", 0.0))
		var sig: StringName = StringName(str(obj.get("signature", "physics_object")))
		result.append(Actuator.make(get_physics_position(obj_id), w, sig))
	return result

func evaluate_mechanisms() -> void:
	if mechanisms.is_empty():
		return
	var actuators := get_all_actuators()
	for m_id in mechanisms:
		mechanisms[m_id].update(actuators)

# --- Interactables (data layer) ---
#
# The data layer owns interactable state (enabled / triggered / one-shot); the
# scene node is a view bound to an id that handles proximity, click, dwell, and
# visuals. Registration/trigger/enable are event-logged so a replay rebuilds the
# registry and re-fires triggers; dwell timing stays on the scheduler (the log
# records the result at the completion tick), keeping fast-forward invariance.

const INTERACTABLE_TYPE_HOLD_ACTION := 0
const INTERACTABLE_TYPE_INSPECTION := 1
const INTERACTABLE_TYPE_TIMED_ACTION := 2


## Keep the data layer independent from the scene-node class while preserving its complete
## three-state activation grammar. Old events/saves only carried `requires_hold`; they still
## deterministically migrate to HOLD_ACTION or INSPECTION.
func _normalize_interactable_type(value: Variant, legacy_requires_hold: bool) -> int:
	var fallback := INTERACTABLE_TYPE_HOLD_ACTION \
		if legacy_requires_hold else INTERACTABLE_TYPE_INSPECTION
	if value == null:
		return fallback
	if value is String or value is StringName:
		match str(value).to_upper():
			"HOLD_ACTION":
				return INTERACTABLE_TYPE_HOLD_ACTION
			"INSPECTION":
				return INTERACTABLE_TYPE_INSPECTION
			"TIMED_ACTION":
				return INTERACTABLE_TYPE_TIMED_ACTION
			_:
				return fallback
	var normalized := int(value)
	if normalized < INTERACTABLE_TYPE_HOLD_ACTION \
			or normalized > INTERACTABLE_TYPE_TIMED_ACTION:
		return fallback
	return normalized


## Normalize a spec dict into the stored shape (defaults + a Vector3 position).
func _normalize_interactable_spec(spec: Dictionary) -> Dictionary:
	var pos_raw: Variant = spec.get("position", Vector3.ZERO)
	var pos: Vector3 = GameEvent.arr_to_v3(pos_raw) if pos_raw is Array else pos_raw
	var legacy_requires_hold := bool(spec.get("requires_hold", true))
	var interaction_type := _normalize_interactable_type(
		spec.get("interactable_type", null), legacy_requires_hold)
	return {
		"id": String(spec.get("id", "")),
		"position": pos,
		# Retain the legacy projection for old consumers, but the richer type is authoritative.
		"requires_hold": interaction_type == INTERACTABLE_TYPE_HOLD_ACTION,
		"interactable_type": interaction_type,
		"hold_time": float(spec.get("hold_time", 1.0)),
		"one_shot": bool(spec.get("one_shot", false)),
		"required_character": String(spec.get("required_character", "")),
		"dialogue_key": String(spec.get("dialogue_key", "")),
		"radius": float(spec.get("radius", 2.0)),
		"tutorial_label": String(spec.get("tutorial_label", "")),
		"catalog_id": String(spec.get("catalog_id", "")),
		"enabled": bool(spec.get("enabled", true)),
		"triggered": false,
		# Monotonic acceptance identity for repeatable interactables. `triggered` answers whether the
		# object has ever fired; it cannot distinguish a newly accepted source receipt from an old use.
		"trigger_count": maxi(0, int(spec.get("trigger_count", 0))),
		"last_trigger_character": String(spec.get("last_trigger_character", "")),
	}

## Register an interactable spec. id is required and unique within the scene.
func register_interactable(spec: Dictionary) -> void:
	var norm := _normalize_interactable_spec(spec)
	if norm.id == "":
		push_warning("GameState.register_interactable: spec has no id")
		return
	_emit(GameEvent.KIND_REGISTER_INTERACTABLE, {
		"id": norm.id,
		"position": GameEvent.v3_to_arr(norm.position),
		"requires_hold": norm.requires_hold,
		"interactable_type": norm.interactable_type,
		"hold_time": norm.hold_time,
		"one_shot": norm.one_shot,
		"required_character": norm.required_character,
		"dialogue_key": norm.dialogue_key,
		"radius": norm.radius,
		"tutorial_label": norm.tutorial_label,
		"catalog_id": norm.catalog_id,
		"enabled": norm.enabled,
	})
	interactables[norm.id] = norm
	interactable_registered.emit(norm.id)

func unregister_interactable(id: String) -> void:
	if not interactables.has(id):
		return
	_emit(GameEvent.KIND_UNREGISTER_INTERACTABLE, {"id": id})
	interactables.erase(id)

func has_interactable(id: String) -> bool:
	return interactables.has(id)

## Copy-on-read so callers can't mutate the registry behind its back.
func get_interactable(id: String) -> Dictionary:
	if not interactables.has(id):
		return {}
	return (interactables[id] as Dictionary).duplicate(true)

func is_interactable_enabled(id: String) -> bool:
	if not interactables.has(id):
		return false
	var spec: Dictionary = interactables[id]
	if bool(spec.get("one_shot", false)) and bool(spec.get("triggered", false)):
		return false
	return bool(spec.get("enabled", true))

## Named LEVEL-STATE values (the survey-lens vantage, committed water levels — any state a
## walkability gate reads). LOGGED: replay reproduces every gate decision, and the mechanism is
## playable through the pure data layer (never a camera/UI read). Values are plain Variants.
var world_state := {}
signal world_state_changed(key: String, value: Variant)

func set_world_state(key: String, value: Variant) -> void:
	if world_state.has(key) and world_state[key] == value:
		return   # no-op: keeps gates free to re-commit without log spam
	_emit(GameEvent.KIND_SET_WORLD_STATE, {"key": key, "value": value})
	world_state[key] = value
	world_state_changed.emit(key, value)

func get_world_state(key: String, default: Variant = null) -> Variant:
	return world_state.get(key, default)

func set_interactable_enabled(id: String, enabled: bool) -> void:
	if not interactables.has(id):
		return
	if bool(interactables[id].get("enabled", true)) == enabled:
		return  # no-op: keeps the node free to mirror without log spam
	_emit(GameEvent.KIND_SET_INTERACTABLE_ENABLED, {"id": id, "enabled": enabled})
	interactables[id]["enabled"] = enabled
	interactable_enabled_changed.emit(id, enabled)

## Re-arm an interactable: clear its triggered flag and re-enable it (so a
## one-shot can fire again). Event-logged so replay reproduces the re-arm.
func reset_interactable(id: String) -> void:
	if not interactables.has(id):
		return
	_emit(GameEvent.KIND_RESET_INTERACTABLE, {"id": id})
	interactables[id]["triggered"] = false
	interactables[id]["enabled"] = true

## The trigger authority. Guards existence / enabled / required_character; on
## success records the event, marks triggered, disables one-shots, and emits.
## Returns true if the trigger was accepted.
func trigger_interactable(id: String, character := "") -> bool:
	if not interactables.has(id):
		return false
	if not is_interactable_enabled(id):
		return false
	var spec: Dictionary = interactables[id]
	var req := String(spec.get("required_character", ""))
	if req != "" and character != "" and character != req:
		return false
	_emit(GameEvent.KIND_TRIGGER_INTERACTABLE, {"id": id, "character": character})
	spec["triggered"] = true
	spec["trigger_count"] = int(spec.get("trigger_count", 0)) + 1
	spec["last_trigger_character"] = String(character)
	if bool(spec.get("one_shot", false)):
		spec["enabled"] = false
	interactable_triggered.emit(id, character)
	return true

## Default radius for "what can the party see/reach" queries.
const INTERACTABLE_VISIBLE_RANGE := 12.0

## Interactable ids within `radius` of ANY of the given characters. Used to ask
## "what can the party act on right now" (the combined visible range). With
## enabled_only, spent one-shots / disabled interactables are excluded.
func interactables_in_range(char_ids: Array, radius: float = INTERACTABLE_VISIBLE_RANGE, enabled_only := true) -> Array:
	var result: Array = []
	var positions: Array[Vector3] = []
	for cid in char_ids:
		if characters.has(String(cid)):
			positions.append(get_position(String(cid)))
	for id in interactables:
		if enabled_only and not is_interactable_enabled(id):
			continue
		var ipos: Vector3 = interactables[id].get("position", Vector3.ZERO)
		for p in positions:
			if Vector3(p.x - ipos.x, 0.0, p.z - ipos.z).length() <= radius:
				result.append(id)
				break
	result.sort()
	return result

## Move a character to a registered interactable (cooperative cell move to its
## cell). Delegates to command_move_to_cell, which is the logged command.
func move_to_interactable(char_id: String, id: String) -> bool:
	if not has_interactable(id) or not grid:
		return false
	var ipos: Vector3 = interactables[id].get("position", Vector3.ZERO)
	return command_move_to_cell(char_id, grid.world_to_grid(ipos))

static func _solve_quadratic_detection(pos_a: Vector3, vel_a: Vector3, pos_b: Vector3, vel_b: Vector3, R: float, max_tau: float) -> float:
	var dp_x := pos_a.x - pos_b.x
	var dp_z := pos_a.z - pos_b.z
	var dv_x := vel_a.x - vel_b.x
	var dv_z := vel_a.z - vel_b.z
	var a := dv_x * dv_x + dv_z * dv_z
	var b := 2.0 * (dp_x * dv_x + dp_z * dv_z)
	var c := dp_x * dp_x + dp_z * dp_z - R * R
	if c <= 1e-6:
		return 0.0  # Already in range
	if absf(a) < 1e-8:
		if absf(b) < 1e-8:
			return -1.0  # Parallel, never converge
		var t := -c / b
		if t >= 0.0 and t <= max_tau:
			return t
		return -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var sqrt_disc := sqrt(disc)
	var t1 := (-b - sqrt_disc) / (2.0 * a)
	var t2 := (-b + sqrt_disc) / (2.0 * a)
	if t1 >= 0.0 and t1 <= max_tau:
		return t1
	if t2 >= 0.0 and t2 <= max_tau:
		return t2
	return -1.0
