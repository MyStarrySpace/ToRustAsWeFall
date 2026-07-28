class_name GridRiskField
extends Node

## Scheduler-owned consequence for a visibly marked set of GridWorld cells.
##
## This is the kit home for generated "risky route" pressure. The level supplies the
## already-rendered risk cells; this object asks where each body actually is on every
## fixed gameplay beat. Merely choosing or highlighting a route never hurts anyone.
## Position, the marked cell's penalty, and the saved cadence together cause damage.

const STATE_CONTRACT := "grid_risk_field/v2"
const LEGACY_STATE_CONTRACT := "grid_risk_field/v1"
const MIN_INTERVAL := 0.000001
const HP_EPSILON := 0.0001

var _gs = null
var _scheduler = null
var _grid = null
var _risk_by_cell: Dictionary = {}
var _character_ids: Array[String] = []
var _interval := 0.5
var _damage_rate_scale := 1.0
var _tag := "grid_risk_field"
var _baseline_active := false
var _active := false
var _tick_armed := false
var _next_tick := -1.0
var _pending_batch: Dictionary = {}
var _batch_resume_armed := false
var _damage_total := 0.0
var _contact_ticks: Dictionary = {}
var _on_bite := Callable()
var _restoring := false


## Risk entries use the navigation-grid schema:
## {cell: [x, y], penalty: float, optional level: int}. An entry without a level
## applies on every rendered level, matching generated risk-floor tinting.
func setup(
	gs,
	scheduler,
	grid,
	risk_entries: Array,
	character_ids: Array,
	opts: Dictionary = {}
) -> void:
	_cancel_tick()
	_gs = gs
	_scheduler = scheduler
	_grid = grid
	_tag = str(opts.get("tag", "grid_risk_field"))
	_interval = maxf(MIN_INTERVAL, float(opts.get("interval", 0.5)))
	_damage_rate_scale = maxf(0.0, float(opts.get("damage_rate_scale", 1.0)))
	_baseline_active = bool(opts.get("active", false))
	_on_bite = opts.get("on_bite", Callable())
	_set_risk_entries(risk_entries)
	set_character_ids(character_ids, false)
	if bool(opts.get("restore_existing_authority", false)) and restore_from_authority():
		return
	_active = _baseline_active
	_damage_total = 0.0
	_contact_ticks.clear()
	if _active:
		_arm_tick_at(_scheduler_tick() + _interval)
	_publish_authoritative_state()


func set_character_ids(character_ids: Array, publish := true) -> void:
	_character_ids.clear()
	for id_v in character_ids:
		var id := str(id_v)
		if id != "" and not _character_ids.has(id):
			_character_ids.append(id)
	if publish:
		_publish_authoritative_state()


func set_active(on: bool) -> void:
	if _active == on and (not on or _tick_armed or not _pending_batch.is_empty()):
		return
	_active = on
	_cancel_derived_callbacks()
	if _pending_batch.is_empty():
		_next_tick = -1.0
	if _active and _pending_batch.is_empty():
		_arm_tick_at(_scheduler_tick() + _interval)
	_publish_authoritative_state()


## Construction/reset baseline: clears accumulated evidence and begins one fresh
## cadence. This is intentionally distinct from set_active(), which preserves history.
func reset(active := true) -> void:
	_cancel_tick()
	_pending_batch.clear()
	_damage_total = 0.0
	_contact_ticks.clear()
	_active = active
	if _active:
		_arm_tick_at(_scheduler_tick() + _interval)
	_publish_authoritative_state()


func is_active() -> bool:
	return _active


func risk_cell_count() -> int:
	return _risk_by_cell.size()


func is_character_exposed(character_id: String) -> bool:
	return _penalty_for_character(character_id) > 0.0


func authority_state_key() -> String:
	return "kit:grid_risk_field:%s" % _tag


func get_state() -> Dictionary:
	return {
		"contract": STATE_CONTRACT,
		"tag": _tag,
		"active": _active,
		"baseline_active": _baseline_active,
		"tick_armed": _tick_armed,
		"next_tick": _next_tick,
		"next_tick_in": (
			maxf(0.0, _next_tick - _scheduler_tick())
			if (_tick_armed or not _pending_batch.is_empty()) and _next_tick >= 0.0
			else -1.0
		),
		"interval": _interval,
		"damage_rate_scale": _damage_rate_scale,
		"character_ids": _character_ids.duplicate(),
		"risk_by_cell": _risk_by_cell.duplicate(true),
		"risk_cell_count": _risk_by_cell.size(),
		"damage_total": _damage_total,
		"contact_ticks": _contact_ticks.duplicate(true),
		"pending_batch": _pending_batch.duplicate(true),
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


## Restores the saved cadence without applying a contact or publishing replacement
## truth. Static cell geometry is reconstructed from the generated spec at setup.
func restore_state(snapshot: Dictionary) -> bool:
	var contract := str(snapshot.get("contract", ""))
	if contract != STATE_CONTRACT and contract != LEGACY_STATE_CONTRACT:
		return false
	if str(snapshot.get("tag", "")) != _tag \
			or _scheduler == null or _gs == null or _grid == null:
		return false
	var saved_interval := float(snapshot.get("interval", -1.0))
	var saved_scale := float(snapshot.get("damage_rate_scale", -1.0))
	if saved_interval < MIN_INTERVAL or saved_scale < 0.0:
		return false

	_restoring = true
	_cancel_derived_callbacks()
	_interval = saved_interval
	_damage_rate_scale = saved_scale
	_active = bool(snapshot.get("active", false))
	set_character_ids(snapshot.get("character_ids", _character_ids), false)
	var saved_risk: Variant = snapshot.get("risk_by_cell", {})
	if saved_risk is Dictionary and not (saved_risk as Dictionary).is_empty():
		_risk_by_cell = (saved_risk as Dictionary).duplicate(true)
	_damage_total = maxf(0.0, float(snapshot.get("damage_total", 0.0)))
	_contact_ticks = (snapshot.get("contact_ticks", {}) as Dictionary).duplicate(true)
	_pending_batch = (snapshot.get("pending_batch", {}) as Dictionary).duplicate(true) \
		if contract == STATE_CONTRACT else {}
	_tick_armed = false
	_next_tick = float(snapshot.get("next_tick", -1.0))
	if not _pending_batch.is_empty():
		var batch_deadline := float(_pending_batch.get("next_tick", _next_tick))
		_next_tick = batch_deadline
		_arm_batch_resume()
	elif _active and bool(snapshot.get("tick_armed", false)):
		var deadline := _next_tick
		if deadline < 0.0:
			var remaining := float(snapshot.get("next_tick_in", -1.0))
			if remaining < 0.0:
				_restoring = false
				return false
			deadline = _scheduler_tick() + remaining
		_arm_tick_at(maxf(_scheduler_tick(), deadline))
	_restoring = false
	return true


func restore_from_authority() -> bool:
	if _gs == null or not _gs.has_method("get_world_state"):
		return false
	var saved: Variant = _gs.get_world_state(authority_state_key(), null)
	return restore_state(saved as Dictionary) if saved is Dictionary else false


## Snapshot absence retracts later history while preserving authored construction
## truth. A dynamically spawned field configures active=false; a marked terrain field
## configures active=true. Do not publish a replacement record merely because we loaded.
func on_game_state_snapshot_restored() -> void:
	if restore_from_authority():
		return
	_restoring = true
	_cancel_tick()
	_pending_batch.clear()
	_active = _baseline_active
	_damage_total = 0.0
	_contact_ticks.clear()
	if _active:
		_arm_tick_at(_scheduler_tick() + _interval)
	_restoring = false


func _tick() -> void:
	_tick_armed = false
	_next_tick = -1.0
	if not _active or _gs == null or _scheduler == null or _grid == null:
		_publish_authoritative_state()
		return

	_pending_batch = {
		"started_tick": _scheduler_tick(),
		"next_tick": _scheduler_tick() + _interval,
		"targets": _sample_tick_cohort(),
	}
	_next_tick = float(_pending_batch.get("next_tick", -1.0))
	# The exact physical cohort, projected payments, and following cadence are world truth before
	# the first adjust_stat signal can offer a save. Later bodies cannot disappear because a first
	# body's signal moved them, and a restore can resume only the unpaid suffix.
	_publish_authoritative_state()
	_drain_pending_batch()


func _sample_tick_cohort() -> Array:
	var cohort: Array = []
	for id in _character_ids:
		if not ("characters" in _gs) or not (_gs.get("characters") as Dictionary).has(id):
			continue
		var penalty := _penalty_for_character(id)
		if penalty <= 0.0:
			continue
		var attempted := penalty * _damage_rate_scale * _interval
		if attempted <= 0.0:
			continue
		var target := _make_damage_receipt(id, attempted)
		var cell: Vector2i = _grid.world_to_grid(_gs.get_position(id))
		target["cell"] = [cell.x, cell.y]
		target["penalty"] = penalty
		target["bookkeeping_committed"] = false
		cohort.append(target)
	return cohort


func _drain_pending_batch() -> void:
	if _pending_batch.is_empty() or _gs == null:
		return
	var targets: Array = _pending_batch.get("targets", [])
	for idx in range(targets.size()):
		var target: Dictionary = (targets[idx] as Dictionary).duplicate(true)
		var applied := float(target.get("applied_damage", 0.0))
		if not bool(target.get("damage_committed", false)):
			target["damage_committed"] = true
			if applied > 0.0 and not bool(target.get("bookkeeping_committed", false)):
				var id := str(target.get("id", ""))
				_damage_total += applied
				_contact_ticks[id] = int(_contact_ticks.get(id, 0)) + 1
				target["bookkeeping_committed"] = true
			targets[idx] = target
			_pending_batch["targets"] = targets
			_publish_authoritative_state()
		_reconcile_target_damage(target)
		if applied > 0.0 and not bool(target.get("callback_committed", false)):
			if _on_bite.is_valid():
				var cell_raw: Array = target.get("cell", [0, 0])
				_on_bite.call(
					str(target.get("id", "")),
					applied,
					Vector2i(int(cell_raw[0]), int(cell_raw[1])),
					float(target.get("penalty", 0.0))
				)
			target["callback_committed"] = true
			targets[idx] = target
			_pending_batch["targets"] = targets
			_publish_authoritative_state()
	var reserved_next := float(_pending_batch.get("next_tick", -1.0))
	_pending_batch.clear()
	if _active:
		_arm_tick_at(reserved_next if reserved_next >= 0.0 else _scheduler_tick() + _interval)
	else:
		_next_tick = -1.0
	_publish_authoritative_state()


func _make_damage_receipt(id: String, attempted_damage: float) -> Dictionary:
	var hp_before := float(_gs.get_stat(id, "hp"))
	var shield_before := _damage_shield(id)
	var absorbed := minf(shield_before, maxf(0.0, attempted_damage))
	var hp_after := maxf(0.0, hp_before - maxf(0.0, attempted_damage - absorbed))
	return {
		"id": id,
		"attempted_damage": maxf(0.0, attempted_damage),
		"applied_damage": maxf(0.0, hp_before - hp_after),
		"hp_before": hp_before,
		"hp_after": hp_after,
		"shield_before": shield_before,
		"shield_after": maxf(0.0, shield_before - maxf(0.0, attempted_damage)),
		"damage_committed": false,
		"callback_committed": false,
	}


func _reconcile_target_damage(target: Dictionary) -> void:
	var id := str(target.get("id", ""))
	if id == "" or not ("characters" in _gs) \
			or not (_gs.get("characters") as Dictionary).has(id):
		return
	var hp_before := float(target.get("hp_before", _gs.get_stat(id, "hp")))
	var hp_after := float(target.get("hp_after", hp_before))
	var shield_before := float(target.get("shield_before", _damage_shield(id)))
	var shield_after := float(target.get("shield_after", shield_before))
	var current_hp := float(_gs.get_stat(id, "hp"))
	var current_shield := _damage_shield(id)
	if is_equal_approx(current_hp, hp_after) and is_equal_approx(current_shield, shield_after):
		return
	if is_equal_approx(current_hp, hp_before) and is_equal_approx(current_shield, shield_before):
		_gs.adjust_stat(
			id,
			"hp",
			-float(target.get("attempted_damage", 0.0)),
			"grid_risk:%s" % _tag
		)
		return
	if is_equal_approx(current_shield, shield_after) and current_hp > hp_after + HP_EPSILON:
		_gs.set_stat(id, "hp", hp_after, "grid_risk:%s" % _tag)


func _damage_shield(id: String) -> float:
	return float(_gs.get_damage_shield(id)) \
		if _gs != null and _gs.has_method("get_damage_shield") else 0.0


func _penalty_for_character(character_id: String) -> float:
	if _gs == null or _grid == null or not ("characters" in _gs) \
			or not (_gs.get("characters") as Dictionary).has(character_id):
		return 0.0
	var cell: Vector2i = _grid.world_to_grid(_gs.get_position(character_id))
	var level := int(_gs.get_character_level(character_id))
	var exact_key := _cell_key(cell, level)
	if _risk_by_cell.has(exact_key):
		return float(_risk_by_cell[exact_key])
	return float(_risk_by_cell.get(_cell_key(cell, -1), 0.0))


func _set_risk_entries(entries: Array) -> void:
	_risk_by_cell.clear()
	for entry_v in entries:
		if not (entry_v is Dictionary):
			continue
		var entry := entry_v as Dictionary
		var raw_cell: Variant = entry.get("cell", [])
		if not (raw_cell is Array) or (raw_cell as Array).size() < 2:
			continue
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var level := int(entry.get("level", -1))
		var penalty := maxf(0.0, float(entry.get("penalty", 0.0)))
		if penalty <= 0.0:
			continue
		var key := _cell_key(cell, level)
		_risk_by_cell[key] = maxf(float(_risk_by_cell.get(key, 0.0)), penalty)


func _cell_key(cell: Vector2i, level: int) -> String:
	return "%d:%d:%s" % [cell.x, cell.y, "*" if level < 0 else str(level)]


func _arm_tick_at(deadline: float) -> void:
	if _scheduler == null or not _active:
		return
	_next_tick = maxf(_scheduler_tick(), deadline)
	_scheduler.schedule_after(
		maxf(0.0, _next_tick - _scheduler_tick()), _tick, _tag
	)
	_tick_armed = true


func _cancel_tick() -> void:
	_cancel_derived_callbacks()
	_pending_batch.clear()
	_next_tick = -1.0


func _cancel_derived_callbacks() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(_tag)
		_scheduler.cancel_tag(_batch_resume_tag())
	_tick_armed = false
	_batch_resume_armed = false


func _arm_batch_resume() -> void:
	if _scheduler == null or _pending_batch.is_empty():
		return
	_scheduler.cancel_tag(_batch_resume_tag())
	_scheduler.schedule_after(0.0, _resume_pending_batch, _batch_resume_tag())
	_batch_resume_armed = true


func _resume_pending_batch() -> void:
	_batch_resume_armed = false
	_drain_pending_batch()


func _batch_resume_tag() -> String:
	return "%s:batch_resume" % _tag


func _scheduler_tick() -> float:
	return float(_scheduler.get_current_tick()) if _scheduler != null else 0.0


func _publish_authoritative_state() -> void:
	if _restoring or _gs == null or not _gs.has_method("set_world_state"):
		return
	_gs.set_world_state(authority_state_key(), serialize_state())


func _exit_tree() -> void:
	# Callback teardown only. The GameState record remains the portable truth.
	_cancel_derived_callbacks()
