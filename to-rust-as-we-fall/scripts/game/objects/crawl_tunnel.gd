class_name CrawlTunnel
extends Interactable

## A CRAWL MOUTH: a squeeze-through passage (wall pipe, vent, burrow) whose interior deliberately
## ignores the grid — the wall cells stay blocked; the crawl is the only way through. Click it and
## the activating member walks up, drops to a crawl (slow, CONCEAL_FULL — you are inside the tube),
## and follows the AUTHORED waypoint path out the far mouth. Tick-interpolated, so it fast-forwards
## and replays like every other move.
##
## GROUP ENTRY works like a PortalPad crossing: when the activator belongs to the current selection
## (the loader installs a group provider), the whole selection queues through — members line up at
## the mouth, enter ONE AT A TIME (a spacing gap keeps them single-file inside the tube), and each
## walks off to its own arrival slot on the far side so the exit never stacks. An activator outside
## the selection crawls alone.

signal crawl_started(who: String)
signal crawl_finished(who: String)
signal group_crawl_finished(ids: Array)
signal refused

const ENTRY_SPACING := 1.6          # in-tube distance kept between members (drives the entry gap)
const QUEUE_SLOT_GAP := 0.9         # line-up spacing outside the mouth
const ARRIVAL_RING_RADIUS := 1.6    # the walk-off fan past the exit mouth

@export var crawl_speed := 0.9

var _gs
var _waypoints: Array[Vector3] = []
var _group_provider: Callable = Callable()
var _queue: Array = []
var _queue_arrivals: Array = []
var _queue_i := 0
var _restore_speeds := {}           # char_id -> pre-crawl move speed
var _live_tags := {}                # every scheduler tag this tunnel has armed (cancelled on exit)

## Configure BEFORE adding to the tree. `waypoints` is the tube interior from just inside THIS
## mouth to the far exit (world space); the crawler's own position is prepended at entry time.
func configure(gs, mouth_world: Vector3, waypoints: Array, radius := 1.4, speed := 0.9) -> void:
	_gs = gs
	position = mouth_world
	for wp in waypoints:
		_waypoints.append(wp as Vector3)
	interaction_radius = radius
	crawl_speed = speed
	interactable_type = InteractableType.INSPECTION
	one_shot = false
	if description == "":
		description = "Crawl through"
	if tutorial_label == "":
		tutorial_label = "CRAWL"

func _ready() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := SphereShape3D.new()
		sh.radius = interaction_radius
		cs.shape = sh
		add_child(cs)
	super._ready()
	if not interacted.is_connected(_on_interacted):
		interacted.connect(_on_interacted)

func set_group_provider(provider: Callable) -> void:
	_group_provider = provider

func is_group_crawl_active() -> bool:
	return not _queue.is_empty()

## Optional activation gate, checked at interaction time: a Callable returning false refuses
## the whole activation (nothing consumed; `refused` is emitted so the host can say why). The
## lockout barricade uses it for the pair boost -- a two-person move needs two people.
var requirement: Callable = Callable()

## The grid level the crawler stands on when it emerges (-1 = keep the entry level). A gangway
## that carries you from a deck down through a building sets 0 so the exit snaps to the ground
## plane (set_character_level is logged — replay-safe like the rest of the crawl).
@export var exit_level := -1

## Whether the authored transit hides its rider (a crawl tube = CONCEAL_FULL; an open resource
## belt = exposed the whole ride). Subclasses flip it.
@export var conceal_riders := true

func _on_interacted() -> void:
	if requirement.is_valid() and not bool(requirement.call()):
		refused.emit()
		return
	var group := _group_for(str(active_character))
	if group.size() <= 1:
		if not group.is_empty():
			_begin_crawl(str(group[0]), 0)
	else:
		start_group_crawl(group)

## Who a click sends through: the selection with the activator leading when the activator belongs
## to it; otherwise just the activator (solo semantics).
func _group_for(activator: String) -> Array:
	var sel: Array = []
	if _group_provider.is_valid():
		for v in (_group_provider.call() as Array):
			var cid := str(v)
			if _gs != null and _gs.characters.has(cid) and not _gs.is_downed(cid) and not sel.has(cid):
				sel.append(cid)
	if activator != "" and sel.has(activator):
		sel.erase(activator)
		sel.push_front(activator)
		return sel
	if activator != "":
		return [activator]
	return sel

## Line-up slots outside the mouth: single file back along the approach direction (away from the
## tube), each snapped walkable. Deterministic — tests and any future ghost preview read this.
func compute_queue_slots(ids: Array) -> Array:
	var out: Array = []
	var into := _tube_dir()
	for i in range(ids.size()):
		var pos := global_position - into * (QUEUE_SLOT_GAP * float(i + 1))
		pos.y = global_position.y
		out.append(_snap_walkable(pos))
	return out

## Walk-off fan past the exit mouth, pointing onward along the tube's final direction, so nobody
## parks on the far mouth and the next crawler always has a clear exit.
func compute_group_arrivals(ids: Array) -> Array:
	var out: Array = []
	if _waypoints.is_empty():
		return out
	var exit_pos := _waypoints[_waypoints.size() - 1]
	var onward := _exit_dir()
	var base_angle := atan2(onward.z, onward.x)
	for i in range(ids.size()):
		var ang := base_angle + (float(i) - (float(ids.size()) - 1.0) * 0.5) * 0.9
		var pos := exit_pos + Vector3(cos(ang), 0.0, sin(ang)) * ARRIVAL_RING_RADIUS
		pos.y = exit_pos.y
		out.append(_snap_walkable(pos))
	return out

## Queue the whole group through: everyone lines up, then members enter one at a time with an
## in-tube spacing gap. All timing rides the gameplay scheduler (pause/fast-forward safe).
func start_group_crawl(ids: Array) -> bool:
	if _gs == null or ids.is_empty() or not _queue.is_empty():
		return false
	_queue = ids.duplicate()
	_queue_arrivals = compute_group_arrivals(ids)
	_queue_i = 0
	var slots := compute_queue_slots(ids)
	for i in range(1, ids.size()):
		var cid := str(ids[i])
		if _gs.characters.has(cid) and not _gs.is_downed(cid):
			_gs.command_move_to_pos(cid, _to_data(slots[mini(i - 1, slots.size() - 1)]))
	_enter_next()
	return true

func _enter_next() -> void:
	if _gs == null or _queue_i >= _queue.size():
		var done := _queue.duplicate()
		_queue.clear()
		if not done.is_empty():
			group_crawl_finished.emit(done)
		return
	var who := str(_queue[_queue_i])
	var slot_index := _queue_i
	_queue_i += 1
	if not _gs.characters.has(who) or _gs.is_downed(who):
		_enter_next()
		return
	# Walk this member to the mouth, crawl when the walk plan ends, and stagger the NEXT entry by
	# the in-tube spacing so the tube stays single-file.
	_gs.command_stop(who)
	_gs.command_move_to_pos(who, _to_data(global_position))
	var sched = _gs.scheduler
	if sched == null:
		_begin_crawl(who, slot_index)
		_enter_next()
		return
	var wait := 0.05
	if _gs.has_method("get_plan_end_tick"):
		var end_tick: float = _gs.get_plan_end_tick(who)
		if end_tick >= 0.0:
			wait = maxf(wait, end_tick - sched.get_current_tick() + 0.05)
	_schedule(sched, wait, func() -> void:
		_begin_crawl(who, slot_index)
		_schedule(sched, ENTRY_SPACING / maxf(0.1, crawl_speed), _enter_next, _tag() + "_next"),
		_entry_tag(who))

## Drop `who` into the tube: conceal, slow, ride the authored path, restore + walk off at the end.
func _begin_crawl(who: String, slot_index: int) -> void:
	if _gs == null or not _gs.characters.has(who) or _gs.is_downed(who):
		return
	var prior := 2.6
	var cd: Variant = _gs.characters.get(who)
	if cd is Dictionary and (cd as Dictionary).has("move_speed"):
		prior = float((cd as Dictionary)["move_speed"])
	_restore_speeds[who] = prior
	_gs.command_stop(who)
	if conceal_riders:
		_gs.set_character_concealment(who, _gs.CONCEAL_FULL)
	_gs.change_move_speed(who, crawl_speed)
	var path: Array[Vector3] = [_gs.get_position(who) as Vector3]
	var total := 0.0
	for wp in _waypoints:
		total += path[path.size() - 1].distance_to(wp)
		path.append(wp)
	_gs._start_movement(who, path)
	crawl_started.emit(who)
	var sched = _gs.scheduler
	if sched == null:
		_end_crawl(who, slot_index)
		return
	_schedule(sched, total / maxf(0.1, crawl_speed) + 0.1,
		func() -> void: _end_crawl(who, slot_index), _tag() + "_end_" + who)

func _end_crawl(who: String, slot_index: int) -> void:
	if _gs == null or not _gs.characters.has(who):
		return
	_gs.change_move_speed(who, float(_restore_speeds.get(who, 2.6)))
	_restore_speeds.erase(who)
	_gs.set_character_concealment(who, _gs.CONCEAL_NONE)
	if exit_level >= 0 and _gs.has_method("set_character_level"):
		_gs.set_character_level(who, exit_level)
	crawl_finished.emit(who)
	# Clear the exit mouth: walk off to this member's own arrival slot (group entries only).
	if slot_index >= 0 and slot_index < _queue_arrivals.size() and not _gs.is_downed(who):
		_gs.command_move_to_pos(who, _to_data(_queue_arrivals[slot_index]))

func _tube_dir() -> Vector3:
	if _waypoints.is_empty():
		return Vector3.FORWARD
	var into := _waypoints[0] - global_position
	into.y = 0.0
	return into.normalized() if into.length() > 0.01 else Vector3.FORWARD

func _exit_dir() -> Vector3:
	if _waypoints.size() >= 2:
		var d := _waypoints[_waypoints.size() - 1] - _waypoints[_waypoints.size() - 2]
		d.y = 0.0
		if d.length() > 0.01:
			return d.normalized()
	return _tube_dir()

func _snap_walkable(pos: Vector3) -> Vector3:
	if _gs != null and _gs.grid != null and _gs.grid.has_method("nearest_walkable_world"):
		var snapped_pos: Vector3 = _gs.grid.nearest_walkable_world(pos)
		snapped_pos.y = pos.y
		return snapped_pos
	return pos

func _to_data(world_pos: Vector3) -> Vector3:
	if _gs != null and _gs.coord_map != null:
		return _gs.coord_map.to_data(world_pos)
	return world_pos

func _tag() -> String:
	return "crawl_tunnel_" + str(name)

func _entry_tag(who: String) -> String:
	return _tag() + "_enter_" + who

## Every schedule goes through here: replace any prior event on the tag and remember the tag, so
## _exit_tree can cancel EVERYTHING this tunnel armed (a freed tunnel must leave no live lambdas).
func _schedule(sched, wait: float, fn: Callable, tag: String) -> void:
	sched.cancel_tag(tag)
	_live_tags[tag] = true
	sched.schedule_after(wait, fn, tag)

func _exit_tree() -> void:
	if _gs != null and _gs.scheduler != null:
		for tag in _live_tags.keys():
			_gs.scheduler.cancel_tag(tag)
	_live_tags.clear()
