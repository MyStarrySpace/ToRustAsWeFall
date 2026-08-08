class_name HazardField
extends Node3D

## A cadenced area-damage field (P-KIT): the kit home for "standing here hurts on a beat" --
## popcorn fire, a flare lane, vented steam. The level PLACES it and toggles it from its own
## visible mechanism (a burst gas sac, a valve, a lever); the field owns the consequence. It
## bites only ground-level bodies among the ids it was configured with, on the gameplay
## scheduler (so it pauses and fast-forwards with everything else).

const STATE_CONTRACT := "hazard_field/v2"
const LEGACY_STATE_CONTRACT := "hazard_field/v1"
const MIN_INTERVAL := 0.000001
const HP_EPSILON := 0.0001

var _gs = null
var _scheduler = null
var _min := Vector2.ZERO
var _max := Vector2.ZERO
var _ids: Array = []
var _dps_tick := 2.5
var _interval := 1.0
var _tag := "hazard_field"
var _active := false
var _on_bite := Callable()
var _target_filter := Callable()
var _bite_armed := false
var _next_bite_tick := -1.0
var _pending_batch: Dictionary = {}
var _batch_resume_armed := false
var _restoring := false
var _cadence_rearm_source := ""
var _cadence_rearm_cue := ""
var _cadence_rearm_tick := -1.0

## rect_min/rect_max are world-XZ corners. opts: dps_tick, interval, tag,
## target_filter(id, position) -> bool, on_bite(id) -> void, restore_existing_authority.
## The filter is derived scene wiring (for cover/immunity rules); phase/deadline remain portable.
## Streamed authored fields opt into restoring an already-loaded record during setup so construction
## cannot rebase its active cadence before the normal post-load presenter attachment seam.
func setup(gs, scheduler, rect_min: Vector2, rect_max: Vector2, ids: Array, opts: Dictionary = {}) -> void:
	# Reconfiguration invalidates the old derived callback before replacing its tag/scheduler.
	# Preserve whether the world mechanism was active: callers may refresh bindings while it burns.
	var was_active := _active
	_cancel_bite()
	_gs = gs
	_scheduler = scheduler
	_min = rect_min
	_max = rect_max
	_ids = ids.duplicate()
	_dps_tick = maxf(0.0, float(opts.get("dps_tick", 2.5)))
	_interval = maxf(MIN_INTERVAL, float(opts.get("interval", 1.0)))
	_tag = str(opts.get("tag", "hazard_field"))
	_on_bite = opts.get("on_bite", Callable())
	_target_filter = opts.get("target_filter", Callable())
	if bool(opts.get("restore_existing_authority", false)) and restore_from_authority():
		return
	_clear_cadence_rearm_provenance()
	_active = was_active
	if _active:
		_arm_bite_at(_scheduler_tick() + _interval)
	_publish_authoritative_state()

func set_active(on: bool) -> void:
	if _active == on and (not on or _bite_armed or not _pending_batch.is_empty()):
		return
	_active = on
	_cancel_derived_callbacks()
	_clear_cadence_rearm_provenance()
	if _pending_batch.is_empty():
		_next_bite_tick = -1.0
	if on and _pending_batch.is_empty():
		_arm_bite_at(_scheduler_tick() + _interval)
	_publish_authoritative_state()


## Rebase an already-visible field's next pulse from a player-facing mechanism
## commitment. Unlike set_active(false/true), this never creates an unrenderable
## off/on state between frames. The source and cue remain in portable authority so
## presentation and replay can explain why this cadence starts at this tick.
func rearm_cadence_from_visible_commitment(
		source_id: StringName, cue_id: StringName) -> bool:
	if not _active or _scheduler == null or _gs == null \
			or not _pending_batch.is_empty() \
			or String(source_id).is_empty() or String(cue_id).is_empty():
		return false
	_cancel_derived_callbacks()
	_cadence_rearm_source = String(source_id)
	_cadence_rearm_cue = String(cue_id)
	_cadence_rearm_tick = _scheduler_tick()
	_arm_bite_at(_cadence_rearm_tick + _interval)
	_publish_authoritative_state()
	return true

func is_active() -> bool:
	return _active

func _bite() -> void:
	_bite_armed = false
	_next_bite_tick = -1.0
	if not _active or _gs == null or _scheduler == null:
		_publish_authoritative_state()
		return
	_pending_batch = {
		"started_tick": _scheduler_tick(),
		"next_bite_tick": _scheduler_tick() + _interval,
		"targets": _sample_bite_cohort(),
	}
	_next_bite_tick = float(_pending_batch.get("next_bite_tick", -1.0))
	# Publish the complete physical cohort and future cadence before the first target can emit a
	# synchronous stat signal. A save made from that signal can therefore resume the unpaid suffix
	# instead of replaying the whole beat or forgetting everyone after the first body.
	_publish_authoritative_state()
	_drain_pending_batch()


func _sample_bite_cohort() -> Array:
	var cohort: Array = []
	for id_v in _ids:
		var id := str(id_v)
		if not _gs.characters.has(id):
			continue
		var p: Vector3 = _gs.get_position(id)
		if p.y > 1.5:
			continue
		if p.x > _min.x and p.x < _max.x and p.z > _min.y and p.z < _max.y:
			if _target_filter.is_valid() and not bool(_target_filter.call(id, p)):
				continue
			cohort.append(_make_damage_receipt(id, _dps_tick))
	return cohort


func _drain_pending_batch() -> void:
	if _pending_batch.is_empty() or _gs == null:
		return
	var targets: Array = _pending_batch.get("targets", [])
	for idx in range(targets.size()):
		var target: Dictionary = (targets[idx] as Dictionary).duplicate(true)
		if not bool(target.get("damage_committed", false)):
			# The receipt is committed before adjust_stat: stat_changed handlers then serialize a
			# record that says exactly which target owns this payment. hp_before/hp_after lets a
			# restore distinguish the tiny pre-signal reservation seam from the post-signal seam.
			target["damage_committed"] = true
			targets[idx] = target
			_pending_batch["targets"] = targets
			_publish_authoritative_state()
		_reconcile_target_damage(target)
		if not bool(target.get("callback_committed", false)):
			if _on_bite.is_valid():
				_on_bite.call(str(target.get("id", "")))
			target["callback_committed"] = true
			targets[idx] = target
			_pending_batch["targets"] = targets
			_publish_authoritative_state()
	var reserved_next := float(_pending_batch.get("next_bite_tick", -1.0))
	_pending_batch.clear()
	# A bite callback is allowed to toggle the visible mechanism. Do not resurrect a field that its
	# own consequence just disabled.
	if _active:
		_arm_bite_at(reserved_next if reserved_next >= 0.0 else _scheduler_tick() + _interval)
	else:
		_next_bite_tick = -1.0
	_publish_authoritative_state()


func _make_damage_receipt(id: String, attempted_damage: float) -> Dictionary:
	var hp_before := float(_gs.get_stat(id, "hp"))
	var shield_before := _damage_shield(id)
	var absorbed := minf(shield_before, maxf(0.0, attempted_damage))
	var hp_after := maxf(0.0, hp_before - maxf(0.0, attempted_damage - absorbed))
	return {
		"id": id,
		"attempted_damage": maxf(0.0, attempted_damage),
		"hp_before": hp_before,
		"hp_after": hp_after,
		"shield_before": shield_before,
		"shield_after": maxf(0.0, shield_before - maxf(0.0, attempted_damage)),
		"damage_committed": false,
		"callback_committed": false,
	}


func _reconcile_target_damage(target: Dictionary) -> void:
	var id := str(target.get("id", ""))
	if id == "" or not _gs.characters.has(id):
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
		_gs.adjust_stat(id, "hp", -float(target.get("attempted_damage", 0.0)))
		return
	# A damage shield emits before set_stat. If a save is taken from that shield signal, the shield
	# payment is already canonical while HP is not. Finish only the missing HP suffix without
	# charging the shield a second time.
	if is_equal_approx(current_shield, shield_after) and current_hp > hp_after + HP_EPSILON:
		_gs.set_stat(id, "hp", hp_after)


func _damage_shield(id: String) -> float:
	return float(_gs.get_damage_shield(id)) \
		if _gs != null and _gs.has_method("get_damage_shield") else 0.0


## Portable phase data. The absolute deadline is the authority; remaining time is diagnostic and
## provides compatibility for standalone snapshots that carry no serialized scheduler clock.
func get_state() -> Dictionary:
	var remaining := -1.0
	if (_bite_armed or not _pending_batch.is_empty()) and _next_bite_tick >= 0.0:
		remaining = maxf(0.0, _next_bite_tick - _scheduler_tick())
	return {
		"contract": STATE_CONTRACT,
		"tag": _tag,
		"active": _active,
		"bite_armed": _bite_armed,
		"next_bite_tick": _next_bite_tick,
		"next_bite_in": remaining,
		"interval": _interval,
		"damage_per_bite": _dps_tick,
		"pending_batch": _pending_batch.duplicate(true),
		"cadence_rearm_source": _cadence_rearm_source,
		"cadence_rearm_cue": _cadence_rearm_cue,
		"cadence_rearm_tick": _cadence_rearm_tick,
	}


func serialize_state() -> Dictionary:
	return get_state().duplicate(true)


## Rebuild the one derived scheduler callback from GameState truth. Restoration emits no bite and
## writes no replacement record, so loading an earlier snapshot can retract later damage cleanly.
func restore_state(snapshot: Dictionary) -> bool:
	var contract := str(snapshot.get("contract", ""))
	if contract != STATE_CONTRACT and contract != LEGACY_STATE_CONTRACT:
		return false
	if str(snapshot.get("tag", "")) != _tag or _scheduler == null or _gs == null:
		return false
	var saved_interval := float(snapshot.get("interval", -1.0))
	var saved_damage := float(snapshot.get("damage_per_bite", -1.0))
	if saved_interval < MIN_INTERVAL or saved_damage < 0.0:
		return false

	_restoring = true
	_cancel_derived_callbacks()
	_interval = saved_interval
	_dps_tick = saved_damage
	_active = bool(snapshot.get("active", false))
	_pending_batch = (snapshot.get("pending_batch", {}) as Dictionary).duplicate(true) \
		if contract == STATE_CONTRACT else {}
	_cadence_rearm_source = str(snapshot.get("cadence_rearm_source", "")) \
		if contract == STATE_CONTRACT else ""
	_cadence_rearm_cue = str(snapshot.get("cadence_rearm_cue", "")) \
		if contract == STATE_CONTRACT else ""
	_cadence_rearm_tick = float(snapshot.get("cadence_rearm_tick", -1.0)) \
		if contract == STATE_CONTRACT else -1.0
	_bite_armed = false
	_next_bite_tick = float(snapshot.get("next_bite_tick", -1.0))
	if not _pending_batch.is_empty():
		var batch_deadline := float(_pending_batch.get("next_bite_tick", _next_bite_tick))
		_next_bite_tick = batch_deadline
		_arm_batch_resume()
	elif _active and bool(snapshot.get("bite_armed", false)):
		var deadline := _next_bite_tick
		if deadline < 0.0:
			var saved_remaining := float(snapshot.get("next_bite_in", -1.0))
			if saved_remaining < 0.0:
				_restoring = false
				return false
			deadline = _scheduler_tick() + saved_remaining
		_arm_bite_at(maxf(_scheduler_tick(), deadline))
	_restoring = false
	return true


## Stable GameState.world_state address. Tags are already required to be unique per scene.
func authority_state_key() -> String:
	return "kit:hazard_field:%s" % _tag


func restore_from_authority() -> bool:
	if _gs == null or not _gs.has_method("get_world_state"):
		return false
	var saved: Variant = _gs.get_world_state(authority_state_key(), null)
	return restore_state(saved as Dictionary) if saved is Dictionary else false


## TutorialSequence calls this after replacing GameState and clearing the scheduler callback heap.
func on_game_state_snapshot_restored() -> void:
	if restore_from_authority():
		return
	# Absence is authoritative too: an earlier save may predate this dynamically spawned/activated
	# field. Never preserve the presenter's later `_active` bit across that rollback.
	_cancel_bite()
	_pending_batch.clear()
	_active = false
	_clear_cadence_rearm_provenance()


func _arm_bite_at(deadline: float) -> void:
	if _scheduler == null or not _active:
		return
	_next_bite_tick = maxf(_scheduler_tick(), deadline)
	_scheduler.schedule_after(
		maxf(0.0, _next_bite_tick - _scheduler_tick()), _bite, _tag
	)
	_bite_armed = true


func _cancel_bite() -> void:
	_cancel_derived_callbacks()
	_pending_batch.clear()
	_next_bite_tick = -1.0


func _cancel_derived_callbacks() -> void:
	if _scheduler != null:
		_scheduler.cancel_tag(_tag)
		_scheduler.cancel_tag(_batch_resume_tag())
	_bite_armed = false
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


func _clear_cadence_rearm_provenance() -> void:
	_cadence_rearm_source = ""
	_cadence_rearm_cue = ""
	_cadence_rearm_tick = -1.0


func _publish_authoritative_state() -> void:
	if _restoring or _gs == null or not _gs.has_method("set_world_state"):
		return
	_gs.set_world_state(authority_state_key(), serialize_state())


func _exit_tree() -> void:
	# Presenter teardown retracts Callables but must not rewrite saved world truth.
	_cancel_derived_callbacks()
