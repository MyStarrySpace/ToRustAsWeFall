class_name AlignmentCrossing
extends CrawlTunnel

## A PHASE-GATED crawl mouth: a CrawlTunnel whose passage only physically exists in WINDOWS (the
## Paranucleus wheel gaps; any future rotating/cyclic barrier). The command grammar stays queued
## and committed: ordering the thread OUTSIDE a window is not a refusal — the group lines up at
## the mouth and the crawl LAUNCHES on the next window's tick, predicted analytically from the
## gate's pure phase functions (never sampled per frame — the puzzle-fast-forward law). A trigger
## is logged like any interaction, and the launch tick is pure f(trigger tick), so replay and
## fast-forward reproduce the same crossing exactly.
##
## The gate callables come from the owning level:
##   checker(tick)   -> bool   the passage is physically open at this tick
##   next_open(tick) -> float  the first tick >= `tick` when it opens (< 0 = none in horizon)
## The VIEW rule (which vantage lets a player commit at all) stays at the enabled layer — the
## level enables/disables the mouth; this class owns only the physical window.

var _checker: Callable = Callable()
var _next_open: Callable = Callable()
var _pending_launch := false

func set_window_gate(checker: Callable, next_open: Callable) -> void:
	_checker = checker
	_next_open = next_open

## Anyone inside the tube (or committed to enter): the wheel must not be moved under them.
func has_occupants() -> bool:
	return _pending_launch or not _restore_speeds.is_empty() or is_group_crawl_active()

func _on_interacted() -> void:
	if _gs == null:
		return
	var sched = _gs.scheduler
	var now := float(sched.get_current_tick()) if sched != null else 0.0
	if not _checker.is_valid() or bool(_checker.call(now)):
		super._on_interacted()
		return
	# closed: QUEUE the order — line the group up at the mouth and launch on the predicted window
	if _pending_launch:
		return
	var launch := float(_next_open.call(now)) if _next_open.is_valid() else -1.0
	if launch < 0.0 or sched == null:
		return   # no window in the horizon: the order cannot be taken
	var group := _group_for(str(active_character))
	if group.is_empty():
		return
	_pending_launch = true
	var slots := compute_queue_slots(group)
	for i in range(group.size()):
		var cid := str(group[i])
		if _gs.characters.has(cid) and not _gs.is_downed(cid):
			_gs.command_move_to_pos(cid, _to_data(slots[mini(i, slots.size() - 1)]))
	_schedule(sched, launch - now + 0.05, func() -> void: _launch_queued(group), _tag() + "_launch")

func _launch_queued(group: Array) -> void:
	_pending_launch = false
	if _gs == null:
		return
	var sched = _gs.scheduler
	var now := float(sched.get_current_tick()) if sched != null else 0.0
	if _checker.is_valid() and not bool(_checker.call(now)):
		# the window moved out from under the prediction (a re-parked ring): re-queue once forward
		var launch := float(_next_open.call(now)) if _next_open.is_valid() else -1.0
		if launch >= 0.0 and sched != null:
			_pending_launch = true
			_schedule(sched, launch - now + 0.05, func() -> void: _launch_queued(group), _tag() + "_launch")
		return
	if group.size() <= 1:
		if not group.is_empty():
			_begin_crawl(str(group[0]), 0)
	else:
		start_group_crawl(group)
