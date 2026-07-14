class_name HazardField
extends Node3D

## A cadenced area-damage field (P-KIT): the kit home for "standing here hurts on a beat" --
## popcorn fire, a flare lane, vented steam. The level PLACES it and toggles it from its own
## visible mechanism (a burst gas sac, a valve, a lever); the field owns the consequence. It
## bites only ground-level bodies among the ids it was configured with, on the gameplay
## scheduler (so it pauses and fast-forwards with everything else).

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

## rect_min/rect_max are world-XZ corners. opts: dps_tick, interval, tag, on_bite (id) -> void.
func setup(gs, scheduler, rect_min: Vector2, rect_max: Vector2, ids: Array, opts: Dictionary = {}) -> void:
	_gs = gs
	_scheduler = scheduler
	_min = rect_min
	_max = rect_max
	_ids = ids
	_dps_tick = float(opts.get("dps_tick", 2.5))
	_interval = float(opts.get("interval", 1.0))
	_tag = str(opts.get("tag", "hazard_field"))
	_on_bite = opts.get("on_bite", Callable())

func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	if _scheduler == null:
		return
	_scheduler.cancel_tag(_tag)
	if on:
		_scheduler.schedule_after(_interval, _bite, _tag)

func is_active() -> bool:
	return _active

func _bite() -> void:
	if not _active or _gs == null or _scheduler == null:
		return
	for id_v in _ids:
		var id := str(id_v)
		if not _gs.characters.has(id):
			continue
		var p: Vector3 = _gs.get_position(id)
		if p.y > 1.5:
			continue
		if p.x > _min.x and p.x < _max.x and p.z > _min.y and p.z < _max.y:
			_gs.adjust_stat(id, "hp", -_dps_tick)
			if _on_bite.is_valid():
				_on_bite.call(id)
	_scheduler.schedule_after(_interval, _bite, _tag)
