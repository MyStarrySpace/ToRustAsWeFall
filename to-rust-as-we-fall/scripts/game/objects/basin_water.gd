class_name RisingWaterCrossing
extends Node3D

## A BASIN: a bowl-scale water level on an autonomous, non-uniform ROTA (docs/BALANCING_BASIN.md).
## The ONE state variable is the water state — LOW / MID / HIGH — committed on the gameplay
## scheduler (never sampled), and each state is a different MAP over the same geometry:
##   LOW  — the bowl floor (grid level 0) is walkable; floats rest on the bed and are NOT a path.
##   MID  — the floor is drowned (caught party members return to the visited start shelf; enemies
##          are expelled through the outfall); the FLOAT cells
##          ride up to the deck plane (float_level) and become the only crossing.
##   HIGH — floats pin against the rim (a float-stander is swept); only the authored decks remain.
## The rota is a repeating dwell list ({level, dwell}) — pure data, analytic next-onsets via prefix
## arithmetic, so windows may be non-uniform (short-short-LONG) without any bespoke cadence code.
##
## Composition, not invention: the carry/impact consequence is the reusable Channel sweep
## transaction — this object owns WHEN a body is caught and routes it through an embedded,
## never-started Channel via request_sweep_body(), so party bite / enemy drown / save-load
## reconciliation stay on the one battle-tested path. Walkability edits go through the grid's
## per-level allow-sets (derived state, rebuilt by these scheduler-driven applies on replay).
##
## Dweller EVICTION: the rise telegraph sends each rostered floor enemy breaking for its refuge
## (an authored set_patrol leg — real, logged movement); the drain commit sends it back to graze
## (set_roam at its home post). A dweller that cannot reach its refuge in the telegraph lead is
## caught by the same predicate as everyone else — the first fill's demonstration kill (P18).

signal telegraphed(next_state: int)
signal state_changed(state: int)
signal body_swept(id: String, kind: String)
signal body_settled(id: String)
## Generic presentation seam consumed by ConsequencePresentationController. The payload describes
## authoritative timing and world endpoints; this kit never reaches into a preview HUD or camera.
signal state_change_cue_requested(cue: Dictionary)

const STATE_CONTRACT := "rising_water_crossing/v1"
const LEGACY_STATE_CONTRACT := "basin/v1"
const STATE_LOW := 0 # Compatibility index for the classic three-state preset.
const STATE_MID := 1 # Compatibility index for authored crossing assists.
const STATE_HIGH := 2 # Compatibility index for the classic three-state preset.
const WET_POLL_INTERVAL := 0.5
const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")
const RisingWaterCrossingSpecScript := preload(
	"res://scripts/game/objects/rising_water_crossing_spec.gd")
const MovingPlatform3DScript := preload(
	"res://scripts/game/objects/moving_platform_3d.gd")
const StylizedWaterSurfaceScript := preload(
	"res://scripts/game/visuals/stylized_water_surface_3d.gd"
)

var _gs = null
var _scheduler = null
var _tag := "basin"
var _party_ids: Array = []
var _enemy_resolver := Callable()

# --- authored data (configure) ---
var _center := Vector3.ZERO
var _plane_size := Vector2(12.0, 9.0)
var _floor_min := Vector2.ZERO          # world XZ rect of the drownable bowl floor
var _floor_max := Vector2.ZERO
var _safe_cells := {}                    # Vector2i -> true; level-0 pockets never drowned
var _float_cells := {}                   # Vector2i -> true; the raft crossing
var _float_level := 1
var _rota: Array = []                    # [{level:int, dwell:float}] repeating
var _telegraph_lead := 2.5
var _platform_motion_lead := 2.5
var _water_states: Array = []
var _outfall := Vector3.ZERO
var _recovery_cells: Array[Vector2i] = []  # ordered, distinct (cell, level) failure-recovery vertices
var _recovery_level := 0
var _sweep_opts: Dictionary = {}
var _dwellers: Array = []                # [{id, refuge:Vector3, home:Vector3, radius:float}]

# --- runtime state ---
var _running := false
var _state := STATE_LOW
var _rota_index := 0
var _state_started_tick := -1.0
var _next_change_tick := -1.0
var _pending_state_override := -1
var _wet_epoch := -1.0
var _floor_cells: Array = []             # Vector2i list, derived from the rect minus safe cells
var _floor_cells_built := false
var _swept_party_count := 0
var _drowned_enemy_count := 0
var _warned_unrestricted := false

var _channel: Channel = null
var _water_mesh: MeshInstance3D = null
var _water_mat: ShaderMaterial = null
var _float_meshes: Array = []
var _float_mesh_cells: Array[Vector2i] = []
var _float_click_bodies: Array[AnimatableBody3D] = []
var _float_platform: Node3D = null
var _visual_transition_active := false
var _visual_transition_from_state := STATE_LOW
var _visual_transition_to_state := STATE_LOW
var _visual_transition_start_tick := -1.0
var _visual_transition_end_tick := -1.0

## Configure BEFORE start(). All spatial policy is data: the drownable floor rect, the safe
## pockets, the float cells, the rota, party recovery vertices, the enemy outfall, and the dweller
## roster.
func configure(gs, spec: Dictionary) -> void:
	spec = RisingWaterCrossingSpecScript.normalize(spec)
	_gs = gs
	_tag = str(spec.get("tag", "basin"))
	_center = spec.get("pos", Vector3.ZERO)
	var ps = spec.get("plane_size", _plane_size)
	_plane_size = ps if ps is Vector2 else _plane_size
	var fmin = spec.get("floor_min", Vector2.ZERO)
	var fmax = spec.get("floor_max", Vector2.ZERO)
	_floor_min = fmin if fmin is Vector2 else Vector2.ZERO
	_floor_max = fmax if fmax is Vector2 else Vector2.ZERO
	_safe_cells = _cell_set(spec.get("safe_cells", []))
	_float_cells = _cell_set(spec.get("float_cells", []))
	_float_level = int(spec.get("float_level", 1))
	_water_states = (spec.get("water_states", []) as Array).duplicate(true)
	if _water_states.size() < 2:
		_water_states = (RisingWaterCrossingSpecScript.normalize({}).get(
			"water_states", []) as Array).duplicate(true)
	_rota.clear()
	for entry_v in (spec.get("rota", []) as Array):
		var entry := entry_v as Dictionary
		var lvl := clampi(int(entry.get("level", STATE_LOW)), 0, _water_states.size() - 1)
		_rota.append({"level": lvl, "dwell": maxf(0.5, float(entry.get("dwell", 6.0)))})
	if _rota.is_empty():
		_rota = [{"level": STATE_LOW, "dwell": 8.0}, {"level": STATE_MID, "dwell": 6.0}]
	_telegraph_lead = maxf(0.0, float(spec.get("telegraph_lead", 2.5)))
	_platform_motion_lead = clampf(float(spec.get(
		"platform_motion_lead", _telegraph_lead)), 0.0, _telegraph_lead)
	_outfall = spec.get("outfall", _center)
	_recovery_cells = _cell_list(spec.get("recovery_cells", []) as Array)
	_recovery_level = int(spec.get("recovery_level", 0))
	_sweep_opts = (spec.get("sweep", {}) as Dictionary).duplicate(true)
	_dwellers.clear()
	for dw_v in (spec.get("dwellers", []) as Array):
		var dw := dw_v as Dictionary
		_dwellers.append({
			"id": str(dw.get("id", "")),
			"refuge": dw.get("refuge", _center),
			"home": dw.get("home", _center),
			"radius": float(dw.get("radius", 2.0)),
		})
	_state = int((_rota[0] as Dictionary)["level"])
	_build_visuals()
	_build_carry_channel()

func set_party_ids(ids: Array) -> void:
	_party_ids = ids.duplicate()
	if not _recovery_cells.is_empty() and _recovery_cells.size() < _party_ids.size():
		push_error("BasinWater %s: recovery_cells needs one distinct graph vertex per party member" % _tag)

func set_enemy_resolver(resolver: Callable) -> void:
	_enemy_resolver = resolver

## Begin the rota on the gameplay scheduler. Call once the scheduler + grid exist; reset()
## cancels it. Restores from the published authority record instead when one is present, so a
## save/load lands mid-cycle rather than restarting the rota.
func start(scheduler, game_state = null) -> void:
	_cancel_callbacks()
	_scheduler = scheduler
	if game_state != null:
		_gs = game_state
	if _float_platform != null:
		_float_platform.call("set_authority", _scheduler, _gs)
		_sync_float_platform_cells()
	if _scheduler == null or _gs == null:
		return
	_validate_recovery_vertices()
	_running = true
	_arm_carry_channel()
	if _restore_from_authority():
		return
	_rota_index = 0
	_state = int((_rota[0] as Dictionary)["level"])
	_state_started_tick = _tick() + 0.01
	_next_change_tick = _state_started_tick + float((_rota[0] as Dictionary)["dwell"])
	_swept_party_count = 0
	_drowned_enemy_count = 0
	_apply_state()
	_schedule_change_at(_next_change_tick)
	_schedule_telegraph_for(_next_change_tick)
	_arm_wet_poll_if_needed()
	_publish_authoritative_state()

func reset() -> void:
	_cancel_callbacks()
	if _channel != null:
		_channel.reset()
	_running = false
	_rota_index = 0
	_state = int((_rota[0] as Dictionary)["level"])
	_state_started_tick = -1.0
	_next_change_tick = -1.0
	_pending_state_override = -1
	_wet_epoch = -1.0
	_swept_party_count = 0
	_drowned_enemy_count = 0
	_apply_state()
	_publish_authoritative_state()

func get_water_state() -> int:
	return _state


## Switches, scripts, and generated encounters use the same transition path as the automatic rota.
## This guarantees that manual control also captures passengers and replans affected routes.
func request_state(target_state: int, transition_duration := -1.0) -> bool:
	if not _running or _scheduler == null or target_state < 0 \
			or target_state >= _water_states.size() or target_state == _state:
		return false
	_pending_state_override = target_state
	_scheduler.cancel_tag(_tag + "_change")
	_scheduler.cancel_tag(_tag + "_telegraph")
	var duration := _telegraph_lead if transition_duration < 0.0 else transition_duration
	_next_change_tick = _tick() + maxf(0.05, duration)
	_emit_telegraph()
	_schedule_change_at(_next_change_tick)
	_publish_authoritative_state()
	return true

## True if a body standing at (pos, grid level) would be caught by the CURRENT water state —
## the one predicate both the commit resolution and the wet poll consult, party and enemy alike.
func catches_body_at(pos: Vector3, level: int) -> bool:
	if _gs == null or _gs.grid == null:
		return false
	var cell: Vector2i = _gs.grid.world_to_grid(pos)
	if level == 0 and _state_flag(_state, "catches_floor"):
		return _in_floor_rect(cell) and not _safe_cells.has(cell)
	if level == _float_level and _state_flag(_state, "catches_floats"):
		# A rider RIDES. The raft climbs with the water, so a body on it only drowns when the water
		# actually closes over the deck — which the state's own geometry already says. Sweeping on
		# the flag alone would drown riders through every authored rise, because every authored state
		# keeps float_y above water_y.
		return _float_cells.has(cell) and _float_height(_state) <= _water_height(_state)
	return false

## CrossingAssist stages a party across water-state changes. A hold vertex must therefore belong
## to permanent deck/safe-pocket topology, never a float cell that only exists at MID or ordinary
## bowl floor that disappears on a rise.
func is_stable_hold_position(pos: Vector3, level: int) -> bool:
	if _gs == null or _gs.grid == null:
		return false
	var cell: Vector2i = _gs.grid.world_to_grid(pos)
	if level == _float_level and _float_cells.has(cell):
		return false
	if level == 0 and _in_floor_rect(cell):
		return false
	return _gs.grid.is_walkable(cell.x, cell.y, {}, {}, level)

## Analytic: the absolute tick of the next COMMIT into `target_state`, walking the rota's dwell
## prefix sums from the live boundary — pure arithmetic, never sampled. When the basin is IN the
## target state already this still returns the NEXT entry: a read buys the next FULL window,
## never the remainder of this one. Returns -1.0 when idle or the state never occurs.
func next_state_tick(target_state: int) -> float:
	if not _running or _rota.is_empty() or _next_change_tick < 0.0:
		return -1.0
	var tick := _next_change_tick
	var idx := _rota_index
	for _hop in range(_rota.size()):
		idx = (idx + 1) % _rota.size()
		if int((_rota[idx] as Dictionary)["level"]) == target_state:
			return tick
		tick += float((_rota[idx] as Dictionary)["dwell"])
	return -1.0

## Portable rota truth — also the substrate the chart / Aster read consume later: the full
## repeating schedule plus the analytic next boundary.
func get_state() -> Dictionary:
	var change_in := maxf(0.0, _next_change_tick - _tick()) if _next_change_tick >= 0.0 else -1.0
	var telegraph_progress := 0.0
	if _visual_transition_active and _visual_transition_end_tick > _visual_transition_start_tick:
		telegraph_progress = clampf((_tick() - _visual_transition_start_tick) \
			/ (_visual_transition_end_tick - _visual_transition_start_tick), 0.0, 1.0)
	return {
		"contract": STATE_CONTRACT,
		"tag": _tag,
		"running": _running,
		"state": _state,
		"state_name": _state_name(_state),
		"water_states": _portable_water_states(),
		"rota_index": _rota_index,
		"state_started_tick": _state_started_tick,
		"next_change_tick": _next_change_tick,
		"next_change_in": change_in,
		"next_state": _peek_next_state(),
		"pending_state_override": _pending_state_override,
		"telegraph_lead": _telegraph_lead,
		"platform_motion_lead": _platform_motion_lead,
		"platform_motion_start_tick": _next_change_tick - _platform_motion_lead \
			if _next_change_tick >= 0.0 else -1.0,
		"telegraph_active": _running and change_in >= 0.0 and change_in <= _telegraph_lead,
		"telegraph_progress": telegraph_progress,
		"platform_motion": _float_platform.call("get_motion_window") \
			if _float_platform != null else {},
		"recovery_vertices": get_recovery_vertices(),
		"rota": _portable_rota(),
		"cycle_length": _cycle_length(),
		"swept_party": _swept_party_count,
		"drowned_enemies": _drowned_enemy_count,
	}


func get_recovery_vertices() -> Array:
	var out: Array = []
	for cell in _recovery_cells:
		var world := _outfall
		if _gs != null and _gs.grid != null:
			world = _gs.grid.grid_to_world(cell, _recovery_level)
		out.append({
			"cell": [cell.x, cell.y],
			"level": _recovery_level,
			"world": [world.x, world.y, world.z],
		})
	return out

func authority_state_key() -> String:
	return "kit:basin:%s" % _tag

func on_game_state_snapshot_restored() -> void:
	if _scheduler == null or _gs == null:
		return
	if not _restore_from_authority():
		reset()

# --- rota engine ---

func _commit_transition() -> void:
	if not _running or _scheduler == null:
		return
	var previous := _state
	var entry: Dictionary
	if _pending_state_override >= 0:
		var target := _pending_state_override
		_pending_state_override = -1
		var found_index := -1
		for offset in range(1, _rota.size() + 1):
			var candidate := (_rota_index + offset) % _rota.size()
			if int((_rota[candidate] as Dictionary).get("level", -1)) == target:
				found_index = candidate
				break
		if found_index >= 0:
			_rota_index = found_index
			entry = _rota[_rota_index] as Dictionary
		else:
			entry = {"level": target, "dwell": 6.0}
	else:
		_rota_index = (_rota_index + 1) % _rota.size()
		entry = _rota[_rota_index] as Dictionary
	if _float_platform != null:
		# Water walkability commits immediately below, so route replanning waits for that map.
		_float_platform.call("commit_transition", true)
	_state = int(entry["level"])
	_state_started_tick = _tick()
	_next_change_tick = _state_started_tick + float(entry["dwell"])
	_apply_state()
	if _float_platform != null:
		_float_platform.call("replan_affected_routes", "water_platform_state_changed")
	_arm_carry_channel()
	if not _state_has_catches(_state):
		_scheduler.cancel_tag(_tag + "_wet")
		_wet_epoch = -1.0
	else:
		_resolve_catches()
		_arm_wet_poll_if_needed()
	if _state_flag(_state, "floor_walkable"):
		if _state_flag(previous, "floats_walkable") \
				and not _state_flag(_state, "floats_walkable"):
			_settle_float_standers()
		_send_dwellers_home()
	_schedule_change_at(_next_change_tick)
	_schedule_telegraph_for(_next_change_tick)
	_publish_authoritative_state()
	state_changed.emit(_state)


## The traversal end and water commit intentionally share a boundary. If the scheduler dispatches
## the state callback first, pin each platform-owned traversal at its computed endpoint before
## catch resolution. Cancellation samples the traversal at the current tick, which is already its
## exact destination; this avoids a one-frame passenger lag without inventing a teleport.
func _emit_telegraph() -> void:
	if not _running:
		return
	var next := _peek_next_state()
	if _state_flag(_state, "floor_walkable") \
			and _state_flag(next, "catches_floor"):
		_evict_dwellers()
	_pulse_telegraph_visual()
	_schedule_platform_motion(next)
	var rising := _water_height(next) > _water_height(_state)
	var source_position := Vector3(
		_center.x,
		maxf(0.35, _water_height(_state) + 0.55),
		_center.z - _plane_size.y * 0.42)
	var destination := _outfall + Vector3.UP * 0.15 if rising else \
		Vector3(_center.x, maxf(0.35, _water_height(next) + 0.55), _center.z)
	var source_render := _to_render_position(source_position)
	var destination_render := _to_render_position(destination)
	state_change_cue_requested.emit({
		"scope": "player_facing",
		"event_id": "basin:%s:fill:%.3f" % [_tag, _next_change_tick],
		"cause_id": "basin:%s" % _tag,
		"cause_kind": "rising_water" if rising else "draining_water",
		"effect_kind": "hazard_transition",
		"cue_kind": "basin_level_warning",
		# The moving water and floats are the warning. Keep the portable causal
		# relationship for observation/replay without spawning explanatory text.
		"label": "",
		"destination_label": "",
		"show_label": false,
		"source_render_position": [source_render.x, source_render.y, source_render.z],
		"destination_render_position": [
			destination_render.x, destination_render.y, destination_render.z],
		"telegraph_tick": _tick(),
		"commit_tick": _next_change_tick,
	})
	telegraphed.emit(next)


func _schedule_platform_motion(next_state: int) -> void:
	if _scheduler == null or not _running:
		return
	_scheduler.cancel_tag(_tag + "_platform_motion")
	var motion_tick := _next_change_tick - _platform_motion_lead
	if motion_tick <= _tick() + 0.000001:
		_begin_platform_motion(next_state, motion_tick)
	else:
		_scheduler.schedule_after(motion_tick - _tick(),
			_begin_platform_motion.bind(next_state, motion_tick),
			_tag + "_platform_motion")


func _begin_platform_motion(next_state: int, start_tick: float) -> void:
	if not _running or next_state != _peek_next_state():
		return
	_begin_visual_transition(next_state, start_tick)
	if _float_platform != null:
		_float_platform.call("begin_transition", next_state, start_tick,
			_next_change_tick, Callable(self, "_float_passenger_receipt").bind(next_state))


func _float_passenger_receipt(
		id: String,
		render_origin: Vector3,
		render_destination: Vector3,
		motion_tick: float,
		commit_tick: float,
		next_state: int
	) -> Dictionary:
	var rising := _float_height(next_state) > _float_height(_state)
	return {
		"scope": "player_facing",
		"event_id": "water:%s:float:%s:%.3f" % [_tag, id, commit_tick],
		"cause_id": "rising_water_crossing:%s" % _tag,
		"cause_kind": "rising_water" if rising else "draining_water",
		"effect_kind": "platform_carry",
		"cue_kind": "float_passenger_carry",
		"label": "",
		"destination_label": "",
		"show_label": false,
		"subject_id": id,
		"subjects": [id],
		"source_render_position": [render_origin.x, render_origin.y, render_origin.z],
		"destination_render_position": [
			render_destination.x, render_destination.y, render_destination.z],
		"telegraph_tick": motion_tick,
		"commit_tick": commit_tick,
	}

func _peek_next_state() -> int:
	if _pending_state_override >= 0:
		return _pending_state_override
	if _rota.is_empty():
		return _state
	return int((_rota[(_rota_index + 1) % _rota.size()] as Dictionary)["level"])

func _cycle_length() -> float:
	var total := 0.0
	for entry_v in _rota:
		total += float((entry_v as Dictionary)["dwell"])
	return total

func _portable_rota() -> Array:
	var out: Array = []
	for entry_v in _rota:
		var entry := entry_v as Dictionary
		out.append({"level": int(entry["level"]), "dwell": float(entry["dwell"])})
	return out


func _state_spec(index: int) -> Dictionary:
	if index < 0 or index >= _water_states.size() \
			or not (_water_states[index] is Dictionary):
		return {}
	return _water_states[index] as Dictionary


func _state_name(index: int) -> String:
	return str(_state_spec(index).get("name", "LEVEL_%d" % index))


func _state_flag(index: int, key: String) -> bool:
	return bool(_state_spec(index).get(key, false))


func _state_has_catches(index: int) -> bool:
	return _state_flag(index, "catches_floor") \
		or _state_flag(index, "catches_floats")


func _water_height(index: int) -> float:
	return float(_state_spec(index).get("water_y", 0.0))


func _float_height(index: int) -> float:
	return float(_state_spec(index).get("float_y", 0.0))


func _portable_water_states() -> Array:
	var result: Array = []
	for index in range(_water_states.size()):
		var state := _state_spec(index)
		result.append({
			"index": index,
			"name": _state_name(index),
			"water_y": _water_height(index),
			"float_y": _float_height(index),
			"floor_walkable": bool(state.get("floor_walkable", false)),
			"floats_walkable": bool(state.get("floats_walkable", false)),
			"catches_floor": bool(state.get("catches_floor", false)),
			"catches_floats": bool(state.get("catches_floats", false)),
		})
	return result

# --- state-authored maps (per-level allow-sets; derived, rebuilt by replayed applies) ---

func _apply_state() -> void:
	var grid = _gs.grid if _gs != null else null
	if grid != null:
		_ensure_floor_cells(grid)
		if grid.is_level_restricted(0):
			for cell in _floor_cells:
				if _state_flag(_state, "floor_walkable"):
					grid.allow_cell_on_level(cell, 0)
				else:
					grid.disallow_cell_on_level(cell, 0)
			for cell_v in _safe_cells.keys():
				grid.allow_cell_on_level(cell_v, 0)
		elif not _warned_unrestricted:
			_warned_unrestricted = true
			push_error("BasinWater %s: grid level 0 has no footprint — declare the fragment's " % _tag
				+ "level-0 cells (grid.level_cells / level_regions) so the basin can drown the floor")
		for cell_v in _float_cells.keys():
			if _state_flag(_state, "floats_walkable"):
				grid.allow_cell_on_level(cell_v, _float_level)
			else:
				grid.disallow_cell_on_level(cell_v, _float_level)
	_apply_visual_state()

func _ensure_floor_cells(grid) -> void:
	if _floor_cells_built:
		return
	_floor_cells_built = true
	_floor_cells.clear()
	var a: Vector2i = grid.world_to_grid(Vector3(_floor_min.x, 0.0, _floor_min.y))
	var b: Vector2i = grid.world_to_grid(Vector3(_floor_max.x, 0.0, _floor_max.y))
	for z in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			var cell := Vector2i(x, z)
			if not _safe_cells.has(cell):
				_floor_cells.append(cell)
				# The bowl is safe only while LOW. Put that causal fact on the
				# level-aware graph vertex so hover, humans, and persona players can
				# distinguish it from the permanent CURRENT RETURN shelf without
				# consulting this mechanism's private geometry.
				if grid.has_method("set_navigation_consequence"):
					grid.set_navigation_consequence(
						cell, 0, "RISK: RISING BASIN SWEEP")

func _in_floor_rect(cell: Vector2i) -> bool:
	if _gs == null or _gs.grid == null:
		return false
	_ensure_floor_cells(_gs.grid)
	return _floor_cells.has(cell)

# --- catches (one predicate; the Channel transaction is the one consequence path) ---

func _resolve_catches() -> void:
	if _gs == null or _channel == null:
		return
	for id_v in _gs.characters.keys():
		var id := str(id_v)
		if _gs.is_external_traversal_active(id):
			continue
		var level := int(_gs.get_character_level(id)) \
			if _gs.has_method("get_character_level") else 0
		if not catches_body_at(_gs.get_position(id), level):
			continue
		var kind := sweep_kind_for(id)
		if kind != "":
			_channel.request_sweep_body(id, kind)


## What the flood does to this body if it is caught: "party", "enemy", or "" for nothing.
## ONE HAZARD, ONE PREDICATE (BALANCING_BASIN) — the flood that drowns a dweller drowns anything
## else standing in it. Eligibility must NOT depend on the chunk's enemy resolver recognising the
## body: that made an enemy which wandered in, or one owned by another system, quietly immune, and
## made the whole rule collapse to nothing in a scene with no resolver wired. The resolver's job is
## eviction and return behaviour, not deciding who can drown. The only body the water spares is one
## we can positively confirm is already dead — never sweep a corpse.
func sweep_kind_for(id: String) -> String:
	if id in _party_ids:
		return "party"
	var foe: Variant = _enemy_resolver.call(id) if _enemy_resolver.is_valid() else null
	if foe != null and is_instance_valid(foe):
		# Ask BOTH questions. Enemy.die() only transitions the FSM to "dead" and never zeroes hp, so
		# a corpse still answers is_alive() with true — checking only that would sweep bodies the
		# room has already finished with.
		if foe.has_method("is_alive") and not bool(foe.call("is_alive")):
			return ""
		if foe.has_method("get_state") and str(foe.call("get_state")) == "dead":
			return ""
	return "enemy"

func _wet_poll() -> void:
	if not _running or not _state_has_catches(_state) or _scheduler == null:
		return
	_resolve_catches()
	_schedule_wet_at(FixedCadenceScript.next_strict_tick(_wet_epoch, WET_POLL_INTERVAL, _tick()))

func _arm_wet_poll_if_needed() -> void:
	if not _state_has_catches(_state) or _scheduler == null:
		return
	_wet_epoch = _tick() + WET_POLL_INTERVAL
	_schedule_wet_at(_wet_epoch)

## A drain settles anyone riding a float onto the bed below — the raft grounds, the rider is now
## a floor-stander (a real, logged floor change; being stranded mid-bowl at LOW is the honest
## price of a late crossing).
func _settle_float_standers() -> void:
	if _gs == null or not _gs.has_method("get_character_level"):
		return
	for id_v in _gs.characters.keys():
		var id := str(id_v)
		if _gs.is_external_traversal_active(id):
			continue
		if int(_gs.get_character_level(id)) != _float_level:
			continue
		var cell: Vector2i = _gs.grid.world_to_grid(_gs.get_position(id)) \
			if _gs.grid != null else Vector2i(-9999, -9999)
		if not _float_cells.has(cell):
			continue
		var destination: Vector3 = _gs.grid.grid_to_world(cell, 0) \
			if _gs.grid != null else Vector3(_gs.get_position(id).x, 0.0, _gs.get_position(id).z)
		var render_origin: Vector3 = _gs.get_render_position(id) \
			if _gs.has_method("get_render_position") else _gs.get_position(id)
		var render_destination := destination
		if _gs.coord_map != null:
			render_destination = _gs.coord_map.to_world(destination)
		var now := _tick()
		var accepted := bool(_gs.command_external_traversal(
			id,
			StringName("basin_settle/%s/%s" % [_tag, id]),
			destination,
			render_origin,
			render_destination,
			0.6,
			&"locked",
			{
				"scope": "player_facing",
				"event_id": "basin:%s:drain:%.3f" % [_tag, now],
				"cause_id": "basin:%s" % _tag,
				"cause_kind": "draining_water",
				"effect_kind": "forced_movement",
				"cue_kind": "raft_settle",
				"label": "LOWERED BY DRAINING BASIN",
				"destination_label": "BOWL FLOOR",
				"subject_id": id,
				"subjects": [id],
				"source_render_position": [render_origin.x, render_origin.y, render_origin.z],
				"destination_render_position": [
					render_destination.x, render_destination.y, render_destination.z],
				"telegraph_tick": now - _telegraph_lead,
				"commit_tick": now,
			}))
		if accepted:
			body_settled.emit(id)

# --- dweller eviction (rise telegraph: break for the refuge; drain commit: back to graze) ---

func _evict_dwellers() -> void:
	for dw_v in _dwellers:
		var dw := dw_v as Dictionary
		var foe: Variant = _resolve_dweller(str(dw["id"]))
		if foe == null:
			continue
		var level := int(_gs.get_character_level(str(dw["id"]))) \
			if _gs != null and _gs.has_method("get_character_level") else 0
		if level != 0:
			continue
		if foe.has_method("set_patrol"):
			var leg: Array[Vector3] = []
			leg.append(dw["refuge"] as Vector3)
			foe.set_patrol(leg)

func _send_dwellers_home() -> void:
	for dw_v in _dwellers:
		var dw := dw_v as Dictionary
		var foe: Variant = _resolve_dweller(str(dw["id"]))
		if foe == null:
			continue
		if foe.has_method("set_roam"):
			foe.set_roam(dw["home"] as Vector3, float(dw["radius"]))

func _resolve_dweller(id: String) -> Variant:
	if id.is_empty() or not _enemy_resolver.is_valid():
		return null
	var foe: Variant = _enemy_resolver.call(id)
	if foe == null or not is_instance_valid(foe):
		return null
	if foe.has_method("is_alive") and not bool(foe.call("is_alive")):
		return null
	return foe

# --- the embedded carry channel (consequence transactions only; its own cadence never starts) ---

func _build_carry_channel() -> void:
	if _channel != null:
		return
	_channel = Channel.new()
	_channel.name = "BasinCarry"
	_channel.owns_visuals = false
	var half := absf(_floor_max.x - _floor_min.x) * 0.5 + 1.0
	var z_half := absf(_floor_max.y - _floor_min.y) * 0.5 + 1.0
	_channel.configure((_floor_min.x + _floor_max.x) * 0.5, half, z_half,
		100000.0, 0.5, 0.0, _tag + "_carry", (_floor_min.y + _floor_max.y) * 0.5)
	add_child(_channel)

func _arm_carry_channel() -> void:
	if _channel == null or _gs == null:
		return
	var render_source := _to_render_position(Vector3(
		_center.x, maxf(0.35, _water_height(_state) + 0.55), _center.z))
	var opts := {
		"party_hp": float(_sweep_opts.get("party_hp", 6.0)),
		"enemy_damage": float(_sweep_opts.get("enemy_damage", 999.0)),
		"enemy_stun": float(_sweep_opts.get("enemy_stun", 0.0)),
		"travel_speed": float(_sweep_opts.get("travel_speed", 7.0)),
		"refractory": float(_sweep_opts.get("refractory", 4.0)),
		"enemy_resolver": _enemy_resolver,
		"on_swept": _on_party_swept,
		"on_enemy_swept": _on_enemy_swept,
		"presentation_receipt": {
			"cause_id": "basin:%s" % _tag,
			"cause_kind": "rising_water",
			"cue_kind": "current_carry",
			"label": "SWEPT BY RISING BASIN",
			"destination_label": "START / CURRENT RETURN",
			"event_id_prefix": "basin:%s:fill" % _tag,
			"telegraph_lead": _telegraph_lead,
			"source_render_position": [
				render_source.x, render_source.y, render_source.z],
		},
	}
	_channel.set_sweep(_gs, _party_ids, _sweep_landing, opts)

func _sweep_landing(id: String, _origin: Vector3) -> Vector3:
	var idx := _party_ids.find(id)
	if idx >= 0 and idx < _recovery_cells.size() and _gs != null and _gs.grid != null:
		return _gs.grid.grid_to_world(_recovery_cells[idx], _recovery_level)
	# Enemies terminate at the named outfall, which must itself be a safe recovery vertex. Party
	# overflow falls back here only after configure emitted the missing-slot authoring error.
	return _outfall

func _on_party_swept(id: String) -> void:
	_swept_party_count += 1
	_publish_authoritative_state()
	body_swept.emit(id, "party")

func _on_enemy_swept(id: String) -> void:
	_drowned_enemy_count += 1
	_publish_authoritative_state()
	body_swept.emit(id, "enemy")

# --- scheduling (all tagged; a reset cancels everything) ---

func _schedule_change_at(deadline: float) -> void:
	if _scheduler == null or not _running:
		return
	_scheduler.cancel_tag(_tag + "_change")
	_scheduler.schedule_after(maxf(0.0, deadline - _tick()), _commit_transition, _tag + "_change")

func _schedule_telegraph_for(change_tick: float) -> void:
	if _scheduler == null or not _running or _telegraph_lead <= 0.0:
		return
	_scheduler.cancel_tag(_tag + "_telegraph")
	_scheduler.cancel_tag(_tag + "_platform_motion")
	_scheduler.schedule_after(maxf(0.0, change_tick - _telegraph_lead - _tick()),
		_emit_telegraph, _tag + "_telegraph")

func _schedule_wet_at(deadline: float) -> void:
	if _scheduler == null or not _running:
		return
	_scheduler.cancel_tag(_tag + "_wet")
	_scheduler.schedule_after(maxf(0.0, deadline - _tick()), _wet_poll, _tag + "_wet")

func _cancel_callbacks() -> void:
	if _scheduler == null:
		return
	_scheduler.cancel_tag(_tag + "_change")
	_scheduler.cancel_tag(_tag + "_telegraph")
	_scheduler.cancel_tag(_tag + "_wet")

func _tick() -> float:
	return float(_scheduler.get_current_tick()) if _scheduler != null else 0.0

# --- authority (portable rota truth; the Channel owns its own sweep transactions) ---

func _publish_authoritative_state() -> void:
	if _gs == null or not _gs.has_method("set_world_state"):
		return
	_gs.set_world_state(authority_state_key(), get_state())

func _restore_from_authority() -> bool:
	if _gs == null or not _gs.has_method("get_world_state"):
		return false
	var saved: Variant = _gs.get_world_state(authority_state_key(), null)
	if not saved is Dictionary or (saved as Dictionary).is_empty():
		return false
	var snapshot := saved as Dictionary
	if str(snapshot.get("contract", "")) not in [STATE_CONTRACT, LEGACY_STATE_CONTRACT] \
			or str(snapshot.get("tag", "")) != _tag \
			or not bool(snapshot.get("running", false)):
		return false
	var idx := int(snapshot.get("rota_index", -1))
	var next_tick := float(snapshot.get("next_change_tick", -1.0))
	if idx < 0 or idx >= _rota.size() or next_tick < 0.0:
		return false
	_running = true
	_rota_index = idx
	_state = clampi(int(snapshot.get("state", STATE_LOW)), 0, _water_states.size() - 1)
	_pending_state_override = clampi(int(snapshot.get(
		"pending_state_override", -1)), -1, _water_states.size() - 1)
	_state_started_tick = float(snapshot.get("state_started_tick", _tick()))
	_next_change_tick = next_tick
	_swept_party_count = int(snapshot.get("swept_party", 0))
	_drowned_enemy_count = int(snapshot.get("drowned_enemies", 0))
	_apply_state()
	_arm_carry_channel()
	_schedule_change_at(maxf(_tick(), _next_change_tick))
	_schedule_telegraph_for(_next_change_tick)
	if _platform_motion_lead > 0.0 \
			and _next_change_tick - _tick() <= _platform_motion_lead:
		_begin_platform_motion(
			_peek_next_state(), _next_change_tick - _platform_motion_lead)
	_arm_wet_poll_if_needed()
	return true

# --- visuals (cosmetic only; the data above never reads them) ---

func _build_visuals() -> void:
	if _water_mesh != null:
		return
	# One continuous, margin-covered surface. The reusable @tool node owns mesh
	# density and the stylized-water material; this mechanism owns only the
	# authoritative state elevation.
	_water_mesh = StylizedWaterSurfaceScript.new()
	_water_mesh.name = "BasinWaterPlane"
	_water_mesh.call("configure", _plane_size, 0.18)
	_water_mat = _water_mesh.material_override as ShaderMaterial
	_water_mesh.position = Vector3(_center.x, _water_height(_state), _center.z)
	add_child(_water_mesh)
	_float_platform = MovingPlatform3DScript.new()
	_float_platform.name = "BasinFloatPlatform"
	add_child(_float_platform)
	var platform_transforms: Array = []
	var platform_levels: Array = []
	for state_index in range(_water_states.size()):
		platform_transforms.append(Transform3D(
			Basis.IDENTITY, Vector3(0.0, _float_height(state_index), 0.0)))
		var levels: Array[int] = [_float_level]
		if _state_flag(state_index, "floor_walkable") \
				and not _state_flag(state_index, "floats_walkable"):
			levels.append(0)
		platform_levels.append(levels)
	_float_platform.call("configure", null, _gs, "water_float_%s" % _tag,
		platform_transforms, _state, _float_cells, platform_levels)
	for cell_v in _float_cells.keys():
		var float_cell := cell_v as Vector2i
		var raft := MeshInstance3D.new()
		raft.name = "BasinFloat_%d_%d" % [float_cell.x, float_cell.y]
		var rm := BoxMesh.new()
		rm.size = Vector3(1.3, 0.22, 1.3)
		raft.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.42, 0.34, 0.2)
		rmat.emission_enabled = true
		rmat.emission = Color(0.5, 0.42, 0.2)
		rmat.emission_energy_multiplier = 0.12
		raft.material_override = rmat
		var cell_world := _cell_world(float_cell, 0.0)
		raft.position = Vector3(cell_world.x, 0.0, cell_world.z)
		var click_body := AnimatableBody3D.new()
		click_body.name = "GroundClickSurface"
		click_body.collision_layer = 1 if _state_flag(_state, "floats_walkable") else 0
		click_body.collision_mask = 0
		click_body.input_ray_pickable = true
		click_body.sync_to_physics = false
		click_body.set_meta("navigation_level", _float_level)
		var click_shape := CollisionShape3D.new()
		var click_box := BoxShape3D.new()
		click_box.size = rm.size
		click_shape.shape = click_box
		click_body.add_child(click_shape)
		raft.add_child(click_body)
		_float_platform.add_child(raft)
		_float_meshes.append(raft)
		_float_mesh_cells.append(float_cell)
		_float_click_bodies.append(click_body)

func _apply_visual_state() -> void:
	_visual_transition_active = false
	if _water_mesh != null:
		_water_mesh.position.y = _water_height(_state)
	if _float_platform != null:
		_sync_float_platform_cells()
		_float_platform.call("set_state_immediate", _state)
	# Keep human pointer targeting on the same state boundary as pathfinding.
	# In float-walkable states these are typed level-1 ground surfaces; otherwise the ray passes
	# through to the currently valid floor instead of advertising a closed raft.
	for click_body in _float_click_bodies:
		if is_instance_valid(click_body):
			click_body.collision_layer = 1 if _state_flag(_state, "floats_walkable") else 0
	if _water_mat != null:
		_water_mat.set_shader_parameter("alert_strength", 0.0)


func _sync_float_platform_cells() -> void:
	if _gs == null or _gs.grid == null:
		return
	var count := mini(_float_meshes.size(), _float_mesh_cells.size())
	for index in range(count):
		var raft := _float_meshes[index] as Node3D
		if not is_instance_valid(raft):
			continue
		var world_position: Vector3 = _gs.grid.grid_to_world(_float_mesh_cells[index])
		raft.position = Vector3(world_position.x, 0.0, world_position.z)

func _pulse_telegraph_visual() -> void:
	if _water_mat != null:
		_water_mat.set_shader_parameter("alert_strength", 1.0)


## The grid changes only at the scheduled commit, but the water and floats visibly travel toward
## that state throughout the warning window. This is deliberately cosmetic and reads scheduler
## time, so pause/save/fast-forward cannot make the tell disagree with the authoritative boundary.
func _begin_visual_transition(next_state: int, start_tick := -1.0) -> void:
	if next_state < 0 or next_state >= _water_states.size() or next_state == _state:
		return
	_visual_transition_active = true
	_visual_transition_from_state = _state
	_visual_transition_to_state = next_state
	_visual_transition_start_tick = _tick() if start_tick < 0.0 else start_tick
	_visual_transition_end_tick = _next_change_tick
	set_process(true)
	_update_visual_transition()


func _process(_delta: float) -> void:
	if not _visual_transition_active:
		set_process(false)
		return
	_update_visual_transition()


func _update_visual_transition() -> void:
	if not _visual_transition_active:
		return
	var duration := _visual_transition_end_tick - _visual_transition_start_tick
	var progress := 1.0 if duration <= 0.0 else clampf(
		(_tick() - _visual_transition_start_tick) / duration, 0.0, 1.0)
	# Ease at both ends: the first visible motion begins immediately without looking like a snap,
	# and the visual surface reaches the exact committed height at the scheduler boundary.
	var eased := progress * progress * (3.0 - 2.0 * progress)
	if _water_mesh != null:
		_water_mesh.position.y = lerpf(
			_water_height(_visual_transition_from_state),
			_water_height(_visual_transition_to_state), eased)

func _cell_world(cell: Vector2i, y: float) -> Vector3:
	if _gs != null and _gs.grid != null:
		var w: Vector3 = _gs.grid.grid_to_world(cell)
		return Vector3(w.x, y, w.z)
	return Vector3(_center.x, y, _center.z)


func _to_render_position(data_position: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_world(data_position)
	return data_position

func _cell_set(raw: Array) -> Dictionary:
	var out := {}
	for cell_v in raw:
		if cell_v is Vector2i:
			out[cell_v] = true
		elif cell_v is Array and (cell_v as Array).size() == 2:
			out[Vector2i(int((cell_v as Array)[0]), int((cell_v as Array)[1]))] = true
	return out


func _cell_list(raw: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell_v in raw:
		var cell := Vector2i(-999999, -999999)
		if cell_v is Vector2i:
			cell = cell_v as Vector2i
		elif cell_v is Array and (cell_v as Array).size() == 2:
			cell = Vector2i(int((cell_v as Array)[0]), int((cell_v as Array)[1]))
		if cell.x > -999999 and not out.has(cell):
			out.append(cell)
	return out


func _validate_recovery_vertices() -> void:
	if _gs == null or _gs.grid == null:
		return
	if _recovery_cells.size() < _party_ids.size():
		push_error("BasinWater %s: recovery graph has %d vertices for %d party members" % [
			_tag, _recovery_cells.size(), _party_ids.size()])
	for cell in _recovery_cells:
		if not _safe_cells.has(cell):
			push_error("BasinWater %s: recovery vertex %s is not in safe_cells" % [_tag, str(cell)])
		if not _gs.grid.is_walkable(cell.x, cell.y, {}, {}, _recovery_level):
			push_error("BasinWater %s: recovery vertex %s is not walkable on level %d" % [
				_tag, str(cell), _recovery_level])

func _exit_tree() -> void:
	_cancel_callbacks()
