class_name Flare
extends Enemy

## FLARE (fauna_roster L33; the neutrophil entry): "triggered bomb, mid — neutrophils; a multi-lobed
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
##    inside `bunch_radius`. It counts any registered body that can CROWD, so an enemy pack that
##    crowds it arms it exactly as a careless party does -- bunching is bunching, whoever crowds.
##    The one exclusion is other Flares: a rooted bomb is scenery that sits there, not a body that
##    crowds, and counting them would make the roster's own "Flare cluster" self-detonate at boot.
##  - THE WIND-UP IS THE WHOLE COUNTERPLAY, AND IT DOES NOT CANCEL. This is the deliberate inversion
##    of the Spiker: breaking a Spiker's line of sight SEVERS its connection, but stepping out of a
##    primed Flare only saves the body that stepped. The burst still happens. "Leave the radius" is
##    the roster's counter, and it is a counter for YOU, not a way to switch the bomb back off.
##  - HITS FRIEND AND FOE. The burst damages every body in radius at the moment it goes, party and
##    enemy alike. That is what makes "pop it on purpose" a real play rather than a flavour line.
##
## Rooted and inert are enforced the same way as the Spiker: refuse engagement so the base's
## lunge cycle never arms (it would both move this body and double-bill the target on top of the
## burst), keep no detection subscription (refusing engagement alone still lets the base acquire,
## alert and walk), and keep a TOKEN move_speed because a character registered at speed 0 divides by
## it and reports its position as NaN for its whole life.
##
## Deliberately NOT here: "careless FIRE sets it off" -- ignition is the other half of the roster
## trigger and there is no shipped fire/ignition source to read, so only the bunching half is
## implemented. `pop()` exposes the deliberate trigger so a fragment that does have an ignition
## source can wire it without this class pretending to own one.

signal primed(trigger_ids: Array)
signal burst(at_position: Vector3, hit_ids: Array)

## Canon says two or three seconds of swelling membrane. The window has to be long enough to walk
## out of, because walking out is the entire answer.
@export var windup_delay := 2.5
@export var bunch_radius := 2.6
@export var bunch_count := 2
@export var burst_radius := 3.2
@export var burst_damage := 18.0

## Live Flare bodies, by char_id. A Flare is a REGISTERED body like any other, so without this a
## bed would read its own neighbours as a crowd and every Flare in it would arm at boot -- which
## would make the roster's "Flare cluster" impossible to build. A rooted bomb is not a body that
## crowds: it is scenery that sits there.
static var _flare_body_ids: Dictionary = {}

var _state_name := "inert"          # inert | priming | spent
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
## body still; refusing engagement alone still lets the base acquire, alert and step toward a last
## known position.
func _sync_detection_subscription(_state: String) -> void:
	if game_state != null and game_state.has_method("set_detection_enabled") \
			and game_state.characters.has(char_id):
		game_state.set_detection_enabled(char_id, false)

func set_roam(_anchor: Vector3, _radius: float) -> void:
	return

func set_patrol(_waypoints: Array) -> void:
	return

## PREDICTED, NOT POLLED. A polled count resolves the trigger up to its period late, and its answer
## depends on the sampling rate rather than on the movement that caused it. GameState SOLVES for
## the exact tick a queued move brings enough bodies inside the bunch radius and schedules that,
## re-solving whenever anybody's movement changes.
func activate() -> void:
	super.activate()
	_flare_body_ids[char_id] = true
	_arm_bunch_trigger()

func _arm_bunch_trigger() -> void:
	if game_state == null or not game_state.has_method("register_proximity_trigger"):
		return
	# ANY body can crowd it, not just declared targets: an enemy pack that bunches on a Flare arms it
	# exactly as a careless party does. The filter drops other Flares, which sit there rather than crowd.
	game_state.call("register_proximity_trigger", _trigger_id(), char_id, [],
		bunch_radius, bunch_count, Callable(self, "_on_bunched"),
		Callable(self, "_counts_as_crowd"))

func _counts_as_crowd(subject_id: String) -> bool:
	return not _flare_body_ids.has(subject_id)

func _trigger_id() -> String:
	return "flare_bunch_%s" % char_id

## The predicted crossing fired; GameState has already re-read the live count before calling.
func _on_bunched() -> void:
	if _state_name != "inert":
		return
	_prime(bodies_in_bunch_radius())

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
		if other_id == char_id or _flare_body_ids.has(other_id):
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
	# The swell is a known span, so the moment it ends is known the instant it starts. Scheduled AT
	# that tick -- nothing counts down and nothing samples.
	if sched != null:
		sched.cancel_tag(_burst_tag())
		sched.schedule_after(windup_delay, _burst, _burst_tag())
	primed.emit(trigger_ids)

func _burst_tag() -> String:
	return "flare_burst_%s" % char_id

## The burst reads the room at the moment it goes, never at the moment it was armed. That is what
## makes stepping out work and what makes it hit friend and foe without special-casing either: the
## party carry hp stats in GameState, enemy bodies carry their own, so both are paid.
func _burst() -> void:
	if game_state == null:
		return
	_state_name = "spent"
	_primed_at_tick = -1.0
	if game_state.has_method("unregister_proximity_trigger"):
		game_state.call("unregister_proximity_trigger", _trigger_id())
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
		# Neighbouring Flares are skipped rather than chipped. Chain detonation would be the
		# roster's "careless fire sets it off" half, which does not ship; half-implementing it as
		# quiet chip damage that silently kills a bed off would be worse than the stated gap.
		if node is Flare:
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
	_flare_body_ids.erase(char_id)
	if game_state != null and game_state.has_method("unregister_proximity_trigger"):
		game_state.call("unregister_proximity_trigger", _trigger_id())
	var sched = _get_scheduler()
	if sched != null:
		sched.cancel_tag(_burst_tag())
