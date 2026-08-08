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

const CONNECTION_POLL := 0.15
const _RESTORE_POLL_EPSILON := 0.000001

@export var connection_delay := 1.8
@export var discharge_damage := 12.0

var _connection_target := ""
var _connection_started_tick := -1.0
var _poll_deadline := -1.0

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

func activate() -> void:
	super.activate()
	_arm_connection_poll()

func _arm_connection_poll() -> void:
	var sched = _get_scheduler()
	if sched == null:
		_poll_deadline = -1.0
		return
	sched.cancel_tag(_poll_tag())
	var deadline := float(sched.get_current_tick()) + CONNECTION_POLL
	_poll_deadline = deadline
	sched.schedule_after(CONNECTION_POLL, _run_connection_poll.bind(deadline), _poll_tag())

func _poll_tag() -> String:
	return "spiker_conn_%s" % char_id

func _run_connection_poll(expected_deadline: float) -> void:
	if _poll_deadline < 0.0 or not is_equal_approx(_poll_deadline, expected_deadline):
		return
	_poll_deadline = -1.0
	_advance_connection()
	_arm_connection_poll()

## The connection: open on a MOVING body in sight, hold only while that sight is clear, discharge when
## the authored delay has elapsed. Every exit from here is one of the roster's three outcomes.
func _advance_connection() -> void:
	var gs = game_state
	if gs == null:
		return
	if _connection_target == "":
		_try_open_connection()
		return
	if not _connection_holds(_connection_target):
		_sever("los_broken")
		return
	var sched = _get_scheduler()
	if sched == null:
		return
	var elapsed := float(sched.get_current_tick()) - _connection_started_tick
	if elapsed >= connection_delay:
		_discharge()

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
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_poll_tag())
