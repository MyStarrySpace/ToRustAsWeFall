class_name Spiker
extends Enemy

## SPIKER (fauna_roster L31): "delayed line-of-sight connection turret, static — hyperexcitable
## pyramidal neurons... ROOTED. It locks onto movement, establishes a visible connection, and deals
## damage ONLY if that connection retains clear line of sight for the full authored delay. ANY LOS
## break severs it immediately and cancels the damage. A completed discharge also draws the Tanglers
## that hunt it. Tell: one branch brightens, then a visible filament and traveling charge show the
## lock and its progress. Counter: break line of sight with terrain, Capbage, or Scarpet before the
## delay expires, or bait a Tangler onto it."
##
## Every number and rule below is that line and nothing else:
##
##  - ROOTED. move_speed 0 and no roam or patrol is ever armed. A Spiker that repositioned would be a
##    different creature; being unable to follow you IS its weakness.
##  - LOCKS ONTO MOVEMENT. It reads motion, not noise (that is the Tangler) and not enforcement flags
##    (that is the Naturalizer). A body holding still is not a lock.
##  - THE CONNECTION IS THE WHOLE ENCOUNTER. Damage lands only after `connection_delay` of UNBROKEN
##    line of sight, and the LOS is polled on the scheduler so it rides pause and fast-forward. Break
##    it once, at any point, and the charge is cancelled outright -- not paused, not resumed.
##
## Deliberately NOT here: "a completed discharge draws the Tanglers that hunt it" is emitted as a
## signal (`discharged`) for a fragment to wire, because the actual enemy-on-enemy consumption belongs
## to the inter-enemy matrix build and does not ship. Emitting the event without pretending the
## attraction is implemented keeps the gap visible.

signal connection_opened(target_id: String)
signal connection_severed(target_id: String, reason: String)
signal discharged(target_id: String, at_position: Vector3)

## How finely each movement leg is probed for a sight break. Cells are the unit the grid stores
## blockers at, and legs are cell-to-cell, so the midpoint plus the end catches a blocker crossed
## mid-leg without sampling time.
const LOS_SAMPLES_PER_LEG := 2

var _rig: FloraRig = null

@export var connection_delay := 1.8
@export var discharge_damage := 12.0

var _connection_target := ""
var _connection_started_tick := -1.0

func _ready() -> void:
	color = Color(0.86, 0.82, 0.44)
	# Rooted is enforced by REFUSING to move (see _target_engageable, set_roam, set_patrol), not by a
	# zero speed. A character registered at speed 0 divides by it in the movement maths and its
	# position comes back NaN -- measured, the body reported (nan, nan, nan) for its whole life. Keep a
	# token speed that nothing ever spends.
	move_speed = 1.0
	detection_range = 7.0
	# The base's attack cycle is a LUNGE -- pursue, wind up, charge in, strike. A Spiker does none of
	# that: it connects. Left enabled, the cycle both moved this rooted body (the charge rides
	# charge_speed, not move_speed, so zeroing move_speed alone does not hold it still, and a
	# zero-length lunge vector even produced a NaN position) and landed its own strike ON TOP of the
	# discharge, so a single connection cost the target twice. Zeroed here and refused outright below.
	charge_speed = 0.0
	charge_damage = 0.0
	super._ready()

## A Spiker NEVER engages. It has no strike and no legs; the connection is its entire offence, and it
## runs on this class's own scheduler poll. Refusing engagement keeps the body rooted and keeps the
## base from double-billing the target for one filament.
func _target_engageable() -> bool:
	return false

## A Spiker does not "notice and react" -- it connects. Refusing engagement was not enough to hold it
## still: the base still acquired, alerted and then walked toward the last known position, drifting the
## turret three metres across the room. So it keeps NO detection subscription at all. Its own poll does
## its own range and grid-LOS checks, so nothing is lost, and with the base never acquiring there is no
## alert, no search and no step.
func _sync_detection_subscription(_state: String) -> void:
	if game_state != null and game_state.has_method("set_detection_enabled") 			and game_state.characters.has(char_id):
		game_state.set_detection_enabled(char_id, false)

## A Spiker never walks. Swallow the movement verbs the base offers so a fragment cannot accidentally
## hand it a route and quietly turn a turret into a pursuer.
func set_roam(_anchor: Vector3, _radius: float) -> void:
	return

func set_patrol(_waypoints: Array) -> void:
	return

## PREDICTED WHERE IT CAN BE, AND HONEST WHERE IT CANNOT.
##
## Two of this turret's three questions are solvable in advance and are scheduled exactly:
##   - WHEN does a body come into reach? Solved from its queued movement (a proximity trigger).
##   - WHEN does an unbroken connection discharge? A known span from the moment it opens.
## The third -- WHEN does line of sight break? -- is not cheap to solve analytically, because it
## depends on the target's path crossing the shadow of arbitrary grid blockers. The shipped detection
## system makes the same compromise (_arm_detection_los_recheck) for the same reason, so this follows
## that precedent rather than inventing a second answer: LOS is re-checked only while a connection is
## OPEN and its target is actually MOVING. A parked target is frozen geometry and schedules nothing,
## where an always-on fixed-cadence poll would keep running forever, room empty or not.
func activate() -> void:
	super.activate()
	_arm_range_trigger()
	# It locks onto MOVEMENT, so a body already standing in reach becomes interesting the moment it
	# STARTS moving -- which is an event, not something to re-solve or sample for.
	if game_state != null and game_state.has_signal("movement_started") 			and not game_state.movement_started.is_connected(_on_movement_started):
		game_state.movement_started.connect(_on_movement_started)
	# A re-route mid-connection changes when (or whether) sight breaks, so the solve is redone from
	# the new plan rather than trusting the one made against the old one.
	if game_state != null and game_state.has_signal("movement_started") 			and not game_state.movement_started.is_connected(_on_target_replanned):
		game_state.movement_started.connect(_on_target_replanned)

func _on_target_replanned(moved_id: String) -> void:
	if _connection_target != "" and str(moved_id) == _connection_target:
		_watch_connection()

func _on_movement_started(moved_id: String) -> void:
	if _connection_target != "" or str(moved_id) not in _detection_targets:
		return
	_try_open_connection()
	if _connection_target != "":
		_watch_connection()

func _arm_range_trigger() -> void:
	if game_state == null or not game_state.has_method("register_proximity_trigger"):
		return
	var subjects: Array = []
	for raw_id in _detection_targets:
		subjects.append(str(raw_id))
	if subjects.is_empty():
		return
	game_state.call("register_proximity_trigger", _range_trigger_id(), char_id, subjects,
		detection_range, 1, Callable(self, "_on_body_in_reach"))

func _range_trigger_id() -> String:
	return "spiker_reach_%s" % char_id

## A body crossed into reach at the solved tick. It only becomes a lock if it is MOVING and in sight.
func _on_body_in_reach() -> void:
	if _connection_target != "":
		return
	_try_open_connection()
	if _connection_target != "":
		_watch_connection()

func _rearm_range_trigger() -> void:
	if game_state != null and game_state.has_method("unregister_proximity_trigger"):
		game_state.call("unregister_proximity_trigger", _range_trigger_id())
	_arm_range_trigger()

func _discharge_tag() -> String:
	return "spiker_discharge_%s" % char_id

func _los_tag() -> String:
	return "spiker_los_%s" % char_id

## SOLVED, NOT SAMPLED. The turret is rooted, so sight can only break because the TARGET moved -- and
## its path is known. Ask when that path first leaves sight and schedule the sever at exactly that
## tick. A parked target schedules nothing at all, because frozen geometry cannot break sight.
##
## A fixed-cadence poll would pay its cost for the whole connection (~12 checks per 1.8s lock, and
## keep paying as long as the target kept moving); solving caps an entire encounter at two scheduled
## events: the sever, or the discharge.
func _watch_connection() -> void:
	var sched = _get_scheduler()
	if sched == null or _connection_target == "":
		return
	sched.cancel_tag(_los_tag())
	if game_state == null or not game_state.has_method("predict_los_break_tick"):
		return
	var break_tick := float(game_state.call(
		"predict_los_break_tick", char_id, _connection_target))
	if break_tick < 0.0:
		return                      # sight holds for the rest of its plan; the discharge stands
	if break_tick >= _connection_started_tick + connection_delay:
		return                      # it discharges before sight is lost
	sched.schedule_at(break_tick, _on_predicted_los_break, _los_tag())

## The solved break tick. Re-read live sight before severing, exactly as a predicted detection event
## re-validates its pair -- the target may have been re-routed since the solve.
func _on_predicted_los_break() -> void:
	if _connection_target == "":
		return
	if _connection_holds(_connection_target):
		_watch_connection()
		return
	_sever("los_broken")
	_rearm_range_trigger()

## Fires at the solved discharge tick. Re-reads live sight first, exactly as a predicted detection
## event re-validates its pair before any side effect.
func _discharge_if_held() -> void:
	if _connection_target == "":
		return
	if not _connection_holds(_connection_target):
		_sever("los_broken")
		_rearm_range_trigger()
		return
	_discharge()
	_rearm_range_trigger()

func _try_open_connection() -> void:
	var gs = game_state
	if gs == null:
		return
	for raw_id in _detection_targets:
		var target_id := str(raw_id)
		if not _connection_holds(target_id):
			continue
		# LOCKS ONTO MOVEMENT: a still body is not a lock.
		if not (gs.has_method("is_moving") and bool(gs.call("is_moving", target_id))):
			continue
		_connection_target = target_id
		var sched = _get_scheduler()
		_connection_started_tick = float(sched.get_current_tick()) if sched != null else 0.0
		# The delay is a known span, so the discharge tick is known the instant the filament attaches.
		if sched != null:
			sched.cancel_tag(_discharge_tag())
			sched.schedule_after(connection_delay, _discharge_if_held, _discharge_tag())
		connection_opened.emit(target_id)
		return

## Sight is the ONLY thing holding the connection together, so it is checked against the grid every
## poll rather than trusted from acquisition -- terrain, Capbage and Scarpet all break it through the
## same call, which is exactly the counter the roster names.
func _connection_holds(target_id: String) -> bool:
	var gs = game_state
	if gs == null or not gs.characters.has(target_id):
		return false
	var stats: Dictionary = gs.characters[target_id].stats
	if stats.has("hp") and float(stats["hp"]) <= 0.0:
		return false
	if gs.has_method("is_at_shelter") and bool(gs.call("is_at_shelter", target_id)):
		return false
	var here := gs.get_position(char_id)
	var there := gs.get_position(target_id)
	if Vector2(here.x - there.x, here.z - there.z).length() > detection_range:
		return false
	if gs.grid != null and gs.grid.has_method("has_line_of_sight") \
			and not bool(gs.grid.call("has_line_of_sight", here, there)):
		return false
	return true

func _sever(reason: String) -> void:
	if _connection_target == "":
		return
	var was := _connection_target
	_connection_target = ""
	_connection_started_tick = -1.0
	connection_severed.emit(was, reason)

func _discharge() -> void:
	var gs = game_state
	var target_id := _connection_target
	if gs == null or target_id == "":
		return
	var at := gs.get_position(target_id)
	if gs.has_method("adjust_stat"):
		gs.call("adjust_stat", target_id, "hp", -discharge_damage)
	_connection_target = ""
	_connection_started_tick = -1.0
	discharged.emit(target_id, at)

## Read-only, for a fragment or a test to present the filament without reaching into private state.
func get_connection_target() -> String:
	return _connection_target

func get_connection_progress() -> float:
	if _connection_target == "" or _connection_started_tick < 0.0:
		return 0.0
	var sched = _get_scheduler()
	if sched == null:
		return 0.0
	return clampf(
		(float(sched.get_current_tick()) - _connection_started_tick) / maxf(0.001, connection_delay),
		0.0, 1.0)

func _exit_tree() -> void:
	if game_state != null and game_state.has_signal("movement_started") 			and game_state.movement_started.is_connected(_on_movement_started):
		game_state.movement_started.disconnect(_on_movement_started)
	if game_state != null and game_state.has_method("unregister_proximity_trigger"):
		game_state.call("unregister_proximity_trigger", _range_trigger_id())
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_discharge_tag())
		sched.cancel_tag(_los_tag())


## The rooted body, and the clips its own connection drives.
##
## The roster gives the read: "One branch brightens, then a visible filament and
## traveling charge show the lock and its progress." The charge climbing the
## branch IS the delay the player is racing, so it plays off the same signals the
## connection already emits rather than being timed a second time here.
##
## Cosmetic only. The connection, its delay and its damage live in the data layer;
## breaking line of sight severs it whether or not the beads have caught up.
func _build_visual() -> void:
	if not FloraRig.has_rig("spiker"):
		super._build_visual()
		return
	var rigged := FloraRig.new()
	rigged.name = "SpikerBody"
	add_child(rigged)
	if not rigged.setup("spiker"):
		rigged.queue_free()
		super._build_visual()
		return
	_rig = rigged
	# _mesh stays null, so the base class's squash-and-punch pulses no-op: a body
	# rooted to the floor reads by what its branches do, not by bouncing.
	if not connection_opened.is_connected(_on_connection_shown):
		connection_opened.connect(_on_connection_shown)
	if not connection_severed.is_connected(_on_connection_dropped):
		connection_severed.connect(_on_connection_dropped)
	if not discharged.is_connected(_on_connection_fired):
		discharged.connect(_on_connection_fired)


func _on_connection_shown(_target_id: String) -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.play("spiker_charge")


func _on_connection_dropped(_target_id: String, _reason: String) -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.play("spiker_sever")


func _on_connection_fired(_target_id: String, _at_position: Vector3) -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.play("spiker_discharge")
