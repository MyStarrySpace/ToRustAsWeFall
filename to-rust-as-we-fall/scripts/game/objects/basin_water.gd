class_name BasinWater
extends Node3D

## A BASIN: a bowl-scale water level on an autonomous, non-uniform ROTA (docs/BALANCING_BASIN.md).
## The ONE state variable is the water state — LOW / MID / HIGH — committed on the gameplay
## scheduler (never sampled), and each state is a different MAP over the same geometry:
##   LOW  — the bowl floor (grid level 0) is walkable; floats rest on the bed and are NOT a path.
##   MID  — the floor is drowned (anything caught on it is swept to the outfall); the FLOAT cells
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

const STATE_CONTRACT := "basin/v1"
const STATE_LOW := 0
const STATE_MID := 1
const STATE_HIGH := 2
const STATE_NAMES := ["LOW", "MID", "HIGH"]
const WET_POLL_INTERVAL := 0.5
const FixedCadenceScript := preload("res://scripts/system/core/fixed_cadence.gd")

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
var _water_y := [-0.4, 2.35, 3.1]
var _float_y := [0.15, 2.55, 3.25]
var _outfall := Vector3.ZERO
var _sweep_opts: Dictionary = {}
var _dwellers: Array = []                # [{id, refuge:Vector3, home:Vector3, radius:float}]

# --- runtime state ---
var _running := false
var _state := STATE_LOW
var _rota_index := 0
var _state_started_tick := -1.0
var _next_change_tick := -1.0
var _wet_epoch := -1.0
var _floor_cells: Array = []             # Vector2i list, derived from the rect minus safe cells
var _floor_cells_built := false
var _swept_party_count := 0
var _drowned_enemy_count := 0
var _warned_unrestricted := false

var _channel: Channel = null
var _water_mesh: MeshInstance3D = null
var _water_mat: StandardMaterial3D = null
var _float_meshes: Array = []

## Configure BEFORE start(). All spatial policy is data: the drownable floor rect, the safe
## pockets, the float cells, the rota, the outfall, and the dweller roster.
func configure(gs, spec: Dictionary) -> void:
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
	_rota.clear()
	for entry_v in (spec.get("rota", []) as Array):
		var entry := entry_v as Dictionary
		var lvl := clampi(int(entry.get("level", STATE_LOW)), STATE_LOW, STATE_HIGH)
		_rota.append({"level": lvl, "dwell": maxf(0.5, float(entry.get("dwell", 6.0)))})
	if _rota.is_empty():
		_rota = [{"level": STATE_LOW, "dwell": 8.0}, {"level": STATE_MID, "dwell": 6.0}]
	_telegraph_lead = maxf(0.0, float(spec.get("telegraph_lead", 2.5)))
	if spec.get("water_y", null) is Array and (spec["water_y"] as Array).size() == 3:
		_water_y = (spec["water_y"] as Array).duplicate()
	if spec.get("float_y", null) is Array and (spec["float_y"] as Array).size() == 3:
		_float_y = (spec["float_y"] as Array).duplicate()
	_outfall = spec.get("outfall", _center)
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
	if _scheduler == null or _gs == null:
		return
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
	_wet_epoch = -1.0
	_swept_party_count = 0
	_drowned_enemy_count = 0
	_apply_state()
	_publish_authoritative_state()

func get_water_state() -> int:
	return _state

## True if a body standing at (pos, grid level) would be caught by the CURRENT water state —
## the one predicate both the commit resolution and the wet poll consult, party and enemy alike.
func catches_body_at(pos: Vector3, level: int) -> bool:
	if _gs == null or _gs.grid == null:
		return false
	var cell: Vector2i = _gs.grid.world_to_grid(pos)
	if level == 0 and _state >= STATE_MID:
		return _in_floor_rect(cell) and not _safe_cells.has(cell)
	if level == _float_level and _state == STATE_HIGH:
		return _float_cells.has(cell)
	return false

## Portable rota truth — also the substrate the chart / Aster read consume later: the full
## repeating schedule plus the analytic next boundary.
func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"tag": _tag,
		"running": _running,
		"state": _state,
		"state_name": STATE_NAMES[_state],
		"rota_index": _rota_index,
		"state_started_tick": _state_started_tick,
		"next_change_tick": _next_change_tick,
		"next_change_in": maxf(0.0, _next_change_tick - _tick()) if _next_change_tick >= 0.0 else -1.0,
		"next_state": _peek_next_state(),
		"rota": _portable_rota(),
		"cycle_length": _cycle_length(),
		"swept_party": _swept_party_count,
		"drowned_enemies": _drowned_enemy_count,
	}

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
	_rota_index = (_rota_index + 1) % _rota.size()
	var entry := _rota[_rota_index] as Dictionary
	_state = int(entry["level"])
	_state_started_tick = _tick()
	_next_change_tick = _state_started_tick + float(entry["dwell"])
	_apply_state()
	if _state == STATE_LOW:
		_scheduler.cancel_tag(_tag + "_wet")
		_wet_epoch = -1.0
		_settle_float_standers()
		_send_dwellers_home()
	else:
		if previous < _state:
			_resolve_catches()
		_arm_wet_poll_if_needed()
	_schedule_change_at(_next_change_tick)
	_schedule_telegraph_for(_next_change_tick)
	_publish_authoritative_state()
	state_changed.emit(_state)

func _emit_telegraph() -> void:
	if not _running:
		return
	var next := _peek_next_state()
	if _state == STATE_LOW and next > STATE_LOW:
		_evict_dwellers()
	_pulse_telegraph_visual()
	telegraphed.emit(next)

func _peek_next_state() -> int:
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

# --- the three maps (per-level allow-sets; derived, rebuilt by replayed applies) ---

func _apply_state() -> void:
	var grid = _gs.grid if _gs != null else null
	if grid != null:
		_ensure_floor_cells(grid)
		if grid.is_level_restricted(0):
			for cell in _floor_cells:
				if _state == STATE_LOW:
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
			if _state == STATE_MID:
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
		if id in _party_ids:
			_channel.request_sweep_body(id, "party")
		elif _enemy_resolver.is_valid() and _enemy_resolver.call(id) != null:
			_channel.request_sweep_body(id, "enemy")

func _wet_poll() -> void:
	if not _running or _state == STATE_LOW or _scheduler == null:
		return
	_resolve_catches()
	_schedule_wet_at(FixedCadenceScript.next_strict_tick(_wet_epoch, WET_POLL_INTERVAL, _tick()))

func _arm_wet_poll_if_needed() -> void:
	if _state == STATE_LOW or _scheduler == null:
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
		if _float_cells.has(cell) and _gs.has_method("set_character_level"):
			_gs.set_character_level(id, 0)
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
	var opts := {
		"party_hp": float(_sweep_opts.get("party_hp", 6.0)),
		"enemy_damage": float(_sweep_opts.get("enemy_damage", 999.0)),
		"enemy_stun": float(_sweep_opts.get("enemy_stun", 0.0)),
		"travel_speed": float(_sweep_opts.get("travel_speed", 7.0)),
		"refractory": float(_sweep_opts.get("refractory", 4.0)),
		"enemy_resolver": _enemy_resolver,
		"on_swept": _on_party_swept,
		"on_enemy_swept": _on_enemy_swept,
	}
	_channel.set_sweep(_gs, _party_ids, _sweep_landing, opts)

func _sweep_landing(id: String, _origin: Vector3) -> Vector3:
	var idx := _party_ids.find(id)
	if idx < 0:
		return _outfall + Vector3(-0.9, 0.0, 0.0)
	return _outfall + Vector3(0.0, 0.0, 1.5 * float(idx % 2) - 0.75 * float(idx % 3 == 2))

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
	if str(snapshot.get("contract", "")) != STATE_CONTRACT \
			or str(snapshot.get("tag", "")) != _tag \
			or not bool(snapshot.get("running", false)):
		return false
	var idx := int(snapshot.get("rota_index", -1))
	var next_tick := float(snapshot.get("next_change_tick", -1.0))
	if idx < 0 or idx >= _rota.size() or next_tick < 0.0:
		return false
	_running = true
	_rota_index = idx
	_state = clampi(int(snapshot.get("state", STATE_LOW)), STATE_LOW, STATE_HIGH)
	_state_started_tick = float(snapshot.get("state_started_tick", _tick()))
	_next_change_tick = next_tick
	_swept_party_count = int(snapshot.get("swept_party", 0))
	_drowned_enemy_count = int(snapshot.get("drowned_enemies", 0))
	_apply_state()
	_schedule_change_at(maxf(_tick(), _next_change_tick))
	_schedule_telegraph_for(_next_change_tick)
	_arm_wet_poll_if_needed()
	return true

# --- visuals (cosmetic only; the data above never reads them) ---

func _build_visuals() -> void:
	if _water_mesh != null:
		return
	_water_mesh = MeshInstance3D.new()
	_water_mesh.name = "BasinWaterPlane"
	var wm := BoxMesh.new()
	wm.size = Vector3(_plane_size.x, 0.28, _plane_size.y)
	_water_mesh.mesh = wm
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.13, 0.3, 0.36, 0.82)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.emission_enabled = true
	_water_mat.emission = Color(0.16, 0.45, 0.5)
	_water_mat.emission_energy_multiplier = 0.35
	_water_mesh.material_override = _water_mat
	_water_mesh.position = Vector3(_center.x, float(_water_y[_state]), _center.z)
	add_child(_water_mesh)
	for cell_v in _float_cells.keys():
		var raft := MeshInstance3D.new()
		raft.name = "BasinFloat_%d_%d" % [(cell_v as Vector2i).x, (cell_v as Vector2i).y]
		var rm := BoxMesh.new()
		rm.size = Vector3(1.3, 0.22, 1.3)
		raft.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.42, 0.34, 0.2)
		rmat.emission_enabled = true
		rmat.emission = Color(0.5, 0.42, 0.2)
		rmat.emission_energy_multiplier = 0.12
		raft.material_override = rmat
		raft.position = _cell_world(cell_v as Vector2i, float(_float_y[_state]))
		add_child(raft)
		_float_meshes.append(raft)

func _apply_visual_state() -> void:
	if _water_mesh != null:
		_water_mesh.position.y = float(_water_y[_state])
	var i := 0
	var cells := _float_cells.keys()
	for raft_v in _float_meshes:
		var raft := raft_v as MeshInstance3D
		if is_instance_valid(raft) and i < cells.size():
			raft.position = _cell_world(cells[i] as Vector2i, float(_float_y[_state]))
		i += 1
	if _water_mat != null:
		_water_mat.emission_energy_multiplier = 0.35

func _pulse_telegraph_visual() -> void:
	if _water_mat != null:
		_water_mat.emission_energy_multiplier = 1.4

func _cell_world(cell: Vector2i, y: float) -> Vector3:
	if _gs != null and _gs.grid != null:
		var w: Vector3 = _gs.grid.grid_to_world(cell)
		return Vector3(w.x, y, w.z)
	return Vector3(_center.x, y, _center.z)

func _cell_set(raw: Array) -> Dictionary:
	var out := {}
	for cell_v in raw:
		if cell_v is Vector2i:
			out[cell_v] = true
		elif cell_v is Array and (cell_v as Array).size() == 2:
			out[Vector2i(int((cell_v as Array)[0]), int((cell_v as Array)[1]))] = true
	return out

func _exit_tree() -> void:
	_cancel_callbacks()
