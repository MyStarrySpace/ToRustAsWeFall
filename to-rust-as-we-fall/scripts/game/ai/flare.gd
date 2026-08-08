class_name Flare
extends Enemy

## FLARE (fauna_roster L33, renamed from Neutros): "triggered bomb, mid — neutrophils; a multi-lobed
## nucleus and three granule classes, the burst being collateral oxidative damage. Inert until set
## off, then a short bright wind-up and an area burst that hits friend and foe. Careless fire and
## bunching set it off, and the savvy play is triggering it yourself (Myke's flame) into a group.
## Tell: the membrane swells and brightens for two or three seconds. Counter: leave the radius, do
## not cluster near one, or pop it on purpose."
##
## Every rule below is that line and nothing else:
##
##  - INERT UNTIL SET OFF. It never notices, never approaches, never picks a target. A Flare that
##    hunted would be a Gnawer. It is scenery until something crowds it.
##  - BUNCHING SETS IT OFF. The trigger is DENSITY near the body, not identity: `bunch_count` bodies
##    inside `bunch_radius`. It counts ANY registered body, so an enemy pack that crowds it arms it
##    exactly as a careless party does -- bunching is bunching, whoever crowds.
##  - THE WIND-UP IS THE WHOLE COUNTERPLAY, AND IT DOES NOT CANCEL. This is the deliberate inversion
##    of the Spiker: breaking a Spiker's line of sight SEVERS its connection, but stepping out of a
##    primed Flare only saves the body that stepped. The burst still happens. "Leave the radius" is
##    the roster's counter, and it is a counter for YOU, not a way to switch the bomb back off.
##  - HITS FRIEND AND FOE. The burst damages every body in radius at the moment it goes, party and
##    enemy alike. That is what makes "pop it on purpose" a real play rather than a flavour line.
##
## Rooted and inert are enforced the way the Spiker proved out: refuse engagement so the base's
## lunge cycle never arms (it would both move this body and double-bill the target on top of the
## burst), keep no detection subscription (refusing engagement alone still let the base acquire,
## alert and walk), and keep a TOKEN move_speed because a character registered at speed 0 divides by
## it and reports its position as NaN for its whole life.
##
## Deliberately NOT here: "careless FIRE sets it off" -- ignition is the other half of the roster
## trigger and there is no shipped fire/ignition source to read, so only the bunching half is
## implemented. `pop()` exposes the deliberate trigger so a fragment that does have an ignition
## source can wire it without this class pretending to own one.

signal primed(trigger_ids: Array)
signal burst(at_position: Vector3, hit_ids: Array)

const PRIME_POLL := 0.2

## Canon says two or three seconds of swelling membrane. The window has to be long enough to walk
## out of, because walking out is the entire answer.
@export var windup_delay := 2.5
@export var bunch_radius := 2.6
@export var bunch_count := 2
@export var burst_radius := 3.2
@export var burst_damage := 18.0

var _state_name := "inert"          # inert | priming | spent
var _prime_deadline := -1.0
var _primed_at_tick := -1.0

func _ready() -> void:
	# Granule pallor while inert; the swell repaints toward white-hot.
	color = Color(0.72, 0.66, 0.30)
	move_speed = 1.0
	charge_speed = 0.0
	charge_damage = 0.0
	detection_range = 0.0
	super._ready()

## A Flare never engages: it has no strike, no legs and no target. The burst is its entire offence
## and it runs on this class's own poll.
func _target_engageable() -> bool:
	return false

## It does not spot anything -- it is set off. Keeping no subscription is what actually holds the
## body still; refusing engagement alone still let the base acquire, alert and step toward a last
## known position.
func _sync_detection_subscription(_state: String) -> void:
	if game_state != null and game_state.has_method("set_detection_enabled") \
			and game_state.characters.has(char_id):
		game_state.set_detection_enabled(char_id, false)

func set_roam(_anchor: Vector3, _radius: float) -> void:
	return

func set_patrol(_waypoints: Array) -> void:
	return

func activate() -> void:
	super.activate()
	_arm_prime_poll()

func _arm_prime_poll() -> void:
	var sched = _get_scheduler()
	if sched == null:
		_prime_deadline = -1.0
		return
	sched.cancel_tag(_poll_tag())
	var deadline := float(sched.get_current_tick()) + PRIME_POLL
	_prime_deadline = deadline
	sched.schedule_after(PRIME_POLL, _run_prime_poll.bind(deadline), _poll_tag())

func _poll_tag() -> String:
	return "flare_prime_%s" % char_id

func _run_prime_poll(expected_deadline: float) -> void:
	if _prime_deadline < 0.0 or not is_equal_approx(_prime_deadline, expected_deadline):
		return
	_prime_deadline = -1.0
	_advance()
	if _state_name != "spent":
		_arm_prime_poll()

func _advance() -> void:
	if game_state == null:
		return
	match _state_name:
		"inert":
			var crowd := bodies_in_bunch_radius()
			if crowd.size() >= bunch_count:
				_prime(crowd)
		"priming":
			var sched = _get_scheduler()
			if sched == null:
				return
			if float(sched.get_current_tick()) - _primed_at_tick >= windup_delay:
				_burst()

## Who is currently crowding it. Public so a fragment can show the count and a test can assert the
## trigger without reaching into private state.
func bodies_in_bunch_radius() -> Array:
	return _bodies_within(bunch_radius)

func _bodies_within(radius: float) -> Array:
	var found: Array[String] = []
	if game_state == null:
		return found
	var here := game_state.get_position(char_id)
	for id_v in game_state.characters.keys():
		var other_id := str(id_v)
		if other_id == char_id:
			continue
		var there: Vector3 = game_state.get_position(other_id)
		if Vector2(here.x - there.x, here.z - there.z).length() <= radius:
			found.append(other_id)
	return found

## The deliberate trigger -- the roster's "pop it on purpose". Same path as bunching, so a popped
## Flare and a crowded one behave identically from here on.
func pop() -> void:
	if _state_name != "inert":
		return
	_prime(bodies_in_bunch_radius())

func _prime(trigger_ids: Array) -> void:
	if _state_name != "inert":
		return
	var sched = _get_scheduler()
	_state_name = "priming"
	_primed_at_tick = float(sched.get_current_tick()) if sched != null else 0.0
	primed.emit(trigger_ids)

## The burst reads the room at the moment it goes, never at the moment it was armed. That is what
## makes stepping out work and what makes it hit friend and foe without special-casing either: the
## party carry hp stats in GameState, enemy bodies carry their own, so both are paid.
func _burst() -> void:
	if game_state == null:
		return
	_state_name = "spent"
	_primed_at_tick = -1.0
	var here := game_state.get_position(char_id)
	var caught := _bodies_within(burst_radius)
	for id_v in caught:
		var hit_id := str(id_v)
		var stats: Dictionary = game_state.characters[hit_id].stats
		if stats.has("hp") and game_state.has_method("adjust_stat"):
			game_state.call("adjust_stat", hit_id, "hp", -burst_damage)
	for body in _enemy_bodies_within(burst_radius):
		body.call("take_damage", burst_damage)
	burst.emit(here, caught)

## Enemy bodies keep their hp on the node rather than in GameState stats, so friend-and-foe needs
## this second pass. A one-shot walk at the moment of the burst, never a per-frame scan.
func _enemy_bodies_within(radius: float) -> Array:
	var found: Array = []
	var root := get_tree().get_root() if get_tree() != null else null
	if root == null or game_state == null:
		return found
	var here := game_state.get_position(char_id)
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node == self or not (node is Enemy) or not node.has_method("take_damage"):
			continue
		if not (node as Node3D).is_inside_tree():
			continue
		var there: Vector3 = (node as Node3D).global_position
		if Vector2(here.x - there.x, here.z - there.z).length() <= radius:
			found.append(node)
	return found

## Read-only state for a fragment's readout and for tests.
func get_flare_state() -> String:
	return _state_name

func is_primed() -> bool:
	return _state_name == "priming"

## 0..1 across the swell, for the cosmetic membrane and a fragment's meter. Cosmetic only -- the
## burst fires off the scheduler poll, never off this.
func get_prime_progress() -> float:
	if _state_name != "priming" or _primed_at_tick < 0.0:
		return 0.0
	var sched = _get_scheduler()
	if sched == null:
		return 0.0
	return clampf(
		(float(sched.get_current_tick()) - _primed_at_tick) / maxf(0.001, windup_delay),
		0.0, 1.0)

func _exit_tree() -> void:
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_poll_tag())
