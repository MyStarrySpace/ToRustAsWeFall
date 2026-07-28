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
var _pending_group: Array = []
var _launch_deadline := -1.0

func set_window_gate(checker: Callable, next_open: Callable) -> void:
	_checker = checker
	_next_open = next_open

## Anyone inside the tube (or committed to enter): the wheel must not be moved under them.
func has_occupants() -> bool:
	return _pending_launch or not _crawl_traversals.is_empty() \
			or not _restore_speeds.is_empty() or is_group_crawl_active()

func _has_subclass_pending_activation() -> bool:
	return _pending_launch


func _accept_interaction_receipt(receipt: Dictionary) -> bool:
	if _gs == null:
		return false
	var sched = _gs.scheduler
	var now := float(sched.get_current_tick()) if sched != null else 0.0
	if not _checker.is_valid() or bool(_checker.call(now)):
		return super._accept_interaction_receipt(receipt)
	# closed: QUEUE the order — line the group up at the mouth and launch on the predicted window
	if _pending_launch:
		return false
	var launch := float(_next_open.call(now)) if _next_open.is_valid() else -1.0
	if launch < 0.0 or sched == null:
		refused.emit()
		return false   # no window in the horizon: the order cannot be taken
	var group := (receipt.get("group", []) as Array).duplicate()
	if group.is_empty():
		refused.emit()
		return false
	_pending_launch = true
	_pending_group = group.duplicate()
	_launch_deadline = launch + 0.05
	_activation_receipt = receipt.duplicate(true)
	_activation_receipt["phase"] = "alignment_wait"
	# Consequence authority comes first: a movement_started observer must already see the exact
	# predicted window/group receipt that caused this lineup.
	_schedule_crawl_phase("alignment_launch", _launch_deadline)
	var slots := compute_queue_slots(group)
	for i in range(group.size()):
		var cid := str(group[i])
		if _gs.characters.has(cid) and not _gs.is_downed(cid):
			_gs.command_move_to_pos(cid, _to_data(slots[mini(i, slots.size() - 1)]))
	return true

func _launch_queued() -> void:
	var group := _pending_group.duplicate()
	_pending_launch = false
	_launch_deadline = -1.0
	if _gs == null:
		_pending_group.clear()
		return
	var sched = _gs.scheduler
	var now := float(sched.get_current_tick()) if sched != null else 0.0
	if _checker.is_valid() and not bool(_checker.call(now)):
		# the window moved out from under the prediction (a re-parked ring): re-queue once forward
		var launch := float(_next_open.call(now)) if _next_open.is_valid() else -1.0
		if launch >= 0.0 and sched != null:
			_pending_launch = true
			_launch_deadline = launch + 0.05
			_schedule_crawl_phase("alignment_launch", _launch_deadline)
		else:
			_pending_group.clear()
			_activation_receipt.clear()
			_publish_crawl_authority()
		return
	_pending_group.clear()
	if not _activation_receipt.is_empty():
		_activation_receipt["phase"] = "alignment_released"
	_publish_crawl_authority()
	if not group.is_empty() \
			and not _commit_group_crawl_from_receipt(group, _activation_receipt):
		_activation_receipt.clear()
		refused.emit()
		_publish_crawl_authority()


func _run_custom_crawl_phase(kind: String, _who: String, _slot: int) -> void:
	if kind == "alignment_launch":
		_launch_queued()
	else:
		super._run_custom_crawl_phase(kind, _who, _slot)


func _crawl_authority_payload() -> Dictionary:
	var payload := super._crawl_authority_payload()
	payload["alignment"] = {
		"pending": _pending_launch,
		"group": _pending_group.duplicate(),
		"deadline": _launch_deadline,
	}
	return payload


func on_game_state_snapshot_restored() -> void:
	_pending_launch = false
	_pending_group.clear()
	_launch_deadline = -1.0
	if _gs == null:
		super.on_game_state_snapshot_restored()
		return
	var key := _crawl_authority_key()
	var saved: Variant = _gs.get_world_state(key, {}) if key != "" \
			and _gs.has_method("get_world_state") else {}
	if saved is Dictionary and int(saved.get("version", 0)) in [
			LEGACY_CRAWL_AUTHORITY_VERSION, CRAWL_AUTHORITY_VERSION]:
		var alignment: Dictionary = saved.get("alignment", {})
		_pending_launch = bool(alignment.get("pending", false))
		for who_v in (alignment.get("group", []) as Array):
			_pending_group.append(str(who_v))
		_launch_deadline = float(alignment.get("deadline", -1.0))
	# Base reconciliation consults _has_subclass_pending_activation(), so restore this transaction
	# first. A fresh load cannot then accept another receipt over a saved predicted-window order.
	super.on_game_state_snapshot_restored()
